import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// 現場量測偵錯日誌。
///
/// - **畫面日誌**：BLE 連線頁透過 [uiSink] 顯示（release 亦有效）。
/// - **Logcat / adb**：Debug 預設開啟；Release 需
///   `--dart-define=ENABLE_FIELD_LOGS=true`。
typedef FieldLogUiSink = void Function(String line);

class FieldLog {
  FieldLog._();

  static FieldLogUiSink? uiSink;

  /// Release 建置是否輸出至系統 log（adb logcat）。
  static bool get logcatEnabled =>
      kDebugMode ||
      const bool.fromEnvironment('ENABLE_FIELD_LOGS', defaultValue: false);

  static void ble(String message, {bool toUi = true}) =>
      _emit('BleLive', message, toUi: toUi);

  static void gps(String message, {bool toUi = false}) =>
      _emit('FieldGPS', message, toUi: toUi);

  static void pending(String message, {bool toUi = false}) =>
      _emit('Pending', message, toUi: toUi);

  static void maintenance(String message, {bool toUi = false}) =>
      _emit('Maintain', message, toUi: toUi);

  static void _emit(String tag, String message, {required bool toUi}) {
    if (logcatEnabled) {
      developer.log(message, name: tag, time: DateTime.now());
    }
    if (toUi && uiSink != null) {
      final hh = DateTime.now().hour.toString().padLeft(2, '0');
      final mm = DateTime.now().minute.toString().padLeft(2, '0');
      final ss = DateTime.now().second.toString().padLeft(2, '0');
      uiSink!('[$hh:$mm:$ss][$tag] $message');
    }
  }
}
