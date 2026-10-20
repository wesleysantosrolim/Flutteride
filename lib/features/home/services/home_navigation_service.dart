import 'package:material_ui/material_ui.dart';

import '../../terminal/presentation/screens/terminal_screen.dart';

class HomeNavigationService {
  const HomeNavigationService._();

  static void openTerminal(
    BuildContext context,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            const TerminalScreen(),
      ),
    );
  }

  static void openNewProject(
    BuildContext context,
  ) {
    // Implementaremos posteriormente.
  }

  static void openProject(
    BuildContext context,
  ) {
    // Implementaremos posteriormente.
  }

  static void openSettings(
    BuildContext context,
  ) {
    // Implementaremos posteriormente.
  }
}