import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:terminal_view/terminal_view.dart';

import '../models/ubuntu_session.dart';

class UbuntuSessionManager {
  UbuntuSessionManager._();

  static final UbuntuSessionManager instance =
      UbuntuSessionManager._();

  static const MethodChannel _platform =
      MethodChannel(
    'com.flutteride.flutteride/native_path',
  );

  final Set<UbuntuSession> _sessions =
      <UbuntuSession>{};

  // ============================================================
  // TERMINAL PERSISTENTE
  // ============================================================

  /// Terminal visual compartilhado entre todas as instâncias
  /// de TerminalScreen.
  ///
  /// Isso permite que o histórico continue existindo quando
  /// TerminalScreen é destruída ao voltar para a HomeScreen.
  final Terminal terminal =
      Terminal(
    maxLines: 10000,
  );

  UbuntuSession? _terminalSession;

  StreamSubscription<List<int>>?
      _terminalOutputSubscription;

  int get activeSessionCount =>
      _sessions.length;

  bool get hasTerminalSession {
    final session =
        _terminalSession;

    return session != null &&
        !session.isClosed;
  }

  UbuntuSession? get terminalSession =>
      _terminalSession;

  // ============================================================
  // DIRETÓRIOS
  // ============================================================

  Future<Directory> _getApplicationDirectory() async {
    return getApplicationSupportDirectory();
  }

  Future<String> getRootfsPath() async {
    final appDir =
        await _getApplicationDirectory();

    return p.join(
      appDir.path,
      'ubuntu_rootfs',
    );
  }

  Future<String> _getNativeLibraryDirectory() async {
    try {
      final nativeDir =
          await _platform.invokeMethod<String>(
        'getNativeLibDir',
      );

      if (nativeDir != null &&
          nativeDir.trim().isNotEmpty) {
        return nativeDir;
      }
    } on PlatformException catch (e) {
      debugPrint(
        '[UbuntuSessionManager] Falha ao obter diretório '
        'nativo pelo MethodChannel: $e',
      );
    } catch (e) {
      debugPrint(
        '[UbuntuSessionManager] Erro obtendo diretório nativo: $e',
      );
    }

    final appDir =
        await _getApplicationDirectory();

    return p.join(
      appDir.path,
      'bin',
    );
  }

  // ============================================================
  // PREPARAÇÃO DO AMBIENTE
  // ============================================================

  Future<void> prepareEnvironment() async {
    final stopwatch =
        Stopwatch()..start();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'prepareEnvironment: INÍCIO',
    );

    final rootfsPath =
        await getRootfsPath();

    final rootfsDirectory =
        Directory(rootfsPath);

    if (!await rootfsDirectory.exists()) {
      throw StateError(
        'Ubuntu rootfs não encontrado:\n'
        '$rootfsPath',
      );
    }

    try {
      final resolvConf = File(
        p.join(
          rootfsPath,
          'etc',
          'resolv.conf',
        ),
      );

      if (!await resolvConf.exists() ||
          (await resolvConf.readAsString())
              .trim()
              .isEmpty) {
        await resolvConf.writeAsString(
          'nameserver 8.8.8.8\n'
          'nameserver 1.1.1.1\n',
          mode: FileMode.write,
        );
      }

      final bashrc = File(
        p.join(
          rootfsPath,
          'root',
          '.bashrc',
        ),
      );

      if (await bashrc.exists()) {
        final content =
            await bashrc.readAsString();

        if (!content.contains(
          'alias sdcard=',
        )) {
          await bashrc.writeAsString(
            '\n'
            "alias ls='ls --color=auto'\n"
            "alias ll='ls -la'\n"
            "alias sdcard='cd /sdcard'\n"
            "export PS1='\\u@ubuntu:\\w\\\$ '\n",
            mode: FileMode.append,
          );
        }
      }

      final sdcardMountPoint =
          Directory(
        p.join(
          rootfsPath,
          'sdcard',
        ),
      );

      if (!await sdcardMountPoint.exists()) {
        await sdcardMountPoint.create(
          recursive: true,
        );
      }

      final tmpRootfs =
          Directory(
        p.join(
          rootfsPath,
          'tmp',
        ),
      );

      if (!await tmpRootfs.exists()) {
        await tmpRootfs.create(
          recursive: true,
        );
      }

      try {
        await Process.run(
          'chmod',
          [
            '1777',
            tmpRootfs.path,
          ],
        );
      } catch (e) {
        debugPrint(
          '[UbuntuSessionManager] Aviso ao configurar /tmp: $e',
        );
      }

      await _prepareGradleConfiguration(
        rootfsPath,
      );
    } catch (e) {
      debugPrint(
        '[UbuntuSessionManager] Erro preparando ambiente: $e',
      );
    }

    stopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'prepareEnvironment: FIM '
      '(${stopwatch.elapsedMilliseconds} ms)',
    );
  }

  // ============================================================
  // CONFIGURAÇÃO GLOBAL DO GRADLE
  // ============================================================

  /// Configura o Gradle global do Ubuntu para utilizar o AAPT2
  /// nativo ARM64 disponível no Android SDK.
  ///
  /// Isso é feito no rootfs do Ubuntu para que todos os projetos
  /// Flutter compilados pelo flutteride utilizem a mesma
  /// configuração, sem precisar alterar cada projeto individual.
  Future<void> _prepareGradleConfiguration(
    String rootfsPath,
  ) async {
    final stopwatch =
        Stopwatch()..start();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_prepareGradleConfiguration: INÍCIO',
    );

    final gradleDirectory =
        Directory(
      p.join(
        rootfsPath,
        'root',
        '.gradle',
      ),
    );

    if (!await gradleDirectory.exists()) {
      await gradleDirectory.create(
        recursive: true,
      );
    }

    final gradleProperties =
        File(
      p.join(
        gradleDirectory.path,
        'gradle.properties',
      ),
    );

    const property =
        'android.aapt2FromMavenOverride='
        '/opt/android_sdk/build-tools/35.0.1/aapt2';

    var content = '';

    if (await gradleProperties.exists()) {
      content =
          await gradleProperties.readAsString();
    }

    final lines =
        content.split('\n');

    var found = false;

    final updatedLines =
        lines.map((line) {
      if (line.trimLeft().startsWith(
            'android.aapt2FromMavenOverride=',
          )) {
        found = true;
        return property;
      }

      return line;
    }).toList();

    if (!found) {
      if (updatedLines.isNotEmpty &&
          updatedLines.last.trim().isNotEmpty) {
        updatedLines.add('');
      }

      updatedLines.add(
        property,
      );
    }

    await gradleProperties.writeAsString(
      updatedLines.join('\n'),
    );

    debugPrint(
      '[UbuntuSessionManager] AAPT2 ARM64 configurado no Gradle global.',
    );

    debugPrint(
      '[UbuntuSessionManager] AAPT2: '
      '/opt/android_sdk/build-tools/35.0.1/aapt2',
    );

    stopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_prepareGradleConfiguration: FIM '
      '(${stopwatch.elapsedMilliseconds} ms)',
    );
  }

  // ============================================================
  // PROOT
  // ============================================================

  Future<String> _resolveProotPath() async {
    final stopwatch =
        Stopwatch()..start();

    final appDir =
        await _getApplicationDirectory();

    final nativeLibDir =
        await _getNativeLibraryDirectory();

    final nativeProot =
        File(
      p.join(
        nativeLibDir,
        'libproot.so',
      ),
    );

    if (await nativeProot.exists()) {
      stopwatch.stop();

      debugPrint(
        '[UbuntuSessionManager][TIMING] '
        '_resolveProotPath: '
        '${stopwatch.elapsedMilliseconds} ms',
      );

      return nativeProot.path;
    }

    final fallbackProot =
        File(
      p.join(
        appDir.path,
        'bin',
        'proot',
      ),
    );

    if (await fallbackProot.exists()) {
      stopwatch.stop();

      debugPrint(
        '[UbuntuSessionManager][TIMING] '
        '_resolveProotPath: '
        '${stopwatch.elapsedMilliseconds} ms',
      );

      return fallbackProot.path;
    }

    throw StateError(
      'PRoot não encontrado.\n'
      'Tentativas:\n'
      '${nativeProot.path}\n'
      '${fallbackProot.path}',
    );
  }

  // ============================================================
  // BIBLIOTECAS
  // ============================================================

  Future<String> _prepareLinksDirectory(
    String nativeLibDir,
  ) async {
    final stopwatch =
        Stopwatch()..start();

    final appDir =
        await _getApplicationDirectory();

    final linksDir =
        Directory(
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

    final tallocOriginal =
        File(
      p.join(
        nativeLibDir,
        'libtalloc.so',
      ),
    );

    final tallocOriginalV2 =
        File(
      p.join(
        nativeLibDir,
        'libtalloc.so.2',
      ),
    );

    final tallocTarget =
        File(
      p.join(
        linksDir.path,
        'libtalloc.so.2',
      ),
    );

    if (!await tallocTarget.exists()) {
      if (await tallocOriginal.exists()) {
        try {
          await Link(
            tallocTarget.path,
          ).create(
            tallocOriginal.path,
          );
        } catch (_) {
          try {
            await tallocOriginal.copy(
              tallocTarget.path,
            );
          } catch (e) {
            debugPrint(
              '[UbuntuSessionManager] Não foi possível criar '
              'libtalloc.so.2: $e',
            );
          }
        }
      } else if (await tallocOriginalV2.exists()) {
        try {
          await tallocOriginalV2.copy(
            tallocTarget.path,
          );
        } catch (e) {
          debugPrint(
            '[UbuntuSessionManager] Não foi possível copiar '
            'libtalloc.so.2: $e',
          );
        }
      }
    }

    stopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_prepareLinksDirectory: '
      '${stopwatch.elapsedMilliseconds} ms',
    );

    return linksDir.path;
  }

  Future<Directory> _prepareTmpDirectory() async {
    final stopwatch =
        Stopwatch()..start();

    final appDir =
        await _getApplicationDirectory();

    final tmpDir =
        Directory(
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

    stopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_prepareTmpDirectory: '
      '${stopwatch.elapsedMilliseconds} ms',
    );

    return tmpDir;
  }

  Future<String> _resolveBashPath(
    String rootfsPath,
  ) async {
    final stopwatch =
        Stopwatch()..start();

    final bashInBin =
        File(
      p.join(
        rootfsPath,
        'bin',
        'bash',
      ),
    );

    if (await bashInBin.exists()) {
      stopwatch.stop();

      debugPrint(
        '[UbuntuSessionManager][TIMING] '
        '_resolveBashPath: '
        '${stopwatch.elapsedMilliseconds} ms',
      );

      return '/bin/bash';
    }

    final bashInUsrBin =
        File(
      p.join(
        rootfsPath,
        'usr',
        'bin',
        'bash',
      ),
    );

    if (await bashInUsrBin.exists()) {
      stopwatch.stop();

      debugPrint(
        '[UbuntuSessionManager][TIMING] '
        '_resolveBashPath: '
        '${stopwatch.elapsedMilliseconds} ms',
      );

      return '/usr/bin/bash';
    }

    throw StateError(
      'Bash não encontrado no Ubuntu rootfs.\n'
      'Procurado:\n'
      '${bashInBin.path}\n'
      '${bashInUsrBin.path}',
    );
  }

  // ============================================================
  // CRIAÇÃO DE SESSÕES
  // ============================================================

  Future<UbuntuSession> createSession({
    String workingDirectory = '/root',
    String? command,
    List<String> arguments =
        const <String>[],
    bool loginShell = true,
  }) async {
    final totalStopwatch =
        Stopwatch()..start();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'createSession: INÍCIO',
    );

    final prepareStopwatch =
        Stopwatch()..start();

    await prepareEnvironment();

    prepareStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'createSession → prepareEnvironment: '
      '${prepareStopwatch.elapsedMilliseconds} ms',
    );

    final rootfsStopwatch =
        Stopwatch()..start();

    final rootfsPath =
        await getRootfsPath();

    rootfsStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'getRootfsPath: '
      '${rootfsStopwatch.elapsedMilliseconds} ms',
    );

    final nativeLibStopwatch =
        Stopwatch()..start();

    final nativeLibDir =
        await _getNativeLibraryDirectory();

    nativeLibStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_getNativeLibraryDirectory: '
      '${nativeLibStopwatch.elapsedMilliseconds} ms',
    );

    final prootStopwatch =
        Stopwatch()..start();

    final prootPath =
        await _resolveProotPath();

    prootStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_resolveProotPath total: '
      '${prootStopwatch.elapsedMilliseconds} ms',
    );

    final linksStopwatch =
        Stopwatch()..start();

    final linksDir =
        await _prepareLinksDirectory(
      nativeLibDir,
    );

    linksStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_prepareLinksDirectory total: '
      '${linksStopwatch.elapsedMilliseconds} ms',
    );

    final tmpStopwatch =
        Stopwatch()..start();

    final tmpDir =
        await _prepareTmpDirectory();

    tmpStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_prepareTmpDirectory total: '
      '${tmpStopwatch.elapsedMilliseconds} ms',
    );

    final bashStopwatch =
        Stopwatch()..start();

    final bashPath =
        await _resolveBashPath(
      rootfsPath,
    );

    bashStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      '_resolveBashPath total: '
      '${bashStopwatch.elapsedMilliseconds} ms',
    );

    final executable =
        command ?? bashPath;

    final prootArgs =
        <String>[
      '--kill-on-exit',
      '--link2symlink',
      '-0',
      '-r',
      rootfsPath,
      '-b',
      '/dev',
      '-b',
      '/proc',
      '-b',
      '/sys',
      '-b',
      '/sdcard:/sdcard',
      '-b',
      '/storage/emulated/0:/storage/emulated/0',
      '-w',
      workingDirectory,
      executable,
    ];

    if (loginShell &&
        executable == bashPath) {
      prootArgs.add(
        '--login',
      );
    }

    if (arguments.isNotEmpty) {
      prootArgs.addAll(
        arguments,
      );
    }

    final environment =
        <String, String>{
      'TERM': 'xterm-256color',
      'HOME': '/root',
      'TMPDIR': '/tmp',
      'TMP': '/tmp',
      'TEMP': '/tmp',
      'PATH':
          '/usr/local/sbin:'
          '/usr/local/bin:'
          '/usr/sbin:'
          '/usr/bin:'
          '/sbin:'
          '/bin',
      'LD_LIBRARY_PATH':
          '$linksDir:$nativeLibDir',
      'PROOT_LOADER':
          p.join(
        nativeLibDir,
        'libproot_loader.so',
      ),
      'PROOT_NO_SECCOMP': '1',
      'PROOT_TMP_DIR':
          tmpDir.path,
    };

    debugPrint(
      '[UbuntuSessionManager] Criando sessão.',
    );

    debugPrint(
      '[UbuntuSessionManager] Rootfs: $rootfsPath',
    );

    debugPrint(
      '[UbuntuSessionManager] PRoot: $prootPath',
    );

    debugPrint(
      '[UbuntuSessionManager] Bash: $bashPath',
    );

    debugPrint(
      '[UbuntuSessionManager] Working directory: '
      '$workingDirectory',
    );

    final ptyStopwatch =
        Stopwatch()..start();

    final pty =
        Pty.start(
      prootPath,
      arguments: prootArgs,
      environment: environment,
    );

    ptyStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'Pty.start: '
      '${ptyStopwatch.elapsedMilliseconds} ms',
    );

    final session =
        UbuntuSession(
      pty: pty,
      rootfsPath: rootfsPath,
    );

    _sessions.add(session);

    unawaited(
      _watchSession(session),
    );

    totalStopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'createSession: FIM '
      '(${totalStopwatch.elapsedMilliseconds} ms)',
    );

    return session;
  }

  Future<UbuntuSession>
      createTerminalSession({
    bool forceNew = false,
  }) async {
    if (!forceNew &&
        hasTerminalSession) {
      debugPrint(
        '[UbuntuSessionManager] Reutilizando sessão '
        'Ubuntu existente.',
      );

      return _terminalSession!;
    }

    if (forceNew) {
      closeTerminalSession();
    }

    final session =
        await createSession(
      workingDirectory: '/root',
    );

    _terminalSession = session;

    _startTerminalOutputBridge(
      session,
    );

    return session;
  }

  Future<UbuntuSession>
      createFlutterSession({
    String workingDirectory = '/root',
  }) async {
    final stopwatch =
        Stopwatch()..start();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'createFlutterSession: INÍCIO',
    );

    final session =
        await createSession(
      workingDirectory:
          workingDirectory,
    );

    stopwatch.stop();

    debugPrint(
      '[UbuntuSessionManager][TIMING] '
      'createFlutterSession: FIM '
      '(${stopwatch.elapsedMilliseconds} ms)',
    );

    return session;
  }

  // ============================================================
  // PONTE PTY → TERMINAL
  // ============================================================

  void _startTerminalOutputBridge(
    UbuntuSession session,
  ) {
    unawaited(
      _terminalOutputSubscription?.cancel(),
    );

    _terminalOutputSubscription =
        session.pty.output.listen(
      (data) {
        if (_terminalSession != session) {
          return;
        }

        try {
          final text =
              utf8.decode(
            data,
            allowMalformed: true,
          );

          terminal.write(
            text,
          );
        } catch (e) {
          debugPrint(
            '[UbuntuSessionManager] Erro processando saída '
            'do terminal: $e',
          );
        }
      },
      onDone: () {
        if (_terminalSession != session) {
          return;
        }

        terminal.write(
          '\r\n'
          '[Sessão do terminal encerrada]'
          '\r\n',
        );
      },
      onError: (Object e) {
        if (_terminalSession != session) {
          return;
        }

        terminal.write(
          '\r\n'
          '[Erro no PTY: $e]'
          '\r\n',
        );
      },
    );
  }

  // ============================================================
  // MONITORAMENTO
  // ============================================================

  Future<void> _watchSession(
    UbuntuSession session,
  ) async {
    try {
      await session.pty.exitCode;
    } catch (e) {
      debugPrint(
        '[UbuntuSessionManager] Erro aguardando sessão: $e',
      );
    }

    _sessions.remove(session);

    session.markClosed();

    if (_terminalSession == session) {
      await _terminalOutputSubscription?.cancel();

      _terminalOutputSubscription = null;

      _terminalSession = null;
    }

    debugPrint(
      '[UbuntuSessionManager] Sessão encerrada.',
    );
  }

  // ============================================================
  // ENCERRAMENTO
  // ============================================================

  void closeSession(
    UbuntuSession session,
  ) {
    if (!_sessions.contains(session)) {
      return;
    }

    if (_terminalSession == session) {
      unawaited(
        _terminalOutputSubscription?.cancel(),
      );

      _terminalOutputSubscription = null;

      _terminalSession = null;
    }

    session.kill();

    _sessions.remove(
      session,
    );
  }

  void closeTerminalSession() {
    final session =
        _terminalSession;

    if (session == null) {
      return;
    }

    unawaited(
      _terminalOutputSubscription?.cancel(),
    );

    _terminalOutputSubscription = null;

    _terminalSession = null;

    session.kill();

    _sessions.remove(
      session,
    );
  }

  void closeAllSessions() {
    unawaited(
      _terminalOutputSubscription?.cancel(),
    );

    _terminalOutputSubscription = null;

    _terminalSession = null;

    final sessions =
        List<UbuntuSession>.from(
      _sessions,
    );

    for (final session in sessions) {
      session.kill();
    }

    _sessions.clear();
  }
}