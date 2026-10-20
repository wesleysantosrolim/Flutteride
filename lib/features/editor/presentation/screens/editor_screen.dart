import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../../models/editor_file_node.dart';
import '../../services/editor_file_service.dart';
import '../../services/editor_analysis_coordinator.dart';
import '../../services/editor_monaco_sync_service.dart';
import '../../services/editor_monaco_completion_service.dart';
import '../../services/editor_code_action_service.dart';
import '../../../flutter/services/flutter_run_service.dart';
import '../widgets/editor_app_bar.dart';
import '../widgets/editor_file_explorer.dart';
import '../widgets/editor_run_bar.dart';
import '../widgets/bottom_panel/editor_bottom_panel.dart';
import 'editor_area.dart';
import 'editor_actions.dart';
import 'preview_screen.dart';

class EditorScreen extends StatefulWidget {
  final String projectName;
  final String projectPath;

  const EditorScreen({
    super.key,
    required this.projectName,
    required this.projectPath,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorAnalysisCoordinator _analysisCoordinator =
      EditorAnalysisCoordinator();

  final EditorFileService _fileService = EditorFileService();

  late final EditorMonacoSyncService _monacoSyncService;

  late final EditorMonacoCompletionService _completionService;

  late final EditorCodeActionService _codeActionService;

  final FlutterRunService _flutterRunService = FlutterRunService.instance;

  StreamSubscription<String>? _flutterOutputSubscription;

  GlobalKey<ScaffoldState> get _scaffoldKey => _scaffoldKeyValue;

  final GlobalKey<ScaffoldState> _scaffoldKeyValue =
      GlobalKey<ScaffoldState>();

  EditorFileNode? _selectedFile;

  final Set<String> _expandedPaths = <String>{};

  final List<EditorFileNode> _openedFiles = <EditorFileNode>[];

  final Map<String, String> _loadedFileContents = <String, String>{};

  List<EditorFileNode> _nodes = <EditorFileNode>[];

  bool _isLoadingFiles = true;
  bool _isLoadingFileContent = false;
  bool _isSavingFile = false;

  String _editorContent = '';

  MonacoController? _monacoController;

  int _fileLoadRequest = 0;

  bool _isPreviewVisible = false;

  static const Map<String, MonacoLanguage> _extensionMap = {
    'dart': MonacoLanguage.dart,
    'json': MonacoLanguage.json,
    'yaml': MonacoLanguage.yaml,
    'yml': MonacoLanguage.yaml,
    'md': MonacoLanguage.markdown,
    'xml': MonacoLanguage.xml,
    'html': MonacoLanguage.html,
    'css': MonacoLanguage.css,
    'js': MonacoLanguage.javascript,
    'ts': MonacoLanguage.typescript,
  };

  bool get _isFlutterRunning => _flutterRunService.isRunning;

  bool get _canHotReload =>
      _isFlutterRunning &&
      _flutterRunService.target == FlutterRunTarget.webServer;

  bool get _canPreview => _flutterRunService.canPreview;

  bool get _canHotRestart =>
      _isFlutterRunning &&
      _flutterRunService.target == FlutterRunTarget.webServer;

  @override
  void initState() {
    super.initState();

    _monacoSyncService = EditorMonacoSyncService(
      analysisCoordinator: _analysisCoordinator,
    );

    _completionService = EditorMonacoCompletionService(
      analysisCoordinator: _analysisCoordinator,
    );

    _codeActionService = EditorCodeActionService(
      analysisCoordinator: _analysisCoordinator,
    );

    _expandedPaths.add(widget.projectPath);

    _flutterOutputSubscription = _flutterRunService.output.listen((_) {});

    _loadFiles();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      unawaited(
        _analysisCoordinator
            .start(workspacePath: widget.projectPath)
            .catchError((error) {
          debugPrint('[EditorScreen] Analysis Server error: $error');
        }),
      );
    });
  }

  @override
  void dispose() {
    _completionService.dispose();
    _codeActionService.dispose();
    _monacoSyncService.dispose();

    unawaited(_analysisCoordinator.dispose());

    _flutterOutputSubscription?.cancel();
    _flutterOutputSubscription = null;

    _fileLoadRequest++;

    _monacoController?.dispose();
    _monacoController = null;

    _loadedFileContents.clear();

    super.dispose();
  }

  Future<void> _runFlutter() async {
    if (_flutterRunService.isRunning) return;

    final target = await _showRunTargetDialog();

    if (!mounted || target == null) return;

    await _saveFile();

    if (!mounted) return;

    setState(() {});

    await _flutterRunService.run(
      projectPath: widget.projectPath,
      target: target,
    );

    if (!mounted) return;

    setState(() {});
  }

  Future<FlutterRunTarget?> _showRunTargetDialog() async {
    return showDialog<FlutterRunTarget>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Executar projeto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: const Text('Flutter Web Server'),
                subtitle: const Text('Executar no Web com Hot Reload'),
                onTap: () {
                  Navigator.of(context).pop(FlutterRunTarget.webServer);
                },
              ),
              ListTile(
                leading: const Icon(Icons.android_rounded),
                title: const Text('Android ARM64'),
                subtitle: const Text('Gerar APK Android debug'),
                onTap: () {
                  Navigator.of(context).pop(FlutterRunTarget.androidArm64);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }

  void _openPreview() {
    if (!_flutterRunService.canPreview) return;

    if (!_isPreviewVisible) {
      setState(() {
        _isPreviewVisible = true;
      });
    }
  }

  void _hidePreview() {
    if (!mounted) return;

    setState(() {
      _isPreviewVisible = false;
    });
  }

  Future<void> _hotReload() async {
    await _saveFile();

    if (!mounted) return;

    _flutterRunService.hotReload();
    setState(() {});
  }

  void _hotRestart() {
    _flutterRunService.hotRestart();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopFlutter() async {
    await _flutterRunService.stop();

    if (!mounted) return;

    setState(() {
      _isPreviewVisible = false;
    });
  }

  Future<void> _loadFiles() async {
    if (!mounted) return;

    setState(() {
      _isLoadingFiles = true;
    });

    try {
      List<EditorFileNode> nodes;

      try {
        nodes = await _fileService.listProjectTree(widget.projectPath);
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
        nodes = await _fileService.listProjectTree(widget.projectPath);
      }

      if (!mounted) return;

      setState(() {
        _nodes = nodes;
        _isLoadingFiles = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingFiles = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao carregar arquivos: ${error.toString().split('\n').first}',
          ),
        ),
      );
    }
  }

  Future<void> _selectFile(EditorFileNode file) async {
    if (!file.isFile) return;

    final requestId = ++_fileLoadRequest;

    setState(() {
      _selectedFile = file;
      _isLoadingFileContent = true;
    });

    _completionService.setActiveFile(file.path);

    _monacoSyncService.bindDiagnostics(
      controller: _monacoController,
      activeFilePath: file.path,
    );

    final alreadyOpened = _openedFiles.any(
      (openedFile) => openedFile.path == file.path,
    );

    if (!alreadyOpened) {
      setState(() {
        _openedFiles.add(file);
      });
    }

    try {
      String content;
      final cachedContent = _loadedFileContents[file.path];

      if (cachedContent != null) {
        content = cachedContent;
      } else {
        content = await _fileService.readFile(file.path);

        if (!mounted || requestId != _fileLoadRequest) return;

        _loadedFileContents[file.path] = content;
      }

      if (!mounted || requestId != _fileLoadRequest) return;

      setState(() {
        _editorContent = content;
        _isLoadingFileContent = false;
      });

      if (file.path.toLowerCase().endsWith('.dart')) {
        unawaited(
          _monacoSyncService.onDocumentOpened(file.path, content),
        );
      }

      final controller = _monacoController;
      if (controller == null) return;

      try {
        await controller.whenReady;
      } catch (_) {
        return;
      }

      if (!mounted || requestId != _fileLoadRequest) return;

      _monacoSyncService.bindDiagnostics(
        controller: _monacoController,
        activeFilePath: file.path,
      );

      _completionService.setActiveFile(file.path);
    } catch (error) {
      if (!mounted || requestId != _fileLoadRequest) return;

      setState(() {
        _isLoadingFileContent = false;
      });

      if (error.toString().contains('MonacoDisposedError') ||
          error.toString().contains('disposed')) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir "${file.name}": $error'),
        ),
      );
    }
  }

  Future<void> _selectOpenedTab(EditorFileNode file) async {
    if (_selectedFile?.path == file.path) return;

    final requestId = ++_fileLoadRequest;
    final cachedContent = _loadedFileContents[file.path];

    if (cachedContent != null) {
      _completionService.setActiveFile(file.path);

      _monacoSyncService.bindDiagnostics(
        controller: _monacoController,
        activeFilePath: file.path,
      );

      if (file.path.toLowerCase().endsWith('.dart')) {
        unawaited(
          _monacoSyncService.onDocumentOpened(file.path, cachedContent),
        );
      }

      setState(() {
        _selectedFile = file;
        _editorContent = cachedContent;
        _isLoadingFileContent = false;
      });

      return;
    }

    await _selectFile(file);

    if (!mounted || requestId != _fileLoadRequest) return;
  }

  Future<void> _closeTab(EditorFileNode file) async {
    final index = _openedFiles.indexWhere(
      (openedFile) => openedFile.path == file.path,
    );

    if (index < 0) return;

    final wasActive = _selectedFile?.path == file.path;

    if (!mounted) return;

    setState(() {
      _openedFiles.removeAt(index);
    });

    if (file.path.toLowerCase().endsWith('.dart')) {
      unawaited(
        _monacoSyncService.onDocumentClosed(file.path),
      );
    }

    if (!wasActive) return;

    if (_openedFiles.isEmpty) {
      setState(() {
        _selectedFile = null;
        _editorContent = '';
        _isLoadingFileContent = false;
      });

      _completionService.setActiveFile(null);

      _monacoSyncService.bindDiagnostics(
        controller: _monacoController,
        activeFilePath: null,
      );

      return;
    }

    final nextIndex =
        index >= _openedFiles.length ? _openedFiles.length - 1 : index;

    final nextFile = _openedFiles[nextIndex];

    await _selectOpenedTab(nextFile);
  }

  Future<void> _saveFile() async {
    final file = _selectedFile;
    final controller = _monacoController;

    if (file == null || controller == null || _isSavingFile) return;

    setState(() {
      _isSavingFile = true;
    });

    try {
      await controller.whenReady;

      final document = controller.document;
      final content = await EditorActions.save(document);

      if (content == null) return;

      await _fileService.writeFile(file.path, content);
      await document.markSaved();

      if (!mounted) return;

      _loadedFileContents[file.path] = content;

      _analysisCoordinator.onContentChanged(
        filePath: file.path,
        content: content,
      );

      setState(() {
        _editorContent = content;
      });
      
      // Notificação de sucesso removida para evitar o banner na tela
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar "${file.name}": $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingFile = false;
        });
      }
    }
  }

  void _onMonacoReady(MonacoController controller) {
    _monacoController = controller;

    _monacoSyncService.bindDiagnostics(
      controller: _monacoController,
      activeFilePath: _selectedFile?.path,
    );

    _completionService.setActiveFile(_selectedFile?.path);

    unawaited(
      _completionService.attachController(controller),
    );
  }

  void _onContentChanged(String value) {
    if (!mounted) return;

    _editorContent = value;

    final file = _selectedFile;
    if (file != null) {
      _loadedFileContents[file.path] = value;

      _analysisCoordinator.onContentChanged(
        filePath: file.path,
        content: value,
      );
    }
  }

  void _toggleDirectory(String path) {
    setState(() {
      if (_expandedPaths.contains(path)) {
        _expandedPaths.remove(path);
      } else {
        _expandedPaths.add(path);
      }
    });
  }

  MonacoLanguage _languageForFile(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return _extensionMap[ext] ?? MonacoLanguage.plaintext;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSmallScreen = constraints.maxWidth < 700;

        return Stack(
          children: [
            Scaffold(
              key: _scaffoldKey,
              appBar: EditorAppBar(
                projectName: widget.projectName,
                isSmallScreen: isSmallScreen,
                isSaving: _isSavingFile,
                hasSelectedFile: _selectedFile != null,
                onOpenExplorer: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
                onSave: _saveFile,
                onUndo: () {
                  EditorActions.undo(_monacoController);
                },
                onRedo: () {
                  EditorActions.redo(_monacoController);
                },
                onFind: () {
                  EditorActions.find(_monacoController);
                },
              ),
              drawer: isSmallScreen
                  ? Drawer(
                      width: 320,
                      child: SafeArea(
                        child: EditorFileExplorer(
                          projectName: widget.projectName,
                          projectPath: widget.projectPath,
                          nodes: _nodes,
                          isLoading: _isLoadingFiles,
                          selectedPath: _selectedFile?.path,
                          expandedPaths: _expandedPaths,
                          onDirectoryToggled: _toggleDirectory,
                          onFileSelected: _selectFile,
                          onRefresh: _loadFiles,
                          onFileOpened: () {
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    )
                  : null,
              body: SafeArea(
                child: Column(
                  children: [
                    EditorRunBar(
                      isFlutterRunning: _isFlutterRunning,
                      canHotReload: _canHotReload,
                      canHotRestart: _canHotRestart,
                      canPreview: _canPreview,
                      onRun: _runFlutter,
                      onHotReload: _hotReload,
                      onHotRestart: _hotRestart,
                      onStop: _stopFlutter,
                      onPreview: _openPreview,
                      onIntelliSense: () {
                        unawaited(_completionService.triggerIntelliSense());
                      },
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Row(
                            children: [
                              if (!isSmallScreen)
                                SizedBox(
                                  width: 300,
                                  child: EditorFileExplorer(
                                    projectName: widget.projectName,
                                    projectPath: widget.projectPath,
                                    nodes: _nodes,
                                    isLoading: _isLoadingFiles,
                                    selectedPath: _selectedFile?.path,
                                    expandedPaths: _expandedPaths,
                                    onDirectoryToggled: _toggleDirectory,
                                    onFileSelected: _selectFile,
                                    onRefresh: _loadFiles,
                                  ),
                                ),
                              if (!isSmallScreen)
                                const VerticalDivider(
                                  width: 1,
                                ),
                              Expanded(
                                child: EditorArea(
                                  selectedFile: _selectedFile,
                                  openedFiles: _openedFiles,
                                  fileContent: _editorContent,
                                  onTabSelected: _selectOpenedTab,
                                  onTabClosed: _closeTab,
                                  onMonacoReady: _onMonacoReady,
                                  onContentChanged: _onContentChanged,
                                  syncService: _monacoSyncService,
                                  codeActionService: _codeActionService,
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: EditorBottomPanel(
                              analysisCoordinator: _analysisCoordinator,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_flutterRunService.previewUrl != null)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_isPreviewVisible,
                  child: Visibility(
                    visible: _isPreviewVisible,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: false,
                    child: PreviewScreen(
                      url: _flutterRunService.previewUrl!,
                      onClose: _hidePreview,
                      isFlutterRunning: _isFlutterRunning,
                      canHotReload: _canHotReload,
                      canHotRestart: _canHotRestart,
                      onHotReload: _hotReload,
                      onHotRestart: _hotRestart,
                      onStop: _stopFlutter,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
