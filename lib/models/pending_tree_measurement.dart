import 'dart:math' as math;

/// 待測量樹木數據模型
///
/// 用於存儲 VLGEO2 匯入但尚未完成 DBH 測量的樹木資料
/// 支援兩階段測量流程：
/// 1. 第一階段：VLGEO2 測量員使用設備測量樹木位置
/// 2. 第二階段：DBH 測量員使用 AR 功能測量胸徑
class PendingTreeMeasurement {
  final int? id; // 資料庫 ID
  final String? sessionId; // 測量批次 ID
  final String? originalRecordId; // VLGEO2 原始記錄 ID

  // 專案資訊
  final String? projectArea;
  final String? projectCode;
  final String? projectName;

  // 樹木基本資料 (來自 VLGEO2)
  final String? speciesName; // 樹種名稱 (可能待確認)
  final double treeHeight; // 樹高 (公尺)
  final double? dbhCm; // 胸徑 (待測量)

  // 樹木位置 (計算得出)
  final double treeLatitude; // 樹木緯度
  final double treeLongitude; // 樹木經度

  // 測站位置 (從 VLGEO2 數據反推)
  final double stationLatitude; // 測站緯度
  final double stationLongitude; // 測站經度

  // VLGEO2 測量數據 (用於反推計算)
  final double horizontalDistance; // 水平距離 (m)
  final double slopeDistance; // 斜距 (m)
  final double azimuth; // 方位角 (度)
  final double pitch; // 俯仰角 (度)
  final double? altitude; // 海拔 (m)

  // 狀態資訊
  final MeasurementStatus status;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String? assignedTo; // 指派給哪位測量員
  final int? priority; // 優先級 (1-5)

  final String? measurementType; // 測量類型 (1P, 3P, 3D, DME)

  // DBH 測量結果 (第二階段填入)
  final double? measuredDbhCm; // 測量的 DBH
  final double? measurementConfidence; // 測量信心度
  final String? measurementMethod; // 測量方法
  final String? measurementNotes; // 測量備註

  const PendingTreeMeasurement({
    this.id,
    this.sessionId,
    this.originalRecordId,
    this.projectArea,
    this.projectCode,
    this.projectName,
    this.speciesName,
    required this.treeHeight,
    this.dbhCm,
    required this.treeLatitude,
    required this.treeLongitude,
    required this.stationLatitude,
    required this.stationLongitude,
    required this.horizontalDistance,
    required this.slopeDistance,
    required this.azimuth,
    required this.pitch,
    this.altitude,
    required this.status,
    required this.createdAt,
    this.completedAt,
    this.assignedTo,
    this.priority,
    this.measurementType,
    this.measuredDbhCm,
    this.measurementConfidence,
    this.measurementMethod,
    this.measurementNotes,
  });

  /// 計算目前使用者到測站的距離 (公尺)
  double distanceToStation(double userLat, double userLon) {
    return _haversineDistance(
        userLat, userLon, stationLatitude, stationLongitude);
  }

  /// 測站到樹木的方位角 (度)
  /// 直接使用儀器 AZ 值，因為這是最可靠的（GPS 反算有精度損失）
  double bearingToTree() {
    return azimuth;
  }

  /// Haversine 公式計算兩點間距離
  static double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const double R = 6371000; // 地球半徑 (公尺)

    double dLat = _toRadians(lat2 - lat1);
    double dLon = _toRadians(lon2 - lon1);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
  }

  /// 計算從點 A 到點 B 的方位角
  static double _toRadians(double degrees) => degrees * math.pi / 180;
  static double _toDegrees(double radians) => radians * 180 / math.pi;

  /// 從 VLGEO2 數據正向推算樹木位置
  ///
  /// [修正 2026-02] VLGEO2 的 GPS 座標是操作員位置，不是樹木位置。
  /// 公式：樹木位置 = 操作員GPS + offset(HD, AZ)
  static ({double lat, double lon}) calculateTreePositionFromStation({
    required double stationLat,
    required double stationLon,
    required double horizontalDistance,
    required double azimuth,
  }) {
    const double R = 6371000;

    double azimuthRad = _toRadians(azimuth);
    double stationLatRad = _toRadians(stationLat);
    double stationLonRad = _toRadians(stationLon);
    double angularDistance = horizontalDistance / R;

    double treeLatRad = math.asin(
        math.sin(stationLatRad) * math.cos(angularDistance) +
            math.cos(stationLatRad) *
                math.sin(angularDistance) *
                math.cos(azimuthRad));

    double treeLonRad = stationLonRad +
        math.atan2(
            math.sin(azimuthRad) *
                math.sin(angularDistance) *
                math.cos(stationLatRad),
            math.cos(angularDistance) -
                math.sin(stationLatRad) * math.sin(treeLatRad));

    return (lat: _toDegrees(treeLatRad), lon: _toDegrees(treeLonRad));
  }

  /// [向後相容] 反推測站位置
  @Deprecated(
      'Use calculateTreePositionFromStation instead. GPS coords are station, not tree.')
  static ({double lat, double lon}) calculateStationPosition({
    required double treeLat,
    required double treeLon,
    required double horizontalDistance,
    required double azimuth,
  }) {
    const double R = 6371000;
    double reverseAzimuth = (azimuth + 180) % 360;
    double azimuthRad = _toRadians(reverseAzimuth);
    double treeLatRad = _toRadians(treeLat);
    double treeLonRad = _toRadians(treeLon);
    double angularDistance = horizontalDistance / R;

    double stationLatRad = math.asin(
        math.sin(treeLatRad) * math.cos(angularDistance) +
            math.cos(treeLatRad) *
                math.sin(angularDistance) *
                math.cos(azimuthRad));

    double stationLonRad = treeLonRad +
        math.atan2(
            math.sin(azimuthRad) *
                math.sin(angularDistance) *
                math.cos(treeLatRad),
            math.cos(angularDistance) -
                math.sin(treeLatRad) * math.sin(stationLatRad));

    return (lat: _toDegrees(stationLatRad), lon: _toDegrees(stationLonRad));
  }

  /// 從 JSON 創建
  factory PendingTreeMeasurement.fromJson(Map<String, dynamic> json) {
    return PendingTreeMeasurement(
      id: json['id'] as int?,
      sessionId: json['session_id'] as String?,
      originalRecordId: json['original_record_id'] as String?,
      projectArea: json['project_area'] as String?,
      projectCode: json['project_code'] as String?,
      projectName: json['project_name'] as String?,
      speciesName: json['species_name'] as String?,
      treeHeight: (json['tree_height'] as num).toDouble(),
      dbhCm: json['dbh_cm'] != null ? (json['dbh_cm'] as num).toDouble() : null,
      treeLatitude: (json['tree_latitude'] as num).toDouble(),
      treeLongitude: (json['tree_longitude'] as num).toDouble(),
      stationLatitude: (json['station_latitude'] as num).toDouble(),
      stationLongitude: (json['station_longitude'] as num).toDouble(),
      horizontalDistance: (json['horizontal_distance'] as num).toDouble(),
      slopeDistance: (json['slope_distance'] as num).toDouble(),
      azimuth: (json['azimuth'] as num).toDouble(),
      pitch: (json['pitch'] as num).toDouble(),
      altitude: json['altitude'] != null
          ? (json['altitude'] as num).toDouble()
          : null,
      status:
          MeasurementStatus.fromString(json['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(json['created_at'] as String),
      completedAt: json['completed_at'] != null
          ? DateTime.parse(json['completed_at'] as String)
          : null,
      assignedTo: json['assigned_to'] as String?,
      priority: json['priority'] as int?,
      measurementType: json['measurement_type'] as String?,
      measuredDbhCm: json['measured_dbh_cm'] != null
          ? (json['measured_dbh_cm'] as num).toDouble()
          : null,
      measurementConfidence: json['measurement_confidence'] != null
          ? (json['measurement_confidence'] as num).toDouble()
          : null,
      measurementMethod: json['measurement_method'] as String?,
      measurementNotes: json['measurement_notes'] as String?,
    );
  }

  /// 轉換為 JSON
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (originalRecordId != null) 'original_record_id': originalRecordId,
      if (projectArea != null) 'project_area': projectArea,
      if (projectCode != null) 'project_code': projectCode,
      if (projectName != null) 'project_name': projectName,
      if (speciesName != null) 'species_name': speciesName,
      'tree_height': treeHeight,
      if (dbhCm != null) 'dbh_cm': dbhCm,
      'tree_latitude': treeLatitude,
      'tree_longitude': treeLongitude,
      'station_latitude': stationLatitude,
      'station_longitude': stationLongitude,
      'horizontal_distance': horizontalDistance,
      'slope_distance': slopeDistance,
      'azimuth': azimuth,
      'pitch': pitch,
      if (altitude != null) 'altitude': altitude,
      'status': status.value,
      'created_at': createdAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (assignedTo != null) 'assigned_to': assignedTo,
      if (priority != null) 'priority': priority,
      if (measurementType != null) 'measurement_type': measurementType,
      if (measuredDbhCm != null) 'measured_dbh_cm': measuredDbhCm,
      if (measurementConfidence != null)
        'measurement_confidence': measurementConfidence,
      if (measurementMethod != null) 'measurement_method': measurementMethod,
      if (measurementNotes != null) 'measurement_notes': measurementNotes,
    };
  }

  /// 複製並更新部分欄位
  PendingTreeMeasurement copyWith({
    int? id,
    String? sessionId,
    String? originalRecordId,
    String? projectArea,
    String? projectCode,
    String? projectName,
    String? speciesName,
    double? treeHeight,
    double? dbhCm,
    double? treeLatitude,
    double? treeLongitude,
    double? stationLatitude,
    double? stationLongitude,
    double? horizontalDistance,
    double? slopeDistance,
    double? azimuth,
    double? pitch,
    double? altitude,
    MeasurementStatus? status,
    DateTime? createdAt,
    DateTime? completedAt,
    String? assignedTo,
    int? priority,
    String? measurementType,
    double? measuredDbhCm,
    double? measurementConfidence,
    String? measurementMethod,
    String? measurementNotes,
  }) {
    return PendingTreeMeasurement(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      originalRecordId: originalRecordId ?? this.originalRecordId,
      projectArea: projectArea ?? this.projectArea,
      projectCode: projectCode ?? this.projectCode,
      projectName: projectName ?? this.projectName,
      speciesName: speciesName ?? this.speciesName,
      treeHeight: treeHeight ?? this.treeHeight,
      dbhCm: dbhCm ?? this.dbhCm,
      treeLatitude: treeLatitude ?? this.treeLatitude,
      treeLongitude: treeLongitude ?? this.treeLongitude,
      stationLatitude: stationLatitude ?? this.stationLatitude,
      stationLongitude: stationLongitude ?? this.stationLongitude,
      horizontalDistance: horizontalDistance ?? this.horizontalDistance,
      slopeDistance: slopeDistance ?? this.slopeDistance,
      azimuth: azimuth ?? this.azimuth,
      pitch: pitch ?? this.pitch,
      altitude: altitude ?? this.altitude,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      assignedTo: assignedTo ?? this.assignedTo,
      priority: priority ?? this.priority,
      measurementType: measurementType ?? this.measurementType,
      measuredDbhCm: measuredDbhCm ?? this.measuredDbhCm,
      measurementConfidence:
          measurementConfidence ?? this.measurementConfidence,
      measurementMethod: measurementMethod ?? this.measurementMethod,
      measurementNotes: measurementNotes ?? this.measurementNotes,
    );
  }
}

/// 測量狀態枚舉
enum MeasurementStatus {
  pending('pending', '待測量'),
  inProgress('in_progress', '進行中'),
  completed('completed', '已完成'),
  skipped('skipped', '已跳過'),
  failed('failed', '測量失敗'),
  transferred('transferred', '已轉移');

  final String value;
  final String label;

  const MeasurementStatus(this.value, this.label);

  static MeasurementStatus fromString(String value) {
    return MeasurementStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => MeasurementStatus.pending,
    );
  }
}

/// 測量任務批次
class MeasurementSession {
  final String sessionId;
  final String? name;
  final String? description;
  final String createdBy;
  final DateTime createdAt;
  final int totalTrees;
  final int completedTrees;
  final String? projectArea;
  final String? projectCode;

  const MeasurementSession({
    required this.sessionId,
    this.name,
    this.description,
    required this.createdBy,
    required this.createdAt,
    required this.totalTrees,
    required this.completedTrees,
    this.projectArea,
    this.projectCode,
  });

  double get progressPercent =>
      totalTrees > 0 ? (completedTrees / totalTrees * 100) : 0;

  bool get isComplete => completedTrees >= totalTrees;

  factory MeasurementSession.fromJson(Map<String, dynamic> json) {
    return MeasurementSession(
      sessionId: json['session_id'] as String,
      name: json['name'] as String?,
      description: json['description'] as String?,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      totalTrees: json['total_trees'] as int,
      completedTrees: json['completed_trees'] as int,
      projectArea: json['project_area'] as String?,
      projectCode: json['project_code'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'total_trees': totalTrees,
      'completed_trees': completedTrees,
      if (projectArea != null) 'project_area': projectArea,
      if (projectCode != null) 'project_code': projectCode,
    };
  }
}
