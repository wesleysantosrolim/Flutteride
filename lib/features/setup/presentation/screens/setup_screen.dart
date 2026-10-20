import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/sdk_component.dart';
import '../../models/sdk_file.dart';
import '../../services/sdk_detector_service.dart';
import '../../services/sdk_installer_service.dart';

import '../../../terminal/presentation/screens/terminal_screen.dart';


class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
  });

  @override
  State<SetupScreen> createState() =>
      _SetupScreenState();
}

class _SetupScreenState
    extends State<SetupScreen> {
  final SDKInstallerService _installer =
      SDKInstallerService();

  final SDKDetectorService _detector =
      SDKDetectorService();

  late List<SDKComponent> _components;

  bool _loading = true;
  bool _installing = false;

  @override
  void initState() {
    super.initState();

    _components =
        _createComponents();

    _restoreInstallationState();
  }

  List<SDKComponent> _createComponents() {
    return [
      SDKComponent(
        type:
            SDKComponentType.flutter,
        name: 'Flutter',
        description:
            'Framework Flutter para desenvolvimento.',
        expectedArchitecture:
            'Linux ARM64',
        expectedFileExtension:
            '.tar.gz',
      ),
      SDKComponent(
        type:
            SDKComponentType.java,
        name: 'Java / JDK 17',
        description:
            'Java Development Kit utilizado pelo Gradle e Android.',
        expectedArchitecture:
            'Linux ARM64',
        expectedFileExtension:
            '.tar.gz',
      ),
      SDKComponent(
        type:
            SDKComponentType.androidSdk,
        name: 'Android SDK',
        description:
            'Pacote completo do Android SDK, incluindo Platform Tools, Build Tools, Platforms e NDK.',
        expectedFileExtension:
            '.tar.gz',
      ),
    ];
  }

  Future<void>
      _restoreInstallationState() async {
    try {
      await _installer
          .restoreComponentStates(
        _components,
      );
    } catch (e) {
      debugPrint(
        'Erro ao restaurar estado da instalação: $e',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
    });
  }

  Future<void> _selectFile(
    SDKComponent component,
  ) async {
    if (_installing) {
      return;
    }

    try {
      final selected =
          await FilePicker.pickFile();

      if (selected == null) {
        return;
      }

      final path =
          selected.path;

      if (path == null ||
          path.isEmpty) {
        _showMessage(
          'Não foi possível obter o caminho do arquivo selecionado.',
        );

        return;
      }

      final sdkFile =
          SDKFile.fromPath(
        path: path,
        componentType:
            component.type,
      );

      final detection =
          await _detector.detect(
        sdkFile,
      );

      if (!detection.success) {
        _showMessage(
          detection.message,
        );

        return;
      }

      if (!_detector.isCompatible(
        component.type,
        detection,
      )) {
        _showMessage(
          'Este arquivo parece ser '
          '${_componentName(detection.componentType)}, '
          'mas foi selecionado para '
          '${component.name}.',
        );

        return;
      }

      if (!_isSupportedExtension(
        selected.name,
        component.expectedFileExtension,
      )) {
        _showMessage(
          'Formato inválido para '
          '${component.name}.',
        );

        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        component.selectFile(
          path,
        );
      });

      _showMessage(
        '${selected.name} selecionado '
        '(${sdkFile.formattedSize}).',
      );
    } catch (e) {
      debugPrint(
        'Erro ao selecionar arquivo: $e',
      );

      _showMessage(
        'Erro ao selecionar o arquivo: $e',
      );
    }
  }

  bool _isSupportedExtension(
    String fileName,
    String? expectedExtension,
  ) {
    if (expectedExtension == null ||
        expectedExtension.isEmpty) {
      return true;
    }

    final normalized =
        fileName.toLowerCase();

    switch (expectedExtension
        .toLowerCase()) {
      case '.tar.gz':
        return normalized.endsWith(
              '.tar.gz',
            ) ||
            normalized.endsWith(
              '.tgz',
            );

      case '.tar.xz':
        return normalized.endsWith(
          '.tar.xz',
        );

      case '.zip':
        return normalized.endsWith(
          '.zip',
        );

      default:
        return normalized.endsWith(
          expectedExtension.toLowerCase(),
        );
    }
  }

  Future<void> _installComponent(
    SDKComponent component,
  ) async {
    if (_installing) {
      return;
    }

    final selectedPath =
        component.selectedFilePath;

    if (selectedPath == null ||
        selectedPath.isEmpty) {
      _showMessage(
        'Selecione um arquivo primeiro.',
      );

      return;
    }

    final source =
        File(selectedPath);

    if (!await source.exists()) {
      _showMessage(
        'O arquivo selecionado não existe mais.',
      );

      return;
    }

    if (component.isInstalled) {
      _showMessage(
        '${component.name} já está instalado.',
      );

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _installing = true;
      component.startInstallation();
    });

    try {
      final sdkFile =
          SDKFile.fromPath(
        path: selectedPath,
        componentType:
            component.type,
      );

      final detection =
          await _detector.detect(
        sdkFile,
      );

      if (!detection.success) {
        throw Exception(
          detection.message,
        );
      }

      if (!_detector.isCompatible(
        component.type,
        detection,
      )) {
        throw Exception(
          'O arquivo selecionado não corresponde '
          'ao componente ${component.name}.',
        );
      }

      var installationError =
          false;

      String? installationErrorMessage;

      await for (
        final progress
        in _installer.install(
          sdkFile,
          component.type,
        )
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          component.updateProgress(
            progress.progress,
          );
        });

        if (progress.progress <= 0) {
          installationError = true;
          installationErrorMessage =
              progress.message;
        }
      }

      if (installationError) {
        throw Exception(
          installationErrorMessage ??
              'Erro durante a instalação.',
        );
      }

      final installedPath =
          await _installer
              .getInstalledPath(
        component.type,
      );

      if (installedPath == null) {
        throw Exception(
          'A instalação terminou, mas '
          'o componente não pôde ser validado.',
        );
      }

      final validation =
          await _installer
              .validateInstallation(
        component.type,
        installedPath,
      );

      if (!validation.success) {
        throw Exception(
          validation.message,
        );
      }

      if (mounted) {
        setState(() {
          component.markInstalled(
            validation.installPath ??
                installedPath,
          );
        });

        _showMessage(
          '${component.name} instalado com sucesso.',
        );
      }
    } catch (e) {
      debugPrint(
        'Erro ao instalar ${component.name}: $e',
      );

      if (mounted) {
        setState(() {
          component.markError(
            e.toString(),
          );
        });

        _showMessage(
          'Erro ao instalar ${component.name}.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  Future<void>
      _refreshInstallationState() async {
    if (_installing) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
    });

    for (final component
        in _components) {
      component.status =
          SDKComponentStatus.notSelected;

      component.installedPath = null;
      component.progress = 0.0;
      component.errorMessage = null;
    }

    await _restoreInstallationState();
  }

  bool get _isEnvironmentReady {
    return _components.isNotEmpty &&
        _components.every(
          (component) =>
              component.isInstalled,
        );
  }

  int get _installedCount {
    return _components
        .where(
          (component) =>
              component.isInstalled,
        )
        .length;
  }

  String _componentName(
    SDKComponentType type,
  ) {
    switch (type) {
      case SDKComponentType.flutter:
        return 'Flutter';

      case SDKComponentType.java:
        return 'Java';

      case SDKComponentType.androidSdk:
        return 'Android SDK';

      case SDKComponentType.buildTools:
        return 'Android Build Tools';

      case SDKComponentType.platformTools:
        return 'Platform Tools';

      case SDKComponentType.androidPlatform:
        return 'Android Platform';

      case SDKComponentType.gradle:
        return 'Gradle';

      case SDKComponentType.ndk:
        return 'Android NDK';

      case SDKComponentType.linuxRuntime:
        return 'Ubuntu';

      case SDKComponentType.unknown:
        return 'desconhecido';
    }
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .hideCurrentSnackBar();

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading:
            false,
        title: const Text(
          'Configuração',
        ),
        actions: [
		  IconButton(
            tooltip: 'Terminal Ubuntu',
            icon: const Icon(Icons.terminal),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TerminalScreen(),
                 ),
               );
            },
           ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed:
                _loading ||
                        _installing
                    ? null
                    : _refreshInstallationState,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final ready =
        _isEnvironmentReady;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding:
                const EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24,
            ),
            children: [
              const Text(
                'Prepare sua IDE',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                'Instale os componentes necessários '
                'para compilar e executar projetos Flutter.',
                style: TextStyle(
                  fontSize: 15,
                ),
              ),
              const SizedBox(
                height: 20,
              ),
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons
                                .settings_suggest,
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          const Expanded(
                            child: Text(
                              'Ambiente de desenvolvimento',
                              style:
                                  TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '$_installedCount/${_components.length}',
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(
                        height: 12,
                      ),
                      LinearProgressIndicator(
                        value:
                            _components.isEmpty
                                ? 0
                                : _installedCount /
                                    _components.length,
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      Text(
                        ready
                            ? 'Todos os componentes estão instalados.'
                            : 'Selecione e instale os componentes necessários.',
                        style: TextStyle(
                          color: ready
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(
                height: 24,
              ),
              const Text(
                'Componentes',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              ..._components.map(
                _buildComponentCard,
              ),
            ],
          ),
        ),
        _buildContinueButton(
          ready,
        ),
      ],
    );
  }

  Widget _buildContinueButton(
    bool ready,
  ) {
    return SafeArea(
      top: false,
      child: Container(
        padding:
            const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .scaffoldBackgroundColor,
          boxShadow: const [
            BoxShadow(
              blurRadius: 8,
              offset: Offset(0, -2),
              color: Colors.black12,
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed:
                ready &&
                        !_installing
                    ? () {
                        _showMessage(
                          'Ambiente pronto.',
                        );
                      }
                    : null,
            icon: Icon(
              ready
                  ? Icons.check
                  : Icons.lock_outline,
            ),
            label: Text(
              ready
                  ? 'Ambiente pronto'
                  : 'Finalize a configuração para continuar',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildComponentCard(
    SDKComponent component,
  ) {
    final installed =
        component.isInstalled;

    final installing =
        component.status ==
            SDKComponentStatus.installing;

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding:
            const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    component.name,
                    style:
                        const TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                _buildStatusIcon(
                  component,
                ),
              ],
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              component.description,
            ),
            const SizedBox(
              height: 12,
            ),
            Text(
              component.statusText,
              style: TextStyle(
                fontWeight:
                    FontWeight.w600,
                color: _statusColor(
                  component.status,
                ),
              ),
            ),
            if (component.errorMessage !=
                null) ...[
              const SizedBox(
                height: 8,
              ),
              Text(
                component.errorMessage!,
                style:
                    const TextStyle(
                  color: Colors.red,
                ),
              ),
            ],
            if (component.selectedFilePath !=
                null) ...[
              const SizedBox(
                height: 8,
              ),
              Text(
                component.selectedFilePath!,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
            if (installed &&
                component.installedPath !=
                    null) ...[
              const SizedBox(
                height: 8,
              ),
              const Text(
                'Instalado em:',
                style:
                    TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 2,
              ),
              Text(
                component.installedPath!,
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  fontSize: 12,
                ),
              ),
            ],
            if (installing) ...[
              const SizedBox(
                height: 16,
              ),
              LinearProgressIndicator(
                value:
                    component.progress,
              ),
              const SizedBox(
                height: 6,
              ),
              Text(
                '${(component.progress * 100).toStringAsFixed(0)}%',
              ),
            ],
            const SizedBox(
              height: 16,
            ),
            Row(
              children: [
                Expanded(
                  child:
                      OutlinedButton.icon(
                    onPressed:
                        _installing
                            ? null
                            : () =>
                                _selectFile(
                                  component,
                                ),
                    icon: const Icon(
                      Icons.folder_open,
                    ),
                    label:
                        const Text(
                      'Selecionar',
                    ),
                  ),
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child:
                      ElevatedButton.icon(
                    onPressed:
                        _installing ||
                                installed
                            ? null
                            : () =>
                                _installComponent(
                                  component,
                                ),
                    icon: Icon(
                      installed
                          ? Icons.check
                          : Icons.download,
                    ),
                    label: Text(
                      installed
                          ? 'Instalado'
                          : 'Instalar',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(
    SDKComponent component,
  ) {
    switch (component.status) {
      case SDKComponentStatus.installed:
      case SDKComponentStatus.valid:
        return const Icon(
          Icons.check_circle,
          color: Colors.green,
        );

      case SDKComponentStatus.installing:
      case SDKComponentStatus.validating:
        return const SizedBox(
          width: 22,
          height: 22,
          child:
              CircularProgressIndicator(
            strokeWidth: 2,
          ),
        );

      case SDKComponentStatus.invalid:
      case SDKComponentStatus.error:
        return const Icon(
          Icons.error,
          color: Colors.red,
        );

      default:
        return const Icon(
          Icons.circle_outlined,
        );
    }
  }

  Color _statusColor(
    SDKComponentStatus status,
  ) {
    switch (status) {
      case SDKComponentStatus.installed:
      case SDKComponentStatus.valid:
        return Colors.green;

      case SDKComponentStatus.invalid:
      case SDKComponentStatus.error:
        return Colors.red;

      case SDKComponentStatus.installing:
      case SDKComponentStatus.validating:
        return Colors.orange;

      default:
        return Colors.grey;
    }
  }
}