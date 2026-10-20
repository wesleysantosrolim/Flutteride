import 'package:material_ui/material_ui.dart';

import '../../services/home_navigation_service.dart';

class HomeAppBarActions extends StatelessWidget {
  final VoidCallback? onRefresh;

  const HomeAppBarActions({
    super.key,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Abrir Terminal Ubuntu',
          icon: const Icon(
            Icons.terminal_outlined,
          ),
          onPressed: () {
            HomeNavigationService.openTerminal(
              context,
            );
          },
        ),
        IconButton(
          tooltip: 'Atualizar projetos',
          icon: const Icon(
            Icons.refresh_rounded,
          ),
          onPressed: onRefresh,
        ),
      ],
    );
  }
}