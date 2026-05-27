import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// 輕量 i18n（主要流程）；後續可遷移至 ARB / gen-l10n
class LocaleService extends ChangeNotifier {
  LocaleService._();
  static final LocaleService instance = LocaleService._();

  static const _prefKey = 'app_locale_code';

  Locale _locale = const Locale('zh', 'TW');
  /// system | zh | en
  String _preference = 'system';

  Locale get locale => _locale;
  String get preference => _preference;

  bool get isEnglish => _locale.languageCode == 'en';
  bool get followsSystem => _preference == 'system';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefKey) ?? 'system';
    _preference = code;
    _applyPreference(code);
    notifyListeners();
  }

  void _applyPreference(String code) {
    if (code == 'en') {
      _locale = const Locale('en');
      return;
    }
    if (code == 'zh') {
      _locale = const Locale('zh', 'TW');
      return;
    }
    // system
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    _locale = device.languageCode == 'en'
        ? const Locale('en')
        : const Locale('zh', 'TW');
  }

  Future<void> setPreference(String mode) async {
    if (mode != 'system' && mode != 'zh' && mode != 'en') return;
    _preference = mode;
    _applyPreference(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode);
    notifyListeners();
  }

  /// 繁中 → English → 系統 → 繁中
  Future<void> cycleLanguage() async {
    switch (_preference) {
      case 'zh':
        await setPreference('en');
        break;
      case 'en':
        await setPreference('system');
        break;
      default:
        await setPreference('zh');
    }
  }

  Future<void> setEnglish(bool english) =>
      setPreference(english ? 'en' : 'zh');

  Future<void> toggle() => cycleLanguage();

  String t(String key) {
    final map = isEnglish ? AppStrings.en : AppStrings.zh;
    return map[key] ?? key;
  }

  String tParams(String key, Map<String, String> params) {
    var s = t(key);
    params.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  String get languageMenuLabel {
    switch (_preference) {
      case 'en':
        return t('language_en');
      case 'system':
        return t('language_system');
      default:
        return t('language_zh');
    }
  }
}

extension LocaleX on BuildContext {
  String tr(String key) => LocaleService.instance.t(key);

  String trParams(String key, Map<String, String> params) =>
      LocaleService.instance.tParams(key, params);
}
