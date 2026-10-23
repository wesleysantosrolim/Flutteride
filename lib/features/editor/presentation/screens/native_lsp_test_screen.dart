
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

/// Tela experimental para integrar o Monaco ao Dart Analysis Server.
class NativeLspTestScreen extends StatefulWidget {
  const NativeLspTestScreen({
    super.key,
    this.projectPath = '/root/projects/casa',
  });

  final String projectPath;

  @override
  State<NativeLspTestScreen> createState() => _NativeLspTestScreenState();
}

class _NativeLspTestScreenState extends State<NativeLspTestScreen> {
  static const String _connectionId = 'native-dart-lsp-test';
  static const String _completionProviderId =
      'native-lsp-server-completion-test';
  static const Duration _syncDelay = Duration(milliseconds: 250);

  MonacoController? _controller;
  MonacoDocument? _document;
  LanguageServerConnection? _connection;
  MonacoCompletionRegistration? _completionRegistration;

  StreamSubscription<MonacoContentChanged>? _contentSubscription;
  StreamSubscription<Map<String, Object?>>?
      _completionDeliverySubscription;

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
  bool _manualDocumentSync = false;
  bool _completionInFlight = false;

  int _documentVersion = 1;

  @override
  void initState() {
    super.initState();

    unawaited(
      NativeLspLogger.info(
        'test_screen.open',
        details: 'projectPath=${widget.projectPath}; uri=$_documentUri',
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();

    unawaited(_contentSubscription?.cancel() ?? Future<void>.value());
    unawaited(
      _completionDeliverySubscription?.cancel() ??
          Future<void>.value(),
    );

    final registration = _completionRegistration;
    _completionRegistration = null;

    if (registration != null) {
      unawaited(
        registration.dispose().catchError((Object error) {
          NativeLspLogger.warning(
            'completion_provider.dispose.failed',
            details: error,
          );
        }),
      );
    }

    final connection = _connection;
    _connection = null;

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


  Future<void> _logMonacoRuntimeBundle() async {
    try {
      await MonacoAssets.ensureReady();
      final info = await MonacoAssets.assetInfo();

      final bundle = File(
        p.join(info.path, 'min', 'vs', 'index-DZH_zysX.js'),
      );

      final exists = await bundle.exists();
      var bytes = 0;
      var traceMarker = false;
      var entryMarker = false;

      if (exists) {
        final js = await bundle.readAsString(encoding: utf8);
        bytes = await bundle.length();
        traceMarker = js.contains('__fm_native_lsp_trace');
        entryMarker = js.contains('Entrou em provideCompletionItems');
      }

      final sentinel = File(p.join(info.path, '.monaco_complete'));
      final sentinelValue = await sentinel.exists()
          ? (await sentinel.readAsString()).trim()
          : 'missing';

      await NativeLspLogger.info(
        'monaco.runtime.bundle',
        details: 'version=${info.monacoVersion}; '
            'cachePath=${info.path}; '
            'bundleExists=$exists; '
            'bundleBytes=$bytes; '
            'traceMarker=$traceMarker; '
            'entryMarker=$entryMarker; '
            'sentinel=$sentinelValue',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'monaco.runtime.bundle.failed',
        exception: error,
        stackTrace: stackTrace,
      );
    }
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
      details:
          'guestPath=${widget.projectPath}/lib/app.dart; '
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
      details:
          'path=$hostFilePath; characters=${text.length}; '
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
        _status = 'Monaco pronto. Iniciando Dart Analysis Server...';
      });
    }

    await NativeLspLogger.info('test_screen.monaco.ready');
    await _logMonacoRuntimeBundle();

    if (!_disposed) {
      unawaited(_connect());
    }
  }

  LspBridgedTransport _instrumentTransport(
    LspBridgedTransport original,
  ) {
    return LspBridgedTransport(
      fromServer: original.fromServer.map((message) {
        final method = message['method'];
        final id = message['id'];

        final payload = <String, Object?>{
          if (message.containsKey('params')) 'params': message['params'],
          if (message.containsKey('result')) 'result': message['result'],
          if (message.containsKey('error')) 'error': message['error'],
        };

        String eventName = 'lsp.server.message';

        if (method == 'client/registerCapability') {
          eventName = 'lsp.server.register_capability';
        } else if (method == 'textDocument/publishDiagnostics') {
          eventName = 'lsp.server.publish_diagnostics';
        } else if (method == null && message.containsKey('result')) {
          eventName = 'lsp.server.response';
        } else if (method == null && message.containsKey('error')) {
          eventName = 'lsp.server.response_error';
        }

        unawaited(
          NativeLspLogger.info(
            eventName,
            details:
                'method=${method ?? "(response)"}; '
                'id=${id ?? "(notification)"}; '
                'payload=${_shortJson(payload, maxLength: 4000)}',
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
    final id = message['id'];
    final responseError = message['error'];
    final isResponse = method == null && message.containsKey('id');

    final payload = isResponse
        ? <String, Object?>{
            if (message.containsKey('result')) 'result': message['result'],
            if (responseError != null) 'error': responseError,
          }
        : message['params'];

    String eventName = 'lsp.client.message';

    if (method == 'textDocument/completion') {
      eventName = 'lsp.client.completion_request';
    } else if (method == 'textDocument/didOpen') {
      eventName = 'lsp.client.did_open';
    } else if (method == 'textDocument/didChange') {
      eventName = 'lsp.client.did_change';
    } else if (method == 'initialize') {
      eventName = 'lsp.client.initialize';
    } else if (method == 'initialized') {
      eventName = 'lsp.client.initialized';
    } else if (isResponse && responseError != null) {
      eventName = 'lsp.client.response_error';
    } else if (isResponse) {
      eventName = 'lsp.client.response';
    }

    unawaited(
      NativeLspLogger.info(
        eventName,
        details:
            'method=${method ?? "(response)"}; '
            'id=${id ?? "(notification)"}; '
            'payload=${_shortJson(payload, maxLength: 4000)}',
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

    if (!_editorReady || controller == null) {
      _showStatus('Aguarde o Monaco ficar pronto.');
      return;
    }

    setState(() {
      _connecting = true;
      _lastError = null;
      _lastCompletion = null;
      _status = 'Iniciando Dart Analysis Server...';
    });

    try {
      await NativeLspLogger.info(
        'test_screen.connect.begin',
        details: 'projectPath=${widget.projectPath}; uri=$_documentUri',
      );

      final rawTransport =
          await NativeLspTransportService.createTransport(
        projectPath: widget.projectPath,
      );

      if (_disposed) {
        await rawTransport.onClose?.call();
        return;
      }

      final transport = _instrumentTransport(rawTransport);

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
        'test_screen.connect.server_initialized',
        details:
            'connectionId=$_connectionId; '
            'projectPath=${widget.projectPath}',
      );

      _completionDeliverySubscription =
          connection.completionDeliveries.listen(
        (delivery) {
          unawaited(
            NativeLspLogger.jsonDump(
              'monaco.completion.delivery',
              delivery,
            ),
          );

          if (_disposed || !mounted) return;

          setState(() {
            _lastCompletion =
                'Entrega de completion observada:\n'
                'URI: ${delivery['uri'] ?? '(desconhecida)'}\n'
                'Posicao: ${delivery['position'] ?? '(desconhecida)'}\n'
                'Quantidade: '
                '${delivery['suggestionCount'] ?? '(nao informada)'}\n'
                'Resultado:\n'
                '${_shortJson(delivery['result'], maxLength: 8000)}';

            _status = delivery['error'] != null
                ? 'O provider de completion apresentou erro.'
                : 'Entrega de completion registrada.';
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          unawaited(
            NativeLspLogger.error(
              'monaco.completion.delivery_stream.error',
              exception: error,
              stackTrace: stackTrace,
            ),
          );
        },
      );

      if (mounted && !_disposed) {
        setState(() {
          _status = 'Servidor conectado. Carregando lib/app.dart...';
        });
      }

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
      _documentVersion = 1;

      await _contentSubscription?.cancel();

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
          _status = 'Arquivo carregado. Sincronizando com o servidor...';
        });
      }

      _manualDocumentSync = true;
      await _sendDidOpen();

      if (_disposed) return;

      await _registerDynamicCompletionProvider();

      if (_disposed) return;

      if (mounted) {
        setState(() {
          _connected = true;
          _documentReady = true;
          _status = 'Conectado. lib/app.dart aberto e sincronizado.';
        });
      }

      await NativeLspLogger.info(
        'test_screen.connect.success',
        details:
            'projectPath=${widget.projectPath}; uri=$_documentUri; '
            'documentReady=$_documentReady',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.connect.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      final failedConnection = _connection;
      _connection = null;

      _manualDocumentSync = false;
      _connected = false;
      _documentReady = false;
      _syncTimer?.cancel();

      await _contentSubscription?.cancel();
      _contentSubscription = null;

      await _completionDeliverySubscription?.cancel();
      _completionDeliverySubscription = null;

      if (failedConnection != null) {
        try {
          await failedConnection.disconnect();
        } catch (disconnectError, disconnectStackTrace) {
          await NativeLspLogger.error(
            'test_screen.connect.cleanup.failed',
            exception: disconnectError,
            stackTrace: disconnectStackTrace,
          );
        }
      }

      if (!_disposed && mounted) {
        setState(() {
          _connected = false;
          _documentReady = false;
          _lastError = error.toString();
          _status = 'Falha ao conectar ou abrir lib/app.dart.';
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

  Future<void> _sendDidOpen() async {
    final connection = _connection;
    final document = _document;

    if (connection == null || document == null) return;

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
      'test_screen.did_open.sent',
      details:
          'uri=$_documentUri; version=$_documentVersion; '
          'characters=${content.length}',
    );
  }

  void _scheduleDocumentSync() {
    if (_disposed || !_connected || !_manualDocumentSync || _syncing) {
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
        'test_screen.did_change.sent',
        details:
            'uri=$_documentUri; version=$_documentVersion; '
            'characters=${content.length}',
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
      _showStatus('A sincronizacao manual nao esta ativa.');
      return;
    }

    await _sendDidChange();
    _showStatus('Sincronizacao manual do documento executada.');
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncate()) {
      return value.toInt();
    }
    return null;
  }

  /// Converte CompletionItemKind do protocolo LSP para os tipos Monaco.
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
      case 8:
        return CompletionItemKind.interfaceType;
      case 9:
        return CompletionItemKind.module;
      case 10:
        return CompletionItemKind.property;
      case 11:
        return CompletionItemKind.unit;
      case 12:
        return CompletionItemKind.value;
      case 13:
        return CompletionItemKind.enumType;
      case 14:
        return CompletionItemKind.keyword;
      case 15:
        return CompletionItemKind.snippet;
      case 16:
        return CompletionItemKind.color;
      case 17:
        return CompletionItemKind.file;
      case 18:
        return CompletionItemKind.reference;
      case 19:
        return CompletionItemKind.folder;
      case 20:
        return CompletionItemKind.enumMember;
      case 21:
        return CompletionItemKind.constant;
      case 22:
        return CompletionItemKind.struct;
      case 23:
        return CompletionItemKind.event;
      case 24:
        return CompletionItemKind.operatorType;
      case 25:
        return CompletionItemKind.typeParameter;
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

  /// Converte uma range LSP (indices iniciados em zero) para Monaco.
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
        endColumn == null ||
        startLine < 0 ||
        startColumn < 0 ||
        endLine < 0 ||
        endColumn < 0) {
      return null;
    }

    return Range(
      startLine: startLine + 1,
      startColumn: startColumn + 1,
      endLine: endLine + 1,
      endColumn: endColumn + 1,
    );
  }

  /// Transforma a resposta LSP nos objetos de completion usados pelo Monaco.
  List<CompletionItem> _convertCompletionItems(List<dynamic> rawItems) {
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
        if (newText is String) insertText = newText;

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

      final commitCharacters = raw['commitCharacters'];
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
          commitCharacters: commitCharacters is List
              ? commitCharacters.map((value) => value.toString()).toList()
              : null,
          insertTextRules: rules,
        ),
      );
    }

    return converted;
  }

  /// Normaliza o contexto antes de enviar a solicitação ao servidor.
  ///
  /// LSP CompletionTriggerKind:
  /// 1 = Invoked, 2 = TriggerCharacter, 3 = TriggerForIncompleteCompletions.
  Map<String, Object?> _completionContext(
    CompletionRequest request,
  ) {
    final requestedKind = request.triggerKind;

    final triggerKind = requestedKind == 3
        ? 3
        : requestedKind == 2 &&
                request.triggerCharacter != null &&
                request.triggerCharacter!.length == 1
            ? 2
            : 1;

    return {
      'triggerKind': triggerKind,
      if (triggerKind == 2)
        'triggerCharacter': request.triggerCharacter!,
    };
  }

  void _reportCompletionResult({
    required Uri uri,
    required int line,
    required int character,
    required int received,
    required List<CompletionItem> suggestions,
  }) {
    if (_disposed || !mounted) return;

    final labels = suggestions
        .take(30)
        .map((item) => item.label)
        .toList();

    setState(() {
      _lastCompletion =
          'Resposta do Dart Analysis Server:\n'
          'URI: $uri\n'
          'Posicao LSP: linha $line, coluna $character\n'
          'Itens recebidos: $received\n'
          'Sugestoes convertidas: ${suggestions.length}\n'
          '${labels.join(', ')}';

      _status = suggestions.isEmpty
          ? 'O servidor respondeu sem sugestoes para esta posicao.'
          : 'O provider nativo recebeu ${suggestions.length} sugestoes.';
    });
  }

  Future<void> _registerDynamicCompletionProvider() async {
    final controller = _controller;

    if (_disposed || controller == null) return;
    if (_completionRegistration != null) return;

    _completionRegistration = await controller.registerCompletions(
      id: _completionProviderId,
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
        final connection = _connection;

        if (_disposed ||
            !_connected ||
            connection == null ||
            !_documentReady) {
          return const CompletionList(suggestions: []);
        }

        // O Analysis Server pode rejeitar duas requests de completion
        // simultaneas. A request em andamento fica responsavel pela resposta.
        if (_completionInFlight) {
          await NativeLspLogger.warning(
            'monaco.completion.dynamic.skipped',
            details: 'reason=request_in_flight',
          );
          return const CompletionList(suggestions: []);
        }

        _completionInFlight = true;

        final uri = request.uri ?? _documentUri;
        final position = request.position;
        final line = position.lineZeroBased;
        final character = position.columnZeroBased;

        try {
          // Sincroniza o documento antes de consultar o servidor.
          await _sendDidChange();

          if (_disposed || _connection != connection) {
            return const CompletionList(suggestions: []);
          }

          final context = _completionContext(request);

          await NativeLspLogger.info(
            'monaco.completion.dynamic.request',
            details:
                'uri=$uri; line=$line; character=$character; '
                'triggerKind=${context['triggerKind']}; '
                'triggerCharacter=${context['triggerCharacter'] ?? "(none)"}',
          );

          final dynamic response = await connection.sendRequest(
            'textDocument/completion',
            {
              'textDocument': {'uri': uri.toString()},
              'position': {
                'line': line,
                'character': character,
              },
              'context': context,
            },
            const Duration(seconds: 30),
          );

          List<dynamic> rawItems = <dynamic>[];
          bool isIncomplete = false;

          if (response is Map && response['items'] is List) {
            rawItems = List<dynamic>.from(response['items'] as List);
            isIncomplete = response['isIncomplete'] == true;
          } else if (response is List) {
            rawItems = List<dynamic>.from(response);
          } else if (response == null) {
            await NativeLspLogger.warning(
              'monaco.completion.dynamic.null_result',
              details: 'uri=$uri; line=$line; character=$character',
            );
          } else {
            await NativeLspLogger.warning(
              'monaco.completion.dynamic.unexpected_result',
              details:
                  'type=${response.runtimeType}; '
                  'value=${_shortJson(response, maxLength: 1000)}',
            );
          }

          final suggestions = _convertCompletionItems(rawItems);

          await NativeLspLogger.info(
            'monaco.completion.dynamic.success',
            details:
                'uri=$uri; line=$line; character=$character; '
                'received=${rawItems.length}; '
                'converted=${suggestions.length}; '
                'isIncomplete=$isIncomplete',
          );

          _reportCompletionResult(
            uri: uri,
            line: line,
            character: character,
            received: rawItems.length,
            suggestions: suggestions,
          );

          return CompletionList(
            suggestions: suggestions,
            isIncomplete: isIncomplete,
          );
        } catch (error, stackTrace) {
          await NativeLspLogger.error(
            'monaco.completion.dynamic.failed',
            exception: error,
            stackTrace: stackTrace,
          );

          if (!_disposed && mounted) {
            setState(() {
              _lastError = error.toString();
              _status = 'Falha na requisicao de completion.';
            });
          }

          return const CompletionList(suggestions: []);
        } finally {
          _completionInFlight = false;
        }
      },
    );

    await NativeLspLogger.info(
      'monaco.completion.dynamic.registered',
      details: 'providerId=$_completionProviderId',
    );
  }

  /// Aciona apenas o mecanismo de sugestões nativo do Monaco.
  ///
  /// A consulta ao servidor acontece dentro do provider registrado acima.
  /// Assim, o botão não dispara uma segunda textDocument/completion.
  Future<void> _testCompletion() async {
    if (_disposed || _testing) return;

    final controller = _controller;

    if (!_connected ||
        controller == null ||
        _document == null ||
        !_documentReady) {
      _showStatus('Conecte o LSP antes de testar completion.');
      return;
    }

    setState(() {
      _testing = true;
      _lastCompletion = null;
      _lastError = null;
      _status = 'Acionando as sugestoes nativas do Monaco...';
    });

    try {
      await _sendDidChange();

      if (_disposed || !_connected) return;

      await NativeLspLogger.info(
        'test_screen.completion.native_trigger',
        details: 'uri=$_documentUri; providerId=$_completionProviderId',
      );

      await controller.executeAction(
        const MonacoAction('editor.action.triggerSuggest'),
      );

      if (_disposed || !mounted) return;

      setState(() {
        _status =
            'Comando nativo enviado. Aguardando o provider consultar o servidor...';
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
          _status = 'Falha ao acionar completion nativo.';
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
      final registration = _completionRegistration;
      _completionRegistration = null;

      if (registration != null) {
        await registration.dispose();
      }

      await connection.disconnect();

      _connection = null;
      _connected = false;
      _documentReady = false;
      _manualDocumentSync = false;
      _completionInFlight = false;

      await NativeLspLogger.info('test_screen.disconnect.success');

      if (!_disposed && mounted) {
        setState(() {
          _status = 'Desconectado.';
        });
      }
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
      supportedLocales: const [Locale('pt', 'BR')],
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
                  initialText:
                      '// Aguardando conexao com Dart Analysis Server...',
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
                  constraints: const BoxConstraints(maxHeight: 180),
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
                onPressed:
                    _editorReady && !_connecting && !_connected
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
                onPressed: _connected && !_testing ? _testCompletion : null,
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
                onPressed:
                    _connected && _manualDocumentSync ? _syncNow : null,
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
              style: const TextStyle(color: Colors.red, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
