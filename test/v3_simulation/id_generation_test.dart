// ============================================================================
// V3 ID 生成系統測試套件
// ============================================================================
// 測試覆蓋:
// - System Tree ID (ST-X) 生成
// - Project Tree ID (PT-X) 生成
// - 佔位記錄排除邏輯
// - 並發 ID 生成
// - ID 唯一性驗證
// ============================================================================

import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用 ID 生成系統
// ============================================================================

/// 樹木記錄
class TestTreeRecord {
  final int id;
  final String systemTreeId;
  final String projectTreeId;
  final String projectCode;
  final String speciesName;
  final bool isPlaceholder;
  
  TestTreeRecord({
    required this.id,
    required this.systemTreeId,
    required this.projectTreeId,
    required this.projectCode,
    this.speciesName = '測試樹種',
    this.isPlaceholder = false,
  });
}

/// ID 生成器
class TestIDGenerator {
  final List<TestTreeRecord> _records = [];
  int _autoIncrementId = 1;
  
  /// 獲取所有記錄
  List<TestTreeRecord> get records => List.unmodifiable(_records);
  
  /// 創建新專案 (會產生佔位記錄)
  TestTreeRecord createProject(String projectCode, String projectName) {
    // 產生下一個系統 ID
    final maxSystemId = _getMaxSystemId(excludePlaceholder: true);
    final systemTreeId = 'PLACEHOLDER-$projectCode';
    
    // 佔位記錄使用 PT-0
    const projectTreeId = 'PT-0';
    
    final record = TestTreeRecord(
      id: _autoIncrementId++,
      systemTreeId: systemTreeId,
      projectTreeId: projectTreeId,
      projectCode: projectCode,
      speciesName: '__PLACEHOLDER__',
      isPlaceholder: true,
    );
    
    _records.add(record);
    return record;
  }
  
  /// 新增樹木記錄 (V2 API)
  TestTreeRecord createTreeV2(String projectCode, String speciesName) {
    // 獲取下一個系統 ID
    final maxSystemId = _getMaxSystemId(excludePlaceholder: true);
    final nextSystemId = maxSystemId + 1;
    final systemTreeId = 'ST-$nextSystemId';
    
    // 獲取下一個專案 ID
    final maxProjectId = _getMaxProjectId(projectCode, excludePlaceholder: true);
    final nextProjectId = maxProjectId + 1;
    final projectTreeId = 'PT-$nextProjectId';
    
    final record = TestTreeRecord(
      id: _autoIncrementId++,
      systemTreeId: systemTreeId,
      projectTreeId: projectTreeId,
      projectCode: projectCode,
      speciesName: speciesName,
      isPlaceholder: false,
    );
    
    _records.add(record);
    return record;
  }
  
  /// 批量新增樹木
  List<TestTreeRecord> batchCreate(String projectCode, int count) {
    final results = <TestTreeRecord>[];
    
    // 獲取起始 ID
    int nextSystemId = _getMaxSystemId(excludePlaceholder: true) + 1;
    int nextProjectId = _getMaxProjectId(projectCode, excludePlaceholder: true) + 1;
    
    for (var i = 0; i < count; i++) {
      final record = TestTreeRecord(
        id: _autoIncrementId++,
        systemTreeId: 'ST-$nextSystemId',
        projectTreeId: 'PT-$nextProjectId',
        projectCode: projectCode,
        speciesName: '批量匯入樹種 $i',
        isPlaceholder: false,
      );
      
      _records.add(record);
      results.add(record);
      
      nextSystemId++;
      nextProjectId++;
    }
    
    return results;
  }
  
  /// 獲取最大系統 ID
  int _getMaxSystemId({bool excludePlaceholder = false}) {
    int maxId = 0;
    
    for (final record in _records) {
      if (excludePlaceholder && record.isPlaceholder) continue;
      if (!record.systemTreeId.startsWith('ST-')) continue;
      
      final numStr = record.systemTreeId.replaceAll(RegExp(r'[^0-9]'), '');
      final num = int.tryParse(numStr) ?? 0;
      if (num > maxId) maxId = num;
    }
    
    return maxId;
  }
  
  /// 獲取專案最大 ID
  int _getMaxProjectId(String projectCode, {bool excludePlaceholder = false}) {
    int maxId = 0;
    
    for (final record in _records) {
      if (record.projectCode != projectCode) continue;
      if (excludePlaceholder && record.isPlaceholder) continue;
      if (record.projectTreeId == 'PT-0') continue; // 排除佔位記錄
      
      final numStr = record.projectTreeId.replaceAll(RegExp(r'[^0-9]'), '');
      final num = int.tryParse(numStr) ?? 0;
      if (num > maxId) maxId = num;
    }
    
    return maxId;
  }
  
  /// 獲取專案的所有記錄
  List<TestTreeRecord> getProjectRecords(String projectCode, {bool includePlaceholder = true}) {
    return _records.where((r) {
      if (r.projectCode != projectCode) return false;
      if (!includePlaceholder && r.isPlaceholder) return false;
      return true;
    }).toList();
  }
  
  /// 獲取下一個專案 ID 預覽
  int getNextProjectId(String projectCode) {
    return _getMaxProjectId(projectCode, excludePlaceholder: true) + 1;
  }
  
  /// 清除所有記錄
  void clear() {
    _records.clear();
    _autoIncrementId = 1;
  }
}

/// 並發 ID 生成模擬器
class TestConcurrentIDSimulator {
  final TestIDGenerator _generator1;
  final TestIDGenerator _generator2;
  
  TestConcurrentIDSimulator()
      : _generator1 = TestIDGenerator(),
        _generator2 = TestIDGenerator();
  
  /// 模擬並發讀取問題 (無鎖定)
  (List<TestTreeRecord>, List<TestTreeRecord>) simulateWithoutLock(
    String projectCode,
    int countEach,
  ) {
    // 同時讀取當前最大 ID
    final startId1 = _generator1._getMaxProjectId(projectCode, excludePlaceholder: true);
    final startId2 = _generator2._getMaxProjectId(projectCode, excludePlaceholder: true);
    
    // 兩個生成器使用相同的起始 ID 生成記錄
    final results1 = <TestTreeRecord>[];
    final results2 = <TestTreeRecord>[];
    
    int nextId1 = startId1 + 1;
    int nextId2 = startId2 + 1;
    
    for (var i = 0; i < countEach; i++) {
      results1.add(TestTreeRecord(
        id: i + 1,
        systemTreeId: 'ST-${i + 1}',
        projectTreeId: 'PT-$nextId1',
        projectCode: projectCode,
      ));
      nextId1++;
      
      results2.add(TestTreeRecord(
        id: i + 100,
        systemTreeId: 'ST-${i + 100}',
        projectTreeId: 'PT-$nextId2',
        projectCode: projectCode,
      ));
      nextId2++;
    }
    
    return (results1, results2);
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  late TestIDGenerator generator;
  
  setUp(() {
    generator = TestIDGenerator();
  });
  
  // =========================================================================
  // 基本 ID 生成測試
  // =========================================================================
  
  group('基本 ID 生成測試', () {
    test('創建新專案產生佔位記錄', () {
      final placeholder = generator.createProject('P001', '測試專案');
      
      expect(placeholder.isPlaceholder, true);
      expect(placeholder.projectTreeId, 'PT-0');
      expect(placeholder.systemTreeId, 'PLACEHOLDER-P001');
      expect(placeholder.speciesName, '__PLACEHOLDER__');
    });
    
    test('第一筆實際資料 ID 為 PT-1', () {
      // 先創建專案（產生佔位記錄）
      generator.createProject('P001', '測試專案');
      
      // 新增第一筆實際資料
      final firstTree = generator.createTreeV2('P001', '樟樹');
      
      expect(firstTree.isPlaceholder, false);
      expect(firstTree.projectTreeId, 'PT-1'); // ⭐ 關鍵測試：第一筆應該是 PT-1
      expect(firstTree.systemTreeId, 'ST-1');
    });
    
    test('連續新增 ID 遞增', () {
      generator.createProject('P001', '測試專案');
      
      final tree1 = generator.createTreeV2('P001', '樟樹');
      final tree2 = generator.createTreeV2('P001', '榕樹');
      final tree3 = generator.createTreeV2('P001', '楓香');
      
      expect(tree1.projectTreeId, 'PT-1');
      expect(tree2.projectTreeId, 'PT-2');
      expect(tree3.projectTreeId, 'PT-3');
      
      expect(tree1.systemTreeId, 'ST-1');
      expect(tree2.systemTreeId, 'ST-2');
      expect(tree3.systemTreeId, 'ST-3');
    });
    
    test('多專案 ID 獨立', () {
      generator.createProject('P001', '專案一');
      generator.createProject('P002', '專案二');
      
      final tree1 = generator.createTreeV2('P001', '樟樹');
      final tree2 = generator.createTreeV2('P002', '榕樹');
      final tree3 = generator.createTreeV2('P001', '楓香');
      final tree4 = generator.createTreeV2('P002', '黑板樹');
      
      // 專案 ID 各自獨立
      expect(tree1.projectTreeId, 'PT-1');
      expect(tree2.projectTreeId, 'PT-1'); // P002 的第一筆也是 PT-1
      expect(tree3.projectTreeId, 'PT-2');
      expect(tree4.projectTreeId, 'PT-2'); // P002 的第二筆
      
      // 系統 ID 全局遞增
      expect(tree1.systemTreeId, 'ST-1');
      expect(tree2.systemTreeId, 'ST-2');
      expect(tree3.systemTreeId, 'ST-3');
      expect(tree4.systemTreeId, 'ST-4');
    });
  });
  
  // =========================================================================
  // 佔位記錄排除測試
  // =========================================================================
  
  group('佔位記錄排除測試', () {
    test('佔位記錄不影響 ID 序列', () {
      // 創建多個專案（每個都有佔位記錄）
      generator.createProject('P001', '專案一');
      generator.createProject('P002', '專案二');
      generator.createProject('P003', '專案三');
      
      // 佔位記錄不應該佔用正常 ID 序列
      final tree1 = generator.createTreeV2('P001', '樟樹');
      
      expect(tree1.systemTreeId, 'ST-1'); // 不是 ST-4
      expect(tree1.projectTreeId, 'PT-1');
    });
    
    test('PT-0 不計入 MAX 計算', () {
      generator.createProject('P001', '測試專案');
      
      // 驗證 getNextProjectId 返回 1
      expect(generator.getNextProjectId('P001'), 1);
      
      // 新增第一筆資料後
      generator.createTreeV2('P001', '樟樹');
      
      // 下一個應該是 2
      expect(generator.getNextProjectId('P001'), 2);
    });
    
    test('getProjectRecords 可選擇包含/排除佔位記錄', () {
      generator.createProject('P001', '測試專案');
      generator.createTreeV2('P001', '樟樹');
      generator.createTreeV2('P001', '榕樹');
      
      // 包含佔位記錄
      final allRecords = generator.getProjectRecords('P001', includePlaceholder: true);
      expect(allRecords.length, 3);
      
      // 排除佔位記錄
      final realRecords = generator.getProjectRecords('P001', includePlaceholder: false);
      expect(realRecords.length, 2);
      expect(realRecords.every((r) => !r.isPlaceholder), true);
    });
  });
  
  // =========================================================================
  // 批量匯入測試
  // =========================================================================
  
  group('批量匯入測試', () {
    test('批量匯入 ID 連續', () {
      generator.createProject('P001', '測試專案');
      
      final batch = generator.batchCreate('P001', 10);
      
      expect(batch.length, 10);
      
      // 驗證 ID 連續
      for (var i = 0; i < batch.length; i++) {
        expect(batch[i].projectTreeId, 'PT-${i + 1}');
        expect(batch[i].systemTreeId, 'ST-${i + 1}');
      }
    });
    
    test('批量匯入後繼續新增', () {
      generator.createProject('P001', '測試專案');
      generator.batchCreate('P001', 5);
      
      final nextTree = generator.createTreeV2('P001', '新樹');
      
      expect(nextTree.projectTreeId, 'PT-6');
      expect(nextTree.systemTreeId, 'ST-6');
    });
    
    test('混合批量和單筆', () {
      generator.createProject('P001', '測試專案');
      
      generator.createTreeV2('P001', '樹1'); // PT-1
      generator.batchCreate('P001', 3);       // PT-2, 3, 4
      generator.createTreeV2('P001', '樹5'); // PT-5
      generator.batchCreate('P001', 2);       // PT-6, 7
      
      final records = generator.getProjectRecords('P001', includePlaceholder: false);
      
      expect(records.length, 7);
      
      // 驗證 ID 序列正確
      final projectIds = records.map((r) => r.projectTreeId).toList();
      expect(projectIds, ['PT-1', 'PT-2', 'PT-3', 'PT-4', 'PT-5', 'PT-6', 'PT-7']);
    });
  });
  
  // =========================================================================
  // 多專案交互測試
  // =========================================================================
  
  group('多專案交互測試', () {
    test('交替新增多專案', () {
      generator.createProject('P001', '專案一');
      generator.createProject('P002', '專案二');
      
      generator.createTreeV2('P001', 'A1'); // P001: PT-1, ST-1
      generator.createTreeV2('P002', 'B1'); // P002: PT-1, ST-2
      generator.createTreeV2('P001', 'A2'); // P001: PT-2, ST-3
      generator.createTreeV2('P002', 'B2'); // P002: PT-2, ST-4
      
      final p1Records = generator.getProjectRecords('P001', includePlaceholder: false);
      final p2Records = generator.getProjectRecords('P002', includePlaceholder: false);
      
      expect(p1Records.map((r) => r.projectTreeId).toList(), ['PT-1', 'PT-2']);
      expect(p2Records.map((r) => r.projectTreeId).toList(), ['PT-1', 'PT-2']);
      
      // 系統 ID 全局連續
      final allRecords = generator.records.where((r) => !r.isPlaceholder).toList();
      final systemIds = allRecords.map((r) => r.systemTreeId).toList();
      expect(systemIds, ['ST-1', 'ST-2', 'ST-3', 'ST-4']);
    });
    
    test('大量專案', () {
      // 創建 100 個專案
      for (var i = 1; i <= 100; i++) {
        generator.createProject('P${i.toString().padLeft(3, '0')}', '專案$i');
      }
      
      // 每個專案新增一筆
      for (var i = 1; i <= 100; i++) {
        final projectCode = 'P${i.toString().padLeft(3, '0')}';
        generator.createTreeV2(projectCode, '樹$i');
      }
      
      // 驗證每個專案的第一筆都是 PT-1
      for (var i = 1; i <= 100; i++) {
        final projectCode = 'P${i.toString().padLeft(3, '0')}';
        final records = generator.getProjectRecords(projectCode, includePlaceholder: false);
        expect(records.first.projectTreeId, 'PT-1',
            reason: '專案 $projectCode 的第一筆應該是 PT-1');
      }
    });
  });
  
  // =========================================================================
  // 並發問題模擬測試
  // =========================================================================
  
  group('並發問題模擬測試', () {
    test('無鎖定情況下的 ID 衝突', () {
      final simulator = TestConcurrentIDSimulator();
      
      // 模擬兩個客戶端同時讀取相同的起始 ID
      final (results1, results2) = simulator.simulateWithoutLock('P001', 5);
      
      // 兩個結果應該有重複的 project_tree_id
      final ids1 = results1.map((r) => r.projectTreeId).toSet();
      final ids2 = results2.map((r) => r.projectTreeId).toSet();
      
      // 有交集 = 有衝突
      final intersection = ids1.intersection(ids2);
      expect(intersection.isNotEmpty, true,
          reason: '無鎖定情況下應該產生 ID 衝突');
    });
    
    test('使用鎖定機制避免衝突', () {
      generator.createProject('P001', '測試專案');
      
      // 模擬有鎖定的情況：順序執行
      final results = <TestTreeRecord>[];
      
      for (var i = 0; i < 10; i++) {
        results.add(generator.createTreeV2('P001', '樹$i'));
      }
      
      // 所有 ID 應該唯一
      final ids = results.map((r) => r.projectTreeId).toSet();
      expect(ids.length, 10, reason: '有鎖定情況下所有 ID 應該唯一');
    });
  });
  
  // =========================================================================
  // 邊界條件測試
  // =========================================================================
  
  group('邊界條件測試', () {
    test('空專案的第一筆資料', () {
      // 不創建佔位記錄，直接新增
      final tree = generator.createTreeV2('P001', '樟樹');
      
      expect(tree.projectTreeId, 'PT-1');
      expect(tree.systemTreeId, 'ST-1');
    });
    
    test('大量記錄後的 ID', () {
      generator.createProject('P001', '測試專案');
      
      // 新增 1000 筆
      generator.batchCreate('P001', 1000);
      
      final nextTree = generator.createTreeV2('P001', '第1001棵');
      
      expect(nextTree.projectTreeId, 'PT-1001');
    });
    
    test('清除後重新開始', () {
      generator.createProject('P001', '測試專案');
      generator.createTreeV2('P001', '樟樹');
      
      generator.clear();
      
      generator.createProject('P002', '新專案');
      final tree = generator.createTreeV2('P002', '新樹');
      
      expect(tree.projectTreeId, 'PT-1');
      expect(tree.systemTreeId, 'ST-1');
    });
  });
  
  // =========================================================================
  // ID 唯一性驗證測試
  // =========================================================================
  
  group('ID 唯一性驗證測試', () {
    test('系統 ID 全局唯一', () {
      generator.createProject('P001', '專案一');
      generator.createProject('P002', '專案二');
      
      // 兩個專案各新增 50 筆
      generator.batchCreate('P001', 50);
      generator.batchCreate('P002', 50);
      
      final allRecords = generator.records.where((r) => !r.isPlaceholder);
      final systemIds = allRecords.map((r) => r.systemTreeId).toSet();
      
      expect(systemIds.length, 100, reason: '所有系統 ID 應該唯一');
    });
    
    test('專案內 ID 唯一', () {
      generator.createProject('P001', '測試專案');
      generator.batchCreate('P001', 100);
      
      final records = generator.getProjectRecords('P001', includePlaceholder: false);
      final projectIds = records.map((r) => r.projectTreeId).toSet();
      
      expect(projectIds.length, 100, reason: '專案內所有 ID 應該唯一');
    });
    
    test('ID 格式正確', () {
      generator.createProject('P001', '測試專案');
      
      for (var i = 0; i < 20; i++) {
        generator.createTreeV2('P001', '樹$i');
      }
      
      final records = generator.getProjectRecords('P001', includePlaceholder: false);
      
      for (final record in records) {
        expect(record.systemTreeId, matches(RegExp(r'^ST-\d+$')));
        expect(record.projectTreeId, matches(RegExp(r'^PT-\d+$')));
      }
    });
  });
}
