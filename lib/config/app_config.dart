import 'package:shared_preferences/shared_preferences.dart';

// 後端固定為自架伺服器（Tailscale）。保留 enum 是為了讓舊 SharedPreferences
// 的 'environment' 字串不會炸掉，並為未來再次新增環境留好擴充點。
enum Environment { selfHosted }

class AppConfig {
  late Environment environment;
  late String baseUrl;
  late String mlServiceUrl;

  /// ML Service URL. Normally synced from the backend login/config response;
  /// can also be supplied at build time for local test APKs.
  String? _configuredMlServiceUrl;

  static const String defaultMlServiceUrl = String.fromEnvironment(
    'TREE_ML_SERVICE_URL',
    defaultValue: '',
  );

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

    _configuredMlServiceUrl = prefs.getString('ml_service_url') ??
        prefs.getString('self_hosted_ml_url');
    await prefs.remove('ml_api_key');

    _setEnvironment(initialEnv);
  }

  // Private method to set URLs
  void _setEnvironment(Environment env) {
    environment = env;
    // 目前唯一環境：自架後端（Tailscale）
    baseUrl = 'https://richardhualienserver.tail124a1b.ts.net/api';
    final configuredUrl =
        (_configuredMlServiceUrl != null && _configuredMlServiceUrl!.isNotEmpty)
            ? _configuredMlServiceUrl!
            : defaultMlServiceUrl;
    mlServiceUrl =
        configuredUrl.isNotEmpty ? _normalizeMlServiceUrl(configuredUrl) : '';
  }

  bool get hasMlServiceUrl => mlServiceUrl.isNotEmpty;

  /// Backward-compatible wrapper for existing login/config code.
  Future<void> setSelfHostedMlUrl(String? url) async {
    return setMlServiceUrl(url);
  }

  /// 設定 ML Service URL，會自動加上 /api/v1 後綴。
  Future<void> setMlServiceUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      final cleanUrl = _normalizeMlServiceUrl(url);
      _configuredMlServiceUrl = cleanUrl;
      await prefs.setString('ml_service_url', cleanUrl);
      await prefs.remove('self_hosted_ml_url');
    } else {
      _configuredMlServiceUrl = null;
      await prefs.remove('ml_service_url');
      await prefs.remove('self_hosted_ml_url');
    }
    // 重新套用設定
    _setEnvironment(environment);
  }

  /// 取得目前 ML Service 來源描述
  String get mlServiceSource =>
      mlServiceUrl.isNotEmpty ? mlServiceUrl : 'ML Service URL 未設定';

  static String _normalizeMlServiceUrl(String url) {
    String cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    cleanUrl = cleanUrl.replaceAll(RegExp(r'/api(/v\d+)?$'), '');
    return '$cleanUrl/api/v1';
  }
}
