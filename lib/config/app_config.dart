import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io'; // Import for exit()

enum Environment { prod, staging }

class AppConfig {
  late Environment environment;
  late String baseUrl;
  late String mlServiceUrl;

  /// 自架 ML Service 的 URL（null = 使用 Render）
  String? _selfHostedMlUrl;

  /// ML Service API Key (用於自架時的認證)
  String? _mlApiKey;

  /// 取得 ML API Key
  String? get mlApiKey => _mlApiKey;

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
        prefs.getString('environment') ?? Environment.prod.toString();
    Environment initialEnv = Environment.values.firstWhere(
      (e) => e.toString() == envString,
      orElse: () => Environment.prod,
    );

    // 載入自架 ML Service URL
    _selfHostedMlUrl = prefs.getString('self_hosted_ml_url');
    _mlApiKey = prefs.getString('ml_api_key');

    _setEnvironment(initialEnv);
  }

  // Private method to set URLs
  void _setEnvironment(Environment env) {
    environment = env;
    switch (env) {
      case Environment.staging:
        baseUrl = 'https://tree-app-backend-staging.onrender.com/api';
        break;
      case Environment.prod:
        baseUrl = 'https://tree-app-backend-prod.onrender.com/api';
        break;
    }

    // ML Service URL: 優先使用自架，否則用 Render
    if (_selfHostedMlUrl != null && _selfHostedMlUrl!.isNotEmpty) {
      mlServiceUrl = _selfHostedMlUrl!;
    } else {
      mlServiceUrl = 'https://tree-app-ml-service.onrender.com/api/v1';
    }
  }

  /// 設定自架 ML Service URL
  /// 傳入 ngrok URL (例如 https://xxxx.ngrok-free.app)
  /// 會自動加上 /api/v1 後綴
  Future<void> setSelfHostedMlUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    if (url != null && url.isNotEmpty) {
      // 確保 URL 格式正確
      String cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), ''); // 去除尾部 /
      if (!cleanUrl.endsWith('/api/v1')) {
        cleanUrl = '$cleanUrl/api/v1';
      }
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
    return 'Render Cloud';
  }

  // Toggle environment and save to shared_preferences
  Future<void> toggleEnvironment(BuildContext context) async {
    final newEnv = (environment == Environment.prod)
        ? Environment.staging
        : Environment.prod;
    _setEnvironment(newEnv);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('environment', newEnv.toString());

    // Show a dialog to inform the user and prompt for a restart
    await showDialog(
      context: context,
      barrierDismissible: false, // User must interact with the dialog
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('環境已切換'),
          content: Text(
              'API 環境已切換至 ${newEnv == Environment.prod ? "正式版" : "測試版"}。\n\n為了讓所有設定生效，應用程式需要重新啟動。'),
          actions: <Widget>[
            TextButton(
              child: const Text('立即重啟'),
              onPressed: () {
                // This is a simple way to "restart". A more graceful way might involve more complex state management.
                exit(0);
              },
            ),
          ],
        );
      },
    );
  }
}
