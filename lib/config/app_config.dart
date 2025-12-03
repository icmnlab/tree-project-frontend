import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io'; // Import for exit()

enum Environment { prod, staging }

class AppConfig {
  late Environment environment;
  late String baseUrl;

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
