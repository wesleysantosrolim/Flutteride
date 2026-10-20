import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'core/linux/linux_environment_service.dart';
import 'features/setup/presentation/screens/setup_screen.dart';
import 'features/home/presentation/screens/home_screen.dart';

class FlutterIdeApp extends StatelessWidget {
  const FlutterIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlutterIDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const AppBootstrapPage(),
    );
  }
}

class AppBootstrapPage extends StatefulWidget {
  const AppBootstrapPage({super.key});

  @override
  State<AppBootstrapPage> createState() =>
      _AppBootstrapPageState();
}

class _AppBootstrapPageState
    extends State<AppBootstrapPage> {
  final LinuxEnvironmentService _linuxService =
      LinuxEnvironmentService();

  StreamSubscription<Map<String, dynamic>>?
      _subscription;

  bool _checking = true;

  double _progress = 0.0;

  String _message =
      'Verificando ambiente Ubuntu...';

  LinuxSetupStatus _status =
      LinuxSetupStatus.notInstalled;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final installed =
          await _linuxService.isInstalled();

      if (!mounted) {
        return;
      }

      if (installed) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                const HomeScreen(),
          ),
        );

        return;
      }

      setState(() {
        _checking = false;

        _status =
            LinuxSetupStatus.notInstalled;

        _message =
            'Preparando ambiente Ubuntu...';
      });

      await _startUbuntuSetup();
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _checking = false;

        _status =
            LinuxSetupStatus.error;

        _progress = 0.0;

        _message =
            'Erro:\n$e';
      });
    }
  }

  Future<void> _startUbuntuSetup() async {
    _subscription?.cancel();

    _subscription =
        _linuxService.setupEnvironment().listen(
      (event) {
        if (!mounted) {
          return;
        }

        final status =
            event['status'];

        setState(() {
          if (status is LinuxSetupStatus) {
            _status = status;
          }

          final progress =
              event['progress'];

          if (progress is num) {
            _progress =
                progress.toDouble();
          }

          final message =
              event['message'];

          if (message is String) {
            _message = message;
          }
        });

        if (status ==
            LinuxSetupStatus.ready) {
          _openSetupScreen();
        }
      },
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        if (!mounted) {
          return;
        }

        setState(() {
          _status =
              LinuxSetupStatus.error;

          _progress = 0.0;

          _message =
              'Erro:\n$error';
        });
      },
    );
  }

  void _openSetupScreen() {
    if (!mounted) {
      return;
    }

    _subscription?.cancel();
    _subscription = null;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            const SetupScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final isError =
        _status == LinuxSetupStatus.error;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FlutterIDE'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 600,
          ),
          child: Padding(
            padding:
                const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.terminal,
                  size: 72,
                ),
                const SizedBox(
                  height: 24,
                ),
                Text(
                  'Ambiente Ubuntu',
                  textAlign:
                      TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall,
                ),
                const SizedBox(
                  height: 24,
                ),
                LinearProgressIndicator(
                  value: isError
                      ? 0
                      : _progress,
                ),
                const SizedBox(
                  height: 20,
                ),
                Text(
                  _message,
                  textAlign:
                      TextAlign.center,
                ),
                if (isError) ...[
                  const SizedBox(
                    height: 24,
                  ),
                  FilledButton.icon(
                    onPressed:
                        _startUbuntuSetup,
                    icon: const Icon(
                      Icons.refresh,
                    ),
                    label: const Text(
                      'Tentar novamente',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}