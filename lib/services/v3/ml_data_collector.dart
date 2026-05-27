/// V3 ML 數據收集服務
/// 
/// 核心設計原則：
/// 1. 不影響使用者操作 - 完全背景執行
/// 2. 全面收集 - 所有 V3 關鍵操作都記錄
/// 3. 安全儲存 - 本地暫存，後台匯出
/// 4. 數據完整性 - 包含所有相關上下文
/// 
/// 收集範圍：
/// - 碳計算修改（自動 vs 手動）
/// - AR 測量修改
/// - 樹種辨識修改
/// - 座標修正
/// - 任何欄位的自動值被手動覆蓋
/// 
/// 用途：
/// - 累積訓練數據優化模型
/// - 分析系統性誤差
/// - 發現需要優化的功能
library;

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_config.dart';

/// ML 訓練記錄類型
enum MLRecordType {
  /// 碳計算修改
  carbonCalculation,
  
  /// AR DBH 測量修改
  arMeasurement,
  
  /// 樹種辨識修改
  speciesIdentification,
  
  /// 座標修正
  coordinateCorrection,
  
  /// 一般欄位修改
  fieldModification,
  
  /// 資料衝突解決
  conflictResolution,
  
  /// 測站位置計算
  stationPositionCalculation,
}

/// ML 訓練記錄
class MLTrainingRecord {
  /// 記錄唯一 ID
  final String id;
  
  /// 記錄類型
  final MLRecordType recordType;
  
  /// 關聯的樹木 ID
  final String? treeId;
  
  /// 關聯的批次 ID
  final String? batchId;
  
  /// 時間戳
  final DateTime timestamp;
  
  /// 輸入參數（用於計算的原始數據）
  final Map<String, dynamic> inputParameters;
  
  /// 自動計算/識別的值
  final Map<String, dynamic> autoValues;
  
  /// 使用者最終輸入/確認的值
  final Map<String, dynamic> userValues;
  
  /// 差異分析
  final Map<String, dynamic> differenceAnalysis;
  
  /// 環境資訊
  final Map<String, dynamic> environment;
  
  /// 額外元數據
  final Map<String, dynamic> metadata;

  MLTrainingRecord({
    String? id,
    required this.recordType,
    this.treeId,
    this.batchId,
    DateTime? timestamp,
    required this.inputParameters,
    required this.autoValues,
    required this.userValues,
    Map<String, dynamic>? differenceAnalysis,
    Map<String, dynamic>? environment,
    Map<String, dynamic>? metadata,
  }) : id = id ?? _generateId(),
       timestamp = timestamp ?? DateTime.now(),
       differenceAnalysis = differenceAnalysis ?? {},
       environment = environment ?? {},
       metadata = metadata ?? {};

  static String _generateId() {
    final now = DateTime.now();
    final random = math.Random();
    return 'ml_${now.millisecondsSinceEpoch}_${random.nextInt(10000)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'record_type': recordType.name,
    'tree_id': treeId,
    'batch_id': batchId,
    'timestamp': timestamp.toIso8601String(),
    'input_parameters': inputParameters,
    'auto_values': autoValues,
    'user_values': userValues,
    'difference_analysis': differenceAnalysis,
    'environment': environment,
    'metadata': metadata,
  };

  factory MLTrainingRecord.fromJson(Map<String, dynamic> json) {
    return MLTrainingRecord(
      id: json['id'],
      recordType: MLRecordType.values.firstWhere(
        (e) => e.name == json['record_type'],
        orElse: () => MLRecordType.fieldModification,
      ),
      treeId: json['tree_id'],
      batchId: json['batch_id'],
      timestamp: DateTime.parse(json['timestamp']),
      inputParameters: Map<String, dynamic>.from(json['input_parameters'] ?? {}),
      autoValues: Map<String, dynamic>.from(json['auto_values'] ?? {}),
      userValues: Map<String, dynamic>.from(json['user_values'] ?? {}),
      differenceAnalysis: Map<String, dynamic>.from(json['difference_analysis'] ?? {}),
      environment: Map<String, dynamic>.from(json['environment'] ?? {}),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }
}

/// V3 ML 數據收集服務
/// 
/// 使用方式：
/// ```dart
/// // 記錄碳計算修改
/// await MLDataCollector.recordCarbonModification(
///   treeId: '123',
///   dbhCm: 25.0,
///   autoCalculatedStorage: 150.5,
///   userModifiedStorage: 145.0,
/// );
/// 
/// // 匯出數據（僅後台管理）
/// final csv = await MLDataCollector.exportToCsv();
/// ```
class MLDataCollector {
  static const String _storageKey = 'v3_ml_training_data';
  static const int _maxLocalRecords = 2000;
  
  // ========================================
  // 核心記錄方法
  // ========================================
  
  /// 記錄碳計算修改
  /// 
  /// 當使用者關閉自動計算並手動輸入碳儲存量/年碳吸存量時調用
  static Future<void> recordCarbonModification({
    required String treeId,
    String? speciesName,
    required double dbhCm,
    double? treeHeightM,
    required double autoCalculatedStorage,
    required double userModifiedStorage,
    required double autoCalculatedSequestration,
    required double userModifiedSequestration,
    Map<String, dynamic>? metadata,
  }) async {
    // 計算差異
    final storageDiff = userModifiedStorage - autoCalculatedStorage;
    final sequestrationDiff = userModifiedSequestration - autoCalculatedSequestration;
    final storagePercentDiff = autoCalculatedStorage != 0 
        ? (storageDiff / autoCalculatedStorage * 100) 
        : 0.0;
    final sequestrationPercentDiff = autoCalculatedSequestration != 0 
        ? (sequestrationDiff / autoCalculatedSequestration * 100) 
        : 0.0;

    final record = MLTrainingRecord(
      recordType: MLRecordType.carbonCalculation,
      treeId: treeId,
      inputParameters: {
        'dbh_cm': dbhCm,
        'tree_height_m': treeHeightM,
        'species_name': speciesName,
      },
      autoValues: {
        'carbon_storage_kg': autoCalculatedStorage,
        'carbon_sequestration_per_year_kg': autoCalculatedSequestration,
      },
      userValues: {
        'carbon_storage_kg': userModifiedStorage,
        'carbon_sequestration_per_year_kg': userModifiedSequestration,
      },
      differenceAnalysis: {
        'storage_absolute_diff': storageDiff,
        'storage_percent_diff': storagePercentDiff,
        'sequestration_absolute_diff': sequestrationDiff,
        'sequestration_percent_diff': sequestrationPercentDiff,
      },
      metadata: metadata ?? {},
    );

    await _saveRecord(record);
    debugPrint('[MLDataCollector] 碳計算修改: $autoCalculatedStorage → $userModifiedStorage (${storagePercentDiff.toStringAsFixed(1)}%)');
  }
  
  /// 記錄 AR 測量修改
  /// 
  /// 當使用者修改 AR 自動測量的 DBH 值時調用
  static Future<void> recordARMeasurementModification({
    required String treeId,
    required String referenceObjectType,
    required double referenceActualSizeCm,
    int? referencePixelWidth,
    int? treePixelWidth,
    double? distanceToTreeM,
    required double autoMeasuredDbh,
    required double userModifiedDbh,
    double? confidence,
    String? imagePath,
    Map<String, dynamic>? metadata,
  }) async {
    final diff = userModifiedDbh - autoMeasuredDbh;
    final percentDiff = autoMeasuredDbh != 0 ? (diff / autoMeasuredDbh * 100) : 0.0;

    final record = MLTrainingRecord(
      recordType: MLRecordType.arMeasurement,
      treeId: treeId,
      inputParameters: {
        'reference_object_type': referenceObjectType,
        'reference_actual_size_cm': referenceActualSizeCm,
        'reference_pixel_width': referencePixelWidth,
        'tree_pixel_width': treePixelWidth,
        'distance_to_tree_m': distanceToTreeM,
      },
      autoValues: {
        'dbh_cm': autoMeasuredDbh,
        'confidence': confidence,
      },
      userValues: {
        'dbh_cm': userModifiedDbh,
      },
      differenceAnalysis: {
        'absolute_diff': diff,
        'percent_diff': percentDiff,
      },
      metadata: {
        'image_path': imagePath,
        ...?metadata,
      },
    );

    await _saveRecord(record);
    debugPrint('[MLDataCollector] AR測量修改: $autoMeasuredDbh → $userModifiedDbh (${percentDiff.toStringAsFixed(1)}%)');
  }
  
  /// 記錄樹種辨識修改
  /// 
  /// 當使用者修改 AI 辨識的樹種時調用
  static Future<void> recordSpeciesModification({
    required String treeId,
    required String autoIdentifiedSpeciesId,
    required String autoIdentifiedSpeciesName,
    required String userSelectedSpeciesId,
    required String userSelectedSpeciesName,
    double? confidence,
    List<Map<String, dynamic>>? topPredictions,
    String? imagePath,
    Map<String, dynamic>? metadata,
  }) async {
    final record = MLTrainingRecord(
      recordType: MLRecordType.speciesIdentification,
      treeId: treeId,
      inputParameters: {
        'image_path': imagePath,
      },
      autoValues: {
        'species_id': autoIdentifiedSpeciesId,
        'species_name': autoIdentifiedSpeciesName,
        'confidence': confidence,
        'top_predictions': topPredictions,
      },
      userValues: {
        'species_id': userSelectedSpeciesId,
        'species_name': userSelectedSpeciesName,
      },
      differenceAnalysis: {
        'was_correct': autoIdentifiedSpeciesId == userSelectedSpeciesId,
        'was_in_top_predictions': topPredictions?.any(
          (p) => p['species_id'] == userSelectedSpeciesId
        ) ?? false,
      },
      metadata: metadata ?? {},
    );

    await _saveRecord(record);
    debugPrint('[MLDataCollector] 樹種辨識修改: $autoIdentifiedSpeciesName → $userSelectedSpeciesName');
  }
  
  /// 記錄座標修正
  /// 
  /// 當使用者手動調整 GPS 座標時調用
  static Future<void> recordCoordinateCorrection({
    required String treeId,
    required double originalLat,
    required double originalLon,
    required double correctedLat,
    required double correctedLon,
    String? correctionReason,
    double? gpsAccuracy,
    Map<String, dynamic>? metadata,
  }) async {
    // 計算位移距離
    final distance = _calculateDistance(
      originalLat, originalLon, 
      correctedLat, correctedLon
    );

    final record = MLTrainingRecord(
      recordType: MLRecordType.coordinateCorrection,
      treeId: treeId,
      inputParameters: {
        'gps_accuracy': gpsAccuracy,
      },
      autoValues: {
        'lat': originalLat,
        'lon': originalLon,
      },
      userValues: {
        'lat': correctedLat,
        'lon': correctedLon,
      },
      differenceAnalysis: {
        'distance_meters': distance,
        'lat_diff': correctedLat - originalLat,
        'lon_diff': correctedLon - originalLon,
      },
      metadata: {
        'correction_reason': correctionReason,
        ...?metadata,
      },
    );

    await _saveRecord(record);
    debugPrint('[MLDataCollector] 座標修正: ${distance.toStringAsFixed(2)}m 位移');
  }
  
  /// 記錄一般欄位修改
  /// 
  /// 通用方法，用於記錄任何欄位的自動值被手動覆蓋
  static Future<void> recordFieldModification({
    required String treeId,
    required String fieldName,
    required dynamic autoValue,
    required dynamic userValue,
    String? modificationReason,
    Map<String, dynamic>? inputParameters,
    Map<String, dynamic>? metadata,
  }) async {
    // 計算差異（如果是數值）
    Map<String, dynamic> diffAnalysis = {};
    if (autoValue is num && userValue is num) {
      final diff = userValue - autoValue;
      final percentDiff = autoValue != 0 ? (diff / autoValue * 100) : 0.0;
      diffAnalysis = {
        'absolute_diff': diff,
        'percent_diff': percentDiff,
      };
    } else {
      diffAnalysis = {
        'value_changed': autoValue != userValue,
      };
    }

    final record = MLTrainingRecord(
      recordType: MLRecordType.fieldModification,
      treeId: treeId,
      inputParameters: inputParameters ?? {},
      autoValues: {
        fieldName: autoValue,
      },
      userValues: {
        fieldName: userValue,
      },
      differenceAnalysis: diffAnalysis,
      metadata: {
        'field_name': fieldName,
        'modification_reason': modificationReason,
        ...?metadata,
      },
    );

    await _saveRecord(record);
    debugPrint('[MLDataCollector] 欄位修改 $fieldName: $autoValue → $userValue');
  }

  /// 記錄資料衝突解決
  /// 
  /// 當系統自動解決資料衝突時調用
  static Future<void> recordConflictResolution({
    String? treeId,
    required double lat,
    required double lon,
    required int recordCount,
    required Map<String, List<dynamic>> conflictingFields,
    required Map<String, dynamic> keptRecord,
    required String resolutionStrategy,
    Map<String, dynamic>? metadata,
  }) async {
    final record = MLTrainingRecord(
      recordType: MLRecordType.conflictResolution,
      treeId: treeId,
      inputParameters: {
        'lat': lat,
        'lon': lon,
        'record_count': recordCount,
      },
      autoValues: {
        'conflicting_fields': conflictingFields,
      },
      userValues: {
        'kept_record': keptRecord,
      },
      differenceAnalysis: {
        'field_count': conflictingFields.length,
        'resolution_strategy': resolutionStrategy,
      },
      metadata: metadata ?? {},
    );

    await _saveRecord(record);
    debugPrint('[MLDataCollector] 衝突解決: ${conflictingFields.length} 個欄位衝突');
  }

  /// 記錄測站位置計算
  /// 
  /// 記錄 VLGEO2 測站位置計算結果，用於驗證公式準確性
  static Future<void> recordStationPositionCalculation({
    String? batchId,
    required double treeLat,
    required double treeLon,
    required double horizontalDistance,
    required double azimuth,
    required double calculatedStationLat,
    required double calculatedStationLon,
    double? actualStationLat,
    double? actualStationLon,
    Map<String, dynamic>? metadata,
  }) async {
    Map<String, dynamic> diffAnalysis = {};
    
    if (actualStationLat != null && actualStationLon != null) {
      final error = _calculateDistance(
        calculatedStationLat, calculatedStationLon,
        actualStationLat, actualStationLon,
      );
      diffAnalysis = {
        'position_error_meters': error,
        'has_ground_truth': true,
      };
    } else {
      diffAnalysis = {
        'has_ground_truth': false,
      };
    }

    final record = MLTrainingRecord(
      recordType: MLRecordType.stationPositionCalculation,
      batchId: batchId,
      inputParameters: {
        'tree_lat': treeLat,
        'tree_lon': treeLon,
        'horizontal_distance': horizontalDistance,
        'azimuth': azimuth,
      },
      autoValues: {
        'calculated_station_lat': calculatedStationLat,
        'calculated_station_lon': calculatedStationLon,
      },
      userValues: {
        'actual_station_lat': actualStationLat,
        'actual_station_lon': actualStationLon,
      },
      differenceAnalysis: diffAnalysis,
      metadata: metadata ?? {},
    );

    await _saveRecord(record);
  }

  // ========================================
  // 數據管理方法
  // ========================================

  /// 保存記錄到本地
  static Future<void> _saveRecord(MLTrainingRecord record) async {
    if (!AppConfig.enableMlCorrectionUpload) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final existingData = prefs.getString(_storageKey);
      
      List<dynamic> records = [];
      if (existingData != null) {
        records = jsonDecode(existingData) as List<dynamic>;
      }
      
      records.add(record.toJson());
      
      // 限制本地儲存數量
      if (records.length > _maxLocalRecords) {
        records = records.sublist(records.length - _maxLocalRecords);
      }
      
      await prefs.setString(_storageKey, jsonEncode(records));
    } catch (e) {
      debugPrint('[MLDataCollector] 保存記錄失敗: $e');
    }
  }

  /// 獲取本地儲存的所有記錄
  static Future<List<MLTrainingRecord>> getLocalRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      
      if (data == null) return [];
      
      final List<dynamic> jsonList = jsonDecode(data);
      return jsonList
          .map((json) => MLTrainingRecord.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('[MLDataCollector] 讀取記錄失敗: $e');
      return [];
    }
  }

  /// 獲取記錄統計
  static Future<MLDataStatistics> getStatistics() async {
    final records = await getLocalRecords();
    
    final typeCount = <MLRecordType, int>{};
    final avgDifferences = <String, double>{};
    final modifications = <String, List<double>>{};
    
    for (final record in records) {
      // 統計類型
      typeCount[record.recordType] = (typeCount[record.recordType] ?? 0) + 1;
      
      // 收集差異數據
      final diff = record.differenceAnalysis;
      if (diff.containsKey('percent_diff')) {
        final key = '${record.recordType.name}_percent_diff';
        modifications.putIfAbsent(key, () => []);
        modifications[key]!.add((diff['percent_diff'] as num).toDouble());
      }
      if (diff.containsKey('storage_percent_diff')) {
        modifications.putIfAbsent('carbon_storage_percent_diff', () => []);
        modifications['carbon_storage_percent_diff']!.add(
          (diff['storage_percent_diff'] as num).toDouble()
        );
      }
    }
    
    // 計算平均值
    for (final entry in modifications.entries) {
      if (entry.value.isNotEmpty) {
        avgDifferences[entry.key] = 
            entry.value.reduce((a, b) => a + b) / entry.value.length;
      }
    }
    
    return MLDataStatistics(
      totalRecords: records.length,
      recordsByType: typeCount,
      averageDifferences: avgDifferences,
      oldestRecord: records.isNotEmpty ? records.first.timestamp : null,
      newestRecord: records.isNotEmpty ? records.last.timestamp : null,
    );
  }

  /// 匯出數據為 JSON
  static Future<String> exportToJson() async {
    final records = await getLocalRecords();
    return const JsonEncoder.withIndent('  ')
        .convert(records.map((r) => r.toJson()).toList());
  }

  /// 匯出數據為 CSV（僅後台管理使用）
  static Future<String> exportToCsv() async {
    final records = await getLocalRecords();
    
    if (records.isEmpty) return '';
    
    final buffer = StringBuffer();
    
    // CSV 標題
    buffer.writeln(
      'id,type,tree_id,batch_id,timestamp,'
      'input_params,auto_values,user_values,'
      'diff_analysis,metadata'
    );
    
    // CSV 內容
    for (final record in records) {
      buffer.writeln([
        record.id,
        record.recordType.name,
        record.treeId ?? '',
        record.batchId ?? '',
        record.timestamp.toIso8601String(),
        _escapeCsvField(jsonEncode(record.inputParameters)),
        _escapeCsvField(jsonEncode(record.autoValues)),
        _escapeCsvField(jsonEncode(record.userValues)),
        _escapeCsvField(jsonEncode(record.differenceAnalysis)),
        _escapeCsvField(jsonEncode(record.metadata)),
      ].join(','));
    }
    
    return buffer.toString();
  }

  /// 清除所有本地記錄
  static Future<void> clearLocalRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    debugPrint('[MLDataCollector] 已清除所有本地記錄');
  }

  /// 獲取指定類型的記錄
  static Future<List<MLTrainingRecord>> getRecordsByType(MLRecordType type) async {
    final records = await getLocalRecords();
    return records.where((r) => r.recordType == type).toList();
  }

  // ========================================
  // 輔助方法
  // ========================================

  /// 計算兩點距離（公尺）
  static double _calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double R = 6371000;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = 
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;

  /// 轉義 CSV 欄位
  static String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
}

/// ML 數據統計
class MLDataStatistics {
  final int totalRecords;
  final Map<MLRecordType, int> recordsByType;
  final Map<String, double> averageDifferences;
  final DateTime? oldestRecord;
  final DateTime? newestRecord;

  MLDataStatistics({
    required this.totalRecords,
    required this.recordsByType,
    required this.averageDifferences,
    this.oldestRecord,
    this.newestRecord,
  });

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('ML 數據統計:');
    buffer.writeln('  總記錄數: $totalRecords');
    buffer.writeln('  按類型:');
    for (final entry in recordsByType.entries) {
      buffer.writeln('    - ${entry.key.name}: ${entry.value}');
    }
    if (averageDifferences.isNotEmpty) {
      buffer.writeln('  平均差異:');
      for (final entry in averageDifferences.entries) {
        buffer.writeln('    - ${entry.key}: ${entry.value.toStringAsFixed(2)}%');
      }
    }
    if (oldestRecord != null) {
      buffer.writeln('  最舊記錄: $oldestRecord');
    }
    if (newestRecord != null) {
      buffer.writeln('  最新記錄: $newestRecord');
    }
    return buffer.toString();
  }
}
