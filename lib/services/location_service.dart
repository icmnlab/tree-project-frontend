import 'api_service.dart';

class LocationService {
  Future<Map<String, dynamic>> validateLocation({
    required String area,
    required double latitude,
    required double longitude,
  }) async {
    return ApiService.post('location/validate', {
      'area': area,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  Future<Map<String, dynamic>> suggestArea({
    required double latitude,
    required double longitude,
  }) async {
    return ApiService.post('location/suggest_area', {
      'latitude': latitude,
      'longitude': longitude,
    });
  }
}
