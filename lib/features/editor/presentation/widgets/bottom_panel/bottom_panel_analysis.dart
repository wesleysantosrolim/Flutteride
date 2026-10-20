import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../services/dart_analysis_service.dart';
import '../../../services/editor_analysis_coordinator.dart';

class BottomPanelAnalysis extends StatefulWidget {
  const BottomPanelAnalysis({
    super.key,
    required this.analysisCoordinator,
  });

  final EditorAnalysisCoordinator analysisCoordinator;

  @override
  State<BottomPanelAnalysis> createState() =>
      _BottomPanelAnalysisState();
}

class _BottomPanelAnalysisState
    extends State<BottomPanelAnalysis> {
  StreamSubscription<bool>? _connectionSubscription;

  StreamSubscription<DartFileDiagnostics>?
      _diagnosticsSubscription;

  bool _connected = false;

  final Map<String, List<DartDiagnostic>>
      _diagnosticsByFile =
      <String, List<DartDiagnostic>>{};

  @override
  void initState() {
    super.initState();

    _connected =
        widget.analysisCoordinator.isConnected;

    _subscribeToCoordinator(
      widget.analysisCoordinator,
    );
  }

  void _subscribeToCoordinator(
    EditorAnalysisCoordinator coordinator,
  ) {
    _connectionSubscription =
        coordinator.connectionStream.listen(
      _handleConnectionState,
    );

    _diagnosticsSubscription =
        coordinator.fileDiagnostics.listen(
      _handleFileDiagnostics,
    );
  }

  @override
  void didUpdateWidget(
    covariant BottomPanelAnalysis oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.analysisCoordinator !=
        widget.analysisCoordinator) {
      _connectionSubscription?.cancel();
      _diagnosticsSubscription?.cancel();

      _connected =
          widget.analysisCoordinator.isConnected;

      _subscribeToCoordinator(
        widget.analysisCoordinator,
      );
    }
  }

  void _handleConnectionState(
    bool connected,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      _connected = connected;
    });
  }

  void _handleFileDiagnostics(
    DartFileDiagnostics fileDiagnostics,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      if (fileDiagnostics.diagnostics.isEmpty) {
        _diagnosticsByFile.remove(
          fileDiagnostics.uri,
        );
      } else {
        _diagnosticsByFile[
                fileDiagnostics.uri] =
            List<DartDiagnostic>.from(
          fileDiagnostics.diagnostics,
        );
      }
    });
  }

  List<DartDiagnostic> get _allDiagnostics {
    final diagnostics =
        <DartDiagnostic>[];

    for (final fileDiagnostics
        in _diagnosticsByFile.values) {
      diagnostics.addAll(
        fileDiagnostics,
      );
    }

    return diagnostics;
  }

  int get _errorCount {
    return _allDiagnostics.where(
      (diagnostic) =>
          diagnostic.severity ==
          DartDiagnosticSeverity.error,
    ).length;
  }

  int get _warningCount {
    return _allDiagnostics.where(
      (diagnostic) =>
          diagnostic.severity ==
          DartDiagnosticSeverity.warning,
    ).length;
  }

  int get _informationCount {
    return _allDiagnostics.where(
      (diagnostic) =>
          diagnostic.severity ==
          DartDiagnosticSeverity.information,
    ).length;
  }

  int get _hintCount {
    return _allDiagnostics.where(
      (diagnostic) =>
          diagnostic.severity ==
          DartDiagnosticSeverity.hint,
    ).length;
  }

  @override
  Widget build(BuildContext context) {
    final diagnostics =
        _allDiagnostics;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 8,
      ),
      children: [
        Row(
          children: [
            _buildServerStatus(),
            const Spacer(),
            _buildSummary(),
          ],
        ),
        const Divider(
          color: Color(0xFF3A3A3A),
          height: 16,
        ),
        if (diagnostics.isEmpty)
          _buildNoDiagnostics()
        else
          ...diagnostics.map(
            _buildDiagnosticItem,
          ),
      ],
    );
  }

  Widget _buildServerStatus() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _connected
                ? Colors.greenAccent
                : Colors.orangeAccent,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _connected
              ? 'Server conectado'
              : 'Conectando...',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final total =
        _allDiagnostics.length;

    if (total == 0) {
      return const Text(
        'Sem problemas',
        style: TextStyle(
          color: Colors.white38,
          fontSize: 11,
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_errorCount > 0)
          _buildCount(
            icon: Icons.error_outline,
            count: _errorCount,
          ),
        if (_warningCount > 0)
          _buildCount(
            icon: Icons.warning_amber_outlined,
            count: _warningCount,
          ),
        if (_informationCount > 0)
          _buildCount(
            icon: Icons.info_outline,
            count: _informationCount,
          ),
        if (_hintCount > 0)
          _buildCount(
            icon: Icons.lightbulb_outline,
            count: _hintCount,
          ),
      ],
    );
  }

  Widget _buildCount({
    required IconData icon,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(
        left: 8,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: Colors.white54,
          ),
          const SizedBox(width: 3),
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoDiagnostics() {
    return const Padding(
      padding: EdgeInsets.symmetric(
        vertical: 20,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 28,
              color: Colors.greenAccent,
            ),
            SizedBox(height: 8),
            Text(
              'Nenhum problema encontrado',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticItem(
    DartDiagnostic diagnostic,
  ) {
    final severity =
        diagnostic.severity;

    final IconData icon;

    switch (severity) {
      case DartDiagnosticSeverity.error:
        icon = Icons.error_outline;
        break;

      case DartDiagnosticSeverity.warning:
        icon = Icons.warning_amber_outlined;
        break;

      case DartDiagnosticSeverity.information:
        icon = Icons.info_outline;
        break;

      case DartDiagnosticSeverity.hint:
        icon = Icons.lightbulb_outline;
        break;

      case DartDiagnosticSeverity.unknown:
        icon = Icons.help_outline;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(
        bottom: 6,
      ),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.03,
        ),
        borderRadius:
            BorderRadius.circular(4),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: _severityColor(
              severity,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  diagnostic.message,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _diagnosticLocation(
                    diagnostic,
                  ),
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _diagnosticLocation(
    DartDiagnostic diagnostic,
  ) {
    final line =
        diagnostic.range.start.line + 1;

    final character =
        diagnostic.range.start.character + 1;

    return '$line:$character';
  }

  Color _severityColor(
    DartDiagnosticSeverity severity,
  ) {
    switch (severity) {
      case DartDiagnosticSeverity.error:
        return Colors.redAccent;

      case DartDiagnosticSeverity.warning:
        return Colors.orangeAccent;

      case DartDiagnosticSeverity.information:
        return Colors.lightBlueAccent;

      case DartDiagnosticSeverity.hint:
        return Colors.greenAccent;

      case DartDiagnosticSeverity.unknown:
        return Colors.white38;
    }
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _diagnosticsSubscription?.cancel();

    super.dispose();
  }
}