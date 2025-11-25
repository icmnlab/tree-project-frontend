import 'package:flutter/material.dart';
//import 'package:flutter_dotenv/flutter_dotenv.dart';
//import 'tree_input_page.dart'; // 引入你的輸入頁面
import 'tree_survey_page.dart'; // 查詢頁面
import 'admin_page.dart';
import 'statistics_page.dart';
import 'map_page.dart';
import 'screens/ai_sustainability_report_screen.dart';
import 'ai_assistant_page.dart';
import 'screens/cities_page.dart';
import 'services/carbon_sink_service.dart';
import 'screens/login_page.dart';
import 'screens/home_page.dart';
import 'routes/auth_guard.dart';
import 'config/app_config.dart'; // Import AppConfig

ThemeData createAppTheme() {
  return ThemeData(
    primarySwatch: const MaterialColor(
      0xFF2E7D32, // 深綠色
      <int, Color>{
        50: Color(0xFFE8F5E9),
        100: Color(0xFFC8E6C9),
        200: Color(0xFFA5D6A7),
        300: Color(0xFF81C784),
        400: Color(0xFF66BB6A),
        500: Color(0xFF4CAF50),
        600: Color(0xFF43A047),
        700: Color(0xFF388E3C),
        800: Color(0xFF2E7D32),
        900: Color(0xFF1B5E20),
      },
    ),
    colorScheme: ColorScheme.light(
      primary: const Color(0xFF2E7D32), // 主要顏色（深綠色）
      primaryContainer: const Color(0xFFC8E6C9), // 主要顏色容器（淺綠色）
      secondary: const Color(0xFF795548), // 次要顏色（棕色）
      secondaryContainer: const Color(0xFFD7CCC8), // 次要顏色容器（淺棕色）
      surface: Colors.white,
      error: Colors.red[700]!,
    ),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: Color(0xFF2E7D32),
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF2E7D32),
        side: const BorderSide(color: Color(0xFF2E7D32)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey[400]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF2E7D32), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2E7D32),
      ),
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2E7D32),
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: Color(0xFF2E7D32),
      ),
      bodyLarge: TextStyle(fontSize: 16, color: Colors.black87),
      bodyMedium: TextStyle(fontSize: 14, color: Colors.black87),
    ),
    dividerTheme: DividerThemeData(thickness: 1, color: Colors.grey[300]),
    iconTheme: const IconThemeData(color: Color(0xFF2E7D32)),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF2E7D32),
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智慧樹木管理系統',
      theme: createAppTheme(),
      initialRoute: '/login',
      routes: {
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
        '/ai-sustainability-report': (context) =>
            const AISustainabilityReportScreen(),
        '/cities': (context) => const CitiesPage(),
      },
    );
  }
}
