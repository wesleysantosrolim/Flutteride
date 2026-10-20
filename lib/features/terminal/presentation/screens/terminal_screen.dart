import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:terminal_view/terminal_view.dart';

import '../../models/ubuntu_session.dart';
import '../../services/ubuntu_session_manager.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() =>
      _TerminalScreenState();
}

class _TerminalScreenState
    extends State<TerminalScreen> {
  final UbuntuSessionManager _manager =
      UbuntuSessionManager.instance;

  late final Terminal _terminal;

  final TerminalController
      _terminalController =
      TerminalController();

  UbuntuSession? _session;

  bool _starting = false;

  bool _sessionReady = false;

  final List<Map<String, String>>
      _shortcutKeys = [
    {
      'label': 'ESC',
      'value': '\x1B',
    },
    {
      'label': 'TAB',
      'value': '\t',
    },
    {
      'label': 'CTRL+C',
      'value': '\x03',
    },
    {
      'label': 'CTRL+D',
      'value': '\x04',
    },
    {
      'label': 'CTRL+Z',
      'value': '\x1A',
    },
    {
      'label': '▲',
      'value': '\x1B[A',
    },
    {
      'label': '▼',
      'value': '\x1B[B',
    },
    {
      'label': '◄',
      'value': '\x1B[D',
    },
    {
      'label': '►',
      'value': '\x1B[C',
    },
    {
      'label': '/',
      'value': '/',
    },
    {
      'label': '-',
      'value': '-',
    },
    {
      'label': '~',
      'value': '~',
    },
    {
      'label': '|',
      'value': '|',
    },
    {
      'label': r'$',
      'value': r'$',
    },
  ];

  @override
  void initState() {
    super.initState();

    _terminal =
        _manager.terminal;

    _terminal.onOutput =
        _handleTerminalOutput;

    _initTerminalWithPermissions();
  }

  // ============================================================
  // INICIALIZAÇÃO
  // ============================================================

  Future<void>
      _initTerminalWithPermissions() async {
    if (_starting) {
      return;
    }

    setState(() {
      _starting = true;
      _sessionReady = false;
    });

    try {
      await _requestStoragePermission();

      await _startUbuntuTerminal();
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  Future<void>
      _requestStoragePermission() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      if (await Permission
              .manageExternalStorage
              .isGranted ||
          await Permission.storage.isGranted) {
        return;
      }

      final statusManage =
          await Permission
              .manageExternalStorage
              .request();

      if (!statusManage.isGranted) {
        await Permission.storage.request();
      }
    } catch (e) {
      debugPrint(
        '[TerminalScreen] Erro solicitando permissão '
        'de armazenamento: $e',
      );
    }
  }

  // ============================================================
  // CONTROLE DE TECLAS
  // ============================================================

  void _sendKey(String value) {
    final session = _session;

    if (session == null ||
        session.isClosed) {
      return;
    }

    try {
      session.write(
        utf8.encode(value),
      );
    } catch (e) {
      debugPrint(
        '[TerminalScreen] Erro ao enviar tecla para o PTY: $e',
      );
    }
  }

  void _handleTerminalOutput(
    String data,
  ) {
    final session = _session;

    if (session == null ||
        session.isClosed) {
      return;
    }

    try {
      session.write(
        utf8.encode(data),
      );
    } catch (e) {
      debugPrint(
        '[TerminalScreen] Erro ao enviar dados para o PTY: $e',
      );
    }
  }

  // ============================================================
  // CLIPBOARD
  // ============================================================

  Future<void> _copySelection() async {
    final selection =
        _terminalController.selection;

    if (selection == null) {
      _showMessage(
        'Nenhum texto selecionado',
      );

      return;
    }

    final text =
        _terminal.buffer.getText(
      selection,
    );

    if (text.isEmpty) {
      _showMessage(
        'Nenhum texto selecionado',
      );

      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: text,
      ),
    );

    _terminalController.clearSelection();

    _showMessage(
      'Texto selecionado copiado',
    );
  }

  Future<void> _copyAllTerminal() async {
    final text =
        _terminal.buffer.getText();

    if (text.isEmpty) {
      _showMessage(
        'O terminal está vazio',
      );

      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: text,
      ),
    );

    _showMessage(
      'Log completo copiado '
      '(${text.length} caracteres)',
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration:
              const Duration(
            seconds: 2,
          ),
        ),
      );
  }

  // ============================================================
  // UBUNTU
  // ============================================================

  Future<void>
      _startUbuntuTerminal() async {
    try {
      debugPrint(
        '[TerminalScreen] Obtendo sessão Ubuntu...',
      );

      final session =
          await _manager.createTerminalSession();

      if (!mounted) {
        return;
      }

      _session = session;

      // --------------------------------------------------------
      // Redimensionamento do PTY
      // --------------------------------------------------------

      _terminal.onResize = (
        w,
        h,
        pw,
        ph,
      ) {
        if (session.isClosed) {
          return;
        }

        try {
          session.resize(
            h,
            w,
          );
        } catch (e) {
          debugPrint(
            '[TerminalScreen] Erro redimensionando PTY: $e',
          );
        }
      };

      setState(() {
        _sessionReady =
            !session.isClosed;
      });

      debugPrint(
        '[TerminalScreen] Sessão Ubuntu pronta.',
      );
    } catch (e) {
      debugPrint(
        '[TerminalScreen] Erro ao iniciar Ubuntu: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _sessionReady = false;
      });

      _terminal.write(
        '\r\n'
        'Erro ao iniciar terminal Ubuntu:\r\n'
        '$e\r\n',
      );
    }
  }

  // ============================================================
  // REINICIAR SESSÃO
  // ============================================================

  Future<void> _restartTerminal() async {
    if (_starting) {
      return;
    }

    setState(() {
      _starting = true;
      _sessionReady = false;
    });

    try {
      _manager.closeTerminalSession();

      _terminal.eraseDisplay();

      _terminal.write(
        'Reiniciando sessão Ubuntu...\r\n',
      );

      final session =
          await _manager.createTerminalSession(
        forceNew: true,
      );

      if (!mounted) {
        return;
      }

      _session = session;

      _terminal.onResize = (
        w,
        h,
        pw,
        ph,
      ) {
        if (session.isClosed) {
          return;
        }

        try {
          session.resize(
            h,
            w,
          );
        } catch (e) {
          debugPrint(
            '[TerminalScreen] Erro redimensionando PTY: $e',
          );
        }
      };

      setState(() {
        _sessionReady = true;
      });
    } catch (e) {
      debugPrint(
        '[TerminalScreen] Erro reiniciando terminal: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _sessionReady = false;
      });

      _terminal.write(
        '\r\n'
        'Erro ao reiniciar terminal Ubuntu:\r\n'
        '$e\r\n',
      );
    } finally {
      if (mounted) {
        setState(() {
          _starting = false;
        });
      }
    }
  }

  // ============================================================
  // TOOLBAR
  // ============================================================

  Widget _buildTerminalToolbar() {
    return Container(
      height: 44,
      color: const Color(
        0xFF1E1E1E,
      ),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                const Icon(
                  Icons.terminal,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(
                  width: 8,
                ),
                const Text(
                  'Ubuntu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                if (_starting)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                else if (_sessionReady)
                  const Icon(
                    Icons.circle,
                    color: Colors.green,
                    size: 8,
                  )
                else
                  const Icon(
                    Icons.circle,
                    color: Colors.redAccent,
                    size: 8,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reiniciar terminal',
            icon: const Icon(
              Icons.refresh,
              color: Colors.white70,
              size: 19,
            ),
            onPressed: _starting
                ? null
                : _restartTerminal,
          ),
          IconButton(
            tooltip: 'Copiar seleção',
            icon: const Icon(
              Icons.content_copy,
              color: Colors.white70,
              size: 19,
            ),
            onPressed: _copySelection,
          ),
          IconButton(
            tooltip: 'Copiar log completo',
            icon: const Icon(
              Icons.library_books_outlined,
              color: Colors.white70,
              size: 19,
            ),
            onPressed: _copyAllTerminal,
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutToolbar() {
    return Container(
      color: const Color(
        0xFF1E1E1E,
      ),
      height: 48,
      child: SingleChildScrollView(
        scrollDirection:
            Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 6,
        ),
        child: Row(
          children:
              _shortcutKeys.map(
            (shortcut) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 3,
                ),
                child: Material(
                  color:
                      const Color(
                    0xFF333333,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    4,
                  ),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(
                      4,
                    ),
                    onTap: () =>
                        _sendKey(
                      shortcut['value']!,
                    ),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      alignment:
                          Alignment.center,
                      child: Text(
                        shortcut['label']!,
                        style:
                            const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight:
                              FontWeight.bold,
                          fontFamily:
                              'monospace',
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ).toList(),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Ubuntu Terminal',
        ),
        backgroundColor:
            const Color(0xFF1E1E1E),
        actions: [
          IconButton(
            tooltip: 'Reiniciar terminal',
            icon: const Icon(
              Icons.refresh,
            ),
            onPressed: _starting
                ? null
                : _restartTerminal,
          ),
          IconButton(
            tooltip: 'Copiar seleção',
            icon: const Icon(
              Icons.content_copy,
            ),
            onPressed:
                _copySelection,
          ),
          IconButton(
            tooltip: 'Copiar log completo',
            icon: const Icon(
              Icons.library_books_outlined,
            ),
            onPressed:
                _copyAllTerminal,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTerminalToolbar(),
            Expanded(
              child: TerminalView(
                _terminal,
                controller:
                    _terminalController,
                autofocus: true,
                textStyle:
                    const TerminalStyle(
                  fontSize: 13,
                  fontFamily:
                      'monospace',
                ),
                cursorType:
                    TerminalCursorType.block,
                alwaysShowCursor: true,
              ),
            ),
            _buildShortcutToolbar(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    // A sessão Ubuntu pertence ao
    // UbuntuSessionManager e continua viva
    // durante a navegação.
    _terminal.onOutput = null;
    _terminal.onResize = null;

    _terminalController.dispose();

    super.dispose();
  }
}