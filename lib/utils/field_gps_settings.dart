import 'package:shared_preferences/shared_preferences.dart';

/// 現場 GPS 測試選項（系統設定內開關）
class FieldGpsSettings {
  static const String _relaxedKey = 'field_gps_relaxed_accuracy';

  /// 測試模式：不強制 ±5m，只要有有效座標即可
  static Future<bool> isRelaxedAccuracy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_relaxedKey) ?? false;
  }

  static Future<void> setRelaxedAccuracy(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_relaxedKey, enabled);
  }
}
