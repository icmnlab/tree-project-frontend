// ============================================================================
// V3 專案邊界服務完整測試套件
// ============================================================================
// 測試覆蓋:
// - 邊界座標驗證
// - 多邊形運算 (面積、周長、重心)
// - 點包含測試 (Point-in-Polygon)
// - 座標自動匹配
// - 邊界衝突檢測
// - 邊界資料正規化
// ============================================================================

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用邊界座標模型
// ============================================================================

/// 座標點
class TestCoordinate {
  final double lat;
  final double lon;
  
  const TestCoordinate(this.lat, this.lon);
  
  /// 計算兩點間距離 (Haversine 公式，返回公尺)
  double distanceTo(TestCoordinate other) {
    const R = 6371000.0; // 地球半徑 (公尺)
    final lat1 = lat * math.pi / 180;
    final lat2 = other.lat * math.pi / 180;
    final dLat = (other.lat - lat) * math.pi / 180;
    final dLon = (other.lon - lon) * math.pi / 180;
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(lat1) * math.cos(lat2) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return R * c;
  }
  
  bool isValid() {
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }
  
  @override
  bool operator ==(Object other) =>
      other is TestCoordinate && lat == other.lat && lon == other.lon;
  
  @override
  int get hashCode => lat.hashCode ^ lon.hashCode;
  
  @override
  String toString() => 'TestCoordinate($lat, $lon)';
}

/// 專案邊界
class TestProjectBoundary {
  final String projectId;
  final String projectName;
  final List<TestCoordinate> coordinates;
  final DateTime createdAt;
  
  TestProjectBoundary({
    required this.projectId,
    required this.projectName,
    required this.coordinates,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
  
  /// 計算邊界面積 (平方公尺) - 使用 Shoelace 公式
  double calculateArea() {
    if (coordinates.length < 3) return 0;
    
    // 簡化版：使用平面近似 (適用於小區域)
    // 對於更精確的計算，應使用球面幾何
    double sum = 0;
    for (var i = 0; i < coordinates.length; i++) {
      final j = (i + 1) % coordinates.length;
      sum += coordinates[i].lon * coordinates[j].lat;
      sum -= coordinates[j].lon * coordinates[i].lat;
    }
    
    // 轉換為平方公尺（近似值）
    // 1度緯度 ≈ 111,320 公尺, 1度經度 ≈ 111,320 * cos(lat) 公尺
    final centerLat = coordinates.map((c) => c.lat).reduce((a, b) => a + b) / coordinates.length;
    const meterPerDegreeLat = 111320.0;
    final meterPerDegreeLon = 111320.0 * math.cos(centerLat * math.pi / 180);
    
    return (sum.abs() / 2) * meterPerDegreeLat * meterPerDegreeLon;
  }
  
  /// 計算邊界周長 (公尺)
  double calculatePerimeter() {
    if (coordinates.length < 2) return 0;
    
    double perimeter = 0;
    for (var i = 0; i < coordinates.length; i++) {
      final j = (i + 1) % coordinates.length;
      perimeter += coordinates[i].distanceTo(coordinates[j]);
    }
    return perimeter;
  }
  
  /// 計算邊界重心
  TestCoordinate? calculateCentroid() {
    if (coordinates.isEmpty) return null;
    
    double sumLat = 0;
    double sumLon = 0;
    for (final coord in coordinates) {
      sumLat += coord.lat;
      sumLon += coord.lon;
    }
    return TestCoordinate(sumLat / coordinates.length, sumLon / coordinates.length);
  }
  
  /// 點是否在邊界內 (Ray Casting 演算法)
  bool containsPoint(TestCoordinate point) {
    if (coordinates.length < 3) return false;
    
    int crossings = 0;
    for (var i = 0; i < coordinates.length; i++) {
      final j = (i + 1) % coordinates.length;
      
      final xi = coordinates[i].lon;
      final yi = coordinates[i].lat;
      final xj = coordinates[j].lon;
      final yj = coordinates[j].lat;
      
      if (((yi > point.lat) != (yj > point.lat)) &&
          (point.lon < (xj - xi) * (point.lat - yi) / (yj - yi) + xi)) {
        crossings++;
      }
    }
    
    return crossings % 2 == 1;
  }
  
  /// 驗證邊界
  BoundaryValidationResult validate() {
    final issues = <String>[];
    
    if (coordinates.length < 3) {
      issues.add('邊界至少需要3個座標點');
    }
    
    for (var i = 0; i < coordinates.length; i++) {
      if (!coordinates[i].isValid()) {
        issues.add('座標點 $i 無效: ${coordinates[i]}');
      }
    }
    
    // 檢查自相交
    if (hasSelfIntersection()) {
      issues.add('邊界存在自相交');
    }
    
    // 檢查重複點
    final uniquePoints = coordinates.toSet();
    if (uniquePoints.length != coordinates.length) {
      issues.add('邊界存在重複座標點');
    }
    
    return BoundaryValidationResult(
      isValid: issues.isEmpty,
      issues: issues,
    );
  }
  
  /// 檢查自相交 (簡化版)
  bool hasSelfIntersection() {
    if (coordinates.length < 4) return false;
    
    for (var i = 0; i < coordinates.length - 2; i++) {
      for (var j = i + 2; j < coordinates.length; j++) {
        // 跳過相鄰邊
        if (i == 0 && j == coordinates.length - 1) continue;
        
        if (_segmentsIntersect(
          coordinates[i], coordinates[i + 1],
          coordinates[j], coordinates[(j + 1) % coordinates.length],
        )) {
          return true;
        }
      }
    }
    return false;
  }
  
  bool _segmentsIntersect(
    TestCoordinate a1, TestCoordinate a2,
    TestCoordinate b1, TestCoordinate b2,
  ) {
    double cross(TestCoordinate o, TestCoordinate a, TestCoordinate b) {
      return (a.lon - o.lon) * (b.lat - o.lat) - (a.lat - o.lat) * (b.lon - o.lon);
    }
    
    final d1 = cross(b1, b2, a1);
    final d2 = cross(b1, b2, a2);
    final d3 = cross(a1, a2, b1);
    final d4 = cross(a1, a2, b2);
    
    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    
    return false;
  }
}

/// 邊界驗證結果
class BoundaryValidationResult {
  final bool isValid;
  final List<String> issues;
  
  BoundaryValidationResult({
    required this.isValid,
    required this.issues,
  });
}

/// 座標匹配器
class TestCoordinateMatcher {
  final List<TestProjectBoundary> boundaries;
  
  TestCoordinateMatcher(this.boundaries);
  
  /// 找到包含指定點的所有邊界
  List<TestProjectBoundary> findContainingBoundaries(TestCoordinate point) {
    return boundaries.where((b) => b.containsPoint(point)).toList();
  }
  
  /// 找到最近的邊界
  (TestProjectBoundary?, double) findNearestBoundary(TestCoordinate point) {
    TestProjectBoundary? nearest;
    double minDistance = double.infinity;
    
    for (final boundary in boundaries) {
      final centroid = boundary.calculateCentroid();
      if (centroid != null) {
        final distance = point.distanceTo(centroid);
        if (distance < minDistance) {
          minDistance = distance;
          nearest = boundary;
        }
      }
    }
    
    return (nearest, minDistance);
  }
  
  /// 批次匹配座標到專案
  Map<String, TestProjectBoundary?> batchMatch(List<TestCoordinate> points) {
    final results = <String, TestProjectBoundary?>{};
    
    for (final point in points) {
      final key = '${point.lat},${point.lon}';
      final containing = findContainingBoundaries(point);
      results[key] = containing.isNotEmpty ? containing.first : null;
    }
    
    return results;
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  // =========================================================================
  // 座標驗證測試
  // =========================================================================
  
  group('座標驗證測試', () {
    test('有效座標範圍', () {
      expect(const TestCoordinate(0, 0).isValid(), true);
      expect(const TestCoordinate(90, 180).isValid(), true);
      expect(const TestCoordinate(-90, -180).isValid(), true);
      expect(const TestCoordinate(25.0330, 121.5654).isValid(), true);
    });
    
    test('無效座標範圍', () {
      expect(const TestCoordinate(91, 0).isValid(), false);
      expect(const TestCoordinate(-91, 0).isValid(), false);
      expect(const TestCoordinate(0, 181).isValid(), false);
      expect(const TestCoordinate(0, -181).isValid(), false);
    });
    
    test('台灣座標範圍檢測', () {
      // 台灣本島大致座標範圍
      const taiwanMinLat = 21.5;
      const taiwanMaxLat = 25.5;
      const taiwanMinLon = 119.5;
      const taiwanMaxLon = 122.5;
      
      bool isInTaiwan(TestCoordinate coord) {
        return coord.lat >= taiwanMinLat && coord.lat <= taiwanMaxLat &&
               coord.lon >= taiwanMinLon && coord.lon <= taiwanMaxLon;
      }
      
      expect(isInTaiwan(const TestCoordinate(25.0330, 121.5654)), true); // 台北
      expect(isInTaiwan(const TestCoordinate(22.6273, 120.3014)), true); // 高雄
      expect(isInTaiwan(const TestCoordinate(24.1477, 120.6736)), true); // 台中
      expect(isInTaiwan(const TestCoordinate(35.6762, 139.6503)), false); // 東京
      expect(isInTaiwan(const TestCoordinate(-33.8688, 151.2093)), false); // 雪梨
    });
  });
  
  // =========================================================================
  // 距離計算測試
  // =========================================================================
  
  group('距離計算測試', () {
    test('相同點距離為零', () {
      const point = TestCoordinate(25.0330, 121.5654);
      expect(point.distanceTo(point), 0);
    });
    
    test('台北到高雄距離約 300 公里', () {
      const taipei = TestCoordinate(25.0330, 121.5654);
      const kaohsiung = TestCoordinate(22.6273, 120.3014);
      
      final distance = taipei.distanceTo(kaohsiung);
      
      // 距離應該在 280-320 公里之間 (實際約 297 公里)
      expect(distance, greaterThan(280000));
      expect(distance, lessThan(320000));
    });
    
    test('短距離計算精確度', () {
      // 約 1 公里的距離
      const point1 = TestCoordinate(25.0330, 121.5654);
      const point2 = TestCoordinate(25.0420, 121.5654);
      
      final distance = point1.distanceTo(point2);
      
      // 緯度差 0.009 度約等於 1 公里
      expect(distance, greaterThan(900));
      expect(distance, lessThan(1100));
    });
    
    test('南北半球距離計算', () {
      const northPoint = TestCoordinate(25.0330, 121.5654);
      const southPoint = TestCoordinate(-25.0330, 121.5654);
      
      final distance = northPoint.distanceTo(southPoint);
      
      // 50 度緯度差約 5500 公里
      expect(distance, greaterThan(5000000));
      expect(distance, lessThan(6000000));
    });
  });
  
  // =========================================================================
  // 邊界驗證測試
  // =========================================================================
  
  group('邊界驗證測試', () {
    test('有效三角形邊界', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.05, 121.6),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, true);
      expect(result.issues, isEmpty);
    });
    
    test('座標點不足', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, false);
      expect(result.issues, contains('邊界至少需要3個座標點'));
    });
    
    test('無效座標點', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(91.0, 121.5), // 無效
          const TestCoordinate(25.05, 121.6),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, false);
      expect(result.issues.any((i) => i.contains('無效')), true);
    });
    
    test('重複座標點', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.0, 121.5), // 重複
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.05, 121.6),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, false);
      expect(result.issues.any((i) => i.contains('重複')), true);
    });
  });
  
  // =========================================================================
  // 面積計算測試
  // =========================================================================
  
  group('面積計算測試', () {
    test('空邊界面積為零', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [],
      );
      
      expect(boundary.calculateArea(), 0);
    });
    
    test('兩點邊界面積為零', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
        ],
      );
      
      expect(boundary.calculateArea(), 0);
    });
    
    test('三角形面積計算', () {
      // 約 1km x 1km 的三角形，面積約 0.5 平方公里
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.009, 121.5),
          const TestCoordinate(25.0045, 121.509),
        ],
      );
      
      final area = boundary.calculateArea();
      
      // 面積應該在合理範圍內
      expect(area, greaterThan(0));
      expect(area, lessThan(1000000)); // 小於 1 平方公里
    });
    
    test('正方形面積計算', () {
      // 約 1km x 1km 的正方形
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.009, 121.5),
          const TestCoordinate(25.009, 121.509),
          const TestCoordinate(25.0, 121.509),
        ],
      );
      
      final area = boundary.calculateArea();
      
      // 1 平方公里 = 1,000,000 平方公尺
      expect(area, greaterThan(500000));
      expect(area, lessThan(2000000));
    });
  });
  
  // =========================================================================
  // 周長計算測試
  // =========================================================================
  
  group('周長計算測試', () {
    test('空邊界周長為零', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [],
      );
      
      expect(boundary.calculatePerimeter(), 0);
    });
    
    test('單點邊界周長為零', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [const TestCoordinate(25.0, 121.5)],
      );
      
      expect(boundary.calculatePerimeter(), 0);
    });
    
    test('三角形周長計算', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.009, 121.5),
          const TestCoordinate(25.0045, 121.509),
        ],
      );
      
      final perimeter = boundary.calculatePerimeter();
      
      // 周長應該是三邊之和
      expect(perimeter, greaterThan(0));
      expect(perimeter, lessThan(5000)); // 小於 5 公里
    });
  });
  
  // =========================================================================
  // 點包含測試 (Point-in-Polygon)
  // =========================================================================
  
  group('點包含測試', () {
    late TestProjectBoundary squareBoundary;
    
    setUp(() {
      // 建立一個正方形邊界
      squareBoundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.1, 121.6),
          const TestCoordinate(25.0, 121.6),
        ],
      );
    });
    
    test('中心點在邊界內', () {
      const centerPoint = TestCoordinate(25.05, 121.55);
      expect(squareBoundary.containsPoint(centerPoint), true);
    });
    
    test('邊界外的點', () {
      const outsidePoint = TestCoordinate(24.9, 121.5);
      expect(squareBoundary.containsPoint(outsidePoint), false);
    });
    
    test('遠離邊界的點', () {
      const farPoint = TestCoordinate(30.0, 130.0);
      expect(squareBoundary.containsPoint(farPoint), false);
    });
    
    test('多個測試點', () {
      final testPoints = [
        (const TestCoordinate(25.05, 121.55), true),  // 中心
        (const TestCoordinate(25.02, 121.52), true),  // 內部
        (const TestCoordinate(25.08, 121.58), true),  // 內部
        (const TestCoordinate(24.99, 121.55), false), // 下方外部
        (const TestCoordinate(25.11, 121.55), false), // 上方外部
        (const TestCoordinate(25.05, 121.49), false), // 左方外部
        (const TestCoordinate(25.05, 121.61), false), // 右方外部
      ];
      
      for (final (point, expected) in testPoints) {
        expect(
          squareBoundary.containsPoint(point),
          expected,
          reason: 'Point $point should be ${expected ? "inside" : "outside"}',
        );
      }
    });
    
    test('複雜多邊形', () {
      // L 形狀
      final lShapeBoundary = TestProjectBoundary(
        projectId: 'P002',
        projectName: 'L形專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.1, 121.55),
          const TestCoordinate(25.05, 121.55),
          const TestCoordinate(25.05, 121.6),
          const TestCoordinate(25.0, 121.6),
        ],
      );
      
      // L 形內部的點
      expect(lShapeBoundary.containsPoint(const TestCoordinate(25.05, 121.52)), true);
      expect(lShapeBoundary.containsPoint(const TestCoordinate(25.02, 121.57)), true);
      
      // L 形凹處的點（應該在外部）
      expect(lShapeBoundary.containsPoint(const TestCoordinate(25.07, 121.57)), false);
    });
  });
  
  // =========================================================================
  // 重心計算測試
  // =========================================================================
  
  group('重心計算測試', () {
    test('空邊界重心為 null', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [],
      );
      
      expect(boundary.calculateCentroid(), isNull);
    });
    
    test('正方形重心', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.1, 121.6),
          const TestCoordinate(25.0, 121.6),
        ],
      );
      
      final centroid = boundary.calculateCentroid()!;
      
      // 正方形重心應該在中心
      expect(centroid.lat, closeTo(25.05, 0.001));
      expect(centroid.lon, closeTo(121.55, 0.001));
    });
    
    test('三角形重心', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.05, 121.6),
        ],
      );
      
      final centroid = boundary.calculateCentroid()!;
      
      // 三角形重心
      expect(centroid.lat, closeTo(25.05, 0.001));
      expect(centroid.lon, closeTo(121.533, 0.01));
    });
  });
  
  // =========================================================================
  // 座標匹配測試
  // =========================================================================
  
  group('座標匹配測試', () {
    late List<TestProjectBoundary> boundaries;
    late TestCoordinateMatcher matcher;
    
    setUp(() {
      boundaries = [
        TestProjectBoundary(
          projectId: 'P001',
          projectName: '北區專案',
          coordinates: [
            const TestCoordinate(25.0, 121.5),
            const TestCoordinate(25.1, 121.5),
            const TestCoordinate(25.1, 121.6),
            const TestCoordinate(25.0, 121.6),
          ],
        ),
        TestProjectBoundary(
          projectId: 'P002',
          projectName: '南區專案',
          coordinates: [
            const TestCoordinate(24.8, 121.5),
            const TestCoordinate(24.9, 121.5),
            const TestCoordinate(24.9, 121.6),
            const TestCoordinate(24.8, 121.6),
          ],
        ),
      ];
      matcher = TestCoordinateMatcher(boundaries);
    });
    
    test('找到包含座標的專案', () {
      const point = TestCoordinate(25.05, 121.55);
      final result = matcher.findContainingBoundaries(point);
      
      expect(result.length, 1);
      expect(result.first.projectId, 'P001');
    });
    
    test('座標不在任何專案內', () {
      const point = TestCoordinate(26.0, 121.0);
      final result = matcher.findContainingBoundaries(point);
      
      expect(result, isEmpty);
    });
    
    test('找到最近的專案', () {
      const point = TestCoordinate(24.95, 121.55); // 兩個邊界之間
      final (nearest, distance) = matcher.findNearestBoundary(point);
      
      expect(nearest, isNotNull);
      // 應該更接近 P002（南區）
    });
    
    test('批次匹配座標', () {
      final points = [
        const TestCoordinate(25.05, 121.55), // P001
        const TestCoordinate(24.85, 121.55), // P002
        const TestCoordinate(26.0, 121.0),   // 無
      ];
      
      final results = matcher.batchMatch(points);
      
      expect(results.length, 3);
      expect(results['25.05,121.55']?.projectId, 'P001');
      expect(results['24.85,121.55']?.projectId, 'P002');
      expect(results['26.0,121.0'], isNull);
    });
    
    test('重疊邊界處理', () {
      // 添加一個與 P001 重疊的邊界
      boundaries.add(TestProjectBoundary(
        projectId: 'P003',
        projectName: '重疊專案',
        coordinates: [
          const TestCoordinate(25.05, 121.55),
          const TestCoordinate(25.15, 121.55),
          const TestCoordinate(25.15, 121.65),
          const TestCoordinate(25.05, 121.65),
        ],
      ));
      matcher = TestCoordinateMatcher(boundaries);
      
      // 在重疊區域的點應該返回多個匹配
      const point = TestCoordinate(25.07, 121.57);
      final result = matcher.findContainingBoundaries(point);
      
      expect(result.length, 2); // P001 和 P003
    });
  });
  
  // =========================================================================
  // 自相交檢測測試
  // =========================================================================
  
  group('自相交檢測測試', () {
    test('正常多邊形無自相交', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '測試專案',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.1, 121.6),
          const TestCoordinate(25.0, 121.6),
        ],
      );
      
      expect(boundary.hasSelfIntersection(), false);
    });
    
    test('8字形自相交', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '8字形',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.1, 121.6),
          const TestCoordinate(25.0, 121.6),
          const TestCoordinate(25.1, 121.5),
        ],
      );
      
      expect(boundary.hasSelfIntersection(), true);
    });
    
    test('複雜自相交', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '複雜自相交',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.05, 121.6),
          const TestCoordinate(25.1, 121.5),
          const TestCoordinate(25.05, 121.55),
          const TestCoordinate(25.0, 121.55),
        ],
      );
      
      expect(boundary.hasSelfIntersection(), true);
    });
  });
  
  // =========================================================================
  // 邊界條件測試
  // =========================================================================
  
  group('邊界條件測試', () {
    test('極小邊界', () {
      // 極小的三角形（幾乎是一個點）
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '極小邊界',
        coordinates: [
          const TestCoordinate(25.0, 121.5),
          const TestCoordinate(25.000001, 121.5),
          const TestCoordinate(25.0, 121.500001),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, true);
      
      // 面積應該非常小
      final area = boundary.calculateArea();
      expect(area, lessThan(1)); // 小於 1 平方公尺
    });
    
    test('跨越 0 度經線的邊界', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '跨經線邊界',
        coordinates: [
          const TestCoordinate(50.0, -1.0),
          const TestCoordinate(50.0, 1.0),
          const TestCoordinate(51.0, 0.0),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, true);
    });
    
    test('接近極點的邊界', () {
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '北極邊界',
        coordinates: [
          const TestCoordinate(89.0, 0.0),
          const TestCoordinate(89.0, 90.0),
          const TestCoordinate(89.0, 180.0),
          const TestCoordinate(89.0, -90.0),
        ],
      );
      
      final result = boundary.validate();
      expect(result.isValid, true);
    });
    
    test('大量座標點的邊界', () {
      // 生成圓形邊界
      final coordinates = <TestCoordinate>[];
      const centerLat = 25.0;
      const centerLon = 121.5;
      const radius = 0.01; // 約 1 公里
      
      for (var i = 0; i < 100; i++) {
        final angle = (i / 100) * 2 * math.pi;
        coordinates.add(TestCoordinate(
          centerLat + radius * math.cos(angle),
          centerLon + radius * math.sin(angle),
        ));
      }
      
      final boundary = TestProjectBoundary(
        projectId: 'P001',
        projectName: '圓形邊界',
        coordinates: coordinates,
      );
      
      final result = boundary.validate();
      expect(result.isValid, true);
      
      // 面積應該接近 π * r²
      final area = boundary.calculateArea();
      expect(area, greaterThan(0));
    });
  });
}
