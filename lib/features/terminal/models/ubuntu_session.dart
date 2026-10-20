
import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';

class UbuntuSession {
  UbuntuSession({
    required this.pty,
    required this.rootfsPath,
  });

  final Pty pty;
  final String rootfsPath;

  bool _closed = false;

  bool get isClosed => _closed;

  void write(List<int> data) {
    if (_closed) {
      return;
    }

    try {
      pty.write(
        Uint8List.fromList(data),
      );
    } catch (e) {
      debugPrint(
        '[UbuntuSession] Erro ao escrever no PTY: $e',
      );
    }
  }

  void resize(
    int height,
    int width,
  ) {
    if (_closed) {
      return;
    }

    try {
      pty.resize(
        height,
        width,
      );
    } catch (e) {
      debugPrint(
        '[UbuntuSession] Erro ao redimensionar PTY: $e',
      );
    }
  }

  void markClosed() {
    _closed = true;
  }

  void kill() {
    if (_closed) {
      return;
    }

    _closed = true;

    try {
      pty.kill();
    } catch (e) {
      debugPrint(
        '[UbuntuSession] Erro ao encerrar PTY: $e',
      );
    }
  }
}