import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Logger exclusivo para os testes de comunicacao LSP nativa do Monaco.
///
/// O arquivo fica no armazenamento compartilhado do Android para facilitar
/// a leitura dos diagnosticos sem depender de adb ou logcat.
class NativeLspLogger {
  NativeLspLogger._();

  static const String _logDirectory =
      '/storage/emulated/0/Download/FlutterIDE/logs';

  static const String _logFileName = 'flutteride_native_lsp.log';

  static const int _maxLogBytes = 512 * 1024;
  static const int _maxMessageLength = 4000;

  static Future<void> _queue = Future<void>.value();

  static bool _enabled = true;

  static String? _lastWriteError;
  static bool _lastWriteSucceeded = false;

  static String get logPath => '$_logDirectory/$_logFileName';

  /// Ultimo erro ocorrido durante uma tentativa de gravacao.
  static String? get lastWriteError => _lastWriteError;

  /// Indica se a ultima tentativa de gravacao terminou com sucesso.
  static bool get lastWriteSucceeded => _lastWriteSucceeded;

  /// Ativa ou desativa novos registros.
  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  /// Registra um evento informativo.
  static Future<void> info(
    String event, {
    Object? details,
  }) {
    return log('INFO', event, details: details);
  }

  /// Registra um aviso.
  static Future<void> warning(
    String event, {
    Object? details,
  }) {
    return log('WARN', event, details: details);
  }

  /// Registra uma falha.
  static Future<void> error(
    String event, {
    Object? details,
    Object? exception,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();

    if (details != null) {
      buffer.write(details);
    }

    if (exception != null) {
      if (buffer.isNotEmpty) {
        buffer.write(' | ');
      }
      buffer.write('exception=$exception');
    }

    if (stackTrace != null) {
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(stackTrace);
    }

    return log(
      'ERROR',
      event,
      details: buffer.isEmpty ? null : buffer.toString(),
    );
  }

  /// Adiciona um registro ao arquivo.
  ///
  /// As escritas sao serializadas. Uma falha de gravacao nao interrompe
  /// o funcionamento do editor, mas fica disponivel para diagnostico.
  static Future<void> log(
    String level,
    String event, {
    Object? details,
  }) {
    if (!_enabled) {
      return Future<void>.value();
    }

    final timestamp = DateTime.now().toIso8601String();
    final safeEvent = _singleLine(event);
    final safeDetails =
        details == null ? '' : _limit(_singleLine(details.toString()));

    final line = safeDetails.isEmpty
        ? '[$timestamp] [$level] $safeEvent\n'
        : '[$timestamp] [$level] $safeEvent | $safeDetails\n';

    _queue = _queue.then((_) async {
      try {
        await _writeLine(line);
        _lastWriteSucceeded = true;
        _lastWriteError = null;
      } catch (error, stackTrace) {
        _lastWriteSucceeded = false;
        _lastWriteError =
            '${error.runtimeType}: $error\n$stackTrace';

        // Fallback de diagnostico. A tela de teste podera consultar
        // lastWriteError e apresentar a falha diretamente ao usuario.
        debugPrint(
          '[NativeLspLogger] Falha ao gravar em $logPath: '
          '$_lastWriteError',
        );
      }
    });

    return _queue;
  }

  /// Tenta gravar um evento de diagnostico imediatamente.
  ///
  /// Depois do await, consulte lastWriteSucceeded e lastWriteError.
  static Future<bool> testWrite() async {
    await info(
      'logger.write_test',
      details: 'Teste explicito de escrita do logger.',
    );

    return _lastWriteSucceeded;
  }

  static Future<void> _writeLine(String line) async {
    final directory = Directory(_logDirectory);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final file = File(logPath);

    if (await file.exists()) {
      final length = await file.length();

      if (length >= _maxLogBytes) {
        await file.writeAsString(
          '[${DateTime.now().toIso8601String()}] [INFO] '
          'Log reiniciado: limite de tamanho atingido.\n',
          encoding: utf8,
          flush: true,
        );
      }
    }

    await file.writeAsString(
      line,
      mode: FileMode.append,
      encoding: utf8,
      flush: true,
    );
  }

  static String _singleLine(String value) {
    return value
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n')
        .replaceAll('\t', r'\t');
  }

  static String _limit(String value) {
    if (value.length <= _maxMessageLength) {
      return value;
    }

    return '${value.substring(0, _maxMessageLength)}... [truncated]';
  }
}