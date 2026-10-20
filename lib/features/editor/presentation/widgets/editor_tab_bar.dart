import 'package:material_ui/material_ui.dart';

import '../../models/editor_file_node.dart';

class EditorTabBar extends StatelessWidget {
  final List<EditorFileNode> openedFiles;
  final String? activePath;
  final ValueChanged<EditorFileNode> onTabSelected;
  final ValueChanged<EditorFileNode> onTabClosed;

  const EditorTabBar({
    super.key,
    required this.openedFiles,
    required this.activePath,
    required this.onTabSelected,
    required this.onTabClosed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (openedFiles.isEmpty) {
      return Container(
        height: 44,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: theme.dividerColor,
            ),
          ),
        ),
      );
    }

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: openedFiles.length,
        itemBuilder: (
          context,
          index,
        ) {
          final file = openedFiles[index];

          final isActive =
              file.path == activePath;

          return _buildTab(
            context,
            file,
            isActive,
          );
        },
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    EditorFileNode file,
    bool isActive,
  ) {
    final theme = Theme.of(context);

    return Material(
      color: isActive
          ? theme.colorScheme.surface
          : theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.35),
      child: InkWell(
        onTap: () {
          onTabSelected(file);
        },
        child: Container(
          constraints: const BoxConstraints(
            minWidth: 120,
            maxWidth: 220,
          ),
          padding: const EdgeInsets.only(
            left: 12,
            right: 4,
          ),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: theme.dividerColor,
              ),
              bottom: isActive
                  ? BorderSide(
                      color:
                          theme.colorScheme.primary,
                      width: 2,
                    )
                  : BorderSide.none,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _fileIcon(file.name),
                size: 17,
                color: _fileColor(
                  context,
                  file.name,
                ),
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  file.name,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                ),
              ),
              const SizedBox(
                width: 4,
              ),
              InkWell(
                borderRadius:
                    BorderRadius.circular(16),
                onTap: () {
                  onTabClosed(file);
                },
                child: const Padding(
                  padding: EdgeInsets.all(5),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _fileIcon(
    String name,
  ) {
    final lower =
        name.toLowerCase();

    if (lower.endsWith('.dart')) {
      return Icons.code_rounded;
    }

    if (lower.endsWith('.yaml') ||
        lower.endsWith('.yml')) {
      return Icons.data_object_rounded;
    }

    if (lower.endsWith('.json')) {
      return Icons.data_object_outlined;
    }

    if (lower.endsWith('.md')) {
      return Icons.description_outlined;
    }

    if (lower.startsWith('.')) {
      return Icons.settings_outlined;
    }

    return Icons.insert_drive_file_outlined;
  }

  Color _fileColor(
    BuildContext context,
    String name,
  ) {
    final lower =
        name.toLowerCase();

    if (lower.endsWith('.dart')) {
      return Theme.of(context)
          .colorScheme
          .primary;
    }

    return Theme.of(context)
        .colorScheme
        .onSurfaceVariant;
  }
}