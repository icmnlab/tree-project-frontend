import 'api_service.dart';

class AiService {
  /// 發送聊天訊息
  /// [sessionId] 可選，用於追蹤同一對話會話
  Future<Map<String, dynamic>> getChatResponse(
    String message,
    List<String> projectAreas,
    String modelPreference,
    String userId, {
    String? sessionId,
  }) async {
    return ApiService.post('chat', {
      'message': message,
      'userId': userId,
      'projectAreas': projectAreas,
      'model_preference': modelPreference,
      if (sessionId != null) 'sessionId': sessionId,
    });
  }

  /// 發送 Agent 對話 (具備工具調用能力)
  Future<Map<String, dynamic>> getAgentResponse(
    String message,
    String userId, {
    String? sessionId,
    String? model,
  }) async {
    return ApiService.post('agent/chat', {
      'message': message,
      if (sessionId != null) 'sessionId': sessionId,
      if (model != null) 'model': model,
    });
  }

  /// 取得 Agent 狀態
  Future<Map<String, dynamic>> getAgentStatus() async {
    return ApiService.get('agent/status');
  }

  /// 依後端偵測結果取得可用 LLM 模型清單
  Future<Map<String, dynamic>> getLlmOptions({bool refresh = false}) async {
    final q = refresh ? '?refresh=1' : '';
    return ApiService.get('ai/llm-options$q');
  }

  // [Cleanup] 已移除 getSpeciesRecommendations / getManagementAdvice / compareSpecies：
  //   對應後端 ai/species_recommendations、ai/management_advice、ai/species_comparison
  //   路由已隨舊 AI 功能移除，前端亦無任何呼叫者（呼叫只會得到 404）。

  Future<Map<String, dynamic>> getDirectOpenAIChat(
      String message, String systemPrompt) async {
    return ApiService.post(
        'ai/direct-chat', {'message': message, 'systemPrompt': systemPrompt});
  }

  /// 列出當前登入帳號（依 JWT 判定）的所有對話 session 後設資料
  Future<Map<String, dynamic>> listChatSessions() async {
    return ApiService.get('chat/sessions');
  }

  /// 取得單一 session 的完整對話內容
  Future<Map<String, dynamic>> getChatSession(String sessionId) async {
    return ApiService.get('chat/sessions/$sessionId');
  }

  /// 刪除單一對話 session
  Future<Map<String, dynamic>> deleteChatSession(String sessionId) async {
    return ApiService.delete('chat/sessions/$sessionId');
  }
}
