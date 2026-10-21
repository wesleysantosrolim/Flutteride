import 'package:material_ui/material_ui.dart';

import '../../../editor/presentation/screens/native_lsp_test_screen.dart';
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

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text(
        'Meus Projetos Flutter',
      ),
      actions: [
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
