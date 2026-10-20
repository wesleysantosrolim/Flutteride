import 'package:material_ui/material_ui.dart';

import '../../models/editor_file_node.dart';
import '../../services/editor_file_service.dart';

/// Estrutura plana para representação otimizada com ListView.builder
class _FlatNode {
  final EditorFileNode node;
  final int level;
  final bool isExpanded;

  const _FlatNode({
    required this.node,
    required this.level,
    required this.isExpanded,
  });
}

class EditorFileExplorer extends StatefulWidget {
  final String projectName;
  final String projectPath;
  final List<EditorFileNode> nodes;
  final bool isLoading;
  final String? selectedPath;
  final Set<String> expandedPaths;
  final ValueChanged<EditorFileNode> onFileSelected;
  final ValueChanged<String> onDirectoryToggled;
  final VoidCallback? onRefresh;
  final VoidCallback? onFileOpened;

  const EditorFileExplorer({
    super.key,
    required this.projectName,
    required this.projectPath,
    required this.nodes,
    required this.isLoading,
    required this.selectedPath,
    required this.expandedPaths,
    required this.onFileSelected,
    required this.onDirectoryToggled,
    this.onRefresh,
    this.onFileOpened,
  });

  @override
  State<EditorFileExplorer> createState() => _EditorFileExplorerState();
}

class _EditorFileExplorerState extends State<EditorFileExplorer> {
  late final EditorFileService _fileService;
  bool _operationInProgress = false;

  @override
  void initState() {
    super.initState();
    _fileService = EditorFileService();
  }

  /// Achata a hierarquia recursiva em uma lista plana considerando apenas os caminhos expandidos
  List<_FlatNode> _buildFlattenedTree() {
    final List<_FlatNode> flatList = [];

    final rootNode = EditorFileNode(
      name: widget.projectName,
      path: widget.projectPath,
      type: EditorFileNodeType.directory,
      children: widget.nodes,
    );

    void traverse(EditorFileNode node, int level) {
      final isExpanded = widget.expandedPaths.contains(node.path);
      flatList.add(_FlatNode(
        node: node,
        level: level,
        isExpanded: isExpanded,
      ));

      if (node.isDirectory && isExpanded) {
        for (final child in node.children) {
          traverse(child, level + 1);
        }
      }
    }

    traverse(rootNode, 0);
    return flatList;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          _buildHeader(context),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.dividerColor.withValues(alpha: 0.55),
          ),
          Expanded(
            child: Stack(
              children: [
                _buildTree(context),
                if (_operationInProgress)
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: 0.45),
                      child: const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'EXPLORADOR',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Atualizar arquivos',
              onPressed: widget.isLoading || _operationInProgress
                  ? null
                  : widget.onRefresh,
              splashRadius: 19,
              icon: Icon(
                Icons.refresh_rounded,
                size: 20,
                color: widget.isLoading || _operationInProgress
                    ? colorScheme.onSurface.withValues(alpha: 0.35)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTree(BuildContext context) {
    if (widget.isLoading && widget.nodes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final flatNodes = _buildFlattenedTree();

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      itemCount: flatNodes.length,
      itemExtent: 34.0,
      itemBuilder: (context, index) {
        final flatNode = flatNodes[index];
        final node = flatNode.node;

        if (node.isDirectory) {
          return _buildDirectoryItem(
            context,
            node,
            flatNode.level,
            flatNode.isExpanded,
          );
        }

        return _buildFileItem(
          context,
          node,
          flatNode.level,
        );
      },
    );
  }

  Widget _buildFileItem(
    BuildContext context,
    EditorFileNode node,
    int level,
  ) {
    final selected = widget.selectedPath == node.path;

    return _ExplorerTreeItem(
      key: ValueKey(node.path),
      selected: selected,
      onTap: () {
        widget.onFileSelected(node);
        widget.onFileOpened?.call();
      },
      onLongPress: (position) => _showFileMenu(context, node, position),
      child: Padding(
        padding: EdgeInsets.only(left: 10 + (level * 18), right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Icon(
                _fileIcon(node.name),
                size: 17,
                color: _fileColor(context, node.name),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectoryItem(
    BuildContext context,
    EditorFileNode node,
    int level,
    bool isExpanded,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isRoot = level == 0;

    return _ExplorerTreeItem(
      key: ValueKey(node.path),
      onTap: () => widget.onDirectoryToggled(node.path),
      onLongPress: (position) => _showDirectoryMenu(context, node, position),
      child: Padding(
        padding: EdgeInsets.only(left: 5 + (level * 18), right: 8),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(
              width: 20,
              child: Icon(
                isExpanded ? Icons.folder_open_rounded : Icons.folder_rounded,
                size: 17,
                color: _folderColor(context, isRoot: isRoot),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: isRoot ? FontWeight.w600 : FontWeight.w400,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDirectoryMenu(
    BuildContext context,
    EditorFileNode node,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: _menuPosition(context, position),
      items: const [
        PopupMenuItem<String>(
          value: 'new_file',
          child: _ExplorerMenuItem(
            icon: Icons.note_add_outlined,
            label: 'Novo arquivo',
          ),
        ),
        PopupMenuItem<String>(
          value: 'new_folder',
          child: _ExplorerMenuItem(
            icon: Icons.create_new_folder_outlined,
            label: 'Nova pasta',
          ),
        ),
        PopupMenuItem<String>(
          value: 'import_file',
          child: _ExplorerMenuItem(
            icon: Icons.file_upload_outlined,
            label: 'Importar arquivo',
          ),
        ),
        PopupMenuItem<String>(
          value: 'import_folder',
          child: _ExplorerMenuItem(
            icon: Icons.drive_folder_upload_outlined,
            label: 'Importar pasta',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'export',
          child: _ExplorerMenuItem(
            icon: Icons.file_download_outlined,
            label: 'Exportar',
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: _ExplorerMenuItem(
            icon: Icons.copy_outlined,
            label: 'Copiar',
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: _ExplorerMenuItem(
            icon: Icons.content_paste_outlined,
            label: 'Colar',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'rename',
          child: _ExplorerMenuItem(
            icon: Icons.drive_file_rename_outline,
            label: 'Renomear',
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: _ExplorerMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Deletar',
          ),
        ),
      ],
    );

    if (!mounted || !context.mounted || action == null) return;

    switch (action) {
      case 'new_file':
        await _createFile(context, node);
        break;
      case 'new_folder':
        await _createFolder(context, node);
        break;
      case 'import_file':
        await _importFile(context, node);
        break;
      case 'import_folder':
        await _importFolder(context, node);
        break;
      case 'export':
        await _export(context, node);
        break;
      case 'copy':
        await _copy(context, node);
        break;
      case 'paste':
        await _paste(context, node);
        break;
      case 'rename':
        await _rename(context, node);
        break;
      case 'delete':
        await _delete(context, node);
        break;
    }
  }

  Future<void> _showFileMenu(
    BuildContext context,
    EditorFileNode node,
    Offset position,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: _menuPosition(context, position),
      items: const [
        PopupMenuItem<String>(
          value: 'rename',
          child: _ExplorerMenuItem(
            icon: Icons.drive_file_rename_outline,
            label: 'Renomear',
          ),
        ),
        PopupMenuItem<String>(
          value: 'copy',
          child: _ExplorerMenuItem(
            icon: Icons.copy_outlined,
            label: 'Copiar',
          ),
        ),
        PopupMenuItem<String>(
          value: 'paste',
          child: _ExplorerMenuItem(
            icon: Icons.content_paste_outlined,
            label: 'Colar',
          ),
        ),
        PopupMenuItem<String>(
          value: 'export',
          child: _ExplorerMenuItem(
            icon: Icons.file_download_outlined,
            label: 'Exportar',
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: _ExplorerMenuItem(
            icon: Icons.delete_outline_rounded,
            label: 'Deletar',
          ),
        ),
      ],
    );

    if (!mounted || !context.mounted || action == null) return;

    switch (action) {
      case 'rename':
        await _rename(context, node);
        break;
      case 'copy':
        await _copy(context, node);
        break;
      case 'paste':
        final parent = _parentPath(node.path);
        if (parent == null) {
          await _showError(
            context,
            'Não foi possível determinar a pasta de destino.',
          );
          return;
        }
        await _pastePath(context, parent);
        break;
      case 'export':
        await _export(context, node);
        break;
      case 'delete':
        await _delete(context, node);
        break;
    }
  }

  Future<void> _createFile(
    BuildContext context,
    EditorFileNode directory,
  ) async {
    final name = await _askName(
      context,
      title: 'Novo arquivo',
      label: 'Nome do arquivo',
      hint: 'exemplo.dart',
      confirmLabel: 'Criar',
    );

    if (!mounted || !context.mounted || name == null) return;

    // Garante que a pasta pai esteja expandida para visualização imediata
    if (!widget.expandedPaths.contains(directory.path)) {
      widget.onDirectoryToggled(directory.path);
    }

    await _runOperation(
      context,
      operation: () => _fileService.createFile(directory.path, name),
    );
  }

  Future<void> _createFolder(
    BuildContext context,
    EditorFileNode directory,
  ) async {
    final name = await _askName(
      context,
      title: 'Nova pasta',
      label: 'Nome da pasta',
      hint: 'nova_pasta',
      confirmLabel: 'Criar',
    );

    if (!mounted || !context.mounted || name == null) return;

    if (!widget.expandedPaths.contains(directory.path)) {
      widget.onDirectoryToggled(directory.path);
    }

    await _runOperation(
      context,
      operation: () => _fileService.createDirectory(directory.path, name),
    );
  }

  Future<void> _importFile(
    BuildContext context,
    EditorFileNode directory,
  ) async {
    await _runOperation(
      context,
      operation: () => _fileService.importFile(directory.path),
    );
  }

  Future<void> _importFolder(
    BuildContext context,
    EditorFileNode directory,
  ) async {
    await _runOperation(
      context,
      operation: () => _fileService.importDirectory(directory.path),
    );
  }

  Future<void> _export(
    BuildContext context,
    EditorFileNode node,
  ) async {
    await _runOperation(
      context,
      operation: () => _fileService.export(node.path),
    );
  }

  Future<void> _copy(
    BuildContext context,
    EditorFileNode node,
  ) async {
    await _runOperation(
      context,
      operation: () => _fileService.copy(node.path),
    );
  }

  Future<void> _paste(
    BuildContext context,
    EditorFileNode directory,
  ) async {
    await _pastePath(context, directory.path);
  }

  Future<void> _pastePath(
    BuildContext context,
    String destinationPath,
  ) async {
    await _runOperation(
      context,
      operation: () => _fileService.paste(destinationPath),
    );
  }

  Future<void> _rename(
    BuildContext context,
    EditorFileNode node,
  ) async {
    final name = await _askName(
      context,
      title: 'Renomear',
      label: 'Novo nome',
      initialValue: node.name,
      confirmLabel: 'Renomear',
    );

    if (!mounted || !context.mounted || name == null) return;

    await _runOperation(
      context,
      operation: () => _fileService.rename(node.path, name),
    );
  }

  Future<void> _delete(
    BuildContext context,
    EditorFileNode node,
  ) async {
    final confirmed = await _confirmDelete(context, node);

    if (!mounted || !context.mounted || !confirmed) return;

    await _runOperation(
      context,
      operation: () => _fileService.delete(node.path),
    );
  }

  Future<String?> _askName(
    BuildContext context, {
    required String title,
    required String label,
    required String confirmLabel,
    String? hint,
    String? initialValue,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');

    final result = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              final value = controller.text.trim();
              if (value.isNotEmpty) {
                Navigator.of(dialogContext).pop(value);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isEmpty) return;
                Navigator.of(dialogContext).pop(value);
              },
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );

    // Aguarda a animação do diálogo fechar antes de descartar o controller
    await Future.delayed(const Duration(milliseconds: 200));
    controller.dispose();
    return result;
  }

  Future<bool> _confirmDelete(
    BuildContext context,
    EditorFileNode node,
  ) async {
    final isDirectory = node.isDirectory;

    return await showDialog<bool>(
          context: context,
          useRootNavigator: true,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                isDirectory ? 'Deletar pasta?' : 'Deletar arquivo?',
              ),
              content: Text(
                isDirectory
                    ? 'A pasta "${node.name}" e todo o seu conteúdo serão removidos. Essa ação não pode ser desfeita.'
                    : 'O arquivo "${node.name}" será removido. Essa ação não pode ser desfeita.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Deletar'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _runOperation(
    BuildContext context, {
    required Future<dynamic> Function() operation,
  }) async {
    if (_operationInProgress || !mounted) return;

    // Aguarda o encerramento das animações de diálogo/menu antes de reconstruir a árvore
    await Future.delayed(Duration.zero);
    if (!mounted) return;

    setState(() {
      _operationInProgress = true;
    });

    Object? operationError;

    try {
      await operation();
    } catch (error) {
      operationError = error;
    }

    if (!mounted) return;

    if (operationError != null) {
      setState(() {
        _operationInProgress = false;
      });

      if (!mounted || !context.mounted) return;

      await _showError(
        context,
        _friendlyError(operationError!),
      );

      return;
    }

    _refreshTree();

    if (!mounted) return;

    setState(() {
      _operationInProgress = false;
    });
  }

  void _refreshTree() {
    widget.onRefresh?.call();
  }

  Future<void> _showError(BuildContext context, String message) async {
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Não foi possível concluir'),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  String? _parentPath(String path) {
    final normalized = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;

    final index = normalized.lastIndexOf('/');
    if (index <= 0) return null;

    return normalized.substring(0, index);
  }

  RelativeRect _menuPosition(BuildContext context, Offset position) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(position);

    return RelativeRect.fromLTRB(
      localPosition.dx,
      localPosition.dy,
      overlay.size.width - localPosition.dx,
      overlay.size.height - localPosition.dy,
    );
  }

  IconData _fileIcon(String name) {
    final lower = name.toLowerCase();

    if (lower.endsWith('.dart')) return Icons.code_rounded;
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return Icons.data_object_rounded;
    }
    if (lower.endsWith('.json')) return Icons.data_object_outlined;
    if (lower.endsWith('.xml')) return Icons.code_rounded;
    if (lower.endsWith('.html')) return Icons.language_rounded;
    if (lower.endsWith('.css')) return Icons.palette_outlined;
    if (lower.endsWith('.js') || lower.endsWith('.ts')) {
      return Icons.javascript_rounded;
    }
    if (lower.endsWith('.md')) return Icons.description_outlined;
    if (lower.endsWith('.gitignore') || lower.startsWith('.')) {
      return Icons.settings_outlined;
    }

    return Icons.insert_drive_file_outlined;
  }

  Color _fileColor(BuildContext context, String name) {
    final theme = Theme.of(context);
    final lower = name.toLowerCase();

    if (lower.endsWith('.dart')) return const Color(0xFF42A5F5);
    if (lower.endsWith('.json')) return const Color(0xFFFFCA28);
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return const Color(0xFFFF7043);
    }
    if (lower.endsWith('.html') || lower.endsWith('.xml')) {
      return const Color(0xFFE44D26);
    }
    if (lower.endsWith('.css')) return const Color(0xFF42A5F5);
    if (lower.endsWith('.js') || lower.endsWith('.ts')) {
      return const Color(0xFFFFD54F);
    }
    if (lower.endsWith('.md')) return const Color(0xFF90A4AE);

    return theme.brightness == Brightness.dark
        ? const Color(0xFFB0BEC5)
        : const Color(0xFF607D8B);
  }

  Color _folderColor(BuildContext context, {required bool isRoot}) {
    if (isRoot) return const Color(0xFFFFC107);
    return const Color(0xFFFFB300);
  }
}

class _ExplorerTreeItem extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onLongPress;
  final bool selected;

  const _ExplorerTreeItem({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
  });

  @override
  State<_ExplorerTreeItem> createState() => _ExplorerTreeItemState();
}

class _ExplorerTreeItemState extends State<_ExplorerTreeItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color? backgroundColor;

    if (widget.selected) {
      backgroundColor = colorScheme.secondaryContainer.withValues(alpha: 0.78);
    } else if (_hovered) {
      backgroundColor = colorScheme.onSurface.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.06 : 0.045,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (!mounted) return;
        setState(() => _hovered = true);
      },
      onExit: (_) {
        if (!mounted) return;
        setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: widget.onLongPress == null
            ? null
            : (details) => widget.onLongPress!(details.globalPosition),
        child: Material(
          color: backgroundColor ?? Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: Colors.transparent,
            splashColor: colorScheme.primary.withValues(alpha: 0.08),
            highlightColor: Colors.transparent,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _ExplorerMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ExplorerMenuItem({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Icon(
            icon,
            size: 19,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 10),
        Text(label),
      ],
    );
  }
}
