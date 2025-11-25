import 'api_service.dart';

class ManagementService {
  Future<Map<String, dynamic>> getManagementActions({
    Map<String, dynamic>? filters,
    int limit = 15,
    int offset = 0,
  }) async {
    Map<String, String> queryParams = {
      'limit': limit.toString(),
      'offset': offset.toString(),
    };

    if (filters != null) {
      if (filters['area_name'] != null) {
        queryParams['area_name'] = filters['area_name']!;
      }
      if (filters['is_done'] != null) {
        queryParams['is_done'] = filters['is_done']!.toString();
      }
      if (filters['category'] != null) {
        queryParams['category'] = filters['category']!;
      }
    }

    final endpoint =
        'tree-management/actions?${Uri.encodeQueryComponent(queryParams.toString())}';
    return ApiService.get(endpoint);
  }

  Future<Map<String, dynamic>> updateActionStatus(
      int actionId, bool isDone) async {
    return ApiService.put(
        'tree-management/actions/$actionId', {'is_done': isDone});
  }

  Future<Map<String, dynamic>> generateNewActions(
      String areaName, String userId) async {
    return ApiService.post('tree-management/actions/generate', {
      'area_name': areaName,
      'user_id': userId,
    });
  }

  Future<Map<String, dynamic>> deleteAction(int actionId) async {
    return ApiService.delete('tree-management/actions/$actionId');
  }
}
