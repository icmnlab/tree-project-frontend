import 'api_service.dart';

class AiService {
  Future<Map<String, dynamic>> getChatResponse(String message,
      List<String> projectAreas, String modelPreference, String userId) async {
    return ApiService.post('chat', {
      'message': message,
      'userId': userId,
      'projectAreas': projectAreas,
      'model_preference': modelPreference,
    });
  }

  Future<Map<String, dynamic>> getSpeciesRecommendations(
      String userId, List<String> selectedAreas) async {
    return ApiService.post('ai/species_recommendations',
        {'userId': userId, 'selectedAreas': selectedAreas});
  }

  Future<Map<String, dynamic>> getManagementAdvice(
      String userId, List<String> selectedAreas) async {
    return ApiService.post('ai/management_advice',
        {'userId': userId, 'selectedAreas': selectedAreas});
  }

  Future<Map<String, dynamic>> compareSpecies(List<String> species) async {
    return ApiService.post('ai/species_comparison', {'species': species});
  }

  Future<Map<String, dynamic>> getDirectOpenAIChat(
      String message, String systemPrompt) async {
    return ApiService.post(
        'ai/direct-chat', {'message': message, 'systemPrompt': systemPrompt});
  }
}
