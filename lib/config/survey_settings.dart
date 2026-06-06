import 'package:shared_preferences/shared_preferences.dart';

/// 現場調查偏好（手冊合規 vs 研究模式）。
class SurveySettings {
  SurveySettings._();
  static final SurveySettings instance = SurveySettings._();

  static const _researchModeKey = 'survey_research_mode_enabled';

  bool _loaded = false;
  bool _researchModeEnabled = false;

  bool get isLoaded => _loaded;
  bool get researchModeEnabled => _researchModeEnabled;

  /// 碳匯手冊合規：DBH 僅人工量測。
  bool get handbookCompliantMode => !_researchModeEnabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _researchModeEnabled = prefs.getBool(_researchModeKey) ?? false;
    _loaded = true;
  }

  Future<void> setResearchModeEnabled(bool enabled) async {
    _researchModeEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_researchModeKey, enabled);
  }
}
