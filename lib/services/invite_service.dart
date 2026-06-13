import 'api_service.dart';

/// 邀請碼管理（業務管理員以上）
class InviteService {
  Future<List<Map<String, dynamic>>> listInvites() async {
    final response = await ApiService.get('invites');
    if (response['success'] == true && response['invites'] != null) {
      return List<Map<String, dynamic>>.from(response['invites']);
    }
    throw Exception(response['message'] ?? '無法載入邀請碼');
  }

  Future<Map<String, dynamic>> createInvite({
    required String role,
    int maxUses = 1,
    int expiresInDays = 7,
    List<String>? projectCodes,
    List<String>? projectLocations,
    bool requiresApproval = false,
  }) async {
    final response = await ApiService.post('invites', {
      'role': role,
      'max_uses': maxUses,
      'expires_in_days': expiresInDays,
      if (projectCodes != null && projectCodes.isNotEmpty)
        'project_codes': projectCodes,
      if (projectLocations != null && projectLocations.isNotEmpty)
        'project_locations': projectLocations,
      'requires_approval': requiresApproval,
    });
    if (response['success'] == true) {
      return Map<String, dynamic>.from(response['invite'] as Map);
    }
    throw Exception(response['message'] ?? '建立邀請碼失敗');
  }

  Future<void> deactivateInvite(int inviteId) async {
    final response =
        await ApiService.patch('invites/$inviteId/deactivate', {});
    if (response['success'] != true) {
      throw Exception(response['message'] ?? '停用失敗');
    }
  }

  /// 刪除邀請碼紀錄（僅移除這筆紀錄，不影響已用此碼註冊的帳號）。
  Future<void> deleteInvite(int inviteId) async {
    final response = await ApiService.delete('invites/$inviteId');
    if (response['success'] != true) {
      throw Exception(response['message'] ?? '刪除失敗');
    }
  }
}
