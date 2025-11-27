import 'api_service.dart';

class ProjectService {
  Future<Map<String, dynamic>> getProjects() async {
    return await ApiService.get('projects');
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
    return await ApiService.post('projects/add', {'name': name, 'area': area});
  }
}
