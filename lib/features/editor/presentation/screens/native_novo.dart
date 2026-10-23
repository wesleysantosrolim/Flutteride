
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Buffer global de logs da ferramenta de diagnostico.
class LspDiagnosticsLogger {
  static final StreamController<String> _logController =
      StreamController<String>.broadcast();
  static final List<String> _history = [];

  static Stream<String> get stream => _logController.stream;
  static List<String> get history => List.unmodifiable(_history);

  static void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final formatted = '[$timestamp] $message';

    _history.add(formatted);

    if (_history.length > 1500) {
      _history.removeAt(0);
    }

    _logController.add(formatted);
    debugPrint(formatted);
  }

  static String dump() => _history.join('\n');

  static void clear() {
    _history.clear();
  }
}

/// Tela de teste com chave para alternar o registerCompletions dinamicamente.
class CasaEditorView extends StatefulWidget {
  const CasaEditorView({super.key});

  @override
  State<CasaEditorView> createState() => _CasaEditorViewState();
}

class _CasaEditorViewState extends State<CasaEditorView> {
  MonacoController? _controller;
  MonacoDocument? _document;
  LanguageServerConnection? _connection;
  MonacoCompletionRegistration? _completionRegistration;
  StreamSubscription<MonacoContentChanged>? _contentSubscription;

  String _status = 'Iniciando ambiente PRoot e LSP...';
  bool _isReady = false;
  bool _showLogger = false;
  int _documentVersion = 1;
  String _sourceText = '';

  bool _enableCustomCompletions = false;

  final Uri _documentUri =
      Uri.parse('file:///root/projects/casa/lib/app.dart');

  @override
  void initState() {
    super.initState();
    _initEditorAndLsp();
  }

  Future<void> _initEditorAndLsp() async {
    try {
      LspDiagnosticsLogger.log(
        'Iniciando inicializacao do editor e LSP...',
      );

      setState(() {
        _status = 'Localizando o projeto casa e lib/app.dart...';
      });

      final appDir = await getApplicationSupportDirectory();
      final rootfsPath =
          p.normalize(p.join(appDir.path, 'ubuntu_rootfs'));

      final projectHostPath =
          p.join(rootfsPath, 'root', 'projects', 'casa');
      final libDir = Directory(p.join(projectHostPath, 'lib'));

      if (!await libDir.exists()) {
        await libDir.create(recursive: true);
      }

      final appDartFile = File(p.join(libDir.path, 'app.dart'));

      if (!await appDartFile.exists()) {
        await appDartFile.writeAsString('''
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
        body: Center(
          child: Text('Ola, Teste de Investigacao LSP!'),
        ),
      ),
    );
  }
}
''');
      }

      final fileContent = await appDartFile.readAsString();
      _sourceText = fileContent;

      LspDiagnosticsLogger.log(
        'Criando controlador do Monaco...',
      );

      setState(() {
        _status = 'Criando controlador do Monaco...';
      });

      final controller = await MonacoController.create(
        options: const EditorOptions(
          language: MonacoLanguage.dart,
          theme: MonacoTheme.vsDark,
          fontSize: 14,
          automaticLayout: true,
          minimap: MonacoMinimapOptions(enabled: true),
          quickSuggestions: true,
          suggestOnTriggerCharacters: true,
        ),
        initialText: fileContent,
      );

      _controller = controller;
      await _controller!.whenReady;

      LspDiagnosticsLogger.log('Controlador Monaco pronto.');

      setState(() {
        _status = 'Iniciando Dart Analysis Server via PRoot...';
      });

      LspDiagnosticsLogger.log(
        'Iniciando transporte nativo (PRoot + Stdio)...',
      );

      final transport =
          await NativeLspTransportService.createTransport(
        projectPath: projectHostPath,
      );

      LspDiagnosticsLogger.log(
        'Conectando canal nativo connectLanguageServer...',
      );

      final connection = await controller.connectLanguageServer(
        id: 'dart-analysis-server',
        transport: transport,
        initializationTimeout: const Duration(seconds: 45),
      );

      _connection = connection;

      LspDiagnosticsLogger.log(
        'LanguageServerConnection estabelecida com sucesso!',
      );

      setState(() {
        _status = 'Abrindo documento no editor...';
      });

      LspDiagnosticsLogger.log(
        'Abrindo documento no Monaco: $_documentUri',
      );

      final doc = await _controller!.openDocument(
        text: fileContent,
        language: MonacoLanguage.dart,
        uri: _documentUri,
      );

      await _controller!.activateDocument(doc);
      _document = doc;

      LspDiagnosticsLogger.log(
        'Enviando notificacao textDocument/didOpen...',
      );

      await connection.sendNotification('textDocument/didOpen', {
        'textDocument': {
          'uri': _documentUri.toString(),
          'languageId': 'dart',
          'version': _documentVersion,
          'text': fileContent,
        },
      });

      LspDiagnosticsLogger.log(
        'Enviando workspace/didChangeWorkspaceFolders...',
      );

      await connection.sendNotification(
        'workspace/didChangeWorkspaceFolders',
        {
          'event': {
            'added': [
              {
                'uri': 'file:///root/projects/casa',
                'name': 'casa',
              },
            ],
            'removed': [],
          },
        },
      );

      _contentSubscription =
          controller.onContentChanged.listen((_) async {
        if (_connection == null || _document == null) return;

        try {
          final newText = await _document!.getText();
          if (newText == _sourceText) return;

          _documentVersion++;
          _sourceText = newText;

          await _connection!.sendNotification(
            'textDocument/didChange',
            {
              'textDocument': {
                'uri': _documentUri.toString(),
                'version': _documentVersion,
              },
              'contentChanges': [
                {'text': newText},
              ],
            },
          );
        } catch (e, st) {
          LspDiagnosticsLogger.log(
            '[DIDCHANGE] Erro ao sincronizar documento: $e\n$st',
          );
        }
      });

      await _updateCompletionProviderState();

      if (!mounted) return;

      setState(() {
        _isReady = true;
        _status =
            'LSP Conectado! Teste o switch de Completion no topo.';
      });

      LspDiagnosticsLogger.log(
        'Inicializacao concluida com sucesso!',
      );
    } catch (e, st) {
      LspDiagnosticsLogger.log(
        'ERRO FATAL na inicializacao: $e\n$st',
      );

      debugPrint('Erro ao inicializar LSP: $e\n$st');

      if (!mounted) return;

      setState(() {
        _status = 'Erro: $e';
      });
    }
  }

  Future<void> _toggleCustomCompletions(bool value) async {
    LspDiagnosticsLogger.log(
      '[SWITCH] Alterando Custom: '
      '${_enableCustomCompletions ? "ON" : "OFF"} -> '
      '${value ? "ON" : "OFF"}',
    );

    setState(() {
      _enableCustomCompletions = value;
    });

    await _updateCompletionProviderState();
  }

  Future<void> _updateCompletionProviderState() async {
    if (_completionRegistration != null) {
      LspDiagnosticsLogger.log(
        '[Investigacao] Removendo registro anterior de completions...',
      );

      await _completionRegistration!.dispose();
      _completionRegistration = null;

      LspDiagnosticsLogger.log(
        '[Investigacao] registerCompletions REMOVIDO.',
      );
    }

    if (_enableCustomCompletions &&
        _controller != null &&
        _connection != null) {
      LspDiagnosticsLogger.log(
        '[Investigacao] Registrando provider manual...',
      );

      _completionRegistration =
          await _controller!.registerCompletions(
        id: 'dart-lsp-investigation-completions',
        languages: [MonacoLanguage.dart],
        triggerCharacters: const [
          '.',
          '=',
          '(',
          r'$',
          '"',
          "'",
          '{',
          '/',
          ':',
        ],
        provider: (request) async {
          // [2A] Confirma se o Monaco realmente chama o provider.
          LspDiagnosticsLogger.log(
            '[2A] PROVIDER INVOCADO pelo Monaco.',
          );

          final connection = _connection;

          if (connection == null) {
            LspDiagnosticsLogger.log(
              '[ERRO] [2A] Conexao LSP nula; nenhuma sugestao sera entregue.',
            );

            return const CompletionList(suggestions: []);
          }

          final position = request.position;

          LspDiagnosticsLogger.log(
            '[2A] Posicao: '
            'linha=${position.lineZeroBased}, '
            'coluna=${position.columnZeroBased}; '
            'triggerKind=${request.triggerKind}; '
            'triggerCharacter=${request.triggerCharacter}',
          );

          try {
            await _sendDidChangeImmediate();

            LspDiagnosticsLogger.log(
              '[2A] Enviando textDocument/completion ao servidor.',
            );

            final dynamic response = await connection.sendRequest(
              'textDocument/completion',
              {
                'textDocument': {
                  'uri': _documentUri.toString(),
                },
                'position': {
                  'line': position.lineZeroBased,
                  'character': position.columnZeroBased,
                },
                'context': {
                  'triggerKind':
                      request.triggerKind == 2 ? 2 : 1,
                  if (request.triggerCharacter != null)
                    'triggerCharacter': request.triggerCharacter,
                },
              },
              const Duration(seconds: 10),
            );

            // [2B] Confirma que o servidor respondeu.
            LspDiagnosticsLogger.log(
              '[2B] RESPOSTA LSP RECEBIDA. '
              'Tipo=${response.runtimeType}',
            );

            List<dynamic> rawItems = [];

            if (response is Map && response['items'] is List) {
              rawItems = response['items'] as List;

              LspDiagnosticsLogger.log(
                '[2B] Formato CompletionList; '
                'isIncomplete=${response['isIncomplete']}; '
                'itens brutos=${rawItems.length}',
              );
            } else if (response is List) {
              rawItems = response;

              LspDiagnosticsLogger.log(
                '[2B] Formato lista direta; '
                'itens=${rawItems.length}',
              );
            } else {
              LspDiagnosticsLogger.log(
                '[ERRO] [2B] Formato de resposta inesperado. '
                'Resposta=${response.toString()}',
              );
            }

            // [2C] Confirma o início da conversão.
            LspDiagnosticsLogger.log(
              '[2C] Iniciando conversao de ${rawItems.length} itens.',
            );

            final suggestions = _convertCompletionItems(rawItems);

            // [2D] Confirma quantos itens foram convertidos.
            LspDiagnosticsLogger.log(
              '[2D] CONVERSAO CONCLUIDA. '
              'Brutos=${rawItems.length}; '
              'convertidos=${suggestions.length}',
            );

            // Registra somente os primeiros dez itens para não
            // sobrecarregar o histórico de diagnóstico.
            for (var i = 0;
                i < suggestions.length && i < 10;
                i++) {
              final item = suggestions[i];

              final itemJson = <String, Object?>{
                'label': item.label,
                'insertText': item.insertText,
                'kind': item.kind.toString(),
                'detail': item.detail,
                'documentation': item.documentation,
                'sortText': item.sortText,
                'filterText': item.filterText,
                'range': item.range == null
                    ? null
                    : {
                        'startLine': item.range!.startLine,
                        'startColumn': item.range!.startColumn,
                        'endLine': item.range!.endLine,
                        'endColumn': item.range!.endColumn,
                      },
                'insertTextRules': item.insertTextRules
                    ?.map((rule) => rule.toString())
                    .toList(),
              };

              LspDiagnosticsLogger.log(
                '[2D ITEM $i] ${jsonEncode(itemJson)}',
              );
            }

            if (suggestions.length > 10) {
              LspDiagnosticsLogger.log(
                '[2D] Mais ${suggestions.length - 10} itens '
                'omitidos do log para preservar o historico.',
              );
            }

            // [2E] Confirma que a lista será devolvida ao Monaco.
            LspDiagnosticsLogger.log(
              '[2E] ENTREGANDO ${suggestions.length} ITENS AO MONACO.',
            );

            return CompletionList(suggestions: suggestions);
          } catch (e, st) {
            LspDiagnosticsLogger.log(
              '[ERRO PROVIDER] $e\n$st',
            );

            debugPrint(
              'Erro no autocomplete LSP customizado: $e\n$st',
            );

            return const CompletionList(suggestions: []);
          }
        },
      );

      LspDiagnosticsLogger.log(
        '[Investigacao] registerCompletions ATIVADO.',
      );

      if (mounted) {
        setState(() {
          _status = 'Modo: registerCompletions MANUAL Ligado';
        });
      }
    } else {
      LspDiagnosticsLogger.log(
        '[Investigacao] Usando apenas connectLanguageServer '
        '(Sem provider manual).',
      );

      if (mounted) {
        setState(() {
          _status =
              'Modo: Apenas connectLanguageServer (Manual Desligado)';
        });
      }
    }
  }

  Future<void> _sendDidChangeImmediate() async {
    if (_connection == null || _document == null) return;

    final content = await _document!.getText();
    if (content == _sourceText) return;

    _documentVersion++;
    _sourceText = content;

    await _connection!.sendNotification(
      'textDocument/didChange',
      {
        'textDocument': {
          'uri': _documentUri.toString(),
          'version': _documentVersion,
        },
        'contentChanges': [
          {'text': content},
        ],
      },
    );
  }

  int? _asInt(Object? value) {
    if (value is int) return value;

    if (value is num &&
        value.isFinite &&
        value == value.truncate()) {
      return value.toInt();
    }

    return null;
  }

  CompletionItemKind _completionKind(Object? rawKind) {
    switch (_asInt(rawKind) ?? 1) {
      case 2:
        return CompletionItemKind.method;
      case 3:
        return CompletionItemKind.functionType;
      case 4:
        return CompletionItemKind.constructor;
      case 5:
        return CompletionItemKind.field;
      case 6:
        return CompletionItemKind.variable;
      case 7:
        return CompletionItemKind.classType;
      case 15:
        return CompletionItemKind.snippet;
      case 21:
        return CompletionItemKind.constant;
      default:
        return CompletionItemKind.text;
    }
  }

  String? _documentationText(Object? documentation) {
    if (documentation == null) return null;
    if (documentation is String) return documentation;

    if (documentation is Map) {
      final value = documentation['value'];
      if (value != null) return value.toString();
    }

    return documentation.toString();
  }

  Range? _completionRange(Object? rawRange) {
    if (rawRange is! Map) return null;

    final start = rawRange['start'];
    final end = rawRange['end'];

    if (start is! Map || end is! Map) return null;

    final startLine = _asInt(start['line']);
    final startColumn = _asInt(start['character']);
    final endLine = _asInt(end['line']);
    final endColumn = _asInt(end['character']);

    if (startLine == null ||
        startColumn == null ||
        endLine == null ||
        endColumn == null) {
      return null;
    }

    return Range(
      startLine: startLine + 1,
      startColumn: startColumn + 1,
      endLine: endLine + 1,
      endColumn: endColumn + 1,
    );
  }

  List<CompletionItem> _convertCompletionItems(
    List<dynamic> rawItems,
  ) {
    final converted = <CompletionItem>[];
    final seen = <String>{};

    for (final raw in rawItems) {
      if (raw is! Map) continue;

      final labelValue = raw['label'];
      if (labelValue is! String || labelValue.isEmpty) continue;

      final textEdit = raw['textEdit'];
      String? insertText;
      Range? range;

      if (textEdit is Map) {
        final newText = textEdit['newText'];
        if (newText is String) {
          insertText = newText;
        }

        range = _completionRange(textEdit['range']) ??
            _completionRange(textEdit['replace']) ??
            _completionRange(textEdit['insert']);
      }

      if (insertText == null && raw['insertText'] is String) {
        insertText = raw['insertText'] as String;
      }

      insertText ??= labelValue;

      final dedupeKey = '$labelValue\u0000$insertText';
      if (!seen.add(dedupeKey)) continue;

      final insertTextFormat = _asInt(raw['insertTextFormat']);
      final isSnippet = insertTextFormat == 2;

      final rules = isSnippet
          ? <InsertTextRule>{InsertTextRule.insertAsSnippet}
          : null;

      converted.add(
        CompletionItem(
          label: labelValue,
          insertText: insertText,
          kind: _completionKind(raw['kind']),
          detail: raw['detail']?.toString(),
          documentation: _documentationText(raw['documentation']),
          sortText: raw['sortText']?.toString(),
          filterText: raw['filterText']?.toString(),
          range: range,
          insertTextRules: rules,
        ),
      );
    }

    return converted;
  }

  @override
  void dispose() {
    _contentSubscription?.cancel();
    _completionRegistration?.dispose();
    _connection?.disconnect();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Investigacao LSP (Completions)'),
          backgroundColor: const Color(0xFF2D2D2D),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Custom',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                    Switch(
                      value: _enableCustomCompletions,
                      onChanged: _toggleCustomCompletions,
                      activeColor: Colors.greenAccent,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                _showLogger ? Icons.code : Icons.bug_report,
                color: Colors.orangeAccent,
              ),
              tooltip: _showLogger ? 'Ver Editor' : 'Ver Logs',
              onPressed: () {
                setState(() {
                  _showLogger = !_showLogger;
                });
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(26),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              color: const Color(0xFF252526),
              child: Text(
                _status,
                style: TextStyle(
                  fontSize: 12,
                  color: _isReady
                      ? Colors.greenAccent
                      : Colors.orangeAccent,
                ),
              ),
            ),
          ),
        ),
        body: _showLogger
            ? const LspLoggerView()
            : (_isReady && _controller != null
                ? MonacoEditor(controller: _controller!)
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() => _showLogger = true);
                            },
                            icon: const Icon(Icons.bug_report),
                            label: const Text('Ver Logs'),
                          ),
                        ],
                      ),
                    ),
                  )),
      ),
    );
  }
}

/// Visualizador de logs de diagnostico LSP.
class LspLoggerView extends StatelessWidget {
  const LspLoggerView({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String>(
      stream: LspDiagnosticsLogger.stream,
      builder: (context, snapshot) {
        final logs = LspDiagnosticsLogger.history;

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Console de Trafego LSP (Client <-> Server)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copiar Logs',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(
                          text: LspDiagnosticsLogger.dump(),
                        ),
                      );

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Logs copiados.'),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 18),
                    tooltip: 'Limpar Logs',
                    onPressed: () {
                      LspDiagnosticsLogger.clear();
                      (context as Element).markNeedsBuild();
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.shade800,
                    ),
                  ),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      final isClient =
                          log.contains('CLIENT ➔ SERVER');
                      final isServer =
                          log.contains('SERVER ➔ CLIENT');
                      final isError = log.contains('ERRO') ||
                          log.contains('stderr') ||
                          log.contains('fatal');

                      Color textColor = Colors.lightGreenAccent;
                      if (isClient) textColor = Colors.cyanAccent;
                      if (isServer) textColor = Colors.amberAccent;
                      if (isError) textColor = Colors.redAccent;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                        ),
                        child: SelectableText(
                          log,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: textColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Servico de transporte nativo (PRoot + Stdio).
class NativeLspTransportService {
  NativeLspTransportService._();

  static Future<LspBridgedTransport> createTransport({
    String? projectPath,
  }) async {
    final server = await _NativeLspProcess.start(
      projectPath: projectPath,
    );

    return server.transport;
  }
}

class _NativeLspProcess {
  _NativeLspProcess._({
    required Process process,
    required String executable,
    required List<String> arguments,
  })  : _process = process,
        _executable = executable,
        _arguments = List<String>.unmodifiable(arguments) {
    _stdoutSubscription = _process.stdout.listen(
      _handleStdout,
      onError: (Object error, StackTrace stackTrace) {
        _fail(error, stackTrace);
      },
      onDone: _handleStdoutDone,
      cancelOnError: false,
    );

    _stderrSubscription = _process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(
      (line) => LspDiagnosticsLogger.log('[LSP stderr]: $line'),
      onError: (Object error, StackTrace stackTrace) {
        LspDiagnosticsLogger.log('[LSP stderr error]: $error');
      },
      cancelOnError: false,
    );

    _exitFuture = _process.exitCode.then<void>(
      _handleExitCode,
      onError: (Object error, StackTrace stackTrace) {
        _fail(error, stackTrace);
      },
    );

    transport = LspBridgedTransport(
      fromServer: _fromServer.stream,
      toServer: _handleClientMessage,
      onClose: stop,
    );
  }

  static const MethodChannel _platform =
      MethodChannel('com.flutteride.flutteride/native_path');

  final Process _process;
  final String _executable;
  final List<String> _arguments;

  final StreamController<Map<String, Object?>> _fromServer =
      StreamController<Map<String, Object?>>();

  final LspStdioMessageDecoder _decoder = LspStdioMessageDecoder();

  late final LspBridgedTransport transport;

  StreamSubscription<List<int>>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;

  late final Future<void> _exitFuture;

  bool _stopped = false;
  bool _stdoutFinished = false;
  bool _streamClosed = false;

  static Future<_NativeLspProcess> start({
    String? projectPath,
  }) async {
    LspDiagnosticsLogger.log(
      'Iniciando _NativeLspProcess.start()...',
    );

    final appDir = await getApplicationSupportDirectory();
    final rootfsPath =
        p.normalize(p.join(appDir.path, 'ubuntu_rootfs'));

    final rootfsDir = Directory(rootfsPath);
    if (!await rootfsDir.exists()) {
      throw StateError('Ubuntu rootfs nao encontrado: $rootfsPath');
    }

    final nativeLibDir =
        await _getNativeLibraryDir(appDir);
    final linksDir =
        await _ensureNativeLinks(appDir, nativeLibDir);

    final prootExecutable =
        p.join(linksDir.path, 'libproot.so');

    if (!await File(prootExecutable).exists()) {
      throw StateError(
        'Executavel PRoot nao encontrado: $prootExecutable',
      );
    }

    const dartExecutable = '/opt/flutter/bin/dart';
    const analysisServerSnapshot =
        '/opt/flutter/bin/cache/dart-sdk/bin/snapshots/analysis_server.dart.snapshot';

    final ubuntuWorkingDirectory =
        _convertProjectPath(projectPath, rootfsPath);

    final tmpDir = Directory(p.join(appDir.path, 'tmp'));
    if (!await tmpDir.exists()) {
      await tmpDir.create(recursive: true);
    }

    const pathValue =
        '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin';

    final bashCommand =
        'export DEBIAN_FRONTEND=noninteractive && '
        'mkdir -p /tmp /root/.pub-cache && '
        'chmod 1777 /tmp && '
        'export TMPDIR=/tmp && '
        'export PUB_CACHE=/root/.pub-cache && '
        'export HOME=/root && '
        'export FLUTTER_ROOT=/opt/flutter && '
        'export PATH="$pathValue" && '
        'exec $dartExecutable $analysisServerSnapshot --lsp';

    final arguments = <String>[
      '-r',
      rootfsPath,
      '-0',
      '-b',
      '/dev',
      '-b',
      '/proc',
      '-b',
      '/sys',
      '-b',
      '${tmpDir.path}:/tmp',
      '-w',
      ubuntuWorkingDirectory,
      '/bin/bash',
      '-c',
      bashCommand,
    ];

    final environment = <String, String>{
      'HOME': '/root',
      'PATH': pathValue,
      'FLUTTER_ROOT': '/opt/flutter',
      'LD_LIBRARY_PATH': '${linksDir.path}:$nativeLibDir',
      'PROOT_LOADER':
          p.join(linksDir.path, 'libproot_loader.so'),
      'PROOT_NO_SECCOMP': '1',
      'TMPDIR': '/tmp',
      'PUB_CACHE': '/root/.pub-cache',
      'PROOT_TMP_DIR': tmpDir.path,
    };

    LspDiagnosticsLogger.log('Executando processo PRoot...');

    final process = await Process.start(
      prootExecutable,
      arguments,
      environment: environment,
      runInShell: false,
    );

    LspDiagnosticsLogger.log(
      'Processo PRoot iniciado com PID: ${process.pid}',
    );

    return _NativeLspProcess._(
      process: process,
      executable: prootExecutable,
      arguments: arguments,
    );
  }

  static Future<String> _getNativeLibraryDir(
    Directory appDir,
  ) async {
    try {
      final nativeDir =
          await _platform.invokeMethod<String>('getNativeLibDir');

      if (nativeDir != null && nativeDir.isNotEmpty) {
        return nativeDir;
      }
    } catch (_) {}

    if (Platform.isAndroid) {
      return '/data/data/com.flutteride.flutteride/lib';
    }

    return p.join(appDir.path, 'bin');
  }

  static Future<Directory> _ensureNativeLinks(
    Directory appDir,
    String nativeLibDir,
  ) async {
    final linksDir = Directory(
      p.join(appDir.path, 'lib_links'),
    );

    if (!await linksDir.exists()) {
      await linksDir.create(recursive: true);
    }

    final nativeDir = Directory(nativeLibDir);
    if (!await nativeDir.exists()) {
      throw StateError(
        'Diretorio nativo nao encontrado: $nativeLibDir',
      );
    }

    await for (final entity in nativeDir.list()) {
      if (entity is! File) continue;

      final fileName = p.basename(entity.path);
      final link = Link(p.join(linksDir.path, fileName));

      try {
        if (await link.exists()) {
          await link.delete();
        }
        await link.create(entity.path);
      } catch (_) {}
    }

    return linksDir;
  }

  static String _convertProjectPath(
    String? projectPath,
    String rootfsPath,
  ) {
    if (projectPath == null || projectPath.trim().isEmpty) {
      return '/root/projects';
    }

    final normalizedPath = p.normalize(projectPath.trim());
    final normalizedRootfs = p.normalize(rootfsPath);

    if (normalizedPath == normalizedRootfs) return '/';

    final rootfsPrefix =
        '$normalizedRootfs${p.separator}';

    if (normalizedPath.startsWith(rootfsPrefix)) {
      final relativePath =
          normalizedPath.substring(rootfsPrefix.length);

      return '/${relativePath.replaceAll('\\', '/')}';
    }

    if (normalizedPath.startsWith('/root/') ||
        normalizedPath.startsWith('/usr/') ||
        normalizedPath.startsWith('/tmp/') ||
        normalizedPath.startsWith('/home/')) {
      return normalizedPath.replaceAll('\\', '/');
    }

    return '/root/projects';
  }

  void _handleStdout(List<int> bytes) {
    if (_stopped || _streamClosed) return;

    try {
      final messages = _decoder.addBytes(bytes);

      for (final message in messages) {
        if (_stopped || _streamClosed) break;

        LspDiagnosticsLogger.log(
          'SERVER ➔ CLIENT: ${jsonEncode(message)}',
        );

        _fromServer.add(
          Map<String, Object?>.from(message),
        );
      }
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _handleClientMessage(
    Map<String, Object?> message,
  ) {
    if (_stopped || _streamClosed) return;

    LspDiagnosticsLogger.log(
      'CLIENT ➔ SERVER: ${jsonEncode(message)}',
    );

    unawaited(_writeMessage(message));
  }

  Future<void> _writeMessage(
    Map<String, Object?> message,
  ) async {
    if (_stopped) return;

    try {
      final bytes = LspStdioMessageEncoder.encode(message);
      _process.stdin.add(bytes);
      await _process.stdin.flush();
    } catch (error, stackTrace) {
      _fail(error, stackTrace);
    }
  }

  void _handleStdoutDone() {
    _stdoutFinished = true;

    if (_stopped || _streamClosed) return;

    unawaited(_closeStream());
  }

  void _handleExitCode(int code) {
    _stopped = true;

    if (code != 0) {
      _fail(
        ProcessException(
          _executable,
          _arguments,
          'Analysis Server encerrou com codigo $code.',
          code,
        ),
        StackTrace.current,
      );
      return;
    }

    unawaited(_closeStream());
  }

  void _fail(Object error, StackTrace stackTrace) {
    if (_stopped || _streamClosed) return;

    if (!_fromServer.isClosed) {
      _fromServer.addError(error, stackTrace);
    }

    unawaited(_closeStream());
  }

  Future<void> _closeStream() async {
    if (_streamClosed) return;

    _streamClosed = true;

    if (!_fromServer.isClosed) {
      await _fromServer.close();
    }
  }

  Future<void> stop() async {
    if (_stopped) return;

    _stopped = true;

    try {
      await _stdoutSubscription?.cancel();
    } catch (_) {}

    try {
      await _stderrSubscription?.cancel();
    } catch (_) {}

    try {
      _process.stdin.close();
    } catch (_) {}

    try {
      _process.kill();
    } catch (_) {}

    try {
      await _exitFuture.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {}

    await _closeStream();
  }
}
