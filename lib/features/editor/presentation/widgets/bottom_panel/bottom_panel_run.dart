import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:terminal_view/terminal_view.dart';

import '../../../../flutter/services/flutter_run_service.dart';

class BottomPanelRun extends StatefulWidget {
  final FlutterRunService? runService;
  final ScrollController? scrollController;

  const BottomPanelRun({
    super.key,
    this.runService,
    this.scrollController,
  });

  @override
  State<BottomPanelRun> createState() =>
      _BottomPanelRunState();
}

class _BottomPanelRunState
    extends State<BottomPanelRun> {
  late final FlutterRunService _runService;
  late final Terminal _terminal;

  StreamSubscription<String>? _outputSubscription;

  bool _isRunning = false;

  @override
  void initState() {
    super.initState();

    _runService =
        widget.runService ??
        FlutterRunService.instance;

    _terminal = Terminal();

    _outputSubscription =
        _runService.output.listen(
      _handleOutput,
    );

    _isRunning = _runService.isRunning;
  }

  void _handleOutput(String output) {
    if (!mounted) {
      return;
    }

    _terminal.write(output);

    final running =
        _runService.isRunning;

    if (_isRunning != running) {
      setState(() {
        _isRunning = running;
      });
    }
  }

  void _clear() {
    _terminal.write(
      '\x1B[2J\x1B[H',
    );
  }

  void _goToBottom() {
    final controller =
        widget.scrollController;

    if (controller == null ||
        !controller.hasClients) {
      return;
    }

    controller.animateTo(
      controller.position.maxScrollExtent,
      duration: const Duration(
        milliseconds: 150,
      ),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _terminal.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: Container(
            width: double.infinity,
            color: const Color(0xFF181818),
            child: TerminalView(
              _terminal,
              scrollController:
                  widget.scrollController,
              autofocus: false,
              theme: _terminalTheme(),
              textStyle: const TerminalStyle(
                fontFamily: 'monospace',
                fontSize: 11,
              ),
              cursorType:
                  TerminalCursorType.block,
              alwaysShowCursor: false,
            ),
          ),
        ),
      ],
    );
  }

  TerminalTheme _terminalTheme() {
    return const TerminalTheme(
      background: Color(0xFF181818),
      foreground: Color(0xFFE5E5E5),

      cursor: Colors.white70,
      selection: Colors.white24,

      searchHitBackground:
          Color(0xFF555522),
      searchHitBackgroundCurrent:
          Color(0xFF777733),
      searchHitForeground:
          Colors.white,

      black: Color(0xFF181818),
      red: Color(0xFFF14C4C),
      green: Color(0xFF23D18B),
      yellow: Color(0xFFE5E510),
      blue: Color(0xFF3B8EEA),
      magenta: Color(0xFFD670D6),
      cyan: Color(0xFF29B8DB),
      white: Color(0xFFE5E5E5),

      brightBlack: Color(0xFF666666),
      brightRed: Color(0xFFF14C4C),
      brightGreen: Color(0xFF23D18B),
      brightYellow: Color(0xFFE5E510),
      brightBlue: Color(0xFF3B8EEA),
      brightMagenta: Color(0xFFD670D6),
      brightCyan: Color(0xFF29B8DB),
      brightWhite: Color(0xFFFFFFFF),
    );
  }

  Widget _buildToolbar() {
    return Container(
      height: 38,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      decoration:
          const BoxDecoration(
        color: Color(0xFF202020),
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF3A3A3A),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.play_circle_outline_rounded,
            size: 15,
            color: Colors.white54,
          ),
          const SizedBox(width: 7),
          const Text(
            'Flutter Run',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          if (_isRunning)
            Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Ir para o final',
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(
              minWidth: 30,
              minHeight: 30,
            ),
            onPressed: _goToBottom,
            icon: const Icon(
              Icons.vertical_align_bottom,
              size: 16,
              color: Colors.white54,
            ),
          ),
          IconButton(
            tooltip: 'Limpar saída',
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(
              minWidth: 30,
              minHeight: 30,
            ),
            onPressed: _clear,
            icon: const Icon(
              Icons.delete_outline,
              size: 16,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}