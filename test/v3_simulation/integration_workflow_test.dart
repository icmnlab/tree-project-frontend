// ============================================================================
// V3 整合測試套件 - 完整工作流程模擬
// ============================================================================
// 測試覆蓋:
// - 完整調查流程模擬
// - 多設備數據同步
// - 離線/線上切換
// - 資料完整性驗證
// - 效能壓力測試
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用整合系統類別
// ============================================================================

/// 調查狀態
enum SurveyStatus {
  pending,
  inProgress,
  completed,
  synced,
  failed,
}

/// 網路狀態
enum NetworkStatus {
  online,
  offline,
  unstable,
}

/// 樹木調查記錄
class TestSurveyRecord {
  final String localId;
  String? serverId;
  final String projectCode;
  final String speciesName;
  final double lat;
  final double lon;
  final double? dbhCm;
  final double? heightM;
  final DateTime surveyTime;
  SurveyStatus status;
  int retryCount;
  String? errorMessage;
  final Map<String, dynamic> metadata;
  
  TestSurveyRecord({
    required this.localId,
    this.serverId,
    required this.projectCode,
    required this.speciesName,
    required this.lat,
    required this.lon,
    this.dbhCm,
    this.heightM,
    DateTime? surveyTime,
    this.status = SurveyStatus.pending,
    this.retryCount = 0,
    this.errorMessage,
    Map<String, dynamic>? metadata,
  }) : surveyTime = surveyTime ?? DateTime.now(),
       metadata = metadata ?? {};
  
  bool get isSynced => status == SurveyStatus.synced;
  bool get needsRetry => status == SurveyStatus.failed && retryCount < 3;
  
  Map<String, dynamic> toJson() => {
    'localId': localId,
    'serverId': serverId,
    'projectCode': projectCode,
    'speciesName': speciesName,
    'lat': lat,
    'lon': lon,
    'dbhCm': dbhCm,
    'heightM': heightM,
    'surveyTime': surveyTime.toIso8601String(),
    'status': status.name,
  };
}

/// 模擬後端 API
class TestMockBackendAPI {
  final math.Random _random = math.Random();
  final Map<String, Map<String, dynamic>> _serverData = {};
  int _nextId = 1;
  
  double errorRate;
  Duration latency;
  bool isDown;
  
  TestMockBackendAPI({
    this.errorRate = 0.0,
    this.latency = const Duration(milliseconds: 100),
    this.isDown = false,
  });
  
  /// 模擬創建記錄
  Future<Map<String, dynamic>> createRecord(Map<String, dynamic> data) async {
    await Future.delayed(latency);
    
    if (isDown) {
      throw Exception('Server is down');
    }
    
    if (_random.nextDouble() < errorRate) {
      throw Exception('Random server error');
    }
    
    final id = _nextId++;
    final systemTreeId = 'ST-$id';
    final projectTreeId = 'PT-$id';
    
    final serverRecord = {
      'id': id,
      'system_tree_id': systemTreeId,
      'project_tree_id': projectTreeId,
      ...data,
      'created_at': DateTime.now().toIso8601String(),
    };
    
    _serverData[id.toString()] = serverRecord;
    
    return serverRecord;
  }
  
  /// 模擬批量創建
  Future<List<Map<String, dynamic>>> batchCreate(List<Map<String, dynamic>> records) async {
    final results = <Map<String, dynamic>>[];
    
    for (final record in records) {
      results.add(await createRecord(record));
    }
    
    return results;
  }
  
  /// 獲取伺服器記錄數
  int get recordCount => _serverData.length;
  
  /// 重置
  void reset() {
    _serverData.clear();
    _nextId = 1;
  }
}

/// 本地資料庫模擬
class TestLocalDatabase {
  final Map<String, TestSurveyRecord> _records = {};
  final List<String> _syncQueue = [];
  
  /// 儲存記錄
  void save(TestSurveyRecord record) {
    _records[record.localId] = record;
  }
  
  /// 獲取記錄
  TestSurveyRecord? get(String localId) => _records[localId];
  
  /// 獲取所有記錄
  List<TestSurveyRecord> getAll() => _records.values.toList();
  
  /// 獲取待同步記錄
  List<TestSurveyRecord> getPendingSync() {
    return _records.values.where((r) => 
      r.status == SurveyStatus.pending || 
      r.status == SurveyStatus.failed
    ).toList();
  }
  
  /// 添加到同步佇列
  void queueForSync(String localId) {
    if (!_syncQueue.contains(localId)) {
      _syncQueue.add(localId);
    }
  }
  
  /// 獲取同步佇列
  List<String> get syncQueue => List.unmodifiable(_syncQueue);
  
  /// 從佇列移除
  void removeFromQueue(String localId) {
    _syncQueue.remove(localId);
  }
  
  /// 清除所有資料
  void clear() {
    _records.clear();
    _syncQueue.clear();
  }
  
  /// 統計
  Map<SurveyStatus, int> getStatusCounts() {
    final counts = <SurveyStatus, int>{};
    for (final record in _records.values) {
      counts[record.status] = (counts[record.status] ?? 0) + 1;
    }
    return counts;
  }
}

/// 同步服務
class TestSyncService {
  final TestLocalDatabase localDb;
  final TestMockBackendAPI api;
  
  NetworkStatus networkStatus;
  int successfulSyncs = 0;
  int failedSyncs = 0;
  
  TestSyncService({
    required this.localDb,
    required this.api,
    this.networkStatus = NetworkStatus.online,
  });
  
  /// 同步單筆記錄
  Future<bool> syncRecord(String localId) async {
    final record = localDb.get(localId);
    if (record == null) return false;
    
    if (networkStatus == NetworkStatus.offline) {
      record.status = SurveyStatus.pending;
      localDb.queueForSync(localId);
      return false;
    }
    
    try {
      record.status = SurveyStatus.inProgress;
      localDb.save(record);
      
      final result = await api.createRecord(record.toJson());
      
      record.serverId = result['id'].toString();
      record.status = SurveyStatus.synced;
      record.errorMessage = null;
      localDb.save(record);
      localDb.removeFromQueue(localId);
      
      successfulSyncs++;
      return true;
    } catch (e) {
      record.status = SurveyStatus.failed;
      record.retryCount++;
      record.errorMessage = e.toString();
      localDb.save(record);
      
      if (record.needsRetry) {
        localDb.queueForSync(localId);
      }
      
      failedSyncs++;
      return false;
    }
  }
  
  /// 同步所有待處理記錄
  Future<(int, int)> syncAll() async {
    final pending = localDb.getPendingSync();
    int success = 0;
    int failed = 0;
    
    for (final record in pending) {
      if (await syncRecord(record.localId)) {
        success++;
      } else {
        failed++;
      }
    }
    
    return (success, failed);
  }
  
  /// 重試失敗的記錄
  Future<int> retryFailed() async {
    final failed = localDb.getAll().where((r) => r.needsRetry).toList();
    int retried = 0;
    
    for (final record in failed) {
      if (await syncRecord(record.localId)) {
        retried++;
      }
    }
    
    return retried;
  }
}

/// 調查工作流程管理器
class TestSurveyWorkflowManager {
  final TestLocalDatabase localDb;
  final TestSyncService syncService;
  final math.Random _random = math.Random();
  
  int _localIdCounter = 1;
  String? currentProject;
  
  TestSurveyWorkflowManager({
    required this.localDb,
    required this.syncService,
  });
  
  /// 開始新專案
  void startProject(String projectCode) {
    currentProject = projectCode;
  }
  
  /// 結束專案
  void endProject() {
    currentProject = null;
  }
  
  /// 創建新調查記錄
  TestSurveyRecord createSurvey({
    required String speciesName,
    required double lat,
    required double lon,
    double? dbhCm,
    double? heightM,
    Map<String, dynamic>? metadata,
  }) {
    if (currentProject == null) {
      throw Exception('No active project');
    }
    
    final record = TestSurveyRecord(
      localId: 'LOCAL-${_localIdCounter++}',
      projectCode: currentProject!,
      speciesName: speciesName,
      lat: lat,
      lon: lon,
      dbhCm: dbhCm,
      heightM: heightM,
      metadata: metadata,
    );
    
    localDb.save(record);
    localDb.queueForSync(record.localId);
    
    return record;
  }
  
  /// 模擬現場調查
  List<TestSurveyRecord> simulateFieldSurvey({
    required int treeCount,
    double centerLat = 25.0,
    double centerLon = 121.5,
    double radiusKm = 0.5,
  }) {
    final records = <TestSurveyRecord>[];
    final species = ['樟樹', '榕樹', '楓香', '黑板樹', '茄苳', '龍眼'];
    
    for (var i = 0; i < treeCount; i++) {
      // 隨機位置
      final angle = _random.nextDouble() * 2 * math.pi;
      final distance = _random.nextDouble() * radiusKm / 111; // 度數
      final lat = centerLat + distance * math.cos(angle);
      final lon = centerLon + distance * math.sin(angle);
      
      records.add(createSurvey(
        speciesName: species[_random.nextInt(species.length)],
        lat: lat,
        lon: lon,
        dbhCm: 10 + _random.nextDouble() * 90, // 10-100 cm
        heightM: 3 + _random.nextDouble() * 27, // 3-30 m
        metadata: {
          'surveyNumber': i + 1,
          'operator': 'TestOperator',
        },
      ));
    }
    
    return records;
  }
  
  /// 獲取統計資訊
  Map<String, dynamic> getStatistics() {
    final all = localDb.getAll();
    final statusCounts = localDb.getStatusCounts();
    
    return {
      'totalRecords': all.length,
      'synced': statusCounts[SurveyStatus.synced] ?? 0,
      'pending': statusCounts[SurveyStatus.pending] ?? 0,
      'failed': statusCounts[SurveyStatus.failed] ?? 0,
      'inProgress': statusCounts[SurveyStatus.inProgress] ?? 0,
      'successfulSyncs': syncService.successfulSyncs,
      'failedSyncs': syncService.failedSyncs,
    };
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  late TestLocalDatabase localDb;
  late TestMockBackendAPI api;
  late TestSyncService syncService;
  late TestSurveyWorkflowManager workflow;
  
  setUp(() {
    localDb = TestLocalDatabase();
    api = TestMockBackendAPI();
    syncService = TestSyncService(localDb: localDb, api: api);
    workflow = TestSurveyWorkflowManager(localDb: localDb, syncService: syncService);
  });
  
  // =========================================================================
  // 基本工作流程測試
  // =========================================================================
  
  group('基本工作流程測試', () {
    test('創建調查記錄', () {
      workflow.startProject('P001');
      
      final record = workflow.createSurvey(
        speciesName: '樟樹',
        lat: 25.033,
        lon: 121.565,
        dbhCm: 45.5,
        heightM: 12.3,
      );
      
      expect(record.localId, startsWith('LOCAL-'));
      expect(record.projectCode, 'P001');
      expect(record.status, SurveyStatus.pending);
    });
    
    test('無專案時無法創建記錄', () {
      expect(
        () => workflow.createSurvey(
          speciesName: '樟樹',
          lat: 25.0,
          lon: 121.5,
        ),
        throwsException,
      );
    });
    
    test('模擬現場調查', () {
      workflow.startProject('P001');
      
      final records = workflow.simulateFieldSurvey(treeCount: 10);
      
      expect(records.length, 10);
      expect(localDb.getAll().length, 10);
      expect(localDb.syncQueue.length, 10);
    });
  });
  
  // =========================================================================
  // 同步測試
  // =========================================================================
  
  group('同步測試', () {
    test('線上同步成功', () async {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      final (success, failed) = await syncService.syncAll();
      
      expect(success, 1);
      expect(failed, 0);
      
      final record = localDb.getAll().first;
      expect(record.status, SurveyStatus.synced);
      expect(record.serverId, isNotNull);
    });
    
    test('離線狀態不同步', () async {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      syncService.networkStatus = NetworkStatus.offline;
      
      final (success, failed) = await syncService.syncAll();
      
      expect(success, 0);
      expect(failed, 1);
      
      final record = localDb.getAll().first;
      expect(record.status, SurveyStatus.pending);
    });
    
    test('伺服器錯誤時重試', () async {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      // 設定 100% 錯誤率
      api.errorRate = 1.0;
      
      await syncService.syncAll();
      
      final record = localDb.getAll().first;
      expect(record.status, SurveyStatus.failed);
      expect(record.retryCount, 1);
      expect(record.needsRetry, true);
      
      // 恢復正常
      api.errorRate = 0.0;
      
      final retried = await syncService.retryFailed();
      expect(retried, 1);
      
      final updatedRecord = localDb.getAll().first;
      expect(updatedRecord.status, SurveyStatus.synced);
    });
    
    test('批量同步', () async {
      workflow.startProject('P001');
      workflow.simulateFieldSurvey(treeCount: 20);
      
      final (success, failed) = await syncService.syncAll();
      
      expect(success, 20);
      expect(failed, 0);
      expect(api.recordCount, 20);
    });
  });
  
  // =========================================================================
  // 離線/線上切換測試
  // =========================================================================
  
  group('離線/線上切換測試', () {
    test('離線收集後線上同步', () async {
      workflow.startProject('P001');
      
      // 離線收集
      syncService.networkStatus = NetworkStatus.offline;
      workflow.simulateFieldSurvey(treeCount: 10);
      
      await syncService.syncAll();
      
      final stats = workflow.getStatistics();
      expect(stats['synced'], 0);
      expect(stats['pending'], 10);
      
      // 恢復線上
      syncService.networkStatus = NetworkStatus.online;
      final (success, _) = await syncService.syncAll();
      
      expect(success, 10);
      
      final newStats = workflow.getStatistics();
      expect(newStats['synced'], 10);
    });
    
    test('不穩定網路', () async {
      workflow.startProject('P001');
      workflow.simulateFieldSurvey(treeCount: 20);
      
      // 50% 錯誤率
      api.errorRate = 0.5;
      
      final (success1, failed1) = await syncService.syncAll();
      
      // 應該有部分成功，部分失敗
      expect(success1, greaterThan(0));
      expect(failed1, greaterThan(0));
      
      // 重試失敗的
      api.errorRate = 0.0;
      await syncService.retryFailed();
      
      final stats = workflow.getStatistics();
      expect(stats['synced'], 20);
    });
  });
  
  // =========================================================================
  // 效能壓力測試
  // =========================================================================
  
  group('效能壓力測試', () {
    test('大量記錄處理', () async {
      workflow.startProject('P001');
      
      final stopwatch = Stopwatch()..start();
      workflow.simulateFieldSurvey(treeCount: 1000);
      stopwatch.stop();
      
      expect(stopwatch.elapsedMilliseconds, lessThan(5000)); // 5 秒內
      expect(localDb.getAll().length, 1000);
    });
    
    test('高並發同步', () async {
      workflow.startProject('P001');
      workflow.simulateFieldSurvey(treeCount: 100);
      
      // 減少延遲模擬高並發
      api.latency = const Duration(milliseconds: 10);
      
      final stopwatch = Stopwatch()..start();
      final (success, _) = await syncService.syncAll();
      stopwatch.stop();
      
      expect(success, 100);
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });
  
  // =========================================================================
  // 資料完整性測試
  // =========================================================================
  
  group('資料完整性測試', () {
    test('所有必填欄位存在', () {
      workflow.startProject('P001');
      
      final record = workflow.createSurvey(
        speciesName: '樟樹',
        lat: 25.033,
        lon: 121.565,
      );
      
      expect(record.localId, isNotEmpty);
      expect(record.projectCode, isNotEmpty);
      expect(record.speciesName, isNotEmpty);
      expect(record.lat, isNotNull);
      expect(record.lon, isNotNull);
      expect(record.surveyTime, isNotNull);
    });
    
    test('JSON 序列化正確', () {
      workflow.startProject('P001');
      
      final record = workflow.createSurvey(
        speciesName: '樟樹',
        lat: 25.033,
        lon: 121.565,
        dbhCm: 45.5,
        heightM: 12.3,
      );
      
      final json = record.toJson();
      
      expect(json['projectCode'], 'P001');
      expect(json['speciesName'], '樟樹');
      expect(json['lat'], 25.033);
      expect(json['lon'], 121.565);
      expect(json['dbhCm'], 45.5);
      expect(json['heightM'], 12.3);
    });
    
    test('同步後資料完整', () async {
      workflow.startProject('P001');
      
      final originalRecord = workflow.createSurvey(
        speciesName: '樟樹',
        lat: 25.033,
        lon: 121.565,
        dbhCm: 45.5,
        metadata: {'operator': 'Test'},
      );
      
      await syncService.syncAll();
      
      final syncedRecord = localDb.get(originalRecord.localId)!;
      
      expect(syncedRecord.speciesName, originalRecord.speciesName);
      expect(syncedRecord.lat, originalRecord.lat);
      expect(syncedRecord.lon, originalRecord.lon);
      expect(syncedRecord.dbhCm, originalRecord.dbhCm);
      expect(syncedRecord.serverId, isNotNull);
    });
  });
  
  // =========================================================================
  // 多專案測試
  // =========================================================================
  
  group('多專案測試', () {
    test('切換專案', () {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      workflow.endProject();
      workflow.startProject('P002');
      workflow.createSurvey(speciesName: '榕樹', lat: 25.1, lon: 121.6);
      
      final all = localDb.getAll();
      final p1Records = all.where((r) => r.projectCode == 'P001');
      final p2Records = all.where((r) => r.projectCode == 'P002');
      
      expect(p1Records.length, 1);
      expect(p2Records.length, 1);
    });
    
    test('多專案同步', () async {
      workflow.startProject('P001');
      workflow.simulateFieldSurvey(treeCount: 10);
      
      workflow.endProject();
      workflow.startProject('P002');
      workflow.simulateFieldSurvey(treeCount: 10);
      
      final (success, _) = await syncService.syncAll();
      
      expect(success, 20);
    });
  });
  
  // =========================================================================
  // 伺服器故障恢復測試
  // =========================================================================
  
  group('伺服器故障恢復測試', () {
    test('伺服器宕機處理', () async {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      api.isDown = true;
      
      final (success, failed) = await syncService.syncAll();
      
      expect(success, 0);
      expect(failed, 1);
      
      final record = localDb.getAll().first;
      expect(record.status, SurveyStatus.failed);
      expect(record.errorMessage, contains('Server is down'));
    });
    
    test('伺服器恢復後重試', () async {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      api.isDown = true;
      await syncService.syncAll();
      
      api.isDown = false;
      final retried = await syncService.retryFailed();
      
      expect(retried, 1);
      
      final record = localDb.getAll().first;
      expect(record.status, SurveyStatus.synced);
    });
    
    test('重試次數限制', () async {
      workflow.startProject('P001');
      workflow.createSurvey(speciesName: '樟樹', lat: 25.0, lon: 121.5);
      
      api.errorRate = 1.0;
      
      // 重試 3 次
      for (var i = 0; i < 3; i++) {
        await syncService.syncAll();
      }
      
      final record = localDb.getAll().first;
      expect(record.retryCount, 3);
      expect(record.needsRetry, false); // 達到限制
    });
  });
}
