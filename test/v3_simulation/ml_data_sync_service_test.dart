// ============================================================================
// V3 ML 數據同步服務完整測試套件
// ============================================================================
// 測試覆蓋:
// - 同步條件判斷
// - 批次上傳處理
// - 網絡狀態感知
// - 錯誤重試機制
// - 同步結果追蹤
// ============================================================================

// dart:convert import removed - unused
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用網絡狀態模擬
// ============================================================================

enum TestConnectivityResult {
  wifi,
  mobile,
  ethernet,
  none,
}

class TestConnectivityChecker {
  TestConnectivityResult _currentStatus = TestConnectivityResult.wifi;

  void setStatus(TestConnectivityResult status) {
    _currentStatus = status;
  }

  TestConnectivityResult checkConnectivity() => _currentStatus;

  bool get isConnected => _currentStatus != TestConnectivityResult.none;
  
  bool get isWifi => _currentStatus == TestConnectivityResult.wifi;
  
  bool get isMobile => _currentStatus == TestConnectivityResult.mobile;
}

// ============================================================================
// 測試用同步結果
// ============================================================================

class TestSyncResult {
  final bool success;
  final String message;
  final int recordsSynced;
  final int recordsFailed;
  final List<String>? failedIds;
  final DateTime? syncedAt;

  TestSyncResult({
    required this.success,
    required this.message,
    this.recordsSynced = 0,
    this.recordsFailed = 0,
    this.failedIds,
    this.syncedAt,
  });

  @override
  String toString() => 'SyncResult(success: $success, synced: $recordsSynced, failed: $recordsFailed)';
}

// ============================================================================
// 測試用同步記錄
// ============================================================================

class TestSyncRecord {
  final String id;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  bool isSynced;
  int retryCount;

  TestSyncRecord({
    required this.id,
    required this.data,
    DateTime? createdAt,
    this.isSynced = false,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'data': data,
    'created_at': createdAt.toIso8601String(),
    'is_synced': isSynced,
    'retry_count': retryCount,
  };

  factory TestSyncRecord.fromJson(Map<String, dynamic> json) {
    return TestSyncRecord(
      id: json['id'],
      data: Map<String, dynamic>.from(json['data']),
      createdAt: DateTime.parse(json['created_at']),
      isSynced: json['is_synced'] ?? false,
      retryCount: json['retry_count'] ?? 0,
    );
  }
}

// ============================================================================
// 測試用批次管理器
// ============================================================================

class TestBatchManager {
  static const int defaultBatchSize = 100;
  
  /// 將記錄分成批次
  static List<List<T>> splitIntoBatches<T>(List<T> items, {int batchSize = defaultBatchSize}) {
    final batches = <List<T>>[];
    for (var i = 0; i < items.length; i += batchSize) {
      final end = math.min(i + batchSize, items.length);
      batches.add(items.sublist(i, end));
    }
    return batches;
  }

  /// 計算需要的批次數
  static int calculateBatchCount(int totalItems, {int batchSize = defaultBatchSize}) {
    return (totalItems / batchSize).ceil();
  }

  /// 預估同步時間（毫秒）
  static int estimateSyncTime(int totalItems, {int msPerItem = 10}) {
    return totalItems * msPerItem;
  }
}

// ============================================================================
// 測試用重試策略
// ============================================================================

class TestRetryPolicy {
  static const int maxRetries = 3;
  static const int baseDelayMs = 1000;

  /// 計算下次重試延遲（指數退避）
  static int calculateDelay(int retryCount) {
    if (retryCount >= maxRetries) return -1; // 不再重試
    return baseDelayMs * math.pow(2, retryCount).toInt();
  }

  /// 是否應該重試
  static bool shouldRetry(int retryCount, {int? httpStatusCode}) {
    if (retryCount >= maxRetries) return false;
    
    // 4xx 錯誤通常不應重試（除了 429 Too Many Requests）
    if (httpStatusCode != null) {
      if (httpStatusCode >= 400 && httpStatusCode < 500 && httpStatusCode != 429) {
        return false;
      }
    }
    
    return true;
  }

  /// 取得重試資訊
  static Map<String, dynamic> getRetryInfo(int retryCount) {
    return {
      'current_retry': retryCount,
      'max_retries': maxRetries,
      'should_retry': retryCount < maxRetries,
      'next_delay_ms': calculateDelay(retryCount),
    };
  }
}

// ============================================================================
// 測試用同步狀態追蹤器
// ============================================================================

class TestSyncStateTracker {
  DateTime? _lastSyncTime;
  int _totalSynced = 0;
  int _totalFailed = 0;
  final List<TestSyncResult> _syncHistory = [];
  final Map<String, int> _failedRecords = {}; // ID -> retry count

  /// 記錄同步結果
  void recordSync(TestSyncResult result) {
    _syncHistory.add(result);
    _totalSynced += result.recordsSynced;
    _totalFailed += result.recordsFailed;
    
    if (result.success) {
      _lastSyncTime = result.syncedAt ?? DateTime.now();
    }
    
    // 追蹤失敗的記錄
    if (result.failedIds != null) {
      for (final id in result.failedIds!) {
        _failedRecords[id] = (_failedRecords[id] ?? 0) + 1;
      }
    }
  }

  /// 取得上次同步時間
  DateTime? get lastSyncTime => _lastSyncTime;

  /// 取得總同步數
  int get totalSynced => _totalSynced;

  /// 取得總失敗數
  int get totalFailed => _totalFailed;

  /// 取得同步歷史
  List<TestSyncResult> get history => List.from(_syncHistory);

  /// 取得需要重試的記錄
  List<String> getRecordsToRetry() {
    return _failedRecords.entries
        .where((e) => e.value < TestRetryPolicy.maxRetries)
        .map((e) => e.key)
        .toList();
  }

  /// 取得已放棄的記錄
  List<String> getAbandonedRecords() {
    return _failedRecords.entries
        .where((e) => e.value >= TestRetryPolicy.maxRetries)
        .map((e) => e.key)
        .toList();
  }

  /// 清除失敗記錄
  void clearFailedRecord(String id) {
    _failedRecords.remove(id);
  }

  /// 統計資訊
  Map<String, dynamic> getStats() => {
    'total_synced': _totalSynced,
    'total_failed': _totalFailed,
    'success_rate': _totalSynced + _totalFailed > 0 
        ? _totalSynced / (_totalSynced + _totalFailed) * 100 
        : 0.0,
    'last_sync': _lastSyncTime?.toIso8601String(),
    'sync_count': _syncHistory.length,
    'pending_retries': getRecordsToRetry().length,
    'abandoned': getAbandonedRecords().length,
  };
}

// ============================================================================
// 測試用同步條件檢查器
// ============================================================================

class TestSyncConditionChecker {
  final TestConnectivityChecker connectivity;
  final int minIntervalMs;
  final int minRecordsForMobile;

  TestSyncConditionChecker({
    required this.connectivity,
    this.minIntervalMs = 30 * 60 * 1000, // 30 分鐘
    this.minRecordsForMobile = 100,
  });

  /// 檢查是否應該同步
  bool shouldSync({
    required DateTime? lastSyncTime,
    required int pendingRecords,
    bool force = false,
  }) {
    if (force) return true;
    if (pendingRecords == 0) return false;
    
    // 檢查網絡
    if (!connectivity.isConnected) return false;
    
    // 如果是行動網絡，需要更多記錄才同步
    if (connectivity.isMobile && pendingRecords < minRecordsForMobile) {
      return false;
    }
    
    // 檢查時間間隔
    if (lastSyncTime != null) {
      final elapsed = DateTime.now().difference(lastSyncTime).inMilliseconds;
      if (elapsed < minIntervalMs && pendingRecords < 500) {
        return false;
      }
    }
    
    return true;
  }

  /// 取得同步建議
  String getSyncRecommendation({
    required DateTime? lastSyncTime,
    required int pendingRecords,
  }) {
    if (!connectivity.isConnected) {
      return '無網絡連接';
    }
    if (pendingRecords == 0) {
      return '無待同步記錄';
    }
    if (connectivity.isMobile && pendingRecords < minRecordsForMobile) {
      return '行動網絡下，待記錄數 ($pendingRecords) 未達閾值 ($minRecordsForMobile)';
    }
    return '可以同步';
  }
}

// ============================================================================
// 測試用 API 模擬器
// ============================================================================

class TestAPIMock {
  bool _shouldFail = false;
  int _failureCount = 0;
  int _failAfterCount = -1;
  int _callCount = 0;
  final List<Map<String, dynamic>> _receivedData = [];

  void setFailure(bool shouldFail) {
    _shouldFail = shouldFail;
  }

  void failAfter(int count) {
    _failAfterCount = count;
    _callCount = 0;
  }

  void reset() {
    _shouldFail = false;
    _failureCount = 0;
    _failAfterCount = -1;
    _callCount = 0;
    _receivedData.clear();
  }

  /// 模擬 API 上傳
  Future<TestSyncResult> uploadBatch(List<Map<String, dynamic>> batch) async {
    _callCount++;
    
    // 模擬網絡延遲
    await Future.delayed(const Duration(milliseconds: 10));
    
    // 檢查是否應該失敗
    if (_shouldFail || (_failAfterCount >= 0 && _callCount > _failAfterCount)) {
      _failureCount++;
      return TestSyncResult(
        success: false,
        message: '模擬失敗',
        recordsFailed: batch.length,
        failedIds: batch.map((b) => b['id'] as String).toList(),
      );
    }
    
    _receivedData.addAll(batch);
    
    return TestSyncResult(
      success: true,
      message: '上傳成功',
      recordsSynced: batch.length,
      syncedAt: DateTime.now(),
    );
  }

  int get callCount => _callCount;
  int get failureCount => _failureCount;
  List<Map<String, dynamic>> get receivedData => List.from(_receivedData);
}

// ============================================================================
// 測試用同步服務
// ============================================================================

class TestMLDataSyncService {
  final TestConnectivityChecker connectivity;
  final TestSyncStateTracker stateTracker;
  final TestAPIMock api;
  final TestSyncConditionChecker conditionChecker;
  
  bool _isSyncing = false;
  final List<TestSyncRecord> _pendingRecords = [];

  TestMLDataSyncService({
    required this.connectivity,
    required this.stateTracker,
    required this.api,
    required this.conditionChecker,
  });

  /// 加入待同步記錄
  void addRecord(TestSyncRecord record) {
    _pendingRecords.add(record);
  }

  /// 取得待同步記錄數
  int get pendingCount => _pendingRecords.where((r) => !r.isSynced).length;

  /// 是否正在同步
  bool get isSyncing => _isSyncing;

  /// 執行同步
  Future<TestSyncResult> sync({bool force = false}) async {
    if (_isSyncing) {
      return TestSyncResult(success: false, message: '同步進行中');
    }

    if (!conditionChecker.shouldSync(
      lastSyncTime: stateTracker.lastSyncTime,
      pendingRecords: pendingCount,
      force: force,
    )) {
      return TestSyncResult(
        success: true,
        message: conditionChecker.getSyncRecommendation(
          lastSyncTime: stateTracker.lastSyncTime,
          pendingRecords: pendingCount,
        ),
      );
    }

    _isSyncing = true;

    try {
      final toSync = _pendingRecords.where((r) => !r.isSynced).toList();
      final batches = TestBatchManager.splitIntoBatches(toSync, batchSize: 50);
      
      int totalSynced = 0;
      int totalFailed = 0;
      final failedIds = <String>[];

      for (final batch in batches) {
        final batchData = batch.map((r) => r.toJson()).toList();
        final result = await api.uploadBatch(batchData);
        
        if (result.success) {
          totalSynced += result.recordsSynced;
          for (final record in batch) {
            record.isSynced = true;
          }
        } else {
          totalFailed += result.recordsFailed;
          failedIds.addAll(result.failedIds ?? []);
          for (final record in batch) {
            record.retryCount++;
          }
        }
      }

      final finalResult = TestSyncResult(
        success: totalFailed == 0,
        message: totalFailed == 0 ? '同步完成' : '部分失敗',
        recordsSynced: totalSynced,
        recordsFailed: totalFailed,
        failedIds: failedIds.isEmpty ? null : failedIds,
        syncedAt: DateTime.now(),
      );

      stateTracker.recordSync(finalResult);
      return finalResult;
    } finally {
      _isSyncing = false;
    }
  }

  /// 清除已同步記錄
  void clearSyncedRecords() {
    _pendingRecords.removeWhere((r) => r.isSynced);
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  group('網絡狀態檢查器測試', () {
    late TestConnectivityChecker checker;

    setUp(() {
      checker = TestConnectivityChecker();
    });

    test('預設應為 WiFi 連接', () {
      expect(checker.isConnected, true);
      expect(checker.isWifi, true);
      expect(checker.isMobile, false);
    });

    test('應正確更新狀態', () {
      checker.setStatus(TestConnectivityResult.mobile);
      expect(checker.isMobile, true);
      expect(checker.isWifi, false);

      checker.setStatus(TestConnectivityResult.none);
      expect(checker.isConnected, false);
    });
  });

  group('批次管理器測試', () {
    test('應正確分割批次', () {
      final items = List.generate(250, (i) => i);
      final batches = TestBatchManager.splitIntoBatches(items, batchSize: 100);

      expect(batches.length, 3);
      expect(batches[0].length, 100);
      expect(batches[1].length, 100);
      expect(batches[2].length, 50);
    });

    test('應處理空列表', () {
      final batches = TestBatchManager.splitIntoBatches<int>([], batchSize: 100);
      expect(batches, isEmpty);
    });

    test('應處理小於批次大小的列表', () {
      final items = List.generate(30, (i) => i);
      final batches = TestBatchManager.splitIntoBatches(items, batchSize: 100);

      expect(batches.length, 1);
      expect(batches[0].length, 30);
    });

    test('應正確計算批次數', () {
      expect(TestBatchManager.calculateBatchCount(250, batchSize: 100), 3);
      expect(TestBatchManager.calculateBatchCount(100, batchSize: 100), 1);
      expect(TestBatchManager.calculateBatchCount(0, batchSize: 100), 0);
    });

    test('應預估同步時間', () {
      expect(TestBatchManager.estimateSyncTime(100, msPerItem: 10), 1000);
      expect(TestBatchManager.estimateSyncTime(500, msPerItem: 5), 2500);
    });
  });

  group('重試策略測試', () {
    test('應計算指數退避延遲', () {
      expect(TestRetryPolicy.calculateDelay(0), 1000);
      expect(TestRetryPolicy.calculateDelay(1), 2000);
      expect(TestRetryPolicy.calculateDelay(2), 4000);
      expect(TestRetryPolicy.calculateDelay(3), -1); // 超過最大重試次數
    });

    test('應正確判斷是否重試', () {
      expect(TestRetryPolicy.shouldRetry(0), true);
      expect(TestRetryPolicy.shouldRetry(2), true);
      expect(TestRetryPolicy.shouldRetry(3), false);
    });

    test('應根據 HTTP 狀態碼判斷重試', () {
      // 5xx 錯誤應重試
      expect(TestRetryPolicy.shouldRetry(0, httpStatusCode: 500), true);
      expect(TestRetryPolicy.shouldRetry(0, httpStatusCode: 503), true);
      
      // 4xx 錯誤不應重試（除了 429）
      expect(TestRetryPolicy.shouldRetry(0, httpStatusCode: 400), false);
      expect(TestRetryPolicy.shouldRetry(0, httpStatusCode: 404), false);
      expect(TestRetryPolicy.shouldRetry(0, httpStatusCode: 429), true);
    });

    test('應提供正確的重試資訊', () {
      final info = TestRetryPolicy.getRetryInfo(1);
      
      expect(info['current_retry'], 1);
      expect(info['max_retries'], 3);
      expect(info['should_retry'], true);
      expect(info['next_delay_ms'], 2000);
    });
  });

  group('同步狀態追蹤器測試', () {
    late TestSyncStateTracker tracker;

    setUp(() {
      tracker = TestSyncStateTracker();
    });

    test('應記錄成功同步', () {
      tracker.recordSync(TestSyncResult(
        success: true,
        message: '成功',
        recordsSynced: 50,
        syncedAt: DateTime.now(),
      ));

      expect(tracker.totalSynced, 50);
      expect(tracker.totalFailed, 0);
      expect(tracker.lastSyncTime, isNotNull);
    });

    test('應記錄失敗同步', () {
      tracker.recordSync(TestSyncResult(
        success: false,
        message: '失敗',
        recordsFailed: 10,
        failedIds: ['id1', 'id2', 'id3'],
      ));

      expect(tracker.totalFailed, 10);
      expect(tracker.getRecordsToRetry(), contains('id1'));
    });

    test('應追蹤重試次數並放棄超過上限的記錄', () {
      // 模擬多次失敗
      for (var i = 0; i < TestRetryPolicy.maxRetries + 1; i++) {
        tracker.recordSync(TestSyncResult(
          success: false,
          message: '失敗',
          recordsFailed: 1,
          failedIds: ['stubborn_record'],
        ));
      }

      expect(tracker.getRecordsToRetry(), isNot(contains('stubborn_record')));
      expect(tracker.getAbandonedRecords(), contains('stubborn_record'));
    });

    test('應提供正確的統計資訊', () {
      tracker.recordSync(TestSyncResult(
        success: true,
        message: '成功',
        recordsSynced: 80,
        syncedAt: DateTime.now(),
      ));
      tracker.recordSync(TestSyncResult(
        success: false,
        message: '失敗',
        recordsFailed: 20,
        failedIds: ['f1', 'f2'],
      ));

      final stats = tracker.getStats();
      expect(stats['total_synced'], 80);
      expect(stats['total_failed'], 20);
      expect(stats['success_rate'], 80.0);
      expect(stats['sync_count'], 2);
    });
  });

  group('同步條件檢查器測試', () {
    late TestConnectivityChecker connectivity;
    late TestSyncConditionChecker checker;

    setUp(() {
      connectivity = TestConnectivityChecker();
      checker = TestSyncConditionChecker(
        connectivity: connectivity,
        minIntervalMs: 1000, // 1秒（測試用）
        minRecordsForMobile: 50,
      );
    });

    test('無網絡時不應同步', () {
      connectivity.setStatus(TestConnectivityResult.none);
      
      expect(checker.shouldSync(
        lastSyncTime: null,
        pendingRecords: 100,
      ), false);
    });

    test('無待同步記錄時不應同步', () {
      expect(checker.shouldSync(
        lastSyncTime: null,
        pendingRecords: 0,
      ), false);
    });

    test('行動網絡下記錄數不足時不應同步', () {
      connectivity.setStatus(TestConnectivityResult.mobile);
      
      expect(checker.shouldSync(
        lastSyncTime: null,
        pendingRecords: 30,
      ), false);
    });

    test('行動網絡下記錄數足夠時應同步', () {
      connectivity.setStatus(TestConnectivityResult.mobile);
      
      expect(checker.shouldSync(
        lastSyncTime: null,
        pendingRecords: 100,
      ), true);
    });

    test('WiFi 下應正常同步', () {
      expect(checker.shouldSync(
        lastSyncTime: null,
        pendingRecords: 10,
      ), true);
    });

    test('強制同步應忽略條件', () {
      connectivity.setStatus(TestConnectivityResult.none);
      
      expect(checker.shouldSync(
        lastSyncTime: null,
        pendingRecords: 0,
        force: true,
      ), true);
    });

    test('應提供正確的同步建議', () {
      connectivity.setStatus(TestConnectivityResult.none);
      expect(checker.getSyncRecommendation(
        lastSyncTime: null,
        pendingRecords: 100,
      ), '無網絡連接');

      connectivity.setStatus(TestConnectivityResult.wifi);
      expect(checker.getSyncRecommendation(
        lastSyncTime: null,
        pendingRecords: 0,
      ), '無待同步記錄');

      expect(checker.getSyncRecommendation(
        lastSyncTime: null,
        pendingRecords: 100,
      ), '可以同步');
    });
  });

  group('API 模擬器測試', () {
    late TestAPIMock api;

    setUp(() {
      api = TestAPIMock();
    });

    test('預設應成功上傳', () async {
      final batch = [
        {'id': '1', 'data': 'test1'},
        {'id': '2', 'data': 'test2'},
      ];

      final result = await api.uploadBatch(batch);

      expect(result.success, true);
      expect(result.recordsSynced, 2);
      expect(api.receivedData.length, 2);
    });

    test('設定失敗時應返回錯誤', () async {
      api.setFailure(true);
      final batch = [{'id': '1', 'data': 'test'}];

      final result = await api.uploadBatch(batch);

      expect(result.success, false);
      expect(result.recordsFailed, 1);
      expect(result.failedIds, contains('1'));
    });

    test('應在指定次數後失敗', () async {
      api.failAfter(2);
      final batch = [{'id': 'test', 'data': 'data'}];

      // 前兩次成功
      expect((await api.uploadBatch(batch)).success, true);
      expect((await api.uploadBatch(batch)).success, true);
      
      // 第三次失敗
      expect((await api.uploadBatch(batch)).success, false);
    });
  });

  group('同步服務整合測試', () {
    late TestConnectivityChecker connectivity;
    late TestSyncStateTracker stateTracker;
    late TestAPIMock api;
    late TestSyncConditionChecker conditionChecker;
    late TestMLDataSyncService syncService;

    setUp(() {
      connectivity = TestConnectivityChecker();
      stateTracker = TestSyncStateTracker();
      api = TestAPIMock();
      conditionChecker = TestSyncConditionChecker(
        connectivity: connectivity,
        minIntervalMs: 0, // 測試用，無最小間隔
        minRecordsForMobile: 10,
      );
      syncService = TestMLDataSyncService(
        connectivity: connectivity,
        stateTracker: stateTracker,
        api: api,
        conditionChecker: conditionChecker,
      );
    });

    test('應成功同步記錄', () async {
      // 加入待同步記錄
      for (var i = 0; i < 5; i++) {
        syncService.addRecord(TestSyncRecord(
          id: 'record_$i',
          data: {'index': i},
        ));
      }

      expect(syncService.pendingCount, 5);

      final result = await syncService.sync();

      expect(result.success, true);
      expect(result.recordsSynced, 5);
      expect(syncService.pendingCount, 0);
      expect(stateTracker.totalSynced, 5);
    });

    test('應處理部分失敗', () async {
      // 加入記錄
      for (var i = 0; i < 100; i++) {
        syncService.addRecord(TestSyncRecord(
          id: 'record_$i',
          data: {'index': i},
        ));
      }

      // 設定第二批次後失敗
      api.failAfter(1);

      final result = await syncService.sync();

      expect(result.success, false);
      expect(result.recordsSynced, 50); // 第一批成功
      expect(result.recordsFailed, 50); // 第二批失敗
    });

    test('無網絡時不應同步', () async {
      connectivity.setStatus(TestConnectivityResult.none);
      
      syncService.addRecord(TestSyncRecord(
        id: 'test',
        data: {},
      ));

      final result = await syncService.sync();

      expect(result.message, contains('無網絡'));
      expect(api.callCount, 0);
    });

    test('無待同步記錄時不應同步', () async {
      final result = await syncService.sync();

      expect(result.message, contains('無待同步'));
      expect(api.callCount, 0);
    });

    test('同步進行中應拒絕新請求', () async {
      // 加入記錄
      for (var i = 0; i < 10; i++) {
        syncService.addRecord(TestSyncRecord(
          id: 'record_$i',
          data: {},
        ));
      }

      // 同時發起兩個同步請求
      final results = await Future.wait([
        syncService.sync(),
        Future.delayed(const Duration(milliseconds: 5), () => syncService.sync()),
      ]);

      // 其中一個應該成功，另一個應該被拒絕
      final successCount = results.where((r) => r.recordsSynced > 0).length;
      final rejectedCount = results.where((r) => r.message.contains('進行中')).length;
      
      expect(successCount + rejectedCount, 2);
    });

    test('應正確清除已同步記錄', () async {
      for (var i = 0; i < 5; i++) {
        syncService.addRecord(TestSyncRecord(
          id: 'record_$i',
          data: {},
        ));
      }

      await syncService.sync();
      expect(syncService.pendingCount, 0);

      syncService.clearSyncedRecords();
      
      // 加入新記錄
      syncService.addRecord(TestSyncRecord(
        id: 'new_record',
        data: {},
      ));
      
      expect(syncService.pendingCount, 1);
    });

    test('強制同步應忽略條件', () async {
      connectivity.setStatus(TestConnectivityResult.none);
      
      syncService.addRecord(TestSyncRecord(
        id: 'test',
        data: {},
      ));

      // 一般同步應失敗
      // ignore: unused_local_variable
      final normalResult = await syncService.sync();
      expect(api.callCount, 0);

      // 強制同步應執行（雖然會因網絡問題失敗）
      connectivity.setStatus(TestConnectivityResult.wifi);
      // ignore: unused_local_variable
      final forceResult = await syncService.sync(force: true);
      expect(api.callCount, greaterThan(0));
    });
  });

  group('SyncRecord 模型測試', () {
    test('應正確序列化', () {
      final record = TestSyncRecord(
        id: 'sr_001',
        data: {'key': 'value', 'number': 42},
        createdAt: DateTime(2024, 6, 1),
        isSynced: true,
        retryCount: 2,
      );

      final json = record.toJson();

      expect(json['id'], 'sr_001');
      expect(json['data']['key'], 'value');
      expect(json['is_synced'], true);
      expect(json['retry_count'], 2);
    });

    test('應正確反序列化', () {
      final json = {
        'id': 'sr_002',
        'data': {'test': true},
        'created_at': '2024-07-15T10:30:00.000',
        'is_synced': false,
        'retry_count': 1,
      };

      final record = TestSyncRecord.fromJson(json);

      expect(record.id, 'sr_002');
      expect(record.data['test'], true);
      expect(record.isSynced, false);
      expect(record.retryCount, 1);
    });
  });

  group('端到端測試', () {
    test('完整同步流程', () async {
      final connectivity = TestConnectivityChecker();
      final stateTracker = TestSyncStateTracker();
      final api = TestAPIMock();
      final conditionChecker = TestSyncConditionChecker(
        connectivity: connectivity,
        minIntervalMs: 0,
      );
      final syncService = TestMLDataSyncService(
        connectivity: connectivity,
        stateTracker: stateTracker,
        api: api,
        conditionChecker: conditionChecker,
      );

      // 1. 收集數據
      for (var i = 0; i < 120; i++) {
        syncService.addRecord(TestSyncRecord(
          id: 'ml_record_$i',
          data: {
            'type': 'carbonCalculation',
            'tree_id': 'tree_${i % 10}',
            'auto_value': 100.0 + i,
            'user_value': 95.0 + i,
          },
        ));
      }

      expect(syncService.pendingCount, 120);

      // 2. 執行同步
      final result = await syncService.sync();

      expect(result.success, true);
      expect(result.recordsSynced, 120);

      // 3. 驗證狀態
      final stats = stateTracker.getStats();
      expect(stats['total_synced'], 120);
      expect(stats['success_rate'], 100.0);
      expect(stats['last_sync'], isNotNull);

      // 4. 驗證 API 接收的數據
      expect(api.receivedData.length, 120);
      expect(api.callCount, 3); // 120 / 50 = 3 batches
    });

    test('網絡中斷恢復測試', () async {
      final connectivity = TestConnectivityChecker();
      final stateTracker = TestSyncStateTracker();
      final api = TestAPIMock();
      final conditionChecker = TestSyncConditionChecker(
        connectivity: connectivity,
        minIntervalMs: 0,
      );
      final syncService = TestMLDataSyncService(
        connectivity: connectivity,
        stateTracker: stateTracker,
        api: api,
        conditionChecker: conditionChecker,
      );

      // 加入記錄
      for (var i = 0; i < 20; i++) {
        syncService.addRecord(TestSyncRecord(
          id: 'record_$i',
          data: {'index': i},
        ));
      }

      // 1. 無網絡 - 同步應被跳過
      connectivity.setStatus(TestConnectivityResult.none);
      var result = await syncService.sync();
      expect(result.message, contains('無網絡'));
      expect(syncService.pendingCount, 20);

      // 2. 恢復網絡 - 同步應成功
      connectivity.setStatus(TestConnectivityResult.wifi);
      result = await syncService.sync();
      expect(result.success, true);
      expect(result.recordsSynced, 20);
      expect(syncService.pendingCount, 0);
    });
  });
}
