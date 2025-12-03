import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../tree_survey_page.dart';
import '../tree_list_page.dart';
import 'cities_page.dart';
import '../main.dart';
import 'ble_import_page.dart';
import 'species_identification_page.dart';
import 'pending_measurement_task_page.dart';
import 'v3_services_page.dart';
import '../constants/colors.dart';
import '../themes/app_theme.dart';

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
  String? _userName;

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
      body: _pages[_selectedIndex],
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

/// 儀表板頁面 - 極簡現代化設計
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String? _userName;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // 自定義 AppBar
        SliverToBoxAdapter(
          child: _buildHeader(),
        ),
        
        // 功能區塊標題
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Row(
              children: [
                Text(
                  '功能中心',
                  style: AppTheme.headlineSmall.copyWith(
                    color: AppColors.neutral900,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.eco_rounded, size: 14, color: AppColors.accent),
                      const SizedBox(width: 4),
                      Text(
                        '永續管理',
                        style: AppTheme.labelMedium.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // 功能卡片網格
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
            delegate: SliverChildListDelegate([
              FeatureCard(
                title: '樹木調查',
                subtitle: '新增與編輯',
                icon: Icons.nature_rounded,
                color: AppColors.primary,
                onTap: () => Navigator.pushNamed(context, '/tree-survey'),
              ),
              FeatureCard(
                title: '統計圖表',
                subtitle: '數據視覺化',
                icon: Icons.bar_chart_rounded,
                color: AppColors.tipcTeal,
                onTap: () => Navigator.pushNamed(context, '/statistics'),
              ),
              FeatureCard(
                title: '樹木地圖',
                subtitle: '位置分佈',
                icon: Icons.map_rounded,
                color: AppColors.chartOrange,
                onTap: () => Navigator.pushNamed(context, '/map'),
              ),
              FeatureCard(
                title: 'AI 助理',
                subtitle: '智慧問答',
                icon: Icons.psychology_rounded,
                color: AppColors.tipcPurple,
                onTap: () => Navigator.pushNamed(context, '/ai-chat'),
              ),
              FeatureCard(
                title: '永續報告',
                subtitle: '碳匯分析',
                icon: Icons.eco_rounded,
                color: AppColors.accent,
                onTap: () => Navigator.pushNamed(context, '/ai-sustainability-report'),
              ),
              FeatureCard(
                title: '縣市專案',
                subtitle: '區域管理',
                icon: Icons.location_city_rounded,
                color: AppColors.primaryDark,
                onTap: () => Navigator.pushNamed(context, '/cities'),
              ),
              FeatureCard(
                title: '藍牙匯入',
                subtitle: '儀器同步',
                icon: Icons.bluetooth_rounded,
                color: AppColors.tipcRed,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BleImportPage()),
                ),
              ),
              FeatureCard(
                title: '待測量任務',
                subtitle: '現場測量',
                icon: Icons.assignment_rounded,
                color: Colors.deepOrange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const PendingMeasurementTaskPage()),
                ),
              ),
              FeatureCard(
                title: '樹種辨識',
                subtitle: '拍照識別',
                icon: Icons.camera_enhance_rounded,
                color: AppColors.accentLight,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SpeciesIdentificationPage()),
                ),
              ),
              FeatureCard(
                title: '進階服務',
                subtitle: 'V3 功能管理',
                icon: Icons.settings_suggest_rounded,
                color: Colors.deepPurple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const V3ServicesPage()),
                ),
              ),
            ]),
          ),
        ),
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

