import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// 永續碳匯管理系統 - 統一設計系統 v2.0
/// 
/// 極簡現代化設計原則：
/// 1. 大量留白，內容呼吸
/// 2. 清晰的視覺層級
/// 3. 柔和的陰影與圓角
/// 4. 一致的間距系統
/// 5. 優雅的過渡動畫

class AppTheme {
  AppTheme._();

  // ============================================
  // 間距系統
  // ============================================
  static const double spacingXS = 4;
  static const double spacingSM = 8;
  static const double spacingMD = 16;
  static const double spacingLG = 24;
  static const double spacingXL = 32;
  static const double spacingXXL = 48;

  // ============================================
  // 圓角系統
  // ============================================
  static const double radiusSM = 8;
  static const double radiusMD = 12;
  static const double radiusLG = 16;
  static const double radiusXL = 24;
  static const double radiusFull = 100;

  // ============================================
  // 文字樣式
  // ============================================
  static const TextStyle displayLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    color: AppColors.neutral900,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.neutral900,
    letterSpacing: -0.25,
    height: 1.3,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.neutral900,
    height: 1.3,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.neutral900,
    height: 1.4,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.neutral700,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.neutral700,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.neutral500,
    height: 1.4,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.neutral900,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.neutral700,
    letterSpacing: 0.5,
  );

  // ============================================
  // 陰影系統
  // ============================================
  static List<BoxShadow> get shadowSM => [
    BoxShadow(
      color: AppColors.neutral900.withOpacity(0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get shadowMD => [
    BoxShadow(
      color: AppColors.neutral900.withOpacity(0.06),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> get shadowLG => [
    BoxShadow(
      color: AppColors.neutral900.withOpacity(0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  // ============================================
  // Material Theme
  // ============================================
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    // 色彩配置
    colorScheme: ColorScheme.light(
      primary: AppColors.primary,
      primaryContainer: AppColors.primarySurface,
      secondary: AppColors.accent,
      secondaryContainer: AppColors.accentSurface,
      tertiary: AppColors.tipcTeal,
      surface: AppColors.white,
      error: AppColors.error,
      onPrimary: AppColors.white,
      onSecondary: AppColors.white,
      onSurface: AppColors.neutral900,
      onError: AppColors.white,
      outline: AppColors.neutral300,
      outlineVariant: AppColors.neutral200,
    ),

    // Scaffold 背景
    scaffoldBackgroundColor: AppColors.neutral100,

    // AppBar 主題 - 極簡白色風格
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppColors.neutral900),
      actionsIconTheme: const IconThemeData(color: AppColors.neutral700),
      titleTextStyle: headlineMedium.copyWith(fontSize: 18),
      centerTitle: false,
    ),

    // 卡片主題
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLG),
        side: BorderSide(color: AppColors.neutral300.withOpacity(0.5)),
      ),
      margin: EdgeInsets.zero,
    ),

    // 按鈕主題
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
        ),
        textStyle: labelLarge,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
        ),
        side: const BorderSide(color: AppColors.primary),
        textStyle: labelLarge,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: labelLarge,
      ),
    ),

    // 浮動按鈕主題
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLG),
      ),
    ),

    // 輸入框主題
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.neutral300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.neutral300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      hintStyle: bodyMedium.copyWith(color: AppColors.neutral500),
      labelStyle: bodyMedium,
    ),

    // Chip 主題
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.neutral100,
      selectedColor: AppColors.primary.withOpacity(0.15),
      labelStyle: labelMedium,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusFull),
      ),
    ),

    // 底部導航主題
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.white,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.neutral500,
      selectedLabelStyle: labelMedium.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: labelMedium,
    ),

    // 對話框主題
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXL),
      ),
      titleTextStyle: headlineSmall,
      contentTextStyle: bodyMedium,
    ),

    // Snackbar 主題
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.neutral900,
      contentTextStyle: bodyMedium.copyWith(color: AppColors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
    ),

    // 分隔線主題
    dividerTheme: DividerThemeData(
      color: AppColors.neutral300.withOpacity(0.5),
      thickness: 1,
      space: 1,
    ),

    // 圖標主題
    iconTheme: const IconThemeData(
      color: AppColors.neutral700,
      size: 24,
    ),

    // 文字主題
    textTheme: const TextTheme(
      displayLarge: displayLarge,
      headlineLarge: headlineLarge,
      headlineMedium: headlineMedium,
      headlineSmall: headlineSmall,
      bodyLarge: bodyLarge,
      bodyMedium: bodyMedium,
      bodySmall: bodySmall,
      labelLarge: labelLarge,
      labelMedium: labelMedium,
    ),

    // TabBar 主題
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primary,
      unselectedLabelColor: AppColors.neutral500,
      indicatorColor: AppColors.primary,
      labelStyle: labelLarge,
      unselectedLabelStyle: labelMedium,
    ),

    // ListTile 主題
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
    ),

    // Switch 主題
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return AppColors.neutral400;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary.withOpacity(0.3);
        }
        return AppColors.neutral300;
      }),
    ),

    // Checkbox 主題
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return Colors.transparent;
      }),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),

    // Radio 主題
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primary;
        }
        return AppColors.neutral500;
      }),
    ),

    // ProgressIndicator 主題
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.neutral200,
    ),

    // Slider 主題
    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.neutral200,
      thumbColor: AppColors.primary,
      overlayColor: AppColors.primary.withOpacity(0.2),
    ),
  );

  // ============================================
  // 暗色主題
  // ============================================
  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    colorScheme: ColorScheme.dark(
      primary: AppColors.primaryLight,
      primaryContainer: AppColors.primaryDark,
      secondary: AppColors.accentLight,
      secondaryContainer: AppColors.accentDark,
      tertiary: AppColors.tipcTeal,
      surface: AppColors.darkSurface,
      error: const Color(0xFFEF5350),
      onPrimary: AppColors.white,
      onSecondary: AppColors.white,
      onSurface: AppColors.darkTextPrimary,
      onError: AppColors.white,
      outline: AppColors.darkBorder,
      outlineVariant: AppColors.darkSurfaceLighter,
    ),

    scaffoldBackgroundColor: AppColors.darkBackground,

    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
      iconTheme: const IconThemeData(color: AppColors.darkTextPrimary),
      actionsIconTheme: const IconThemeData(color: AppColors.darkTextSecondary),
      titleTextStyle: headlineMedium.copyWith(
        fontSize: 18,
        color: AppColors.darkTextPrimary,
      ),
      centerTitle: false,
    ),

    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLG),
        side: BorderSide(color: AppColors.darkBorder.withValues(alpha: 0.5)),
      ),
      margin: EdgeInsets.zero,
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryLight,
        foregroundColor: AppColors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
        ),
        textStyle: labelLarge,
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD),
        ),
        side: const BorderSide(color: AppColors.primaryLight),
        textStyle: labelLarge,
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primaryLight,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: labelLarge,
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: AppColors.primaryLight,
      foregroundColor: AppColors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusLG),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurfaceLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMD),
        borderSide: const BorderSide(color: Color(0xFFEF5350)),
      ),
      hintStyle: bodyMedium.copyWith(color: AppColors.darkTextTertiary),
      labelStyle: bodyMedium.copyWith(color: AppColors.darkTextSecondary),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkSurfaceLighter,
      selectedColor: AppColors.primaryLight.withValues(alpha: 0.2),
      labelStyle: labelMedium.copyWith(color: AppColors.darkTextPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusFull),
      ),
    ),

    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppColors.primaryLight,
      unselectedItemColor: AppColors.darkTextTertiary,
      selectedLabelStyle: labelMedium.copyWith(fontWeight: FontWeight.w600),
      unselectedLabelStyle: labelMedium,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusXL),
      ),
      titleTextStyle: headlineSmall.copyWith(color: AppColors.darkTextPrimary),
      contentTextStyle: bodyMedium.copyWith(color: AppColors.darkTextSecondary),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkSurfaceLighter,
      contentTextStyle: bodyMedium.copyWith(color: AppColors.darkTextPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
    ),

    dividerTheme: DividerThemeData(
      color: AppColors.darkBorder.withOpacity(0.5),
      thickness: 1,
      space: 1,
    ),

    iconTheme: const IconThemeData(
      color: AppColors.darkTextSecondary,
      size: 24,
    ),

    textTheme: TextTheme(
      displayLarge: displayLarge.copyWith(color: AppColors.darkTextPrimary),
      headlineLarge: headlineLarge.copyWith(color: AppColors.darkTextPrimary),
      headlineMedium: headlineMedium.copyWith(color: AppColors.darkTextPrimary),
      headlineSmall: headlineSmall.copyWith(color: AppColors.darkTextPrimary),
      bodyLarge: bodyLarge.copyWith(color: AppColors.darkTextSecondary),
      bodyMedium: bodyMedium.copyWith(color: AppColors.darkTextSecondary),
      bodySmall: bodySmall.copyWith(color: AppColors.darkTextTertiary),
      labelLarge: labelLarge.copyWith(color: AppColors.darkTextPrimary),
      labelMedium: labelMedium.copyWith(color: AppColors.darkTextSecondary),
    ),

    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.primaryLight,
      unselectedLabelColor: AppColors.darkTextTertiary,
      indicatorColor: AppColors.primaryLight,
      labelStyle: labelLarge,
      unselectedLabelStyle: labelMedium,
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
      tileColor: Colors.transparent,
      textColor: AppColors.darkTextPrimary,
      iconColor: AppColors.darkTextSecondary,
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryLight;
        }
        return AppColors.darkTextTertiary;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryLight.withValues(alpha: 0.3);
        }
        return AppColors.darkBorder;
      }),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryLight;
        }
        return Colors.transparent;
      }),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
      ),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return AppColors.primaryLight;
        }
        return AppColors.darkTextTertiary;
      }),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primaryLight,
      linearTrackColor: AppColors.darkSurfaceLighter,
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: AppColors.primaryLight,
      inactiveTrackColor: AppColors.darkSurfaceLighter,
      thumbColor: AppColors.primaryLight,
      overlayColor: AppColors.primaryLight.withValues(alpha: 0.2),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.darkCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMD),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.darkSurface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

// ============================================
// 常用 Widget 組件
// ============================================

/// 統一的卡片樣式
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final List<BoxShadow>? shadow;
  final bool hasBorder;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.backgroundColor,
    this.shadow,
    this.hasBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: hasBorder ? Border.all(
          color: AppColors.neutral300.withOpacity(0.5),
        ) : null,
        boxShadow: shadow ?? AppTheme.shadowSM,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(AppTheme.spacingMD),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// 統一的圖標按鈕容器
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;
  final String? tooltip;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
    this.size = 44,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.neutral100,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          child: Icon(
            icon,
            color: iconColor ?? AppColors.neutral700,
            size: size * 0.5,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// 統一的標籤/徽章樣式
class AppBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSM,
        vertical: AppTheme.spacingXS,
      ),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: textColor ?? AppColors.primary,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTheme.labelMedium.copyWith(
              color: textColor ?? AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 統計數值卡片
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const Spacer(),
              if (onTap != null)
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: AppColors.neutral500,
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMD),
          Text(
            value,
            style: AppTheme.headlineLarge.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTheme.spacingXS),
          Text(
            title,
            style: AppTheme.bodyMedium.copyWith(
              color: AppColors.neutral700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppTheme.spacingXS),
            Text(
              subtitle!,
              style: AppTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// 功能入口卡片
class FeatureCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const FeatureCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : AppColors.white;
    final borderColor = isDark
        ? AppColors.darkBorder.withValues(alpha: 0.5)
        : AppColors.neutral300.withValues(alpha: 0.5);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
        border: Border.all(color: borderColor),
        boxShadow: isDark ? null : AppTheme.shadowSM,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusLG),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMD),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        color,
                        color.withValues(alpha: 0.8),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 28, color: AppColors.white),
                ),
                const SizedBox(height: AppTheme.spacingMD),
                Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge,
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppTheme.spacingXS),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 空狀態組件
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingXL),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.neutral100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: AppColors.neutral500,
              ),
            ),
            const SizedBox(height: AppTheme.spacingLG),
            Text(
              title,
              style: AppTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: AppTheme.spacingSM),
              Text(
                description!,
                style: AppTheme.bodyMedium.copyWith(
                  color: AppColors.neutral500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppTheme.spacingLG),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

