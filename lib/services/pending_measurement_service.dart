import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/pending_tree_measurement.dart';
import '../config/app_config.dart';
import 'api_service.dart';
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
  List<PendingTreeMeasurement> createFromBleData({
    required List<Map<String, dynamic>> bleData,
    String? projectArea,
    String? projectCode,
    String? projectName,
    String? createdBy,
  }) {
    final String sessionId = _generateSessionId();
    final List<PendingTreeMeasurement> pendingMeasurements = [];
    
    for (var record in bleData) {
      try {
        final metadata = record['metadata'] as Map<String, dynamic>? ?? {};
        
        final double lat = (record['lat'] as num?)?.toDouble() ?? 0;
        final double lon = (record['lon'] as num?)?.toDouble() ?? 0;
        final double height = (record['height'] as num?)?.toDouble() ?? 0;
        final double horizontalDistance = (metadata['horizontal_distance'] as num?)?.toDouble() ?? 0;
        final double slopeDistance = (metadata['slope_distance'] as num?)?.toDouble() ?? 0;
        final double azimuth = (metadata['azimuth'] as num?)?.toDouble() ?? 0;
        final double pitch = (metadata['pitch'] as num?)?.toDouble() ?? 0;
        final double? altitude = (metadata['altitude'] as num?)?.toDouble();
        final String type = record['type'] as String? ?? '';
        final bool hasGps = record['hasGps'] as bool? ?? (lat != 0 || lon != 0);
        final double? bleDia = (record['dbh'] as num?)?.toDouble();
        final String? dbhSource = metadata['dbh_source'] as String?;
        
        if (horizontalDistance <= 0) continue;

        // [v21.0] 缺 GPS 處理：若使用者於 BLE import 時選 lax 模式（requires_gps_fix=true），
        // 仍保留記錄（樹位置先以 0,0 placeholder，等待使用者於 pending 列表手動補座標）；
        // 否則維持原行為跳過。
        final requiresGpsFix = metadata['requires_gps_fix'] == true;
        if (!hasGps && !requiresGpsFix) {
          debugPrint('━━━ 記錄 ID=${record['id']} — 無 GPS 且無 UTM 可補救，跳過 ━━━');
          continue;
        }

        // [v21.0] GPS 來源辨識：'tree' = lat/lon 已是樹位置，不需偏移；
        //                    'surveyor' / 'gnss' (預設舊行為) = 用 HD+AZ 計算樹位置；
        //                    'mixed_pending' = 視為 surveyor 處理但下游 UI 提示需確認
        final gpsSource = metadata['gps_source'] as String? ?? 'gnss';
        debugPrint('━━━ 記錄 ID=${record['id']} (GPS via $gpsSource'
            '${requiresGpsFix ? ", REQUIRES_GPS_FIX" : ""}) ━━━');
        debugPrint('  GPS 座標: ($lat, $lon)');
        debugPrint('  HD=${horizontalDistance}m  AZ=${azimuth}°  H=${height}m');

        double treeLat;
        double treeLon;
        if (!hasGps && requiresGpsFix) {
          // 缺 GPS lax：placeholder 0,0；UI 標紅旗
          treeLat = 0;
          treeLon = 0;
        } else if (gpsSource == 'tree') {
          // GPS 已是樹位置，不偏移
          treeLat = lat;
          treeLon = lon;
        } else {
          // 'surveyor' / 'gnss' / 'mixed_pending' / 'utm_recovery' → 用 HD+AZ 偏移
          final treePos = _stationService.calculateTreePosition(
            stationLat: lat,
            stationLng: lon,
            distanceMeters: horizontalDistance,
            azimuthDegrees: azimuth,
          );
          treeLat = treePos.latitude;
          treeLon = treePos.longitude;

          final verifyDist = _stationService.getDistance(
            lat1: lat, lon1: lon,
            lat2: treeLat, lon2: treeLon,
          );
          debugPrint('  計算樹位: (${treeLat.toStringAsFixed(7)}, ${treeLon.toStringAsFixed(7)})');
          debugPrint('  驗證距離: ${verifyDist.toStringAsFixed(2)}m (應≈${horizontalDistance}m)');
        }
        
        final pending = PendingTreeMeasurement(
          sessionId: sessionId,
          originalRecordId: record['id']?.toString(),
          projectArea: (record['_assigned_project_area'] as String?) ?? projectArea,
          projectCode: (record['_assigned_project_code'] as String?) ?? projectCode,
          projectName: (record['_assigned_project_name'] as String?) ?? projectName,
          treeHeight: height,
          dbhCm: bleDia,
          instrumentDbhCm: (dbhSource == 'remote_diameter') ? bleDia : null,
          dbhSource: dbhSource,
          treeLatitude: treeLat,
          treeLongitude: treeLon,
          stationLatitude: lat,
          stationLongitude: lon,
          horizontalDistance: horizontalDistance,
          slopeDistance: slopeDistance,
          azimuth: azimuth,
          pitch: pitch,
          altitude: altitude,
          measurementType: type,
          status: MeasurementStatus.pending,
          createdAt: DateTime.now(),
          priority: _calculatePriority(horizontalDistance),
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
  
  /// 生成測量批次 ID
  static String _generateSessionId() {
    final now = DateTime.now();
    return 'MS-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.millisecondsSinceEpoch % 100000}';
  }
  
  /// 根據距離計算優先級 (近的優先)
  static int _calculatePriority(double distance) {
    if (distance <= 10) return 1;  // 很近
    if (distance <= 30) return 2;  // 近
    if (distance <= 50) return 3;  // 中等
    if (distance <= 100) return 4; // 遠
    return 5;                       // 很遠
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
    List<PendingTreeMeasurement> measurements,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/pending-measurements/batch'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode({
          'measurements': measurements.map((m) => m.toJson()).toList(),
        }),
      ).timeout(_timeout);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception('上傳失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('上傳待測量記錄失敗: $e');
      rethrow;
    }
  }
  
  /// 獲取所有待測量批次
  Future<List<MeasurementSession>> getSessions() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/pending-measurements/sessions'),
        headers: ApiService.getAuthHeaders(),
      ).timeout(_timeout);
      
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
      
      final response = await http.get(
        uri,
        headers: ApiService.getAuthHeaders(),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        var trees = data.map((json) => PendingTreeMeasurement.fromJson(json)).toList();
        
        // 如果提供用戶位置，按距離排序
        if (sortByDistance && userLat != null && userLon != null) {
          trees.sort((a, b) {
            final distA = a.distanceToStation(userLat, userLon);
            final distB = b.distanceToStation(userLat, userLon);
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

      if (speciesName != null) {
        body['species_name'] = speciesName;
      }
      if (expectedUpdatedAt != null) {
        body['expected_updated_at'] = expectedUpdatedAt;
      }

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/$id'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode(body),
      ).timeout(_timeout);

      // [T6] 200 / 409 / 410 都把 body 解析後回傳
      if (response.statusCode == 200 ||
          response.statusCode == 409 ||
          response.statusCode == 410) {
        return jsonDecode(response.body) as Map<String, dynamic>;
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
      final response = await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/$id'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode({
          'status': MeasurementStatus.skipped.value,
          'measurement_notes': reason ?? '使用者跳過',
        }),
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('跳過測量失敗: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('跳過測量失敗: $e');
      rethrow;
    }
  }
  
  /// 更新任務狀態（不改變其他欄位）
  Future<void> updateTaskStatus(int id, MeasurementStatus status) async {
    try {
      await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/$id'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode({
          'status': status.value,
        }),
      ).timeout(_timeout);
    } catch (e) {
      debugPrint('更新任務狀態失敗: $e');
      rethrow;
    }
  }
  
  /// 將已完成的測量轉移到正式 tree_survey 表
  Future<Map<String, dynamic>> transferToTreeSurvey({
    required String sessionId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/pending-measurements/transfer'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode({
          'session_id': sessionId,
        }),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('轉移數據失敗: ${response.statusCode}');
      }
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
      final response = await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/session/$sessionId/project'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode({
          'project_area': projectArea,
          'project_code': projectCode,
          'project_name': projectName,
        }),
      ).timeout(_timeout);

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
      final response = await http.delete(
        Uri.parse('$_baseUrl/api/pending-measurements/session/$sessionId'),
        headers: ApiService.getAuthHeaders(),
      ).timeout(_timeout);

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
  }) async {
    try {
      // 1. 本地解析 BLE 數據
      final measurements = createFromBleData(
        bleData: bleData,
        projectArea: projectArea,
        projectCode: projectCode,
        projectName: projectName,
      );
      
      if (measurements.isEmpty) {
        return {
          'success': false,
          'message': '沒有有效的測量數據',
          'count': 0,
        };
      }
      
      // 2. 上傳到後端
      final result = await uploadPendingMeasurements(measurements);
      
      return {
        'success': true,
        'message': '成功儲存 ${measurements.length} 筆待測量記錄',
        'count': measurements.length,
        'sessionId': measurements.first.sessionId,
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
