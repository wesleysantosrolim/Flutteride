import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:flutteride/features/editor/services/editor_autocomplete_file_logger.dart';
import 'package:flutteride/features/editor/services/editor_code_action_service.dart';
import 'package:flutteride/features/editor/services/editor_monaco_sync_service.dart';

class EditorMonaco extends StatefulWidget {
  final String? filePath;
  final String fileContent;
  final bool visible;
  final ValueChanged<String>? onContentChanged;
  final ValueChanged<MonacoController>? onControllerReady;
  final EditorMonacoSyncService? syncService;
  final EditorCodeActionService? codeActionService;

  const EditorMonaco({
    super.key,
    required this.filePath,
    required this.fileContent,
    required this.visible,
    this.onContentChanged,
    this.onControllerReady,
    this.syncService,
    this.codeActionService,
  });

  @override
  State<EditorMonaco> createState() => _EditorMonacoState();
}

class _EditorMonacoState extends State<EditorMonaco>
    with WidgetsBindingObserver {
  MonacoController? _controller;

  bool _ready = false;
  bool _isSyncingContent = false;
  bool _syncPending = false;
  bool _isLoadingCodeActions = false;

  void _record(String message) {
    unawaited(EditorAutocompleteFileLogger.log(message));
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_onFocusChanged);

    _record('[TOUCH_DEBUG] initState');
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);

    _record('[TOUCH_DEBUG] dispose');

    super.dispose();
  }

  void _onFocusChanged() {
    final focus = FocusManager.instance.primaryFocus;
    final type = focus?.runtimeType.toString() ?? 'none';
    final label = focus?.debugLabel ?? '-';

    _record('[FOCUS] primaryType=$type debugLabel=$label');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _record('[LIFECYCLE] state=${state.name}');
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final inset = MediaQuery.maybeOf(context)?.viewInsets.bottom;

      _record('[KEYBOARD_METRICS] viewInsetsBottom=$inset');
    });
  }

  Future<void> _handleReady(MonacoController controller) async {
    _controller = controller;
    _ready = true;

    _record(
      '[MONACO_READY] file=${widget.filePath ?? '-'} '
      'visible=${widget.visible}',
    );

    widget.syncService?.attachMonacoController(controller);
    widget.codeActionService?.attachController(controller);
    widget.codeActionService?.setActiveFile(widget.filePath);

    widget.onControllerReady?.call(controller);

    await _syncCurrentContent();

    if (!mounted) return;

    setState(() {});
  }

  /// Consulta o foco real no DOM do WebView.
  ///
  /// Esta função apenas coleta informações: não altera o foco
  /// e não tenta abrir ou fechar o teclado.
  Future<void> _logKeyboardDiagnostic(String source) async {
    final controller = _controller;

    if (!mounted || controller == null || !_ready) {
      _record(
        '[KEYBOARD_DIAG] source=$source '
        'skipped=true ready=$_ready',
      );
      return;
    }

    try {
      final result = await controller.evaluateJavaScript<String>('''
JSON.stringify((() => {
  const editor = document.querySelector('.monaco-editor');
  const active = document.activeElement;
  const input = editor
    ? editor.querySelector('textarea.inputarea, .native-edit-context')
    : null;
  const viewport = window.visualViewport;

  return {
    editorExists: !!editor,
    editorHasFocusedClass: !!editor?.classList.contains('focused'),
    activeTag: active?.tagName ?? null,
    activeId: active?.id ?? null,
    activeClass: typeof active?.className === 'string'
      ? active.className
      : '',
    inputExists: !!input,
    inputTag: input?.tagName ?? null,
    inputFocused: !!input && active === input,
    inputReadOnly: input ? !!input.readOnly : null,
    inputDisabled: input ? !!input.disabled : null,
    innerHeight: window.innerHeight,
    documentHeight: document.documentElement?.clientHeight ?? null,
    visualViewportHeight: viewport?.height ?? null,
    visualViewportOffsetTop: viewport?.offsetTop ?? null,
    visualViewportScale: viewport?.scale ?? null
  };
})())
''', defaultValue: '{"error":"resultado JavaScript vazio"}');

      if (!mounted) return;

      final inset = MediaQuery.maybeOf(context)?.viewInsets.bottom;

      _record(
        '[KEYBOARD_DIAG] source=$source '
        'flutterViewInsetsBottom=$inset '
        'javascript=${result ?? 'null'}',
      );
    } catch (error) {
      _record('[KEYBOARD_DIAG_ERROR] source=$source error=$error');
    }
  }

  /// Faz duas leituras para observar o foco imediatamente após o toque
  /// e novamente durante a possível animação do teclado.
  void _scheduleKeyboardDiagnostics() {
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;

      unawaited(_logKeyboardDiagnostic('tap_plus_350ms'));
    });

    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;

      unawaited(_logKeyboardDiagnostic('tap_plus_1000ms'));
    });
  }

  Future<void> _syncCurrentContent() async {
    final controller = _controller;

    if (controller == null || !_ready || !mounted) return;

    // Nao descarta atualizacoes que chegam durante outra sincronizacao.
    if (_isSyncingContent) {
      _syncPending = true;
      return;
    }

    _isSyncingContent = true;

    try {
      do {
        _syncPending = false;

        // Sempre captura a selecao mais recente.
        final content = widget.fileContent;
        final filePath = widget.filePath;

        if (filePath == null) break;

        await controller.whenReady;

        if (!mounted) break;

        if (widget.filePath != filePath || widget.fileContent != content) {
          _syncPending = true;
          continue;
        }

        final currentContent = await controller.document.getText();

        if (!mounted) break;

        if (widget.filePath != filePath || widget.fileContent != content) {
          _syncPending = true;
          continue;
        }

        if (currentContent != content) {
          await controller.document.setText(content);
        }

        if (!mounted) break;

        // A selecao pode mudar enquanto setText esta em andamento.
        if (widget.filePath != filePath || widget.fileContent != content) {
          _syncPending = true;
          continue;
        }

        final language = _languageForFile(filePath);
        await controller.document.setLanguage(language);

        // Se chegou outra solicitacao durante a operacao, repete
        // usando o caminho e o conteudo atuais do widget.
        if (widget.filePath != filePath || widget.fileContent != content) {
          _syncPending = true;
        }
      } while (_syncPending && mounted);
    } catch (error) {
      _record('[SYNC_ERROR] error=$error');

      debugPrint('[EditorMonaco] Erro ao sincronizar conteúdo: $error');
    } finally {
      _isSyncingContent = false;

      // Protecao para uma solicitacao pendente apos uma falha.
      if (_syncPending && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_syncCurrentContent());
          }
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant EditorMonaco oldWidget) {
    super.didUpdateWidget(oldWidget);

    final fileChanged = oldWidget.filePath != widget.filePath;

    if (fileChanged) {
      widget.codeActionService?.setActiveFile(widget.filePath);
    }

    final contentChanged = oldWidget.fileContent != widget.fileContent;

    if (fileChanged || contentChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        unawaited(_syncCurrentContent());
      });
    }
  }

  MonacoLanguage _languageForFile(String path) {
    final lower = path.toLowerCase();

    if (lower.endsWith('.dart')) return MonacoLanguage.dart;
    if (lower.endsWith('.json')) return MonacoLanguage.json;

    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return MonacoLanguage.yaml;
    }

    if (lower.endsWith('.md')) return MonacoLanguage.markdown;
    if (lower.endsWith('.xml')) return MonacoLanguage.xml;
    if (lower.endsWith('.html')) return MonacoLanguage.html;
    if (lower.endsWith('.css')) return MonacoLanguage.css;
    if (lower.endsWith('.js')) return MonacoLanguage.javascript;
    if (lower.endsWith('.ts')) return MonacoLanguage.typescript;

    return MonacoLanguage.plaintext;
  }

  Future<void> _showCodeActions() async {
    final controller = _controller;
    final service = widget.codeActionService;
    final path = widget.filePath;

    if (!mounted ||
        controller == null ||
        service == null ||
        path == null ||
        _isLoadingCodeActions ||
        !_ready) {
      return;
    }

    setState(() => _isLoadingCodeActions = true);

    try {
      await controller.whenReady;

      final cursor = await controller.getCursorPosition();
      if (cursor == null || !mounted) return;

      final documentText = await controller.document.getText();
      final actions = await service.requestActions(
        path: path,
        line: cursor.line > 0 ? cursor.line - 1 : 0,
        character: cursor.column > 0 ? cursor.column - 1 : 0,
        documentText: documentText,
      );

      if (!mounted) return;

      if (actions.isEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Nenhuma ação de código disponível nesta posição.',
            ),
          ),
        );
        return;
      }

      final selectedAction = await showModalBottomSheet<DartCodeAction>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Ações de código',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              for (final action in actions)
                ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(action.title),
                  subtitle:
                      action.kind == null ? null : Text(action.kind!),
                  onTap: () => Navigator.of(sheetContext).pop(action),
                ),
            ],
          ),
        ),
      );

      if (selectedAction == null || !mounted) return;

      await service.applyAction(
        action: selectedAction,
        activeFilePath: path,
      );

      final updatedText = await controller.document.getText();
      if (!mounted || widget.filePath != path) return;

      widget.onContentChanged?.call(updatedText);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('Não foi possível executar a ação: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingCodeActions = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    final background = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _record(
          '[POINTER_DOWN] x=${event.localPosition.dx} '
          'y=${event.localPosition.dy} kind=${event.kind} '
          'ready=$_ready visible=${widget.visible} '
          'file=${widget.filePath ?? '-'}',
        );

        _scheduleKeyboardDiagnostics();
      },
      onPointerUp: (event) {
        _record(
          '[POINTER_UP] kind=${event.kind} '
          'ready=$_ready visible=${widget.visible}',
        );
      },
      onPointerCancel: (event) {
        _record('[POINTER_CANCEL] kind=${event.kind}');
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          MonacoEditor(
            initialText: widget.fileContent,
            backgroundColor: background,
            options: EditorOptions(
              language: widget.filePath != null
                  ? _languageForFile(widget.filePath!)
                  : MonacoLanguage.dart,
              theme: isDark ? MonacoTheme.vsDark : MonacoTheme.vs,
              fontSize: 14,
              wordWrap: MonacoWordWrap.off,
              minimap: const MonacoMinimapOptions(enabled: false),
              tabSize: 2,
              insertSpaces: true,
              detectIndentation: false,
              formatOnPaste: false,
              quickSuggestions: true,
              suggestOnTriggerCharacters: true,
            ),
            onReady: _handleReady,
            onContentChanged: widget.onContentChanged,
            loadingBuilder: (context) {
              return Container(color: background);
            },
            errorBuilder: (context, error, stackTrace) {
              _record('[MONACO_ERROR] error=$error');

              return Container(
                color: background,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Erro ao carregar o Monaco:\n$error',
                  textAlign: TextAlign.center,
                ),
              );
            },
          ),
          if (widget.visible &&
              _ready &&
              widget.filePath?.toLowerCase().endsWith('.dart') == true &&
              widget.codeActionService != null)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: theme.colorScheme.surface.withValues(alpha: 0.92),
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  tooltip: 'Ações de código',
                  onPressed:
                      _isLoadingCodeActions ? null : _showCodeActions,
                  icon: _isLoadingCodeActions
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lightbulb_outline),
                ),
              ),
            ),
          if (!widget.visible || !_ready)
            Container(
              color: background,
              alignment: Alignment.center,
              child: !_ready
                  ? const SizedBox.shrink()
                  : const Text('Selecione um arquivo para começar'),
            ),
        ],
      ),
    );
  }
}
