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

/// Tela experimental para validar o LSP nativo do Monaco com conexão automática
/// e um botão dedicado para envio do didOpen.
class NativeLspTestScreen extends StatefulWidget {
  const NativeLspTestScreen({
    super.key,
    this.projectPath = '/root/projects/casa',
  });

  /// Caminho do projeto dentro do Ubuntu/PRoot.
  final String projectPath;

  @override
  State<NativeLspTestScreen> createState() =>
      _NativeLspTestScreenState();
}

class _NativeLspTestScreenState extends State<NativeLspTestScreen> {
  static const String _connectionId = 'native-dart-lsp-test';

  MonacoController? _controller;
  MonacoDocument? _fileDocument;
  LanguageServerConnection? _connection;
  LspBridgedTransport? _activeTransport;

  String? _fileContent;
  String? _fileUri;
  String? _lastError;
  String? _logTestResult;

  bool _editorReady = false;
  bool _documentReady = false;
  bool _loadingFile = true;
  bool _connecting = false;
  bool _connected = false;
  bool _disconnecting = false;
  bool _testingLog = false;
  bool _disposed = false;

  bool? _logTestSucceeded;

  String _status = 'Carregando arquivo do projeto...';

  String get _guestFilePath =>
      p.posix.join(widget.projectPath, 'lib', 'app.dart');

  @override
  void initState() {
    super.initState();

    unawaited(_logOpen());
    unawaited(_loadProjectFile());
  }

  Future<void> _logOpen() async {
    await NativeLspLogger.info(
      'test_screen.open',
      details: 'projectPath=${widget.projectPath}; file=lib/app.dart',
    );
  }

  /// Lê o arquivo real dentro do rootfs usado pelo aplicativo.
  Future<void> _loadProjectFile() async {
    if (_disposed) return;

    try {
      final appDir = await getApplicationSupportDirectory();

      final rootfsPath = p.normalize(
        p.join(appDir.path, 'ubuntu_rootfs'),
      );

      final relativeGuestPath = _guestFilePath.startsWith('/')
          ? _guestFilePath.substring(1)
          : _guestFilePath;

      final androidFilePath = p.normalize(
        p.join(rootfsPath, relativeGuestPath),
      );

      final file = File(androidFilePath);

      if (!await file.exists()) {
        throw FileSystemException(
          'Arquivo não encontrado no rootfs do aplicativo.',
          androidFilePath,
        );
      }

      final content = await file.readAsString(encoding: utf8);

      if (_disposed) return;

      setState(() {
        _fileContent = content;
        _loadingFile = false;
        _status = 'Arquivo carregado. Inicializando Monaco...';
      });

      // Se o editor já estiver pronto, dispara a conexão automática
      if (_editorReady) {
        unawaited(_connect());
      }
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.file.load.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (_disposed) return;

      setState(() {
        _loadingFile = false;
        _lastError = error.toString();
        _status = 'Falha ao carregar app.dart.';
      });
    }
  }

  Future<void> _onEditorReady(MonacoController controller) async {
    if (_disposed) return;

    _controller = controller;

    if (mounted) {
      setState(() {
        _editorReady = true;
        _status = 'Editor pronto.';
        _lastError = null;
      });
    }

    // Se o arquivo já foi carregado, inicia a conexão automática
    if (!_loadingFile && _fileContent != null && !_connected && !_connecting) {
      unawaited(_connect());
    }
  }

  /// Conexão automática ao iniciar a tela ou carregar os recursos.
  Future<void> _connect() async {
    if (_disposed ||
        _connecting ||
        _connected ||
        !_editorReady ||
        _fileContent == null) {
      return;
    }

    final controller = _controller;
    if (controller == null) return;

    setState(() {
      _connecting = true;
      _lastError = null;
      _status = 'Iniciando Dart Analysis Server automaticamente...';
    });

    try {
      final transport = await NativeLspTransportService.createTransport(
        projectPath: widget.projectPath,
      );

      if (_disposed) {
        await transport.onClose?.call();
        return;
      }

      _activeTransport = transport;

      setState(() {
        _status = 'Servidor iniciado. Negociando protocolo LSP...';
      });

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

      // Abre e ativa o documento no Monaco
      final fileUri = Uri.file(_guestFilePath);
      final document = await controller.openDocument(
        text: _fileContent!,
        language: MonacoLanguage.dart,
        uri: fileUri,
      );

      await controller.activateDocument(document);

      if (_disposed) return;

      _fileDocument = document;
      _fileUri = document.uri.toString();

      setState(() {
        _documentReady = true;
        _connected = true;
        _status = 'LSP Conectado! Use o botão abaixo para enviar o didOpen.';
      });

      await NativeLspLogger.info(
        'test_screen.connect.success',
        details: 'connectionId=$_connectionId; uri=$_fileUri',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.connect.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (!_disposed) {
        setState(() {
          _connected = false;
          _documentReady = false;
          _lastError = error.toString();
          _status = 'Falha ao conectar ao Dart Analysis Server.';
        });
      }
    } finally {
      if (!_disposed) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  /// Botão manual para disparar a notificação `textDocument/didOpen`.
  void _sendDidOpen() {
    final transport = _activeTransport;
    final fileUri = _fileUri;
    final content = _fileContent;

    if (transport == null || fileUri == null || content == null) {
      setState(() {
        _status = 'Impossível enviar didOpen: conexão ou documento ausente.';
      });
      return;
    }

    transport.toServer({
      'jsonrpc': '2.0',
      'method': 'textDocument/didOpen',
      'params': {
        'textDocument': {
          'uri': fileUri,
          'languageId': 'dart',
          'version': 1,
          'text': content,
        }
      },
    });

    setState(() {
      _status = 'Notificação textDocument/didOpen enviada com sucesso!';
    });

    unawaited(
      NativeLspLogger.info(
        'test_screen.didOpen.manual_sent',
        details: 'uri=$fileUri',
      ),
    );
  }

  Future<void> _disconnect() async {
    if (_disposed || _connecting || _disconnecting) return;

    final controller = _controller;
    if (controller == null || !_connected) return;

    setState(() {
      _disconnecting = true;
      _status = 'Desconectando...';
    });

    try {
      await controller.disconnectLanguageServer(_connectionId);

      _connection = null;
      _fileDocument = null;
      _activeTransport = null;

      if (!_disposed) {
        setState(() {
          _connected = false;
          _documentReady = false;
          _status = 'Desconectado.';
        });
      }
    } catch (error, stackTrace) {
      if (!_disposed) {
        setState(() {
          _lastError = error.toString();
          _status = 'Erro ao desconectar.';
        });
      }
    } finally {
      if (!_disposed) {
        setState(() {
          _disconnecting = false;
        });
      }
    }
  }

  Future<void> _testLogWrite() async {
    if (_disposed || _testingLog) return;

    setState(() {
      _testingLog = true;
      _logTestResult = 'Testando a escrita do log...';
      _logTestSucceeded = null;
    });

    try {
      final success = await NativeLspLogger.testWrite();
      if (_disposed) return;

      setState(() {
        _logTestSucceeded = success;
        _logTestResult = success
            ? 'Escrita confirmada em: ${NativeLspLogger.logPath}'
            : 'Falha na escrita.';
      });
    } catch (error) {
      if (!_disposed) {
        setState(() {
          _logTestSucceeded = false;
          _logTestResult = 'Erro: $error';
        });
      }
    } finally {
      if (!_disposed) {
        setState(() {
          _testingLog = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connection?.disconnect();
    super.dispose();
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
          title: const Text('Teste LSP Nativo (Auto & didOpen)'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildConnectionPanel(),
              const Divider(height: 1),
              Expanded(child: _buildEditorArea()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditorArea() {
    if (_loadingFile) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_fileContent == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 40),
              const SizedBox(height: 12),
              const Text('Não foi possível carregar lib/app.dart.'),
              const SizedBox(height: 8),
              SelectableText(_lastError ?? 'Erro não informado.'),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _loadingFile = true;
                    _lastError = null;
                  });
                  unawaited(_loadProjectFile());
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        MonacoEditor(
          options: const EditorOptions(
            language: MonacoLanguage.dart,
            theme: MonacoTheme.vsDark,
            fontSize: 14,
            minimap: MonacoMinimapOptions(enabled: false),
          ),
          onReady: (controller) {
            unawaited(_onEditorReady(controller));
          },
          onError: (error, stackTrace) {
            if (!_disposed) {
              setState(() {
                _lastError = error.toString();
              });
            }
          },
        ),
        if (_connecting || !_editorReady)
          Positioned(
            top: 8,
            left: 8,
            right: 8,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_status)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildConnectionPanel() {
    final Color statusColor = _lastError != null
        ? Colors.red
        : _connected
            ? Colors.green
            : _connecting
                ? Colors.orange
                : Colors.grey;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
          const SizedBox(height: 6),
          Text(
            'Arquivo: $_guestFilePath',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _connected ? _sendDidOpen : null,
                  icon: const Icon(Icons.send),
                  label: const Text('Enviar didOpen'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _connected ? _disconnect : (_connecting ? null : _connect),
                  icon: Icon(_connected ? Icons.link_off : Icons.link),
                  label: Text(_connected ? 'Desconectar' : 'Reconectar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testingLog ? null : _testLogWrite,
              icon: const Icon(Icons.description_outlined),
              label: const Text('Testar gravação do log'),
            ),
          ),
          if (_logTestResult != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              _logTestResult!,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
