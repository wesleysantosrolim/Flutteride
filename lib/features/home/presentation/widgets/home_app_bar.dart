import 'package:material_ui/material_ui.dart';

import 'home_app_bar_actions.dart';

class HomeAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  final VoidCallback? onRefresh;

  const HomeAppBar({
    super.key,
    this.onRefresh,
  });

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: const Text(
        'Meus Projetos Flutter',
      ),
      actions: [
        HomeAppBarActions(
          onRefresh: onRefresh,
        ),
      ],
    );
  }
}