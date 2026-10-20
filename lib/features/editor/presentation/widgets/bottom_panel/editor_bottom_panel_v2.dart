import 'package:material_ui/material_ui.dart';


class IdeEditorScreen extends StatefulWidget {
  const IdeEditorScreen({super.key});

  @override
  State<IdeEditorScreen> createState() => _IdeEditorScreenState();
}

class _IdeEditorScreenState extends State<IdeEditorScreen> {
  final List<String> _tabs = [
    'Saída de compilação',
    'Logs do aplicativo',
    'Logs da IDE',
    'Diagnósticos',
    'Resultados',
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: const Color(0xFF1E1E1E),
        appBar: AppBar(
          title: const Text('activity_main.xml'),
          backgroundColor: const Color(0xFF252526),
          elevation: 0,
        ),
        body: Stack(
          children: [
            // 1. ÁREA PRINCIPAL DO EDITOR DE CÓDIGO
            Positioned.fill(
              child: Container(
                color: const Color(0xFF1E1E1E),
                padding: const EdgeInsets.all(16.0),
                child: const SingleChildScrollView(
                  child: Text(
                    '<?xml version="1.0" encoding="utf-8"?>\n'
                    '<androidx.constraintlayout.widget.ConstraintLayout\n'
                    '    xmlns:android="http://schemas.android.com/apk/res/android"\n'
                    '    xmlns:app="http://schemas.android.com/apk/res-auto"\n'
                    '    android:layout_width="match_parent"\n'
                    '    android:layout_height="match_parent">\n\n'
                    '    <TextView\n'
                    '        android:id="@+id/text_view"\n'
                    '        android:layout_width="wrap_content"\n'
                    '        android:layout_height="wrap_content"\n'
                    '        android:text="Hello World!" />\n\n'
                    '</androidx.constraintlayout.widget.ConstraintLayout>',
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),

            // 2. PAINEL DESLIZANTE NATIVO COM DRAGGABLESCROLLABLESHEET
            DraggableScrollableSheet(
              initialChildSize: 0.45,
              minChildSize: 0.12,
              maxChildSize: 0.85,
              snap: true,
              snapSizes: const [0.12, 0.45, 0.85],
              builder: (BuildContext context, ScrollController scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF252526),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 10,
                        spreadRadius: 2,
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      // CABEÇALHO (ALÇA + TABBAR) VINCULADO AO SCROLL
                      SingleChildScrollView(
                        controller: scrollController, // ✅ Permite arrastar o painel puxando a alça
                        physics: const ClampingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),
                            // Indicador de arrasto (Alça)
                            Center(
                              child: Container(
                                height: 5,
                                width: 40,
                                decoration: BoxDecoration(
                                  color: Colors.grey[600],
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Barra de Abas
                            TabBar(
                              isScrollable: true,
                              indicatorColor: Colors.blueAccent,
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.grey,
                              tabs: _tabs.map((tab) => Tab(text: tab)).toList(),
                            ),
                            const Divider(height: 1, color: Colors.black26),
                          ],
                        ),
                      ),

                      // ÁREA DE CONTEÚDO COM ROLAGEM INDEPENDENTE
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildLogList(
                              'Executar tarefas: [app:assembleDebug]\n'
                              'Code On The Go clean logs running...\n\n'
                              'FAILURE: Build failed with an exception.\n\n'
                              '* What went wrong:\n'
                              'Build cancelled.\n\n'
                              'BUILD FAILED in 13s\n'
                              '${List.generate(50, (i) => 'Linha de log de erro #$i').join('\n')}',
                              Colors.redAccent,
                            ),
                            _buildLogList(
                              'INFO: [main] IndexingServiceRegistered\n'
                              'WARN: DefaultDispatcher-worker-1\n'
                              'INFO: JavaDebugAdapter connected.\n'
                              '${List.generate(50, (i) => 'Info log trace #$i').join('\n')}',
                              Colors.lightBlueAccent,
                            ),
                            _buildLogList(
                              'IDE Log output initialized...\nSystem ready.',
                              Colors.grey,
                            ),
                            _buildLogList(
                              'Nenhum diagnóstico pendente.',
                              Colors.greenAccent,
                            ),
                            _buildLogList(
                              'Sem dados de pesquisa.',
                              Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogList(String content, Color textColor) {
    final lines = content.split('\n');
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return Text(
          lines[index],
          style: TextStyle(
            color: textColor,
            fontFamily: 'monospace',
            fontSize: 12,
          ),
        );
      },
    );
  }
}
