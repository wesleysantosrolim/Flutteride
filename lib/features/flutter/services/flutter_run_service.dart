import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../terminal/models/ubuntu_session.dart';
import '../../terminal/services/ubuntu_session_manager.dart';

enum FlutterRunTarget {
  webServer,
  androidArm64,
}

enum FlutterRunStatus {
  idle,
  starting,
  running,
  stopping,
  stopped,
  error,
}

class FlutterRunService {
  FlutterRunService._();

  static final FlutterRunService instance =
      FlutterRunService._();

  UbuntuSession? _session;

  StreamSubscription<List<int>>?
      _outputSubscription;

  final StreamController<String>
      _outputController =
      StreamController<String>.broadcast();

  FlutterRunStatus _status =
      FlutterRunStatus.idle;

  FlutterRunTarget? _target;

  String? _projectPath;

  String? _previewUrl;

  bool _stopRequested = false;

  FlutterRunStatus get status => _status;

  FlutterRunTarget? get target => _target;

  bool get isRunning =>
      _status == FlutterRunStatus.running ||
      _status == FlutterRunStatus.starting;

  bool get hasSession =>
      _session != null &&
      !_session!.isClosed;

  String? get projectPath =>
      _projectPath;

  String? get previewUrl =>
      _previewUrl;

  bool get canPreview =>
      _status == FlutterRunStatus.running &&
      _target == FlutterRunTarget.webServer &&
      _previewUrl != null;

  Stream<String> get output =>
      _outputController.stream;

  Future<void> run({
    required String projectPath,
    required FlutterRunTarget target,
  }) async {
    if (isRunning) {
      debugPrint(
        '[FlutterRunService] Flutter já está executando.',
      );
      return;
    }

    await stop();

    _projectPath = projectPath;
    _target = target;
    _previewUrl = null;
    _stopRequested = false;

    _setStatus(
      FlutterRunStatus.starting,
    );

    try {
      final session =
          await UbuntuSessionManager
              .instance
              .createFlutterSession(
        workingDirectory: projectPath,
      );

      _session = session;

      _startOutputListener(
        session,
      );

      final command =
          _buildFlutterCommand(target);

      debugPrint(
        '[FlutterRunService] Executando: $command',
      );

      session.write(
        Uint8List.fromList(
          utf8.encode(
            '$command\n',
          ),
        ),
      );

      _setStatus(
        FlutterRunStatus.running,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[FlutterRunService] Erro iniciando Flutter: '
        '$error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      _previewUrl = null;

      _setStatus(
        FlutterRunStatus.error,
      );

      _emitOutput(
        '\r\n'
        '[FlutterRunService] Erro ao iniciar Flutter:\r\n'
        '$error\r\n',
      );

      await _cleanupSession();
    }
  }

  String _buildFlutterCommand(
    FlutterRunTarget target,
  ) {
    final command =
        <String>[
      'flutter',
      if (target ==
          FlutterRunTarget.webServer) ...[
        'run',
        '-d',
        'web-server',
      ] else ...[
        'build',
        'apk',
        '--debug',
        '--target-platform',
        'android-arm64',
        '--android-skip-build-dependency-validation',
      ],
    ];

    return command
        .map(_shellEscape)
        .join(' ');
  }

  String _shellEscape(
    String value,
  ) {
    if (value.isEmpty) {
      return "''";
    }

    if (RegExp(
      r'^[a-zA-Z0-9_./:=+-]+$',
    ).hasMatch(value)) {
      return value;
    }

    return "'${value.replaceAll(
      "'",
      "'\\''",
    )}'";
  }

  void _startOutputListener(
    UbuntuSession session,
  ) {
    unawaited(
      _outputSubscription?.cancel(),
    );

    _outputSubscription =
        session.pty.output.listen(
      (data) {
        if (_session != session) {
          return;
        }

        try {
          final text =
              utf8.decode(
            data,
            allowMalformed: true,
          );

          _detectPreviewUrl(text);

          _emitOutput(text);
        } catch (error) {
          debugPrint(
            '[FlutterRunService] Erro processando saída: '
            '$error',
          );
        }
      },
      onDone: () {
        if (_session != session) {
          return;
        }

        _previewUrl = null;

        _emitOutput(
          '\r\n'
          '[Sessão Flutter encerrada]\r\n',
        );

        if (!_stopRequested) {
          _setStatus(
            FlutterRunStatus.stopped,
          );
        }

        unawaited(
          _cleanupSession(
            expectedSession: session,
          ),
        );
      },
      onError: (Object error) {
        if (_session != session) {
          return;
        }

        _previewUrl = null;

        _emitOutput(
          '\r\n'
          '[Erro no PTY Flutter: $error]\r\n',
        );

        _setStatus(
          FlutterRunStatus.error,
        );
      },
    );
  }

  void _detectPreviewUrl(
    String text,
  ) {
    if (_target != FlutterRunTarget.webServer) {
      return;
    }

    if (_previewUrl != null) {
      return;
    }

    final match = RegExp(
      r'lib/main\.dart is being served at\s+(https?://[^\s\x1b]+)',
      caseSensitive: false,
    ).firstMatch(text);

    if (match == null) {
      return;
    }

    var url = match.group(1);

    if (url == null || url.isEmpty) {
      return;
    }

    url = url.replaceAll(
      RegExp(r'[\r\n]+$'),
      '',
    );

    if (url.endsWith('/')) {
      url = url.substring(
        0,
        url.length - 1,
      );
    }

    _previewUrl = url;

    debugPrint(
      '[FlutterRunService] Preview disponível: $_previewUrl',
    );
  }

  void _emitOutput(
    String text,
  ) {
    if (_outputController.isClosed) {
      return;
    }

    _outputController.add(text);
  }

  void hotReload() {
    if (_target !=
        FlutterRunTarget.webServer) {
      return;
    }

    final session =
        _session;

    if (session == null ||
        session.isClosed ||
        !isRunning) {
      return;
    }

    debugPrint(
      '[FlutterRunService] Hot Reload.',
    );

    session.write(
      Uint8List.fromList(
        <int>[114],
      ),
    );
  }

  void hotRestart() {
    if (_target !=
        FlutterRunTarget.webServer) {
      return;
    }

    final session =
        _session;

    if (session == null ||
        session.isClosed ||
        !isRunning) {
      return;
    }

    debugPrint(
      '[FlutterRunService] Hot Restart.',
    );

    session.write(
      Uint8List.fromList(
        <int>[82],
      ),
    );
  }

  Future<void> stop() async {
    final session =
        _session;

    if (session == null) {
      _previewUrl = null;

      if (_status !=
          FlutterRunStatus.idle) {
        _setStatus(
          FlutterRunStatus.stopped,
        );
      }

      return;
    }

    if (session.isClosed) {
      _previewUrl = null;

      await _cleanupSession(
        expectedSession: session,
      );

      return;
    }

    _stopRequested = true;
    _previewUrl = null;

    _setStatus(
      FlutterRunStatus.stopping,
    );

    debugPrint(
      '[FlutterRunService] Encerrando Flutter.',
    );

    try {
      session.write(
        Uint8List.fromList(
          <int>[3],
        ),
      );
    } catch (error) {
      debugPrint(
        '[FlutterRunService] Erro enviando Ctrl+C: '
        '$error',
      );
    }

    await Future<void>.delayed(
      const Duration(
        milliseconds: 800,
      ),
    );

    if (_session == session &&
        !session.isClosed) {
      session.kill();
    }

    await _cleanupSession(
      expectedSession: session,
    );

    _setStatus(
      FlutterRunStatus.stopped,
    );

    _emitOutput(
      '\r\n'
      '[Flutter parado]\r\n',
    );
  }

  void write(
    String input,
  ) {
    final session =
        _session;

    if (session == null ||
        session.isClosed) {
      return;
    }

    session.write(
      Uint8List.fromList(
        utf8.encode(input),
      ),
    );
  }

  void sendKey(
    int keyCode,
  ) {
    final session =
        _session;

    if (session == null ||
        session.isClosed) {
      return;
    }

    session.write(
      Uint8List.fromList(
        <int>[keyCode],
      ),
    );
  }

  void _setStatus(
    FlutterRunStatus status,
  ) {
    _status = status;
  }

  Future<void> _cleanupSession({
    UbuntuSession? expectedSession,
  }) async {
    final session =
        _session;

    if (expectedSession != null &&
        session != expectedSession) {
      return;
    }

    await _outputSubscription?.cancel();

    _outputSubscription = null;

    if (session != null &&
        !session.isClosed) {
      session.kill();
    }

    _session = null;
  }

  Future<void> dispose() async {
    await stop();

    await _outputSubscription?.cancel();

    _outputSubscription = null;

    await _outputController.close();
  }
}