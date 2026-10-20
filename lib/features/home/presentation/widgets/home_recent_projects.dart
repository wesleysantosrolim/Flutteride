import 'package:material_ui/material_ui.dart';

class HomeRecentProjects extends StatelessWidget {
  const HomeRecentProjects({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history,
                ),
                const SizedBox(
                  width: 12,
                ),
                const Expanded(
                  child: Text(
                    'Projetos recentes',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Implementaremos posteriormente.
                  },
                  child: const Text(
                    'Ver todos',
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 16,
            ),
            const Center(
              child: Padding(
                padding:
                    EdgeInsets.symmetric(
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.folder_copy_outlined,
                      size: 48,
                    ),
                    SizedBox(
                      height: 12,
                    ),
                    Text(
                      'Nenhum projeto recente',
                    ),
                    SizedBox(
                      height: 4,
                    ),
                    Text(
                      'Seus projetos aparecerão aqui.',
                      textAlign:
                          TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}