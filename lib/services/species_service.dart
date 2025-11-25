import 'api_service.dart';

class TreeSpeciesService {
  Future<List<Map<String, dynamic>>> getSpecies() async {
    final response = await ApiService.get('tree_species');
    if (response['success'] == true && response['data'] is List) {
      return List<Map<String, dynamic>>.from(response['data']);
    }
    throw Exception('Failed to load species list');
  }

  Future<Map<String, dynamic>> addSpecies(String name) async {
    final response = await ApiService.post('tree_species', {'name': name});
    return response;
  }
}
