import 'api_service.dart';

class ProjectService {
  // Simple in-memory cache
  Map<String, dynamic>? _cachedProjectsResponse;
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  Future<Map<String, dynamic>> getProjects({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedProjectsResponse != null &&
        _lastFetchTime != null &&
        DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
      return _cachedProjectsResponse!;
    }

    final response = await ApiService.get('projects');
    if (response['success'] == true) {
      _cachedProjectsResponse = response;
      _lastFetchTime = DateTime.now();
    }
    return response;
  }

  Future<Map<String, dynamic>> getProjectByName(String name) async {
    final String encodedName = Uri.encodeComponent(name);
    return await ApiService.get('projects/by_name/$encodedName');
  }

  Future<Map<String, dynamic>> getProjectByCode(String code) async {
    final String encodedCode = Uri.encodeComponent(code);
    return await ApiService.get('projects/by_code/$encodedCode');
  }

  Future<Map<String, dynamic>> getProjectsByArea(String area) async {
    final String encodedArea = Uri.encodeComponent(area);
    return await ApiService.get('projects/by_area/$encodedArea');
  }

  Future<Map<String, dynamic>> addProject(String name, String area) async {
    // Clear cache when adding a new project
    _cachedProjectsResponse = null;
    return await ApiService.post('projects/add', {'name': name, 'area': area});
  }

  Future<Map<String, dynamic>> deleteProject(String code) async {
    // Clear cache when deleting a project
    _cachedProjectsResponse = null;
    return await ApiService.delete('projects/$code');
  }
}
