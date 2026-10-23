import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'native_lsp_logger.dart';

/// Cria um transporte LSP entre o Monaco e o Dart Analysis Server
/// executado dentro do Ubuntu/PRoot.
class NativeLspTransportService {
  NativeLspTransportService._();

  static Future<LspBridgedTransport> createTransport({
    String? projectPath,
  }) async {
    final server = await _NativeLspProcess.start(
      projectPath: projectPath,
    );

    return server.transport;
  }
}

/// Processo PRoot que executa o Dart Analysis Server.
class _NativeLspProcess {
  _NativeLspProcess._({
    required Process process,
    required String executable,
    required List<String> arguments,
  })  : _process = process,
        _executable = executable,
        _arguments = List<String>.unmodifiable(arguments) {
    _stdoutSubscription = _process.stdout.listen(
      _handleStdout,
      onError: (Object error, StackTrace stackTrace) {
        _fail(error, stackTrace);
      },
      onDone: _handleStdoutDone,
      cancelOnError: false,
    );

    _stderrSubscription = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
      (line) {
        NativeLspLogger.warning(
          'server.stderr',
          details: line,
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        NativeLspLogger.error(
          'server.stderr.read_failed',
          exception: error,
          stackTrace: stackTrace,
        );
      },
      cancelOnError: false,
    );

    _exitFuture = _process.exitCode.then<void>(
      (code) {
        _handleExitCode(code);
      },
      onError: (Object error, StackTrace stackTrace) {
        _fail(error, stackTrace);
      },
    );

    transport = LspBridgedTransport(
      fromServer: _fromServer.stream,
      toServer: _handleClientMessage,
      onClose: stop,
    );
  }

  static const MethodChannel _platform = MethodChannel(
    'com.flutteride.flutteride/native_path',
  );

  final Process _process;
  final String _executable;
  final List<String> _arguments;

  final StreamController<Map<String, Object?>> _fromServer =
      StreamController<Map<String, Object?>>();

  final LspStdioMessageDecoder _decoder = LspStdioMessageDecoder();

  late final LspBridgedTransport transport;

  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  late final Future<void> _exitFuture;

  bool _stopped = false;
  bool _stdoutFinished = false;
  bool _streamClosed = false;

  static Future<_NativeLspProcess> start({
    String? projectPath,
  }) async {
    await NativeLspLogger.info(
      'transport.start.begin',
      details: 'Preparing Ubuntu/PRoot process.',
    );

    final appDir = await getApplicationSupportDirectory();

    final rootfsPath = p.normalize(
      p.join(appDir.path, 'ubuntu_rootfs'),
    );

    final rootfsDir = Directory(rootfsPath);

    if (!await rootfsDir.exists()) {
      throw StateError(
        'Ubuntu rootfs nao encontrado: $rootfsPath',
      );
    }

    final nativeLibDir = await _getNativeLibraryDir(appDir);
    final linksDir = await _ensureNativeLinks(appDir, nativeLibDir);

    final prootExecutable = p.join(
      linksDir.path,
      'libproot.so',
    );

    if (!await File(prootExecutable).exists()) {
      throw StateError(
        'Executavel PRoot nao encontrado: $prootExecutable',
      );
    }

    const dartExecutable = '/opt/flutter/bin/dart';
    const analysisServerSnapshot =
        '/opt/flutter/bin/cache/dart-sdk/bin/snapshots/analysis_server.dart.snapshot';

    final dartFile = File(
      p.join(
        rootfsPath,
        dartExecutable.substring(1),
      ),
    );

    if (!await dartFile.exists()) {
      throw StateError(
        'Executavel Dart nao encontrado: ${dartFile.path}',
      );
    }

    final snapshotFile = File(
      p.join(
        rootfsPath,
        analysisServerSnapshot.substring(1),
      ),
    );

    if (!await snapshotFile.exists()) {
      throw StateError(
        'Analysis Server nao encontrado: ${snapshotFile.path}',
      );
    }

    final ubuntuWorkingDirectory = _convertProjectPath(
      projectPath,
      rootfsPath,
    );

    final tmpDir = Directory(
      p.join(appDir.path, 'tmp'),
    );

    if (!await tmpDir.exists()) {
      await tmpDir.create(recursive: true);
    }

    const pathValue =
        '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin';

    final bashCommand =
        'export DEBIAN_FRONTEND=noninteractive && '
        'mkdir -p /tmp /root/.pub-cache && '
        'chmod 1777 /tmp && '
        'export TMPDIR=/tmp && '
        'export PUB_CACHE=/root/.pub-cache && '
        'export HOME=/root && '
        'export PATH="$pathValue" && '
        'exec $dartExecutable $analysisServerSnapshot --lsp';

    final arguments = <String>[
      '-r',
      rootfsPath,
      '-0',
      '-b',
      '/dev',
      '-b',
      '/proc',
      '-b',
      '/sys',
      '-b',
      '${tmpDir.path}:/tmp',
      '-w',
      ubuntuWorkingDirectory,
      '/bin/bash',
      '-c',
      bashCommand,
    ];

    final environment = <String, String>{
      'HOME': '/root',
      'PATH': pathValue,
      'LD_LIBRARY_PATH': '${linksDir.path}:$nativeLibDir',
      'PROOT_LOADER': p.join(
        linksDir.path,
        'libproot_loader.so',
      ),
      'PROOT_NO_SECCOMP': '1',
      'TMPDIR': '/tmp',
      'PUB_CACHE': '/root/.pub-cache',
      'PROOT_TMP_DIR': tmpDir.path,
    };

    await NativeLspLogger.info(
      'transport.process.launch',
      details: 'rootfs=$rootfsPath; '
          'workspace=$ubuntuWorkingDirectory; '
          'executable=$prootExecutable',
    );

    final process = await Process.start(
      prootExecutable,
      arguments,
      environment: environment,
      runInShell: false,
    );

    await NativeLspLogger.info(
      'transport.process.started',
      details: 'pid=${process.pid}',
    );

    return _NativeLspProcess._(
      process: process,
      executable: prootExecutable,
      arguments: arguments,
    );
  }

  static Future<String> _getNativeLibraryDir(
    Directory appDir,
  ) async {
    try {
      final nativeDir = await _platform.invokeMethod<String>(
        'getNativeLibDir',
      );

      if (nativeDir != null && nativeDir.isNotEmpty) {
        return nativeDir;
      }
    } catch (error) {
      await NativeLspLogger.warning(
        'transport.native_lib_dir.channel_failed',
        details: error,
      );
    }

    if (Platform.isAndroid) {
      return '/data/data/com.flutteride.flutteride/lib';
    }

    return p.join(appDir.path, 'bin');
  }

  static Future<Directory> _ensureNativeLinks(
    Directory appDir,
    String nativeLibDir,
  ) async {
    final linksDir = Directory(
      p.join(appDir.path, 'lib_links'),
    );

    if (!await linksDir.exists()) {
      await linksDir.create(recursive: true);
    }

    final nativeDir = Directory(nativeLibDir);

    if (!await nativeDir.exists()) {
      throw StateError(
        'Diretorio de bibliotecas nativas nao encontrado: $nativeLibDir',
      );
    }

    await for (final entity in nativeDir.list()) {
      if (entity is! File) continue;

      final fileName = p.basename(entity.path);
      final link = Link(p.join(linksDir.path, fileName));

      try {
        if (await link.exists()) {
          await link.delete();
        }

        await link.create(entity.path);
      } catch (error) {
        await NativeLspLogger.warning(
          'transport.native_link.failed',
          details: '$fileName: $error',
        );
      }
    }

    return linksDir;
  }

  static String _convertProjectPath(
    String? projectPath,
    String rootfsPath,
  ) {
    if (projectPath == null || projectPath.trim().isEmpty) {
      return '/root/projects';
    }

    final normalizedPath = p.normalize(projectPath.trim());
    final normalizedRootfs = p.normalize(rootfsPath);

    if (normalizedPath == normalizedRootfs) {
      return '/';
    }

    final rootfsPrefix = '$normalizedRootfs${p.separator}';

    if (normalizedPath.startsWith(rootfsPrefix)) {
      final relativePath = normalizedPath.substring(rootfsPrefix.length);
      return '/${relativePath.replaceAll('\\', '/')}';
    }

    if (normalizedPath.startsWith('/root/') ||
        normalizedPath.startsWith('/usr/') ||
        normalizedPath.startsWith('/tmp/') ||
        normalizedPath.startsWith('/home/')) {
      return normalizedPath.replaceAll('\\', '/');
    }

    return '/root/projects';
  }

  void _handleStdout(List<int> bytes) {
    if (_stopped || _streamClosed) return;

    try {
      final messages = _decoder.addBytes(bytes);

      for (final message in messages) {
        if (_stopped || _streamClosed) break;

        final jsonMessage = jsonEncode(message);
        final method = message['method'];
        final id = message['id'];

        unawaited(
          NativeLspLogger.info(
            'transport.server.message',
            details: 'method=${method ?? "(response)"}; '
                'id=${id ?? "(notification)"}; '
                'bytes=${utf8.encode(jsonMessage).length}',
          ),
        );

        _fromServer.add(Map<String, Object?>.from(message));
      }
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _handleClientMessage(Map<String, Object?> message) {
    if (_stopped || _streamClosed) return;

    final method = message['method'];
    final id = message['id'];

    unawaited(
      NativeLspLogger.info(
        'transport.client.message',
        details: 'method=${method ?? "(response)"}; '
            'id=${id ?? "(notification)"}',
      ),
    );

    unawaited(_writeMessage(message));
  }

  Future<void> _writeMessage(Map<String, Object?> message) async {
    if (_stopped) return;

    try {
      final bytes = LspStdioMessageEncoder.encode(message);
      _process.stdin.add(bytes);
      await _process.stdin.flush();
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _handleStdoutDone() {
    _stdoutFinished = true;
    if (_stopped || _streamClosed) return;

    unawaited(
      NativeLspLogger.warning(
        'transport.stdout.closed',
        details: 'Analysis Server stdout stream closed.',
      ),
    );

    unawaited(_closeStream());
  }

  void _handleExitCode(int code) {
    if (_stopped) return;

    unawaited(
      NativeLspLogger.info(
        'transport.process.exit',
        details: 'exitCode=$code',
      ),
    );

    if (code != 0) {
      _fail(
        ProcessException(
          _executable,
          _arguments,
          'Dart Analysis Server encerrou com codigo $code.',
          code,
        ),
        StackTrace.current,
      );
      return;
    }

    unawaited(_closeStream());
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_stopped || _streamClosed) return;

    unawaited(
      NativeLspLogger.error(
        'transport.failure',
        exception: error,
        stackTrace: stackTrace,
      ),
    );

    if (!_fromServer.isClosed) {
      _fromServer.addError(error, stackTrace);
    }

    unawaited(_closeStream());
  }

  Future<void> _closeStream() async {
    if (_streamClosed) return;
    _streamClosed = true;

    if (!_fromServer.isClosed) {
      await _fromServer.close();
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;

    await NativeLspLogger.info(
      'transport.stop',
      details: 'Stopping native LSP process.',
    );

    try {
      await _stdoutSubscription?.cancel();
    } catch (_) {}

    try {
      await _stderrSubscription?.cancel();
    } catch (_) {}

    try {
      _process.stdin.close();
    } catch (_) {}

    try {
      _process.kill();
    } catch (_) {}

    try {
      await _exitFuture.timeout(const Duration(seconds: 2));
    } catch (_) {}

    await _closeStream();
  }
}
