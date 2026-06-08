import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/theme_service.dart';
import '../tree_survey_page.dart';
import '../tree_list_page.dart';
import 'ble_import_page.dart';
import 'ble_live_session_page.dart';
import 'maintenance_survey_page.dart';
import '../widgets/field/field_session_setup.dart';
import '../services/locale_service.dart';
import 'species_identification_page.dart';
import 'pending_measurement_task_page.dart';
import 'v3_services_page.dart';
import 'scanner_page.dart';
import '../config/app_config.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : AppColors.neutral100;

    return Scaffold(
      backgroundColor: bgColor,
      body: Column(
        children: [
          const NetworkAwareBanner(),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(isDark),
    );
  }

  /// 頁面轉場動畫路由 (reserved for future navigation transitions)
  // ignore: unused_element
  static PageRouteBuilder _buildPageRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  Widget _buildBottomNavBar(bool isDark) {
    final navBg = isDark ? AppColors.darkSurface : AppColors.white;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: navBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusXL),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : AppColors.neutral900).withValues(alpha: 0.15),
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
          indicatorColor: primary.withValues(alpha: 0.1),
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() => _selectedIndex = index);
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded, color: primary),
              label: LocaleService.instance.t('nav_home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder_rounded, color: primary),
              label: LocaleService.instance.t('nav_projects'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.park_outlined),
              selectedIcon: Icon(Icons.park_rounded, color: primary),
              label: LocaleService.instance.t('nav_trees'),
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

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  String? _userName;
  bool _isEditMode = false;
  List<String> _cardOrder = [];
  
  static const _prefsKey = 'dashboard_card_order';

  // All available cards — order controlled by _cardOrder
  static const _allCards = [
    // 現場作業
    {'id': 'field_survey', 'title': 'VLGEO2 現場連線', 'subtitle': '掃描儀器 · 逐棵提交', 'icon': 'bluetooth_connected', 'category': 'field', 'needsNetwork': true},
    {'id': 'maintenance', 'title': '維護量測', 'subtitle': '選區重測既有樹木', 'icon': 'build', 'category': 'field', 'needsNetwork': true},
    {'id': 'ble', 'title': '藍牙匯入', 'subtitle': '儀器同步', 'icon': 'bluetooth', 'category': 'field', 'needsNetwork': false},
    {'id': 'pending', 'title': '待測量任務', 'subtitle': '批次導航測量', 'icon': 'assignment', 'category': 'field', 'needsNetwork': true},
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
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0, 0.5, curve: Curves.easeOut),
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0, 0.5, curve: Curves.easeOutCubic),
    ));
    _animController.forward();
    _loadUserInfo();
    _loadCardOrder();
    LocaleService.instance.load();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// 卡片交錯動畫
  Animation<double> _cardAnimation(int index) {
    final start = (0.15 + index * 0.05).clamp(0.0, 0.85);
    final end = (start + 0.15).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _animController,
      curve: Interval(start, end, curve: Curves.easeOutBack),
    );
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
      _cardOrder.removeWhere((id) => !AppConfig.isDashboardCardVisible(id));
      _cardOrder.removeWhere((id) => id == 'ble_live');
      if (!_cardOrder.contains('maintenance')) {
        final i = _cardOrder.indexOf('field_survey');
        if (i >= 0) {
          _cardOrder.insert(i + 1, 'maintenance');
        } else {
          _cardOrder.insert(0, 'maintenance');
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
      case 'forest': return Icons.forest_rounded;
      case 'bluetooth_connected': return Icons.bluetooth_connected_rounded;
      case 'build': return Icons.build_circle_outlined;
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
      case 'field_survey':
      case 'ble':
      case 'ble_live':
        return AppColors.tipcRed;
      case 'maintenance': return Colors.teal.shade700;
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
  
  String _l10n(String key) => LocaleService.instance.t(key);

  String _cardTitleKey(String id) {
    switch (id) {
      case 'field_survey':
        return 'card_field_survey';
      case 'maintenance':
        return 'card_maintenance';
      case 'ble':
        return 'card_ble';
      case 'ble_live':
        return 'card_ble_live';
      case 'pending':
        return 'card_pending';
      case 'survey':
        return 'card_survey';
      case 'map':
        return 'card_map';
      case 'cities':
        return 'card_cities';
      case 'stats':
        return 'card_stats';
      case 'report':
        return 'card_report';
      case 'species':
        return 'card_species';
      case 'test_scan':
        return 'card_scan';
      case 'ai':
        return 'card_ai';
      case 'v3':
        return 'card_v3';
      default:
        return id;
    }
  }

  String _cardSubtitleKey(String id) => '${_cardTitleKey(id)}_sub';

  Future<void> _openFieldLiveSession() async {
    final setup = await showFieldSessionSetupDialog(context);
    if (!mounted || setup == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BleLiveSessionPage(initialSessionSetup: setup),
      ),
    );
  }

  void _onCardTap(String id) {
    switch (id) {
      case 'survey': Navigator.pushNamed(context, '/tree-survey'); break;
      case 'stats': Navigator.pushNamed(context, '/statistics'); break;
      case 'map': Navigator.pushNamed(context, '/map'); break;
      case 'ai': Navigator.pushNamed(context, '/ai-chat'); break;
      case 'report': Navigator.pushNamed(context, '/ai-sustainability-report'); break;
      case 'cities': Navigator.pushNamed(context, '/cities'); break;
      case 'field_survey':
      case 'ble_live':
        _openFieldLiveSession();
        break;
      case 'maintenance':
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MaintenanceSurveyPage()),
        );
        break;
      case 'ble':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BleImportPage()));
        break;
      case 'pending': Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingMeasurementTaskPage())); break;
      case 'test_scan': Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerPage())); break;
      case 'species': Navigator.push(context, MaterialPageRoute(builder: (_) => const SpeciesIdentificationPage())); break;
      case 'v3': Navigator.push(context, MaterialPageRoute(builder: (_) => const V3ServicesPage())); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryLabels = {
      'field': _l10n('cat_field'),
      'data': _l10n('cat_data'),
      'analysis': _l10n('cat_analysis'),
      'more': _l10n('cat_more'),
    };
    
    // Build ordered card list grouped by category
    final orderedCards = <Map<String, dynamic>>[];
    for (final id in _cardOrder) {
      if (!AppConfig.isDashboardCardVisible(id)) continue;
      final card = _allCards.where((c) => c['id'] == id).firstOrNull;
      if (card != null) orderedCards.add(card);
    }
    
    // Group by category preserving order
    final categories = <String>[];
    for (final card in orderedCards) {
      final cat = card['category'] as String;
      if (!categories.contains(cat)) categories.add(cat);
    }

    // Build global card index for staggered animation
    int globalCardIndex = 0;
    final cardIndexMap = <String, int>{};
    for (final card in orderedCards) {
      cardIndexMap[card['id'] as String] = globalCardIndex++;
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SlideTransition(
            position: _headerSlide,
            child: FadeTransition(
              opacity: _headerFade,
              child: _buildHeader(),
            ),
          ),
        ),
        
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Row(
              children: [
                Text(_l10n('feature_center'),
                    style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  icon: Icon(_isEditMode ? Icons.check : Icons.tune, size: 20),
                  tooltip: _isEditMode
                      ? _l10n('dashboard_edit_done')
                      : _l10n('dashboard_edit_sort'),
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
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
                    
                    final title = _l10n(_cardTitleKey(id));
                    final subtitle = _l10n(_cardSubtitleKey(id));
                    Widget featureCard = FeatureCard(
                      title: title,
                      subtitle: subtitle,
                      icon: _getIcon(card['icon'] as String),
                      color: _getColor(id),
                      onTap: _isEditMode ? () {} : () => _onCardTap(id),
                    );
                    
                    if (needsNetwork && !_isEditMode) {
                      featureCard = NetworkGuard(
                        message: '$title ${_l10n('needs_network')}',
                        child: featureCard,
                      );
                    }
                    
                    // 交錯入場動畫
                    final cardIdx = cardIndexMap[id] ?? 0;
                    final anim = _cardAnimation(cardIdx);

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
                    
                    return ScaleTransition(
                      scale: anim,
                      child: FadeTransition(
                        opacity: anim,
                        child: featureCard,
                      ),
                    );
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

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 6) return _l10n('greeting_night');
    if (hour < 12) return _l10n('greeting_morning');
    if (hour < 18) return _l10n('greeting_afternoon');
    return _l10n('greeting_evening');
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerBg = isDark ? AppColors.darkSurface : AppColors.white;

    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 24),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.only(
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
                      color: AppColors.primary.withValues(alpha: 0.3),
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
                      _l10n('app_title'),
                      style: AppTheme.labelLarge.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _l10n('brand_org'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              
              // 用戶選單
              _buildUserMenu(),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // 動態問候訊息
          Text(
            '${_getGreeting()}，${_userName ?? _l10n('user_default')}',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _l10n('welcome_subtitle'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserMenu() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<String>(
      offset: const Offset(0, 48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceLighter : AppColors.neutral100,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        ),
        child: Icon(
          Icons.person_rounded,
          color: isDark ? AppColors.darkTextSecondary : AppColors.neutral700,
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
          value: 'theme',
          child: Row(
            children: [
              Icon(
                isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(isDark ? _l10n('theme_light') : _l10n('theme_dark')),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'language',
          child: Row(
            children: [
              const Icon(Icons.language_rounded, size: 20),
              const SizedBox(width: 12),
              Text(LocaleService.instance.languageMenuLabel),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'logout',
          child: Row(
            children: [
              const Icon(Icons.logout_rounded, size: 20, color: AppColors.error),
              const SizedBox(width: 12),
              Text(_l10n('logout'), style: const TextStyle(color: AppColors.error)),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        if (value == 'logout') {
          AuthService.logout(context);
        } else if (value == 'theme') {
          ThemeService().toggleDarkMode();
        } else if (value == 'language') {
          LocaleService.instance.cycleLanguage().then((_) {
            if (context.mounted) setState(() {});
          });
        }
      },
    );
  }
}

