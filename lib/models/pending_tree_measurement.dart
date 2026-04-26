import 'dart:convert';
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
  final double? dbhCm; // 胸徑 (待測量或 Remote Diameter)
  final double? instrumentDbhCm; // 儀器 Remote Diameter 測量值 (cm)
  final String? dbhSource; // DBH 來源: 'remote_diameter', 'vision', 'manual'

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
  // [T6][Phase1.5] 樂觀鎖依據（PG trigger 自動更新）
  final DateTime? updatedAt;
  final DateTime? completedAt;
  final String? assignedTo; // 指派給哪位測量員
  final int? priority; // 優先級 (1-5)

  final String? measurementType; // 測量類型 (1P, 3P, 3D, DME)

  // DBH 測量結果 (第二階段填入)
  final double? measuredDbhCm; // 測量的 DBH
  final double? measurementConfidence; // 測量信心度
  final String? measurementMethod; // 測量方法
  final String? measurementNotes; // 測量備註

  // 儀器參數 (來自 VLGEO2 擴展欄位)
  final double? gpsHdop; // GPS HDOP 精度指標
  final String? deviceSn; // 儀器序號
  final double? refHeight; // 參考高度 (REFH)
  final String? utmZone; // UTM 區域
  final Map<String, dynamic>? rawDataSnapshot; // 原始資料快照

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
    this.instrumentDbhCm,
    this.dbhSource,
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
    this.updatedAt,
    this.completedAt,
    this.assignedTo,
    this.priority,
    this.measurementType,
    this.measuredDbhCm,
    this.measurementConfidence,
    this.measurementMethod,
    this.measurementNotes,
    this.gpsHdop,
    this.deviceSn,
    this.refHeight,
    this.utmZone,
    this.rawDataSnapshot,
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

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double _toDouble(dynamic v, [double fallback = 0.0]) {
    if (v == null) return fallback;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static double? _toDoubleOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  factory PendingTreeMeasurement.fromJson(Map<String, dynamic> json) {
    return PendingTreeMeasurement(
      id: _toInt(json['id']),
      sessionId: json['session_id']?.toString(),
      originalRecordId: json['original_record_id']?.toString(),
      projectArea: json['project_area']?.toString(),
      projectCode: json['project_code']?.toString(),
      projectName: json['project_name']?.toString(),
      speciesName: json['species_name']?.toString(),
      treeHeight: _toDouble(json['tree_height']),
      dbhCm: _toDoubleOrNull(json['dbh_cm']),
      instrumentDbhCm: _toDoubleOrNull(json['instrument_dbh_cm']),
      dbhSource: json['dbh_source']?.toString(),
      treeLatitude: _toDouble(json['tree_latitude']),
      treeLongitude: _toDouble(json['tree_longitude']),
      stationLatitude: _toDouble(json['station_latitude']),
      stationLongitude: _toDouble(json['station_longitude']),
      horizontalDistance: _toDouble(json['horizontal_distance']),
      slopeDistance: _toDouble(json['slope_distance']),
      azimuth: _toDouble(json['azimuth']),
      pitch: _toDouble(json['pitch']),
      altitude: _toDoubleOrNull(json['altitude']),
      status: MeasurementStatus.fromString(json['status']?.toString() ?? 'pending'),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : null,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString())
          : null,
      assignedTo: json['assigned_to']?.toString(),
      priority: _toInt(json['priority']),
      measurementType: json['measurement_type']?.toString(),
      measuredDbhCm: _toDoubleOrNull(json['measured_dbh_cm']),
      measurementConfidence: _toDoubleOrNull(json['measurement_confidence']),
      measurementMethod: json['measurement_method']?.toString(),
      measurementNotes: json['measurement_notes']?.toString(),
      gpsHdop: _toDoubleOrNull(json['gps_hdop']),
      deviceSn: json['device_sn']?.toString(),
      refHeight: _toDoubleOrNull(json['ref_height']),
      utmZone: json['utm_zone']?.toString(),
      rawDataSnapshot: json['raw_data_snapshot'] is Map
          ? Map<String, dynamic>.from(json['raw_data_snapshot'])
          : (json['raw_data_snapshot'] is String
              ? (jsonDecode(json['raw_data_snapshot']) as Map<String, dynamic>?)
              : null),
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
      if (instrumentDbhCm != null) 'instrument_dbh_cm': instrumentDbhCm,
      if (dbhSource != null) 'dbh_source': dbhSource,
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
      if (gpsHdop != null) 'gps_hdop': gpsHdop,
      if (deviceSn != null) 'device_sn': deviceSn,
      if (refHeight != null) 'ref_height': refHeight,
      if (utmZone != null) 'utm_zone': utmZone,
      if (rawDataSnapshot != null) 'raw_data_snapshot': rawDataSnapshot,
    };
  }

  /// 複製並更新部分欄位
  /// 是否已有儀器 Remote Diameter 數據
  bool get hasInstrumentDbh =>
      instrumentDbhCm != null && instrumentDbhCm! > 0;

  /// 是否需要 DBH 補測（沒有任何 DBH 來源）
  bool get needsDbhMeasurement =>
      !hasInstrumentDbh && (measuredDbhCm == null || measuredDbhCm == 0);

  /// 最佳可用 DBH 值（優先: 影像/手動測量 > 儀器 Remote Diameter）
  double? get bestAvailableDbh =>
      (measuredDbhCm != null && measuredDbhCm! > 0)
          ? measuredDbhCm
          : instrumentDbhCm;

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
    double? instrumentDbhCm,
    String? dbhSource,
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
    DateTime? updatedAt,
    DateTime? completedAt,
    String? assignedTo,
    int? priority,
    String? measurementType,
    double? measuredDbhCm,
    double? measurementConfidence,
    String? measurementMethod,
    String? measurementNotes,
    double? gpsHdop,
    String? deviceSn,
    double? refHeight,
    String? utmZone,
    Map<String, dynamic>? rawDataSnapshot,
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
      instrumentDbhCm: instrumentDbhCm ?? this.instrumentDbhCm,
      dbhSource: dbhSource ?? this.dbhSource,
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
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      assignedTo: assignedTo ?? this.assignedTo,
      priority: priority ?? this.priority,
      measurementType: measurementType ?? this.measurementType,
      measuredDbhCm: measuredDbhCm ?? this.measuredDbhCm,
      measurementConfidence:
          measurementConfidence ?? this.measurementConfidence,
      measurementMethod: measurementMethod ?? this.measurementMethod,
      measurementNotes: measurementNotes ?? this.measurementNotes,
      gpsHdop: gpsHdop ?? this.gpsHdop,
      deviceSn: deviceSn ?? this.deviceSn,
      refHeight: refHeight ?? this.refHeight,
      utmZone: utmZone ?? this.utmZone,
      rawDataSnapshot: rawDataSnapshot ?? this.rawDataSnapshot,
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
      sessionId: json['session_id']?.toString() ?? '',
      name: json['name']?.toString(),
      description: json['description']?.toString(),
      createdBy: json['created_by']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      totalTrees: _jsonToInt(json['total_trees']),
      completedTrees: _jsonToInt(json['completed_trees']),
      projectArea: json['project_area']?.toString(),
      projectCode: json['project_code']?.toString(),
    );
  }

  static int _jsonToInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
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
