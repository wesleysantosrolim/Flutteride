import 'package:flutter_monaco/flutter_monaco.dart';

/// Ações disponíveis para o Editor.
///
/// Esta classe concentra comandos diretamente relacionados
/// ao Monaco Editor, mantendo o EditorScreen responsável
/// apenas pelo estado e pela coordenação da tela.
class EditorActions {
  const EditorActions._();

  /// Desfaz a última alteração no documento ativo.
  static Future<void> undo(
    MonacoController? controller,
  ) async {
    if (controller == null) return;

    await controller.executeAction(
      MonacoAction.undo,
    );
  }

  /// Refaz a última alteração desfeita no documento ativo.
  static Future<void> redo(
    MonacoController? controller,
  ) async {
    if (controller == null) return;

    await controller.executeAction(
      MonacoAction.redo,
    );
  }

  /// Abre a pesquisa nativa do Monaco Editor.
  static Future<void> find(
    MonacoController? controller,
  ) async {
    if (controller == null) return;

    await controller.executeAction(
      MonacoAction.find,
    );
  }

  /// Obtém o conteúdo atual do documento Monaco.
  ///
  /// O salvamento físico do arquivo é realizado pelo
  /// EditorFileService.
  static Future<String?> save(
    MonacoDocument? document,
  ) async {
    if (document == null) {
      return null;
    }

    return document.getText();
  }
}