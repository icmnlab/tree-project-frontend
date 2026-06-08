import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/project_scope.dart';

/// 記住使用者最近選過的 [ProjectScope]（專案＋區＋代碼）。
class ProjectScopeStore {
  static const _recentKey = 'project_scope_recent_v2';
  static const _lastKey = 'project_scope_last_v2';
  static const _maxRecent = 5;

  Future<void> remember(ProjectScope scope) async {
    if (!scope.isComplete) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastKey, jsonEncode(scope.toJson()));

    final recent = await loadRecent();
    final next = [
      scope,
      ...recent.where((r) => r != scope),
    ].take(_maxRecent).toList();
    await prefs.setString(
      _recentKey,
      jsonEncode(next.map((e) => e.toJson()).toList()),
    );
  }

  Future<ProjectScope?> loadLast() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final scope = ProjectScope.fromJson(map);
      return scope.isComplete ? scope : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<ProjectScope>> loadRecent() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ProjectScope.fromJson(Map<String, dynamic>.from(e as Map)))
          .where((s) => s.isComplete)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
