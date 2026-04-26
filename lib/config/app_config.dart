import 'package:shared_preferences/shared_preferences.dart';

// 後端固定為自架伺服器（Tailscale）。歷史上曾有 Render prod/staging 環境，
// 已於 2026-04 退役，因此 enum 只剩單一值；保留 enum 是為了讓舊 SharedPreferences
// 的 'environment' 字串不會炸掉，並為未來再次新增環境留好擴充點。
enum Environment { selfHosted }

class AppConfig {
  late Environment environment;
  late String baseUrl;
  late String mlServiceUrl;

  /// 自架 ML Service 的 URL（null/空 = 未設定，前端會顯示警告）
  String? _selfHostedMlUrl;

  /// ML Service API Key (用於自架時的認證)
  String? _mlApiKey;

    /// 是否使用自架 ML Service
    bool get useSelfHostedMl => _selfHostedMlUrl != null && _selfHostedMlUrl!.isNotEmpty;

    static final AppConfig _instance = AppConfig._internal();

  factory AppConfig() {
    return _instance;
  }

  AppConfig._internal();

  // Initialize with async loading from shared_preferences
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final String envString =
        prefs.getString('environment') ?? Environment.selfHosted.toString();
    Environment initialEnv = Environment.values.firstWhere(
      (e) => e.toString() == envString,
      orElse: () => Environment.selfHosted,
    );

    // 載入自架 ML Service URL
    _selfHostedMlUrl = prefs.getString('self_hosted_ml_url');
    _mlApiKey = prefs.getString('ml_api_key');

    _setEnvironment(initialEnv);
  }

  // Private method to set URLs
  void _setEnvironment(Environment env) {
    environment = env;
    // 目前唯一環境：自架後端（Tailscale）
    baseUrl = 'https://richardhualienserver.tail124a1b.ts.net/api';

    // ML Service URL：優先使用使用者設定的 ngrok URL；未設定則保留空字串，
    // 由 useSelfHostedMl=false 的呼叫端跳出「請先在管理頁設定 ML Service」提示。
    if (_selfHostedMlUrl != null && _selfHostedMlUrl!.isNotEmpty) {
      mlServiceUrl = _selfHostedMlUrl!;
    } else {
      mlServiceUrl = '';
    }
  }

  /// 取得 ML API Key
  String? get mlApiKey => _mlApiKey;

  /// 設定自架 ML Service URL
  /// 傳入 ngrok URL (例如 https://xxxx.ngrok-free.app)
  /// 會自動加上 /api/v1 後綴
  Future<void> setSelfHostedMlUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      // 確保 URL 格式正確
      String cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), ''); // 去除尾部 /
      // 去除使用者可能多輸入的 API 路徑，避免重複拼接
      cleanUrl = cleanUrl.replaceAll(RegExp(r'/api(/v\d+)?$'), '');
      cleanUrl = '$cleanUrl/api/v1';
      _selfHostedMlUrl = cleanUrl;
      await prefs.setString('self_hosted_ml_url', cleanUrl);
    } else {
      _selfHostedMlUrl = null;
      await prefs.remove('self_hosted_ml_url');
    }
    // 重新套用設定
    _setEnvironment(environment);
  }

  /// 設定 ML API Key（用於自架 ML Service 的認證）
  Future<void> setMlApiKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    if (key != null && key.isNotEmpty) {
      _mlApiKey = key.trim();
      await prefs.setString('ml_api_key', _mlApiKey!);
    } else {
      _mlApiKey = null;
      await prefs.remove('ml_api_key');
    }
  }

  /// 取得目前 ML Service 來源描述
  String get mlServiceSource {
    if (useSelfHostedMl) {
      return '自架 (${_selfHostedMlUrl!})';
    }
    return '未設定（請先在管理頁設定 ML Service URL）';
  }
}
