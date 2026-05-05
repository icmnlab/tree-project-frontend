import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'services/theme_service.dart';
import 'config/global_keys.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/v3/ml_data_sync_service.dart';
import 'services/v3/tree_image_service.dart';
import 'services/network_service.dart';

/// 取得目前已登入帳號的 AI Chat userId。
/// 改用真實帳號 ID（過去誤用裝置綁定 timestamp ID，導致同一裝置不同帳號共用對話）。
Future<String> _getCurrentAiUserId() async {
  final userInfo = await AuthService.getUserInfo();
  if (userInfo == null) return 'anon';
  // 優先使用 user_id（資料庫主鍵），其次 account（登入帳號）。
  final id = userInfo['user_id']?.toString()
      ?? userInfo['account']?.toString()
      ?? userInfo['username']?.toString();
  return (id == null || id.isEmpty) ? 'anon' : 'u$id';
}

/// 一次性清除舊版（裝置綁定）AI Chat userId key，避免共用對話殘留。
Future<void> _migrateLegacyAiUserId() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey('ai_chat_user_id')) {
    await prefs.remove('ai_chat_user_id');
  }
}

/// 允許自架伺服器的自簽憑證 (僅限 Tailscale 內網 IP / MagicDNS)
class SelfHostedHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        // 只信任 Tailscale 內網的自簽憑證：
        //   - Ubuntu server IP (100.118.203.75)
        //   - Windows server IP (100.81.214.9)
        //   - Tailscale MagicDNS 名稱 (*.ts.net)
        // 任何公網或非 Tailscale 的主機都仍會正常驗證 TLS，保持安全性。
        if (host == '100.118.203.75') return true;
        if (host == '100.81.214.9') return true;
        if (host.endsWith('.ts.net')) return true;
        return false;
      };
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 允許自架伺服器的自簽 TLS 憑證
  HttpOverrides.global = SelfHostedHttpOverrides();

  // 初始化網路連線監聯
  await NetworkService().init();

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

  // [Stage 0.3] 已移除 CarbonSinkService preload：
  //   依賴的後端 /carbon-sink/tree-species 路由與 tree_carbon_data 表均已刪除，
  //   實際也未被任何画面使用。

  // V3: 初始化 ML 數據同步服務
  try {
    await MLDataSyncService.initialize(AppConfig().baseUrl);
    // 啟動背景同步（每 30 分鐘檢查一次）
    MLDataSyncService().startPeriodicSync();
    TreeImageService().startPeriodicSync();
    debugPrint('ML 數據同步服務已初始化');
  } catch (e) {
    debugPrint('ML 數據同步服務初始化失敗: $e');
  }

  // 初始化主題服務
  await ThemeService().initialize();

  // 一次性遷移：清除舊版裝置綁定的 AI Chat userId（避免帳號間互看對話）
  await _migrateLegacyAiUserId();

  runApp(const MyApp());
}

/// 包裝 AIChatPage，確保 userId 來自當前登入帳號（避免裝置綁定共用）。
class _AIChatRoute extends StatelessWidget {
  final List<String> selectedProjectAreas;
  // ignore: unused_element_parameter
  const _AIChatRoute({this.selectedProjectAreas = const []});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _getCurrentAiUserId(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return AIChatPage(
          userId: snap.data ?? 'anon',
          selectedProjectAreas: selectedProjectAreas,
        );
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeService(),
      builder: (context, _) => MaterialApp(
      title: '永續碳匯管理系統',
      navigatorKey: GlobalKeys.navigatorKey,
      navigatorObservers: [GlobalKeys.routeObserver],
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeService().themeMode,
      // [N8 RWD] 限制系統字體放大倍率，避免極大字體在小螢幕擠爆 layout / overflow。
      // 仍尊重使用者偏好（在 0.85~1.30 之間），無障礙需求極大字仍可讀。
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.30,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child ?? const SizedBox.shrink(),
        );
      },
      initialRoute: '/login',
      routes: {
        '/': (context) =>
            const LoginPage(), // Default route for logout redirect
        '/login': (context) => const LoginPage(),
        '/home': (context) => const AuthGuard(child: HomePage()),
        '/admin': (context) =>
            const AuthGuard(requireAdmin: true, child: AdminPage()),
        '/tree-survey': (context) =>
            const AuthGuard(child: TreeSurveyPage()),
        '/statistics': (context) =>
            const AuthGuard(child: StatisticsPage()),
        '/map': (context) => const AuthGuard(child: MapPage()),
        // 舊路由保留兼容，重定向到新版 AI Chat
        '/ai-assistant': (context) => const AuthGuard(
              child: _AIChatRoute(),
            ),
        // 新版 AI 聊天頁面 (ChatGPT 風格)
        '/ai-chat': (context) => const AuthGuard(
              child: _AIChatRoute(),
            ),
        '/ai-sustainability-report': (context) =>
            const AuthGuard(child: AISustainabilityReportScreen()),
        '/cities': (context) => const AuthGuard(child: CitiesPage()),
        // V3 功能路由
        '/v3-services': (context) =>
            const AuthGuard(child: V3ServicesPage()),
        '/v3-manual-input': (context) =>
            const AuthGuard(child: ManualInputPageV3()),
        // IntegratedTreeFormPage 需要 task 參數，不應放在 routes 中
        // 目前由 PendingMeasurementTaskPage 使用 MaterialPageRoute 直接導航
        // 如需路由方式，應使用 onGenerateRoute 處理 arguments
        // '/v3-integrated-form': (context) => const IntegratedTreeFormPage(),
        '/v3-project-boundary': (context) =>
            const AuthGuard(requiredRole: '專案管理員', child: ProjectBoundaryDrawPage()),
      },
    ),
    );
  }
}
