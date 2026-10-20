import 'package:material_ui/material_ui.dart';

import '../../services/home_navigation_service.dart';

class HomeQuickActions extends StatelessWidget {
  final bool isWide;

  const HomeQuickActions({
    super.key,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    final actions = [
      _HomeAction(
        icon: Icons.add_box_outlined,
        title: 'Novo projeto',
        description:
            'Crie um novo projeto Flutter.',
        onPressed: () {
          HomeNavigationService.openNewProject(
            context,
          );
        },
      ),
      _HomeAction(
        icon: Icons.folder_open_outlined,
        title: 'Abrir projeto',
        description:
            'Abra um projeto existente.',
        onPressed: () {
          HomeNavigationService.openProject(
            context,
          );
        },
      ),
    ];

    if (isWide) {
      return Row(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          for (var i = 0;
              i < actions.length;
              i++) ...[
            if (i > 0)
              const SizedBox(
                width: 12,
              ),
            Expanded(
              child: _HomeActionCard(
                action: actions[i],
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      children: [
        for (var i = 0;
            i < actions.length;
            i++) ...[
          if (i > 0)
            const SizedBox(
              height: 12,
            ),
          _HomeActionCard(
            action: actions[i],
          ),
        ],
      ],
    );
  }
}

class _HomeAction {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;

  const _HomeAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });
}

class _HomeActionCard extends StatelessWidget {
  final _HomeAction action;

  const _HomeActionCard({
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior:
          Clip.antiAlias,
      child: InkWell(
        onTap: action.onPressed,
        child: Padding(
          padding:
              const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Icon(
                action.icon,
                size: 32,
              ),
              const SizedBox(
                height: 16,
              ),
              Text(
                action.title,
                style:
                    const TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 6,
              ),
              Text(
                action.description,
              ),
            ],
          ),
        ),
      ),
    );
  }
}