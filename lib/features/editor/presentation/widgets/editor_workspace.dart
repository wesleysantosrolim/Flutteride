import 'package:material_ui/material_ui.dart';

import '../../models/editor_file_node.dart';
import 'monaco/editor_monaco.dart';

class EditorWorkspace extends StatelessWidget {
  final EditorFileNode? selectedFile;
  final String fileContent;
  final bool isLoadingFile;

  const EditorWorkspace({
    super.key,
    this.selectedFile,
    this.fileContent = '',
    this.isLoadingFile = false,
  });

  @override
  Widget build(BuildContext context) {
    final file = selectedFile;

    return Stack(
      fit: StackFit.expand,
      children: [
        EditorMonaco(
          filePath: file?.path,
          fileContent: fileContent,
          visible: file != null && !isLoadingFile,
        ),

        if (file == null)
          Container(
            color: Theme.of(context)
                .scaffoldBackgroundColor,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.code_rounded,
                  size: 64,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Selecione um arquivo',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge,
                ),
              ],
            ),
          ),

        if (file != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context)
                        .dividerColor,
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  const Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),

        if (file != null && isLoadingFile)
          Container(
            color: Theme.of(context)
                .scaffoldBackgroundColor,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          ),
      ],
    );
  }
}