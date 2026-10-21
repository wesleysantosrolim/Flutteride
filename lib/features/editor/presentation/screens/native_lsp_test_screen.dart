
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_monaco/flutter_monaco.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../native_lsp/native_lsp_logger.dart';
import '../../native_lsp/native_lsp_transport_service.dart';

/// Tela experimental para investigar a integracao entre Monaco
/// e Dart Analysis Server por meio do cliente LSP nativo do Monaco.
class NativeLspTestScreen extends StatefulWidget {
  const NativeLspTestScreen({
    super.key,
    this.projectPath = '/root/projects/casa',
  });

  final String projectPath;

  @override
  State<NativeLspTestScreen> createState() =>
      _NativeLspTestScreenState();
}

class _NativeLspTestScreenState extends State<NativeLspTestScreen> {
  static const String _connectionId = 'native-dart-lsp-test';

  static const Duration _syncDelay = Duration(milliseconds: 250);

  static const Duration _didOpenTimeout = Duration(milliseconds: 500);

  MonacoController? _controller;
  MonacoDocument? _document;
  LanguageServerConnection? _connection;

  StreamSubscription<MonacoContentChanged>? _contentSubscription;
  Timer? _syncTimer;

  late final Uri _documentUri = Uri.file(
    '${widget.projectPath}/lib/app.dart',
  );

  String _sourceText = '';
  String _status = 'Inicializando Monaco...';
  String? _lastError;
  String? _lastCompletion;
  String? _lastDocumentPath;

  bool _editorReady = false;
  bool _documentReady = false;
  bool _connecting = false;
  bool _connected = false;
  bool _disposed = false;
  bool _testing = false;
  bool _syncing = false;
  bool _didOpenObserved = false;
  bool _manualDocumentSync = false;

  int _documentVersion = 1;

  @override
  void initState() {
    super.initState();

    unawaited(
      NativeLspLogger.info(
        'test_screen.open',
        details: 'projectPath=${widget.projectPath}; '
            'uri=$_documentUri',
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();

    unawaited(
      _contentSubscription?.cancel() ?? Future<void>.value(),
    );

    final connection = _connection;
    if (connection != null) {
      unawaited(
        connection.disconnect().catchError((Object error) {
          NativeLspLogger.warning(
            'test_screen.disconnect_on_dispose.failed',
            details: error,
          );
        }),
      );
    }

    unawaited(NativeLspLogger.info('test_screen.close'));
    super.dispose();
  }

  Future<String> _loadProjectFile() async {
    final appDirectory = await getApplicationSupportDirectory();

    final relativeProjectPath = widget.projectPath
        .replaceFirst(RegExp(r'^/+'), '')
        .split('/');

    final hostProjectDirectory = p.joinAll([
      appDirectory.path,
      'ubuntu_rootfs',
      ...relativeProjectPath,
    ]);

    final hostFilePath = p.join(
      hostProjectDirectory,
      'lib',
      'app.dart',
    );

    final file = File(hostFilePath);

    await NativeLspLogger.info(
      'test_screen.file.load.begin',
      details: 'guestPath=${widget.projectPath}/lib/app.dart; '
          'hostPath=$hostFilePath',
    );

    if (!await file.exists()) {
      throw FileSystemException(
        'O arquivo lib/app.dart nao foi encontrado no rootfs.',
        hostFilePath,
      );
    }

    final text = await file.readAsString(encoding: utf8);

    if (text.trim().isEmpty) {
      throw FileSystemException(
        'O arquivo lib/app.dart esta vazio.',
        hostFilePath,
      );
    }

    _lastDocumentPath = hostFilePath;

    await NativeLspLogger.info(
      'test_screen.file.load.success',
      details: 'path=$hostFilePath; '
          'characters=${text.length}; '
          'lines=${text.split('\n').length}',
    );

    return text;
  }

  Future<void> _onEditorReady(MonacoController controller) async {
    if (_disposed) return;

    _controller = controller;

    if (mounted) {
      setState(() {
        _editorReady = true;
        _status = 'Monaco pronto. Carregando lib/app.dart...';
      });
    }

    await NativeLspLogger.info('test_screen.monaco.ready');

    try {
      final text = await _loadProjectFile();

      if (_disposed) return;

      final document = await controller.openDocument(
        text: text,
        language: MonacoLanguage.dart,
        uri: _documentUri,
      );

      await controller.activateDocument(document);

      if (_disposed) return;

      _document = document;
      _sourceText = text;

      _contentSubscription = controller.onContentChanged.listen(
        (_) => _scheduleDocumentSync(),
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            NativeLspLogger.error(
              'test_screen.content_stream.error',
              exception: error,
              stackTrace: stackTrace,
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _documentReady = true;
          _status = 'Arquivo real carregado. Conecte o LSP.';
        });
      }

      await NativeLspLogger.info(
        'test_screen.document.ready',
        details: 'uri=${document.uri}; '
            'characters=${text.length}; '
            'contentMatchesFile=${text == await document.getText()}',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.document.load.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (!_disposed && mounted) {
        setState(() {
          _lastError = error.toString();
          _status = 'Falha ao carregar lib/app.dart.';
        });
      }
    }
  }

  LspBridgedTransport _instrumentTransport(
    LspBridgedTransport original,
  ) {
    return LspBridgedTransport(
      fromServer: original.fromServer.map((message) {
        final method = message['method'];
        final id = message['id'];
        final result = message['result'];
        final error = message['error'];

        unawaited(
          NativeLspLogger.info(
            'lsp.server.message',
            details: 'method=${method ?? "(response)"}; '
                'id=${id ?? "(notification)"}; '
                'hasResult=${result != null}; '
                'hasError=${error != null}; '
                'message=${_shortJson(message)}',
          ),
        );

        return message;
      }),
      toServer: (message) {
        _inspectClientMessage(message);
        original.toServer(message);
      },
      onClose: original.onClose,
    );
  }

void _inspectClientMessage(Map<String, Object?> message) {
  final method = message['method'];

  if (method == 'textDocument/didOpen') {
    final params = message['params'];
    final document = params is Map ? params['textDocument'] : null;
    final uri = document is Map ? document['uri']?.toString() : null;

    if (uri == _documentUri.toString()) {
      _didOpenObserved = true;

      unawaited(
        NativeLspLogger.info(
          'test_screen.did_open.observed',
          details: 'uri=$uri; '
              'message=${_shortJson(message)}',
        ),
      );
    }
  }

  // Respostas JSON-RPC nao possuem "method".
  // O log anterior mostrava apenas params=null e ocultava o erro real.
  final responseError = message['error'];
  final isResponse = method == null && message.containsKey('id');

  final Object? loggedPayload = isResponse
      ? <String, Object?>{
          if (message.containsKey('result'))
            'result': message['result'],
          if (responseError != null) 'error': responseError,
        }
      : message['params'];

  unawaited(
    NativeLspLogger.info(
      'lsp.client.message',
      details: 'method=${method ?? "(response)"}; '
          'id=${message['id'] ?? "(notification)"}; '
          'hasResult=${message.containsKey('result')}; '
          'hasError=${responseError != null}; '
          'payload=${_shortJson(loggedPayload, maxLength: 2400)}',
    ),
  );
}

  String _shortJson(Object? value, {int maxLength = 1800}) {
    String result;

    try {
      result = jsonEncode(value);
    } catch (_) {
      result = value.toString();
    }

    if (result.length <= maxLength) return result;

    return '${result.substring(0, maxLength)}...';
  }

  Future<void> _connect() async {
    if (_disposed || _connecting || _connected) return;

    final controller = _controller;

    if (!_editorReady || !_documentReady || controller == null) {
      _showStatus('Aguarde o arquivo real terminar de carregar.');
      return;
    }

    setState(() {
      _connecting = true;
      _lastError = null;
      _status = 'Iniciando Dart Analysis Server...';
    });

    await NativeLspLogger.info(
      'test_screen.connect.begin',
      details: 'projectPath=${widget.projectPath}; '
          'documentUri=$_documentUri',
    );

    try {
      final rawTransport =
          await NativeLspTransportService.createTransport(
        projectPath: widget.projectPath,
      );

      if (_disposed) {
        await rawTransport.onClose?.call();
        return;
      }

      final transport = _instrumentTransport(rawTransport);

      _didOpenObserved = false;

      final connection = await controller.connectLanguageServer(
        id: _connectionId,
        transport: transport,
        initializationTimeout: const Duration(seconds: 45),
      );

      if (_disposed) {
        await connection.disconnect();
        return;
      }

      _connection = connection;

      await NativeLspLogger.info(
        'test_screen.connect.success',
        details: 'connectionId=$_connectionId; '
            'connectionState=${connection.state.status}',
      );

      await Future<void>.delayed(_didOpenTimeout);

      if (_disposed) return;

      if (!_didOpenObserved) {
        await NativeLspLogger.warning(
          'test_screen.did_open.missing',
          details: 'O cliente nativo nao enviou didOpen para '
              '$_documentUri. Tentando reabrir o modelo apos conectar.',
        );

        await _reopenDocumentAfterConnection();

        await Future<void>.delayed(_didOpenTimeout);
      }

      if (_disposed) return;

      if (_didOpenObserved) {
        _manualDocumentSync = false;

        await NativeLspLogger.info(
          'test_screen.did_open.native.success',
          details: 'O cliente nativo abriu o documento: $_documentUri',
        );

        _showStatus(
          'Conectado. Documento aberto pelo cliente nativo do Monaco.',
        );
      } else {
        await NativeLspLogger.warning(
          'test_screen.did_open.native.failed',
          details: 'O didOpen automatico continua ausente apos '
              'reabrir o documento. Ativando sincronizacao manual.',
        );

        await _sendDidOpen();
        _manualDocumentSync = true;

        _showStatus(
          'Conectado. Documento aberto manualmente no servidor.',
        );
      }

      if (mounted && !_disposed) {
        setState(() {
          _connected = true;
        });
      }

      await NativeLspLogger.info(
        'test_screen.connect.ready',
        details: 'didOpenObserved=$_didOpenObserved; '
            'manualDocumentSync=$_manualDocumentSync; '
            'connectionState=${connection.state.status}',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.connect.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (!_disposed && mounted) {
        setState(() {
          _connected = false;
          _lastError = error.toString();
          _status = 'Falha ao conectar ao Dart Analysis Server.';
        });
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  Future<void> _reopenDocumentAfterConnection() async {
    final controller = _controller;
    final oldDocument = _document;

    if (controller == null || oldDocument == null) {
      throw StateError('Monaco ou documento nao esta disponivel.');
    }

    final text = await oldDocument.getText();

    await NativeLspLogger.info(
      'test_screen.document.reopen.begin',
      details: 'uri=$_documentUri; '
          'characters=${text.length}; '
          'connectionActive=${_connection != null}',
    );

    await oldDocument.close();

    if (_disposed) return;

    final newDocument = await controller.openDocument(
      text: text,
      language: MonacoLanguage.dart,
      uri: _documentUri,
    );

    await controller.activateDocument(newDocument);

    if (_disposed) {
      await newDocument.close();
      return;
    }

    _document = newDocument;
    _sourceText = text;

    await NativeLspLogger.info(
      'test_screen.document.reopen.success',
      details: 'uri=${newDocument.uri}; '
          'characters=${text.length}; '
          'didOpenObserved=$_didOpenObserved',
    );
  }

  Future<void> _sendDidOpen() async {
    final connection = _connection;
    final document = _document;

    if (connection == null || document == null) {
      throw StateError(
        'Conexao ou documento ainda nao esta disponivel.',
      );
    }

    final content = await document.getText();

    _sourceText = content;
    _documentVersion = 1;

    await connection.sendNotification(
      'textDocument/didOpen',
      {
        'textDocument': {
          'uri': _documentUri.toString(),
          'languageId': 'dart',
          'version': _documentVersion,
          'text': content,
        },
      },
    );

    await NativeLspLogger.info(
      'lsp.client.didOpen.manual',
      details: 'uri=$_documentUri; '
          'version=$_documentVersion; '
          'characters=${content.length}; '
          'lines=${content.split('\n').length}',
    );

    await connection.sendNotification(
      'workspace/didChangeWorkspaceFolders',
      {
        'event': {
          'added': [
            {
              'uri': Uri.file(widget.projectPath).toString(),
              'name': p.basename(widget.projectPath),
            },
          ],
          'removed': <Object?>[],
        },
      },
    );

    await NativeLspLogger.info(
      'lsp.client.workspace_folders.sent',
      details: 'workspace=${widget.projectPath}',
    );
  }

  void _scheduleDocumentSync() {
    if (_disposed ||
        !_connected ||
        !_manualDocumentSync ||
        _syncing) {
      return;
    }

    _syncTimer?.cancel();

    _syncTimer = Timer(_syncDelay, () {
      unawaited(_sendDidChange());
    });
  }

  Future<void> _sendDidChange() async {
    final connection = _connection;
    final document = _document;

    if (_disposed ||
        connection == null ||
        document == null ||
        !_manualDocumentSync ||
        _syncing) {
      return;
    }

    _syncing = true;

    try {
      final content = await document.getText();

      if (_disposed || content == _sourceText) return;

      _documentVersion++;
      _sourceText = content;

      await connection.sendNotification(
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

      await NativeLspLogger.info(
        'lsp.client.didChange.manual',
        details: 'uri=$_documentUri; '
            'version=$_documentVersion; '
            'characters=${content.length}; '
            'lines=${content.split('\n').length}',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.did_change.failed',
        exception: error,
        stackTrace: stackTrace,
      );
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncNow() async {
    if (!_connected || !_manualDocumentSync) {
      _showStatus(
        'A sincronizacao manual nao esta ativa. '
        'Confira o log de didOpen.',
      );
      return;
    }

    await _sendDidChange();
    _showStatus('Sincronizacao manual do documento executada.');
  }

  /// Solicita completion e aceita os formatos de resposta LSP suportados
  /// pelo cliente customizado do FlutterIDE.
  Future<void> _testCompletion() async {
    if (_disposed || _testing) return;

    final connection = _connection;
    final controller = _controller;
    final document = _document;

    if (!_connected ||
        connection == null ||
        controller == null ||
        document == null) {
      _showStatus('Conecte o LSP antes de testar completion.');
      return;
    }

    setState(() {
      _testing = true;
      _lastCompletion = null;
      _lastError = null;
      _status = 'Sincronizando documento e solicitando completion...';
    });

    try {
      if (_manualDocumentSync) {
        await _sendDidChange();
      }

      final currentText = await document.getText();
      final cursor = await controller.getCursorPosition();

      if (cursor == null) {
        throw StateError(
          'O Monaco nao retornou a posicao atual do cursor.',
        );
      }

      // Monaco usa indices iniciando em 1; o LSP usa indices iniciando em 0.
      final line = cursor.line > 0 ? cursor.line - 1 : 0;
      final character = cursor.column > 0 ? cursor.column - 1 : 0;

      await NativeLspLogger.info(
        'test_screen.completion.request',
        details: 'uri=$_documentUri; '
            'line=$line; character=$character; '
            'monacoLine=${cursor.line}; '
            'monacoColumn=${cursor.column}; '
            'characters=${currentText.length}; '
            'manualSync=$_manualDocumentSync',
      );

      final dynamic response = await connection.sendRequest(
        'textDocument/completion',
        {
          'textDocument': {
            'uri': _documentUri.toString(),
          },
          'position': {
            'line': line,
            'character': character,
          },
          'context': {
            'triggerKind': 1,
          },
        },
        const Duration(seconds: 30),
      );

      // O servidor pode retornar diretamente uma lista de CompletionItem
      // ou um CompletionList com a propriedade "items".
      Map<String, Object?> resultMap = <String, Object?>{};
      List<dynamic> items = <dynamic>[];

      if (response is List) {
        items = List<dynamic>.from(response);
        resultMap = <String, Object?>{
          'isIncomplete': false,
          'items': items,
        };
      } else if (response is Map) {
        resultMap = Map<String, Object?>.from(response);
        dynamic itemsValue = resultMap['items'];

        // Aceita tambem uma resposta que ainda contenha o envelope JSON-RPC.
        if (itemsValue is! List && resultMap['result'] is Map) {
          final nested = Map<String, Object?>.from(
            resultMap['result'] as Map,
          );

          if (nested['items'] is List) {
            resultMap = nested;
            itemsValue = nested['items'];
          }
        }

        if (itemsValue is! List && resultMap['result'] is List) {
          itemsValue = resultMap['result'];
        }

        if (itemsValue is List) {
          items = List<dynamic>.from(itemsValue);
        } else if (resultMap['items'] is List) {
          items = List<dynamic>.from(resultMap['items'] as List);
        }
      } else if (response == null) {
        resultMap = <String, Object?>{
          'isIncomplete': false,
          'items': <Object?>[],
        };
      } else {
        resultMap = <String, Object?>{
          'unexpectedResponseType': response.runtimeType.toString(),
          'response': response.toString(),
          'items': <Object?>[],
        };
      }

      final labels = <String>[];

      for (final value in items) {
        if (value is Map && value['label'] != null) {
          final label = value['label'].toString();

          if (label.isNotEmpty) {
            labels.add(label);
          }
        }
      }

      final completeResponse = _shortJson(
        resultMap,
        maxLength: 10000,
      );

      await NativeLspLogger.info(
        'test_screen.completion.response',
        details: 'uri=$_documentUri; '
            'responseType=${response.runtimeType}; '
            'items=${items.length}; '
            'isIncomplete=${resultMap['isIncomplete']}; '
            'labels=${labels.take(40).join(', ')}; '
            'response=$completeResponse',
      );

      if (_disposed || !mounted) return;

      setState(() {
        _lastCompletion = 'Resposta do Dart Analysis Server:\n'
            'URI: $_documentUri\n'
            'Posicao LSP: linha $line, coluna $character\n'
            'Tipo de resposta: ${response.runtimeType}\n'
            'Itens: ${items.length}\n'
            'isIncomplete: ${resultMap['isIncomplete'] ?? false}\n'
            'Sugestoes: ${labels.isEmpty ? "(nenhuma)" : labels.join(', ')}'
            '\n\nJSON:\n$completeResponse';

        _status = items.isEmpty
            ? 'Completion respondeu, mas retornou zero sugestoes.'
            : 'Completion retornou ${items.length} sugestoes.';
      });
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.completion.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (!_disposed && mounted) {
        setState(() {
          _lastError = error.toString();
          _status = 'Falha no teste de completion.';
        });
      }
    } finally {
      if (!_disposed && mounted) {
        setState(() {
          _testing = false;
        });
      }
    }
  }

  Future<void> _testLogWrite() async {
    try {
      final success = await NativeLspLogger.testWrite();

      if (_disposed || !mounted) return;

      final file = File(NativeLspLogger.logPath);
      final exists = await file.exists();
      final length = exists ? await file.length() : 0;

      setState(() {
        _status = success && exists
            ? 'Gravacao do log confirmada: $length bytes.'
            : 'Falha ao confirmar a gravacao do log.';
      });

      await NativeLspLogger.info(
        'test_screen.log_test',
        details: 'success=$success; exists=$exists; bytes=$length; '
            'path=${NativeLspLogger.logPath}; '
            'lastError=${NativeLspLogger.lastWriteError}',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.log_test.failed',
        exception: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _disconnect() async {
    if (_disposed || _connecting) return;

    final connection = _connection;
    if (connection == null) return;

    _syncTimer?.cancel();

    setState(() {
      _status = 'Desconectando do Dart Analysis Server...';
    });

    try {
      await connection.disconnect();

      _connection = null;
      _connected = false;
      _manualDocumentSync = false;
      _didOpenObserved = false;

      if (!_disposed && mounted) {
        setState(() {
          _status = 'Desconectado.';
        });
      }

      await NativeLspLogger.info('test_screen.disconnect.success');
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.disconnect.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (!_disposed && mounted) {
        setState(() {
          _lastError = error.toString();
          _status = 'Erro ao desconectar.';
        });
      }
    }
  }

  void _showStatus(String message) {
    if (_disposed || !mounted) return;

    setState(() {
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Teste LSP nativo'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildControlPanel(),
              const Divider(height: 1),
              Expanded(
                child: MonacoEditor(
                  initialText: '// Carregando arquivo do projeto...',
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
                    unawaited(
                      NativeLspLogger.error(
                        'test_screen.monaco.error',
                        exception: error,
                        stackTrace: stackTrace,
                      ),
                    );

                    if (!_disposed && mounted) {
                      setState(() {
                        _lastError = error.toString();
                      });
                    }
                  },
                ),
              ),
              if (_lastCompletion != null)
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _lastCompletion!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    final Color statusColor;

    if (_lastError != null) {
      statusColor = Colors.red;
    } else if (_connected) {
      statusColor = Colors.green;
    } else if (_connecting) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.circle, size: 12, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Projeto: ${widget.projectPath}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (_lastDocumentPath != null)
            Text(
              'Arquivo: $_lastDocumentPath',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: _editorReady &&
                        _documentReady &&
                        !_connecting &&
                        !_connected
                    ? _connect
                    : null,
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  _connecting ? 'Conectando...' : 'Conectar LSP',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _connected ? _disconnect : null,
                icon: const Icon(Icons.link_off),
                label: const Text('Desconectar'),
              ),
              FilledButton.tonalIcon(
                onPressed: _connected && !_testing
                    ? _testCompletion
                    : null,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('Testar completion'),
              ),
              OutlinedButton.icon(
                onPressed: _connected && _manualDocumentSync
                    ? _syncNow
                    : null,
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar texto'),
              ),
              OutlinedButton.icon(
                onPressed: _testLogWrite,
                icon: const Icon(Icons.description_outlined),
                label: const Text('Testar log'),
              ),
            ],
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              _lastError!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
