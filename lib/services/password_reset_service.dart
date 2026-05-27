import 'api_service.dart';

/// 待重設密碼（業務管理員以上）
class PasswordResetService {
  Future<List<Map<String, dynamic>>> listPending() async {
    final response = await ApiService.get('pending-password-resets');
    if (response['success'] == true && response['pending'] != null) {
      return List<Map<String, dynamic>>.from(response['pending']);
    }
    throw Exception(response['message'] ?? '無法載入待重設列表');
  }
}
