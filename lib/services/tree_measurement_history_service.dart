import 'api_service.dart';

/// 單棵樹歷次量測（後端 tree_survey_measurements）
class TreeMeasurementHistoryService {
  Future<List<Map<String, dynamic>>> fetchByTreeId(
    int treeId, {
    int limit = 30,
  }) async {
    final capped = limit.clamp(1, 200);
    final res = await ApiService.get(
      'tree_survey/by_id/$treeId/measurements?limit=$capped',
    );
    if (res['success'] != true) return [];
    final data = res['data'];
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
