/// V3 專案邊界服務
/// 
/// 功能：
/// 1. 從後端獲取專案邊界資料
/// 2. 本地快取邊界資料
/// 3. 檢查座標是否在特定專案邊界內（本地計算）
/// 4. 根據座標查找對應的專案（本地計算）
/// 
/// 使用情境：
/// - 新增樹木時驗證座標是否在專案邊界內
/// - BLE 批次匯入時自動匹配專案名稱
/// - 地圖上顯示專案邊界多邊形

import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../api_service.dart';

/// 專案邊界資料模型
class ProjectBoundary {
  final int? id;
  final String projectName;
  final String? projectCode;
  final String? projectArea;
  final List<List<double>> coordinates; // [[lat, lng], ...]
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ProjectBoundary({
    this.id,
    required this.projectName,
    this.projectCode,
    this.projectArea,
    required this.coordinates,
    this.createdAt,
    this.updatedAt,
  });

  factory ProjectBoundary.fromJson(Map<String, dynamic> json) {
    List<List<double>> coords = [];
    
    if (json['boundary_coordinates'] != null) {
      final rawCoords = json['boundary_coordinates'];
      if (rawCoords is List) {
        for (var coord in rawCoords) {
          if (coord is List && coord.length >= 2) {
            coords.add([
              (coord[0] as num).toDouble(),
              (coord[1] as num).toDouble(),
            ]);
          }
        }
      }
    }

    return ProjectBoundary(
      id: json['id'] as int?,
      projectName: json['project_name'] as String,
      projectCode: json['project_code'] as String?,
      projectArea: json['project_area'] as String?,
      coordinates: coords,
      createdAt: json['created_at'] != null 
          ? DateTime.tryParse(json['created_at']) 
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.tryParse(json['updated_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'projectName': projectName,
      'projectCode': projectCode,
      'projectArea': projectArea,
      'coordinates': coordinates,
    };
  }
}

/// 座標匹配結果
class CoordinateMatchResult {
  final bool matched;
  final String? projectName;
  final String? projectCode;
  final String? projectArea;
  final bool multipleMatches;
  final List<ProjectBoundary>? allMatches;
  final String? reason;

  CoordinateMatchResult({
    required this.matched,
    this.projectName,
    this.projectCode,
    this.projectArea,
    this.multipleMatches = false,
    this.allMatches,
    this.reason,
  });
}

/// 專案邊界驗證結果
class BoundaryValidationResult {
  final bool isValid;
  final bool hasBoundary;
  final String message;

  BoundaryValidationResult({
    required this.isValid,
    required this.hasBoundary,
    required this.message,
  });
}

/// 專案邊界狀態（metadata vs spatial）
class ProjectBoundaryStatus {
  final String projectName;
  final bool hasBoundary;
  final String boundaryState; // none | manual
  final int treeCountWithGps;
  final bool canSuggest;
  final String? suggestBlockedReason;

  ProjectBoundaryStatus({
    required this.projectName,
    required this.hasBoundary,
    required this.boundaryState,
    required this.treeCountWithGps,
    required this.canSuggest,
    this.suggestBlockedReason,
  });

  factory ProjectBoundaryStatus.fromJson(Map<String, dynamic> json) {
    return ProjectBoundaryStatus(
      projectName: json['projectName'] as String? ?? '',
      hasBoundary: json['hasBoundary'] == true,
      boundaryState: json['boundaryState'] as String? ?? 'none',
      treeCountWithGps: (json['treeCountWithGps'] as num?)?.toInt() ?? 0,
      canSuggest: json['canSuggest'] == true,
      suggestBlockedReason: json['suggestBlockedReason'] as String?,
    );
  }
}

/// 建議邊界預覽結果（主群集 convex hull，outlier 已排除）
class BoundarySuggestResult {
  final bool success;
  final String? code;
  final String message;
  final List<List<double>> coordinates;
  final Map<String, dynamic>? stats;
  final List<String> warnings;

  BoundarySuggestResult({
    required this.success,
    this.code,
    required this.message,
    this.coordinates = const [],
    this.stats,
    this.warnings = const [],
  });

  factory BoundarySuggestResult.fromJson(Map<String, dynamic> json) {
    final coords = <List<double>>[];
    final raw = json['coordinates'];
    if (raw is List) {
      for (final c in raw) {
        if (c is List && c.length >= 2) {
          coords.add([(c[0] as num).toDouble(), (c[1] as num).toDouble()]);
        }
      }
    }
    final warn = json['warnings'];
    return BoundarySuggestResult(
      success: json['success'] == true,
      code: json['code'] as String?,
      message: json['message'] as String? ?? '',
      coordinates: coords,
      stats: json['stats'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['stats'] as Map)
          : null,
      warnings: warn is List
          ? warn.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// 專案邊界服務
class ProjectBoundaryService {
  static final ProjectBoundaryService _instance = ProjectBoundaryService._internal();
  factory ProjectBoundaryService() => _instance;
  ProjectBoundaryService._internal();

  // 快取的邊界資料
  List<ProjectBoundary> _cachedBoundaries = [];
  DateTime? _lastFetchTime;
  
  // 快取有效期（5 分鐘）
  static const Duration _cacheValidity = Duration(minutes: 5);

  /// 獲取所有專案邊界（帶快取）
  Future<List<ProjectBoundary>> getAllBoundaries({bool forceRefresh = false}) async {
    // 檢查快取是否有效
    if (!forceRefresh && _cachedBoundaries.isNotEmpty && _lastFetchTime != null) {
      final elapsed = DateTime.now().difference(_lastFetchTime!);
      if (elapsed < _cacheValidity) {
        debugPrint('[ProjectBoundaryService] 使用快取的邊界資料 (${_cachedBoundaries.length} 個)');
        return _cachedBoundaries;
      }
    }

    try {
      final response = await ApiService.get('/project-boundaries');
      
      if (response['success'] == true && response['data'] != null) {
        _cachedBoundaries = (response['data'] as List)
            .map((json) => ProjectBoundary.fromJson(json))
            .toList();
        _lastFetchTime = DateTime.now();
        
        debugPrint('[ProjectBoundaryService] 已獲取 ${_cachedBoundaries.length} 個專案邊界');
        return _cachedBoundaries;
      }
      
      return [];
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 獲取邊界錯誤: $e');
      // 返回快取資料（即使過期）
      return _cachedBoundaries;
    }
  }

  /// 獲取特定專案的邊界
  Future<ProjectBoundary?> getBoundary(String projectName) async {
    try {
      final encoded = Uri.encodeComponent(projectName);
      final response = await ApiService.get('/project-boundaries/$encoded');
      
      if (response['success'] == true && response['data'] != null) {
        return ProjectBoundary.fromJson(response['data']);
      }
      
      return null;
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 獲取專案邊界錯誤: $e');
      return null;
    }
  }

  /// 快取中是否已有某專案邊界
  bool hasBoundaryForProject(String projectName) {
    return _cachedBoundaries.any((b) => b.projectName == projectName);
  }

  /// 取得專案邊界狀態（有無 polygon、可否建議邊界）
  Future<ProjectBoundaryStatus?> getProjectBoundaryStatus(String projectName) async {
    try {
      final encoded = Uri.encodeComponent(projectName);
      final response = await ApiService.get('/project-boundaries/status/$encoded');
      if (response['success'] == true) {
        return ProjectBoundaryStatus.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 邊界狀態錯誤: $e');
      return null;
    }
  }

  /// 從既有 tree_survey GPS 產生建議邊界預覽（不寫入 DB；outlier 排除）
  Future<BoundarySuggestResult> suggestBoundaryFromTrees({
    required String projectName,
    int? bufferM,
    int? maxSpanM,
  }) async {
    try {
      final body = <String, dynamic>{'projectName': projectName};
      if (bufferM != null) body['bufferM'] = bufferM;
      if (maxSpanM != null) body['maxSpanM'] = maxSpanM;

      final response = await ApiService.post('/project-boundaries/suggest', body);
      return BoundarySuggestResult.fromJson(response);
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 建議邊界錯誤: $e');
      return BoundarySuggestResult(
        success: false,
        message: '產生建議邊界失敗: $e',
      );
    }
  }

  /// 儲存專案邊界
  Future<bool> saveBoundary(ProjectBoundary boundary) async {
    try {
      final response = await ApiService.post('/project-boundaries', boundary.toJson());
      
      if (response['success'] == true) {
        // 清除快取以便下次重新獲取
        _cachedBoundaries.clear();
        _lastFetchTime = null;
        debugPrint('[ProjectBoundaryService] 邊界已儲存: ${boundary.projectName}');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 儲存邊界錯誤: $e');
      return false;
    }
  }

  /// 刪除專案邊界
  Future<bool> deleteBoundary(String projectName) async {
    try {
      final response = await ApiService.delete('/project-boundaries/$projectName');
      
      if (response['success'] == true) {
        // 清除快取
        _cachedBoundaries.removeWhere((b) => b.projectName == projectName);
        debugPrint('[ProjectBoundaryService] 邊界已刪除: $projectName');
        return true;
      }
      
      return false;
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 刪除邊界錯誤: $e');
      return false;
    }
  }

  /// 檢查座標是否在特定專案邊界內（本地計算）
  /// 
  /// 返回值：
  /// - isValid: true 如果可以加入該專案
  /// - hasBoundary: 該專案是否有設定邊界
  /// - message: 說明訊息
  BoundaryValidationResult validateCoordinateForProject({
    required String projectName,
    required double lat,
    required double lng,
  }) {
    // 查找該專案的邊界
    final boundary = _cachedBoundaries
        .where((b) => b.projectName == projectName)
        .firstOrNull;

    if (boundary == null) {
      // 專案沒有邊界，不受座標限制
      return BoundaryValidationResult(
        isValid: true,
        hasBoundary: false,
        message: '該專案尚未設定邊界，不受座標限制',
      );
    }

    // 檢查座標是否在多邊形內
    final isInside = _isPointInPolygon(lat, lng, boundary.coordinates);

    return BoundaryValidationResult(
      isValid: isInside,
      hasBoundary: true,
      message: isInside 
          ? '座標在專案邊界內' 
          : '座標不在「$projectName」的邊界內，無法加入此專案',
    );
  }

  /// 檢查座標是否在特定專案邊界內（使用後端 API）
  Future<BoundaryValidationResult> validateCoordinateForProjectAsync({
    required String projectName,
    required double lat,
    required double lng,
  }) async {
    try {
      final response = await ApiService.post('/project-boundaries/check', {
        'projectName': projectName,
        'lat': lat,
        'lng': lng,
      });

      if (response['success'] == true) {
        return BoundaryValidationResult(
          isValid: response['isInside'] == true,
          hasBoundary: response['hasBoundary'] == true,
          message: response['message'] ?? '',
        );
      }

      return BoundaryValidationResult(
        isValid: false,
        hasBoundary: true,
        message: '無法驗證邊界，請檢查網路後重試',
      );
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 座標驗證錯誤: $e');
      return BoundaryValidationResult(
        isValid: false,
        hasBoundary: true,
        message: '邊界驗證失敗: $e',
      );
    }
  }

  /// 先刷新快取再本地驗證（BLE / 手動輸入建議使用）
  Future<BoundaryValidationResult> validateCoordinateForProjectFresh({
    required String projectName,
    required double lat,
    required double lng,
    bool preferServer = true,
  }) async {
    await getAllBoundaries(forceRefresh: true);
    if (preferServer) {
      return validateCoordinateForProjectAsync(
        projectName: projectName,
        lat: lat,
        lng: lng,
      );
    }
    return validateCoordinateForProject(
      projectName: projectName,
      lat: lat,
      lng: lng,
    );
  }

  /// 根據座標查找對應的專案（本地計算）
  CoordinateMatchResult findProjectByCoordinate({
    required double lat,
    required double lng,
  }) {
    if (_cachedBoundaries.isEmpty) {
      return CoordinateMatchResult(
        matched: false,
        reason: '尚未載入專案邊界資料',
      );
    }

    final matchingBoundaries = <ProjectBoundary>[];

    for (final boundary in _cachedBoundaries) {
      if (_isPointInPolygon(lat, lng, boundary.coordinates)) {
        matchingBoundaries.add(boundary);
      }
    }

    if (matchingBoundaries.isEmpty) {
      return CoordinateMatchResult(
        matched: false,
        reason: '座標不在任何專案邊界內',
      );
    }

    if (matchingBoundaries.length == 1) {
      return CoordinateMatchResult(
        matched: true,
        projectName: matchingBoundaries[0].projectName,
        projectCode: matchingBoundaries[0].projectCode,
        projectArea: matchingBoundaries[0].projectArea,
      );
    }

    // 多個匹配
    return CoordinateMatchResult(
      matched: true,
      projectName: matchingBoundaries[0].projectName,
      projectCode: matchingBoundaries[0].projectCode,
      projectArea: matchingBoundaries[0].projectArea,
      multipleMatches: true,
      allMatches: matchingBoundaries,
    );
  }

  /// 批次匹配座標到專案（用於 BLE 匯入）
  List<CoordinateMatchResult> batchMatchCoordinates(List<Map<String, double>> coordinates) {
    return coordinates.map((coord) {
      final lat = coord['lat'];
      final lng = coord['lng'];
      
      if (lat == null || lng == null) {
        return CoordinateMatchResult(
          matched: false,
          reason: '座標缺失',
        );
      }

      return findProjectByCoordinate(lat: lat, lng: lng);
    }).toList();
  }

  /// 批次匹配座標到專案（使用後端 API）
  Future<List<Map<String, dynamic>>> batchMatchCoordinatesAsync(
    List<Map<String, dynamic>> trees,
  ) async {
    try {
      final response = await ApiService.post('/project-boundaries/batch_match', {
        'trees': trees,
      });

      if (response['success'] == true && response['results'] != null) {
        return (response['results'] as List).cast<Map<String, dynamic>>();
      }

      return [];
    } catch (e) {
      debugPrint('[ProjectBoundaryService] 批次匹配錯誤: $e');
      return [];
    }
  }

  /// 檢查點是否在多邊形內（射線演算法）
  bool _isPointInPolygon(double lat, double lng, List<List<double>> polygon) {
    if (polygon.length < 3) return false;

    int intersections = 0;
    final n = polygon.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      
      final y1 = polygon[i][0]; // lat
      final x1 = polygon[i][1]; // lng
      final y2 = polygon[j][0];
      final x2 = polygon[j][1];

      // 射線向右延伸
      if (((y1 > lat) != (y2 > lat)) &&
          (lng < (x2 - x1) * (lat - y1) / (y2 - y1) + x1)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }

  /// 計算多邊形面積（公頃）
  double calculatePolygonArea(List<List<double>> coordinates) {
    if (coordinates.length < 3) return 0;

    // 使用球面多邊形面積公式（簡化版）
    double area = 0;
    final n = coordinates.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      
      final lat1 = coordinates[i][0] * math.pi / 180;
      final lng1 = coordinates[i][1] * math.pi / 180;
      final lat2 = coordinates[j][0] * math.pi / 180;
      final lng2 = coordinates[j][1] * math.pi / 180;

      area += (lng2 - lng1) * (2 + math.sin(lat1) + math.sin(lat2));
    }

    // 地球半徑 (km)
    const double earthRadius = 6371;
    area = area.abs() * earthRadius * earthRadius / 2;

    // 轉換為公頃 (1 km² = 100 公頃)
    return area * 100;
  }

  /// 計算多邊形中心點
  Map<String, double> calculatePolygonCenter(List<List<double>> coordinates) {
    if (coordinates.isEmpty) {
      return {'lat': 0, 'lng': 0};
    }

    double sumLat = 0;
    double sumLng = 0;

    for (final coord in coordinates) {
      sumLat += coord[0];
      sumLng += coord[1];
    }

    return {
      'lat': sumLat / coordinates.length,
      'lng': sumLng / coordinates.length,
    };
  }

  /// 清除快取
  void clearCache() {
    _cachedBoundaries.clear();
    _lastFetchTime = null;
    debugPrint('[ProjectBoundaryService] 快取已清除');
  }

  /// 獲取快取的邊界數量
  int get cachedBoundaryCount => _cachedBoundaries.length;

  /// 檢查是否有快取
  bool get hasCache => _cachedBoundaries.isNotEmpty;
}
