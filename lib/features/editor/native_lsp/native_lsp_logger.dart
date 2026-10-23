
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Logger exclusivo para os testes de comunicacao LSP nativa do Monaco.
class NativeLspLogger {
  NativeLspLogger._();

  static const String _logDirectory =
      '/storage/emulated/0/Download/FlutterIDE/logs';

  static const String _logFileName = 'flutteride_native_lsp.log';

  static const int _maxLogBytes = 8 * 1024 * 1024;
  static const int _maxMessageLength = 4000;
  static const int _jsonChunkSize = 2500;

  static Future<void> _queue = Future<void>.value();

  static bool _enabled = true;

  static String? _lastWriteError;
  static bool _lastWriteSucceeded = false;

  static String get logPath => '$_logDirectory/$_logFileName';

  static String? get lastWriteError => _lastWriteError;

  static bool get lastWriteSucceeded => _lastWriteSucceeded;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  static Future<void> info(
    String event, {
    Object? details,
  }) {
    return log('INFO', event, details: details);
  }

  static Future<void> warning(
    String event, {
    Object? details,
  }) {
    return log('WARN', event, details: details);
  }

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
      if (buffer.isNotEmpty) buffer.write(' | ');
      buffer.write('exception=$exception');
    }

    if (stackTrace != null) {
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(stackTrace);
    }

    return log(
      'ERROR',
      event,
      details: buffer.isEmpty ? null : buffer.toString(),
    );
  }

  /// Grava um objeto JSON completo em partes numeradas.
  ///
  /// Para reconstruir o JSON, concatenar os campos data= dos eventos
  /// [event].chunk em ordem crescente de part.
  static Future<void> jsonDump(
    String event,
    Object? value,
  ) async {
    if (!_enabled) return;

    final encoded = jsonEncode(value);

    final totalParts = encoded.isEmpty
        ? 1
        : (encoded.length + _jsonChunkSize - 1) ~/ _jsonChunkSize;

    await info(
      '$event.begin',
      details: 'characters=${encoded.length}; parts=$totalParts',
    );

    for (var index = 0; index < totalParts; index++) {
      final start = index * _jsonChunkSize;
      final end = (start + _jsonChunkSize < encoded.length)
          ? start + _jsonChunkSize
          : encoded.length;

      final chunk = encoded.substring(start, end);

      await info(
        '$event.chunk',
        details: 'part=${index + 1}/$totalParts; data=$chunk',
      );
    }

    await info(
      '$event.end',
      details: 'characters=${encoded.length}; parts=$totalParts',
    );
  }

  static Future<void> log(
    String level,
    String event, {
    Object? details,
  }) {
    if (!_enabled) return Future<void>.value();

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
        _lastWriteError = '${error.runtimeType}: $error\n$stackTrace';

        debugPrint(
          '[NativeLspLogger] Falha ao gravar em $logPath: '
          '$_lastWriteError',
        );
      }
    });

    return _queue;
  }

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

      if (length + utf8.encode(line).length > _maxLogBytes) {
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
    if (value.length <= _maxMessageLength) return value;

    return '${value.substring(0, _maxMessageLength)}... [truncated]';
  }
}
