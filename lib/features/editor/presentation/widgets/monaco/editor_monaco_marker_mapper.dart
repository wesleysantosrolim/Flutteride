import 'package:flutteride/features/editor/services/dart_analysis_service.dart';

/// Mapeia os diagnósticos do Dart Analysis Server para a estrutura JSON do Monaco Editor.
class EditorMonacoMarkerMapper {
  static List<Map<String, dynamic>> fromDartDiagnostics(
    List<DartDiagnostic> diagnostics,
  ) {
    return diagnostics.map((diag) {
      final dynamic d = diag;

      final int line = d.line ?? d.location?.startLine ?? 1;
      final int col = d.column ?? d.location?.startColumn ?? 1;
      final int len = d.length ?? 1;
      final String msg = d.message ?? '';
      final String sevStr = d.severity?.name ?? d.severity?.toString() ?? 'info';

      return <String, dynamic>{
        'startLineNumber': line,
        'startColumn': col,
        'endLineNumber': line,
        'endColumn': col + (len > 0 ? len : 1),
        'message': msg,
        'severity': _mapSeverity(sevStr),
        'source': 'dart',
      };
    }).toList();
  }

  /// Monaco MarkerSeverity: Error = 8, Warning = 4, Info = 2, Hint = 1
  static int _mapSeverity(String severity) {
    final lower = severity.toLowerCase();
    if (lower.contains('error')) return 8;
    if (lower.contains('warning')) return 4;
    if (lower.contains('hint')) return 1;
    return 2;
  }
}
