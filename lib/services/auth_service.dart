import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'api_service.dart'; // 引入 ApiService

class AuthService {
  static const String _userKey = 'user_info';
  static const _secureStorage = FlutterSecureStorage();

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

  // 儲存使用者資訊（使用加密存儲）
  static Future<void> saveUserInfo(Map<String, dynamic> userInfo) async {
    await _secureStorage.write(key: _userKey, value: jsonEncode(userInfo));
  }

  // 獲取使用者資訊
  static Future<Map<String, dynamic>?> getUserInfo() async {
    final userString = await _secureStorage.read(key: _userKey);
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
    await _secureStorage.delete(key: _userKey);
    await ApiService.setJwtToken(null);
  }

  // 檢查使用者是否已登入
  static Future<bool> isLoggedIn() async {
    final userInfo = await getUserInfo();
    return userInfo != null;
  }

  // 獲取使用者可訪問的專案列表
  // [Phase B] 優先讀取 projects 陣列，fallback 到 associated_projects 字串
  static Future<List<String>> getAccessibleProjects() async {
    final userInfo = await getUserInfo();
    if (userInfo == null) return [];

    // 優先讀取新的 projects 陣列
    if (userInfo['projects'] != null && userInfo['projects'] is List) {
      final projects = userInfo['projects'] as List;
      return projects
          .map((p) => p is Map ? (p['code']?.toString() ?? '') : p.toString())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    // Fallback: 從 associated_projects 逗號分隔字串讀取
    if (userInfo['associated_projects'] != null) {
      return (userInfo['associated_projects'] as String)
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return [];
  }

  // [Phase B 新增] 獲取使用者可訪問的專案完整資訊
  static Future<List<Map<String, dynamic>>> getAccessibleProjectDetails() async {
    final userInfo = await getUserInfo();
    if (userInfo == null) return [];

    if (userInfo['projects'] != null && userInfo['projects'] is List) {
      return List<Map<String, dynamic>>.from(userInfo['projects']);
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

  // 角色階層定義（數字越大權限越高）
  static const Map<String, int> _roleHierarchy = {
    '系統管理員': 5,
    '業務管理員': 4,
    '專案管理員': 3,
    '調查管理員': 2,
    '一般使用者': 1,
  };

  /// 取得目前使用者角色名稱
  static Future<String> getUserRole() async {
    final userInfo = await getUserInfo();
    return userInfo?['role'] as String? ?? '一般使用者';
  }

  /// 取得角色層級數字
  static int getRoleLevel(String role) {
    return _roleHierarchy[role] ?? 0;
  }

  /// 檢查目前使用者是否 >= 指定最低角色
  static Future<bool> hasMinimumRole(String minimumRole) async {
    final role = await getUserRole();
    return getRoleLevel(role) >= getRoleLevel(minimumRole);
  }

  /// 是否可以新增/編輯樹木資料（調查管理員以上）
  static Future<bool> canEditTrees() async {
    return await hasMinimumRole('調查管理員');
  }

  /// 是否可以刪除樹木資料（專案管理員以上）
  static Future<bool> canDeleteTrees() async {
    return await hasMinimumRole('專案管理員');
  }

  /// 是否可以管理使用者（業務管理員以上）
  static Future<bool> canManageUsers() async {
    return await hasMinimumRole('業務管理員');
  }
}
