import './api_service.dart';

class UserService {
  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final response = await ApiService.get('users');
    if (response['success'] == true && response['users'] != null) {
      return List<Map<String, dynamic>>.from(response['users']);
    } else {
      throw Exception(response['message'] ?? 'Failed to load users');
    }
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final response = await ApiService.delete('users/$userId');
    return response;
  }

  Future<Map<String, dynamic>> toggleUserStatus(
      String userId, bool newStatus) async {
    final response = await ApiService.put(
      'users/$userId/status',
      {'isActive': newStatus},
    );
    return response;
  }
}
