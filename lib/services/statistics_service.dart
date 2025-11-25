import 'api_service.dart';

class StatisticsService {
  Future<Map<String, dynamic>> getStatistics() async {
    return ApiService.get('tree_statistics');
  }

  Future<Map<String, dynamic>> getTreeStatistics() async {
    return ApiService.get('tree_statistics');
  }

  Future<Map<String, dynamic>> getTreesSummary(String projectArea) async {
    return ApiService.get('project_areas/$projectArea/trees_summary');
  }

  Future<Map<String, dynamic>> getCarbonCredits(String projectArea) async {
    return ApiService.get('project_areas/$projectArea/carbon_credits');
  }
}

class ReportService {
  Future<Map<String, dynamic>> getSustainabilityReport() async {
    return ApiService.get('sustainability_report');
  }
}
