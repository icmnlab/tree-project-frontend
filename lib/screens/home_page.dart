import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../tree_survey_page.dart';
import '../tree_list_page.dart';
import 'ble_import_page.dart';
import 'species_identification_page.dart';
import 'pending_measurement_task_page.dart';
import 'v3_services_page.dart';
import 'scanner_page.dart';
import '../constants/colors.dart';
import '../themes/app_theme.dart';
import '../widgets/network_aware_widgets.dart';

/// 首頁 - 極簡現代化設計 v2.0
/// 
/// 設計特點：
/// - 底部導航採用浮動式設計
/// - 大量留白，視覺層級清晰
/// - 功能卡片採用漸層圖標設計
/// - TIPC 品牌色彩融入

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  // ignore: unused_field
  String? _userName; // userName loaded for future use

  @override
  void initState() {
    super.initState();
    ApiService.triggerCleanup();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final userInfo = await AuthService.getUserInfo();
    if (mounted) {
      setState(() {
        _userName = userInfo?['display_name'] ?? userInfo?['username'];
      });
    }
  }

  final List<Widget> _pages = [
    const DashboardPage(),
    const TreeSurveyPage(),
    const TreeListPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral100,
      body: Column(
        children: [
          const NetworkAwareBanner(),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
      extendBody: true,
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: [
          BoxShadow(
            color: AppColors.neutral900.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        child: NavigationBar(
          height: 70,
          elevation: 0,
          backgroundColor: Colors.transparent,
          indicatorColor: AppColors.primary.withOpacity(0.1),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded, color: AppColors.primary),
              label: '首頁',
            ),
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded, color: AppColors.primary),
              label: '專案',
            ),
            NavigationDestination(
              icon: Icon(Icons.park_outlined),
              selectedIcon: Icon(Icons.park_rounded, color: AppColors.primary),
              label: '樹木',
            ),
          ],
        ),
      ),
    );
  }
}

/// 儀表板頁面 - 分類式設計 + 可自定義排序
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _userName;
  bool _isEditMode = false;
  List<String> _cardOrder = [];
  
  static const _prefsKey = 'dashboard_card_order';

  // All available cards — order controlled by _cardOrder
  static const _allCards = [
    // 現場作業
    {'id': 'ble', 'title': '藍牙匯入', 'subtitle': '儀器同步', 'icon': 'bluetooth', 'category': 'field', 'needsNetwork': false},
    {'id': 'pending', 'title': '待測量任務', 'subtitle': '現場測量', 'icon': 'assignment', 'category': 'field', 'needsNetwork': true},
    // 數據管理
    {'id': 'survey', 'title': '樹木調查', 'subtitle': '新增與編輯', 'icon': 'nature', 'category': 'data', 'needsNetwork': true},
    {'id': 'map', 'title': '樹木地圖', 'subtitle': '位置分佈', 'icon': 'map', 'category': 'data', 'needsNetwork': true},
    {'id': 'cities', 'title': '專案管理', 'subtitle': '區域管理', 'icon': 'location_city', 'category': 'data', 'needsNetwork': true},
    // 分析報告
    {'id': 'stats', 'title': '統計圖表', 'subtitle': '數據視覺化', 'icon': 'bar_chart', 'category': 'analysis', 'needsNetwork': true},
    {'id': 'report', 'title': '碳匯報告', 'subtitle': '永續分析', 'icon': 'eco', 'category': 'analysis', 'needsNetwork': true},
    // 更多
    {'id': 'test_scan', 'title': '掃描測試 (Demo)', 'subtitle': '快速體驗 DBH', 'icon': 'camera', 'category': 'more', 'needsNetwork': true},
    {'id': 'species', 'title': '樹種辨識', 'subtitle': '拍照識別', 'icon': 'camera_enhance', 'category': 'more', 'needsNetwork': true},
    {'id': 'ai', 'title': 'AI 助理', 'subtitle': '智慧問答', 'icon': 'psychology', 'category': 'more', 'needsNetwork': true},
    {'id': 'v3', 'title': '系統設定', 'subtitle': '校準與同步', 'icon': 'settings_suggest', 'category': 'more', 'needsNetwork': true},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadCardOrder();
  }

  Future<void> _loadUserInfo() async {
    final userInfo = await AuthService.getUserInfo();
    if (mounted) {
      setState(() {
        _userName = userInfo?['display_name'] ?? userInfo?['username'];
      });
    }
  }
  
  Future<void> _loadCardOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_prefsKey);
    final defaultOrder = _allCards.map((c) => c['id'] as String).toList();
    setState(() {
      _cardOrder = saved ?? defaultOrder;
      // Ensure all cards are present (handles new cards added in updates)
      for (final card in _allCards) {
        if (!_cardOrder.contains(card['id'])) {
          _cardOrder.add(card['id'] as String);
        }
      }
    });
  }
  
  Future<void> _saveCardOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _cardOrder);
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'bluetooth': return Icons.bluetooth_rounded;
      case 'assignment': return Icons.assignment_rounded;
      case 'nature': return Icons.nature_rounded;
      case 'map': return Icons.map_rounded;
      case 'location_city': return Icons.location_city_rounded;
      case 'bar_chart': return Icons.bar_chart_rounded;
      case 'eco': return Icons.eco_rounded;
      case 'camera_enhance': return Icons.camera_enhance_rounded;
      case 'camera': return Icons.camera_rounded;
      case 'psychology': return Icons.psychology_rounded;
      case 'settings_suggest': return Icons.settings_suggest_rounded;
      default: return Icons.widgets_rounded;
    }
  }
  
  Color _getColor(String id) {
    switch (id) {
      case 'ble': return AppColors.tipcRed;
      case 'pending': return Colors.deepOrange;
      case 'survey': return AppColors.primary;
      case 'map': return AppColors.chartOrange;
      case 'cities': return AppColors.primaryDark;
      case 'stats': return AppColors.tipcTeal;
      case 'report': return AppColors.accent;
      case 'species': return AppColors.accentLight;
      case 'test_scan': return Colors.tealAccent.shade700;
      case 'ai': return AppColors.tipcPurple;
      case 'v3': return Colors.deepPurple;
      default: return Colors.grey;
    }
  }
  
  void _onCardTap(String id) {
    switch (id) {
      case 'survey': Navigator.pushNamed(context, '/tree-survey'); break;
      case 'stats': Navigator.pushNamed(context, '/statistics'); break;
      case 'map': Navigator.pushNamed(context, '/map'); break;
      case 'ai': Navigator.pushNamed(context, '/ai-chat'); break;
      case 'report': Navigator.pushNamed(context, '/ai-sustainability-report'); break;
      case 'cities': Navigator.pushNamed(context, '/cities'); break;
      case 'ble': Navigator.push(context, MaterialPageRoute(builder: (_) => const BleImportPage())); break;
      case 'pending': Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingMeasurementTaskPage())); break;
      case 'test_scan': Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerPage())); break;
      case 'species': Navigator.push(context, MaterialPageRoute(builder: (_) => const SpeciesIdentificationPage())); break;
      case 'v3': Navigator.push(context, MaterialPageRoute(builder: (_) => const V3ServicesPage())); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabels = {
      'field': '現場作業',
      'data': '數據管理',
      'analysis': '分析報告',
      'more': '更多工具',
    };
    
    // Build ordered card list grouped by category
    final orderedCards = <Map<String, dynamic>>[];
    for (final id in _cardOrder) {
      final card = _allCards.where((c) => c['id'] == id).firstOrNull;
      if (card != null) orderedCards.add(card);
    }
    
    // Group by category preserving order
    final categories = <String>[];
    for (final card in orderedCards) {
      final cat = card['category'] as String;
      if (!categories.contains(cat)) categories.add(cat);
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Text('功能中心', style: AppTheme.headlineSmall.copyWith(color: AppColors.neutral900)),
                const Spacer(),
                IconButton(
                  icon: Icon(_isEditMode ? Icons.check : Icons.tune, size: 20),
                  tooltip: _isEditMode ? '完成排序' : '自定義排序',
                  onPressed: () {
                    if (_isEditMode) _saveCardOrder();
                    setState(() => _isEditMode = !_isEditMode);
                  },
                ),
              ],
            ),
          ),
        ),
        
        ...categories.expand((cat) {
          final cardsInCat = orderedCards.where((c) => c['category'] == cat).toList();
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                child: Text(
                  categoryLabels[cat] ?? cat,
                  style: AppTheme.labelLarge.copyWith(color: AppColors.neutral500),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final card = cardsInCat[index];
                    final id = card['id'] as String;
                    final needsNetwork = card['needsNetwork'] as bool;
                    
                    Widget featureCard = FeatureCard(
                      title: card['title'] as String,
                      subtitle: card['subtitle'] as String?,
                      icon: _getIcon(card['icon'] as String),
                      color: _getColor(id),
                      onTap: _isEditMode ? () {} : () => _onCardTap(id),
                    );
                    
                    if (needsNetwork && !_isEditMode) {
                      featureCard = NetworkGuard(
                        message: '${card['title']} 需要網路連線',
                        child: featureCard,
                      );
                    }
                    
                    if (_isEditMode) {
                      return LongPressDraggable<String>(
                        data: id,
                        feedback: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width / 2 - 24,
                            child: featureCard,
                          ),
                        ),
                        childWhenDragging: Opacity(opacity: 0.3, child: featureCard),
                        child: DragTarget<String>(
                          onAcceptWithDetails: (details) {
                            final draggedId = details.data;
                            final fromIdx = _cardOrder.indexOf(draggedId);
                            final toIdx = _cardOrder.indexOf(id);
                            if (fromIdx != -1 && toIdx != -1) {
                              setState(() {
                                _cardOrder.removeAt(fromIdx);
                                _cardOrder.insert(toIdx, draggedId);
                              });
                            }
                          },
                          builder: (context, candidateData, rejectedData) {
                            return Container(
                              decoration: candidateData.isNotEmpty
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.teal, width: 2),
                                    )
                                  : null,
                              child: featureCard,
                            );
                          },
                        ),
                      );
                    }
                    
                    return featureCard;
                  },
                  childCount: cardsInCat.length,
                ),
              ),
            ),
          ];
        }),
        
        const SliverPadding(padding: EdgeInsets.only(bottom: 100)),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo 與標題
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: AppColors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '永續碳匯管理系統',
                      style: AppTheme.labelLarge.copyWith(
                        color: AppColors.primary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'TIPC 臺灣港務',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppColors.neutral500,
                      ),
                    ),
                  ],
                ),
              ),
              
              // 用戶選單
              _buildUserMenu(),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // 歡迎訊息
          Text(
            '您好，${_userName ?? '使用者'}',
            style: AppTheme.headlineLarge.copyWith(
              color: AppColors.neutral900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '歡迎使用智慧樹木管理平台',
            style: AppTheme.bodyMedium.copyWith(
              color: AppColors.neutral500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMenu() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.neutral100,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        ),
        child: const Icon(
          Icons.person_rounded,
          color: AppColors.neutral700,
          size: 22,
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'profile',
          child: Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 20),
              const SizedBox(width: 12),
              Text(_userName ?? '使用者'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
              const SizedBox(width: 12),
              Text('登出', style: TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'logout') {
          AuthService.logout(context);
        }
      },
    );
  }
}

