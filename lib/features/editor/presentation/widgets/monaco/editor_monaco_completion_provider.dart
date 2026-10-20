import '../../../services/dart_analysis_service.dart';

/// Formata itens do Dart Analysis Server para uma estrutura simples
/// compatível com o consumo do editor.
///
/// A conversão completa para CompletionItem do Monaco é feita pelo
/// EditorMonacoCompletionService.
class EditorMonacoCompletionProvider {
  static List<Map<String, dynamic>> formatSuggestions(
    List<DartCompletionItem> items,
  ) {
    return items.map((item) {
      return <String, dynamic>{
        'label': item.label,
        'kind': item.kind,
        'detail': item.detail,
        'insertText': item.insertText ?? item.label,
        'documentation': item.documentation,
        'sortText': item.sortText,
        'filterText': item.filterText,
        'deprecated': item.deprecated,
        'preselect': item.preselect,
      };
    }).toList();
  }
}