/// 維護量測：重測既有樹木時帶入 BLE 現場連線
class MaintenanceTarget {
  final int treeSurveyId;
  final String? projectTreeId;
  final String? systemTreeId;
  final String? speciesName;
  final String? speciesId;
  final double? treeLatitude;
  final double? treeLongitude;

  const MaintenanceTarget({
    required this.treeSurveyId,
    this.projectTreeId,
    this.systemTreeId,
    this.speciesName,
    this.speciesId,
    this.treeLatitude,
    this.treeLongitude,
  });
}

/// BLE 維護場次結束後回傳給 [MaintenanceSurveyPage]
class MaintenanceSessionResult {
  final bool success;
  final int? treeSurveyId;
  final String? projectTreeId;

  /// true = 本場次「新增樹木」；false = 重測既有樹
  final bool isNewTree;

  const MaintenanceSessionResult({
    required this.success,
    this.treeSurveyId,
    this.projectTreeId,
    this.isNewTree = false,
  });
}
