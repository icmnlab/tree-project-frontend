import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'tree_survey_page.dart'; // 查詢頁面
import 'admin_page.dart';
import 'statistics_page.dart';
import 'map_page.dart';
import 'screens/ai_sustainability_report_screen.dart';
import 'ai_assistant_page.dart';
import 'screens/ai_chat_page.dart'; // 新版 AI 聊天頁面
import 'screens/cities_page.dart';
import 'services/carbon_sink_service.dart';
import 'services/v3/ml_data_sync_service.dart'; // V3 ML 數據同步服務
import 'screens/login_page.dart';
import 'screens/home_page.dart';
import 'routes/auth_guard.dart';
import 'config/app_config.dart';
import 'themes/app_theme.dart'; // 新設計系統

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
        '/ai-assistant': (context) => AIAssistantPage(
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
      },
    );
  }
}
