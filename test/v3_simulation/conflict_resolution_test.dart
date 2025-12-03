// ============================================================================
// V3 衝突解決服務完整測試套件
// ============================================================================
// 測試覆蓋:
// - Race Condition 處理
// - 樂觀鎖定 (Optimistic Locking)
// - 版本控制與合併
// - 衝突檢測與解決策略
// - 資料一致性驗證
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用衝突解決核心類別
// ============================================================================

/// 版本控制記錄
class TestVersionedRecord {
  final String id;
  final int version;
  final Map<String, dynamic> data;
  final DateTime timestamp;
  final String? modifiedBy;
  
  TestVersionedRecord({
    required this.id,
    required this.version,
    required this.data,
    DateTime? timestamp,
    this.modifiedBy,
  }) : timestamp = timestamp ?? DateTime.now();
  
  TestVersionedRecord copyWithVersion(int newVersion, Map<String, dynamic> newData) {
    return TestVersionedRecord(
      id: id,
      version: newVersion,
      data: newData,
      modifiedBy: modifiedBy,
    );
  }
  
  TestVersionedRecord merge(TestVersionedRecord other) {
    // 合併策略：較新的值優先
    final mergedData = Map<String, dynamic>.from(data);
    for (final entry in other.data.entries) {
      if (!mergedData.containsKey(entry.key) || 
          other.timestamp.isAfter(timestamp)) {
        mergedData[entry.key] = entry.value;
      }
    }
    return TestVersionedRecord(
      id: id,
      version: math.max(version, other.version) + 1,
      data: mergedData,
    );
  }
}

/// 衝突類型
enum ConflictType {
  versionMismatch,
  concurrentModification,
  dataIntegrity,
  lockTimeout,
  networkPartition,
}

/// 衝突資訊
class TestConflict {
  final String recordId;
  final ConflictType type;
  final TestVersionedRecord? localVersion;
  final TestVersionedRecord? remoteVersion;
  final DateTime detectedAt;
  
  TestConflict({
    required this.recordId,
    required this.type,
    this.localVersion,
    this.remoteVersion,
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();
}

/// 衝突解決策略
enum ConflictResolutionStrategy {
  /// 本地版本優先
  localWins,
  /// 遠端版本優先
  remoteWins,
  /// 最新時間戳優先
  latestWins,
  /// 合併所有變更
  merge,
  /// 手動解決
  manual,
}

/// 解決結果
class ResolutionResult {
  final bool success;
  final TestVersionedRecord? resolvedRecord;
  final String? errorMessage;
  final ConflictResolutionStrategy strategyUsed;
  
  ResolutionResult({
    required this.success,
    this.resolvedRecord,
    this.errorMessage,
    required this.strategyUsed,
  });
}

/// 樂觀鎖定管理器
class TestOptimisticLockManager {
  final Map<String, TestVersionedRecord> _records = {};
  final Map<String, DateTime> _locks = {};
  final Duration lockTimeout;
  
  TestOptimisticLockManager({
    this.lockTimeout = const Duration(seconds: 30),
  });
  
  /// 獲取記錄
  TestVersionedRecord? getRecord(String id) => _records[id];
  
  /// 添加記錄
  void addRecord(TestVersionedRecord record) {
    _records[record.id] = record;
  }
  
  /// 嘗試更新（樂觀鎖定）
  (bool, TestConflict?) tryUpdate(
    String id,
    int expectedVersion,
    Map<String, dynamic> newData,
  ) {
    final current = _records[id];
    if (current == null) {
      return (false, TestConflict(
        recordId: id,
        type: ConflictType.dataIntegrity,
      ));
    }
    
    if (current.version != expectedVersion) {
      return (false, TestConflict(
        recordId: id,
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: id,
          version: expectedVersion,
          data: newData,
        ),
        remoteVersion: current,
      ));
    }
    
    _records[id] = current.copyWithVersion(current.version + 1, newData);
    return (true, null);
  }
  
  /// 強制更新
  void forceUpdate(String id, TestVersionedRecord record) {
    _records[id] = record;
  }
  
  /// 獲取鎖定
  bool acquireLock(String id) {
    final now = DateTime.now();
    
    // 檢查現有鎖定是否過期
    if (_locks.containsKey(id)) {
      final lockTime = _locks[id]!;
      if (now.difference(lockTime) < lockTimeout) {
        return false; // 鎖定中
      }
    }
    
    _locks[id] = now;
    return true;
  }
  
  /// 釋放鎖定
  void releaseLock(String id) {
    _locks.remove(id);
  }
  
  /// 檢查鎖定狀態
  bool isLocked(String id) {
    if (!_locks.containsKey(id)) return false;
    
    final lockTime = _locks[id]!;
    return DateTime.now().difference(lockTime) < lockTimeout;
  }
}

/// 衝突解決服務
class TestConflictResolutionService {
  final TestOptimisticLockManager lockManager;
  final ConflictResolutionStrategy defaultStrategy;
  
  final List<TestConflict> _conflictHistory = [];
  int _resolvedCount = 0;
  int _failedCount = 0;
  
  TestConflictResolutionService({
    required this.lockManager,
    this.defaultStrategy = ConflictResolutionStrategy.latestWins,
  });
  
  List<TestConflict> get conflictHistory => List.unmodifiable(_conflictHistory);
  int get resolvedCount => _resolvedCount;
  int get failedCount => _failedCount;
  
  /// 解決衝突
  ResolutionResult resolveConflict(
    TestConflict conflict, {
    ConflictResolutionStrategy? strategy,
  }) {
    _conflictHistory.add(conflict);
    final usedStrategy = strategy ?? defaultStrategy;
    
    try {
      TestVersionedRecord? resolved;
      
      switch (usedStrategy) {
        case ConflictResolutionStrategy.localWins:
          resolved = conflict.localVersion;
          break;
          
        case ConflictResolutionStrategy.remoteWins:
          resolved = conflict.remoteVersion;
          break;
          
        case ConflictResolutionStrategy.latestWins:
          if (conflict.localVersion != null && conflict.remoteVersion != null) {
            resolved = conflict.localVersion!.timestamp.isAfter(conflict.remoteVersion!.timestamp)
                ? conflict.localVersion
                : conflict.remoteVersion;
          } else {
            resolved = conflict.localVersion ?? conflict.remoteVersion;
          }
          break;
          
        case ConflictResolutionStrategy.merge:
          if (conflict.localVersion != null && conflict.remoteVersion != null) {
            resolved = conflict.localVersion!.merge(conflict.remoteVersion!);
          } else {
            resolved = conflict.localVersion ?? conflict.remoteVersion;
          }
          break;
          
        case ConflictResolutionStrategy.manual:
          _failedCount++;
          return ResolutionResult(
            success: false,
            errorMessage: '需要手動解決',
            strategyUsed: usedStrategy,
          );
      }
      
      if (resolved != null) {
        lockManager.forceUpdate(conflict.recordId, resolved);
        _resolvedCount++;
        return ResolutionResult(
          success: true,
          resolvedRecord: resolved,
          strategyUsed: usedStrategy,
        );
      }
      
      _failedCount++;
      return ResolutionResult(
        success: false,
        errorMessage: '無法解決衝突',
        strategyUsed: usedStrategy,
      );
    } catch (e) {
      _failedCount++;
      return ResolutionResult(
        success: false,
        errorMessage: e.toString(),
        strategyUsed: usedStrategy,
      );
    }
  }
  
  /// 批次解決衝突
  List<ResolutionResult> batchResolve(
    List<TestConflict> conflicts, {
    ConflictResolutionStrategy? strategy,
  }) {
    return conflicts.map((c) => resolveConflict(c, strategy: strategy)).toList();
  }
}

/// 並發模擬器
class TestConcurrentSimulator {
  final TestOptimisticLockManager lockManager;
  final math.Random _random = math.Random();
  
  TestConcurrentSimulator(this.lockManager);
  
  /// 模擬並發更新
  Future<List<(bool, TestConflict?)>> simulateConcurrentUpdates({
    required String recordId,
    required int numberOfClients,
    Duration maxDelay = const Duration(milliseconds: 100),
  }) async {
    final results = <(bool, TestConflict?)>[];
    final futures = <Future<void>>[];
    
    final currentRecord = lockManager.getRecord(recordId);
    if (currentRecord == null) return [];
    
    for (var i = 0; i < numberOfClients; i++) {
      futures.add(Future.delayed(
        Duration(milliseconds: _random.nextInt(maxDelay.inMilliseconds)),
        () {
          final result = lockManager.tryUpdate(
            recordId,
            currentRecord.version, // 所有客戶端使用相同的預期版本
            {'updatedBy': 'client_$i', 'value': _random.nextInt(100)},
          );
          results.add(result);
        },
      ));
    }
    
    await Future.wait(futures);
    return results;
  }
  
  /// 模擬順序更新
  Future<List<(bool, TestConflict?)>> simulateSequentialUpdates({
    required String recordId,
    required int numberOfUpdates,
  }) async {
    final results = <(bool, TestConflict?)>[];
    
    for (var i = 0; i < numberOfUpdates; i++) {
      final currentRecord = lockManager.getRecord(recordId);
      if (currentRecord == null) break;
      
      final result = lockManager.tryUpdate(
        recordId,
        currentRecord.version,
        {'updatedBy': 'client', 'updateNumber': i},
      );
      results.add(result);
    }
    
    return results;
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  // =========================================================================
  // 版本控制測試
  // =========================================================================
  
  group('版本控制測試', () {
    test('記錄版本初始化', () {
      final record = TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'name': 'Test'},
      );
      
      expect(record.id, 'R001');
      expect(record.version, 1);
      expect(record.data['name'], 'Test');
    });
    
    test('版本更新', () {
      final record = TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'name': 'Test'},
      );
      
      final updated = record.copyWithVersion(2, {'name': 'Updated'});
      
      expect(updated.version, 2);
      expect(updated.data['name'], 'Updated');
      expect(record.version, 1); // 原記錄不變
    });
    
    test('記錄合併', () {
      final record1 = TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'field1': 'value1', 'field2': 'old'},
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
      );
      
      final record2 = TestVersionedRecord(
        id: 'R001',
        version: 2,
        data: {'field2': 'new', 'field3': 'value3'},
      );
      
      final merged = record1.merge(record2);
      
      expect(merged.version, 3);
      expect(merged.data['field1'], 'value1');
      expect(merged.data['field2'], 'new'); // 較新的值
      expect(merged.data['field3'], 'value3');
    });
  });
  
  // =========================================================================
  // 樂觀鎖定測試
  // =========================================================================
  
  group('樂觀鎖定測試', () {
    late TestOptimisticLockManager manager;
    
    setUp(() {
      manager = TestOptimisticLockManager();
      manager.addRecord(TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'value': 100},
      ));
    });
    
    test('成功更新', () {
      final (success, conflict) = manager.tryUpdate(
        'R001',
        1,
        {'value': 200},
      );
      
      expect(success, true);
      expect(conflict, isNull);
      
      final updated = manager.getRecord('R001')!;
      expect(updated.version, 2);
      expect(updated.data['value'], 200);
    });
    
    test('版本不匹配失敗', () {
      // 先更新一次
      manager.tryUpdate('R001', 1, {'value': 200});
      
      // 使用舊版本嘗試更新
      final (success, conflict) = manager.tryUpdate(
        'R001',
        1, // 舊版本
        {'value': 300},
      );
      
      expect(success, false);
      expect(conflict, isNotNull);
      expect(conflict!.type, ConflictType.versionMismatch);
    });
    
    test('記錄不存在失敗', () {
      final (success, conflict) = manager.tryUpdate(
        'NONEXISTENT',
        1,
        {'value': 100},
      );
      
      expect(success, false);
      expect(conflict, isNotNull);
      expect(conflict!.type, ConflictType.dataIntegrity);
    });
    
    test('連續更新成功', () {
      for (var i = 0; i < 10; i++) {
        final current = manager.getRecord('R001')!;
        final (success, _) = manager.tryUpdate(
          'R001',
          current.version,
          {'value': i * 100},
        );
        expect(success, true);
      }
      
      final final_ = manager.getRecord('R001')!;
      expect(final_.version, 11);
      expect(final_.data['value'], 900);
    });
  });
  
  // =========================================================================
  // 鎖定機制測試
  // =========================================================================
  
  group('鎖定機制測試', () {
    late TestOptimisticLockManager manager;
    
    setUp(() {
      manager = TestOptimisticLockManager(
        lockTimeout: const Duration(milliseconds: 100),
      );
    });
    
    test('獲取鎖定', () {
      final result = manager.acquireLock('R001');
      expect(result, true);
      expect(manager.isLocked('R001'), true);
    });
    
    test('重複獲取鎖定失敗', () {
      manager.acquireLock('R001');
      final result = manager.acquireLock('R001');
      expect(result, false);
    });
    
    test('釋放鎖定後可重新獲取', () {
      manager.acquireLock('R001');
      manager.releaseLock('R001');
      
      expect(manager.isLocked('R001'), false);
      
      final result = manager.acquireLock('R001');
      expect(result, true);
    });
    
    test('鎖定超時後自動釋放', () async {
      manager.acquireLock('R001');
      
      // 等待超過超時時間
      await Future.delayed(const Duration(milliseconds: 150));
      
      expect(manager.isLocked('R001'), false);
      
      final result = manager.acquireLock('R001');
      expect(result, true);
    });
    
    test('多個記錄獨立鎖定', () {
      manager.acquireLock('R001');
      manager.acquireLock('R002');
      manager.acquireLock('R003');
      
      expect(manager.isLocked('R001'), true);
      expect(manager.isLocked('R002'), true);
      expect(manager.isLocked('R003'), true);
      
      manager.releaseLock('R002');
      
      expect(manager.isLocked('R001'), true);
      expect(manager.isLocked('R002'), false);
      expect(manager.isLocked('R003'), true);
    });
  });
  
  // =========================================================================
  // 衝突解決策略測試
  // =========================================================================
  
  group('衝突解決策略測試', () {
    late TestOptimisticLockManager lockManager;
    late TestConflictResolutionService service;
    
    setUp(() {
      lockManager = TestOptimisticLockManager();
      lockManager.addRecord(TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'value': 100},
      ));
      service = TestConflictResolutionService(lockManager: lockManager);
    });
    
    test('本地優先策略', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: {'value': 200, 'source': 'local'},
        ),
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 3,
          data: {'value': 300, 'source': 'remote'},
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.localWins,
      );
      
      expect(result.success, true);
      expect(result.resolvedRecord!.data['source'], 'local');
      expect(result.strategyUsed, ConflictResolutionStrategy.localWins);
    });
    
    test('遠端優先策略', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: {'value': 200, 'source': 'local'},
        ),
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 3,
          data: {'value': 300, 'source': 'remote'},
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.remoteWins,
      );
      
      expect(result.success, true);
      expect(result.resolvedRecord!.data['source'], 'remote');
    });
    
    test('最新時間戳策略', () {
      final oldTime = DateTime.now().subtract(const Duration(hours: 1));
      final newTime = DateTime.now();
      
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: {'value': 200},
          timestamp: newTime,
        ),
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 3,
          data: {'value': 300},
          timestamp: oldTime,
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.latestWins,
      );
      
      expect(result.success, true);
      expect(result.resolvedRecord!.data['value'], 200); // 本地較新
    });
    
    test('合併策略', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: {'field1': 'local', 'field2': 'local'},
          timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        ),
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 3,
          data: {'field2': 'remote', 'field3': 'remote'},
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.merge,
      );
      
      expect(result.success, true);
      final resolved = result.resolvedRecord!;
      expect(resolved.data['field1'], 'local');
      expect(resolved.data['field2'], 'remote'); // 較新的 remote 值
      expect(resolved.data['field3'], 'remote');
    });
    
    test('手動解決策略返回失敗', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.manual,
      );
      
      expect(result.success, false);
      expect(result.errorMessage, contains('手動'));
    });
  });
  
  // =========================================================================
  // 並發更新測試
  // =========================================================================
  
  group('並發更新測試', () {
    late TestOptimisticLockManager lockManager;
    late TestConcurrentSimulator simulator;
    
    setUp(() {
      lockManager = TestOptimisticLockManager();
      lockManager.addRecord(TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'value': 0},
      ));
      simulator = TestConcurrentSimulator(lockManager);
    });
    
    test('並發更新只有一個成功', () async {
      final results = await simulator.simulateConcurrentUpdates(
        recordId: 'R001',
        numberOfClients: 10,
      );
      
      final successCount = results.where((r) => r.$1).length;
      final conflictCount = results.where((r) => !r.$1).length;
      
      // 只有第一個請求成功，其餘都應該失敗
      expect(successCount, 1);
      expect(conflictCount, 9);
    });
    
    test('順序更新全部成功', () async {
      final results = await simulator.simulateSequentialUpdates(
        recordId: 'R001',
        numberOfUpdates: 10,
      );
      
      final successCount = results.where((r) => r.$1).length;
      expect(successCount, 10);
      
      final finalRecord = lockManager.getRecord('R001')!;
      expect(finalRecord.version, 11);
    });
    
    test('多輪並發更新', () async {
      for (var round = 0; round < 5; round++) {
        final results = await simulator.simulateConcurrentUpdates(
          recordId: 'R001',
          numberOfClients: 5,
        );
        
        // 每輪只有一個成功
        final successCount = results.where((r) => r.$1).length;
        expect(successCount, 1);
      }
      
      // 總共 5 次成功更新
      final finalRecord = lockManager.getRecord('R001')!;
      expect(finalRecord.version, 6);
    });
  });
  
  // =========================================================================
  // 批次衝突解決測試
  // =========================================================================
  
  group('批次衝突解決測試', () {
    late TestOptimisticLockManager lockManager;
    late TestConflictResolutionService service;
    
    setUp(() {
      lockManager = TestOptimisticLockManager();
      for (var i = 1; i <= 5; i++) {
        lockManager.addRecord(TestVersionedRecord(
          id: 'R00$i',
          version: 1,
          data: {'value': i * 100},
        ));
      }
      service = TestConflictResolutionService(lockManager: lockManager);
    });
    
    test('批次解決多個衝突', () {
      final conflicts = [
        for (var i = 1; i <= 5; i++)
          TestConflict(
            recordId: 'R00$i',
            type: ConflictType.versionMismatch,
            localVersion: TestVersionedRecord(
              id: 'R00$i',
              version: 2,
              data: {'value': i * 1000},
            ),
            remoteVersion: TestVersionedRecord(
              id: 'R00$i',
              version: 3,
              data: {'value': i * 10000},
            ),
          ),
      ];
      
      final results = service.batchResolve(
        conflicts,
        strategy: ConflictResolutionStrategy.localWins,
      );
      
      expect(results.length, 5);
      expect(results.every((r) => r.success), true);
      expect(service.resolvedCount, 5);
    });
    
    test('批次解決混合結果', () {
      final conflicts = [
        TestConflict(
          recordId: 'R001',
          type: ConflictType.versionMismatch,
          localVersion: TestVersionedRecord(
            id: 'R001',
            version: 2,
            data: {'value': 1000},
          ),
        ),
        TestConflict(
          recordId: 'R002',
          type: ConflictType.versionMismatch,
        ), // 無法解決
      ];
      
      final results = service.batchResolve(
        conflicts,
        strategy: ConflictResolutionStrategy.localWins,
      );
      
      expect(results[0].success, true);
      expect(results[1].success, false);
    });
  });
  
  // =========================================================================
  // 統計與歷史記錄測試
  // =========================================================================
  
  group('統計與歷史記錄測試', () {
    late TestOptimisticLockManager lockManager;
    late TestConflictResolutionService service;
    
    setUp(() {
      lockManager = TestOptimisticLockManager();
      lockManager.addRecord(TestVersionedRecord(
        id: 'R001',
        version: 1,
        data: {'value': 100},
      ));
      service = TestConflictResolutionService(lockManager: lockManager);
    });
    
    test('解決計數正確', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: {'value': 200},
        ),
      );
      
      for (var i = 0; i < 5; i++) {
        service.resolveConflict(conflict, strategy: ConflictResolutionStrategy.localWins);
      }
      
      expect(service.resolvedCount, 5);
      expect(service.failedCount, 0);
    });
    
    test('失敗計數正確', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
      );
      
      for (var i = 0; i < 3; i++) {
        service.resolveConflict(conflict, strategy: ConflictResolutionStrategy.manual);
      }
      
      expect(service.resolvedCount, 0);
      expect(service.failedCount, 3);
    });
    
    test('衝突歷史記錄', () {
      for (var i = 0; i < 5; i++) {
        final conflict = TestConflict(
          recordId: 'R00$i',
          type: ConflictType.versionMismatch,
          localVersion: TestVersionedRecord(
            id: 'R00$i',
            version: i,
            data: {'value': i * 100},
          ),
        );
        service.resolveConflict(conflict);
      }
      
      expect(service.conflictHistory.length, 5);
      expect(service.conflictHistory.first.recordId, 'R000');
      expect(service.conflictHistory.last.recordId, 'R004');
    });
  });
  
  // =========================================================================
  // 邊界條件測試
  // =========================================================================
  
  group('邊界條件測試', () {
    late TestOptimisticLockManager lockManager;
    late TestConflictResolutionService service;
    
    setUp(() {
      lockManager = TestOptimisticLockManager();
      service = TestConflictResolutionService(lockManager: lockManager);
    });
    
    test('空數據記錄', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 1,
          data: {},
        ),
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: {},
        ),
      );
      
      final result = service.resolveConflict(conflict);
      expect(result.success, true);
      expect(result.resolvedRecord!.data, isEmpty);
    });
    
    test('只有本地版本', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 1,
          data: {'value': 100},
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.latestWins,
      );
      
      expect(result.success, true);
      expect(result.resolvedRecord!.data['value'], 100);
    });
    
    test('只有遠端版本', () {
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 1,
          data: {'value': 200},
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.latestWins,
      );
      
      expect(result.success, true);
      expect(result.resolvedRecord!.data['value'], 200);
    });
    
    test('大量欄位合併', () {
      final localData = <String, dynamic>{};
      final remoteData = <String, dynamic>{};
      
      for (var i = 0; i < 100; i++) {
        localData['local_field_$i'] = 'local_$i';
        remoteData['remote_field_$i'] = 'remote_$i';
      }
      
      final conflict = TestConflict(
        recordId: 'R001',
        type: ConflictType.versionMismatch,
        localVersion: TestVersionedRecord(
          id: 'R001',
          version: 1,
          data: localData,
        ),
        remoteVersion: TestVersionedRecord(
          id: 'R001',
          version: 2,
          data: remoteData,
        ),
      );
      
      final result = service.resolveConflict(
        conflict,
        strategy: ConflictResolutionStrategy.merge,
      );
      
      expect(result.success, true);
      expect(result.resolvedRecord!.data.length, 200);
    });
  });
}
