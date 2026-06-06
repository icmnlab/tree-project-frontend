import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/field_log.dart';

/// Debug session 2223ac — 寫入 ingest + logcat（需 adb reverse tcp:7340 tcp:7340）
class DebugSessionLog {
  static const _endpoint =
      'http://127.0.0.1:7340/ingest/39037c80-9d09-4712-af5d-6c6c6384cbc8';
  static const _sessionId = '2223ac';

  // #region agent log
  static void emit(
    String location,
    String message, {
    String? hypothesisId,
    Map<String, dynamic>? data,
    String runId = 'pre-fix',
  }) {
    final payload = <String, dynamic>{
      'sessionId': _sessionId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': location,
      'message': message,
      if (hypothesisId != null) 'hypothesisId': hypothesisId,
      if (data != null) 'data': data,
      'runId': runId,
    };
    FieldLog.ble('[DBG-2223ac][$hypothesisId] $message ${data ?? ''}');
    http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'X-Debug-Session-Id': _sessionId,
          },
          body: jsonEncode(payload),
        )
        .ignore();
  }
  // #endregion
}
