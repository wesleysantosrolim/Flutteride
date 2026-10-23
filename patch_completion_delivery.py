# -*- coding: utf-8 -*-
from pathlib import Path
from datetime import datetime
import shutil
import sys

ROOT = Path.cwd()

FILES = {
    "js": ROOT / "packages/flutter_monaco/assets/monaco/bridge/lsp.js",
    "dart": ROOT / "packages/flutter_monaco/lib/src/lsp/lsp_connection.dart",
    "screen": ROOT / "lib/features/editor/presentation/screens/native_lsp_test_screen.dart",
}

for path in FILES.values():
    if not path.is_file():
        print("ERRO: arquivo nao encontrado:", path)
        print("Execute na raiz do repositorio FlutterIDE.")
        sys.exit(1)

original = {
    key: path.read_text(encoding="utf-8")
    for key, path in FILES.items()
}
updated = dict(original)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            "{}: esperado 1 trecho, encontrados {}.".format(label, count)
        )
    return text.replace(old, new, 1)


try:
    # 1. JavaScript: observar o resultado devolvido pelo provider.
    js = updated["js"]

    js = replace_once(
        js,
        "                  let FlutterLspClientClass = null;\n"
        "                  function getClientClass() {",
        r"""                  // Captura de diagnostico do resultado de completion.
                  let activeCompletionConnectionId = null;
                  let completionProviderCaptureInstalled = false;

                  function installCompletionProviderCapture() {
                    if (completionProviderCaptureInstalled) return;
                    if (!window.monaco ||
                        !monaco.languages ||
                        typeof monaco.languages.registerCompletionItemProvider !== 'function') {
                      return;
                    }

                    const originalRegister =
                      monaco.languages.registerCompletionItemProvider;

                    monaco.languages.registerCompletionItemProvider = function (
                      language,
                      provider
                    ) {
                      const connectionId = activeCompletionConnectionId;

                      if (!connectionId ||
                          !provider ||
                          typeof provider.provideCompletionItems !== 'function') {
                        return originalRegister.apply(this, arguments);
                      }

                      const originalProvide = provider.provideCompletionItems;
                      const wrappedProvider = Object.assign({}, provider);

                      wrappedProvider.provideCompletionItems = function (
                        model,
                        position,
                        context,
                        token
                      ) {
                        function report(value) {
                          try {
                            const safeResult = JSON.parse(JSON.stringify(value));
                            const suggestions = Array.isArray(safeResult)
                              ? safeResult
                              : safeResult &&
                                Array.isArray(safeResult.suggestions)
                                ? safeResult.suggestions
                                : null;

                            postMessageToFlutter({
                              event: 'lspCompletionDelivery',
                              connectionId: connectionId,
                              uri: model && model.uri
                                ? model.uri.toString()
                                : null,
                              position: position || null,
                              result: safeResult,
                              suggestionCount: suggestions
                                ? suggestions.length
                                : null,
                            });
                          } catch (_) {
                            // O diagnostico nao pode interromper o Monaco.
                          }
                          return value;
                        }

                        let result;
                        try {
                          result = originalProvide.call(
                            provider,
                            model,
                            position,
                            context,
                            token
                          );
                        } catch (error) {
                          postMessageToFlutter({
                            event: 'lspCompletionDelivery',
                            connectionId: connectionId,
                            uri: model && model.uri
                              ? model.uri.toString()
                              : null,
                            position: position || null,
                            error: String(error),
                          });
                          throw error;
                        }

                        if (result && typeof result.then === 'function') {
                          return result.then(report, (error) => {
                            postMessageToFlutter({
                              event: 'lspCompletionDelivery',
                              connectionId: connectionId,
                              uri: model && model.uri
                                ? model.uri.toString()
                                : null,
                              position: position || null,
                              error: String(error),
                            });
                            throw error;
                          });
                        }

                        return report(result);
                      };

                      return originalRegister.call(
                        this,
                        language,
                        wrappedProvider
                      );
                    };

                    completionProviderCaptureInstalled = true;
                  }

                  let FlutterLspClientClass = null;
                  function getClientClass() {""",
        "lsp.js: insercao do observador",
    )

    js = replace_once(
        js,
        "                        const ClientClass = getClientClass();\n"
        "                        entry.client = new ClientClass(entry.transport);",
        """                        installCompletionProviderCapture();
                        const previousConnectionId = activeCompletionConnectionId;
                        activeCompletionConnectionId = id;
                        try {
                          const ClientClass = getClientClass();
                          entry.client = new ClientClass(entry.transport);
                        } finally {
                          activeCompletionConnectionId = previousConnectionId;
                        }""",
        "lsp.js: criacao do cliente",
    )

    updated["js"] = js

    # 2. Dart: stream para receber os eventos de completion.
    dart = updated["dart"]

    dart = replace_once(
        dart,
        "  final StreamController<LspConnectionState> _stateController =\n"
        "      StreamController<LspConnectionState>.broadcast();\n"
        "  final Completer<void> _closedCompleter = Completer<void>();",
        "  final StreamController<LspConnectionState> _stateController =\n"
        "      StreamController<LspConnectionState>.broadcast();\n"
        "  final StreamController<Map<String, Object?>> "
        "_completionDeliveryController =\n"
        "      StreamController<Map<String, Object?>>.broadcast();\n"
        "  final Completer<void> _closedCompleter = Completer<void>();",
        "lsp_connection.dart: controlador",
    )

    dart = replace_once(
        dart,
        "  Stream<LspConnectionState> get stateChanges => _stateController.stream;\n",
        "  Stream<LspConnectionState> get stateChanges => _stateController.stream;\n\n"
        "  /// Resultados devolvidos pelo provider de completion do Monaco.\n"
        "  Stream<Map<String, Object?>> get completionDeliveries =>\n"
        "      _completionDeliveryController.stream;\n",
        "lsp_connection.dart: getter",
    )

    dart = replace_once(
        dart,
        "      case 'lspMessage':\n"
        "        _handleLspMessage(Map<String, dynamic>.from(event.data));\n"
        "    }\n"
        "  }\n\n"
        "  void _handleLspStatus",
        "      case 'lspMessage':\n"
        "        _handleLspMessage(Map<String, dynamic>.from(event.data));\n"
        "      case 'lspCompletionDelivery':\n"
        "        _handleCompletionDelivery(Map<String, dynamic>.from(event.data));\n"
        "    }\n"
        "  }\n\n"
        "  void _handleCompletionDelivery(Map<String, dynamic> data) {\n"
        "    final connectionId = data['connectionId']?.toString();\n"
        "    if (connectionId == null) return;\n\n"
        "    final connection = _connections[connectionId];\n"
        "    if (connection == null || connection._finalized) return;\n\n"
        "    if (!connection._completionDeliveryController.isClosed) {\n"
        "      connection._completionDeliveryController.add(\n"
        "        Map<String, Object?>.from(data),\n"
        "      );\n"
        "    }\n"
        "  }\n\n"
        "  void _handleLspStatus",
        "lsp_connection.dart: encaminhamento do evento",
    )

    dart = replace_once(
        dart,
        "    connection._stateController.close();\n",
        "    connection._stateController.close();\n"
        "    connection._completionDeliveryController.close();\n",
        "lsp_connection.dart: fechamento do stream",
    )

    updated["dart"] = dart

    # 3. Tela de teste: registrar o resultado real recebido do Monaco.
    screen = updated["screen"]

    screen = replace_once(
        screen,
        "  StreamSubscription<MonacoContentChanged>? _contentSubscription;\n"
        "  Timer? _syncTimer;",
        "  StreamSubscription<MonacoContentChanged>? _contentSubscription;\n"
        "  StreamSubscription<Map<String, Object?>>? "
        "_completionDeliverySubscription;\n"
        "  Timer? _syncTimer;",
        "tela: subscription",
    )

    screen = replace_once(
        screen,
        "    unawaited(_contentSubscription?.cancel() ?? Future<void>.value());\n",
        "    unawaited(_contentSubscription?.cancel() ?? Future<void>.value());\n"
        "    unawaited(\n"
        "      _completionDeliverySubscription?.cancel() ?? Future<void>.value(),\n"
        "    );\n",
        "tela: cancelamento da subscription",
    )

    screen = replace_once(
        screen,
        "      _connection = connection;\n\n"
        "      await _sendDidOpen();",
        r"""      _connection = connection;
      _completionDeliverySubscription =
          connection.completionDeliveries.listen(
        (delivery) {
          unawaited(
            NativeLspLogger.info(
              'monaco.completion.delivery',
              details: jsonEncode(delivery),
            ),
          );

          if (_disposed || !mounted) return;

          final result = delivery['result'];
          final count = delivery['suggestionCount'];

          setState(() {
            _lastCompletion =
                'Resultado efetivamente entregue ao Monaco:\n'
                'URI: ${delivery['uri'] ?? '(desconhecida)'}\n'
                'Posicao: ${delivery['position'] ?? '(desconhecida)'}\n'
                'Quantidade: ${count ?? '(nao informada)'}\n'
                'Resultado JSON:\n${_shortJson(result, maxLength: 12000)}';

            _status = delivery['error'] != null
                ? 'O provider de completion apresentou erro.'
                : 'Resultado do provider registrado no log.';
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

      await _sendDidOpen();""",
        "tela: assinatura do evento",
    )

    updated["screen"] = screen

except RuntimeError as error:
    print("PATCH CANCELADO:", error)
    print("Nenhum arquivo foi gravado.")
    print("Confira se os arquivos correspondem a versao esperada.")
    sys.exit(2)

changed = [key for key in updated if updated[key] != original[key]]

if len(changed) != 3:
    print("PATCH CANCELADO: alteracoes preparadas:", changed)
    print("Esperava modificar exatamente os tres arquivos.")
    sys.exit(3)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backups = []

try:
    # Criar todos os backups antes de modificar qualquer arquivo.
    for key in changed:
        path = FILES[key]
        backup = path.with_name(
            path.name + ".backup_completion_" + stamp
        )
        shutil.copy2(str(path), str(backup))
        backups.append(backup)

    for key in changed:
        FILES[key].write_text(
            updated[key],
            encoding="utf-8",
        )

except Exception as error:
    print("ERRO ao gravar:", error)
    print("Backups criados:")
    for backup in backups:
        print(" -", backup)
    sys.exit(4)

print("\nPatch aplicado.")
print("\nBackups:")
for backup in backups:
    print(" -", backup)

print("\nArquivos modificados:")
for key in changed:
    print(" -", FILES[key])

print("\nProximos comandos:")
print(
    "flutter analyze "
    "packages/flutter_monaco/lib/src/lsp/lsp_connection.dart "
    "lib/features/editor/presentation/screens/native_lsp_test_screen.dart"
)
print(
    "flutter build apk --debug --target-platform android-arm64 "
    "--android-skip-build-dependency-validation"
)
