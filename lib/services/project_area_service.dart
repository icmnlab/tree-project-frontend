import 'api_service.dart';

class ProjectAreaService {
  Future<List<Map<String, dynamic>>> getProjectAreas() async {
    final response = await ApiService.get('project_areas');
    if (response.containsKey('data') && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }
    throw Exception('Failed to load project areas');
  }

  Future<Map<String, dynamic>> addProjectArea(
      Map<String, dynamic> areaData) async {
    return ApiService.post('project_areas', areaData);
  }

  Future<Map<String, dynamic>> deleteProjectArea(int id) async {
    return ApiService.delete('project_areas/$id');
  }

  Future<void> cleanupProjectAreas() async {
    await ApiService.post('project_areas/cleanup', {});
  }
}
