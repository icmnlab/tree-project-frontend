/// pending→tree_survey 轉移結果的純解析邏輯（與 UI 解耦，便於單元測試）。
///
/// 背景：現場新增樹提交後，正式 `tree_survey_id` 來自 transfer 的
/// `id_mapping`。但若該 session 已被前一次（表單內 auto-transfer）轉移過，
/// 第二次 transfer 會走後端「冪等略過」路徑回傳空的 `id_mapping`／
/// `transferred_tree_ids`，導致新樹 id 遺失、無法標記為「本場新增」而再次
/// 出現在維護清單。因此正式 id 應以「表單轉移當下的 id_mapping」為主來源，
/// 第二次冪等 transfer 僅作後備。
library;

/// 從 `id_mapping` 串列取出最後一筆的 `tree_survey_id`（容忍字串或數字）。
int? treeSurveyIdFromIdMapping(dynamic mapping) {
  if (mapping is! List || mapping.isEmpty) return null;
  final last = mapping.last;
  if (last is! Map) return null;
  final id = last['tree_survey_id'];
  if (id is int) return id;
  return int.tryParse(id?.toString() ?? '');
}

/// 從 transfer 回應取出新樹的正式 `tree_survey_id`。
/// 優先用 `id_mapping`，否則退回 `transferred_tree_ids`；冪等空回應回傳 null。
int? treeSurveyIdFromTransfer(Map<String, dynamic>? tr) {
  if (tr == null || tr['success'] != true) return null;
  final fromMapping = treeSurveyIdFromIdMapping(tr['id_mapping']);
  if (fromMapping != null) return fromMapping;
  final ids = tr['transferred_tree_ids'];
  if (ids is List && ids.isNotEmpty) {
    final last = ids.last;
    if (last is int) return last;
    return int.tryParse(last.toString());
  }
  return null;
}
