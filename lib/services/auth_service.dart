import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'api_service.dart'; // 引入 ApiService

class AuthService {
  static const String _userKey = 'user_info';

  // 新增：登入函式
  static Future<Map<String, dynamic>> login(
      String account, String password, String loginType) async {
    final response = await ApiService.post('login', {
      'account': account,
      'password': password,
      'loginType': loginType,
    });
    return response;
  }

  // 儲存使用者資訊
  static Future<void> saveUserInfo(Map<String, dynamic> userInfo) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userInfo));
  }

  // 獲取使用者資訊
  static Future<Map<String, dynamic>?> getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userString = prefs.getString(_userKey);
    if (userString != null) {
      return jsonDecode(userString) as Map<String, dynamic>;
    }
    return null;
  }

  // 清除使用者資訊（登出時使用）
  static Future<void> logout(BuildContext context) async {
    await clearSession();
    // 導航到登入頁面，並清除所有路由歷史
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  // 清除 session 資料 (不含導航)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await ApiService.setJwtToken(null);
  }

  // 檢查使用者是否已登入
  static Future<bool> isLoggedIn() async {
    final userInfo = await getUserInfo();
    return userInfo != null;
  }

  // 獲取使用者可訪問的專案列表
  static Future<List<String>> getAccessibleProjects() async {
    final userInfo = await getUserInfo();
    if (userInfo != null && userInfo['associated_projects'] != null) {
      return (userInfo['associated_projects'] as String)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  // 檢查使用者是否為管理員
  static Future<bool> isAdmin() async {
    final userInfo = await getUserInfo();
    return userInfo != null && userInfo['role'] == '系統管理員';
  }

  // 檢查使用者是否有權限訪問特定專案
  static Future<bool> canAccessProject(String projectCode) async {
    final isUserAdmin = await isAdmin();
    if (isUserAdmin) return true;

    final projects = await getAccessibleProjects();
    return projects.contains(projectCode);
  }
}
