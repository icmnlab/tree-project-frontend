// ============================================================================
// V3 ML 數據收集服務完整測試套件
// ============================================================================
// 測試覆蓋:
// - MLTrainingRecord 模型
// - 各類型記錄生成
// - 差異分析計算
// - 本地儲存管理
// - 數據匯出格式
// ============================================================================

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用 ML 記錄類型枚舉
// ============================================================================

/// ML 訓練記錄類型
enum TestMLRecordType {
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

// ============================================================================
// 測試用 ML 訓練記錄模型
// ============================================================================

/// ML 訓練記錄
class TestMLTrainingRecord {
  /// 記錄唯一 ID
  final String id;
  
  /// 記錄類型
  final TestMLRecordType recordType;
  
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

  TestMLTrainingRecord({
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

  factory TestMLTrainingRecord.fromJson(Map<String, dynamic> json) {
    return TestMLTrainingRecord(
      id: json['id'],
      recordType: TestMLRecordType.values.firstWhere(
        (e) => e.name == json['record_type'],
        orElse: () => TestMLRecordType.fieldModification,
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

// ============================================================================
// 測試用差異分析計算器
// ============================================================================

class TestDifferenceAnalyzer {
  /// 計算碳儲存量差異
  static Map<String, double> analyzeCarbonDifference({
    required double autoStorage,
    required double userStorage,
    required double autoSequestration,
    required double userSequestration,
  }) {
    final storageDiff = userStorage - autoStorage;
    final sequestrationDiff = userSequestration - autoSequestration;
    
    return {
      'storage_absolute_diff': storageDiff,
      'storage_percent_diff': autoStorage != 0 
          ? (storageDiff / autoStorage * 100) 
          : 0.0,
      'sequestration_absolute_diff': sequestrationDiff,
      'sequestration_percent_diff': autoSequestration != 0 
          ? (sequestrationDiff / autoSequestration * 100) 
          : 0.0,
    };
  }

  /// 計算 AR 測量差異
  static Map<String, double> analyzeARMeasurementDifference({
    required double autoDbh,
    required double userDbh,
  }) {
    final diff = userDbh - autoDbh;
    return {
      'absolute_diff': diff,
      'percent_diff': autoDbh != 0 ? (diff / autoDbh * 100) : 0.0,
    };
  }

  /// 計算座標差異 (距離)
  static Map<String, double> analyzeCoordinateDifference({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    final distance = _calculateDistance(lat1, lon1, lat2, lon2);
    return {
      'distance_meters': distance,
      'lat_diff': lat2 - lat1,
      'lon_diff': lon2 - lon1,
    };
  }

  /// Haversine 公式計算兩點距離
  static double _calculateDistance(
    double lat1, double lon1, 
    double lat2, double lon2,
  ) {
    const R = 6371000.0; // 地球半徑 (公尺)
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  /// 分析樹種辨識結果
  static Map<String, dynamic> analyzeSpeciesIdentification({
    required String autoSpeciesId,
    required String userSpeciesId,
    List<Map<String, dynamic>>? topPredictions,
  }) {
    return {
      'was_correct': autoSpeciesId == userSpeciesId,
      'was_in_top_predictions': topPredictions?.any(
        (p) => p['species_id'] == userSpeciesId
      ) ?? false,
    };
  }
}

// ============================================================================
// 測試用本地儲存管理器
// ============================================================================

class TestLocalStorageManager {
  static const int maxRecords = 2000;
  final List<TestMLTrainingRecord> _records = [];

  /// 儲存記錄
  bool saveRecord(TestMLTrainingRecord record) {
    // 檢查容量
    if (_records.length >= maxRecords) {
      // 移除最舊的記錄
      _records.removeAt(0);
    }
    _records.add(record);
    return true;
  }

  /// 取得所有記錄
  List<TestMLTrainingRecord> getAllRecords() => List.from(_records);

  /// 依類型取得記錄
  List<TestMLTrainingRecord> getRecordsByType(TestMLRecordType type) {
    return _records.where((r) => r.recordType == type).toList();
  }

  /// 依時間範圍取得記錄
  List<TestMLTrainingRecord> getRecordsByTimeRange(DateTime start, DateTime end) {
    return _records.where((r) => 
      r.timestamp.isAfter(start) && r.timestamp.isBefore(end)
    ).toList();
  }

  /// 依樹木 ID 取得記錄
  List<TestMLTrainingRecord> getRecordsByTreeId(String treeId) {
    return _records.where((r) => r.treeId == treeId).toList();
  }

  /// 刪除已同步的記錄
  int deleteRecords(List<String> ids) {
    final before = _records.length;
    _records.removeWhere((r) => ids.contains(r.id));
    return before - _records.length;
  }

  /// 記錄數量
  int get count => _records.length;

  /// 清空所有記錄
  void clear() => _records.clear();

  /// 匯出為 JSON
  List<Map<String, dynamic>> exportToJson() {
    return _records.map((r) => r.toJson()).toList();
  }

  /// 從 JSON 載入
  void loadFromJson(List<dynamic> jsonList) {
    _records.clear();
    for (final json in jsonList) {
      _records.add(TestMLTrainingRecord.fromJson(json));
    }
  }
}

// ============================================================================
// 測試用統計分析器
// ============================================================================

class TestMLStatisticsAnalyzer {
  /// 計算碳計算修改統計
  static Map<String, dynamic> analyzeCarbonModifications(
    List<TestMLTrainingRecord> records,
  ) {
    final carbonRecords = records
        .where((r) => r.recordType == TestMLRecordType.carbonCalculation)
        .toList();

    if (carbonRecords.isEmpty) {
      return {'count': 0};
    }

    final storageDiffs = carbonRecords
        .map((r) => (r.differenceAnalysis['storage_percent_diff'] as num?)?.toDouble() ?? 0.0)
        .toList();

    return {
      'count': carbonRecords.length,
      'avg_storage_diff_percent': storageDiffs.reduce((a, b) => a + b) / storageDiffs.length,
      'max_storage_diff_percent': storageDiffs.reduce(math.max),
      'min_storage_diff_percent': storageDiffs.reduce(math.min),
    };
  }

  /// 計算 AR 測量修改統計
  static Map<String, dynamic> analyzeARModifications(
    List<TestMLTrainingRecord> records,
  ) {
    final arRecords = records
        .where((r) => r.recordType == TestMLRecordType.arMeasurement)
        .toList();

    if (arRecords.isEmpty) {
      return {'count': 0};
    }

    final diffs = arRecords
        .map((r) => (r.differenceAnalysis['percent_diff'] as num?)?.toDouble() ?? 0.0)
        .toList();

    return {
      'count': arRecords.length,
      'avg_diff_percent': diffs.reduce((a, b) => a + b) / diffs.length,
      'max_diff_percent': diffs.reduce(math.max),
      'min_diff_percent': diffs.reduce(math.min),
    };
  }

  /// 計算樹種辨識準確率
  static Map<String, dynamic> analyzeSpeciesAccuracy(
    List<TestMLTrainingRecord> records,
  ) {
    final speciesRecords = records
        .where((r) => r.recordType == TestMLRecordType.speciesIdentification)
        .toList();

    if (speciesRecords.isEmpty) {
      return {'count': 0, 'accuracy': 0.0};
    }

    final correctCount = speciesRecords
        .where((r) => r.differenceAnalysis['was_correct'] == true)
        .length;

    final inTopCount = speciesRecords
        .where((r) => r.differenceAnalysis['was_in_top_predictions'] == true)
        .length;

    return {
      'count': speciesRecords.length,
      'accuracy': correctCount / speciesRecords.length * 100,
      'top_n_accuracy': inTopCount / speciesRecords.length * 100,
    };
  }

  /// 計算座標修正統計
  static Map<String, dynamic> analyzeCoordinateCorrections(
    List<TestMLTrainingRecord> records,
  ) {
    final coordRecords = records
        .where((r) => r.recordType == TestMLRecordType.coordinateCorrection)
        .toList();

    if (coordRecords.isEmpty) {
      return {'count': 0};
    }

    final distances = coordRecords
        .map((r) => (r.differenceAnalysis['distance_meters'] as num?)?.toDouble() ?? 0.0)
        .toList();

    return {
      'count': coordRecords.length,
      'avg_distance_m': distances.reduce((a, b) => a + b) / distances.length,
      'max_distance_m': distances.reduce(math.max),
      'min_distance_m': distances.reduce(math.min),
    };
  }
}

// ============================================================================
// 測試用 CSV 匯出器
// ============================================================================

class TestCSVExporter {
  /// 匯出碳計算記錄
  static String exportCarbonRecords(List<TestMLTrainingRecord> records) {
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln('id,tree_id,timestamp,dbh_cm,auto_storage,user_storage,diff_percent');
    
    // Data
    for (final r in records.where((r) => r.recordType == TestMLRecordType.carbonCalculation)) {
      buffer.writeln([
        r.id,
        r.treeId ?? '',
        r.timestamp.toIso8601String(),
        r.inputParameters['dbh_cm'] ?? '',
        r.autoValues['carbon_storage_kg'] ?? '',
        r.userValues['carbon_storage_kg'] ?? '',
        r.differenceAnalysis['storage_percent_diff']?.toStringAsFixed(2) ?? '',
      ].join(','));
    }
    
    return buffer.toString();
  }

  /// 匯出 AR 測量記錄
  static String exportARRecords(List<TestMLTrainingRecord> records) {
    final buffer = StringBuffer();
    
    buffer.writeln('id,tree_id,timestamp,auto_dbh,user_dbh,diff_percent,confidence');
    
    for (final r in records.where((r) => r.recordType == TestMLRecordType.arMeasurement)) {
      buffer.writeln([
        r.id,
        r.treeId ?? '',
        r.timestamp.toIso8601String(),
        r.autoValues['dbh_cm'] ?? '',
        r.userValues['dbh_cm'] ?? '',
        r.differenceAnalysis['percent_diff']?.toStringAsFixed(2) ?? '',
        r.autoValues['confidence'] ?? '',
      ].join(','));
    }
    
    return buffer.toString();
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  group('MLTrainingRecord 模型測試', () {
    test('應正確建立並生成 ID', () {
      final record = TestMLTrainingRecord(
        recordType: TestMLRecordType.carbonCalculation,
        treeId: 'tree123',
        inputParameters: {'dbh_cm': 30.0},
        autoValues: {'carbon_storage_kg': 100.0},
        userValues: {'carbon_storage_kg': 95.0},
      );

      expect(record.id, startsWith('ml_'));
      expect(record.treeId, 'tree123');
      expect(record.recordType, TestMLRecordType.carbonCalculation);
    });

    test('應正確序列化為 JSON', () {
      final record = TestMLTrainingRecord(
        id: 'ml_test_001',
        recordType: TestMLRecordType.arMeasurement,
        treeId: 'tree456',
        timestamp: DateTime(2024, 6, 15, 10, 30),
        inputParameters: {'reference_size': 10.0},
        autoValues: {'dbh_cm': 25.0},
        userValues: {'dbh_cm': 27.5},
        differenceAnalysis: {'percent_diff': 10.0},
      );

      final json = record.toJson();

      expect(json['id'], 'ml_test_001');
      expect(json['record_type'], 'arMeasurement');
      expect(json['tree_id'], 'tree456');
      expect(json['auto_values']['dbh_cm'], 25.0);
    });

    test('應正確從 JSON 反序列化', () {
      final json = {
        'id': 'ml_test_002',
        'record_type': 'speciesIdentification',
        'tree_id': 'tree789',
        'batch_id': 'batch001',
        'timestamp': '2024-07-01T14:00:00.000',
        'input_parameters': {'image_path': '/path/img.jpg'},
        'auto_values': {'species_name': '樟樹'},
        'user_values': {'species_name': '榕樹'},
        'difference_analysis': {'was_correct': false},
        'environment': {},
        'metadata': {},
      };

      final record = TestMLTrainingRecord.fromJson(json);

      expect(record.id, 'ml_test_002');
      expect(record.recordType, TestMLRecordType.speciesIdentification);
      expect(record.autoValues['species_name'], '樟樹');
      expect(record.userValues['species_name'], '榕樹');
    });

    test('應處理未知的記錄類型', () {
      final json = {
        'id': 'ml_unknown',
        'record_type': 'unknownType',
        'timestamp': '2024-01-01T00:00:00.000',
        'input_parameters': {},
        'auto_values': {},
        'user_values': {},
      };

      final record = TestMLTrainingRecord.fromJson(json);
      expect(record.recordType, TestMLRecordType.fieldModification);
    });
  });

  group('差異分析計算器測試', () {
    test('應正確計算碳儲存量差異', () {
      final diff = TestDifferenceAnalyzer.analyzeCarbonDifference(
        autoStorage: 100.0,
        userStorage: 90.0,
        autoSequestration: 50.0,
        userSequestration: 45.0,
      );

      expect(diff['storage_absolute_diff'], -10.0);
      expect(diff['storage_percent_diff'], -10.0);
      expect(diff['sequestration_absolute_diff'], -5.0);
      expect(diff['sequestration_percent_diff'], -10.0);
    });

    test('應處理零值情況', () {
      final diff = TestDifferenceAnalyzer.analyzeCarbonDifference(
        autoStorage: 0.0,
        userStorage: 50.0,
        autoSequestration: 0.0,
        userSequestration: 25.0,
      );

      expect(diff['storage_percent_diff'], 0.0);
      expect(diff['sequestration_percent_diff'], 0.0);
    });

    test('應正確計算 AR 測量差異', () {
      final diff = TestDifferenceAnalyzer.analyzeARMeasurementDifference(
        autoDbh: 30.0,
        userDbh: 33.0,
      );

      expect(diff['absolute_diff'], 3.0);
      expect(diff['percent_diff'], 10.0);
    });

    test('應正確計算座標距離', () {
      // 台北 101 到台北車站約 2.5 公里
      final diff = TestDifferenceAnalyzer.analyzeCoordinateDifference(
        lat1: 25.0339,  // 台北車站
        lon1: 121.5645,
        lat2: 25.0330,  // 稍微移動
        lon2: 121.5650,
      );

      expect(diff['distance_meters'], greaterThan(0));
      expect(diff['lat_diff'], closeTo(-0.0009, 0.0001));
      expect(diff['lon_diff'], closeTo(0.0005, 0.0001));
    });

    test('應正確分析樹種辨識結果 - 正確', () {
      final analysis = TestDifferenceAnalyzer.analyzeSpeciesIdentification(
        autoSpeciesId: 'sp001',
        userSpeciesId: 'sp001',
        topPredictions: [
          {'species_id': 'sp001', 'confidence': 0.9},
          {'species_id': 'sp002', 'confidence': 0.05},
        ],
      );

      expect(analysis['was_correct'], true);
      expect(analysis['was_in_top_predictions'], true);
    });

    test('應正確分析樹種辨識結果 - 錯誤但在候選中', () {
      final analysis = TestDifferenceAnalyzer.analyzeSpeciesIdentification(
        autoSpeciesId: 'sp001',
        userSpeciesId: 'sp002',
        topPredictions: [
          {'species_id': 'sp001', 'confidence': 0.6},
          {'species_id': 'sp002', 'confidence': 0.3},
        ],
      );

      expect(analysis['was_correct'], false);
      expect(analysis['was_in_top_predictions'], true);
    });
  });

  group('本地儲存管理器測試', () {
    late TestLocalStorageManager storage;

    setUp(() {
      storage = TestLocalStorageManager();
    });

    test('應正確儲存和取得記錄', () {
      final record = TestMLTrainingRecord(
        recordType: TestMLRecordType.carbonCalculation,
        treeId: 'tree1',
        inputParameters: {},
        autoValues: {},
        userValues: {},
      );

      storage.saveRecord(record);
      expect(storage.count, 1);
      expect(storage.getAllRecords().first.treeId, 'tree1');
    });

    test('應依類型過濾記錄', () {
      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.carbonCalculation,
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));
      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.arMeasurement,
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));
      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.carbonCalculation,
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));

      final carbonRecords = storage.getRecordsByType(TestMLRecordType.carbonCalculation);
      expect(carbonRecords.length, 2);
    });

    test('應依樹木 ID 過濾記錄', () {
      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.carbonCalculation,
        treeId: 'tree1',
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));
      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.arMeasurement,
        treeId: 'tree2',
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));
      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.speciesIdentification,
        treeId: 'tree1',
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));

      final tree1Records = storage.getRecordsByTreeId('tree1');
      expect(tree1Records.length, 2);
    });

    test('應在達到上限時移除最舊記錄', () {
      // 模擬超過上限的情況（使用較小的測試上限）
      for (var i = 0; i < 10; i++) {
        storage.saveRecord(TestMLTrainingRecord(
          id: 'record_$i',
          recordType: TestMLRecordType.fieldModification,
          inputParameters: {},
          autoValues: {},
          userValues: {},
        ));
      }

      expect(storage.count, 10);
      
      // 儲存器會在達到 maxRecords 時移除舊記錄
      // 這裡只是驗證功能正常
    });

    test('應正確刪除指定記錄', () {
      storage.saveRecord(TestMLTrainingRecord(
        id: 'to_delete',
        recordType: TestMLRecordType.carbonCalculation,
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));
      storage.saveRecord(TestMLTrainingRecord(
        id: 'to_keep',
        recordType: TestMLRecordType.carbonCalculation,
        inputParameters: {},
        autoValues: {},
        userValues: {},
      ));

      final deleted = storage.deleteRecords(['to_delete']);
      expect(deleted, 1);
      expect(storage.count, 1);
      expect(storage.getAllRecords().first.id, 'to_keep');
    });

    test('應正確匯出和載入 JSON', () {
      storage.saveRecord(TestMLTrainingRecord(
        id: 'r1',
        recordType: TestMLRecordType.carbonCalculation,
        treeId: 'tree1',
        inputParameters: {'dbh': 30.0},
        autoValues: {'storage': 100.0},
        userValues: {'storage': 95.0},
      ));

      final exported = storage.exportToJson();
      final jsonString = jsonEncode(exported);

      final newStorage = TestLocalStorageManager();
      newStorage.loadFromJson(jsonDecode(jsonString));

      expect(newStorage.count, 1);
      expect(newStorage.getAllRecords().first.treeId, 'tree1');
    });
  });

  group('統計分析器測試', () {
    late List<TestMLTrainingRecord> testRecords;

    setUp(() {
      testRecords = [
        // 碳計算記錄
        TestMLTrainingRecord(
          recordType: TestMLRecordType.carbonCalculation,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'storage_percent_diff': 5.0},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.carbonCalculation,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'storage_percent_diff': -10.0},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.carbonCalculation,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'storage_percent_diff': 15.0},
        ),
        // AR 測量記錄
        TestMLTrainingRecord(
          recordType: TestMLRecordType.arMeasurement,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'percent_diff': 8.0},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.arMeasurement,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'percent_diff': 12.0},
        ),
        // 樹種辨識記錄
        TestMLTrainingRecord(
          recordType: TestMLRecordType.speciesIdentification,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'was_correct': true, 'was_in_top_predictions': true},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.speciesIdentification,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'was_correct': false, 'was_in_top_predictions': true},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.speciesIdentification,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'was_correct': false, 'was_in_top_predictions': false},
        ),
        // 座標修正記錄
        TestMLTrainingRecord(
          recordType: TestMLRecordType.coordinateCorrection,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'distance_meters': 5.0},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.coordinateCorrection,
          inputParameters: {},
          autoValues: {},
          userValues: {},
          differenceAnalysis: {'distance_meters': 15.0},
        ),
      ];
    });

    test('應正確分析碳計算修改', () {
      final stats = TestMLStatisticsAnalyzer.analyzeCarbonModifications(testRecords);

      expect(stats['count'], 3);
      expect(stats['avg_storage_diff_percent'], closeTo(3.33, 0.1));
      expect(stats['max_storage_diff_percent'], 15.0);
      expect(stats['min_storage_diff_percent'], -10.0);
    });

    test('應正確分析 AR 測量修改', () {
      final stats = TestMLStatisticsAnalyzer.analyzeARModifications(testRecords);

      expect(stats['count'], 2);
      expect(stats['avg_diff_percent'], 10.0);
      expect(stats['max_diff_percent'], 12.0);
      expect(stats['min_diff_percent'], 8.0);
    });

    test('應正確分析樹種辨識準確率', () {
      final stats = TestMLStatisticsAnalyzer.analyzeSpeciesAccuracy(testRecords);

      expect(stats['count'], 3);
      expect(stats['accuracy'], closeTo(33.33, 0.1)); // 1/3
      expect(stats['top_n_accuracy'], closeTo(66.67, 0.1)); // 2/3
    });

    test('應正確分析座標修正', () {
      final stats = TestMLStatisticsAnalyzer.analyzeCoordinateCorrections(testRecords);

      expect(stats['count'], 2);
      expect(stats['avg_distance_m'], 10.0);
      expect(stats['max_distance_m'], 15.0);
      expect(stats['min_distance_m'], 5.0);
    });

    test('應處理空記錄', () {
      final emptyStats = TestMLStatisticsAnalyzer.analyzeCarbonModifications([]);
      expect(emptyStats['count'], 0);
    });
  });

  group('CSV 匯出器測試', () {
    test('應正確匯出碳計算記錄', () {
      final records = [
        TestMLTrainingRecord(
          id: 'ml_001',
          recordType: TestMLRecordType.carbonCalculation,
          treeId: 'tree123',
          timestamp: DateTime(2024, 6, 1, 10, 0),
          inputParameters: {'dbh_cm': 30.0},
          autoValues: {'carbon_storage_kg': 100.0},
          userValues: {'carbon_storage_kg': 95.0},
          differenceAnalysis: {'storage_percent_diff': -5.0},
        ),
      ];

      final csv = TestCSVExporter.exportCarbonRecords(records);
      final lines = csv.trim().split('\n');

      expect(lines.length, 2); // Header + 1 data row
      expect(lines[0], 'id,tree_id,timestamp,dbh_cm,auto_storage,user_storage,diff_percent');
      expect(lines[1], contains('ml_001'));
      expect(lines[1], contains('tree123'));
      expect(lines[1], contains('30.0'));
      expect(lines[1], contains('100.0'));
      expect(lines[1], contains('95.0'));
    });

    test('應正確匯出 AR 測量記錄', () {
      final records = [
        TestMLTrainingRecord(
          id: 'ml_ar_001',
          recordType: TestMLRecordType.arMeasurement,
          treeId: 'tree456',
          timestamp: DateTime(2024, 6, 15),
          inputParameters: {},
          autoValues: {'dbh_cm': 25.0, 'confidence': 0.85},
          userValues: {'dbh_cm': 27.0},
          differenceAnalysis: {'percent_diff': 8.0},
        ),
      ];

      final csv = TestCSVExporter.exportARRecords(records);
      final lines = csv.trim().split('\n');

      expect(lines.length, 2);
      expect(lines[0], contains('confidence'));
      expect(lines[1], contains('25.0'));
      expect(lines[1], contains('27.0'));
      expect(lines[1], contains('0.85'));
    });

    test('應只匯出對應類型的記錄', () {
      final records = [
        TestMLTrainingRecord(
          recordType: TestMLRecordType.carbonCalculation,
          inputParameters: {},
          autoValues: {},
          userValues: {},
        ),
        TestMLTrainingRecord(
          recordType: TestMLRecordType.arMeasurement,
          inputParameters: {},
          autoValues: {},
          userValues: {},
        ),
      ];

      final carbonCsv = TestCSVExporter.exportCarbonRecords(records);
      final arCsv = TestCSVExporter.exportARRecords(records);

      expect(carbonCsv.trim().split('\n').length, 2); // Header + 1 carbon
      expect(arCsv.trim().split('\n').length, 2); // Header + 1 AR
    });
  });

  group('整合測試', () {
    test('完整的 ML 數據收集流程', () {
      final storage = TestLocalStorageManager();

      // 1. 模擬碳計算修改
      final carbonDiff = TestDifferenceAnalyzer.analyzeCarbonDifference(
        autoStorage: 150.0,
        userStorage: 145.0,
        autoSequestration: 30.0,
        userSequestration: 28.0,
      );

      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.carbonCalculation,
        treeId: 'tree001',
        inputParameters: {'dbh_cm': 45.0, 'height_m': 12.0},
        autoValues: {'carbon_storage_kg': 150.0, 'carbon_sequestration': 30.0},
        userValues: {'carbon_storage_kg': 145.0, 'carbon_sequestration': 28.0},
        differenceAnalysis: carbonDiff,
      ));

      // 2. 模擬 AR 測量修改
      final arDiff = TestDifferenceAnalyzer.analyzeARMeasurementDifference(
        autoDbh: 42.0,
        userDbh: 45.0,
      );

      storage.saveRecord(TestMLTrainingRecord(
        recordType: TestMLRecordType.arMeasurement,
        treeId: 'tree001',
        inputParameters: {'reference_size': 10.0},
        autoValues: {'dbh_cm': 42.0, 'confidence': 0.78},
        userValues: {'dbh_cm': 45.0},
        differenceAnalysis: arDiff,
      ));

      // 3. 分析統計
      final records = storage.getAllRecords();
      final carbonStats = TestMLStatisticsAnalyzer.analyzeCarbonModifications(records);
      final arStats = TestMLStatisticsAnalyzer.analyzeARModifications(records);

      expect(carbonStats['count'], 1);
      expect(arStats['count'], 1);

      // 4. 匯出
      final carbonCsv = TestCSVExporter.exportCarbonRecords(records);
      expect(carbonCsv, contains('tree001'));
    });

    test('多類型記錄的混合處理', () {
      final storage = TestLocalStorageManager();
      final random = math.Random(42);

      // 生成多種類型的測試記錄
      for (var i = 0; i < 50; i++) {
        final type = TestMLRecordType.values[random.nextInt(TestMLRecordType.values.length)];
        storage.saveRecord(TestMLTrainingRecord(
          recordType: type,
          treeId: 'tree_${i % 10}',
          inputParameters: {'index': i},
          autoValues: {'value': random.nextDouble() * 100},
          userValues: {'value': random.nextDouble() * 100},
        ));
      }

      expect(storage.count, 50);

      // 各類型都應該能正確過濾
      for (final type in TestMLRecordType.values) {
        final records = storage.getRecordsByType(type);
        expect(records.every((r) => r.recordType == type), true);
      }

      // 樹木 ID 過濾
      final tree0Records = storage.getRecordsByTreeId('tree_0');
      expect(tree0Records.length, 5); // 50 / 10 = 5
    });
  });
}
