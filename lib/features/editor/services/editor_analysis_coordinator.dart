import 'dart:async';

import 'dart_analysis_service.dart';
import 'dart_lsp_client.dart';

class EditorAnalysisCoordinator {
  EditorAnalysisCoordinator({
    DartAnalysisService? analysisService,
  }) : analysisService =
            analysisService ?? DartAnalysisService();

  final DartAnalysisService analysisService;

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  final List<String> _logHistory = <String>[];

  bool _disposed = false;

  static const int _maxLogHistory = 2000;

  Future<void>? _startFuture;

  Timer? _debounceTimer;

  Future<void> _documentOperationQueue =
      Future<void>.value();

  bool get isInitialized =>
      analysisService.isInitialized;

  bool get isConnected =>
      analysisService.isInitialized;

  bool get isRunning =>
      analysisService.client.isRunning;

  String? get workspacePath =>
      analysisService.workspacePath;

  String? get serverWorkspacePath =>
      analysisService.serverWorkspacePath;

  Set<String> get openDocuments =>
      analysisService.openDocuments;

  Stream<bool> get connectionStream =>
      _connectionController.stream;

  Stream<String> get serverLogs =>
      analysisService.serverLogs;

  Stream<String> get logs =>
      _logController.stream;

  List<String> get logHistory =>
      List<String>.unmodifiable(_logHistory);

  Stream<Map<String, dynamic>> get notifications =>
      analysisService.notifications;

  Stream<DartDiagnostic> get diagnostics =>
      analysisService.diagnostics;

  Stream<DartFileDiagnostics> get fileDiagnostics =>
      analysisService.fileDiagnostics;

  DartLspClient get client =>
      analysisService.client;

  Future<void> start({
    required String workspacePath,
  }) async {
    _ensureNotDisposed();

    final existingStart = _startFuture;

    if (existingStart != null) {
      await existingStart;
      return;
    }

    if (analysisService.isInitialized) {
      return;
    }

    final future = _startInternal(
      workspacePath: workspacePath,
    );

    _startFuture = future;

    try {
      await future;
    } finally {
      if (identical(_startFuture, future)) {
        _startFuture = null;
      }
    }
  }

  Future<void> _startInternal({
    required String workspacePath,
  }) async {
    _ensureNotDisposed();

    _emitLog(
      '[Coordinator] Iniciando Analysis Server...',
    );

    _emitLog(
      '[Coordinator] Workspace: $workspacePath',
    );

    _emitConnectionState(false);

    try {
      _emitLog(
        '[Coordinator] Chamando DartAnalysisService.start()...',
      );

      await analysisService.start(
        workspacePath: workspacePath,
      );

      _emitLog(
        '[Coordinator] DartAnalysisService.start() concluído.',
      );

      _emitLog(
        '[Coordinator] isInitialized: '
        '${analysisService.isInitialized}',
      );

      _emitLog(
        '[Coordinator] isRunning: '
        '${analysisService.client.isRunning}',
      );

      _emitLog(
        '[Coordinator] serverWorkspacePath: '
        '${analysisService.serverWorkspacePath}',
      );

      _emitConnectionState(
        analysisService.isInitialized,
      );

      if (analysisService.isInitialized) {
        _emitLog(
          '[Coordinator] Analysis Server conectado.',
        );
      } else {
        _emitLog(
          '[Coordinator] Analysis Server não foi inicializado.',
        );
      }
    } catch (error, stackTrace) {
      _emitConnectionState(false);

      _emitLog(
        '[Coordinator] ERRO ao iniciar Analysis Server:',
      );

      _emitLog('$error');

      _emitLog(
        '[Coordinator] StackTrace:',
      );

      _emitLog('$stackTrace');

      rethrow;
    }
  }

  Future<void> _waitUntilReady() async {
    _ensureNotDisposed();

    if (analysisService.isInitialized) {
      return;
    }

    final startFuture = _startFuture;

    if (startFuture != null) {
      await startFuture;
    }

    _ensureNotDisposed();

    if (!analysisService.isInitialized) {
      throw StateError(
        'Analysis Server não está inicializado.',
      );
    }
  }

  Future<void> openDocument({
    required String path,
    required String text,
    String languageId = 'dart',
  }) async {
    _ensureNotDisposed();

    await _waitUntilReady();

    await _enqueueDocumentOperation(
      () async {
        await analysisService.openDocument(
          path: path,
          text: text,
          languageId: languageId,
        );
      },
    );
  }

  Future<void> changeDocument({
    required String path,
    required String text,
  }) async {
    _ensureNotDisposed();

    await _waitUntilReady();

    await _enqueueDocumentOperation(
      () async {
        await analysisService.changeDocument(
          path: path,
          text: text,
        );
      },
    );
  }

  Future<void> closeDocument(String path) async {
    if (_disposed) return;

    if (!analysisService.isInitialized) {
      return;
    }

    await _enqueueDocumentOperation(
      () async {
        await analysisService.closeDocument(path);
      },
    );
  }

  Future<List<DartCompletionItem>> complete({
    required String path,
    required int line,
    required int character,
  }) async {
    _ensureNotDisposed();

    await _waitUntilReady();

    return _enqueueDocumentOperation(
      () async {
        _ensureNotDisposed();

        return analysisService.complete(
          path: path,
          line: line,
          character: character,
        );
      },
    );
  }

  /// Solicita ao Dart Analysis Server a assinatura da função
  /// ou do construtor na posição atual do cursor.
  ///
  /// line e character utilizam índices LSP iniciando em zero.
  Future<Map<String, dynamic>?> signatureHelp({
    required String path,
    required int line,
    required int character,
    String? triggerCharacter,
    bool isRetrigger = false,
  }) async {
    _ensureNotDisposed();

    await _waitUntilReady();

    return _enqueueDocumentOperation(
      () async {
        _ensureNotDisposed();

        final result = await analysisService.signatureHelp(
          path: path,
          line: line,
          character: character,
          triggerCharacter: triggerCharacter,
          isRetrigger: isRetrigger,
        );

        if (result == null) {
          _emitLog(
            '[SignatureHelp] Nenhuma assinatura retornada. '
            'path=$path line=$line character=$character',
          );
        } else {
          _emitLog(
            '[SignatureHelp] Resposta recebida. '
            'path=$path line=$line character=$character',
          );
        }

        return result;
      },
    );
  }

  Future<T> _enqueueDocumentOperation<T>(
    Future<T> Function() operation,
  ) {
    if (_disposed) {
      return Future<T>.error(
        StateError(
          'EditorAnalysisCoordinator já foi descartado.',
        ),
      );
    }

    final previousOperation = _documentOperationQueue;

    final operationFuture = previousOperation.then(
      (_) async {
        _ensureNotDisposed();

        return operation();
      },
    );

    _documentOperationQueue = operationFuture.then<void>(
      (_) {},
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {},
    );

    return operationFuture;
  }

  Future<void> reanalyze() async {
    _ensureNotDisposed();

    await _waitUntilReady();

    await _enqueueDocumentOperation(
      () async {
        await analysisService.reanalyze();
      },
    );
  }

  Future<void> stop() async {
    if (_disposed) return;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    _emitLog(
      '[Coordinator] Parando Analysis Server...',
    );

    _emitConnectionState(false);

    try {
      await _documentOperationQueue;
    } catch (_) {}

    if (_disposed) return;

    await analysisService.stop();

    _emitConnectionState(false);

    _emitLog(
      '[Coordinator] Analysis Server parado.',
    );
  }

  void _emitConnectionState(bool connected) {
    if (_disposed || _connectionController.isClosed) {
      return;
    }

    _connectionController.add(connected);
  }

  void _emitLog(String message) {
    if (_disposed) return;

    _logHistory.add(message);

    if (_logHistory.length > _maxLogHistory) {
      _logHistory.removeRange(
        0,
        _logHistory.length - _maxLogHistory,
      );
    }

    if (!_logController.isClosed) {
      _logController.add(message);
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError(
        'EditorAnalysisCoordinator já foi descartado.',
      );
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    try {
      await _documentOperationQueue;
    } catch (_) {}

    _documentOperationQueue = Future<void>.value();

    final startFuture = _startFuture;

    if (startFuture != null) {
      try {
        await startFuture;
      } catch (_) {}
    }

    _startFuture = null;

    await analysisService.dispose();

    if (!_connectionController.isClosed) {
      await _connectionController.close();
    }

    if (!_logController.isClosed) {
      await _logController.close();
    }
  }

  void onContentChanged({
    required String filePath,
    required String content,
  }) {
    if (_disposed) return;

    _debounceTimer?.cancel();
    _debounceTimer = null;

    final update = _enqueueDocumentOperation<void>(
      () async {
        await _sendContentUpdate(
          filePath,
          content,
        );
      },
    );

    unawaited(
      update.catchError((_) {}),
    );
  }

  Future<void> _sendContentUpdate(
    String filePath,
    String content,
  ) async {
    if (_disposed) return;

    try {
      await _waitUntilReady();

      if (_disposed) return;

      await analysisService.openDocument(
        path: filePath,
        text: content,
        languageId: 'dart',
      );
    } catch (_) {}
  }
}