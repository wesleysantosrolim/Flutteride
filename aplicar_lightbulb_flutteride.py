#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Aplica a integração inicial do botão de Ações de Código (lâmpada) ao FlutterIDE.
Executar na raiz do repositório. Cria backups .bak antes de alterar os arquivos.
Lê e grava explicitamente em UTF-8.
"""
from pathlib import Path
import sys

ROOT = Path.cwd()

FILES = {
    "monaco": ROOT / "lib/features/editor/presentation/widgets/monaco/editor_monaco.dart",
    "area": ROOT / "lib/features/editor/presentation/screens/editor_area.dart",
    "screen": ROOT / "lib/features/editor/presentation/screens/editor_screen.dart",
}

def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"Não foi possível aplicar '{label}': esperado 1 trecho, encontrado {count}. "
            "Nenhum arquivo foi alterado."
        )
    return text.replace(old, new, 1)

def read(path):
    if not path.is_file():
        raise FileNotFoundError(f"Arquivo não encontrado: {path}")
    return path.read_text(encoding="utf-8")

def main():
    original = {key: read(path) for key, path in FILES.items()}
    updated = dict(original)

    # editor_monaco.dart
    c = updated["monaco"]
    changes = [
        (
            "import 'package:flutteride/features/editor/services/editor_autocomplete_file_logger.dart';",
            "import 'package:flutteride/features/editor/services/editor_autocomplete_file_logger.dart';\n"
            "import 'package:flutteride/features/editor/services/editor_code_action_service.dart';",
            "importar EditorCodeActionService",
        ),
        (
            "  final EditorMonacoSyncService? syncService;",
            "  final EditorMonacoSyncService? syncService;\n"
            "  final EditorCodeActionService? codeActionService;",
            "campo codeActionService",
        ),
        (
            "    this.syncService,\n  });",
            "    this.syncService,\n    this.codeActionService,\n  });",
            "parâmetro codeActionService",
        ),
        (
            "  bool _isSyncingContent = false;\n  bool _syncPending = false;",
            "  bool _isSyncingContent = false;\n  bool _syncPending = false;\n  bool _isLoadingCodeActions = false;",
            "estado de carregamento",
        ),
        (
            "    widget.syncService?.attachMonacoController(controller);",
            "    widget.syncService?.attachMonacoController(controller);\n"
            "    widget.codeActionService?.attachController(controller);\n"
            "    widget.codeActionService?.setActiveFile(widget.filePath);",
            "conectar serviço no Monaco",
        ),
        (
            "    final fileChanged = oldWidget.filePath != widget.filePath;\n\n"
            "    final contentChanged = oldWidget.fileContent != widget.fileContent;",
            "    final fileChanged = oldWidget.filePath != widget.filePath;\n\n"
            "    if (fileChanged) {\n"
            "      widget.codeActionService?.setActiveFile(widget.filePath);\n"
            "    }\n\n"
            "    final contentChanged = oldWidget.fileContent != widget.fileContent;",
            "atualizar arquivo ativo",
        ),
        (
            "  @override\n  Widget build(BuildContext context) {\n    final theme = Theme.of(context);",
            """  Future<void> _showCodeActions() async {
    final controller = _controller;
    final service = widget.codeActionService;
    final path = widget.filePath;

    if (!mounted ||
        controller == null ||
        service == null ||
        path == null ||
        _isLoadingCodeActions ||
        !_ready) {
      return;
    }

    setState(() => _isLoadingCodeActions = true);

    try {
      await controller.whenReady;

      final cursor = await controller.getCursorPosition();
      if (cursor == null || !mounted) return;

      final documentText = await controller.document.getText();
      final actions = await service.requestActions(
        path: path,
        line: cursor.line > 0 ? cursor.line - 1 : 0,
        character: cursor.column > 0 ? cursor.column - 1 : 0,
        documentText: documentText,
      );

      if (!mounted) return;

      if (actions.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Nenhuma ação de código disponível nesta posição.',
            ),
          ),
        );
        return;
      }

      final selectedAction = await showModalBottomSheet<DartCodeAction>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Ações de código',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final action in actions)
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(action.title),
                  subtitle:
                      action.kind == null ? null : Text(action.kind!),
                  onTap: () => Navigator.of(sheetContext).pop(action),
                ),
            ],
          ),
        ),
      );

      if (selectedAction == null || !mounted) return;

      await service.applyAction(
        action: selectedAction,
        activeFilePath: path,
      );

      final updatedText = await controller.document.getText();
      if (!mounted || widget.filePath != path) return;

      widget.onContentChanged?.call(updatedText);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Não foi possível executar a ação: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingCodeActions = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);""",
            "método para solicitar/aplicar ações",
        ),
        (
            "          if (!widget.visible || !_ready)\n            Container(",
            """          if (widget.visible &&
              _ready &&
              widget.filePath?.toLowerCase().endsWith('.dart') == true &&
              widget.codeActionService != null)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Ações de código',
                  onPressed:
                      _isLoadingCodeActions ? null : _showCodeActions,
                  icon: _isLoadingCodeActions
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lightbulb_outline),
                ),
              ),
            ),
          if (!widget.visible || !_ready)
            Container(""",
            "botão visual da lâmpada",
        ),
    ]
    for old, new, label in changes:
        c = replace_once(c, old, new, label)
    updated["monaco"] = c

    # editor_area.dart
    c = updated["area"]
    changes = [
        (
            "import '../../services/editor_monaco_sync_service.dart';",
            "import '../../services/editor_monaco_sync_service.dart';\n"
            "import '../../services/editor_code_action_service.dart';",
            "importar serviço na área",
        ),
        (
            "  final EditorMonacoSyncService? syncService;",
            "  final EditorMonacoSyncService? syncService;\n"
            "  final EditorCodeActionService? codeActionService;",
            "campo do serviço na área",
        ),
        (
            "    this.syncService,\n  });",
            "    this.syncService,\n    this.codeActionService,\n  });",
            "parâmetro do serviço na área",
        ),
        (
            "            syncService: syncService,",
            "            syncService: syncService,\n"
            "            codeActionService: codeActionService,",
            "encaminhar serviço para Monaco",
        ),
    ]
    for old, new, label in changes:
        c = replace_once(c, old, new, label)
    updated["area"] = c

    # editor_screen.dart
    c = updated["screen"]
    changes = [
        (
            "import '../../services/editor_monaco_completion_service.dart';",
            "import '../../services/editor_monaco_completion_service.dart';\n"
            "import '../../services/editor_code_action_service.dart';",
            "importar serviço na tela",
        ),
        (
            "  late final EditorMonacoCompletionService _completionService;",
            "  late final EditorMonacoCompletionService _completionService;\n\n"
            "  late final EditorCodeActionService _codeActionService;",
            "declarar serviço na tela",
        ),
        (
            "    _completionService = EditorMonacoCompletionService(\n"
            "      analysisCoordinator: _analysisCoordinator,\n"
            "    );",
            "    _completionService = EditorMonacoCompletionService(\n"
            "      analysisCoordinator: _analysisCoordinator,\n"
            "    );\n\n"
            "    _codeActionService = EditorCodeActionService(\n"
            "      analysisCoordinator: _analysisCoordinator,\n"
            "    );",
            "criar serviço na tela",
        ),
        (
            "    _completionService.dispose();\n"
            "    _monacoSyncService.dispose();",
            "    _completionService.dispose();\n"
            "    _codeActionService.dispose();\n"
            "    _monacoSyncService.dispose();",
            "descartar serviço",
        ),
        (
            "                                  syncService: _monacoSyncService,",
            "                                  syncService: _monacoSyncService,\n"
            "                                  codeActionService: _codeActionService,",
            "encaminhar serviço para EditorArea",
        ),
    ]
    for old, new, label in changes:
        c = replace_once(c, old, new, label)
    updated["screen"] = c

    # Todas as verificações são feitas antes de gravar qualquer arquivo.
    for key, path in FILES.items():
        backup = path.with_suffix(path.suffix + ".lightbulb.bak")
        if backup.exists():
            raise FileExistsError(
                f"Backup já existe: {backup}. Renomeie/remova o backup antes de executar."
            )

    try:
        for key, path in FILES.items():
            backup = path.with_suffix(path.suffix + ".lightbulb.bak")
            backup.write_text(original[key], encoding="utf-8")
        for key, path in FILES.items():
            path.write_text(updated[key], encoding="utf-8")
    except Exception:
        # Restaura os originais se houver falha durante a gravação.
        for key, path in FILES.items():
            if path.exists():
                path.write_text(original[key], encoding="utf-8")
        raise

    print("Integração inicial aplicada nos três arquivos:")
    for path in FILES.values():
        print(f"  {path.relative_to(ROOT)}")
    print("Backups UTF-8 criados com o sufixo .lightbulb.bak")
    print()
    print("Agora execute: dart format nos três arquivos e flutter analyze.")
    print("A lâmpada atual é um botão para solicitar ações; não é ainda uma lâmpada")
    print("automática ancorada na margem nem filtra quick fixes pelos diagnostics.")

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERRO: {exc}", file=sys.stderr)
        print("Os arquivos não foram alterados se a validação inicial falhou.", file=sys.stderr)
        sys.exit(1)
