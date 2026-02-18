/// V3 數據過濾服務
/// 
/// 功能：
/// 1. 不完整資料過濾 - 標記缺少必要欄位的記錄
/// 2. 重複資料過濾 - 比對經緯度（考量南北半球及東西半球後的絕對座標）
/// 3. 衝突檢測 - 座標相同但其他欄位不同的處理
/// 
/// 設計原則：
/// - 保留最後一筆重複資料
/// - 經緯度比對使用處理後的座標值（已按 N/S, E/W 給予正負號）
/// - 提供過濾統計報告
/// - 對數據正確性影響為 0（不會錯誤過濾有效數據）
library;

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// 資料過濾結果
class DataFilterResult {
  /// 過濾後的有效資料
  final List<Map<String, dynamic>> validRecords;
  
  /// 被標記為不完整的資料
  final List<Map<String, dynamic>> incompleteRecords;
  
  /// 被過濾的重複資料（完全相同）
  final List<Map<String, dynamic>> duplicateRecords;
  
  /// 衝突資料（座標相同但其他欄位不同）
  final List<DataConflict> conflicts;
  
  /// 統計資訊
  final DataFilterStats stats;

  DataFilterResult({
    required this.validRecords,
    required this.incompleteRecords,
    required this.duplicateRecords,
    required this.conflicts,
    required this.stats,
  });
}

/// 資料衝突記錄
class DataConflict {
  /// 衝突群組中的所有記錄
  final List<Map<String, dynamic>> records;
  
  /// 共同座標
  final double lat;
  final double lon;
  
  /// 不一致的欄位
  final Map<String, List<dynamic>> conflictingFields;
  
  /// 最終保留的記錄（最後一筆）
  final Map<String, dynamic> keptRecord;
  
  /// 衝突解決策略
  final ConflictResolution resolution;

  DataConflict({
    required this.records,
    required this.lat,
    required this.lon,
    required this.conflictingFields,
    required this.keptRecord,
    required this.resolution,
  });

  @override
  String toString() {
    return 'DataConflict(座標: $lat,$lon, 衝突欄位: ${conflictingFields.keys.toList()}, '
           '記錄數: ${records.length}, 策略: $resolution)';
  }
}

/// 衝突解決策略
enum ConflictResolution {
  /// 保留最後一筆（預設）
  keepLast,
  
  /// 保留第一筆
  keepFirst,
  
  /// 保留最完整的記錄
  keepMostComplete,
  
  /// 標記為需要人工審核
  requireManualReview,
}

/// 過濾統計
class DataFilterStats {
  final int totalInput;
  final int validCount;
  final int incompleteCount;
  final int duplicateCount;
  final int conflictCount;
  final Map<String, int> missingFieldCounts;
  final List<String> duplicateGroups;

  DataFilterStats({
    required this.totalInput,
    required this.validCount,
    required this.incompleteCount,
    required this.duplicateCount,
    required this.conflictCount,
    required this.missingFieldCounts,
    required this.duplicateGroups,
  });

  @override
  String toString() {
    return '''
過濾統計報告:
  總輸入: $totalInput
  有效記錄: $validCount
  不完整: $incompleteCount
  重複: $duplicateCount
  衝突: $conflictCount
  缺失欄位統計: $missingFieldCounts
  重複群組: ${duplicateGroups.length} 組
''';
  }
}

/// V3 數據過濾服務
class DataFilterService {
  /// 座標精度（小數點後位數）
  /// 6 位 = 約 0.1 公尺精度，這是 VLGEO2 GPS 的合理精度
  static const int coordinatePrecision = 6;

  /// 必要欄位列表（BLE VLGEO2 數據）
  static const List<String> requiredFields = [
    'id',
    'lat',
    'lon',
    'height',
  ];

  /// 用於衝突檢測的比較欄位
  static const List<String> conflictCheckFields = [
    'height',
    'dbh',
    'type',
  ];

  /// 過濾並處理 BLE 數據
  /// 
  /// [rawRecords] - BleDataProcessor.parseCsvData 的結果
  ///               （座標已經過處理：絕對值 + N/S E/W 正負號）
  /// [existingRecords] - 已存在的資料（用於比對重複）
  /// [options] - 過濾選項
  static DataFilterResult filterBleData(
    List<Map<String, dynamic>> rawRecords, {
    List<Map<String, dynamic>>? existingRecords,
    FilterOptions? options,
  }) {
    options ??= FilterOptions();
    
    final List<Map<String, dynamic>> validRecords = [];
    final List<Map<String, dynamic>> incompleteRecords = [];
    final List<Map<String, dynamic>> duplicateRecords = [];
    final List<DataConflict> conflicts = [];
    final Map<String, int> missingFieldCounts = {};
    final List<String> duplicateGroups = [];

    // ========================================
    // Step 1: 檢查不完整資料
    // ========================================
    final List<Map<String, dynamic>> completeRecords = [];
    
    for (final record in rawRecords) {
      final missingFields = _checkMissingFields(record);
      
      if (missingFields.isNotEmpty) {
        // 標記不完整原因
        record['_incomplete'] = true;
        record['_missing_fields'] = missingFields;
        incompleteRecords.add(record);
        
        // 統計缺失欄位
        for (final field in missingFields) {
          missingFieldCounts[field] = (missingFieldCounts[field] ?? 0) + 1;
        }
        
        // 根據選項決定是否繼續處理
        if (!options.keepIncomplete) {
          continue;
        }
      }
      
      completeRecords.add(record);
    }

    // ========================================
    // Step 2: 座標分組
    // 使用處理後的座標值（BleDataProcessor 已經處理過 N/S, E/W）
    // ========================================
    final Map<String, List<Map<String, dynamic>>> coordGroups = {};
    
    for (final record in completeRecords) {
      final coordKey = _generateCoordinateKey(record);
      if (coordKey == null) continue;
      
      coordGroups.putIfAbsent(coordKey, () => []);
      coordGroups[coordKey]!.add(record);
    }

    // ========================================
    // Step 3: 處理每個座標群組
    // ========================================
    for (final entry in coordGroups.entries) {
      final group = entry.value;
      final coordKey = entry.key;
      
      if (group.length == 1) {
        // 無重複，直接加入有效列表
        validRecords.add(group.first);
        continue;
      }
      
      // 有多筆同座標記錄，需要進一步分析
      duplicateGroups.add('座標群組 $coordKey: ${group.length} 筆');
      
      // 根據時間戳排序（最舊到最新）
      group.sort((a, b) {
        final timeA = a['timestamp'] as DateTime?;
        final timeB = b['timestamp'] as DateTime?;
        if (timeA != null && timeB != null) {
          return timeA.compareTo(timeB);
        }
        return 0;
      });
      
      // 檢查是否有衝突（座標相同但其他欄位不同）
      final conflictingFields = _detectConflicts(group);
      
      if (conflictingFields.isEmpty) {
        // 完全相同的重複記錄，保留最後一筆
        for (int i = 0; i < group.length - 1; i++) {
          group[i]['_duplicate'] = true;
          group[i]['_duplicate_type'] = 'exact';
          group[i]['_kept_record_id'] = group.last['id'];
          duplicateRecords.add(group[i]);
        }
        validRecords.add(group.last);
      } else {
        // 有衝突的記錄
        final lat = _parseDouble(group.first['lat']) ?? 0;
        final lon = _parseDouble(group.first['lon']) ?? 0;
        
        // 根據解決策略處理
        final keptRecord = _resolveConflict(group, options.conflictResolution);
        
        // 記錄衝突
        final conflict = DataConflict(
          records: List.from(group),
          lat: lat,
          lon: lon,
          conflictingFields: conflictingFields,
          keptRecord: keptRecord,
          resolution: options.conflictResolution,
        );
        conflicts.add(conflict);
        
        // 根據策略決定是否加入有效列表
        if (options.conflictResolution != ConflictResolution.requireManualReview) {
          // 將非保留的記錄標記為重複
          for (final record in group) {
            if (record != keptRecord) {
              record['_duplicate'] = true;
              record['_duplicate_type'] = 'conflict_resolved';
              record['_kept_record_id'] = keptRecord['id'];
              record['_conflicting_fields'] = conflictingFields.keys.toList();
              duplicateRecords.add(record);
            }
          }
          validRecords.add(keptRecord);
        } else {
          // 需要人工審核，暫不加入有效列表
          for (final record in group) {
            record['_needs_review'] = true;
            record['_conflicting_fields'] = conflictingFields.keys.toList();
          }
        }
      }
    }

    // ========================================
    // Step 4: 與已存在資料庫記錄比對（可選）
    // ========================================
    if (existingRecords != null && existingRecords.isNotEmpty) {
      final existingCoordKeys = <String, Map<String, dynamic>>{};
      for (final record in existingRecords) {
        final key = _generateCoordinateKey(record);
        if (key != null) {
          existingCoordKeys[key] = record;
        }
      }
      
      final newValidRecords = <Map<String, dynamic>>[];
      
      for (final record in validRecords) {
        final coordKey = _generateCoordinateKey(record);
        
        if (coordKey != null && existingCoordKeys.containsKey(coordKey)) {
          final existingRecord = existingCoordKeys[coordKey]!;
          
          // 檢查是否有衝突
          final conflictingFields = _detectConflictsBetweenTwo(record, existingRecord);
          
          if (conflictingFields.isEmpty) {
            // 完全相同，視為重複
            record['_exists_in_database'] = true;
            record['_duplicate'] = true;
            record['_duplicate_type'] = 'exists_in_db';
            duplicateRecords.add(record);
            duplicateGroups.add('已存在於資料庫: ${record['id']}');
          } else {
            // 座標相同但數據不同，記錄衝突
            final lat = _parseDouble(record['lat']) ?? 0;
            final lon = _parseDouble(record['lon']) ?? 0;
            
            final conflict = DataConflict(
              records: [record, existingRecord],
              lat: lat,
              lon: lon,
              conflictingFields: conflictingFields,
              keptRecord: options.preferNewData ? record : existingRecord,
              resolution: options.conflictResolution,
            );
            conflicts.add(conflict);
            
            // 根據選項決定是保留新資料還是跳過
            if (options.preferNewData) {
              record['_updates_existing'] = true;
              record['_existing_record_id'] = existingRecord['id'];
              newValidRecords.add(record);
            } else {
              record['_exists_in_database'] = true;
              record['_has_conflict'] = true;
              duplicateRecords.add(record);
            }
          }
        } else {
          newValidRecords.add(record);
        }
      }
      
      validRecords.clear();
      validRecords.addAll(newValidRecords);
    }

    // 生成統計
    final stats = DataFilterStats(
      totalInput: rawRecords.length,
      validCount: validRecords.length,
      incompleteCount: incompleteRecords.length,
      duplicateCount: duplicateRecords.length,
      conflictCount: conflicts.length,
      missingFieldCounts: missingFieldCounts,
      duplicateGroups: duplicateGroups,
    );

    debugPrint('[DataFilterService] ${stats.toString()}');

    return DataFilterResult(
      validRecords: validRecords,
      incompleteRecords: incompleteRecords,
      duplicateRecords: duplicateRecords,
      conflicts: conflicts,
      stats: stats,
    );
  }

  /// 檢查缺失欄位
  static List<String> _checkMissingFields(Map<String, dynamic> record) {
    final missing = <String>[];
    final metadata = record['metadata'] as Map<String, dynamic>? ?? {};
    final bool hasGps = metadata['has_gps'] as bool? ?? true;
    
    for (final field in requiredFields) {
      if (!record.containsKey(field) || record[field] == null) {
        // 無GPS記錄允許 lat/lon 缺失
        if ((field == 'lat' || field == 'lon') && !hasGps) continue;
        missing.add(field);
      } else if (record[field] is String && (record[field] as String).isEmpty) {
        missing.add(field);
      } else if (record[field] is num && record[field] == 0) {
        // 無GPS記錄：lat=0/lon=0 不算缺失
        if ((field == 'lat' || field == 'lon') && !hasGps) continue;
        // 0 值對於經緯度可能是無效的（赤道/本初子午線除外）
        if (field == 'lat' || field == 'lon') {
          missing.add(field);
        }
      }
    }
    
    return missing;
  }

  /// 生成座標唯一鍵
  /// 
  /// 設計說明：
  /// - BleDataProcessor.parseCsvData 已經處理過座標：
  ///   1. 取絕對值
  ///   2. 根據 N/S 給緯度正負號（S = 負）
  ///   3. 根據 E/W 給經度正負號（W = 負）
  /// - 這裡直接使用處理後的值，精確到小數點後 6 位
  /// - 6 位小數 = 約 0.1 公尺精度
  static String? _generateCoordinateKey(Map<String, dynamic> record) {
    final lat = _parseDouble(record['lat']);
    final lon = _parseDouble(record['lon']);
    
    // 無GPS記錄：用 ID 作為唯一鍵（每條記錄獨立一組）
    final metadata = record['metadata'] as Map<String, dynamic>? ?? {};
    final bool hasGps = metadata['has_gps'] as bool? ?? true;
    if (!hasGps || lat == null || lon == null) {
      final id = record['id']?.toString() ?? record.hashCode.toString();
      return 'noGps_$id';
    }
    
    // 使用固定精度，確保比對一致性
    final latKey = lat.toStringAsFixed(coordinatePrecision);
    final lonKey = lon.toStringAsFixed(coordinatePrecision);
    
    return '$latKey,$lonKey';
  }

  /// 檢測群組內的衝突欄位
  static Map<String, List<dynamic>> _detectConflicts(List<Map<String, dynamic>> group) {
    final conflicts = <String, List<dynamic>>{};
    
    for (final field in conflictCheckFields) {
      final values = <dynamic>{};
      
      for (final record in group) {
        if (record.containsKey(field) && record[field] != null) {
          values.add(record[field]);
        }
      }
      
      // 如果有多個不同的值，則為衝突
      if (values.length > 1) {
        conflicts[field] = values.toList();
      }
    }
    
    return conflicts;
  }

  /// 檢測兩筆記錄之間的衝突
  static Map<String, List<dynamic>> _detectConflictsBetweenTwo(
    Map<String, dynamic> record1,
    Map<String, dynamic> record2,
  ) {
    final conflicts = <String, List<dynamic>>{};
    
    for (final field in conflictCheckFields) {
      final val1 = record1[field];
      final val2 = record2[field];
      
      // 只有當兩者都有值且不同時才算衝突
      if (val1 != null && val2 != null) {
        // 對於數值，考慮浮點精度
        if (val1 is num && val2 is num) {
          if ((val1 - val2).abs() > 0.001) {
            conflicts[field] = [val1, val2];
          }
        } else if (val1 != val2) {
          conflicts[field] = [val1, val2];
        }
      }
    }
    
    return conflicts;
  }

  /// 根據策略解決衝突
  static Map<String, dynamic> _resolveConflict(
    List<Map<String, dynamic>> group,
    ConflictResolution resolution,
  ) {
    switch (resolution) {
      case ConflictResolution.keepFirst:
        return group.first;
      
      case ConflictResolution.keepMostComplete:
        // 選擇非空欄位最多的記錄
        int maxNonNull = 0;
        Map<String, dynamic> mostComplete = group.first;
        
        for (final record in group) {
          int nonNullCount = 0;
          for (final field in conflictCheckFields) {
            if (record[field] != null) {
              nonNullCount++;
            }
          }
          if (nonNullCount > maxNonNull) {
            maxNonNull = nonNullCount;
            mostComplete = record;
          }
        }
        return mostComplete;
      
      case ConflictResolution.keepLast:
      case ConflictResolution.requireManualReview:
        return group.last;
    }
  }

  /// 解析 double 值
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// 計算兩點之間的距離（公尺）
  /// 使用 Haversine 公式
  static double calculateDistance(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double R = 6371000; // 地球半徑（公尺）
    
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    
    final double a = 
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return R * c;
  }

  /// 檢查兩個座標是否在容差範圍內
  static bool isCoordinateMatch(
    double lat1, double lon1,
    double lat2, double lon2, {
    double toleranceMeters = 1.0,
  }) {
    final distance = calculateDistance(lat1, lon1, lat2, lon2);
    return distance <= toleranceMeters;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
}

/// 過濾選項
class FilterOptions {
  /// 是否保留不完整記錄（標記但不移除）
  final bool keepIncomplete;
  
  /// 衝突解決策略
  final ConflictResolution conflictResolution;
  
  /// 與資料庫比對時，是否優先使用新資料
  final bool preferNewData;

  FilterOptions({
    this.keepIncomplete = false,
    this.conflictResolution = ConflictResolution.keepLast,
    this.preferNewData = false,
  });
}
