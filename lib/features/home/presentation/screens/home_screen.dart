import 'package:material_ui/material_ui.dart';

import '../../models/home_project.dart';
import '../../services/home_project_service.dart';
import '../../../editor/presentation/screens/editor_screen.dart';
import '../widgets/home_app_bar.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_project_action.dart';
import '../widgets/home_project_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
  });

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState
    extends State<HomeScreen> {
  final HomeProjectService _projectService =
      HomeProjectService();

  List<HomeProject> _projects = [];

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _loadProjects();
  }

  Future<void> _loadProjects() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final projects =
          await _projectService.listProjects();

      if (!mounted) {
        return;
      }

      setState(() {
        _projects = projects;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });

      _showMessage(
        'Erro ao carregar projetos: $error',
      );
    }
  }

  void _openProject(
    HomeProject project,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          projectName: project.name,
          projectPath: project.path,
        ),
      ),
    );
  }

  Future<void> _renameProject(
    HomeProject project,
  ) async {
    final controller =
        TextEditingController(
      text: project.name,
    );

    final newName =
        await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Renomear projeto',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction:
                TextInputAction.done,
            decoration:
                const InputDecoration(
              labelText: 'Nome do projeto',
              hintText: 'Digite o novo nome',
            ),
            onSubmitted: (_) {
              Navigator.of(context).pop(
                controller.text.trim(),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(
                  controller.text.trim(),
                );
              },
              child: const Text(
                'Renomear',
              ),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == project.name) {
      return;
    }

    try {
      await _projectService.renameProject(
        project.path,
        newName.trim(),
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Projeto renomeado com sucesso.',
      );

      await _loadProjects();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Erro ao renomear projeto: $error',
      );
    }
  }

  Future<void> _deleteProject(
    HomeProject project,
  ) async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Excluir projeto?',
          ),
          content: Text(
            'O projeto "${project.name}" '
            'e todos os seus arquivos serão '
            'removidos permanentemente.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  false,
                );
              },
              child: const Text(
                'Cancelar',
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .error,
                foregroundColor:
                    Theme.of(context)
                        .colorScheme
                        .onError,
              ),
              onPressed: () {
                Navigator.of(context).pop(
                  true,
                );
              },
              child: const Text(
                'Excluir',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _projectService.deleteProject(
        project.path,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Projeto "${project.name}" excluído.',
      );

      await _loadProjects();
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Erro ao excluir projeto: $error',
      );
    }
  }

  Future<void> _exportProject(
    HomeProject project,
  ) async {
    _showMessage(
      'Exportando "${project.name}"...',
    );

    try {
      final archivePath =
          await _projectService.exportProject(
        project.path,
      );

      if (!mounted) {
        return;
      }

      _showMessage(
        'Projeto exportado para:\n'
        '$archivePath',
        duration: const Duration(
          seconds: 5,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        'Erro ao exportar projeto: $error',
        duration: const Duration(
          seconds: 5,
        ),
      );
    }
  }

  void _showMessage(
    String message, {
    Duration duration =
        const Duration(
      seconds: 3,
    ),
  }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HomeAppBar(
        onRefresh: _loadProjects,
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
      floatingActionButton:
          HomeProjectAction(
        onProjectCreated: _loadProjects,
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_projects.isEmpty) {
      return const HomeEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _projects.length,
      itemBuilder: (
        context,
        index,
      ) {
        final project =
            _projects[index];

        return HomeProjectCard(
          project: project,
          onOpen: () {
            _openProject(project);
          },
          onRename: () {
            _renameProject(project);
          },
          onExport: () {
            _exportProject(project);
          },
          onDelete: () {
            _deleteProject(project);
          },
        );
      },
    );
  }
}