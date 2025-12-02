import 'package:flutter/material.dart';

/// 永續碳匯管理系統 - 統一配色系統 v2.0
/// 
/// 設計靈感：
/// - TIPC 臺灣港務公司品牌色彩（藍色波浪、紅色、黃色、紫色）
/// - 港務與樹木自然元素結合
/// - 極簡現代化設計原則
/// 
/// 配色邏輯：
/// - 主色：海洋藍 (Ocean Blue) - 代表港口與海洋
/// - 強調色：森林綠 (Forest Green) - 代表樹木與永續
/// - 輔助色：暖陽黃、珊瑚紅、深紫 - 源自 TIPC Logo

class AppColors {
  AppColors._();

  // ============================================
  // 主品牌色 - 海洋藍系列
  // ============================================
  static const Color primary = Color(0xFF0066B3);          // 主藍色
  static const Color primaryLight = Color(0xFF4D94D1);     // 淺藍色
  static const Color primaryDark = Color(0xFF004A82);      // 深藍色
  static const Color primarySurface = Color(0xFFE8F4FC);   // 藍色表面

  // ============================================
  // 強調色 - 森林綠系列（樹木與永續）
  // ============================================
  static const Color accent = Color(0xFF2E7D32);           // 森林綠
  static const Color accentLight = Color(0xFF4CAF50);      // 亮綠色
  static const Color accentDark = Color(0xFF1B5E20);       // 深綠色
  static const Color accentSurface = Color(0xFFE8F5E9);    // 綠色表面

  // ============================================
  // TIPC 品牌輔助色
  // ============================================
  static const Color tipcRed = Color(0xFFE53935);          // TIPC 紅色波浪
  static const Color tipcYellow = Color(0xFFFFC107);       // TIPC 黃色
  static const Color tipcPurple = Color(0xFF7B1FA2);       // TIPC 紫色波浪
  static const Color tipcTeal = Color(0xFF00897B);         // 青色（海洋）

  // ============================================
  // 功能色 - 圖表與數據視覺化
  // ============================================
  static const Color chartBlue = Color(0xFF2196F3);
  static const Color chartGreen = Color(0xFF4CAF50);
  static const Color chartOrange = Color(0xFFFF9800);
  static const Color chartPurple = Color(0xFF9C27B0);
  static const Color chartRed = Color(0xFFF44336);
  static const Color chartTeal = Color(0xFF009688);

  // ============================================
  // 語義色
  // ============================================
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFF9A825);
  static const Color error = Color(0xFFD32F2F);
  static const Color info = Color(0xFF0288D1);

  // ============================================
  // 中性色 - 極簡現代
  // ============================================
  static const Color neutral900 = Color(0xFF1A1A2E);       // 主文字
  static const Color neutral800 = Color(0xFF2D2D44);
  static const Color neutral700 = Color(0xFF4A4A68);       // 次要文字
  static const Color neutral600 = Color(0xFF6B6B8A);
  static const Color neutral500 = Color(0xFF8E8EA9);       // 輔助文字
  static const Color neutral400 = Color(0xFFB0B0C5);
  static const Color neutral300 = Color(0xFFD1D1E0);       // 邊框
  static const Color neutral200 = Color(0xFFE5E5EF);
  static const Color neutral100 = Color(0xFFF5F5FA);       // 淺色背景
  static const Color neutral50 = Color(0xFFFAFAFD);        // 最淺背景
  static const Color white = Color(0xFFFFFFFF);

  // ============================================
  // 別名（向後兼容）
  // ============================================
  static const Color secondary = primaryLight;
  static const Color background = neutral100;
  static const Color surface = white;

  // ============================================
  // 設計系統擴展色
  // ============================================
  static const Color portBlue = Color(0xFF0066B3);         // 港口藍（同 primary）
  static const Color portBlueLight = Color(0xFF4D94D1);    // 淺港口藍
  static const Color portBlueDark = Color(0xFF004A82);     // 深港口藍
  static const Color forestGreen = Color(0xFF2E7D32);      // 森林綠（同 accent）
  static const Color leafGreen = Color(0xFF66BB6A);        // 嫩葉綠
  static const Color darkGreen = Color(0xFF1B5E20);        // 深綠色
  static const Color warmOrange = Color(0xFFFF8A65);       // 暖橙色
  static const Color surfaceLight = Color(0xFFF8FAFC);     // 極淺表面色
  static const Color backgroundGrey = Color(0xFFFAFAFA);   // 灰色背景
  static const Color accentOrange = Color(0xFFFF8F00);     // 橙色強調
  static const Color accentTeal = Color(0xFF00897B);       // 青色強調
  
  // 額外別名（向後相容）
  static const Color oceanCyan = Color(0xFF00BCD4);        // 海洋青
  static const Color sunYellow = Color(0xFFFFD54F);        // 陽光黃
  static const Color creativePurple = Color(0xFF7B1FA2);   // 創意紫
  static const Color textPrimary = neutral900;             // 主文字色
  
  static const Color text = neutral900;
  static const Color secondaryText = neutral600;
  static const Color divider = neutral300;

  // ============================================
  // 漸層配置
  // ============================================
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF0088CC)],
  );

  static const LinearGradient greenGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accentLight],
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [neutral50, white],
  );

  static const LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [white, neutral50],
  );
}

