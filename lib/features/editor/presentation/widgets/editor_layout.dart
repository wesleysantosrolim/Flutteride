import 'package:material_ui/material_ui.dart';

import '../../models/editor_file_node.dart';
import 'editor_file_explorer.dart';
import 'editor_workspace.dart';

class EditorLayout extends StatelessWidget {
  final String projectName;
  final String projectPath;
  final List<EditorFileNode> nodes;
  final bool isLoading;
  final EditorFileNode? selectedFile;

  final Set<String> expandedPaths;

  final ValueChanged<EditorFileNode>
      onFileSelected;

  final ValueChanged<String>
      onDirectoryToggled;

  final VoidCallback? onRefresh;

  const EditorLayout({
    super.key,
    required this.projectName,
    required this.projectPath,
    required this.nodes,
    required this.isLoading,
    required this.selectedFile,
    required this.expandedPaths,
    required this.onFileSelected,
    required this.onDirectoryToggled,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final isSmallScreen =
            constraints.maxWidth < 700;

        final explorer =
            EditorFileExplorer(
          projectName: projectName,
          projectPath: projectPath,
          nodes: nodes,
          isLoading: isLoading,
          selectedPath:
              selectedFile?.path,
          expandedPaths:
              expandedPaths,
          onFileSelected:
              onFileSelected,
          onDirectoryToggled:
              onDirectoryToggled,
          onRefresh: onRefresh,
          onFileOpened:
              isSmallScreen
                  ? () {
                      Navigator.of(
                        context,
                      ).pop();
                    }
                  : null,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(projectName),
            leading: isSmallScreen
                ? Builder(
                    builder: (context) {
                      return IconButton(
                        tooltip:
                            'Explorador de arquivos',
                        icon: const Icon(
                          Icons.menu_rounded,
                        ),
                        onPressed: () {
                          Scaffold.of(
                            context,
                          ).openDrawer();
                        },
                      );
                    },
                  )
                : null,
          ),
          drawer: isSmallScreen
              ? Drawer(
                  width: 320,
                  child: SafeArea(
                    child: NavigationDrawer(
                      backgroundColor:
                          Theme.of(context)
                              .colorScheme
                              .surface,
                      children: [
                        SizedBox(
                          height:
                              MediaQuery.of(
                            context,
                          ).padding.top,
                        ),
                        SizedBox(
                          height: 48,
                          child: Padding(
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 16,
                            ),
                            child: Align(
                              alignment:
                                  Alignment.centerLeft,
                              child: Text(
                                projectName,
                                style: Theme.of(
                                  context,
                                )
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                    ),
                              ),
                            ),
                          ),
                        ),
                        const Divider(
                          height: 1,
                        ),
                        SizedBox(
                          height:
                              MediaQuery.of(
                                    context,
                                  ).size.height -
                                  100,
                          child: explorer,
                        ),
                      ],
                    ),
                  ),
                )
              : null,
          body: Row(
            children: [
              if (!isSmallScreen) ...[
                SizedBox(
                  width: 300,
                  child: explorer,
                ),
                const VerticalDivider(
                  width: 1,
                ),
              ],
              const Expanded(
                child: EditorWorkspace(),
              ),
            ],
          ),
        );
      },
    );
  }
}