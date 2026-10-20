import 'package:material_ui/material_ui.dart';

import '../../../services/editor_analysis_coordinator.dart';
import 'bottom_panel_analysis.dart';
import 'bottom_panel_run.dart';
import 'bottom_panel_tab.dart';

class EditorBottomPanel extends StatefulWidget {
  final EditorAnalysisCoordinator analysisCoordinator;

  const EditorBottomPanel({
    super.key,
    required this.analysisCoordinator,
  });

  @override
  State<EditorBottomPanel> createState() => _EditorBottomPanelState();
}

class _EditorBottomPanelState extends State<EditorBottomPanel> {
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();

  int _selectedIndex = 0;
  bool _isExpanded = false;

  final List<_BottomPanelItem> _items = const [
    _BottomPanelItem(
      title: 'Run',
      icon: Icons.play_circle_outline_rounded,
    ),
    _BottomPanelItem(
      title: 'Analysis',
      icon: Icons.analytics_outlined,
    ),
  ];

  @override 
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetSizeChanged);
  }

  void _onSheetSizeChanged() {
    if (_sheetController.isAttached) {
      final currentSize = _sheetController.size;
      final isNowExpanded = currentSize > 0.08;
      if (isNowExpanded != _isExpanded) {
        setState(() {
          _isExpanded = isNowExpanded;
        });
      }
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetSizeChanged);
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.07, // Altura recolhida
      minChildSize: 0.07,     // Mínimo recolhido
      maxChildSize: 0.85,     // Nível 2: Expansão total
      //snap: true,
      //snapSizes: const [0.45, 0.85], // Nível 1 (45%) e Nível 2 (85%)
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.black, // Faixa preta estilo Code on the Go
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Alça Visual Superior
                    _buildDragHandle(),

                    // 2. Faixa Fixa Recolhida
                    _buildFixedHeader(),

                    // 3. Conteúdo Expandido (Sempre construído em memória para reter o estado, 
                    // mas ocultado visualmente através do Offstage quando _isExpanded for falso)
                    const Divider(color: Color(0xFF222222), height: 1),
                    Offstage(
                      offstage: !_isExpanded,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTabBar(),
                          const Divider(color: Color(0xFF222222), height: 1),
                          _buildExpandedContent(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Icon(
          Icons.open_in_full,
          size: 12,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildFixedHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Ponto verde indicativo de conexão
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'Server conectado',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const Spacer(),

          // Indicadores numéricos do Monaco
          _buildStatusCount(Icons.cancel, '0', Colors.redAccent),
          const SizedBox(width: 10),
          _buildStatusCount(Icons.warning, '0', Colors.orangeAccent),
          const SizedBox(width: 10),
          _buildStatusCount(Icons.info, '0', Colors.lightBlueAccent),
          const SizedBox(width: 10),
          _buildStatusCount(Icons.lightbulb, '0', Colors.green),
        ],
      ),
    );
  }

  Widget _buildStatusCount(IconData icon, String count, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(
          count,
          style: const TextStyle(color: Colors.grey, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildTabBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: List.generate(_items.length, (index) {
          final item = _items[index];
          return BottomPanelTab(
            title: item.title,
            icon: item.icon,
            selected: _selectedIndex == index,
            onTap: () {
              setState(() {
                _selectedIndex = index;
              });
            },
          );
        }),
      ),
    );
  }

  Widget _buildExpandedContent() {
    return Material(
      color: const Color(0xFF181818),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.60,
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    // Usamos o IndexedStack para manter ambas as telas (Run e Analysis) vivas na memória
    return IndexedStack(
      index: _selectedIndex,
      children: [
        BottomPanelRun(
          key: const ValueKey('bottom-panel-run'),
        ),
        BottomPanelAnalysis(
          key: const ValueKey('bottom-panel-analysis'),
          analysisCoordinator: widget.analysisCoordinator,
        ),
      ],
    );
  }
}

class _BottomPanelItem {
  final String title;
  final IconData icon;

  const _BottomPanelItem({
    required this.title,
    required this.icon,
  });
}
