
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

/// Teste isolado de sugestões simuladas no Monaco.
/// Não inicia o Dart Analysis Server nem altera a integração LSP existente.
class MonacoSimulatedCompletionScreen extends StatefulWidget {
  const MonacoSimulatedCompletionScreen({super.key});

  @override
  State<MonacoSimulatedCompletionScreen> createState() =>
      _MonacoSimulatedCompletionScreenState();
}

class _MonacoSimulatedCompletionScreenState
    extends State<MonacoSimulatedCompletionScreen> {
  static const String _providerId = 'flutteride-simulated-completion';

  MonacoController? _controller;
  MonacoCompletionRegistration? _registration;

  bool _editorReady = false;
  bool _registering = false;
  bool _registered = false;

  String _status = 'Inicializando Monaco...';
  String? _error;

  static const String _initialCode = '''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Teste de completion')),
        body: Center(
          child: Con
        ),
      ),
    );
  }
}
''';

  static final List<CompletionItem> _simulatedItems = [
    const CompletionItem(
      label: 'Container',
      insertText: 'Container()',
      kind: CompletionItemKind.classType,
      detail: 'SIMULADO - Widget Flutter',
      documentation: 'Resposta fictícia do Dart Analysis Server.',
      sortText: '001',
    ),
    const CompletionItem(
      label: 'ConstrainedBox',
      insertText: 'ConstrainedBox()',
      kind: CompletionItemKind.classType,
      detail: 'SIMULADO - Widget Flutter',
      documentation: 'Resposta fictícia do Dart Analysis Server.',
      sortText: '002',
    ),
    const CompletionItem(
      label: 'Center',
      insertText: 'Center()',
      kind: CompletionItemKind.classType,
      detail: 'SIMULADO - Widget Flutter',
      documentation: 'Resposta fictícia do Dart Analysis Server.',
      sortText: '003',
    ),
    const CompletionItem(
      label: 'Column',
      insertText: 'Column()',
      kind: CompletionItemKind.classType,
      detail: 'SIMULADO - Widget Flutter',
      documentation: 'Resposta fictícia do Dart Analysis Server.',
      sortText: '004',
    ),
    const CompletionItem(
      label: 'ColoredBox',
      insertText: 'ColoredBox()',
      kind: CompletionItemKind.classType,
      detail: 'SIMULADO - Widget Flutter',
      documentation: 'Resposta fictícia do Dart Analysis Server.',
      sortText: '005',
    ),
    const CompletionItem(
      label: 'Text',
      insertText: 'Text()',
      kind: CompletionItemKind.classType,
      detail: 'SIMULADO - Widget Flutter',
      documentation: 'Resposta fictícia do Dart Analysis Server.',
      sortText: '006',
    ),
  ];

  @override
  void dispose() {
    final registration = _registration;
    if (registration != null) {
      unawaited(registration.dispose().catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _onEditorReady(MonacoController controller) async {
    if (!mounted) return;

    setState(() {
      _controller = controller;
      _editorReady = true;
      _status = 'Monaco pronto. Registrando sugestões simuladas...';
    });

    await _registerSimulatedProvider();
  }

  Future<void> _registerSimulatedProvider() async {
    final controller = _controller;

    if (controller == null || _registering || _registered) return;

    setState(() {
      _registering = true;
      _error = null;
    });

    try {
      final registration = await controller.registerStaticCompletions(
        id: _providerId,
        languages: [MonacoLanguage.dart],
        triggerCharacters: ['.', ':'],
        items: _simulatedItems,
        isIncomplete: false,
      );

      if (!mounted) {
        await registration.dispose();
        return;
      }

      _registration = registration;

      setState(() {
        _registered = true;
        _status = 'Provedor simulado registrado. Digite Con no editor.';
      });

      debugPrint('[SIMULATED COMPLETION] Provider registered: $_providerId');
      debugPrint(
        '[SIMULATED COMPLETION] Items: '
        '${_simulatedItems.map((item) => item.label).join(', ')}',
      );
    } catch (error, stackTrace) {
      debugPrint('[SIMULATED COMPLETION] Registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = 'Falha ao registrar as sugestões simuladas.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _registering = false;
        });
      }
    }
  }

  Future<void> _forceSuggestions() async {
    final controller = _controller;

    if (controller == null || !_registered) {
      _showStatus('O provedor simulado ainda não está registrado.');
      return;
    }

    try {
      await controller.executeAction(
        MonacoAction('editor.action.triggerSuggest'),
      );

      _showStatus('Solicitação enviada. Confira as sugestões no editor.');
      debugPrint('[SIMULATED COMPLETION] triggerSuggest executed.');
    } catch (error, stackTrace) {
      debugPrint('[SIMULATED COMPLETION] Trigger failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          _error = error.toString();
          _status = 'Não foi possível abrir a lista automaticamente.';
        });
      }
    }
  }

  void _showStatus(String message) {
    if (!mounted) return;
    setState(() => _status = message);
  }

  @override
  Widget build(BuildContext context) {
    // Fornece as localizações necessárias somente a esta tela.
    return Localizations(
      locale: const Locale('pt', 'BR'),
      delegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (localizedContext) {
          return Theme(
            data: Theme.of(context),
            child: _buildScreen(localizedContext),
          );
        },
      ),
    );
  }

  Widget _buildScreen(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completion simulado'),
        actions: [
          IconButton(
            tooltip: 'Forçar sugestões',
            onPressed: _registered ? _forceSuggestions : null,
            icon: const Icon(Icons.lightbulb_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStatusPanel(),
            const Divider(height: 1),
            Expanded(
              child: MonacoEditor(
                initialText: _initialCode,
                options: const EditorOptions(
                  language: MonacoLanguage.dart,
                  theme: MonacoTheme.vsDark,
                  fontSize: 14,
                  minimap: MonacoMinimapOptions(enabled: false),
                  quickSuggestions: true,
                  suggestOnTriggerCharacters: true,
                ),
                onReady: _onEditorReady,
                onError: (error, stackTrace) {
                  debugPrint('[SIMULATED COMPLETION] Monaco error: $error');
                  debugPrintStack(stackTrace: stackTrace);

                  if (mounted) {
                    setState(() {
                      _error = error.toString();
                      _status = 'Erro no editor Monaco.';
                    });
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _registered ? _forceSuggestions : null,
                    icon: const Icon(Icons.lightbulb_outline),
                    label: const Text('Forçar sugestões'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _editorReady && !_registered && !_registering
                        ? _registerSimulatedProvider
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Registrar novamente'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPanel() {
    final Color statusColor;

    if (_error != null) {
      statusColor = Colors.red;
    } else if (_registered) {
      statusColor = Colors.green;
    } else {
      statusColor = Colors.orange;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 11, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (_registering)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Teste isolado: as sugestões não vêm do servidor real.',
            style: TextStyle(fontSize: 12),
          ),
          if (_registered)
            const Text(
              'Esperado: Container, ConstrainedBox, Center, Column e Text.',
              style: TextStyle(fontSize: 12),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
