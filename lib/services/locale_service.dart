import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// 輕量 i18n（主要流程）；後續可遷移至 ARB / gen-l10n
class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  static const _prefKey = 'app_locale_code';

  Locale _locale = const Locale('zh', 'TW');

  Locale get locale => _locale;

  bool get isEnglish => _locale.languageCode == 'en';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey);
    if (code == 'en') {
      _locale = const Locale('en');
    } else {
      _locale = const Locale('zh', 'TW');
    }
    notifyListeners();
  }

  Future<void> setEnglish(bool english) async {
    _locale = english ? const Locale('en') : const Locale('zh', 'TW');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _locale.languageCode);
    notifyListeners();
  }

  Future<void> toggle() => setEnglish(!isEnglish);

  String t(String key) {
    final map = isEnglish ? AppStrings.en : AppStrings.zh;
    return map[key] ?? key;
  }
}

extension LocaleX on BuildContext {
  String tr(String key) => LocaleService.instance.t(key);
}
