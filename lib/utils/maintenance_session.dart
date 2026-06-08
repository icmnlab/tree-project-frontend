/// 維護場次「待辦」判定的純邏輯（與 UI 解耦，便於單元測試）。
///
/// 規則（維護場次清單／地圖只顯示「尚待重測」的樹）：
///   - 沒有有效 id 的列不算待辦。
///   - 本場次「已完成重測」的樹要從待辦移除（completedThisSession）。
///   - 本場次「新增入庫」的樹不是待重測對象，要從待辦移除（addedThisSession）。
///
/// 這支檔案不依賴 Flutter，純 Dart，方便用 `flutter test` 直接驗證。
library;

/// 從樹木資料列取出整數 id（容忍 `id`/`ID`、字串或數字）。
int? maintenanceTreeIdOf(Map<String, dynamic> tree) {
  final v = tree['id'] ?? tree['ID'];
  if (v is int) return v;
  return int.tryParse(v?.toString() ?? '');
}

/// 該樹是否仍為「本場次待辦」。
bool isMaintenanceSessionPending({
  required int? treeId,
  required Set<int> completedThisSession,
  required Set<int> addedThisSession,
}) {
  if (treeId == null) return false;
  if (completedThisSession.contains(treeId)) return false;
  if (addedThisSession.contains(treeId)) return false;
  return true;
}
