/// 兩階段測量工作流程模擬測試
/// 
/// 此測試使用 test/fixtures/vlgeo2 中的實際 VLGEO2 數據來驗證：
/// 1. 測站位置計算公式的正確性
/// 2. 完整的兩階段工作流程
/// 3. AR 測量模擬
/// 
/// 不修改 lib 中的程式碼，獨立運行

import 'dart:math';
import 'dart:io';

/// =====================================================
/// 測站位置計算 (從 pending_tree_measurement.dart 複製)
/// =====================================================

class StationPosition {
  final double lat;
  final double lon;
  StationPosition(this.lat, this.lon);
  
  @override
  String toString() => 'StationPosition(lat: $lat, lon: $lon)';
}

/// 從樹木座標和 VLGEO2 測量數據計算測站（測量員）位置
/// 
/// 原理：
/// - VLGEO2 記錄的是從測量員位置測量到樹木的數據
/// - 方位角 (azimuth) 是從測量員看向樹木的方向（從北順時針）
/// - 我們需要反向計算：從樹木位置反推測量員位置
StationPosition calculateStationPosition({
  required double treeLat,
  required double treeLon,
  required double horizontalDistance,
  required double azimuth,
}) {
  // 每度緯度約 111320 公尺
  const double metersPerDegreeLat = 111320.0;
  
  // 反向方位角（加 180 度）- 用於計算測站位置
  // 原始方位角 azimuth 只用於計算反向
  final double reverseAzimuthRad = (azimuth + 180) * pi / 180.0;
  
  // 計算經度方向的縮放因子
  final double metersPerDegreeLon = metersPerDegreeLat * cos(treeLat * pi / 180.0);
  
  // 測站在樹木的反方向
  // ΔLat = distance * cos(reverseAzimuth) / metersPerDegreeLat
  // ΔLon = distance * sin(reverseAzimuth) / metersPerDegreeLon
  final double deltaLat = (horizontalDistance * cos(reverseAzimuthRad)) / metersPerDegreeLat;
  final double deltaLon = (horizontalDistance * sin(reverseAzimuthRad)) / metersPerDegreeLon;
  
  final double stationLat = treeLat + deltaLat;
  final double stationLon = treeLon + deltaLon;
  
  return StationPosition(stationLat, stationLon);
}

/// 計算兩點之間的距離（Haversine 公式）
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double R = 6371000; // 地球半徑（公尺）
  
  final double dLat = (lat2 - lat1) * pi / 180.0;
  final double dLon = (lon2 - lon1) * pi / 180.0;
  
  final double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180.0) * cos(lat2 * pi / 180.0) *
      sin(dLon / 2) * sin(dLon / 2);
  
  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
  
  return R * c;
}

/// 計算從點 A 到點 B 的方位角
double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
  final double dLon = (lon2 - lon1) * pi / 180.0;
  final double lat1Rad = lat1 * pi / 180.0;
  final double lat2Rad = lat2 * pi / 180.0;
  
  final double x = cos(lat2Rad) * sin(dLon);
  final double y = cos(lat1Rad) * sin(lat2Rad) - 
      sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
  
  double bearing = atan2(x, y) * 180.0 / pi;
  return (bearing + 360) % 360;
}

/// =====================================================
/// VLGEO2 數據解析
/// =====================================================

class VlgeoRecord {
  final String id;
  final String type;
  final double? lat;
  final double? lon;
  final double? altitude;
  final double? horizontalDistance;  // HD
  final double? slopeDistance;       // SD
  final double? height;              // H (樹高)
  final double? pitch;               // 俯仰角
  final double? azimuth;             // AZ 方位角
  final int? seq;                    // 序號
  
  VlgeoRecord({
    required this.id,
    required this.type,
    this.lat,
    this.lon,
    this.altitude,
    this.horizontalDistance,
    this.slopeDistance,
    this.height,
    this.pitch,
    this.azimuth,
    this.seq,
  });
  
  bool get hasValidPosition => lat != null && lon != null && lat != 0 && lon != 0;
  bool get hasValidMeasurement => horizontalDistance != null && azimuth != null;
  
  @override
  String toString() => 'VlgeoRecord(id: $id, lat: $lat, lon: $lon, HD: $horizontalDistance, AZ: $azimuth)';
}

/// 解析 VLGEO2 CSV 資料
List<VlgeoRecord> parseVlgeoCsv(String csvContent) {
  final List<VlgeoRecord> records = [];
  final lines = csvContent.split('\n');
  
  // 解析 header 獲取欄位索引
  final header = lines[0].split(';');
  final indices = <String, int>{};
  for (int i = 0; i < header.length; i++) {
    indices[header[i].trim()] = i;
  }
  
  // 解析資料行
  for (int i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty || !line.startsWith('\$')) continue;
    
    final parts = line.split(';');
    if (parts.length < 20) continue;
    
    try {
      double? parseDouble(String? s) {
        if (s == null || s.isEmpty) return null;
        return double.tryParse(s);
      }
      
      int? parseInt(String? s) {
        if (s == null || s.isEmpty) return null;
        return int.tryParse(s);
      }
      
      String? getValue(String key) {
        final idx = indices[key];
        if (idx == null || idx >= parts.length) return null;
        return parts[idx].trim();
      }
      
      records.add(VlgeoRecord(
        id: getValue('ID') ?? '',
        type: getValue('TYPE') ?? '',
        lat: parseDouble(getValue('LAT')),
        lon: parseDouble(getValue('LON')),
        altitude: parseDouble(getValue('ALTITUDE')),
        horizontalDistance: parseDouble(getValue('HD')),
        slopeDistance: parseDouble(getValue('SD')),
        height: parseDouble(getValue('H')),
        pitch: parseDouble(getValue('PITCH')),
        azimuth: parseDouble(getValue('AZ')),
        seq: parseInt(getValue('SEQ')),
      ));
    } catch (e) {
      print('解析行 $i 失敗: $e');
    }
  }
  
  return records;
}

/// =====================================================
/// 測試案例
/// =====================================================

void main() async {
  print('========================================');
  print('兩階段測量工作流程模擬測試');
  print('========================================\n');
  
  // 測試 1: 公式對稱性驗證
  testFormulaSymmetry();
  
  // 測試 2: 特殊角度驗證
  testSpecialAngles();
  
  // 測試 3: 使用實際 VLGEO2 數據
  await testWithRealData();
  
  // 測試 4: 完整工作流程模擬
  await testFullWorkflow();
  
  print('\n========================================');
  print('所有測試完成');
  print('========================================');
}

/// 測試 1: 公式對稱性驗證
/// 從測站計算到樹木，再從樹木反推測站，應該得到相同結果
void testFormulaSymmetry() {
  print('--- 測試 1: 公式對稱性驗證 ---\n');
  
  // 假設測站位置
  final double stationLat = 23.8960000;
  final double stationLon = 121.5480000;
  
  // 測量參數
  final double distance = 15.0;  // 15 公尺
  final double azimuth = 45.0;   // 東北方向
  
  // 正向計算：從測站計算樹木位置
  final double azimuthRad = azimuth * pi / 180.0;
  const double metersPerDegreeLat = 111320.0;
  final double metersPerDegreeLon = metersPerDegreeLat * cos(stationLat * pi / 180.0);
  
  final double deltaLat = (distance * cos(azimuthRad)) / metersPerDegreeLat;
  final double deltaLon = (distance * sin(azimuthRad)) / metersPerDegreeLon;
  
  final double treeLat = stationLat + deltaLat;
  final double treeLon = stationLon + deltaLon;
  
  print('原始測站: ($stationLat, $stationLon)');
  print('正向計算樹木位置: ($treeLat, $treeLon)');
  
  // 反向計算：從樹木位置反推測站
  final StationPosition calculated = calculateStationPosition(
    treeLat: treeLat,
    treeLon: treeLon,
    horizontalDistance: distance,
    azimuth: azimuth,
  );
  
  print('反向計算測站位置: (${calculated.lat}, ${calculated.lon})');
  
  // 計算誤差
  final double latError = (calculated.lat - stationLat).abs();
  final double lonError = (calculated.lon - stationLon).abs();
  final double distanceError = calculateDistance(stationLat, stationLon, calculated.lat, calculated.lon);
  
  print('緯度誤差: $latError 度');
  print('經度誤差: $lonError 度');
  print('距離誤差: ${distanceError.toStringAsFixed(4)} 公尺');
  
  if (distanceError < 0.01) {
    print('✅ 對稱性測試通過（誤差 < 0.01 公尺）\n');
  } else {
    print('❌ 對稱性測試失敗\n');
  }
}

/// 測試 2: 特殊角度驗證
void testSpecialAngles() {
  print('--- 測試 2: 特殊角度驗證 ---\n');
  
  final double treeLat = 23.8960000;
  final double treeLon = 121.5480000;
  final double distance = 10.0;
  
  final testCases = [
    {'azimuth': 0.0, 'expected': '測站在樹木正南方'},
    {'azimuth': 90.0, 'expected': '測站在樹木正西方'},
    {'azimuth': 180.0, 'expected': '測站在樹木正北方'},
    {'azimuth': 270.0, 'expected': '測站在樹木正東方'},
  ];
  
  for (final tc in testCases) {
    final double azimuth = tc['azimuth'] as double;
    final String expected = tc['expected'] as String;
    
    final station = calculateStationPosition(
      treeLat: treeLat,
      treeLon: treeLon,
      horizontalDistance: distance,
      azimuth: azimuth,
    );
    
    final double latDiff = station.lat - treeLat;
    final double lonDiff = station.lon - treeLon;
    
    String actual;
    if (latDiff < -0.00001 && lonDiff.abs() < 0.00001) {
      actual = '測站在樹木正南方';
    } else if (latDiff > 0.00001 && lonDiff.abs() < 0.00001) {
      actual = '測站在樹木正北方';
    } else if (lonDiff < -0.00001 && latDiff.abs() < 0.00001) {
      actual = '測站在樹木正西方';
    } else if (lonDiff > 0.00001 && latDiff.abs() < 0.00001) {
      actual = '測站在樹木正東方';
    } else {
      actual = '未知方向 (latDiff: $latDiff, lonDiff: $lonDiff)';
    }
    
    final bool passed = actual == expected;
    print('方位角 ${azimuth.toInt()}°: $expected');
    print('  計算結果: $actual');
    print('  ${passed ? '✅' : '❌'}\n');
  }
}

/// 測試 3: 使用實際 VLGEO2 數據
Future<void> testWithRealData() async {
  print('--- 測試 3: 實際 VLGEO2 數據驗證 ---\n');
  
  // 讀取 CSV 檔案
  final String csvPath = '../fixtures/vlgeo2/DATA_2.CSV';
  final File file = File(csvPath);
  
  if (!await file.exists()) {
    print('⚠️ 找不到測試數據檔案: $csvPath');
    print('請確保在 frontend 目錄下執行此測試\n');
    return;
  }
  
  final String content = await file.readAsString();
  final List<VlgeoRecord> records = parseVlgeoCsv(content);
  
  print('解析到 ${records.length} 筆記錄\n');
  
  // 篩選有完整數據的記錄
  final validRecords = records.where((r) => 
    r.hasValidPosition && r.hasValidMeasurement
  ).toList();
  
  print('有效記錄（含位置和測量數據）: ${validRecords.length} 筆\n');
  
  if (validRecords.isEmpty) {
    print('⚠️ 沒有找到有效的記錄\n');
    return;
  }
  
  // 分析數據
  print('=== 數據統計 ===');
  final distances = validRecords.map((r) => r.horizontalDistance!).toList();
  distances.sort();
  print('水平距離範圍: ${distances.first.toStringAsFixed(1)} - ${distances.last.toStringAsFixed(1)} 公尺');
  print('平均距離: ${(distances.reduce((a, b) => a + b) / distances.length).toStringAsFixed(1)} 公尺');
  
  // 群組分析：根據相似的測站位置
  print('\n=== 測站位置分析 ===');
  
  final Map<String, List<VlgeoRecord>> stationGroups = {};
  
  for (final record in validRecords) {
    final station = calculateStationPosition(
      treeLat: record.lat!,
      treeLon: record.lon!,
      horizontalDistance: record.horizontalDistance!,
      azimuth: record.azimuth!,
    );
    
    // 使用 5 位小數作為群組 key（約 1 公尺精度）
    final key = '${station.lat.toStringAsFixed(5)}_${station.lon.toStringAsFixed(5)}';
    stationGroups.putIfAbsent(key, () => []).add(record);
  }
  
  print('推算出 ${stationGroups.length} 個測站位置');
  
  // 顯示最大的幾個測站群組
  final sortedGroups = stationGroups.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  
  print('\n前 5 個最常用的測站:');
  for (int i = 0; i < min(5, sortedGroups.length); i++) {
    final entry = sortedGroups[i];
    final parts = entry.key.split('_');
    print('  測站 ${i + 1}: (${parts[0]}, ${parts[1]}) - ${entry.value.length} 棵樹');
  }
  
  print('\n✅ 實際數據測試完成\n');
}

/// 測試 4: 完整工作流程模擬
Future<void> testFullWorkflow() async {
  print('--- 測試 4: 完整工作流程模擬 ---\n');
  
  // 模擬階段 1: VLGEO2 測量數據
  final mockBleData = [
    {
      'id': '10001',
      'lat': 23.8962222,
      'lon': 121.5481563,
      'height': 5.9,
      'metadata': {
        'horizontal_distance': 5.7,
        'azimuth': 226.3,
        'pitch': 14.0,
      },
    },
    {
      'id': '10002',
      'lat': 23.8962243,
      'lon': 121.5481460,
      'height': 13.0,
      'metadata': {
        'horizontal_distance': 12.9,
        'azimuth': 239.7,
        'pitch': -5.6,
      },
    },
    {
      'id': '10003',
      'lat': 23.8956676,
      'lon': 121.5478443,
      'height': 3.2,
      'metadata': {
        'horizontal_distance': 3.1,
        'azimuth': 244.0,
        'pitch': -17.4,
      },
    },
  ];
  
  print('階段 1: 接收到 ${mockBleData.length} 棵樹的 BLE 數據\n');
  
  // 計算每棵樹的測站位置
  final List<Map<String, dynamic>> pendingMeasurements = [];
  
  for (final data in mockBleData) {
    final meta = data['metadata'] as Map<String, dynamic>;
    final station = calculateStationPosition(
      treeLat: data['lat'] as double,
      treeLon: data['lon'] as double,
      horizontalDistance: meta['horizontal_distance'] as double,
      azimuth: meta['azimuth'] as double,
    );
    
    pendingMeasurements.add({
      'id': data['id'],
      'tree_lat': data['lat'],
      'tree_lon': data['lon'],
      'tree_height': data['height'],
      'station_lat': station.lat,
      'station_lon': station.lon,
      'horizontal_distance': meta['horizontal_distance'],
      'azimuth': meta['azimuth'],
      'status': 'pending',
    });
    
    print('樹木 ${data['id']}:');
    print('  位置: (${data['lat']}, ${data['lon']})');
    print('  測站: (${station.lat.toStringAsFixed(7)}, ${station.lon.toStringAsFixed(7)})');
    print('  距離: ${meta['horizontal_distance']}m, 方位: ${meta['azimuth']}°\n');
  }
  
  print('階段 1 完成: 創建 ${pendingMeasurements.length} 筆待測量記錄\n');
  
  // 模擬階段 2: AR 測量 DBH
  print('階段 2: 模擬 AR 測量\n');
  
  // 模擬測量員的當前位置（假設在第一棵樹的測站附近）
  final double userLat = pendingMeasurements[0]['station_lat'] as double;
  final double userLon = pendingMeasurements[0]['station_lon'] as double;
  
  print('測量員位置: ($userLat, $userLon)\n');
  
  // 按距離排序
  pendingMeasurements.sort((a, b) {
    final distA = calculateDistance(
      userLat, userLon,
      a['station_lat'] as double, a['station_lon'] as double,
    );
    final distB = calculateDistance(
      userLat, userLon,
      b['station_lat'] as double, b['station_lon'] as double,
    );
    return distA.compareTo(distB);
  });
  
  for (final measurement in pendingMeasurements) {
    final distance = calculateDistance(
      userLat, userLon,
      measurement['station_lat'] as double, measurement['station_lon'] as double,
    );
    
    // 模擬 AR 測量結果
    final double simulatedDbh = 15.0 + (measurement['id'].hashCode % 30);
    
    print('樹木 ${measurement['id']}:');
    print('  到測站距離: ${distance.toStringAsFixed(1)}m');
    print('  模擬 AR 測量 DBH: ${simulatedDbh.toStringAsFixed(1)}cm');
    
    // 更新狀態
    measurement['dbh_cm'] = simulatedDbh;
    measurement['status'] = 'completed';
    measurement['measured_at'] = DateTime.now().toIso8601String();
    
    print('  狀態: completed ✅\n');
  }
  
  print('階段 2 完成: 所有樹木測量完成\n');
  
  // 輸出最終結果
  print('=== 最終數據 ===\n');
  for (final m in pendingMeasurements) {
    print('${m['id']}: DBH=${m['dbh_cm']}cm, H=${m['tree_height']}m, Status=${m['status']}');
  }
  
  print('\n✅ 完整工作流程模擬成功\n');
}
