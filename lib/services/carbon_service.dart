import 'api_service.dart';

class CarbonService {
  Future<Map<String, dynamic>> getCarbonCreditsForArea(String area) async {
    final encodedArea = Uri.encodeComponent(area);
    return ApiService.get('project_areas/$encodedArea/carbon_credits');
  }

  Future<Map<String, dynamic>> getCarbonEducation(String topic) async {
    final encodedTopic = Uri.encodeComponent(topic);
    return ApiService.get('carbon-education/$encodedTopic');
  }

  Future<Map<String, dynamic>> calculateCarbonFootprint({
    required String activityType,
    required double amount,
    required String unit,
  }) async {
    return ApiService.post('carbon-footprint/calculator', {
      'activityType': activityType,
      'amount': amount,
      'unit': unit,
    });
  }

  Future<List<dynamic>> getSpeciesList() async {
    final response = await ApiService.get('tree-carbon-data/species-list');
    if (response['success'] == true && response['data'] is List) {
      return response['data'];
    }
    throw Exception('Failed to load species list');
  }

  Future<Map<String, dynamic>> getSpeciesDetails(List<int> speciesIds) async {
    return ApiService.post(
        'species-comparison/details', {'species_ids': speciesIds});
  }
}
