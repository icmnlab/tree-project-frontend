import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_service.dart';

class MaintenanceLockInfo {
  final int treeId;
  final int userId;
  final String? displayName;
  final DateTime? expiresAt;

  const MaintenanceLockInfo({
    required this.treeId,
    required this.userId,
    this.displayName,
    this.expiresAt,
  });

  factory MaintenanceLockInfo.fromJson(Map<String, dynamic> json) {
    return MaintenanceLockInfo(
      treeId: (json['tree_id'] as num).toInt(),
      userId: (json['user_id'] as num).toInt(),
      displayName: json['display_name']?.toString(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
    );
  }
}

class MaintenanceLockAcquireResult {
  final bool success;
  final bool blocked;
  final String? message;
  final MaintenanceLockInfo? lock;

  const MaintenanceLockAcquireResult({
    required this.success,
    this.blocked = false,
    this.message,
    this.lock,
  });
}

/// 維護重測互斥鎖 API（Server 未部署時優雅降級）
class MaintenanceLockService {
  static const _timeout = Duration(seconds: 12);

  Future<Map<int, MaintenanceLockInfo>> fetchLocks(String projectCode) async {
    try {
      final uri = Uri.parse(
        '${ApiService.baseUrl}/maintenance-locks?project_code=${Uri.encodeComponent(projectCode)}',
      );
      final resp = await http
          .get(uri, headers: ApiService.jsonHeaders())
          .timeout(_timeout);
      if (resp.statusCode == 404) return {};
      if (resp.statusCode != 200) return {};
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (body['success'] != true) return {};
      final locks = body['locks'] as List<dynamic>? ?? [];
      final map = <int, MaintenanceLockInfo>{};
      for (final item in locks) {
        if (item is! Map) continue;
        final info = MaintenanceLockInfo.fromJson(item.cast<String, dynamic>());
        map[info.treeId] = info;
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<MaintenanceLockAcquireResult> acquireLock(
    int treeId, {
    String? sessionHint,
  }) async {
    try {
      final resp = await http
          .post(
            Uri.parse('${ApiService.baseUrl}/maintenance-locks/$treeId'),
            headers: ApiService.jsonHeaders(),
            body: jsonEncode({
              if (sessionHint != null && sessionHint.isNotEmpty)
                'session_hint': sessionHint,
            }),
          )
          .timeout(_timeout);
      if (resp.statusCode == 404) {
        return const MaintenanceLockAcquireResult(success: true);
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode == 409 || body['code'] == 'LOCKED') {
        final lockJson = body['lock'];
        return MaintenanceLockAcquireResult(
          success: false,
          blocked: true,
          message: body['message']?.toString(),
          lock: lockJson is Map
              ? MaintenanceLockInfo.fromJson(lockJson.cast<String, dynamic>())
              : null,
        );
      }
      if (resp.statusCode == 200 && body['success'] == true) {
        final lockJson = body['lock'];
        return MaintenanceLockAcquireResult(
          success: true,
          lock: lockJson is Map
              ? MaintenanceLockInfo.fromJson(lockJson.cast<String, dynamic>())
              : null,
        );
      }
      return MaintenanceLockAcquireResult(
        success: false,
        message: body['message']?.toString() ?? '取得鎖定失敗',
      );
    } catch (_) {
      return const MaintenanceLockAcquireResult(success: true);
    }
  }

  Future<void> releaseLock(int treeId) async {
    try {
      await http
          .delete(
            Uri.parse('${ApiService.baseUrl}/maintenance-locks/$treeId'),
            headers: ApiService.jsonHeaders(),
          )
          .timeout(_timeout);
    } catch (_) {
      // 釋放失敗不阻塞 UI
    }
  }
}
