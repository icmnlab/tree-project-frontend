import 'api_service.dart';

class AuditLogService {
  Future<Map<String, dynamic>> fetchLogs({
    int limit = 50,
    int offset = 0,
    String? action,
  }) async {
    final q = <String>['limit=$limit', 'offset=$offset'];
    if (action != null && action.isNotEmpty) {
      q.add('action=${Uri.encodeComponent(action)}');
    }
    return ApiService.get('admin/audit-logs?${q.join('&')}');
  }
}
