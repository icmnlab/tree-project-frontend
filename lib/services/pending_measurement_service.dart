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
  /// [projectArea] - 專案區位
  /// [projectCode] - 專案代碼
  /// [projectName] - 專案名稱
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
        
        debugPrint('━━━ 記錄 ID=${record['id']} (${hasGps ? "GPS" : "無GPS"}) ━━━');
        debugPrint('  測站 GPS: ($lat, $lon)');
        debugPrint('  HD=${horizontalDistance}m  AZ=${azimuth}°  H=${height}m');
        
        double treeLat = 0;
        double treeLon = 0;
        
        if (hasGps) {
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
        } else {
          debugPrint('  無 GPS，跳過位置推算');
        }
        
        final pending = PendingTreeMeasurement(
          sessionId: sessionId,
          originalRecordId: record['id']?.toString(),
          projectArea: projectArea,
          projectCode: projectCode,
          projectName: projectName,
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
  Future<Map<String, dynamic>> updateMeasurement({
    required int id,
    required double dbhCm,
    required double confidence,
    required String method,
    String? notes,
    String? speciesName,
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

      final response = await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/$id'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: jsonEncode(body),
      ).timeout(_timeout);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
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
  
  /// 更新整個 session 的專案資訊
  Future<void> updateSessionProject({
    required String sessionId,
    required String projectArea,
    String? projectCode,
    String? projectName,
  }) async {
    final trees = await getPendingTrees(sessionId: sessionId);
    final errors = <String>[];
    for (final tree in trees) {
      if (tree.id == null) continue;
      try {
        final response = await http.patch(
          Uri.parse('$_baseUrl/api/pending-measurements/${tree.id}'),
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
          errors.add('ID ${tree.id}: HTTP ${response.statusCode}');
        }
      } catch (e) {
        errors.add('ID ${tree.id}: $e');
      }
    }
    if (errors.isNotEmpty) {
      throw Exception('部分更新失敗: ${errors.join(", ")}');
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
