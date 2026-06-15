import 'package:flutter/material.dart';

/// Forest Intelligence —— 新 UI 設計系統（Material 3）
///
/// 本檔由設計交付物 `UI_sustainable_treeai/forest_intelligence/DESIGN.md`
/// 的設計 token（色彩 / 字體 / 圓角 / 間距）抽出，封裝成可直接套用的
/// [ThemeData] 與常數，供日後改版時整體採用。
///
/// 採用方式（交接者於 `main.dart` 切換即可，全域生效）：
/// ```dart
/// theme: ForestIntelligenceTheme.lightTheme,
/// ```
///
/// 注意事項：
/// - 目前 App 仍以 `AppTheme.lightTheme` 為現行主題；本主題為「可選用」狀態，
///   尚未掛上 `MaterialApp`，以免在交接前一次改動所有畫面（許多頁面仍有
///   硬編碼色彩，需逐頁改用 `Theme.of(context)` 後整體外觀才會一致）。
/// - 字體 `Plus Jakarta Sans` 尚未隨專案打包。若要完整呈現設計字體，請於
///   `pubspec.yaml` 加入字體資產，或加入 `google_fonts` 套件後改用
///   `GoogleFonts.plusJakartaSansTextTheme(...)`；未提供時 Flutter 會
///   自動退回系統預設字體，不影響執行。
/// - DESIGN.md 僅定義淺色模式；深色模式待設計補齊，此處不提供 darkTheme。
class ForestIntelligenceTheme {
  ForestIntelligenceTheme._();

  /// 設計字體；未打包時 Flutter 會退回系統字體。
  static const String fontFamily = 'Plus Jakarta Sans';

  // ============================================================
  // 色彩 token（取自 DESIGN.md）
  // ============================================================
  // Primary：Ocean Blue —— 核心導覽、主要操作、品牌。
  static const Color primary = Color(0xFF004E8B);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFF0066B3);
  static const Color onPrimaryContainer = Color(0xFFD2E3FF);
  static const Color inversePrimary = Color(0xFFA2C9FF);
  static const Color surfaceTint = Color(0xFF0060A9);

  // Secondary：Forest Green —— 碳匯數據、成長指標、成功狀態。
  static const Color secondary = Color(0xFF1B6D24);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color secondaryContainer = Color(0xFFA0F399);
  static const Color onSecondaryContainer = Color(0xFF217128);

  // Tertiary：Deep Purple —— AI 樹種辨識、LIDAR 處理、智慧分析。
  static const Color tertiary = Color(0xFF781B9F);
  static const Color onTertiary = Color(0xFFFFFFFF);
  static const Color tertiaryContainer = Color(0xFF933AB9);
  static const Color onTertiaryContainer = Color(0xFFF7D7FF);

  // Stats：Deep Cyan —— 資料視覺化、儀表板統計（非 M3 標準槽位，另開常數）。
  static const Color stats = Color(0xFF006A6A);

  // Error / Alert。
  static const Color error = Color(0xFFBA1A1A);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD6);
  static const Color onErrorContainer = Color(0xFF93000A);

  // Surface 與層次。
  static const Color surface = Color(0xFFFCF8FF);
  static const Color onSurface = Color(0xFF1A1A2E);
  static const Color onSurfaceVariant = Color(0xFF414751);
  static const Color surfaceDim = Color(0xFFDAD7F3);
  static const Color surfaceBright = Color(0xFFFCF8FF);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF5F2FF);
  static const Color surfaceContainer = Color(0xFFEFECFF);
  static const Color surfaceContainerHigh = Color(0xFFE8E5FF);
  static const Color surfaceContainerHighest = Color(0xFFE2E0FC);

  static const Color outline = Color(0xFF717782);
  static const Color outlineVariant = Color(0xFFC1C7D3);
  static const Color inverseSurface = Color(0xFF2F2E43);
  static const Color onInverseSurface = Color(0xFFF2EFFF);

  // ============================================================
  // 圓角 token（DESIGN.md：sm/DEFAULT/md/lg/xl/full）
  // ============================================================
  static const double radiusSm = 4; // 0.25rem
  static const double radiusDefault = 8; // 0.5rem，標準元件
  static const double radiusMd = 12; // 0.75rem
  static const double radiusLg = 16; // 1rem，卡片 / 列表項
  static const double radiusXl = 24; // 1.5rem，浮動導覽列 / FAB
  static const double radiusFull = 9999;

  // ============================================================
  // 間距 token（DESIGN.md）
  // ============================================================
  static const double touchTargetMin = 48; // 戴手套可操作的最小觸控目標
  static const double marginScreen = 20; // 畫面側邊安全邊距
  static const double gutterGrid = 16;
  static const double stackSm = 8;
  static const double stackMd = 16;
  static const double stackLg = 24;

  // ============================================================
  // 色彩配置（Material 3 ColorScheme）
  // ============================================================
  static const ColorScheme lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    inversePrimary: inversePrimary,
    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,
    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,
    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    surfaceDim: surfaceDim,
    surfaceBright: surfaceBright,
    surfaceContainerLowest: surfaceContainerLowest,
    surfaceContainerLow: surfaceContainerLow,
    surfaceContainer: surfaceContainer,
    surfaceContainerHigh: surfaceContainerHigh,
    surfaceContainerHighest: surfaceContainerHighest,
    outline: outline,
    outlineVariant: outlineVariant,
    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
    surfaceTint: surfaceTint,
  );

  // ============================================================
  // 字體樣式（DESIGN.md typography → Material 3 TextTheme）
  // ============================================================
  static const TextTheme textTheme = TextTheme(
    displayLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 40 / 32,
      letterSpacing: -0.64, // -0.02em
    ),
    displayMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 32 / 24,
      letterSpacing: -0.24, // -0.01em
    ),
    headlineSmall: TextStyle(
      fontFamily: fontFamily,
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 28 / 20,
    ),
    bodyLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 26 / 18,
    ),
    bodyMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 24 / 16,
    ),
    labelLarge: TextStyle(
      fontFamily: fontFamily,
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 20 / 14,
      letterSpacing: 0.7, // 0.05em
    ),
    labelMedium: TextStyle(
      fontFamily: fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 16 / 12,
    ),
  );

  // ============================================================
  // 完整主題
  // ============================================================
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: lightColorScheme,
    fontFamily: fontFamily,
    textTheme: textTheme,
    scaffoldBackgroundColor: surface,

    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),

    // 卡片：白底、圓角 16、柔和陰影（DESIGN.md Level 1）。
    cardTheme: CardThemeData(
      elevation: 1,
      color: surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
    ),

    // 主要按鈕：實心 Ocean Blue，圓角 24（DESIGN.md 簽名元件）。
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, touchTargetMin),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, touchTargetMin),
        backgroundColor: primaryContainer,
        foregroundColor: onPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
    ),

    // 次要按鈕：Forest Green 外框（區分量測相關操作）。
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, touchTargetMin),
        foregroundColor: secondary,
        side: const BorderSide(color: secondary, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusDefault),
        ),
      ),
    ),

    // 輸入框：外框、聚焦 2px、標籤恆顯（協助戶外作業）。
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceContainerLowest,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusDefault),
        borderSide: const BorderSide(color: outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusDefault),
        borderSide: const BorderSide(color: outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusDefault),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
    ),

    // 籌碼（樹種標籤 / 快速篩選）：圓角 16、高對比。
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLg),
      ),
    ),

    // 浮動底部導覽列：藥丸狀、圓角 24。
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surfaceContainerLowest,
      indicatorColor: primaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXl),
      ),
    ),
  );
}
