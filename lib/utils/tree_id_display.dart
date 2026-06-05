/// 樹木 ID 顯示慣例（DB 仍存 ST-/PT- 前綴；UI 依情境取捨）
class TreeIdDisplay {
  /// 專案樹木：現場對齊測距儀／調查員用 **純數字**（PT-123 → 123）
  static String projectTreeDigits(String? id) {
    if (id == null || id.isEmpty) return '—';
    final m = RegExp(r'PT-(\d+)$', caseSensitive: false).firstMatch(id.trim());
    if (m != null) return m.group(1)!;
    final parts = id.split('-');
    if (parts.length > 1 && RegExp(r'^\d+$').hasMatch(parts.last)) {
      return parts.last;
    }
    if (RegExp(r'^\d+$').hasMatch(id.trim())) return id.trim();
    return id;
  }

  /// 系統樹木：管理／除錯用完整前綴（ST-123）
  static String systemTreeFull(String? id) {
    if (id == null || id.isEmpty) return '—';
    return id;
  }

  /// 現場列表一行：大數字專案樹號 + 小字系統號
  static String fieldListLabel({
    required String? projectTreeId,
    String? systemTreeId,
  }) {
    final digits = projectTreeDigits(projectTreeId);
    final sys = systemTreeId?.trim();
    if (sys != null && sys.isNotEmpty && sys != projectTreeId) {
      return '$digits · $sys';
    }
    return digits;
  }
}
