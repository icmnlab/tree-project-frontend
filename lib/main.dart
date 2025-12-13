import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/login_page.dart';
import 'screens/home_page.dart';
import 'admin_page.dart';
import 'tree_survey_page.dart';
import 'statistics_page.dart';
import 'map_page.dart';
import 'screens/ai_chat_page.dart';
import 'screens/ai_sustainability_report_screen.dart';
import 'screens/cities_page.dart';
import 'screens/v3/manual_input_page_v3.dart';
import 'screens/v3/project_boundary_draw_page.dart';
import 'screens/v3_services_page.dart';
import 'routes/auth_guard.dart';
import 'themes/app_theme.dart';
import 'config/app_config.dart';
import 'config/global_keys.dart';
import 'services/api_service.dart';
import 'services/carbon_sink_service.dart';
import 'services/v3/ml_data_sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 設置系統 UI 樣式
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Initialize AppConfig asynchronously
  await AppConfig().initialize();

  await ApiService.initialize();

  // Initialize CarbonSinkService to preload tree species data
  final carbonSinkService = CarbonSinkService();
  try {
    await carbonSinkService.initialize();
    print('樹種資料成功初始化');
  } catch (e) {
    print('樹種資料初始化失敗: $e');
  }

  // V3: 初始化 ML 數據同步服務
  try {
    await MLDataSyncService.initialize(AppConfig().baseUrl);
    // 啟動背景同步（每 30 分鐘檢查一次）
    MLDataSyncService().startPeriodicSync();
    print('ML 數據同步服務已初始化');
  } catch (e) {
    print('ML 數據同步服務初始化失敗: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '永續碳匯管理系統',
      navigatorKey: GlobalKeys.navigatorKey, // Assign global navigator key
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme, // 使用新設計系統
      initialRoute: '/login',
      routes: {
        '/': (context) =>
            const LoginPage(), // Default route for logout redirect
        '/login': (context) => const LoginPage(),
        '/home': (context) => const AuthGuard(child: HomePage()),
        '/admin': (context) =>
            const AuthGuard(requireAdmin: true, child: AdminPage()),
        '/tree-survey': (context) => const TreeSurveyPage(),
        '/statistics': (context) => const StatisticsPage(),
        '/map': (context) => const MapPage(),
        // 舊路由保留兼容，重定向到新版 AI Chat
        '/ai-assistant': (context) => AIChatPage(
              userId: 'user-${DateTime.now().millisecondsSinceEpoch}',
              selectedProjectAreas: const [],
            ),
        // 新版 AI 聊天頁面 (ChatGPT 風格)
        '/ai-chat': (context) => AIChatPage(
              userId: 'user-${DateTime.now().millisecondsSinceEpoch}',
              selectedProjectAreas: const [],
            ),
        '/ai-sustainability-report': (context) =>
            const AISustainabilityReportScreen(),
        '/cities': (context) => const CitiesPage(),
        // V3 功能路由
        '/v3-services': (context) => const V3ServicesPage(),
        '/v3-manual-input': (context) => const ManualInputPageV3(),
        // IntegratedTreeFormPage 需要 task 參數，不應放在 routes 中
        // 目前由 PendingMeasurementTaskPage 使用 MaterialPageRoute 直接導航
        // 如需路由方式，應使用 onGenerateRoute 處理 arguments
        // '/v3-integrated-form': (context) => const IntegratedTreeFormPage(),
        '/v3-project-boundary': (context) => const ProjectBoundaryDrawPage(),
      },
    );
  }
}
