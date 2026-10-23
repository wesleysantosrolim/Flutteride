import 'package:material_ui/material_ui.dart';

import '../../../editor/presentation/screens/native_lsp_test_screen.dart';
import '../../../editor/presentation/screens/native_novo.dart';
import '../../../editor/presentation/screens/monaco_simulated_completion_screen.dart';
// Importe o arquivo onde você salvou o componente CasaEditorView, por exemplo:
// import 'path/to/casa_editor_view.dart';
import 'home_app_bar_actions.dart';

class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const HomeAppBar({
    super.key,
    this.onRefresh,
  });

  final VoidCallback? onRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _openNativeLspTest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NativeLspTestScreen(),
      ),
    );
  }

  void _openSimulatedCompletionTest(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MonacoSimulatedCompletionScreen(),
      ),
    );
  }

  void _openCasaEditor(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>  Scaffold(
          body: CasaEditorView(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text('Meus Projetos Flutter'),
      actions: [
        IconButton(
          tooltip: 'Editor projeto Casa (LSP)',
          icon: const Icon(Icons.code),
          onPressed: () => _openCasaEditor(context),
        ),
        IconButton(
          tooltip: 'Teste completion simulado',
          icon: const Icon(Icons.lightbulb_outline),
          onPressed: () => _openSimulatedCompletionTest(context),
        ),
        IconButton(
          tooltip: 'Teste LSP nativo',
          icon: const Icon(Icons.science_outlined),
          onPressed: () => _openNativeLspTest(context),
        ),
        HomeAppBarActions(
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}
