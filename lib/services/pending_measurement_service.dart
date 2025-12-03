import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/pending_tree_measurement.dart';
import '../config/app_config.dart';
// BleDataProcessor used indirectly via parseCsvData results

/// 待測量樹木服務
/// 
/// 處理 VLGEO2 數據的解析、存儲和第二階段測量的管理
class PendingMeasurementService {
  // 使用 AppConfig 的動態 API URL
  String get _baseUrl => AppConfig().baseUrl.replaceAll('/api', '');
  
  /// 從 BLE 數據創建待測量記錄
  /// 
  /// [bleData] - BleDataProcessor.parseCsvData() 的結果
  /// [projectArea] - 專案區位
  /// [projectCode] - 專案代碼
  /// [projectName] - 專案名稱
  /// [createdBy] - 創建者 ID
  static List<PendingTreeMeasurement> createFromBleData({
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
        // 提取 VLGEO2 測量數據
        final metadata = record['metadata'] as Map<String, dynamic>? ?? {};
        
        final double lat = (record['lat'] as num?)?.toDouble() ?? 0;
        final double lon = (record['lon'] as num?)?.toDouble() ?? 0;
        final double height = (record['height'] as num?)?.toDouble() ?? 0;
        final double horizontalDistance = (metadata['horizontal_distance'] as num?)?.toDouble() ?? 0;
        final double slopeDistance = (metadata['slope_distance'] as num?)?.toDouble() ?? 0;
        final double azimuth = (metadata['azimuth'] as num?)?.toDouble() ?? 0;
        final double pitch = (metadata['pitch'] as num?)?.toDouble() ?? 0;
        final double? altitude = (metadata['altitude'] as num?)?.toDouble();
        
        // 跳過無效數據
        if (lat == 0 && lon == 0) continue;
        if (horizontalDistance <= 0) continue;
        
        // 計算測站位置 (反推)
        final stationPos = PendingTreeMeasurement.calculateStationPosition(
          treeLat: lat,
          treeLon: lon,
          horizontalDistance: horizontalDistance,
          azimuth: azimuth,
        );
        
        // 創建待測量記錄
        final pending = PendingTreeMeasurement(
          sessionId: sessionId,
          originalRecordId: record['id']?.toString(),
          projectArea: projectArea,
          projectCode: projectCode,
          projectName: projectName,
          treeHeight: height,
          treeLatitude: lat,
          treeLongitude: lon,
          stationLatitude: stationPos.lat,
          stationLongitude: stationPos.lon,
          horizontalDistance: horizontalDistance,
          slopeDistance: slopeDistance,
          azimuth: azimuth,
          pitch: pitch,
          altitude: altitude,
          status: MeasurementStatus.pending,
          createdAt: DateTime.now(),
          priority: _calculatePriority(horizontalDistance),
        );
        
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
  
  /// 上傳待測量記錄到後端
  Future<Map<String, dynamic>> uploadPendingMeasurements(
    List<PendingTreeMeasurement> measurements,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/pending-measurements/batch'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'measurements': measurements.map((m) => m.toJson()).toList(),
        }),
      );
      
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
      );
      
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
      
      final response = await http.get(uri);
      
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
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'measured_dbh_cm': dbhCm,
          'measurement_confidence': confidence,
          'measurement_method': method,
          'measurement_notes': notes,
          'status': MeasurementStatus.completed.value,
          'completed_at': DateTime.now().toIso8601String(),
        }),
      );
      
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
      await http.patch(
        Uri.parse('$_baseUrl/api/pending-measurements/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'status': MeasurementStatus.skipped.value,
          'measurement_notes': reason ?? '使用者跳過',
        }),
      );
    } catch (e) {
      debugPrint('跳過測量失敗: $e');
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'session_id': sessionId,
        }),
      );
      
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
