import 'api_service.dart';

class TreeMeasurementHistoryResult {
  final List<Map<String, dynamic>> rows;
  final int total;
  final int offset;
  final int limit;

  const TreeMeasurementHistoryResult({
    required this.rows,
    required this.total,
    required this.offset,
    required this.limit,
  });

  bool get hasMore => offset + rows.length < total;
}

/// 單棵樹歷次量測（後端 tree_survey_measurements）
class TreeMeasurementHistoryService {
  Future<TreeMeasurementHistoryResult> fetchByTreeId(
    int treeId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final capped = limit.clamp(1, 200);
    final res = await ApiService.get(
      'tree_survey/by_id/$treeId/measurements'
      '?limit=$capped&offset=$offset',
    );
    if (res['success'] != true) {
      return TreeMeasurementHistoryResult(
        rows: const [],
        total: 0,
        offset: offset,
        limit: capped,
      );
    }
    final data = res['data'];
    final rows = data is List
        ? data.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    final total = res['total'] is int
        ? res['total'] as int
        : int.tryParse(res['total']?.toString() ?? '') ?? rows.length;
    return TreeMeasurementHistoryResult(
      rows: rows,
      total: total,
      offset: offset,
      limit: capped,
    );
  }
}
