import 'dart:async';

import 'package:flutter_monaco/flutter_monaco.dart';

import 'editor_analysis_coordinator.dart';
import 'dart_analysis_service.dart';

class EditorMonacoSyncService {
  EditorMonacoSyncService({
    required this.analysisCoordinator,
  }) {
    _fileDiagnosticsSubscription =
        analysisCoordinator.fileDiagnostics.listen(
      _onFileDiagnostics,
    );
  }

  final EditorAnalysisCoordinator analysisCoordinator;

  MonacoController? _monacoController;

  String? _activeFilePath;

  bool _editorReady = false;
  bool _disposed = false;

  final Map<String, List<DartDiagnostic>>
      _diagnosticsByFile =
      <String, List<DartDiagnostic>>{};

  final Map<String, int>
      _diagnosticVersions =
      <String, int>{};

  StreamSubscription<DartFileDiagnostics>?
      _fileDiagnosticsSubscription;

  void bindDiagnostics({
    MonacoController? controller,
    String? activeFilePath,
  }) {
    if (_disposed) {
      return;
    }

    if (controller != null) {
      _monacoController = controller;
      _editorReady = true;
    }

    _activeFilePath = activeFilePath;

    if (activeFilePath != null) {
      unawaited(
        applyStoredDiagnosticsForFile(
          activeFilePath,
        ),
      );
    } else {
      unawaited(
        _clearCurrentMarkers(),
      );
    }
  }

  void attachMonacoController(
    MonacoController controller,
  ) {
    if (_disposed) {
      return;
    }

    _monacoController = controller;
    _editorReady = true;

    final activeFilePath =
        _activeFilePath;

    if (activeFilePath != null) {
      unawaited(
        applyStoredDiagnosticsForFile(
          activeFilePath,
        ),
      );
    }
  }

  void detachMonacoController() {
    _monacoController = null;
    _editorReady = false;
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    _fileDiagnosticsSubscription?.cancel();
    _fileDiagnosticsSubscription = null;

    _monacoController = null;
    _activeFilePath = null;
    _editorReady = false;

    _diagnosticsByFile.clear();
    _diagnosticVersions.clear();
  }

  String canonicalizeFilePath(
    String raw,
  ) {
    var path = raw.trim();

    if (path.isEmpty) {
      return path;
    }

    try {
      if (path.startsWith('file://')) {
        path = Uri.parse(path).toFilePath();
      }
    } catch (_) {
      path = path.replaceFirst(
        'file://',
        '',
      );
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }

    return _normalizePath(
      path,
    );
  }

  String _normalizePath(
    String path,
  ) {
    if (path.length > 1 &&
        path.endsWith('/')) {
      return path.substring(
        0,
        path.length - 1,
      );
    }

    return path;
  }

  String _serverPathFor(
    String filePath,
  ) {
    return _normalizePath(
      analysisCoordinator.client
          .convertPathToServerPath(
        filePath,
      ),
    );
  }

  String _diagnosticKeyFor(
    String filePathOrUri,
  ) {
    var path = filePathOrUri.trim();

    if (path.startsWith('file://')) {
      try {
        path = Uri.parse(path).toFilePath();
      } catch (_) {
        path = path.replaceFirst(
          'file://',
          '',
        );
      }
    }

    if (!path.startsWith('/')) {
      path = '/$path';
    }

    /*
     * Os diagnostics recebidos do Analysis Server
     * usam o caminho do workspace Ubuntu.
     *
     * Arquivos selecionados pelo Editor usam
     * o caminho físico do projeto Android.
     *
     * Por isso, quando recebemos um caminho físico,
     * convertemos para o mesmo formato utilizado
     * pelo servidor.
     */
    if (path == filePathOrUri) {
      try {
        path = _serverPathFor(
          filePathOrUri,
        );
      } catch (_) {}
    }

    return canonicalizeFilePath(
      path,
    );
  }

  Future<void> onDocumentOpened(
    String filePath,
    String content,
  ) async {
    if (_disposed) {
      return;
    }

    if (!filePath
        .toLowerCase()
        .endsWith('.dart')) {
      return;
    }

    _activeFilePath = filePath;

    try {
      await analysisCoordinator.openDocument(
        path: filePath,
        text: content,
        languageId: 'dart',
      );

      if (_disposed) {
        return;
      }

      await applyStoredDiagnosticsForFile(
        filePath,
      );
    } catch (error) {
      // A abertura do documento não deve quebrar o Editor.
    }
  }

  Future<void> onDocumentChanged(
    String filePath,
    String content,
  ) async {
    if (_disposed) {
      return;
    }

    if (!filePath
        .toLowerCase()
        .endsWith('.dart')) {
      return;
    }

    try {
      await analysisCoordinator.changeDocument(
        path: filePath,
        text: content,
      );
    } catch (_) {}
  }

  Future<void> onDocumentClosed(
    String filePath,
  ) async {
    if (_disposed) {
      return;
    }

    if (!filePath
        .toLowerCase()
        .endsWith('.dart')) {
      return;
    }

    final canonicalKey =
        _serverPathFor(
      filePath,
    );

    _diagnosticsByFile.remove(
      canonicalKey,
    );

    _diagnosticVersions.remove(
      canonicalKey,
    );

    if (_activeFilePath ==
        filePath) {
      _activeFilePath = null;
    }

    try {
      await analysisCoordinator.closeDocument(
        filePath,
      );
    } catch (_) {}

    if (!_disposed) {
      await _clearCurrentMarkers();
    }
  }

  Future<void> _onFileDiagnostics(
    DartFileDiagnostics update,
  ) async {
    if (_disposed) {
      return;
    }

    final rawUri =
        update.uri.toString();

    final canonicalKey =
        _diagnosticKeyFor(
      rawUri,
    );

    final version =
        (_diagnosticVersions[
                    canonicalKey] ??
                0) +
            1;

    _diagnosticVersions[
        canonicalKey] = version;

    final diagnostics =
        List<DartDiagnostic>.from(
      update.diagnostics,
    );

    if (diagnostics.isEmpty) {
      _diagnosticsByFile.remove(
        canonicalKey,
      );
    } else {
      _diagnosticsByFile[
          canonicalKey] =
          List<DartDiagnostic>.unmodifiable(
        diagnostics,
      );
    }

    await applyDiagnosticsToFilePath(
      rawUri,
      diagnostics,
      expectedVersion: version,
    );
  }

  Future<void>
      applyStoredDiagnosticsForFile(
    String filePath,
  ) async {
    if (_disposed) {
      return;
    }

    final canonicalKey =
        _serverPathFor(
      filePath,
    );

    final diagnostics =
        _diagnosticsByFile[
                canonicalKey] ??
            const <DartDiagnostic>[];

    final version =
        _diagnosticVersions[
            canonicalKey];

    await applyDiagnosticsToFilePath(
      filePath,
      diagnostics,
      expectedVersion: version,
    );
  }

  Future<void>
      applyDiagnosticsToFilePath(
    String filePathOrUri,
    List<DartDiagnostic> diagnostics, {
    int? expectedVersion,
  }) async {
    if (_disposed) {
      return;
    }

    final controller =
        _monacoController;

    if (controller == null ||
        !_editorReady) {
      return;
    }

    final canonicalKey =
        _diagnosticKeyFor(
      filePathOrUri,
    );

    if (expectedVersion != null) {
      final currentVersion =
          _diagnosticVersions[
              canonicalKey];

      if (currentVersion !=
          expectedVersion) {
        return;
      }
    }

    /*
     * O Monaco atual possui apenas um documento
     * ativo. Portanto, os markers só devem ser
     * aplicados quando o diagnóstico pertence
     * ao arquivo atualmente selecionado.
     */
    final activeFilePath =
        _activeFilePath;

    if (activeFilePath == null) {
      return;
    }

    final activeKey =
        _serverPathFor(
      activeFilePath,
    );

    if (activeKey !=
        canonicalKey) {
      return;
    }

    try {
      await controller.whenReady;

      if (_disposed ||
          _monacoController !=
              controller) {
        return;
      }

      final markers =
          diagnostics
              .map(
                _diagnosticToMarker,
              )
              .toList();

      if (markers.isEmpty) {
        await controller.document
            .clearMarkers(
          owner: 'dart-analysis',
        );
      } else {
        await controller.document
            .setMarkers(
          markers,
          owner: 'dart-analysis',
        );
      }
    } catch (_) {}
  }

  Future<void>
      _clearCurrentMarkers() async {
    if (_disposed) {
      return;
    }

    final controller =
        _monacoController;

    if (controller == null ||
        !_editorReady) {
      return;
    }

    try {
      await controller.whenReady;

      if (_disposed ||
          _monacoController !=
              controller) {
        return;
      }

      await controller.document
          .clearMarkers(
        owner: 'dart-analysis',
      );
    } catch (_) {}
  }

  MarkerData _diagnosticToMarker(
    DartDiagnostic diagnostic,
  ) {
    var startLine =
        diagnostic.range.start.line + 1;

    var startColumn =
        diagnostic.range.start.character + 1;

    var endLine =
        diagnostic.range.end.line + 1;

    var endColumn =
        diagnostic.range.end.character + 1;

    if (startLine < 1) {
      startLine = 1;
    }

    if (startColumn < 1) {
      startColumn = 1;
    }

    if (endLine < startLine) {
      endLine = startLine;
    }

    if (endLine == startLine &&
        endColumn <= startColumn) {
      endColumn =
          startColumn + 1;
    }

    return MarkerData(
      range: Range(
        startLine: startLine,
        startColumn: startColumn,
        endLine: endLine,
        endColumn: endColumn,
      ),
      message: diagnostic.message,
      severity:
          _convertDiagnosticSeverity(
        diagnostic.severity,
      ),
      code: diagnostic.code,
      source:
          diagnostic.source ?? 'dart',
    );
  }

  MarkerSeverity
      _convertDiagnosticSeverity(
    DartDiagnosticSeverity severity,
  ) {
    switch (severity) {
      case DartDiagnosticSeverity.error:
        return MarkerSeverity.error;

      case DartDiagnosticSeverity.warning:
        return MarkerSeverity.warning;

      case DartDiagnosticSeverity.information:
        return MarkerSeverity.info;

      case DartDiagnosticSeverity.hint:
        return MarkerSeverity.hint;

      case DartDiagnosticSeverity.unknown:
        return MarkerSeverity.info;
    }
  }
}