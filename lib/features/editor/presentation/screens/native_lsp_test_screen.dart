import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_monaco/flutter_monaco.dart';

import '../../native_lsp/native_lsp_logger.dart';
import '../../native_lsp/native_lsp_transport_service.dart';

/// Tela experimental para validar o LSP nativo do Monaco.
///
/// Esta tela nao utiliza o EditorAnalysisCoordinator nem os servicos antigos
/// de autocomplete e Code Actions. O objetivo e testar a conexao isoladamente.
class NativeLspTestScreen extends StatefulWidget {
  const NativeLspTestScreen({
    super.key,
    this.projectPath = '/root/projects/teste',
  });

  /// Caminho do projeto visto de dentro do Ubuntu/PRoot.
  final String projectPath;

  @override
  State<NativeLspTestScreen> createState() =>
      _NativeLspTestScreenState();
}

class _NativeLspTestScreenState extends State<NativeLspTestScreen> {
  static const String _connectionId = 'native-dart-lsp-test';

  MonacoController? _controller;
  LanguageServerConnection? _connection;

  bool _editorReady = false;
  bool _connecting = false;
  bool _connected = false;
  bool _disposed = false;
  bool _testingLog = false;

  String _status = 'Inicializando Monaco...';
  String? _lastError;
  String? _logTestResult;
  bool? _logTestSucceeded;

  @override
  void initState() {
    super.initState();

    unawaited(
      NativeLspLogger.info(
        'test_screen.open',
        details: 'projectPath=${widget.projectPath}',
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;

    final controller = _controller;

    if (controller != null && _connected) {
      unawaited(
        controller.disconnectLanguageServer(_connectionId).catchError(
          (Object error) {
            NativeLspLogger.warning(
              'test_screen.disconnect_on_dispose.failed',
              details: error,
            );
          },
        ),
      );
    }

    unawaited(
      NativeLspLogger.info('test_screen.close'),
    );

    super.dispose();
  }

  void _onEditorReady(MonacoController controller) {
    if (_disposed) {
      return;
    }

    _controller = controller;

    setState(() {
      _editorReady = true;
      _status = 'Monaco pronto. Conexao LSP ainda nao iniciada.';
    });

    unawaited(
      NativeLspLogger.info('test_screen.monaco.ready'),
    );
  }

  /// Testa a gravacao do arquivo pelo proprio aplicativo Android.
  ///
  /// Esse teste e independente da conexao com o Dart Analysis Server.
  Future<void> _testLogWrite() async {
    if (_disposed || _testingLog) {
      return;
    }

    setState(() {
      _testingLog = true;
      _logTestResult = 'Testando a escrita pelo aplicativo...';
      _logTestSucceeded = null;
    });

    try {
      final success = await NativeLspLogger.testWrite();

      if (_disposed) {
        return;
      }

      if (success) {
        final file = File(NativeLspLogger.logPath);
        final exists = await file.exists();

        if (_disposed) {
          return;
        }

        if (exists) {
          final length = await file.length();

          setState(() {
            _logTestSucceeded = true;
            _logTestResult =
                'Gravacao confirmada.\n'
                'Arquivo: ${NativeLspLogger.logPath}\n'
                'Tamanho atual: $length bytes';
          });
        } else {
          setState(() {
            _logTestSucceeded = false;
            _logTestResult =
                'O logger informou sucesso, mas o arquivo nao foi '
                'encontrado.\nCaminho esperado: ${NativeLspLogger.logPath}';
          });
        }
      } else {
        setState(() {
          _logTestSucceeded = false;
          _logTestResult =
              'A gravacao falhou.\n'
              'Caminho: ${NativeLspLogger.logPath}\n'
              'Erro: ${NativeLspLogger.lastWriteError ?? "Erro nao informado."}';
        });
      }
    } catch (error, stackTrace) {
      if (!_disposed) {
        setState(() {
          _logTestSucceeded = false;
          _logTestResult =
              'Excecao durante o teste de gravacao.\n'
              'Caminho: ${NativeLspLogger.logPath}\n'
              'Erro: $error\n$stackTrace';
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

  Future<void> _connect() async {
    if (_disposed || _connecting || _connected) {
      return;
    }

    final controller = _controller;

    if (!_editorReady || controller == null) {
      _showStatus(
        'Aguarde o Monaco terminar de inicializar.',
      );
      return;
    }

    setState(() {
      _connecting = true;
      _lastError = null;
      _status = 'Iniciando Dart Analysis Server no Ubuntu...';
    });

    await NativeLspLogger.info(
      'test_screen.connect.begin',
      details: 'projectPath=${widget.projectPath}',
    );

    try {
      final transport =
          await NativeLspTransportService.createTransport(
        projectPath: widget.projectPath,
      );

      if (_disposed) {
        await transport.onClose?.call();
        return;
      }

      setState(() {
        _status = 'Processo iniciado. Negociando protocolo LSP...';
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

      setState(() {
        _connected = true;
        _status = 'Conectado ao Dart Analysis Server.';
      });

      await NativeLspLogger.info(
        'test_screen.connect.success',
        details: 'connectionId=$_connectionId',
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

  Future<void> _disconnect() async {
    if (_disposed || _connecting) {
      return;
    }

    final controller = _controller;

    if (controller == null || !_connected) {
      return;
    }

    setState(() {
      _status = 'Desconectando do Dart Analysis Server...';
    });

    try {
      await controller.disconnectLanguageServer(_connectionId);

      _connection = null;

      if (!_disposed) {
        setState(() {
          _connected = false;
          _status = 'Desconectado.';
        });
      }

      await NativeLspLogger.info(
        'test_screen.disconnect.success',
      );
    } catch (error, stackTrace) {
      await NativeLspLogger.error(
        'test_screen.disconnect.failed',
        exception: error,
        stackTrace: stackTrace,
      );

      if (!_disposed) {
        setState(() {
          _lastError = error.toString();
          _status = 'Erro ao desconectar.';
        });
      }
    }
  }

  void _showStatus(String message) {
    if (_disposed) {
      return;
    }

    setState(() {
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final canConnect =
        _editorReady && !_connecting && !_connected;

    final canDisconnect =
        _editorReady && !_connecting && _connected;

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
              _buildConnectionPanel(
                canConnect: canConnect,
                canDisconnect: canDisconnect,
              ),
              const Divider(height: 1),
              Expanded(
                child: MonacoEditor(
                  initialText: '''
void main() {
  print('Teste do Monaco com LSP nativo');

  final message = 'Digite aqui para testar o Dart Analysis Server';
  print(message);
}
''',
                  options: const EditorOptions(
                    language: MonacoLanguage.dart,
                    theme: MonacoTheme.vsDark,
                    fontSize: 14,
                    minimap: MonacoMinimapOptions(enabled: false),
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

                    if (!_disposed) {
                      setState(() {
                        _lastError = error.toString();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionPanel({
    required bool canConnect,
    required bool canDisconnect,
  }) {
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 12,
                color: statusColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canConnect ? _connect : null,
                  icon: _connecting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.link),
                  label: Text(
                    _connecting ? 'Conectando...' : 'Conectar LSP',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canDisconnect ? _disconnect : null,
                  icon: const Icon(Icons.link_off),
                  label: const Text('Desconectar'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _testingLog ? null : _testLogWrite,
              icon: _testingLog
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.description_outlined),
              label: Text(
                _testingLog
                    ? 'Testando gravação...'
                    : 'Testar gravação do log',
              ),
            ),
          ),
          if (_logTestResult != null) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _logTestSucceeded == true
                      ? Icons.check_circle
                      : _logTestSucceeded == false
                          ? Icons.error
                          : Icons.info_outline,
                  size: 18,
                  color: _logTestSucceeded == true
                      ? Colors.green
                      : _logTestSucceeded == false
                          ? Colors.red
                          : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _logTestResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _logTestSucceeded == false
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Workspace: ${widget.projectPath}',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          if (_lastError != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              _lastError!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}