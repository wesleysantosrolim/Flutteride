import 'package:material_ui/material_ui.dart';

import '../../models/home_project.dart';

class HomeProjectCard extends StatelessWidget {
  final HomeProject project;

  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const HomeProjectCard({
    super.key,
    required this.project,
    required this.onOpen,
    required this.onRename,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 4,
        ),
        leading: const Icon(
          Icons.flutter_dash,
          size: 36,
        ),
        title: Text(
          project.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Modificado em: '
          '${_formatDate(project.lastModified)}',
        ),
        trailing: PopupMenuButton<_ProjectAction>(
          tooltip: 'Gerenciar projeto',
          onSelected: (action) {
            switch (action) {
              case _ProjectAction.open:
                onOpen();
                break;

              case _ProjectAction.rename:
                onRename();
                break;

              case _ProjectAction.export:
                onExport();
                break;

              case _ProjectAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) {
            return const [
              PopupMenuItem(
                value: _ProjectAction.open,
                child: ListTile(
                  leading: Icon(Icons.folder_open),
                  title: Text('Abrir'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _ProjectAction.rename,
                child: ListTile(
                  leading: Icon(Icons.drive_file_rename_outline),
                  title: Text('Renomear'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _ProjectAction.export,
                child: ListTile(
                  leading: Icon(Icons.ios_share),
                  title: Text('Exportar'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _ProjectAction.delete,
                child: ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    color: Colors.red,
                  ),
                  title: Text(
                    'Excluir',
                    style: TextStyle(
                      color: Colors.red,
                    ),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ];
          },
        ),
        onTap: onOpen,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }
}

enum _ProjectAction {
  open,
  rename,
  export,
  delete,
}