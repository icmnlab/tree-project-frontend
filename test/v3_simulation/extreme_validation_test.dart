// ============================================================================
// V3 極端嚴格驗證測試套件
// ============================================================================
// 覆蓋範圍：
// 1. 樹種辨識與驗證
// 2. AR 測量參照物限制
// 3. 測站到達標準 (COMPLETE 精度驗證)
// 4. 資料完整性與二階正規化驗證
// 5. ML 數據收集完整性
// 6. 極端邊界條件
// ============================================================================

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// Part 1: 樹種辨識驗證系統
// ============================================================================

/// 樹種資料模型
class TestTreeSpecies {
  final String id;
  final String name;
  final String scientificName;
  final double minDbhCm;      // 該樹種最小可能 DBH
  final double maxDbhCm;      // 該樹種最大可能 DBH
  final double minHeightM;    // 該樹種最小可能高度
  final double maxHeightM;    // 該樹種最大可能高度
  final List<String> regions; // 適合種植區域
  final double carbonRate;    // 碳吸收率 kg/year
  
  const TestTreeSpecies({
    required this.id,
    required this.name,
    required this.scientificName,
    required this.minDbhCm,
    required this.maxDbhCm,
    required this.minHeightM,
    required this.maxHeightM,
    required this.regions,
    required this.carbonRate,
  });
  
  /// 驗證 DBH 值是否在該樹種合理範圍內
  bool isDbhValid(double dbhCm) {
    return dbhCm >= minDbhCm && dbhCm <= maxDbhCm;
  }
  
  /// 驗證樹高是否在該樹種合理範圍內
  bool isHeightValid(double heightM) {
    return heightM >= minHeightM && heightM <= maxHeightM;
  }
  
  /// 驗證 DBH 與樹高的比例是否合理
  bool isDbhHeightRatioValid(double dbhCm, double heightM) {
    // 一般樹木的 DBH/Height 比例約在 0.5-10 cm/m
    final ratio = dbhCm / heightM;
    return ratio >= 0.3 && ratio <= 15;
  }
}

/// 樹種資料庫（模擬）
class TestSpeciesDatabase {
  static const List<TestTreeSpecies> _species = [
    TestTreeSpecies(
      id: '0001',
      name: '樟樹',
      scientificName: 'Cinnamomum camphora',
      minDbhCm: 5,
      maxDbhCm: 300,
      minHeightM: 2,
      maxHeightM: 50,
      regions: ['北部', '中部', '南部', '東部'],
      carbonRate: 23.5,
    ),
    TestTreeSpecies(
      id: '0002',
      name: '榕樹',
      scientificName: 'Ficus microcarpa',
      minDbhCm: 10,
      maxDbhCm: 500,
      minHeightM: 3,
      maxHeightM: 30,
      regions: ['北部', '中部', '南部'],
      carbonRate: 18.2,
    ),
    TestTreeSpecies(
      id: '0003',
      name: '楓香',
      scientificName: 'Liquidambar formosana',
      minDbhCm: 5,
      maxDbhCm: 150,
      minHeightM: 3,
      maxHeightM: 40,
      regions: ['北部', '中部'],
      carbonRate: 15.8,
    ),
    TestTreeSpecies(
      id: '0004',
      name: '黑板樹',
      scientificName: 'Alstonia scholaris',
      minDbhCm: 10,
      maxDbhCm: 100,
      minHeightM: 5,
      maxHeightM: 30,
      regions: ['南部', '東部'],
      carbonRate: 28.3,
    ),
  ];
  
  static TestTreeSpecies? findById(String id) {
    try {
      return _species.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }
  
  static TestTreeSpecies? findByName(String name) {
    try {
      return _species.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }
  
  static List<TestTreeSpecies> get all => _species;
}

/// 樹種辨識結果驗證器
class TestSpeciesValidator {
  /// 驗證樹種資料完整性
  static List<String> validateSpecies(TestTreeSpecies species) {
    final errors = <String>[];
    
    if (species.id.isEmpty) {
      errors.add('樹種 ID 不能為空');
    }
    if (species.name.isEmpty) {
      errors.add('樹種名稱不能為空');
    }
    if (species.scientificName.isEmpty) {
      errors.add('學名不能為空');
    }
    if (species.minDbhCm >= species.maxDbhCm) {
      errors.add('最小 DBH 必須小於最大 DBH');
    }
    if (species.minHeightM >= species.maxHeightM) {
      errors.add('最小樹高必須小於最大樹高');
    }
    if (species.regions.isEmpty) {
      errors.add('必須有至少一個適合區域');
    }
    if (species.carbonRate <= 0) {
      errors.add('碳吸收率必須大於 0');
    }
    
    return errors;
  }
  
  /// 驗證測量數據與樹種的一致性
  static List<String> validateMeasurementConsistency(
    TestTreeSpecies species,
    double dbhCm,
    double heightM,
  ) {
    final errors = <String>[];
    
    if (!species.isDbhValid(dbhCm)) {
      errors.add('DBH ${dbhCm}cm 超出 ${species.name} 的合理範圍 (${species.minDbhCm}-${species.maxDbhCm}cm)');
    }
    if (!species.isHeightValid(heightM)) {
      errors.add('樹高 ${heightM}m 超出 ${species.name} 的合理範圍 (${species.minHeightM}-${species.maxHeightM}m)');
    }
    if (!species.isDbhHeightRatioValid(dbhCm, heightM)) {
      final ratio = dbhCm / heightM;
      errors.add('DBH/Height 比例 ${ratio.toStringAsFixed(2)} 不合理');
    }
    
    return errors;
  }
}

// ============================================================================
// Part 2: AR 測量參照物驗證系統
// ============================================================================

/// 參照物類型
enum ReferenceObjectType {
  creditCard,      // 信用卡 8.56 x 5.398 cm
  a4Paper,         // A4 紙張 21.0 x 29.7 cm
  idCard,          // 身分證 8.56 x 5.4 cm
  smartphone,      // 手機（因型號不同需確認）
  coin50,          // 50 元硬幣 直徑 2.8 cm
  ruler30,         // 30cm 尺
  dbhTape,         // 專業 DBH 皮尺
  custom,          // 自定義
}

/// 參照物規格
class TestReferenceObject {
  final ReferenceObjectType type;
  final String name;
  final double widthCm;
  final double heightCm;
  final double toleranceCm;  // 允許誤差
  
  const TestReferenceObject({
    required this.type,
    required this.name,
    required this.widthCm,
    required this.heightCm,
    required this.toleranceCm,
  });
  
  /// 標準參照物列表
  static const List<TestReferenceObject> standardObjects = [
    TestReferenceObject(
      type: ReferenceObjectType.creditCard,
      name: '信用卡',
      widthCm: 8.56,
      heightCm: 5.398,
      toleranceCm: 0.05,  // ISO 標準容差
    ),
    TestReferenceObject(
      type: ReferenceObjectType.a4Paper,
      name: 'A4 紙張',
      widthCm: 21.0,
      heightCm: 29.7,
      toleranceCm: 0.3,
    ),
    TestReferenceObject(
      type: ReferenceObjectType.idCard,
      name: '身分證',
      widthCm: 8.56,
      heightCm: 5.4,
      toleranceCm: 0.05,
    ),
    TestReferenceObject(
      type: ReferenceObjectType.coin50,
      name: '50元硬幣',
      widthCm: 2.8,
      heightCm: 2.8,  // 圓形
      toleranceCm: 0.02,
    ),
    TestReferenceObject(
      type: ReferenceObjectType.ruler30,
      name: '30cm 尺',
      widthCm: 30.0,
      heightCm: 3.0,
      toleranceCm: 0.1,
    ),
  ];
}

/// AR 測量驗證器
class TestARMeasurementValidator {
  /// 最小有效像素寬度（參照物在畫面中的像素數）
  static const int minReferencePixelWidth = 30;
  
  /// 最大有效參照物比例（樹幹寬度/參照物寬度）
  static const double maxScaleRatio = 20.0;
  
  /// 最小信心度閾值
  static const double minConfidenceThreshold = 0.5;
  
  /// 驗證參照物測量有效性
  static ValidationResult validateReferenceMeasurement({
    required TestReferenceObject reference,
    required int referencePixelWidth,
    required int treePixelWidth,
    required int imageWidth,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    
    // 1. 參照物像素大小檢查
    if (referencePixelWidth < minReferencePixelWidth) {
      errors.add('參照物太小 (${referencePixelWidth}px < ${minReferencePixelWidth}px)，無法準確測量');
    }
    
    // 2. 參照物佔畫面比例檢查
    final referenceRatio = referencePixelWidth / imageWidth;
    if (referenceRatio < 0.02) {
      errors.add('參照物佔畫面比例過小 (${(referenceRatio * 100).toStringAsFixed(1)}%)');
    }
    if (referenceRatio > 0.8) {
      warnings.add('參照物佔畫面比例過大，可能導致樹幹被遮擋');
    }
    
    // 3. 樹幹與參照物比例檢查
    final scaleRatio = treePixelWidth / referencePixelWidth;
    if (scaleRatio > maxScaleRatio) {
      errors.add('比例差距過大 (${scaleRatio.toStringAsFixed(1)}x > ${maxScaleRatio}x)');
    }
    if (scaleRatio < 0.1) {
      warnings.add('樹幹可能太小或參照物太大');
    }
    
    // 4. 計算預估 DBH
    final estimatedDbhCm = (treePixelWidth / referencePixelWidth) * reference.widthCm;
    
    // 5. DBH 合理性檢查
    if (estimatedDbhCm < 1) {
      errors.add('計算的 DBH 過小 (${estimatedDbhCm.toStringAsFixed(1)}cm < 1cm)');
    }
    if (estimatedDbhCm > 500) {
      errors.add('計算的 DBH 過大 (${estimatedDbhCm.toStringAsFixed(1)}cm > 500cm)');
    }
    
    // 6. 計算信心度
    double confidence = 1.0;
    
    // 像素大小影響
    if (referencePixelWidth < 50) {
      confidence -= 0.2;
    } else if (referencePixelWidth > 200) {
      confidence += 0.05;
    }
    
    // 比例影響
    if (scaleRatio > 10) {
      confidence -= 0.15;
    }
    
    // 畫面佔比影響
    if (referenceRatio < 0.05) {
      confidence -= 0.1;
    }
    
    confidence = confidence.clamp(0.0, 1.0);
    
    return ValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      warnings: warnings,
      estimatedDbhCm: estimatedDbhCm,
      confidence: confidence,
    );
  }
  
  /// 驗證測量結果與樹種的一致性
  static List<String> validateDbhWithSpecies(
    double measuredDbhCm,
    TestTreeSpecies species,
  ) {
    final errors = <String>[];
    
    if (!species.isDbhValid(measuredDbhCm)) {
      errors.add('測量的 DBH ${measuredDbhCm.toStringAsFixed(1)}cm 不符合 ${species.name} 的特性');
      errors.add('${species.name} 的 DBH 範圍: ${species.minDbhCm}-${species.maxDbhCm}cm');
    }
    
    return errors;
  }
}

/// 驗證結果
class ValidationResult {
  final bool isValid;
  final List<String> errors;
  final List<String> warnings;
  final double? estimatedDbhCm;
  final double confidence;
  
  ValidationResult({
    required this.isValid,
    required this.errors,
    required this.warnings,
    this.estimatedDbhCm,
    this.confidence = 0.0,
  });
}

// ============================================================================
// Part 3: 測站到達標準驗證 (COMPLETE 精度)
// ============================================================================

/// 測站導航精度等級
enum StationAccuracyLevel {
  excellent,   // < 3m
  good,        // 3-5m
  acceptable,  // 5-10m
  poor,        // 10-15m
  unacceptable, // > 15m
}

/// 測站到達驗證器
class TestStationArrivalValidator {
  /// 判定為「到達」的最大距離（公尺）
  static const double arrivalThresholdM = 10.0;
  
  /// 精確到達的距離（公尺）
  static const double preciseArrivalM = 3.0;
  
  /// GPS 定位誤差容許值（公尺）
  static const double gpsToleranceM = 5.0;
  
  /// 計算到測站的距離
  static double calculateDistanceToStation(
    double userLat, double userLon,
    double stationLat, double stationLon,
  ) {
    const R = 6371000.0; // 地球半徑（公尺）
    final dLat = _toRadians(stationLat - userLat);
    final dLon = _toRadians(stationLon - userLon);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(userLat)) * math.cos(_toRadians(stationLat)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
  
  static double _toRadians(double degrees) => degrees * math.pi / 180;
  
  /// 評估測站到達精度
  static StationArrivalResult evaluateArrival(
    double distanceM,
    double gpsAccuracy,
  ) {
    // 考慮 GPS 誤差的調整距離
    final adjustedDistance = distanceM - gpsAccuracy.clamp(0, gpsToleranceM);
    final effectiveDistance = adjustedDistance < 0 ? 0 : adjustedDistance;
    
    // 判定精度等級
    StationAccuracyLevel level;
    if (effectiveDistance < preciseArrivalM) {
      level = StationAccuracyLevel.excellent;
    } else if (effectiveDistance < 5) {
      level = StationAccuracyLevel.good;
    } else if (effectiveDistance < arrivalThresholdM) {
      level = StationAccuracyLevel.acceptable;
    } else if (effectiveDistance < 15) {
      level = StationAccuracyLevel.poor;
    } else {
      level = StationAccuracyLevel.unacceptable;
    }
    
    // 是否可以標記為 COMPLETE
    final canComplete = effectiveDistance <= arrivalThresholdM;
    
    // 建議信息
    String recommendation;
    if (level == StationAccuracyLevel.excellent) {
      recommendation = '已精確到達測站，可以開始 AR 測量';
    } else if (level == StationAccuracyLevel.good) {
      recommendation = '已到達測站附近，AR 測量精度良好';
    } else if (level == StationAccuracyLevel.acceptable) {
      recommendation = '距離測站稍遠，建議再靠近以提高精度';
    } else if (level == StationAccuracyLevel.poor) {
      recommendation = '距離測站較遠，測量結果可能有誤差';
    } else {
      recommendation = '尚未到達測站，請繼續導航';
    }
    
    return StationArrivalResult(
      distanceM: distanceM,
      effectiveDistanceM: effectiveDistance.toDouble(),
      gpsAccuracy: gpsAccuracy,
      level: level,
      canComplete: canComplete,
      recommendation: recommendation,
    );
  }
  
  /// 驗證是否達到 COMPLETE 標準
  static bool isCompleteEligible(
    double distanceM,
    double gpsAccuracy,
  ) {
    // COMPLETE 標準：
    // 1. 實際距離 <= 10m
    // 2. 或 考慮 GPS 誤差後的有效距離 <= 10m
    final result = evaluateArrival(distanceM, gpsAccuracy);
    return result.canComplete;
  }
}

/// 測站到達結果
class StationArrivalResult {
  final double distanceM;
  final double effectiveDistanceM;
  final double gpsAccuracy;
  final StationAccuracyLevel level;
  final bool canComplete;
  final String recommendation;
  
  StationArrivalResult({
    required this.distanceM,
    required this.effectiveDistanceM,
    required this.gpsAccuracy,
    required this.level,
    required this.canComplete,
    required this.recommendation,
  });
}

// ============================================================================
// Part 4: 資料庫二階正規化驗證
// ============================================================================

/// 二階正規化驗證器
class TestSecondNormalFormValidator {
  /// 驗證表格是否滿足 2NF
  /// 2NF 要求：
  /// 1. 滿足 1NF（原子值）
  /// 2. 非主鍵屬性完全依賴於主鍵
  static List<String> validate2NF(TestTableSchema schema) {
    final issues = <String>[];
    
    // 檢查主鍵
    if (schema.primaryKey.isEmpty) {
      issues.add('表格 ${schema.tableName} 缺少主鍵');
      return issues;
    }
    
    // 檢查部分依賴（違反 2NF 的情況）
    for (final column in schema.columns) {
      if (schema.primaryKey.contains(column.name)) continue;
      
      // 檢查是否有部分依賴
      for (final dependency in column.dependencies) {
        if (schema.primaryKey.length > 1 &&
            schema.primaryKey.contains(dependency) &&
            !_dependsOnFullKey(column, schema.primaryKey)) {
          issues.add(
            '欄位 "${column.name}" 只依賴於部分主鍵 "$dependency"，'
            '違反 2NF。建議拆分到獨立表格。'
          );
        }
      }
    }
    
    // 檢查傳遞依賴（3NF）
    for (final column in schema.columns) {
      if (schema.primaryKey.contains(column.name)) continue;
      
      for (final transitive in column.transitiveDependencies) {
        issues.add(
          '欄位 "${column.name}" 通過 "$transitive" 傳遞依賴於主鍵，'
          '違反 3NF。建議拆分到獨立表格。'
        );
      }
    }
    
    return issues;
  }
  
  static bool _dependsOnFullKey(TestColumnInfo column, List<String> primaryKey) {
    return primaryKey.every((k) => column.dependencies.contains(k));
  }
}

/// 表格結構定義
class TestTableSchema {
  final String tableName;
  final List<String> primaryKey;
  final List<TestColumnInfo> columns;
  final List<String> foreignKeys;
  
  TestTableSchema({
    required this.tableName,
    required this.primaryKey,
    required this.columns,
    this.foreignKeys = const [],
  });
}

/// 欄位資訊
class TestColumnInfo {
  final String name;
  final String type;
  final bool nullable;
  final List<String> dependencies;          // 直接依賴
  final List<String> transitiveDependencies; // 傳遞依賴
  
  TestColumnInfo({
    required this.name,
    required this.type,
    this.nullable = true,
    this.dependencies = const [],
    this.transitiveDependencies = const [],
  });
}

// ============================================================================
// Part 5: ML 數據收集驗證
// ============================================================================

/// ML 數據收集驗證器
class TestMLDataCollectorValidator {
  /// 驗證記錄完整性
  static List<String> validateRecord(Map<String, dynamic> record) {
    final errors = <String>[];
    
    // 必要欄位
    final requiredFields = [
      'id',
      'record_type',
      'timestamp',
      'input_parameters',
      'auto_values',
      'user_values',
    ];
    
    for (final field in requiredFields) {
      if (!record.containsKey(field) || record[field] == null) {
        errors.add('缺少必要欄位: $field');
      }
    }
    
    // 時間戳格式
    if (record.containsKey('timestamp')) {
      try {
        DateTime.parse(record['timestamp']);
      } catch (_) {
        errors.add('時間戳格式無效');
      }
    }
    
    // 差異分析
    if (record.containsKey('auto_values') && record.containsKey('user_values')) {
      final auto = record['auto_values'] as Map<String, dynamic>;
      final user = record['user_values'] as Map<String, dynamic>;
      
      // 檢查是否有任何差異
      if (auto.toString() == user.toString()) {
        errors.add('自動值與用戶值完全相同，不需要記錄');
      }
    }
    
    return errors;
  }
  
  /// 驗證 AR 測量記錄
  static List<String> validateARMeasurementRecord(Map<String, dynamic> record) {
    final errors = validateRecord(record);
    
    final inputParamsRaw = record['input_parameters'];
    if (inputParamsRaw != null && inputParamsRaw is Map) {
      final inputParams = Map<String, dynamic>.from(inputParamsRaw);
      if (!inputParams.containsKey('reference_object_type')) {
        errors.add('AR 測量記錄缺少參照物類型');
      }
      if (!inputParams.containsKey('reference_actual_size_cm')) {
        errors.add('AR 測量記錄缺少參照物實際尺寸');
      }
    }
    
    return errors;
  }
  
  /// 驗證樹種辨識記錄
  static List<String> validateSpeciesRecord(Map<String, dynamic> record) {
    final errors = validateRecord(record);
    
    final autoValues = record['auto_values'] as Map<String, dynamic>?;
    if (autoValues != null) {
      if (!autoValues.containsKey('species_id')) {
        errors.add('樹種辨識記錄缺少自動識別的樹種 ID');
      }
      if (!autoValues.containsKey('confidence')) {
        errors.add('樹種辨識記錄缺少信心度');
      }
    }
    
    return errors;
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  // =========================================================================
  // 樹種辨識驗證測試
  // =========================================================================
  
  group('樹種辨識驗證', () {
    test('所有標準樹種資料完整', () {
      for (final species in TestSpeciesDatabase.all) {
        final errors = TestSpeciesValidator.validateSpecies(species);
        expect(errors, isEmpty, reason: '${species.name} 驗證失敗: $errors');
      }
    });
    
    test('樹種 ID 查詢', () {
      expect(TestSpeciesDatabase.findById('0001')?.name, '樟樹');
      expect(TestSpeciesDatabase.findById('0002')?.name, '榕樹');
      expect(TestSpeciesDatabase.findById('9999'), isNull);
    });
    
    test('DBH 與樹種一致性驗證 - 有效數據', () {
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      
      // 有效 DBH
      expect(species.isDbhValid(50), true);
      expect(species.isDbhValid(100), true);
      expect(species.isDbhValid(5), true);  // 邊界
      expect(species.isDbhValid(300), true); // 邊界
    });
    
    test('DBH 與樹種一致性驗證 - 無效數據', () {
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      
      // 無效 DBH
      expect(species.isDbhValid(0), false);
      expect(species.isDbhValid(-10), false);
      expect(species.isDbhValid(4.9), false);  // 略低於最小值
      expect(species.isDbhValid(301), false);  // 略高於最大值
    });
    
    test('DBH/Height 比例驗證', () {
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      
      // 合理比例
      expect(species.isDbhHeightRatioValid(30, 10), true);  // 3 cm/m
      expect(species.isDbhHeightRatioValid(50, 15), true);  // 3.33 cm/m
      
      // 不合理比例
      expect(species.isDbhHeightRatioValid(10, 50), false); // 0.2 cm/m - 太小
      expect(species.isDbhHeightRatioValid(200, 5), false); // 40 cm/m - 太大
    });
    
    test('完整測量一致性驗證', () {
      final species = TestSpeciesDatabase.findByName('榕樹')!;
      
      // 合理數據
      var errors = TestSpeciesValidator.validateMeasurementConsistency(species, 80, 20);
      expect(errors, isEmpty);
      
      // DBH 超出範圍
      errors = TestSpeciesValidator.validateMeasurementConsistency(species, 5, 20);
      expect(errors.length, greaterThan(0));
      expect(errors.first, contains('DBH'));
      
      // 樹高超出範圍
      errors = TestSpeciesValidator.validateMeasurementConsistency(species, 80, 50);
      expect(errors.length, greaterThan(0));
      expect(errors.first, contains('樹高'));
    });
  });
  
  // =========================================================================
  // AR 測量參照物驗證測試
  // =========================================================================
  
  group('AR 測量參照物驗證', () {
    test('標準參照物規格正確', () {
      for (final obj in TestReferenceObject.standardObjects) {
        expect(obj.widthCm, greaterThan(0));
        expect(obj.heightCm, greaterThan(0));
        expect(obj.toleranceCm, greaterThanOrEqualTo(0));
        expect(obj.name, isNotEmpty);
      }
    });
    
    test('信用卡尺寸符合 ISO 標準', () {
      final creditCard = TestReferenceObject.standardObjects
          .firstWhere((o) => o.type == ReferenceObjectType.creditCard);
      
      // ISO 7810 標準: 85.6mm x 53.98mm
      expect(creditCard.widthCm, closeTo(8.56, 0.01));
      expect(creditCard.heightCm, closeTo(5.398, 0.01));
    });
    
    test('有效的參照物測量', () {
      final reference = TestReferenceObject.standardObjects
          .firstWhere((o) => o.type == ReferenceObjectType.creditCard);
      
      final result = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 100,
        treePixelWidth: 300,
        imageWidth: 1920,
      );
      
      expect(result.isValid, true);
      expect(result.errors, isEmpty);
      expect(result.estimatedDbhCm, closeTo(25.68, 0.1)); // (300/100) * 8.56
      expect(result.confidence, greaterThan(0.7));
    });
    
    test('參照物太小 - 應該報錯', () {
      final reference = TestReferenceObject.standardObjects
          .firstWhere((o) => o.type == ReferenceObjectType.creditCard);
      
      final result = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 15,  // 太小
        treePixelWidth: 100,
        imageWidth: 1920,
      );
      
      expect(result.isValid, false);
      expect(result.errors, contains(predicate<String>((s) => s.contains('太小'))));
    });
    
    test('比例差距過大 - 應該報錯', () {
      final reference = TestReferenceObject.standardObjects
          .firstWhere((o) => o.type == ReferenceObjectType.coin50);  // 2.8cm
      
      final result = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 50,
        treePixelWidth: 1500,  // 30x 放大，超過限制
        imageWidth: 1920,
      );
      
      expect(result.isValid, false);
      expect(result.errors, contains(predicate<String>((s) => s.contains('比例'))));
    });
    
    test('計算的 DBH 超出合理範圍', () {
      final reference = TestReferenceObject.standardObjects
          .firstWhere((o) => o.type == ReferenceObjectType.a4Paper);  // 21cm
      
      // 計算出 600cm 的 DBH（不合理）
      final result = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 100,
        treePixelWidth: 2857,  // (600/21) * 100
        imageWidth: 3840,
      );
      
      expect(result.isValid, false);
      expect(result.errors, contains(predicate<String>((s) => s.contains('過大'))));
    });
    
    test('極端邊界 - 最小有效像素', () {
      final reference = TestReferenceObject.standardObjects.first;
      
      // 剛好在邊界 - 使用較小的 imageWidth 確保比例通過
      var result = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 30,  // 最小有效值
        treePixelWidth: 60,
        imageWidth: 1000,  // 較小的圖片寬度，使 30/1000 = 0.03 > 0.02
      );
      
      expect(result.isValid, true);
      
      // 略低於邊界
      result = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 29,
        treePixelWidth: 58,
        imageWidth: 1000,
      );
      
      expect(result.isValid, false);
    });
  });
  
  // =========================================================================
  // 測站到達標準測試
  // =========================================================================
  
  group('測站到達標準 (COMPLETE 精度)', () {
    test('精確到達 - excellent', () {
      final result = TestStationArrivalValidator.evaluateArrival(2.0, 3.0);
      
      expect(result.level, StationAccuracyLevel.excellent);
      expect(result.canComplete, true);
    });
    
    test('良好到達 - good', () {
      final result = TestStationArrivalValidator.evaluateArrival(6.0, 2.0);
      
      expect(result.level, StationAccuracyLevel.good);
      expect(result.canComplete, true);
    });
    
    test('可接受到達 - acceptable', () {
      final result = TestStationArrivalValidator.evaluateArrival(9.0, 1.0);
      
      expect(result.level, StationAccuracyLevel.acceptable);
      expect(result.canComplete, true);
    });
    
    test('較差到達 - poor', () {
      final result = TestStationArrivalValidator.evaluateArrival(12.0, 1.0);
      
      expect(result.level, StationAccuracyLevel.poor);
      expect(result.canComplete, false);
    });
    
    test('無法接受 - unacceptable', () {
      final result = TestStationArrivalValidator.evaluateArrival(20.0, 2.0);
      
      expect(result.level, StationAccuracyLevel.unacceptable);
      expect(result.canComplete, false);
    });
    
    test('GPS 誤差補償', () {
      // 實際距離 12m，但 GPS 精度 5m，有效距離 7m
      final result = TestStationArrivalValidator.evaluateArrival(12.0, 5.0);
      
      expect(result.effectiveDistanceM, closeTo(7.0, 0.1));
      expect(result.canComplete, true);
    });
    
    test('距離計算準確性', () {
      // 台北 101 到台北車站約 2.3 km
      final distance = TestStationArrivalValidator.calculateDistanceToStation(
        25.0339, 121.5645,  // 台北 101
        25.0478, 121.5170,  // 台北車站
      );
      
      expect(distance, closeTo(5200, 500));  // 約 5.2km
    });
    
    test('COMPLETE 標準嚴格驗證', () {
      // 邊界情況：剛好 10m
      expect(
        TestStationArrivalValidator.isCompleteEligible(10.0, 0.0),
        true,
      );
      
      // 略超過
      expect(
        TestStationArrivalValidator.isCompleteEligible(10.1, 0.0),
        false,
      );
      
      // 考慮 GPS 誤差後剛好符合
      expect(
        TestStationArrivalValidator.isCompleteEligible(15.0, 5.0),
        true,  // 有效距離 = 15 - 5 = 10m
      );
    });
    
    test('極端 GPS 誤差處理', () {
      // GPS 誤差超過容許值
      final result = TestStationArrivalValidator.evaluateArrival(10.0, 20.0);
      
      // 應該只扣除最大容許值 (5m)
      expect(result.effectiveDistanceM, closeTo(5.0, 0.1));
    });
  });
  
  // =========================================================================
  // 資料庫正規化測試
  // =========================================================================
  
  group('資料庫二階正規化驗證', () {
    test('tree_survey 表格 2NF 驗證', () {
      final schema = TestTableSchema(
        tableName: 'tree_survey',
        primaryKey: ['id'],
        columns: [
          TestColumnInfo(name: 'id', type: 'SERIAL'),
          TestColumnInfo(name: 'project_code', type: 'VARCHAR', dependencies: ['id']),
          TestColumnInfo(name: 'species_name', type: 'VARCHAR', dependencies: ['id']),
          TestColumnInfo(name: 'dbh_cm', type: 'DOUBLE', dependencies: ['id']),
          TestColumnInfo(name: 'x_coord', type: 'DOUBLE', dependencies: ['id']),
          TestColumnInfo(name: 'y_coord', type: 'DOUBLE', dependencies: ['id']),
        ],
      );
      
      final issues = TestSecondNormalFormValidator.validate2NF(schema);
      expect(issues, isEmpty);
    });
    
    test('違反 2NF 的表格應該被檢測', () {
      // 複合主鍵的情況下，欄位只依賴部分主鍵
      final schema = TestTableSchema(
        tableName: 'bad_design',
        primaryKey: ['project_id', 'tree_id'],
        columns: [
          TestColumnInfo(
            name: 'project_name',
            type: 'VARCHAR',
            dependencies: ['project_id'],  // 只依賴部分主鍵
          ),
          TestColumnInfo(
            name: 'species_name',
            type: 'VARCHAR',
            dependencies: ['project_id', 'tree_id'],  // 完全依賴
          ),
        ],
      );
      
      final issues = TestSecondNormalFormValidator.validate2NF(schema);
      expect(issues, isNotEmpty);
      expect(issues.first, contains('違反 2NF'));
    });
    
    test('違反 3NF（傳遞依賴）應該被檢測', () {
      final schema = TestTableSchema(
        tableName: 'transitive_dependency',
        primaryKey: ['id'],
        columns: [
          TestColumnInfo(name: 'id', type: 'SERIAL'),
          TestColumnInfo(
            name: 'carbon_rate',
            type: 'DOUBLE',
            dependencies: ['id'],
            transitiveDependencies: ['species_id'],  // 通過 species_id 傳遞依賴
          ),
        ],
      );
      
      final issues = TestSecondNormalFormValidator.validate2NF(schema);
      expect(issues, isNotEmpty);
      expect(issues.first, contains('違反 3NF'));
    });
  });
  
  // =========================================================================
  // ML 數據收集驗證測試
  // =========================================================================
  
  group('ML 數據收集驗證', () {
    test('完整的 ML 記錄驗證通過', () {
      final record = {
        'id': 'ml_1234_5678',
        'record_type': 'arMeasurement',
        'timestamp': DateTime.now().toIso8601String(),
        'input_parameters': {
          'reference_object_type': 'credit_card',
          'reference_actual_size_cm': 8.56,
        },
        'auto_values': {'dbh_cm': 25.0},
        'user_values': {'dbh_cm': 27.0},
      };
      
      final errors = TestMLDataCollectorValidator.validateRecord(record);
      expect(errors, isEmpty);
    });
    
    test('缺少必要欄位應該報錯', () {
      final record = {
        'id': 'ml_1234',
        'record_type': 'arMeasurement',
        // 缺少 timestamp, input_parameters 等
      };
      
      final errors = TestMLDataCollectorValidator.validateRecord(record);
      expect(errors.length, greaterThan(0));
      expect(errors, contains(predicate<String>((s) => s.contains('timestamp'))));
    });
    
    test('無差異的記錄應該被拒絕', () {
      final record = {
        'id': 'ml_1234',
        'record_type': 'arMeasurement',
        'timestamp': DateTime.now().toIso8601String(),
        'input_parameters': {},
        'auto_values': {'dbh_cm': 25.0},
        'user_values': {'dbh_cm': 25.0},  // 與 auto_values 相同
      };
      
      final errors = TestMLDataCollectorValidator.validateRecord(record);
      expect(errors, contains(predicate<String>((s) => s.contains('相同'))));
    });
    
    test('AR 測量記錄必須包含參照物資訊', () {
      final record = {
        'id': 'ml_1234',
        'record_type': 'arMeasurement',
        'timestamp': DateTime.now().toIso8601String(),
        'input_parameters': {},  // 缺少參照物資訊
        'auto_values': {'dbh_cm': 25.0},
        'user_values': {'dbh_cm': 27.0},
      };
      
      final errors = TestMLDataCollectorValidator.validateARMeasurementRecord(record);
      expect(errors, contains(predicate<String>((s) => s.contains('參照物'))));
    });
    
    test('樹種辨識記錄必須包含信心度', () {
      final record = {
        'id': 'ml_1234',
        'record_type': 'speciesIdentification',
        'timestamp': DateTime.now().toIso8601String(),
        'input_parameters': {'image_path': '/path/to/image.jpg'},
        'auto_values': {'species_id': '0001', 'species_name': '樟樹'},
        'user_values': {'species_id': '0002', 'species_name': '榕樹'},
      };
      
      final errors = TestMLDataCollectorValidator.validateSpeciesRecord(record);
      expect(errors, contains(predicate<String>((s) => s.contains('信心度'))));
    });
  });
  
  // =========================================================================
  // 極端邊界條件測試
  // =========================================================================
  
  group('極端邊界條件', () {
    test('零值處理', () {
      // DBH = 0
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      expect(species.isDbhValid(0), false);
      
      // 距離 = 0
      final result = TestStationArrivalValidator.evaluateArrival(0, 0);
      expect(result.level, StationAccuracyLevel.excellent);
      expect(result.canComplete, true);
    });
    
    test('負值處理', () {
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      expect(species.isDbhValid(-10), false);
      expect(species.isHeightValid(-5), false);
    });
    
    test('極大值處理', () {
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      expect(species.isDbhValid(10000), false);
      expect(species.isHeightValid(1000), false);
    });
    
    test('NaN 和 Infinity 處理', () {
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      expect(species.isDbhValid(double.nan), false);
      expect(species.isDbhValid(double.infinity), false);
      expect(species.isDbhValid(double.negativeInfinity), false);
    });
    
    test('座標邊界值', () {
      // 極地座標
      final distance1 = TestStationArrivalValidator.calculateDistanceToStation(
        89.999, 0,  // 北極附近
        89.998, 0,
      );
      expect(distance1, greaterThan(0));
      
      // 赤道跨越 180 度經線
      final distance2 = TestStationArrivalValidator.calculateDistanceToStation(
        0, 179.999,
        0, -179.999,
      );
      expect(distance2, greaterThan(0));
    });
    
    test('Unicode 樹種名稱處理', () {
      final species = TestSpeciesDatabase.findByName('樟樹');
      expect(species, isNotNull);
      expect(species!.name.length, 2);
    });
  });
  
  // =========================================================================
  // 實際使用情境模擬
  // =========================================================================
  
  group('實際使用情境模擬', () {
    test('完整測量流程模擬', () {
      // 1. 選擇樹種
      final species = TestSpeciesDatabase.findByName('樟樹')!;
      expect(species, isNotNull);
      
      // 2. 到達測站
      final arrival = TestStationArrivalValidator.evaluateArrival(5.0, 3.0);
      expect(arrival.canComplete, true);
      
      // 3. AR 測量
      final reference = TestReferenceObject.standardObjects
          .firstWhere((o) => o.type == ReferenceObjectType.creditCard);
      final measurement = TestARMeasurementValidator.validateReferenceMeasurement(
        reference: reference,
        referencePixelWidth: 150,
        treePixelWidth: 450,
        imageWidth: 1920,
      );
      expect(measurement.isValid, true);
      
      // 4. 驗證與樹種一致性
      final consistency = TestARMeasurementValidator.validateDbhWithSpecies(
        measurement.estimatedDbhCm!,
        species,
      );
      expect(consistency, isEmpty);
      
      // 5. 驗證完整測量資料
      final measurementErrors = TestSpeciesValidator.validateMeasurementConsistency(
        species,
        measurement.estimatedDbhCm!,
        15.0,  // 假設樹高
      );
      expect(measurementErrors, isEmpty);
    });
    
    test('異常情況處理流程', () {
      final species = TestSpeciesDatabase.findByName('黑板樹')!;
      
      // 模擬測量值超出樹種範圍
      final errors = TestSpeciesValidator.validateMeasurementConsistency(
        species,
        150,  // 黑板樹最大 100cm
        15,
      );
      
      expect(errors, isNotEmpty);
      expect(errors.first, contains('DBH'));
      
      // 系統應該給出建議
      expect(errors.first, contains('黑板樹'));
    });
    
    test('離線後重新同步情境', () {
      // 模擬離線收集的數據
      final offlineRecords = <Map<String, dynamic>>[];
      
      for (var i = 0; i < 10; i++) {
        offlineRecords.add({
          'id': 'ml_offline_$i',
          'record_type': 'arMeasurement',
          'timestamp': DateTime.now().subtract(Duration(hours: i)).toIso8601String(),
          'input_parameters': {
            'reference_object_type': 'credit_card',
            'reference_actual_size_cm': 8.56,
          },
          'auto_values': {'dbh_cm': 25.0 + i},
          'user_values': {'dbh_cm': 26.0 + i},
        });
      }
      
      // 驗證所有記錄
      for (final record in offlineRecords) {
        final errors = TestMLDataCollectorValidator.validateARMeasurementRecord(record);
        expect(errors, isEmpty);
      }
    });
  });
}
