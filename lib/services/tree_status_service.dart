import 'api_service.dart';

/// 樹況選項（對應後端 tree_status_options）。
/// lifecycle：active=活立木；dead=枯死/枯立木；fallen=倒塌；removed=移除。
class TreeStatusOption {
  final int? id;
  final String name;
  final String lifecycle;
  final bool isBuiltin;

  const TreeStatusOption({
    this.id,
    required this.name,
    required this.lifecycle,
    this.isBuiltin = false,
  });

  /// 是否為「淘汰」狀況（非活立木）。
  bool get isRetire => lifecycle != 'active';

  factory TreeStatusOption.fromJson(Map<String, dynamic> j) => TreeStatusOption(
        id: j['id'] is int ? j['id'] as int : int.tryParse('${j['id']}'),
        name: (j['name'] ?? '').toString(),
        lifecycle: (j['lifecycle'] ?? 'active').toString(),
        isBuiltin: j['is_builtin'] == true,
      );
}

/// 樹況選單服務：載入內建+自訂（可共享）狀況，並支援新增自訂狀況。
/// API 不可用時提供內建後備清單，確保離線/異常仍可作業。
class TreeStatusService {
  static List<TreeStatusOption>? _cache;

  static const List<TreeStatusOption> fallback = [
    TreeStatusOption(name: '正常', lifecycle: 'active', isBuiltin: true),
    TreeStatusOption(name: '傾斜', lifecycle: 'active', isBuiltin: true),
    TreeStatusOption(name: '病蟲害', lifecycle: 'active', isBuiltin: true),
    TreeStatusOption(name: '枯萎', lifecycle: 'active', isBuiltin: true),
    TreeStatusOption(name: '枯立木', lifecycle: 'dead', isBuiltin: true),
    TreeStatusOption(name: '枯死', lifecycle: 'dead', isBuiltin: true),
    TreeStatusOption(name: '倒塌', lifecycle: 'fallen', isBuiltin: true),
    TreeStatusOption(name: '已移除', lifecycle: 'removed', isBuiltin: true),
  ];

  static Future<List<TreeStatusOption>> fetch({bool force = false}) async {
    if (_cache != null && !force) return _cache!;
    try {
      final res = await ApiService.get('tree-statuses');
      if (res['success'] == true && res['data'] is List) {
        final list = (res['data'] as List)
            .whereType<Map>()
            .map((e) => TreeStatusOption.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (list.isNotEmpty) {
          _cache = list;
          return list;
        }
      }
    } catch (_) {
      // 落回後備清單
    }
    return fallback;
  }

  /// 新增自訂狀況（多人共享）。成功回傳該選項並使快取失效。
  static Future<TreeStatusOption?> create(String name, {String? lifecycle}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final body = <String, dynamic>{'name': trimmed};
    if (lifecycle != null) body['lifecycle'] = lifecycle;
    final res = await ApiService.post('tree-statuses', body);
    if (res['success'] == true && res['data'] is Map) {
      _cache = null; // 失效快取，下次重抓含新狀況
      return TreeStatusOption.fromJson(
          Map<String, dynamic>.from(res['data'] as Map));
    }
    return null;
  }

  /// 由狀況名稱取得 lifecycle（先查目錄，查無則以本地關鍵字推導，與後端一致）。
  static String lifecycleOf(String name, List<TreeStatusOption> opts) {
    for (final o in opts) {
      if (o.name == name) return o.lifecycle;
    }
    return localLifecycle(name);
  }

  static bool isRetireName(String name, List<TreeStatusOption> opts) =>
      lifecycleOf(name, opts) != 'active';

  /// 本地後備推導（與 backend utils/treeLifecycle.js 同步）。
  static String localLifecycle(String name) {
    final s = name.trim();
    if (s.contains('移除') || s.contains('砍除') || s.contains('砍伐')) {
      return 'removed';
    }
    if (s.contains('枯死') || s.contains('死亡') || s.contains('枯立')) {
      return 'dead';
    }
    if (s.contains('倒塌') || s.contains('倒伏')) return 'fallen';
    return 'active';
  }
}
