import 'package:material_ui/material_ui.dart';

import '../../services/home_project_service.dart';

class HomeProjectAction extends StatefulWidget {
  final Future<void> Function()?
      onProjectCreated;

  const HomeProjectAction({
    super.key,
    this.onProjectCreated,
  });

  @override
  State<HomeProjectAction> createState() =>
      _HomeProjectActionState();
}

class _HomeProjectActionState
    extends State<HomeProjectAction> {
  final HomeProjectService _projectService =
      HomeProjectService();

  final TextEditingController _nameController =
      TextEditingController();

  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _showCreateProjectDialog() async {
    _nameController.clear();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return AlertDialog(
              title: const Text(
                'Novo Projeto Flutter',
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Informe o nome do projeto que será criado em /root/projects.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium,
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    TextField(
                      controller:
                          _nameController,
                      enabled: !_isCreating,
                      autofocus: true,
                      textInputAction:
                          TextInputAction.done,
                      decoration:
                          const InputDecoration(
                        labelText:
                            'Nome do projeto',
                        hintText:
                            'ex: meu_app',
                        prefixIcon:
                            Icon(
                          Icons
                              .create_new_folder_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      'Use letras minúsculas, números e _.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall,
                    ),
                    if (_isCreating) ...[
                      const SizedBox(
                        height: 24,
                      ),
                      const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child: Text(
                              'Executando flutter create...',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (!_isCreating)
                  TextButton(
                    onPressed: () {
                      Navigator.of(
                        dialogContext,
                      ).pop();
                    },
                    child: const Text(
                      'Cancelar',
                    ),
                  ),
                FilledButton(
                  onPressed: _isCreating
                      ? null
                      : () async {
                          await _createProject(
                            dialogContext,
                            setDialogState,
                          );
                        },
                  child: const Text(
                    'Criar',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createProject(
    BuildContext dialogContext,
    void Function(
      void Function(),
    ) setDialogState,
  ) async {
    final name = _nameController.text
        .trim()
        .toLowerCase();

    if (!_isValidProjectName(name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Informe um nome válido para o projeto.',
          ),
        ),
      );

      return;
    }

    setState(() {
      _isCreating = true;
    });

    setDialogState(() {});

    final result =
        await _projectService.createProject(
      name,
    );

    if (!mounted ||
        !dialogContext.mounted) {
      return;
    }

    setState(() {
      _isCreating = false;
    });

    if (!result.success) {
      setDialogState(() {});

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Não foi possível criar "$name".',
          ),
          duration:
              const Duration(seconds: 5),
        ),
      );

      return;
    }

    Navigator.of(dialogContext).pop();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          'Projeto "$name" criado com sucesso.',
        ),
      ),
    );

    await widget.onProjectCreated?.call();
  }

  bool _isValidProjectName(
    String name,
  ) {
    if (name.isEmpty) {
      return false;
    }

    return RegExp(
      r'^[a-z][a-z0-9_]*$',
    ).hasMatch(name);
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _isCreating
          ? null
          : _showCreateProjectDialog,
      icon: const Icon(
        Icons.add,
      ),
      label: const Text(
        'Novo Projeto',
      ),
    );
  }
}