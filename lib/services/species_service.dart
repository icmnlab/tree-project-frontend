import 'api_service.dart';

class TreeSpeciesService {
  Future<List<Map<String, dynamic>>> getSpecies() async {
    final response = await ApiService.get('tree_species');
    if (response['success'] == true && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }
    throw Exception('Failed to load species list');
  }

  /// 取得增強版樹種列表（含同義詞資訊）
  Future<List<Map<String, dynamic>>> getEnhancedSpecies() async {
    try {
      final response = await ApiService.get('tree_species/enhanced');
      if (response['success'] == true && response['data'] is List) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
    } catch (_) {
      // Fallback 到基本列表
    }
    return getSpecies();
  }

  /// 搜尋樹種（含同義詞匹配，server-side）
  Future<List<Map<String, dynamic>>> searchSpecies(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final response = await ApiService.get('tree_species/search?q=${Uri.encodeComponent(query)}');
      if (response['success'] == true && response['data'] is List) {
        return List<Map<String, dynamic>>.from(response['data']);
      }
    } catch (_) {
      // 如果 server 搜尋失敗，return 空讓本地搜尋 fallback
    }
    return [];
  }

  Future<Map<String, dynamic>> addSpecies(String name, {String? scientificName}) async {
    final body = <String, dynamic>{'name': name};
    if (scientificName != null && scientificName.isNotEmpty) {
      body['scientific_name'] = scientificName;
    }
    final response = await ApiService.post('tree_species', body);
    return response;
  }
}
