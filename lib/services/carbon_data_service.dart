import 'api_service.dart';

class CarbonDataService {
  Future<Map<String, dynamic>> getSpeciesList() async {
    return ApiService.get('tree-carbon-data/species-list');
  }
}
