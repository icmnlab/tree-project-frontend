import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/pending_tree_measurement.dart';
import '../config/app_config.dart';
import '../config/survey_settings.dart';
import 'api_service.dart';
import '../utils/field_log.dart';
import 'v3/station_service.dart'; // Import StationService

/// 待測量樹木服務
///
/// 處理 VLGEO2 數據的解析、存儲和第二階段測量的管理
class PendingMeasurementService {
  // 使用 AppConfig 的動態 API URL
  String get _baseUrl => AppConfig().baseUrl.replaceAll('/api', '');
  final StationService _stationService = StationService();

  /// 從 BLE 數據創建待測量記錄
  ///
  /// [bleData] - BleDataProcessor.parseCsvData() 的結果
  /// [projectArea] / [projectCode] / [projectName] - 全域 fallback 指派
  ///   每筆 record 可以另外帶
  ///     _assigned_project_area / _assigned_project_code / _assigned_project_name
  ///     _survey_mode  ('new' | 'maintenance')
  ///   來覆寫全域值（per-tree 指派優先）。
  /// [createdBy] - 創建者 ID
  /// [sessionId] 若提供則同一現場場次共用（現場連線逐棵模式）
  List<PendingTreeMeasurement> createFromBleData({
    required List<Map<String, dynamic>> bleData,
    String? projectArea,
    String? projectCode,
    String? projectName,
    String? createdBy,
    String? sessionId,
  }) {
    final String resolvedSessionId = sessionId ?? generateSessionId();
    final List<PendingTreeMeasurement> pendingMeasurements = [];

    for (var record in bleData) {
      try {
        final metadata = record['metadata'] as Map<String, dynamic>? ?? {};

        final double lat = (record['lat'] as num?)?.toDouble() ?? 0;
        final double lon = (record['lon'] as num?)?.toDouble() ?? 0;
        final double height = (record['height'] as num?)?.toDouble() ?? 0;
        final double horizontalDistance =
            (metadata['horizontal_distance'] as num?)?.toDouble() ?? 0;
        final double slopeDistance =
            (metadata['slope_distance'] as num?)?.toDouble() ?? 0;
        final double azimuth = (metadata['azimuth'] as num?)?.toDouble() ?? 0;
        final double pitch = (metadata['pitch'] as num?)?.toDouble() ?? 0;
        final double? altitude = (metadata['altitude'] as num?)?.toDouble();
        final String type = record['type'] as String? ?? '';
        final String? heightMethod =
            metadata['height_method'] as String? ??
                metadata['instrument_height_mode'] as String?;
        final String resolvedMeasurementType = _resolveMeasurementType(
          type,
          heightMethod,
        );
        final bool hasGps = record['hasGps'] as bool? ?? (lat != 0 || lon != 0);
        final double? bleDia = (record['dbh'] as num?)?.toDouble();
        final String? dbhSource = metadata['dbh_source'] as String?;
        final String surveyMode = (record['_survey_mode'] as String?) ??
            (metadata['survey_mode'] as String?) ??
            'new';
        final int? targetTreeId = _toInt(
          record['_target_tree_id'] ?? metadata['target_tree_id'],
        );
        final String? matchStatus = (record['_match_status'] as String?) ??
            (metadata['match_status'] as String?);

        if (horizontalDistance <= 0) continue;

        if (!hasGps) {
          debugPrint('━━━ 記錄 ID=${record['id']} — 無 GPS，跳過 ━━━');
          continue;
        }

        // [v21.0] GPS 來源辨識：'tree' = lat/lon 已是樹位置，不需偏移；
        //                    'surveyor' / 'gnss' (預設舊行為) = 用 HD+AZ 計算樹位置。
        final gpsSource = metadata['gps_source'] as String? ?? 'tree';
        if (gpsSource == 'mixed_pending') {
          final recordId = record['id'];
          debugPrint('━━━ 記錄 ID=$recordId — GPS source 尚未逐筆確認，跳過 ━━━');
          continue;
        }
        final recordId = record['id'];
        debugPrint('━━━ 記錄 ID=$recordId (GPS via $gpsSource) ━━━');
        debugPrint('  GPS 座標: ($lat, $lon)');
        debugPrint('  HD=$horizontalDistance m  AZ=$azimuth°  H=$height m');

        double treeLat;
        double treeLon;
        double stationLat;
        double stationLon;
        if (gpsSource == 'tree') {
          // GPS 已是樹位置；反推測站只作導覽/追溯輔助，導航仍直接導到樹位
          treeLat = lat;
          treeLon = lon;
          final stationPos = _stationService.calculateStationPosition(
            treeLat: treeLat,
            treeLng: treeLon,
            distanceMeters: horizontalDistance,
            azimuthDegrees: azimuth,
          );
          stationLat = stationPos.latitude;
          stationLon = stationPos.longitude;
          metadata['tree_position_source'] = 'gps_receiver';
          metadata['station_position_source'] = 'derived_from_tree_gps_hd_az';
        } else {
          // 'surveyor' / 'gnss' / 'utm_recovery' → 用 HD+AZ 偏移
          stationLat = lat;
          stationLon = lon;
          final treePos = _stationService.calculateTreePosition(
            stationLat: stationLat,
            stationLng: stationLon,
            distanceMeters: horizontalDistance,
            azimuthDegrees: azimuth,
          );
          treeLat = treePos.latitude;
          treeLon = treePos.longitude;
          metadata['tree_position_source'] = 'derived_from_station_gps_hd_az';
          metadata['station_position_source'] = 'gps_receiver';

          final verifyDist = _stationService.getDistance(
            lat1: stationLat,
            lon1: stationLon,
            lat2: treeLat,
            lon2: treeLon,
          );
          debugPrint(
              '  計算樹位: (${treeLat.toStringAsFixed(7)}, ${treeLon.toStringAsFixed(7)})');
          debugPrint(
              '  驗證距離: ${verifyDist.toStringAsFixed(2)}m (應≈${horizontalDistance}m)');
        }

        final bool handbook = SurveySettings.instance.handbookCompliantMode;
        final bool hasBleDia = bleDia != null && bleDia > 0;
        final double? pendingDbhCm =
            handbook ? null : (hasBleDia ? bleDia : null);
        final double? instrumentDbhCm = hasBleDia ? bleDia : null;
        final String pendingDbhSource = handbook
            ? 'manual'
            : (dbhSource ?? (hasBleDia ? 'remote_diameter' : 'manual'));

        final pending = PendingTreeMeasurement(
          sessionId: resolvedSessionId,
          originalRecordId: record['id']?.toString(),
          projectArea:
              (record['_assigned_project_area'] as String?) ?? projectArea,
          projectCode:
              (record['_assigned_project_code'] as String?) ?? projectCode,
          projectName:
              (record['_assigned_project_name'] as String?) ?? projectName,
          treeHeight: height,
          dbhCm: pendingDbhCm,
          instrumentDbhCm: instrumentDbhCm,
          dbhSource: pendingDbhSource,
          treeLatitude: treeLat,
          treeLongitude: treeLon,
          stationLatitude: stationLat,
          stationLongitude: stationLon,
          horizontalDistance: horizontalDistance,
          slopeDistance: slopeDistance,
          azimuth: azimuth,
          pitch: pitch,
          altitude: altitude,
          measurementType: resolvedMeasurementType.isEmpty
              ? null
              : resolvedMeasurementType,
          status: MeasurementStatus.pending,
          createdAt: DateTime.now(),
          priority: _calculatePriority(horizontalDistance),
          surveyMode: surveyMode,
          targetTreeId: targetTreeId,
          matchStatus: matchStatus,
          gpsHdop: (metadata['hdop'] as num?)?.toDouble(),
          deviceSn: metadata['device_sn'] as String?,
          refHeight: (metadata['ref_height'] as num?)?.toDouble(),
          utmZone: metadata['utm_zone'] as String?,
          rawDataSnapshot: _buildRawDataSnapshot(record, metadata),
        );

        if (bleDia != null && bleDia > 0) {
          debugPrint('  Remote Diameter: ${bleDia.toStringAsFixed(1)} cm');
        }

        pendingMeasurements.add(pending);
      } catch (e) {
        debugPrint('解析待測量記錄失敗: $e');
      }
    }

    return pendingMeasurements;
  }

  /// 生成測量批次 ID（現場連線多棵共用同一 session）
  static String generateSessionId() {
    final now = DateTime.now();
    return 'MS-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 100000}';
  }

  static String _resolveMeasurementType(String type, String? heightMethod) {
    final t = type.trim();
    if (t == 'LIVE' && heightMethod != null && heightMethod.isNotEmpty) {
      return heightMethod.toUpperCase();
    }
    return t;
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 根據距離計算優先級 (近的優先)
  static int _calculatePriority(double distance) {
    if (distance <= 10) return 1; // 很近
    if (distance <= 30) return 2; // 近
    if (distance <= 50) return 3; // 中等
    if (distance <= 100) return 4; // 遠
    return 5; // 很遠
  }

  /// 構建原始數據快照，保留 VLGEO2 所有欄位供日後追溯
  static Map<String, dynamic> _buildRawDataSnapshot(
    Map<String, dynamic> record,
    Map<String, dynamic> metadata,
  ) {
    return {
      'id': record['id'],
      'type': record['type'],
      'lat': record['lat'],
      'lon': record['lon'],
      'height': record['height'],
      'dbh': record['dbh'],
      'hasGps': record['hasGps'],
      ...metadata,
    };
  }

  /// 上傳待測量記錄到後端
  static const _timeout = Duration(seconds: 30);

  /// 上傳待測量記錄到後端
  Future<Map<String, dynamic>> uploadPendingMeasurements(
    List<PendingTreeMeasurement> measurements, {
    String? requestId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/pending-measurements/batch'),
            headers: ApiService.jsonHeaders(requestId: requestId),
            body: jsonEncode({
              'measurements': measurements.map((m) => m.toJson()).toList(),
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('上傳失敗: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      debugPrint('上傳待測量記錄失敗: $e');
      rethrow;
    }
  }

  /// 獲取所有待測量批次
  Future<List<MeasurementSession>> getSessions() async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/pending-measurements/sessions'),
            headers: ApiService.getAuthHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        return data.map((json) => MeasurementSession.fromJson(json)).toList();
      } else {
        throw Exception('獲取批次失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('獲取測量批次失敗: $e');
      rethrow;
    }
  }

  /// 獲取批次內的待測量樹木
  Future<List<PendingTreeMeasurement>> getPendingTrees({
    String? sessionId,
    MeasurementStatus? status,
    double? userLat,
    double? userLon,
    bool sortByDistance = true,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (sessionId != null) queryParams['session_id'] = sessionId;
      if (status != null) queryParams['status'] = status.value;

      final uri = Uri.parse('$_baseUrl/api/pending-measurements/trees')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      final response = await http
          .get(
            uri,
            headers: ApiService.getAuthHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        var trees =
            data.map((json) => PendingTreeMeasurement.fromJson(json)).toList();

        // 如果提供用戶位置，按距離排序
        if (sortByDistance && userLat != null && userLon != null) {
          trees.sort((a, b) {
            final distA = a.distanceToNavigationTarget(userLat, userLon);
            final distB = b.distanceToNavigationTarget(userLat, userLon);
            return distA.compareTo(distB);
          });
        }

        return trees;
      } else {
        throw Exception('獲取待測量樹木失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('獲取待測量樹木失敗: $e');
      rethrow;
    }
  }

  /// 更新測量結果
  /// [T6][Phase1.5] [expectedUpdatedAt] 帶上載入時的 updated_at 啟用樂觀鎖；
  /// 後端不符會回 409 / 不存在回 410，本方法不再 throw，直接回傳 body Map 給呼叫端判斷 code 欄位。
  Future<Map<String, dynamic>> updateMeasurement({
    required int id,
    required double dbhCm,
    required double confidence,
    required String method,
    String? notes,
    String? speciesName,
    String? expectedUpdatedAt,
    String? dbhSource,
    Map<String, dynamic>? rawDataSnapshotMerge,
  }) async {
    try {
      final body = {
        'measured_dbh_cm': dbhCm,
        'measurement_confidence': confidence,
        'measurement_method': method,
        'measurement_notes': notes,
        'status': MeasurementStatus.completed.value,
        'completed_at': DateTime.now().toIso8601String(),
      };
      if (dbhSource != null) {
        body['dbh_source'] = dbhSource;
      }

      if (speciesName != null) {
        body['species_name'] = speciesName;
      }
      if (expectedUpdatedAt != null) {
        body['expected_updated_at'] = expectedUpdatedAt;
      }
      if (rawDataSnapshotMerge != null && rawDataSnapshotMerge.isNotEmpty) {
        body['raw_data_snapshot_merge'] = rawDataSnapshotMerge;
      }

      final response = await http
          .patch(
            Uri.parse('$_baseUrl/api/pending-measurements/$id'),
            headers: ApiService.jsonHeaders(),
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      // [T6] 200 / 409 / 410 都把 body 解析後回傳
      if (response.statusCode == 200 ||
          response.statusCode == 409 ||
          response.statusCode == 410) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        FieldLog.pending(
          'PATCH $id → ${response.statusCode} '
          'code=${body['code'] ?? 'ok'} '
          'updated_at=${body['updated_at'] ?? body['serverVersion']?['updated_at']}',
        );
        return body;
      } else {
        throw Exception('更新測量結果失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('更新測量結果失敗: $e');
      rethrow;
    }
  }

  /// 跳過某棵樹的測量
  Future<void> skipMeasurement(int id, {String? reason}) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/api/pending-measurements/$id'),
            headers: ApiService.jsonHeaders(),
            body: jsonEncode({
              'status': MeasurementStatus.skipped.value,
              'measurement_notes': reason ?? '使用者跳過',
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('跳過測量失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('跳過測量失敗: $e');
      rethrow;
    }
  }

  /// 更新任務狀態（不改變其他欄位）
  /// 回傳伺服器最新的 [updated_at]（in_progress 會觸發 trigger，供樂觀鎖使用）
  Future<DateTime?> updateTaskStatus(int id, MeasurementStatus status) async {
    try {
      final response = await http
          .patch(
            Uri.parse('$_baseUrl/api/pending-measurements/$id'),
            headers: ApiService.jsonHeaders(),
            body: jsonEncode({
              'status': status.value,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final data = body['data'];
        if (data is Map && data['updated_at'] != null) {
          return DateTime.tryParse(data['updated_at'].toString());
        }
      }
      return null;
    } catch (e) {
      debugPrint('更新任務狀態失敗: $e');
      rethrow;
    }
  }

  /// 取得單筆待測量（含最新 updated_at）
  Future<PendingTreeMeasurement?> fetchTaskById(int id) async {
    try {
      final response = await http
          .get(
            Uri.parse('$_baseUrl/api/pending-measurements/$id'),
            headers: ApiService.getAuthHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          return PendingTreeMeasurement.fromJson(body);
        }
      }
      return null;
    } catch (e) {
      debugPrint('取得待測量任務失敗: $e');
      return null;
    }
  }

  /// 將已完成的測量轉移到正式 tree_survey 表
  Future<Map<String, dynamic>> transferToTreeSurvey({
    required String sessionId,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/pending-measurements/transfer'),
            headers: ApiService.jsonHeaders(),
            body: jsonEncode({
              'session_id': sessionId,
            }),
          )
          .timeout(_timeout);

      final body = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return body is Map<String, dynamic>
            ? body
            : {'success': true, 'data': body};
      }
      if (response.statusCode == 400 && body is Map<String, dynamic>) {
        return {...body, 'success': false};
      }
      throw Exception('轉移數據失敗: ${response.statusCode}');
    } catch (e) {
      debugPrint('轉移數據失敗: $e');
      rethrow;
    }
  }

  /// 更新整個 session 的專案資訊（單次請求，取代 N+1 逐筆 PATCH）
  Future<void> updateSessionProject({
    required String sessionId,
    required String projectArea,
    String? projectCode,
    String? projectName,
  }) async {
    try {
      final response = await http
          .patch(
            Uri.parse(
                '$_baseUrl/api/pending-measurements/session/$sessionId/project'),
            headers: ApiService.jsonHeaders(),
            body: jsonEncode({
              'project_area': projectArea,
              'project_code': projectCode,
              'project_name': projectName,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('批量更新專案資訊失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('批量更新專案資訊失敗: $e');
      rethrow;
    }
  }

  /// [v21.0] 刪除整個 session 的所有 pending 記錄
  /// 回傳已刪除的筆數
  Future<int> deleteSession(String sessionId) async {
    try {
      final response = await http
          .delete(
            Uri.parse('$_baseUrl/api/pending-measurements/session/$sessionId'),
            headers: ApiService.getAuthHeaders(),
          )
          .timeout(_timeout);

      if (response.statusCode == 404) {
        return 0;
      }
      if (response.statusCode != 200) {
        throw Exception('刪除 session 失敗: ${response.statusCode}');
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['deleted_count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('刪除 session 失敗: $e');
      rethrow;
    }
  }

  /// 建立一筆 AutoPilot smoke-test 待測量任務。
  ///
  /// 這筆資料會寫入後端 pending table，讓 V3 表單可以完整測試：
  /// pending list → IntegratedTreeFormPage → 拍照 → DBH + 樹種辨識。
  /// raw_data_snapshot 會標記 is_smoke_test，後端 transfer 會跳過此類資料。
  Future<String> createAutoPilotSmokeTestTask({
    double? baseLatitude,
    double? baseLongitude,
    double? locationAccuracyM,
  }) async {
    final projectsResp = await ApiService.get('projects');
    if (projectsResp['success'] != true || projectsResp['data'] is! List) {
      throw Exception(projectsResp['message'] ?? '無法取得可用專案');
    }

    final projects = (projectsResp['data'] as List)
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .where((p) => (p['code'] ?? '').toString().trim().isNotEmpty)
        .toList();
    if (projects.isEmpty) {
      throw Exception('沒有可用專案，無法建立測試任務');
    }

    final project = projects.first;
    final now = DateTime.now();
    final suffix = now.millisecondsSinceEpoch % 1000000;
    final sessionId =
        'SMOKE-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$suffix';
    final hasBaseLocation = baseLatitude != null &&
        baseLongitude != null &&
        (baseLatitude != 0 || baseLongitude != 0);
    const smokeDistanceM = 2.0;
    const smokeAzimuthDeg = 90.0;
    final stationLat = hasBaseLocation ? baseLatitude : 0.0;
    final stationLon = hasBaseLocation ? baseLongitude : 0.0;
    final projectArea =
        (project['area'] ?? project['name'] ?? 'AutoPilot 測試').toString();
    final projectCode = project['code'].toString();
    final projectName = (project['name'] ?? project['code']).toString();
    final bleLikeRecord = {
      'id': 'SMOKE-AUTOPILOT-001',
      'type': '1P',
      'lat': stationLat,
      'lon': stationLon,
      'hasGps': true,
      'height': 10.0,
      'metadata': {
        'gps_source': 'surveyor',
        'horizontal_distance': smokeDistanceM,
        'slope_distance': smokeDistanceM,
        'azimuth': smokeAzimuthDeg,
        'pitch': 0.0,
        'is_smoke_test': true,
        'smoke_test_type': 'autopilot_phone_flow',
        'smoke_test_has_phone_gps': hasBaseLocation,
        'smoke_test_distance_m': smokeDistanceM,
        'smoke_test_azimuth_deg': smokeAzimuthDeg,
        if (locationAccuracyM != null)
          'phone_gps_accuracy_m': locationAccuracyM,
        'notes':
            'Generated by app for V3 AutoPilot smoke testing. Delete the session after testing.',
      },
    };
    final tasks = createFromBleData(
      bleData: [bleLikeRecord],
      projectArea: projectArea,
      projectCode: projectCode,
      projectName: projectName,
    );
    if (tasks.isEmpty) {
      throw Exception('建立測試任務失敗：BLE-style smoke record was skipped');
    }
    final task = tasks.single.copyWith(
      sessionId: sessionId,
      rawDataSnapshot: {
        ...?tasks.single.rawDataSnapshot,
        'hasGps': hasBaseLocation,
        'is_smoke_test': true,
        'smoke_test_type': 'autopilot_phone_flow',
        'smoke_test_has_phone_gps': hasBaseLocation,
        'smoke_test_distance_m': smokeDistanceM,
        'smoke_test_azimuth_deg': smokeAzimuthDeg,
        'tree_position_source': hasBaseLocation
            ? 'smoke_test_current_gps_plus_offset'
            : 'smoke_test_no_gps',
        'station_position_source':
            hasBaseLocation ? 'smoke_test_current_gps' : 'smoke_test_no_gps',
        if (locationAccuracyM != null)
          'phone_gps_accuracy_m': locationAccuracyM,
        'notes':
            'Generated by app for V3 AutoPilot smoke testing. Delete the session after testing.',
      },
    );

    final result = await uploadPendingMeasurements([task]);
    if (result['success'] != true) {
      throw Exception(result['message'] ?? '建立測試任務失敗');
    }
    return sessionId;
  }

  /// 獲取最近的待測量樹木
  Future<PendingTreeMeasurement?> getNearestPendingTree({
    required double userLat,
    required double userLon,
    String? sessionId,
  }) async {
    final trees = await getPendingTrees(
      sessionId: sessionId,
      status: MeasurementStatus.pending,
      userLat: userLat,
      userLon: userLon,
      sortByDistance: true,
    );

    return trees.isNotEmpty ? trees.first : null;
  }

  /// 從 BLE 數據創建並上傳待測量記錄 (便捷方法)
  ///
  /// [bleData] - BLE 解析後的數據
  /// [batchName] - 批次名稱
  /// [projectArea] - 專案區位
  /// [projectCode] - 專案代碼
  /// [projectName] - 專案名稱
  Future<Map<String, dynamic>> createAndUploadFromBle({
    required List<Map<String, dynamic>> bleData,
    String? batchName,
    String? projectArea,
    String? projectCode,
    String? projectName,
    String? sessionId,
  }) async {
    try {
      final measurements = createFromBleData(
        bleData: bleData,
        projectArea: projectArea,
        projectCode: projectCode,
        projectName: projectName,
        sessionId: sessionId,
      );

      if (measurements.isEmpty) {
        return {
          'success': false,
          'message': '沒有有效的測量數據',
          'count': 0,
        };
      }

      final result = await uploadPendingMeasurements(measurements);

      final insertedRaw = result['inserted_ids'];
      if (insertedRaw is List && insertedRaw.length == measurements.length) {
        for (var i = 0; i < insertedRaw.length; i++) {
          final id = insertedRaw[i];
          if (id is int) {
            measurements[i] = measurements[i].copyWith(id: id);
          } else if (id is num) {
            measurements[i] = measurements[i].copyWith(id: id.toInt());
          }
        }
      }

      return {
        'success': true,
        'message': '成功儲存 ${measurements.length} 筆待測量記錄',
        'count': measurements.length,
        'sessionId': result['session_id'] ?? measurements.first.sessionId,
        'tasks': measurements,
        'data': result,
      };
    } catch (e) {
      debugPrint('創建並上傳 BLE 數據失敗: $e');
      return {
        'success': false,
        'message': '上傳失敗: $e',
        'count': 0,
      };
    }
  }
}
