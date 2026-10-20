import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PreviewScreen extends StatefulWidget {
  final String url;
  final VoidCallback onClose;
  final bool isFlutterRunning;
  final bool canHotReload;
  final bool canHotRestart;
  final VoidCallback? onHotReload;
  final VoidCallback? onHotRestart;
  final VoidCallback? onStop;

  const PreviewScreen({
    super.key,
    required this.url,
    required this.onClose,
    required this.isFlutterRunning,
    required this.canHotReload,
    required this.canHotRestart,
    this.onHotReload,
    this.onHotRestart,
    this.onStop,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  late final WebViewController _controller;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (_) {
            if (!mounted) {
              return;
            }

            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..loadRequest(
        Uri.parse(widget.url),
      );
  }

  Future<void> _reloadPreview() async {
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Material(
              elevation: 1,
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Voltar para o código',
                      onPressed: widget.onClose,
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                      ),
                    ),

                    const Text(
                      'Preview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(width: 8),

                    IconButton(
                      tooltip: widget.isFlutterRunning
                          ? 'Executando'
                          : 'Executar',
                      icon: Icon(
                        widget.isFlutterRunning
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      onPressed: null,
                    ),

                    IconButton(
                      tooltip: 'Hot Reload',
                      icon: const Icon(
                        Icons.bolt_rounded,
                        color: Colors.amber,
                      ),
                      onPressed: widget.canHotReload
                          ? widget.onHotReload
                          : null,
                    ),

                    IconButton(
                      tooltip: 'Hot Restart',
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.green,
                      ),
                      onPressed: widget.canHotRestart
                          ? widget.onHotRestart
                          : null,
                    ),

                    IconButton(
                      tooltip: 'Parar',
                      icon: const Icon(
                        Icons.stop_rounded,
                        color: Colors.red,
                      ),
                      onPressed: widget.isFlutterRunning
                          ? widget.onStop
                          : null,
                    ),

                    const Spacer(),

                    IconButton(
                      tooltip: 'Recarregar Preview',
                      onPressed: _reloadPreview,
                      icon: const Icon(
                        Icons.refresh_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: Stack(
              children: [
                WebViewWidget(
                  controller: _controller,
                ),

                if (_isLoading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}