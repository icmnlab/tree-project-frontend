/// V3 數據過濾服務測試
/// 測試不完整資料過濾和重複資料過濾邏輯

import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/services/v3/data_filter_service.dart';

/// 韌體 CSV 必有 TYPE；測試列預設 1P。
Map<String, dynamic> _tp(Map<String, dynamic> row) => {'type': '1P', ...row};

void main() {
  group('DataFilterService 測試', () {
    test('過濾不完整資料 - 缺少 id（唯一必要欄位）', () {
      // v21.0：上游 BleDataProcessor 已驗過 GPS/HD/AZ，過濾層只要求 id 存在；
      // 缺 height 或缺座標不再判為不完整（HEIGHT DME 等可無 GPS）。
      final testData = [
        _tp({
          'id': '10001',
          'lat': 25.0330,
          'lon': 121.5654,
          'height': 12.5,
        }),
        _tp({
          'id': '',
          'lat': 25.0331,
          'lon': 121.5655,
          'height': 10.0,
        }),
        _tp({
          'id': '10003',
          'lat': 25.0332,
          'lon': 121.5656,
        }),
      ];

      final result = DataFilterService.filterBleData(testData);

      expect(result.validRecords.length, 2,
          reason: '有 id 即視為完整（缺 height/座標不再判為不完整）');
      expect(result.incompleteRecords.length, 1,
          reason: '只有空 id 那筆不完整');
      expect(result.stats.incompleteCount, 1);
      expect(result.stats.missingFieldCounts['id'], 1);
    });

    test('過濾重複資料 - 同 id 同座標保留最後一筆', () {
      // v21.0：座標鍵含 id（同測站可量多棵樹），故「重複」需 id+座標都相同。
      final now = DateTime.now();
      final testData = [
        _tp({
          'id': '10001',
          'lat': 25.033000,
          'lon': 121.565400,
          'height': 12.5,
          'timestamp': now.subtract(const Duration(minutes: 10)),
        }),
        _tp({
          'id': '10001',
          'lat': 25.033000,
          'lon': 121.565400,
          'height': 13.0,
          'timestamp': now.subtract(const Duration(minutes: 5)),
        }),
        _tp({
          'id': '10001',
          'lat': 25.033000,
          'lon': 121.565400,
          'height': 14.0,
          'timestamp': now,
        }),
        _tp({
          'id': '10004',
          'lat': 25.034000,
          'lon': 121.566000,
          'height': 10.0,
          'timestamp': now,
        }),
      ];

      final result = DataFilterService.filterBleData(testData);

      expect(result.validRecords.length, 2,
          reason: '同 id 同座標 3 筆收斂為 1，加上另一棵不同 id');
      expect(result.duplicateRecords.length, 2,
          reason: '2 筆被過濾的重複記錄');

      // 確認保留的是最後一筆（最新 timestamp，height=14.0）
      final keptRecord = result.validRecords
          .firstWhere((r) => r['id'] == '10001');
      expect(keptRecord['height'], 14.0);
    });

    test('座標精度到小數點後 6 位', () {
      final testData = [
        _tp({
          'id': '10001',
          'lat': 25.0330001,
          'lon': 121.5654001,
          'height': 12.5,
        }),
        _tp({
          'id': '10002',
          'lat': 25.0330009,
          'lon': 121.5654009,
          'height': 13.0,
        }),
      ];

      final result = DataFilterService.filterBleData(testData);

      // 由於精度到小數點後 6 位，0.0330001 和 0.0330009 會產生不同的 key
      // 所以這兩筆會被視為不同位置
      expect(result.validRecords.length, 2,
          reason: '座標差異在第 6-7 位，會被視為不同位置');
    });

    test('南北半球座標處理', () {
      final testData = [
        _tp({'id': '10001', 'lat': 25.0330, 'lon': 121.5654, 'height': 12.5}),
        _tp({'id': '10002', 'lat': -25.0330, 'lon': 121.5654, 'height': 12.5}),
        _tp({'id': '10003', 'lat': 25.0330, 'lon': -121.5654, 'height': 12.5}),
      ];

      final result = DataFilterService.filterBleData(testData);

      expect(result.validRecords.length, 3,
          reason: '南北半球和東西半球的座標應被視為不同位置');
      expect(result.duplicateRecords.length, 0);
    });

    test('與已存在資料比對', () {
      // v21.0：座標鍵含 id，故「已存在」需 id+座標都相同才會被過濾。
      final existingData = [
        _tp({'id': 'existing_1', 'lat': 25.0330, 'lon': 121.5654}),
      ];

      final newData = [
        _tp({
          'id': 'existing_1',
          'lat': 25.0330,
          'lon': 121.5654,
          'height': 12.5,
        }),
        _tp({
          'id': '10002',
          'lat': 25.0340,
          'lon': 121.5660,
          'height': 10.0,
        }),
      ];

      final result = DataFilterService.filterBleData(
        newData,
        existingRecords: existingData,
      );

      expect(result.validRecords.length, 1,
          reason: '同 id 同座標、已存在於資料庫的應被過濾');
      expect(result.validRecords.first['id'], '10002');
    });

    test('keepIncomplete 選項', () {
      // 空 id → 不完整；keepIncomplete 決定是否仍保留。
      final testData = [
        _tp({'id': '', 'lat': 25.0330, 'lon': 121.5654, 'height': 12.5}),
      ];

      // 預設不保留
      final result1 = DataFilterService.filterBleData(testData);
      expect(result1.validRecords.length, 0);

      // 設定保留
      final result2 = DataFilterService.filterBleData(
        testData,
        options: FilterOptions(keepIncomplete: true),
      );
      expect(result2.validRecords.length, 1);
    });

    test('距離計算正確性', () {
      // 測試兩個已知位置的距離計算
      // 使用簡單的測試案例：相同經度上的兩點
      // 1 度緯度約 111 km，所以 0.01 度約 1.1 km
      final distance = DataFilterService.calculateDistance(
        25.0000, 121.5654,
        25.0100, 121.5654,
      );

      // 0.01 度緯度約 1100 公尺，允許 20% 誤差
      expect(distance, greaterThan(900));
      expect(distance, lessThan(1300));
    });

    test('統計報告生成', () {
      // 同 id+座標+height → 精確重複；空 id → 不完整。
      final testData = [
        _tp({'id': '1', 'lat': 25.0, 'lon': 121.0, 'height': 10.0}),
        _tp({'id': '1', 'lat': 25.0, 'lon': 121.0, 'height': 10.0}),
        _tp({'id': '', 'lat': 25.1, 'lon': 121.1, 'height': 5.0}),
      ];

      final result = DataFilterService.filterBleData(testData);

      expect(result.stats.totalInput, 3);
      expect(result.stats.validCount, 1);
      expect(result.stats.incompleteCount, 1);
      expect(result.stats.duplicateCount, 1);
      expect(result.stats.duplicateGroups.length, 1);
    });

    test('HEIGHT DME 保留、校準 DME 丟棄', () {
      final testData = [
        {
          'id': '2',
          'type': 'DME',
          'height': 2.5,
          'metadata': {'horizontal_distance': 3.6},
        },
        {
          'id': '',
          'type': 'DME',
          'height': 0.0,
          'metadata': {'horizontal_distance': 1.0},
        },
        {
          'id': '5',
          'type': '3D',
          'height': 1.0,
          'metadata': {'horizontal_distance': 2.0},
        },
      ];

      final result = DataFilterService.filterBleData(testData);

      expect(result.validRecords.length, 1);
      expect(result.validRecords.first['id'], '2');
      expect(result.stats.nonTreeDropped, 2);
    });
  });

  group('座標比對測試', () {
    test('isCoordinateMatch - 使用距離閾值', () {
      // 相同位置應匹配
      final isMatch = DataFilterService.isCoordinateMatch(
        25.033000, 121.565400,
        25.033000, 121.565400,
        toleranceMeters: 1.0,
      );

      expect(isMatch, true);
    });

    test('isCoordinateMatch - 超出容差', () {
      // 較遠的兩點（約 10+ 公尺）
      final isMatch = DataFilterService.isCoordinateMatch(
        25.033000, 121.565400,
        25.033100, 121.565500,
        toleranceMeters: 1.0,
      );

      expect(isMatch, false);
    });
  });
}
