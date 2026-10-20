import 'dart:async';

import 'package:flutter_monaco/flutter_monaco.dart';

import 'editor_analysis_coordinator.dart';

/// Consulta e executa Code Actions fornecidos pelo Dart Analysis Server.
///
/// Este serviço não altera os markers de diagnóstico nem a configuração
/// do autocomplete. A integração visual com o editor é independente.
class EditorCodeActionService {
  EditorCodeActionService({required this.analysisCoordinator});

  final EditorAnalysisCoordinator analysisCoordinator;

  MonacoController? _controller;
  String? _activeFilePath;

  bool _disposed = false;
  int _requestGeneration = 0;

  void attachController(MonacoController controller) {
    if (_disposed) return;
    _controller = controller;
  }

  void setActiveFile(String? path) {
    _activeFilePath = path;
    _requestGeneration++;
  }

  /// Solicita as ações disponíveis na posição atual do cursor.
  ///
  /// line e character seguem o padrão LSP: índices iniciados em zero.
  Future<List<DartCodeAction>> requestActions({
    required String path,
    required int line,
    required int character,
    required String documentText,
  }) async {
    _ensureNotDisposed();

    if (!analysisCoordinator.isInitialized) {
      throw StateError('O Dart Analysis Server ainda não está inicializado.');
    }

    final generation = ++_requestGeneration;
    final client = analysisCoordinator.client;

    final normalizedPath = path.trim();
    if (normalizedPath.isEmpty) {
      throw ArgumentError.value(path, 'path', 'Caminho vazio.');
    }

    final serverPath = client.convertPathToServerPath(normalizedPath);
    final uri = Uri.file(serverPath).toString();

    final safeLine = line < 0 ? 0 : line;
    final safeCharacter = character < 0 ? 0 : character;

    final response = await client.sendRequest(
      'textDocument/codeAction',
      <String, dynamic>{
        'textDocument': <String, dynamic>{'uri': uri},
        'range': <String, dynamic>{
          'start': <String, dynamic>{
            'line': safeLine,
            'character': safeCharacter,
          },
          'end': <String, dynamic>{
            'line': safeLine,
            'character': safeCharacter,
          },
        },
        'context': <String, dynamic>{
          'diagnostics': <dynamic>[],
          'only': <String>['quickfix', 'refactor', 'source'],
        },
      },
    );

    if (_disposed || generation != _requestGeneration) {
      return const <DartCodeAction>[];
    }

    final dynamic rawResult = response.containsKey('result')
        ? response['result']
        : response;

    if (rawResult == null || rawResult is! List) {
      return const <DartCodeAction>[];
    }

    return rawResult
        .whereType<Map>()
        .map((item) => DartCodeAction.fromJson(Map<String, dynamic>.from(item)))
        .where((action) => action.title.trim().isNotEmpty)
        .toList(growable: false);
  }

  /// Aplica as edições da ação ao documento ativo.
  ///
  /// Por segurança, só altera o arquivo atualmente aberto. Se a ação
  /// modificar outros arquivos, informa que a operação precisa ser
  /// coordenada pela camada de gerenciamento de arquivos.
  Future<void> applyAction({
    required DartCodeAction action,
    required String activeFilePath,
  }) async {
    _ensureNotDisposed();

    final controller = _controller;
    if (controller == null) {
      throw StateError('O controlador Monaco não está conectado.');
    }

    final currentPath = _activeFilePath;
    if (currentPath != null && currentPath != activeFilePath) {
      throw StateError(
        'O arquivo da ação não corresponde ao arquivo ativo no editor.',
      );
    }

    await controller.whenReady;

    final workspaceEdit = action.edit;
    if (workspaceEdit != null) {
      final changes = workspaceEdit['changes'];
      if (changes is Map) {
        final serverPath = analysisCoordinator.client.convertPathToServerPath(
          activeFilePath,
        );
        final activeUri = Uri.file(serverPath).toString();

        final editsForActiveFile = changes[activeUri];

        final otherFiles = changes.keys
            .where((key) => key.toString() != activeUri)
            .toList(growable: false);

        if (otherFiles.isNotEmpty) {
          throw UnsupportedError(
            'Esta ação modifica outros arquivos. '
            'É necessário aplicar a edição pelo gerenciador de projetos.',
          );
        }

        if (editsForActiveFile is List) {
          final edits = editsForActiveFile
              .whereType<Map>()
              .map((item) => _toMonacoEdit(Map<String, dynamic>.from(item)))
              .whereType<EditOperation>()
              .toList();

          if (edits.isNotEmpty) {
            await controller.document.applyEdits(edits);
          }
        }
      }

      final documentChanges = workspaceEdit['documentChanges'];
      if (documentChanges is List && documentChanges.isNotEmpty) {
        throw UnsupportedError(
          'Esta ação utiliza documentChanges. '
          'Esse formato ainda precisa ser coordenado pelo gerenciador '
          'de arquivos para preservar as versões dos documentos.',
        );
      }
    }

    if (action.command != null && action.command!.isNotEmpty) {
      await analysisCoordinator.client.sendRequest(
        'workspace/executeCommand',
        <String, dynamic>{
          'command': action.command,
          'arguments': action.arguments ?? <dynamic>[],
        },
      );
    }
  }

  EditOperation? _toMonacoEdit(Map<String, dynamic> item) {
    final rangeJson = item['range'];
    final text = item['newText'];

    if (rangeJson is! Map || text is! String) {
      return null;
    }

    final range = Map<String, dynamic>.from(rangeJson);
    final start = range['start'];
    final end = range['end'];

    if (start is! Map || end is! Map) {
      return null;
    }

    final startMap = Map<String, dynamic>.from(start);
    final endMap = Map<String, dynamic>.from(end);

    final startLine = startMap['line'];
    final startCharacter = startMap['character'];
    final endLine = endMap['line'];
    final endCharacter = endMap['character'];

    if (startLine is! int ||
        startCharacter is! int ||
        endLine is! int ||
        endCharacter is! int) {
      return null;
    }

    return EditOperation(
      range: Range(
        startLine: startLine + 1,
        startColumn: startCharacter + 1,
        endLine: endLine + 1,
        endColumn: endCharacter + 1,
      ),
      text: text,
    );
  }

  void dispose() {
    _disposed = true;
    _requestGeneration++;
    _controller = null;
    _activeFilePath = null;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('EditorCodeActionService já foi descartado.');
    }
  }
}

class DartCodeAction {
  const DartCodeAction({
    required this.title,
    this.kind,
    this.edit,
    this.command,
    this.arguments,
    this.raw,
  });

  final String title;
  final String? kind;
  final Map<String, dynamic>? edit;
  final String? command;
  final List<dynamic>? arguments;
  final Map<String, dynamic>? raw;

  factory DartCodeAction.fromJson(Map<String, dynamic> json) {
    final commandValue = json['command'];
    String? commandName;
    List<dynamic>? commandArguments;

    if (commandValue is Map) {
      final commandMap = Map<String, dynamic>.from(commandValue);
      final value = commandMap['command'];
      if (value is String) commandName = value;

      final args = commandMap['arguments'];
      if (args is List) commandArguments = List<dynamic>.from(args);
    } else if (commandValue is String) {
      commandName = commandValue;

      final args = json['arguments'];
      if (args is List) commandArguments = List<dynamic>.from(args);
    }

    final editValue = json['edit'];

    return DartCodeAction(
      title: json['title'] is String ? json['title'] as String : '',
      kind: json['kind'] is String ? json['kind'] as String : null,
      edit: editValue is Map ? Map<String, dynamic>.from(editValue) : null,
      command: commandName,
      arguments: commandArguments,
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}
