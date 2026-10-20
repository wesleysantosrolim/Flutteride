import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'editor_autocomplete_file_logger.dart';

/// Cliente JSON-RPC/LSP usado pelo flutteride.
class DartLspClient {
  final List<String> _logBuffer = <String>[];

  DartLspClient({
    bool enableDebugLogs = false,
  }) : _enableDebugLogs = enableDebugLogs;

  Process? _process;

  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  StreamSubscription<void>? _exitSubscription;

  final List<int> _stdoutBuffer = [];
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};

  final StreamController<Map<String, dynamic>> _notificationsController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<String> _serverLogController =
      StreamController<String>.broadcast();

  final bool _enableDebugLogs;

  int _nextRequestId = 1;
  bool _started = false;
  bool _disposed = false;

  String? _rootfsPath;
  String? _ubuntuWorkingDirectory;

  static const MethodChannel _platform = MethodChannel(
    'com.flutteride.flutteride/native_path',
  );

  Stream<Map<String, dynamic>> get notifications =>
      _notificationsController.stream;

  Stream<String> get serverLogs async* {
    for (final log in _logBuffer) {
      yield log;
    }
    yield* _serverLogController.stream;
  }

  bool get isRunning => _started && !_disposed && _process != null;

  String? get ubuntuWorkingDirectory => _ubuntuWorkingDirectory;

  String? get rootfsPath => _rootfsPath;

  Future<void> start({
    String? dartExecutable,
    String? analysisServerSnapshot,
    String? workingDirectory,
    String? projectPath,
  }) async {
    if (_disposed) {
      throw StateError('DartLspClient já foi descartado.');
    }

    if (isRunning) {
      _addLog('Dart Analysis Server já está em execução.');
      return;
    }

    try {
      final appDir = await getApplicationSupportDirectory();

      final rootfsPath = p.join(
        appDir.path,
        'ubuntu_rootfs',
      );

      _rootfsPath = p.normalize(rootfsPath);

      final rootfsDir = Directory(rootfsPath);

      if (!await rootfsDir.exists()) {
        throw StateError(
          'Ubuntu rootfs não encontrado:\n$rootfsPath',
        );
      }

      final nativeLibDir = await _getNativeLibraryDir();

      final linksDir = await _ensureNativeLinks(
        appDir,
        nativeLibDir,
      );

      final prootExecutable = p.join(
        linksDir.path,
        'libproot.so',
      );

      final prootFile = File(prootExecutable);

      if (!await prootFile.exists()) {
        throw StateError(
          'PRoot não encontrado:\n$prootExecutable',
        );
      }

      const ubuntuDartExecutable = '/opt/flutter/bin/dart';

      const ubuntuAnalysisServerSnapshot =
          '/opt/flutter/bin/cache/dart-sdk/bin/snapshots/analysis_server.dart.snapshot';

      final dartFile = File(
        p.join(
          rootfsPath,
          ubuntuDartExecutable.substring(1),
        ),
      );

      if (!await dartFile.exists()) {
        throw StateError(
          'Executável Dart não encontrado dentro do Ubuntu:\n'
          '${dartFile.path}',
        );
      }

      final snapshotFile = File(
        p.join(
          rootfsPath,
          ubuntuAnalysisServerSnapshot.substring(1),
        ),
      );

      if (!await snapshotFile.exists()) {
        throw StateError(
          'Analysis Server não encontrado dentro do Ubuntu:\n'
          '${snapshotFile.path}',
        );
      }

      String ubuntuWorkingDirectory = '/root/projects';

      final requestedProject =
          projectPath != null && projectPath.trim().isNotEmpty
              ? projectPath
              : workingDirectory;

      if (requestedProject != null &&
          requestedProject.trim().isNotEmpty) {
        ubuntuWorkingDirectory =
            _convertProjectPathToUbuntuPath(
          requestedProject,
          rootfsPath,
        );
      }

      _ubuntuWorkingDirectory = ubuntuWorkingDirectory;

      _addLog(
        'Iniciando Dart Analysis Server...',
      );

      _addLog(
        'Ubuntu rootfs:\n$rootfsPath',
      );

      _addLog(
        'Projeto dentro do PRoot:\n$ubuntuWorkingDirectory',
      );

      final tmpDir = Directory(
        p.join(
          appDir.path,
          'tmp',
        ),
      );

      if (!await tmpDir.exists()) {
        await tmpDir.create(
          recursive: true,
        );
      }

      final bashCommand =
          'export DEBIAN_FRONTEND=noninteractive && '
          'mkdir -p /tmp /root/.pub-cache && '
          'chmod 1777 /tmp && '
          'export TMPDIR=/tmp && '
          'export PUB_CACHE=/root/.pub-cache && '
          'export HOME=/root && '
          'export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin" && '
          'exec $ubuntuDartExecutable '
          '$ubuntuAnalysisServerSnapshot --lsp';

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
        'PATH':
            '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin',
        'LD_LIBRARY_PATH':
            '${linksDir.path}:$nativeLibDir',
        'PROOT_LOADER':
            p.join(
          linksDir.path,
          'libproot_loader.so',
        ),
        'PROOT_NO_SECCOMP': '1',
        'TMPDIR': '/tmp',
        'PUB_CACHE': '/root/.pub-cache',
        'PROOT_TMP_DIR': tmpDir.path,
      };

      _stdoutBuffer.clear();

      final process = await Process.start(
        prootExecutable,
        arguments,
        environment: environment,
        runInShell: false,
      );

      _process = process;
      _started = true;

      _addLog(
        'Dart Analysis Server iniciado. PID: ${process.pid}',
      );

      _stdoutSubscription = process.stdout.listen(
        _handleStdout,
        onError: (error, stackTrace) {
          _addLog(
            'Analysis Server stdout error: $error',
          );
        },
        cancelOnError: false,
      );

      _stderrSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(
        (data) {
          if (data.isNotEmpty) {
            _addLog(
              '[stderr] $data',
            );
          }
        },
        onError: (error, stackTrace) {
          _addLog(
            'Analysis Server stderr error: $error',
          );
        },
        cancelOnError: false,
      );

      _exitSubscription = process.exitCode
          .then<void>((exitCode) {
            _handleProcessExit(exitCode);
          })
          .asStream()
          .listen((_) {});
    } catch (error, stackTrace) {
      _started = false;
      _process = null;

      _addLog(
        'ERRO ao iniciar Dart Analysis Server:\n$error',
      );

      debugPrint(
        'DartLspClient.start error: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      rethrow;
    }
  }

  String convertPathToServerPath(String path) {
    final rootfs = _rootfsPath;

    if (rootfs == null) {
      return p.normalize(path);
    }

    return _convertProjectPathToUbuntuPath(
      path,
      rootfs,
    );
  }

  Future<String> _getNativeLibraryDir() async {
    try {
      final nativeDir =
          await _platform.invokeMethod<String>(
        'getNativeLibDir',
      );

      if (nativeDir != null &&
          nativeDir.isNotEmpty) {
        return nativeDir;
      }
    } catch (e) {
      debugPrint(
        'Aviso: Falha ao obter nativeLibDir: $e',
      );
    }

    if (Platform.isAndroid) {
      return '/data/data/com.flutteride.flutteride/lib';
    }

    final appDir =
        await getApplicationSupportDirectory();

    return p.join(
      appDir.path,
      'bin',
    );
  }

  Future<Directory> _ensureNativeLinks(
    Directory appDir,
    String nativeLibDir,
  ) async {
    final linksDir = Directory(
      p.join(
        appDir.path,
        'lib_links',
      ),
    );

    if (!await linksDir.exists()) {
      await linksDir.create(
        recursive: true,
      );
    }

    final nativeDir = Directory(nativeLibDir);

    if (!await nativeDir.exists()) {
      throw StateError(
        'Diretório de bibliotecas nativas não encontrado:\n'
        '$nativeLibDir',
      );
    }

    for (final entity in nativeDir.listSync()) {
      if (entity is! File) continue;

      final fileName = p.basename(
        entity.path,
      );

      final linkPath = p.join(
        linksDir.path,
        fileName,
      );

      final link = Link(linkPath);

      try {
        if (await link.exists()) {
          await link.delete();
        }

        await link.create(
          entity.path,
        );
      } catch (e) {
        debugPrint(
          'Aviso ao criar link simbólico para '
          '$fileName: $e',
        );
      }
    }

    return linksDir;
  }

  String _convertProjectPathToUbuntuPath(
    String path,
    String rootfsPath,
  ) {
    final normalizedPath = p.normalize(path);
    final normalizedRootfs = p.normalize(rootfsPath);

    if (normalizedPath == normalizedRootfs) {
      return '/';
    }

    final prefix =
        '$normalizedRootfs${p.separator}';

    if (normalizedPath.startsWith(prefix)) {
      final relative =
          normalizedPath.substring(
        prefix.length,
      );

      return '/${relative.replaceAll('\\', '/')}';
    }

    if (normalizedPath.startsWith('/root/') ||
        normalizedPath.startsWith('/usr/') ||
        normalizedPath.startsWith('/tmp/') ||
        normalizedPath.startsWith('/home/')) {
      return normalizedPath.replaceAll(
        '\\',
        '/',
      );
    }

    return '/root/projects';
  }

  Future<Map<String, dynamic>> sendRequest(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (!isRunning) {
      throw StateError(
        'O Dart Analysis Server não está em execução.',
      );
    }

    final id = _nextRequestId++;

    final completer =
        Completer<Map<String, dynamic>>();

    _pendingRequests[id] = completer;

    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null)
        'params': params,
    };

    _debug(
      'CLIENT → SERVER REQUEST #$id $method\n'
      '${jsonEncode(message)}',
    );

    try {
      await _writeMessage(message);
    } catch (error, stackTrace) {
      _pendingRequests.remove(id);

      if (!completer.isCompleted) {
        completer.completeError(
          error,
          stackTrace,
        );
      }
    }

    return completer.future;
  }

  Future<void> sendNotification(
    String method, [
    Map<String, dynamic>? params,
  ]) async {
    if (!isRunning) {
      throw StateError(
        'O Dart Analysis Server não está em execução.',
      );
    }

    final message = <String, dynamic>{
      'jsonrpc': '2.0',
      'method': method,
      if (params != null)
        'params': params,
    };

    _debug(
      'CLIENT → SERVER NOTIFICATION $method\n'
      '${jsonEncode(message)}',
    );

    await _writeMessage(message);
  }

  Future<void> _writeMessage(
    Map<String, dynamic> message,
  ) async {
    final process = _process;

    if (process == null) {
      throw StateError(
        'Processo do Analysis Server não disponível.',
      );
    }

    final body = utf8.encode(
      jsonEncode(message),
    );

    final header = utf8.encode(
      'Content-Length: ${body.length}\r\n\r\n',
    );

    process.stdin.add(header);
    process.stdin.add(body);

    await process.stdin.flush();
  }

  void _handleStdout(List<int> data) {
    _stdoutBuffer.addAll(data);

    while (true) {
      final message = _tryReadMessage();

      if (message == null) {
        break;
      }

      final encodedMessage = jsonEncode(message);

      _debug(
        'SERVER → CLIENT\n$encodedMessage',
      );

      _handleMessage(message);
    }
  }

  Map<String, dynamic>? _tryReadMessage() {
    final separator = _findHeaderSeparator();

    if (separator == -1) {
      return null;
    }

    final headerBytes =
        _stdoutBuffer.sublist(
      0,
      separator,
    );

    final headerText = utf8.decode(
      headerBytes,
      allowMalformed: true,
    );

    int? contentLength;

    for (final line in headerText.split('\r\n')) {
      final index = line.indexOf(':');

      if (index == -1) {
        continue;
      }

      final name = line
          .substring(0, index)
          .trim()
          .toLowerCase();

      final value = line
          .substring(index + 1)
          .trim();

      if (name == 'content-length') {
        contentLength = int.tryParse(value);
      }
    }

    if (contentLength == null) {
      _stdoutBuffer.removeRange(
        0,
        separator + 4,
      );

      _debug(
        'SERVER → CLIENT mensagem descartada: '
        'Content-Length ausente.',
      );

      return null;
    }

    final bodyStart = separator + 4;

    final totalLength =
        bodyStart + contentLength;

    if (_stdoutBuffer.length < totalLength) {
      return null;
    }

    final bodyBytes =
        _stdoutBuffer.sublist(
      bodyStart,
      totalLength,
    );

    _stdoutBuffer.removeRange(
      0,
      totalLength,
    );

    try {
      final body = utf8.decode(
        bodyBytes,
        allowMalformed: true,
      );

      final decoded = jsonDecode(body);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded,
        );
      }
    } catch (error) {
      _addLog(
        'LSP: erro ao decodificar mensagem: $error',
      );
    }

    return null;
  }

  int _findHeaderSeparator() {
    for (
      var i = 0;
      i < _stdoutBuffer.length - 3;
      i++
    ) {
      if (_stdoutBuffer[i] == 13 &&
          _stdoutBuffer[i + 1] == 10 &&
          _stdoutBuffer[i + 2] == 13 &&
          _stdoutBuffer[i + 3] == 10) {
        return i;
      }
    }

    return -1;
  }

  void _handleMessage(
    Map<String, dynamic> message,
  ) {
    final id = message['id'];
    final method = message['method'];

    if (id != null) {
      final numericId =
          id is int
              ? id
              : int.tryParse(
                  id.toString(),
                );

      if (numericId != null) {
        final completer =
            _pendingRequests.remove(
          numericId,
        );

        if (completer != null &&
            !completer.isCompleted) {
          _debug(
            'CLIENT recebeu resposta para '
            'REQUEST #$numericId'
            '${method is String ? ' ($method)' : ''}.',
          );

          if (message.containsKey('error')) {
            final error = message['error'];

            _debug(
              'CLIENT recebeu ERROR para '
              'REQUEST #$numericId:\n'
              '${jsonEncode(error)}',
            );

            completer.completeError(
              DartLspException(
                code: error is Map
                    ? _toNullableInt(
                        error['code'],
                      )
                    : null,
                message: error is Map
                    ? error['message']?.toString()
                    : 'Erro LSP',
                data: error is Map
                    ? error['data']
                    : null,
              ),
            );
          } else {
            _debug(
              'CLIENT completando REQUEST #$numericId '
              'com resultado:\n'
              '${jsonEncode(message)}',
            );

            completer.complete(message);
          }

          return;
        }

        _debug(
          'SERVER enviou mensagem com ID '
          '$numericId, mas não existe request pendente.',
        );
      }
    }

    if (method is String && id != null) {
      _debug(
        'SERVER REQUEST → CLIENT '
        '#$id $method\n'
        '${jsonEncode(message)}',
      );

      _handleServerRequest(
        id,
        method,
        message['params'],
      );

      return;
    }

    if (method is String) {
      _debug(
        'SERVER NOTIFICATION: $method\n'
        '${jsonEncode(message)}',
      );

      if (!_notificationsController.isClosed) {
        _notificationsController.add(
          message,
        );
      }
    }
  }

  Future<void> _handleServerRequest(
    dynamic id,
    String method,
    dynamic params,
  ) async {
    dynamic result;

    switch (method) {
      case 'workspace/configuration':
        final items = params is Map && params['items'] is List
            ? params['items'] as List
            : <dynamic>[];

        result = items.map<dynamic>((item) {
          if (item is! Map) {
            return null;
          }

          final section = item['section'] as String?;

          if (section == null || section.isEmpty || section == 'dart') {
            return <String, dynamic>{
              'analysisServer': <String, dynamic>{
                'enabled': true,
              },
              'completeFunctionCalls': true,
            };
          }

          if (section == 'dart.completeFunctionCalls') {
            return true;
          }

          if (section == 'dart.analysisServer') {
            return <String, dynamic>{
              'enabled': true,
            };
          }

          if (section == 'dart.analysisServer.enabled') {
            return true;
          }

          return null;
        }).toList();

        break;

      case 'workspace/workspaceFolders':
        final workspace =
            _ubuntuWorkingDirectory;

        result = workspace == null
            ? <dynamic>[]
            : <Map<String, dynamic>>[
                <String, dynamic>{
                  'uri': Uri.file(
                    workspace,
                  ).toString(),
                  'name': p.basename(
                    workspace,
                  ),
                },
              ];

        break;

      case 'client/registerCapability':
      case 'client/unregisterCapability':
      case 'window/workDoneProgress/create':
      default:
        result = <String, dynamic>{};
        break;
    }

    final response = <String, dynamic>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };

    _debug(
      'CLIENT → SERVER RESPONSE #$id $method\n'
      '${jsonEncode(response)}',
    );

    try {
      await _writeMessage(
        response,
      );
    } catch (error) {
      _addLog(
        'Erro ao responder request $method: $error',
      );
    }
  }

  void _handleProcessExit(int exitCode) {
    _started = false;

    _addLog(
      'Dart Analysis Server finalizado. '
      'Exit code: $exitCode',
    );

    final exception = DartLspException(
      message:
          'Dart Analysis Server finalizado '
          'com código $exitCode.',
    );

    for (final completer
        in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          exception,
        );
      }
    }

    _pendingRequests.clear();
    _process = null;
  }

  Future<void> stop() async {
    final process = _process;

    if (process == null) {
      _started = false;
      return;
    }

    _addLog(
      'Solicitando parada do Analysis Server...',
    );

    try {
      process.kill(
        ProcessSignal.sigterm,
      );
    } catch (_) {}

    try {
      await process.exitCode.timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      try {
        process.kill(
          ProcessSignal.sigkill,
        );
      } catch (_) {}
    }

    _process = null;
    _started = false;
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    await stop();

    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    await _exitSubscription?.cancel();

    _stdoutSubscription = null;
    _stderrSubscription = null;
    _exitSubscription = null;

    for (final completer
        in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            'DartLspClient foi descartado.',
          ),
        );
      }
    }

    _pendingRequests.clear();

    await _notificationsController.close();
    await _serverLogController.close();
  }

  void _debug(String message) {
    if (!_enableDebugLogs) {
      return;
    }

    _addLog(
      '[LSP] $message',
    );
  }

  void _addLog(String message) {
    if (_serverLogController.isClosed) {
      return;
    }

    final now = DateTime.now();

    final timestamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}.'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final formattedMessage =
        '[$timestamp] $message';

    _serverLogController.add(
      formattedMessage,
    );

    _logBuffer.add(
      message,
    );

    if (_logBuffer.length > 500) {
      _logBuffer.removeAt(0);
    }

    unawaited(
      EditorAutocompleteFileLogger.log(
        formattedMessage,
      ),
    );
  }

  static int? _toNullableInt(dynamic value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    );
  }
}

class DartLspException implements Exception {
  final int? code;
  final String? message;
  final dynamic data;

  const DartLspException({
    this.code,
    this.message,
    this.data,
  });

  @override
  String toString() =>
      'DartLspException('
      'code: $code, '
      'message: $message, '
      'data: $data'
      ')';
}