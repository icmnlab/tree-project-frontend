// ============================================================================
// V3 AR DBH 整合測試套件
// ============================================================================
// 測試覆蓋:
// - AR 測量數據處理
// - DBH 計算與驗證
// - 圖像分析模擬
// - 多種測量方法整合
// - 數據精確度驗證
// ============================================================================

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用 AR DBH 核心類別
// ============================================================================

/// 測量方法
enum MeasurementMethod {
  /// AR 視覺測量
  arVisual,
  /// BLE 儀器測量
  bleDevice,
  /// 手動輸入
  manual,
  /// 圖像分析
  imageAnalysis,
  /// 傳統捲尺
  tapeMeasure,
}

/// 測量品質等級
enum QualityGrade {
  excellent, // 誤差 < 1%
  good,      // 誤差 1-3%
  acceptable, // 誤差 3-5%
  poor,      // 誤差 5-10%
  invalid,   // 誤差 > 10%
}

/// AR 測量點
class TestARMeasurementPoint {
  final double x;
  final double y;
  final double z;
  final double confidence;
  final DateTime timestamp;
  
  const TestARMeasurementPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.confidence,
    required this.timestamp,
  });
  
  double distanceTo(TestARMeasurementPoint other) {
    return math.sqrt(
      math.pow(x - other.x, 2) +
      math.pow(y - other.y, 2) +
      math.pow(z - other.z, 2),
    );
  }
}

/// DBH 測量結果
class TestDBHMeasurement {
  final String id;
  final double valueCm;
  final MeasurementMethod method;
  final DateTime timestamp;
  final double? accuracy;
  final double? confidence;
  final Map<String, dynamic> metadata;
  
  TestDBHMeasurement({
    required this.id,
    required this.valueCm,
    required this.method,
    DateTime? timestamp,
    this.accuracy,
    this.confidence,
    Map<String, dynamic>? metadata,
  }) : timestamp = timestamp ?? DateTime.now(),
       metadata = metadata ?? {};
  
  /// 驗證 DBH 值是否在合理範圍
  bool isValid() {
    return valueCm > 0 && valueCm < 500; // 0-500 cm
  }
  
  /// 判斷測量品質
  QualityGrade getQualityGrade() {
    if (accuracy == null) return QualityGrade.acceptable;
    
    if (accuracy! < 1) return QualityGrade.excellent;
    if (accuracy! < 3) return QualityGrade.good;
    if (accuracy! < 5) return QualityGrade.acceptable;
    if (accuracy! < 10) return QualityGrade.poor;
    return QualityGrade.invalid;
  }
  
  /// 計算周長
  double get circumferenceCm => valueCm * math.pi;
  
  /// 計算橫截面積 (平方公分)
  double get crossSectionAreaCm2 => math.pi * math.pow(valueCm / 2, 2);
}

/// AR 測量會話
class TestARMeasurementSession {
  final String sessionId;
  final List<TestARMeasurementPoint> points;
  final DateTime startTime;
  DateTime? endTime;
  
  TestARMeasurementSession({
    required this.sessionId,
    List<TestARMeasurementPoint>? points,
    DateTime? startTime,
  }) : points = points ?? [],
       startTime = startTime ?? DateTime.now();
  
  void addPoint(TestARMeasurementPoint point) {
    points.add(point);
  }
  
  void end() {
    endTime = DateTime.now();
  }
  
  Duration get duration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
  
  /// 計算平均信心度
  double get averageConfidence {
    if (points.isEmpty) return 0;
    return points.map((p) => p.confidence).reduce((a, b) => a + b) / points.length;
  }
}

/// AR DBH 計算器
class TestARDBHCalculator {
  static const double defaultHeightCm = 130; // 標準 DBH 測量高度
  
  /// 從 AR 測量點計算直徑
  static double? calculateDiameterFromPoints(List<TestARMeasurementPoint> points) {
    if (points.length < 2) return null;
    
    // 簡單方法：使用對角點計算直徑
    double maxDistance = 0;
    for (var i = 0; i < points.length; i++) {
      for (var j = i + 1; j < points.length; j++) {
        final distance = points[i].distanceTo(points[j]);
        if (distance > maxDistance) {
          maxDistance = distance;
        }
      }
    }
    
    return maxDistance * 100; // 轉換為公分
  }
  
  /// 從周長計算直徑
  static double circumferenceToDiameter(double circumferenceCm) {
    return circumferenceCm / math.pi;
  }
  
  /// 從直徑計算周長
  static double diameterToCircumference(double diameterCm) {
    return diameterCm * math.pi;
  }
  
  /// 驗證測量值
  static (bool, String?) validateMeasurement(double valueCm, MeasurementMethod method) {
    if (valueCm <= 0) {
      return (false, 'DBH 值必須大於 0');
    }
    
    if (valueCm > 500) {
      return (false, 'DBH 值超出合理範圍 (> 500 cm)');
    }
    
    // 根據測量方法設定預期範圍
    switch (method) {
      case MeasurementMethod.arVisual:
        if (valueCm < 5) {
          return (false, 'AR 測量可能不適用於極小直徑 (< 5 cm)');
        }
        break;
      case MeasurementMethod.imageAnalysis:
        if (valueCm < 10) {
          return (false, '圖像分析可能不準確於小直徑 (< 10 cm)');
        }
        break;
      default:
        break;
    }
    
    return (true, null);
  }
  
  /// 計算測量誤差率
  static double calculateErrorRate(double measured, double reference) {
    if (reference == 0) return double.infinity;
    return ((measured - reference).abs() / reference) * 100;
  }
  
  /// 融合多個測量結果
  static TestDBHMeasurement? fuseMeasurements(List<TestDBHMeasurement> measurements) {
    if (measurements.isEmpty) return null;
    if (measurements.length == 1) return measurements.first;
    
    // 加權平均：根據精確度和信心度
    double totalWeight = 0;
    double weightedSum = 0;
    
    for (final m in measurements) {
      final confidence = m.confidence ?? 0.5;
      final accuracy = m.accuracy ?? 5.0;
      final weight = confidence * (10 / accuracy);
      
      weightedSum += m.valueCm * weight;
      totalWeight += weight;
    }
    
    final fusedValue = totalWeight > 0 ? weightedSum / totalWeight : measurements.first.valueCm;
    
    return TestDBHMeasurement(
      id: 'fused_${DateTime.now().millisecondsSinceEpoch}',
      valueCm: fusedValue,
      method: MeasurementMethod.arVisual,
      confidence: measurements.map((m) => m.confidence ?? 0.5).reduce(math.max),
      metadata: {
        'fusedFrom': measurements.length,
        'methods': measurements.map((m) => m.method.name).toSet().toList(),
      },
    );
  }
}

/// 圖像分析模擬器
class TestImageAnalysisSimulator {
  final math.Random _random = math.Random();
  
  /// 模擬從圖像分析 DBH
  TestDBHMeasurement? analyzeImage({
    required double actualDiameterCm,
    double noiseLevel = 0.05, // 5% 噪音
    double failureRate = 0.1, // 10% 失敗率
  }) {
    if (_random.nextDouble() < failureRate) {
      return null; // 分析失敗
    }
    
    // 添加噪音
    final noise = (_random.nextDouble() - 0.5) * 2 * noiseLevel;
    final measuredValue = actualDiameterCm * (1 + noise);
    
    final confidence = 0.7 + _random.nextDouble() * 0.25;
    final accuracy = (noise.abs() * 100) + _random.nextDouble();
    
    return TestDBHMeasurement(
      id: 'img_${DateTime.now().millisecondsSinceEpoch}',
      valueCm: measuredValue,
      method: MeasurementMethod.imageAnalysis,
      confidence: confidence,
      accuracy: accuracy,
      metadata: {
        'analysisType': 'simulated',
        'noiseLevel': noiseLevel,
      },
    );
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  // =========================================================================
  // DBH 測量基本測試
  // =========================================================================
  
  group('DBH 測量基本測試', () {
    test('建立有效 DBH 測量', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.manual,
      );
      
      expect(measurement.id, 'M001');
      expect(measurement.valueCm, 45.5);
      expect(measurement.method, MeasurementMethod.manual);
      expect(measurement.isValid(), true);
    });
    
    test('驗證無效 DBH 值', () {
      final negativeValue = TestDBHMeasurement(
        id: 'M001',
        valueCm: -10,
        method: MeasurementMethod.manual,
      );
      
      final tooLargeValue = TestDBHMeasurement(
        id: 'M002',
        valueCm: 600,
        method: MeasurementMethod.manual,
      );
      
      expect(negativeValue.isValid(), false);
      expect(tooLargeValue.isValid(), false);
    });
    
    test('周長計算', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 100,
        method: MeasurementMethod.manual,
      );
      
      expect(measurement.circumferenceCm, closeTo(314.159, 0.01));
    });
    
    test('橫截面積計算', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 100, // 直徑 100 cm
        method: MeasurementMethod.manual,
      );
      
      // 面積 = π * r² = π * 50² = 7853.98 cm²
      expect(measurement.crossSectionAreaCm2, closeTo(7853.98, 0.1));
    });
  });
  
  // =========================================================================
  // 測量品質等級測試
  // =========================================================================
  
  group('測量品質等級測試', () {
    test('優秀品質', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.bleDevice,
        accuracy: 0.5,
      );
      
      expect(measurement.getQualityGrade(), QualityGrade.excellent);
    });
    
    test('良好品質', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.arVisual,
        accuracy: 2.0,
      );
      
      expect(measurement.getQualityGrade(), QualityGrade.good);
    });
    
    test('可接受品質', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.imageAnalysis,
        accuracy: 4.0,
      );
      
      expect(measurement.getQualityGrade(), QualityGrade.acceptable);
    });
    
    test('較差品質', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.manual,
        accuracy: 7.0,
      );
      
      expect(measurement.getQualityGrade(), QualityGrade.poor);
    });
    
    test('無效品質', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.arVisual,
        accuracy: 15.0,
      );
      
      expect(measurement.getQualityGrade(), QualityGrade.invalid);
    });
    
    test('無精確度資料', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.manual,
      );
      
      expect(measurement.getQualityGrade(), QualityGrade.acceptable);
    });
  });
  
  // =========================================================================
  // AR 測量點測試
  // =========================================================================
  
  group('AR 測量點測試', () {
    test('計算兩點距離', () {
      final now = DateTime.now();
      final point1 = TestARMeasurementPoint(
        x: 0, y: 0, z: 0,
        confidence: 0.9,
        timestamp: now,
      );
      final point2 = TestARMeasurementPoint(
        x: 3, y: 4, z: 0,
        confidence: 0.9,
        timestamp: now,
      );
      
      expect(point1.distanceTo(point2), closeTo(5.0, 0.001));
    });
    
    test('3D 距離計算', () {
      final now = DateTime.now();
      final point1 = TestARMeasurementPoint(
        x: 0, y: 0, z: 0,
        confidence: 0.9,
        timestamp: now,
      );
      final point2 = TestARMeasurementPoint(
        x: 1, y: 1, z: 1,
        confidence: 0.9,
        timestamp: now,
      );
      
      // √3 ≈ 1.732
      expect(point1.distanceTo(point2), closeTo(1.732, 0.01));
    });
  });
  
  // =========================================================================
  // AR 測量會話測試
  // =========================================================================
  
  group('AR 測量會話測試', () {
    test('建立會話並添加點', () {
      final session = TestARMeasurementSession(sessionId: 'S001');
      final now = DateTime.now();
      
      session.addPoint(TestARMeasurementPoint(
        x: 0, y: 0, z: 0, confidence: 0.9, timestamp: now,
      ));
      session.addPoint(TestARMeasurementPoint(
        x: 0.5, y: 0, z: 0, confidence: 0.85, timestamp: now,
      ));
      
      expect(session.points.length, 2);
    });
    
    test('計算平均信心度', () {
      final session = TestARMeasurementSession(sessionId: 'S001');
      final now = DateTime.now();
      
      session.addPoint(TestARMeasurementPoint(
        x: 0, y: 0, z: 0, confidence: 0.8, timestamp: now,
      ));
      session.addPoint(TestARMeasurementPoint(
        x: 0.5, y: 0, z: 0, confidence: 1.0, timestamp: now,
      ));
      
      expect(session.averageConfidence, 0.9);
    });
    
    test('空會話平均信心度為零', () {
      final session = TestARMeasurementSession(sessionId: 'S001');
      expect(session.averageConfidence, 0);
    });
    
    test('會話持續時間', () async {
      final session = TestARMeasurementSession(sessionId: 'S001');
      await Future.delayed(const Duration(milliseconds: 100));
      session.end();
      
      expect(session.duration.inMilliseconds, greaterThanOrEqualTo(100));
    });
  });
  
  // =========================================================================
  // DBH 計算測試
  // =========================================================================
  
  group('DBH 計算測試', () {
    test('從 AR 點計算直徑', () {
      final now = DateTime.now();
      final points = [
        TestARMeasurementPoint(x: 0, y: 0, z: 0, confidence: 0.9, timestamp: now),
        TestARMeasurementPoint(x: 0.5, y: 0, z: 0, confidence: 0.9, timestamp: now),
      ];
      
      final diameter = TestARDBHCalculator.calculateDiameterFromPoints(points);
      
      expect(diameter, closeTo(50.0, 0.01)); // 0.5m = 50cm
    });
    
    test('圓形邊緣點計算直徑', () {
      final now = DateTime.now();
      const radius = 0.25; // 25cm 半徑
      final points = <TestARMeasurementPoint>[];
      
      // 產生圓形上的點
      for (var i = 0; i < 8; i++) {
        final angle = (i / 8) * 2 * math.pi;
        points.add(TestARMeasurementPoint(
          x: radius * math.cos(angle),
          y: radius * math.sin(angle),
          z: 0,
          confidence: 0.9,
          timestamp: now,
        ));
      }
      
      final diameter = TestARDBHCalculator.calculateDiameterFromPoints(points);
      
      // 直徑應該接近 50 cm
      expect(diameter, closeTo(50.0, 5.0)); // 允許 5cm 誤差
    });
    
    test('點數不足返回 null', () {
      final now = DateTime.now();
      final points = [
        TestARMeasurementPoint(x: 0, y: 0, z: 0, confidence: 0.9, timestamp: now),
      ];
      
      final diameter = TestARDBHCalculator.calculateDiameterFromPoints(points);
      expect(diameter, isNull);
    });
    
    test('周長轉直徑', () {
      final diameter = TestARDBHCalculator.circumferenceToDiameter(314.159);
      expect(diameter, closeTo(100.0, 0.01));
    });
    
    test('直徑轉周長', () {
      final circumference = TestARDBHCalculator.diameterToCircumference(100.0);
      expect(circumference, closeTo(314.159, 0.01));
    });
  });
  
  // =========================================================================
  // 測量驗證測試
  // =========================================================================
  
  group('測量驗證測試', () {
    test('有效測量值', () {
      final (valid, error) = TestARDBHCalculator.validateMeasurement(
        45.5,
        MeasurementMethod.manual,
      );
      
      expect(valid, true);
      expect(error, isNull);
    });
    
    test('負值無效', () {
      final (valid, error) = TestARDBHCalculator.validateMeasurement(
        -10,
        MeasurementMethod.manual,
      );
      
      expect(valid, false);
      expect(error, contains('大於 0'));
    });
    
    test('超大值無效', () {
      final (valid, error) = TestARDBHCalculator.validateMeasurement(
        600,
        MeasurementMethod.manual,
      );
      
      expect(valid, false);
      expect(error, contains('超出'));
    });
    
    test('AR 測量極小值警告', () {
      final (valid, error) = TestARDBHCalculator.validateMeasurement(
        3.0,
        MeasurementMethod.arVisual,
      );
      
      expect(valid, false);
      expect(error, contains('極小'));
    });
    
    test('圖像分析小值警告', () {
      final (valid, error) = TestARDBHCalculator.validateMeasurement(
        8.0,
        MeasurementMethod.imageAnalysis,
      );
      
      expect(valid, false);
      expect(error, contains('不準確'));
    });
  });
  
  // =========================================================================
  // 誤差率計算測試
  // =========================================================================
  
  group('誤差率計算測試', () {
    test('零誤差', () {
      final error = TestARDBHCalculator.calculateErrorRate(50.0, 50.0);
      expect(error, 0);
    });
    
    test('正誤差', () {
      final error = TestARDBHCalculator.calculateErrorRate(55.0, 50.0);
      expect(error, 10.0); // 10%
    });
    
    test('負誤差', () {
      final error = TestARDBHCalculator.calculateErrorRate(45.0, 50.0);
      expect(error, 10.0); // 10% (絕對值)
    });
    
    test('參考值為零', () {
      final error = TestARDBHCalculator.calculateErrorRate(50.0, 0);
      expect(error, double.infinity);
    });
  });
  
  // =========================================================================
  // 測量融合測試
  // =========================================================================
  
  group('測量融合測試', () {
    test('空列表返回 null', () {
      final result = TestARDBHCalculator.fuseMeasurements([]);
      expect(result, isNull);
    });
    
    test('單一測量返回原值', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.5,
        method: MeasurementMethod.manual,
      );
      
      final result = TestARDBHCalculator.fuseMeasurements([measurement]);
      
      expect(result, measurement);
    });
    
    test('相同值融合', () {
      final measurements = [
        TestDBHMeasurement(id: 'M001', valueCm: 45.0, method: MeasurementMethod.manual),
        TestDBHMeasurement(id: 'M002', valueCm: 45.0, method: MeasurementMethod.bleDevice),
        TestDBHMeasurement(id: 'M003', valueCm: 45.0, method: MeasurementMethod.arVisual),
      ];
      
      final result = TestARDBHCalculator.fuseMeasurements(measurements);
      
      expect(result, isNotNull);
      expect(result!.valueCm, closeTo(45.0, 0.1));
    });
    
    test('不同值加權融合', () {
      final measurements = [
        TestDBHMeasurement(
          id: 'M001',
          valueCm: 45.0,
          method: MeasurementMethod.bleDevice,
          accuracy: 1.0,
          confidence: 0.95,
        ),
        TestDBHMeasurement(
          id: 'M002',
          valueCm: 50.0,
          method: MeasurementMethod.manual,
          accuracy: 5.0,
          confidence: 0.7,
        ),
      ];
      
      final result = TestARDBHCalculator.fuseMeasurements(measurements);
      
      expect(result, isNotNull);
      // 高精確度的測量應該有更大權重，所以結果應該更接近 45.0
      expect(result!.valueCm, lessThan(48.0));
    });
    
    test('融合結果包含元數據', () {
      final measurements = [
        TestDBHMeasurement(id: 'M001', valueCm: 45.0, method: MeasurementMethod.manual),
        TestDBHMeasurement(id: 'M002', valueCm: 46.0, method: MeasurementMethod.bleDevice),
      ];
      
      final result = TestARDBHCalculator.fuseMeasurements(measurements);
      
      expect(result!.metadata['fusedFrom'], 2);
      expect(result.metadata['methods'], contains('manual'));
      expect(result.metadata['methods'], contains('bleDevice'));
    });
  });
  
  // =========================================================================
  // 圖像分析測試
  // =========================================================================
  
  group('圖像分析測試', () {
    late TestImageAnalysisSimulator simulator;
    
    setUp(() {
      simulator = TestImageAnalysisSimulator();
    });
    
    test('成功分析', () {
      // 多次嘗試以確保至少一次成功
      TestDBHMeasurement? result;
      for (var i = 0; i < 20 && result == null; i++) {
        result = simulator.analyzeImage(
          actualDiameterCm: 50.0,
          failureRate: 0.0,
        );
      }
      
      expect(result, isNotNull);
      expect(result!.method, MeasurementMethod.imageAnalysis);
    });
    
    test('分析結果在合理範圍', () {
      final results = <TestDBHMeasurement>[];
      
      for (var i = 0; i < 100; i++) {
        final result = simulator.analyzeImage(
          actualDiameterCm: 50.0,
          noiseLevel: 0.05,
          failureRate: 0.0,
        );
        if (result != null) results.add(result);
      }
      
      // 所有結果應該在 45-55 cm 範圍內 (5% 噪音)
      for (final r in results) {
        expect(r.valueCm, greaterThan(45.0));
        expect(r.valueCm, lessThan(55.0));
      }
    });
    
    test('高失敗率', () {
      var failCount = 0;
      
      for (var i = 0; i < 100; i++) {
        final result = simulator.analyzeImage(
          actualDiameterCm: 50.0,
          failureRate: 0.9,
        );
        if (result == null) failCount++;
      }
      
      // 大約 90% 應該失敗
      expect(failCount, greaterThan(70));
    });
    
    test('低噪音高精確度', () {
      final results = <TestDBHMeasurement>[];
      
      for (var i = 0; i < 50; i++) {
        final result = simulator.analyzeImage(
          actualDiameterCm: 50.0,
          noiseLevel: 0.01, // 1% 噪音
          failureRate: 0.0,
        );
        if (result != null) results.add(result);
      }
      
      // 所有結果應該在 49-51 cm 範圍內
      for (final r in results) {
        expect(r.valueCm, greaterThan(49.0));
        expect(r.valueCm, lessThan(51.0));
      }
    });
  });
  
  // =========================================================================
  // 多方法整合測試
  // =========================================================================
  
  group('多方法整合測試', () {
    test('所有方法類型', () {
      final measurements = [
        TestDBHMeasurement(id: 'M001', valueCm: 45.0, method: MeasurementMethod.arVisual),
        TestDBHMeasurement(id: 'M002', valueCm: 45.5, method: MeasurementMethod.bleDevice),
        TestDBHMeasurement(id: 'M003', valueCm: 46.0, method: MeasurementMethod.manual),
        TestDBHMeasurement(id: 'M004', valueCm: 44.5, method: MeasurementMethod.imageAnalysis),
        TestDBHMeasurement(id: 'M005', valueCm: 45.2, method: MeasurementMethod.tapeMeasure),
      ];
      
      // 所有測量都應該是有效的
      for (final m in measurements) {
        expect(m.isValid(), true);
      }
      
      // 融合結果
      final fused = TestARDBHCalculator.fuseMeasurements(measurements);
      expect(fused, isNotNull);
      expect(fused!.valueCm, greaterThan(44.0));
      expect(fused.valueCm, lessThan(47.0));
    });
    
    test('方法優先級', () {
      // BLE 設備和捲尺通常更準確
      final measurements = [
        TestDBHMeasurement(
          id: 'M001',
          valueCm: 45.0,
          method: MeasurementMethod.bleDevice,
          accuracy: 0.5,
          confidence: 0.95,
        ),
        TestDBHMeasurement(
          id: 'M002',
          valueCm: 50.0,
          method: MeasurementMethod.arVisual,
          accuracy: 3.0,
          confidence: 0.7,
        ),
      ];
      
      final fused = TestARDBHCalculator.fuseMeasurements(measurements);
      
      // 結果應該更接近 BLE 測量值
      expect(fused!.valueCm, lessThan(48.0));
    });
  });
  
  // =========================================================================
  // 邊界條件測試
  // =========================================================================
  
  group('邊界條件測試', () {
    test('極小 DBH', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 0.1,
        method: MeasurementMethod.manual,
      );
      
      expect(measurement.isValid(), true);
      expect(measurement.circumferenceCm, closeTo(0.314, 0.01));
    });
    
    test('極大 DBH', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 499.0,
        method: MeasurementMethod.manual,
      );
      
      expect(measurement.isValid(), true);
    });
    
    test('零信心度', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.0,
        method: MeasurementMethod.arVisual,
        confidence: 0.0,
      );
      
      expect(measurement.isValid(), true);
    });
    
    test('完美信心度', () {
      final measurement = TestDBHMeasurement(
        id: 'M001',
        valueCm: 45.0,
        method: MeasurementMethod.bleDevice,
        confidence: 1.0,
      );
      
      expect(measurement.isValid(), true);
    });
    
    test('大量測量點', () {
      final now = DateTime.now();
      final points = <TestARMeasurementPoint>[];
      
      for (var i = 0; i < 1000; i++) {
        final angle = (i / 1000) * 2 * math.pi;
        points.add(TestARMeasurementPoint(
          x: 0.25 * math.cos(angle),
          y: 0.25 * math.sin(angle),
          z: 0,
          confidence: 0.9,
          timestamp: now,
        ));
      }
      
      final diameter = TestARDBHCalculator.calculateDiameterFromPoints(points);
      expect(diameter, closeTo(50.0, 1.0));
    });
  });
}
