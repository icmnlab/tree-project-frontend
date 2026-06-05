/// 維護量測：重測既有樹木時帶入 BLE 現場連線
class MaintenanceTarget {
  final int treeSurveyId;
  final String? projectTreeId;
  final String? systemTreeId;
  final String? speciesName;

  const MaintenanceTarget({
    required this.treeSurveyId,
    this.projectTreeId,
    this.systemTreeId,
    this.speciesName,
  });
}
