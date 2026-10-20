import 'package:material_ui/material_ui.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../../models/editor_file_node.dart';
import '../../services/editor_monaco_sync_service.dart';
import '../../services/editor_code_action_service.dart';
import '../widgets/monaco/editor_monaco.dart';

class EditorArea extends StatelessWidget {
  final EditorFileNode? selectedFile;
  final List<EditorFileNode> openedFiles;
  final String fileContent;
  final ValueChanged<EditorFileNode> onTabSelected;
  final ValueChanged<EditorFileNode> onTabClosed;
  final void Function(MonacoController) onMonacoReady;
  final ValueChanged<String> onContentChanged;
  final EditorMonacoSyncService? syncService;
  final EditorCodeActionService? codeActionService;

  const EditorArea({
    super.key,
    required this.selectedFile,
    required this.openedFiles,
    required this.fileContent,
    required this.onTabSelected,
    required this.onTabClosed,
    required this.onMonacoReady,
    required this.onContentChanged,
    this.syncService,
    this.codeActionService,
  });

  @override
  Widget build(BuildContext context) {
    if (openedFiles.isEmpty || selectedFile == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.code_rounded,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'Nenhum arquivo aberto',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Barra de abas
        Container(
          height: 40,
          color: Theme.of(context).cardColor,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: openedFiles.length,
            itemBuilder: (context, index) {
              final file = openedFiles[index];
              final isSelected = file.path == selectedFile?.path;

              return InkWell(
                onTap: () => onTabSelected(file),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).scaffoldBackgroundColor
                        : Colors.transparent,
                    border: Border(
                      bottom: BorderSide(
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        file.name.endsWith('.dart')
                            ? Icons.code
                            : Icons.insert_drive_file_outlined,
                        size: 16,
                        color: isSelected
                            ? Theme.of(context).primaryColor
                            : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        file.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => onTabClosed(file),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1, thickness: 1),
        // Área central do editor Monaco
        Expanded(
          child: EditorMonaco(
            filePath: selectedFile?.path,
            fileContent: fileContent,
            visible: selectedFile != null,
            onContentChanged: onContentChanged,
            onControllerReady: onMonacoReady,
            syncService: syncService,
            codeActionService: codeActionService,
          ),
        ),
      ],
    );
  }
}
