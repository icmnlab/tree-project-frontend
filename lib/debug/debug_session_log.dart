import '../utils/field_log.dart';

/// 現場除錯輔助：將關鍵 BLE／GPS 事件轉送到 [FieldLog]（adb logcat 可見）。
///
/// 歷史上曾額外 POST 到本機 ingest 端點供 AI 除錯工具收集；交接前已移除該網路
/// 旁路與其硬編碼位址，僅保留輕量本機日誌，避免在正式版產生多餘連線。
class DebugSessionLog {
  static void emit(
    String location,
    String message, {
    String? hypothesisId,
    Map<String, dynamic>? data,
    String runId = 'pre-fix',
  }) {
    FieldLog.ble('[$location]${hypothesisId != null ? '[$hypothesisId]' : ''} '
        '$message ${data ?? ''}');
  }
}
