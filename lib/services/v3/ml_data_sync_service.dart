/// V3 ML 數據同步服務
/// 
/// 負責將本地收集的 ML 訓練數據上傳到後端
/// 
/// 功能：
/// - 自動背景同步
/// - 增量上傳（只上傳新記錄）
/// - 錯誤重試
/// - 網絡狀態感知
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

import 'ml_data_collector.dart';
import '../api_service.dart';

/// ML 數據同步服務
class MLDataSyncService {
  /// 單例
  static final MLDataSyncService _instance = MLDataSyncService._internal();
  factory MLDataSyncService() => _instance;
  MLDataSyncService._internal();

  /// API 基礎 URL
  static String _baseUrl = '';
  
  /// 最後同步時間 key
  static const String _lastSyncKey = 'v3_ml_last_sync';
  
  /// 同步失敗記錄 key
  static const String _failedBatchesKey = 'v3_ml_failed_batches';
  
  /// 最小同步間隔（毫秒）
  static const int _minSyncIntervalMs = 30 * 60 * 1000; // 30 分鐘
  
  /// 最大批次大小
  static const int _maxBatchSize = 500;
  
  /// 設備 ID
  String? _deviceId;
  
  /// APP 版本
  String? _appVersion;
  
  /// 是否正在同步
  bool _isSyncing = false;

  /// 初始化
  static Future<void> initialize(String baseUrl) async {
    _baseUrl = baseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    await _instance._loadDeviceInfo();
    debugPrint('[MLDataSync] 已初始化，API: $baseUrl');
  }

  /// 載入設備資訊
  Future<void> _loadDeviceInfo() async {
    try {
      // 獲取 APP 版本
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      
      // 獲取設備 ID
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        _deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await DeviceInfoPlugin().iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      } else {
        _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      debugPrint('[MLDataSync] 載入設備資訊失敗: $e');
      _deviceId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
      _appVersion = 'unknown';
    }
  }

  /// 檢查是否應該同步
  Future<bool> shouldSync() async {
    // 檢查網絡
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty) {
      return false;
    }
    
    // 優先在 WiFi 下同步
    // 如果是行動網絡且記錄數不多，也可以同步
    final records = await MLDataCollector.getLocalRecords();
    if (records.isEmpty) {
      return false;
    }
    
    // 檢查上次同步時間
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(_lastSyncKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 如果記錄超過一定數量，強制同步
    if (records.length > 100) {
      return true;
    }
    
    // 否則檢查時間間隔
    return (now - lastSync) >= _minSyncIntervalMs;
  }

  /// 同步數據到後端
  Future<SyncResult> sync({bool force = false}) async {
    if (_isSyncing) {
      return SyncResult(
        success: false,
        message: '同步進行中',
      );
    }
    
    if (!force) {
      final should = await shouldSync();
      if (!should) {
        return SyncResult(
          success: true,
          message: '無需同步',
          recordsSynced: 0,
        );
      }
    }
    
    _isSyncing = true;
    
    try {
      final records = await MLDataCollector.getLocalRecords();
      
      if (records.isEmpty) {
        return SyncResult(
          success: true,
          message: '無記錄需要同步',
          recordsSynced: 0,
        );
      }
      
      // 分批上傳
      int totalSynced = 0;
      final failures = <String>[];
      
      for (var i = 0; i < records.length; i += _maxBatchSize) {
        final end = math.min(i + _maxBatchSize, records.length);
        final batch = records.sublist(i, end);
        
        final result = await _uploadBatch(batch);
        
        if (result.success) {
          totalSynced += batch.length;
        } else {
          failures.add(result.message ?? '未知錯誤');
        }
      }
      
      // 更新最後同步時間
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastSyncKey, DateTime.now().millisecondsSinceEpoch);
      
      // 如果全部成功，清除本地記錄
      if (failures.isEmpty) {
        await MLDataCollector.clearLocalRecords();
        return SyncResult(
          success: true,
          message: '同步成功',
          recordsSynced: totalSynced,
        );
      } else {
        return SyncResult(
          success: false,
          message: '部分同步失敗: ${failures.join("; ")}',
          recordsSynced: totalSynced,
          errors: failures,
        );
      }
      
    } catch (e) {
      debugPrint('[MLDataSync] 同步錯誤: $e');
      return SyncResult(
        success: false,
        message: '同步失敗: $e',
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// 上傳單個批次
  Future<SyncResult> _uploadBatch(List<MLTrainingRecord> records) async {
    final batchId = _generateBatchId();
    
    // 轉換記錄格式以符合後端 API
    final apiRecords = records.map((r) => _convertToApiFormat(r)).toList();
    
    final body = jsonEncode({
      'batch_id': batchId,
      'device_id': _deviceId ?? 'unknown',
      'app_version': _appVersion ?? 'unknown',
      'records': apiRecords,
    });
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ml-training/batch'),
        headers: {
          'Content-Type': 'application/json',
          ...ApiService.getAuthHeaders(),
        },
        body: body,
      ).timeout(
        const Duration(seconds: 30),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('[MLDataSync] 批次 $batchId 上傳成功，記錄數: ${records.length}');
          return SyncResult(
            success: true,
            batchId: batchId,
            recordsSynced: records.length,
          );
        } else {
          return SyncResult(
            success: false,
            message: data['error'] ?? '上傳失敗',
            batchId: batchId,
          );
        }
      } else {
        return SyncResult(
          success: false,
          message: 'HTTP ${response.statusCode}: ${response.body}',
          batchId: batchId,
        );
      }
    } catch (e) {
      return SyncResult(
        success: false,
        message: '網絡錯誤: $e',
        batchId: batchId,
      );
    }
  }

  /// 轉換記錄格式為 API 格式
  Map<String, dynamic> _convertToApiFormat(MLTrainingRecord record) {
    // 將 MLRecordType 轉換為後端 API 格式
    String recordType;
    switch (record.recordType) {
      case MLRecordType.arMeasurement:
        recordType = 'arMeasurement';
        break;
      case MLRecordType.speciesIdentification:
        recordType = 'speciesIdentification';
        break;
      case MLRecordType.carbonCalculation:
        recordType = 'carbonModification';
        break;
      case MLRecordType.coordinateCorrection:
        recordType = 'coordinateCorrection';
        break;
      case MLRecordType.stationPositionCalculation:
        recordType = 'heightEstimation';  // 暫時映射
        break;
      default:
        recordType = 'carbonModification';  // 預設
    }
    
    return {
      'record_type': recordType,
      'tree_id': record.treeId,
      'auto_values': record.autoValues,
      'user_values': record.userValues,
      'difference': record.differenceAnalysis,
      'context': {
        ...record.environment,
        ...record.metadata,
        'input_parameters': record.inputParameters,
      },
      'image_paths': record.metadata['image_paths'] ?? [],
      'timestamp': record.timestamp.toIso8601String(),
    };
  }

  /// 生成批次 ID
  String _generateBatchId() {
    final now = DateTime.now();
    final random = math.Random();
    // UUID v4 格式
    return '${now.millisecondsSinceEpoch.toRadixString(16)}-'
           '${random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}-'
           '${random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}-'
           '${random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
  }

  /// 定時同步 Timer
  Timer? _periodicTimer;

  /// 啟動定時同步
  /// 
  /// [intervalMinutes] 同步間隔（分鐘），預設 30 分鐘
  void startPeriodicSync({int intervalMinutes = 30}) {
    // 停止現有定時器
    stopPeriodicSync();
    
    debugPrint('[MLDataSync] 啟動定時同步，間隔: $intervalMinutes 分鐘');
    
    // 立即執行一次同步檢查
    syncIfNeeded();
    
    // 設置定時同步
    _periodicTimer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (_) => syncIfNeeded(),
    );
  }

  /// 停止定時同步
  void stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  /// 如果需要則同步（不強制）
  Future<SyncResult> syncIfNeeded() async {
    return sync(force: false);
  }

  /// 獲取同步狀態
  Future<SyncStatus> getStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSync = prefs.getInt(_lastSyncKey);
    final records = await MLDataCollector.getLocalRecords();
    
    return SyncStatus(
      lastSyncTime: lastSync != null 
          ? DateTime.fromMillisecondsSinceEpoch(lastSync)
          : null,
      pendingRecords: records.length,
      isSyncing: _isSyncing,
    );
  }

  /// 嘗試重試失敗的批次
  Future<void> retryFailed() async {
    final prefs = await SharedPreferences.getInstance();
    final failedJson = prefs.getStringList(_failedBatchesKey) ?? [];
    
    if (failedJson.isEmpty) return;
    
    debugPrint('[MLDataSync] 重試 ${failedJson.length} 個失敗批次');
    // 清除失敗記錄後重新執行完整同步
    await prefs.setStringList(_failedBatchesKey, []);
    final result = await sync(force: true);
    if (!result.success) {
      debugPrint('[MLDataSync] 重試同步失敗: ${result.message}');
    } else {
      debugPrint('[MLDataSync] 重試同步完成');
    }
  }
}

/// 同步結果
class SyncResult {
  final bool success;
  final String? message;
  final String? batchId;
  final int? recordsSynced;
  final List<String>? errors;

  SyncResult({
    required this.success,
    this.message,
    this.batchId,
    this.recordsSynced,
    this.errors,
  });

  @override
  String toString() {
    if (success) {
      return 'SyncResult: 成功，同步 ${recordsSynced ?? 0} 條記錄';
    } else {
      return 'SyncResult: 失敗 - $message';
    }
  }
}

/// 同步狀態
class SyncStatus {
  final DateTime? lastSyncTime;
  final int pendingRecords;
  final bool isSyncing;

  SyncStatus({
    this.lastSyncTime,
    required this.pendingRecords,
    required this.isSyncing,
  });

  String get statusText {
    if (isSyncing) return '同步中...';
    if (pendingRecords == 0) return '已同步';
    return '待同步 $pendingRecords 條記錄';
  }

  @override
  String toString() {
    return 'SyncStatus: $statusText (上次同步: $lastSyncTime)';
  }
}
