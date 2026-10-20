import 'package:material_ui/material_ui.dart';

class HomeWelcomeSection extends StatelessWidget {
  const HomeWelcomeSection({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
        Theme.of(context);

    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: theme
                    .colorScheme
                    .primaryContainer,
                borderRadius:
                    BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.code,
                size: 34,
                color: theme
                    .colorScheme
                    .onPrimaryContainer,
              ),
            ),
            const SizedBox(
              width: 20,
            ),
            const Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bem-vindo ao FlutterIDE',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Crie, abra e desenvolva seus projetos Flutter em um único lugar.',
                    style: TextStyle(
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}