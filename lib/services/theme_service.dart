import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主題切換服務 - 支援亮色/暗色模式
class ThemeService extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';
  static final ThemeService _instance = ThemeService._();
  factory ThemeService() => _instance;
  ThemeService._();

  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (saved == 'system') {
      _themeMode = ThemeMode.system;
    } else {
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }

  Future<void> toggleDarkMode() async {
    await setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }
}
