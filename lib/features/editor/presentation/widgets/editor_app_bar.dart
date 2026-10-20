import 'package:material_ui/material_ui.dart';

class EditorAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final String projectName;
  final bool isSmallScreen;
  final bool isSaving;
  final bool hasSelectedFile;

  final VoidCallback? onOpenExplorer;
  final VoidCallback? onSave;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onFind;

  const EditorAppBar({
    super.key,
    required this.projectName,
    required this.isSmallScreen,
    required this.isSaving,
    required this.hasSelectedFile,
    this.onOpenExplorer,
    this.onSave,
    this.onUndo,
    this.onRedo,
    this.onFind,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(projectName),
      leading: isSmallScreen
          ? IconButton(
              tooltip: 'Explorador de arquivos',
              icon: const Icon(
                Icons.menu_rounded,
              ),
              onPressed: onOpenExplorer,
            )
          : null,
      actions: [
        IconButton(
          tooltip: 'Salvar',
          onPressed:
              !hasSelectedFile || isSaving
                  ? null
                  : onSave,
          icon: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(
                  Icons.save_rounded,
                ),
        ),
        IconButton(
          tooltip: 'Desfazer',
          onPressed:
              hasSelectedFile ? onUndo : null,
          icon: const Icon(
            Icons.undo_rounded,
          ),
        ),
        IconButton(
          tooltip: 'Refazer',
          onPressed:
              hasSelectedFile ? onRedo : null,
          icon: const Icon(
            Icons.redo_rounded,
          ),
        ),
        IconButton(
          tooltip: 'Pesquisar',
          onPressed:
              hasSelectedFile ? onFind : null,
          icon: const Icon(
            Icons.search_rounded,
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}