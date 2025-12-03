// ============================================================================
// V3 衝突解決服務 (Conflict Resolution Service)
// ============================================================================
// 採用「兼容式開發」原則：
// - 獨立的 V3 服務，不修改現有 API
// - 使用 Optimistic Lock + 版本號機制
// - 本地暫存 + 自動重試 + 衝突通知
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';

/// 衝突類型
enum ConflictType {
  /// 版本衝突 - 伺服器有更新的版本
  versionConflict,
  
  /// 資料被刪除
  dataDeleted,
  
  /// 權限變更
  permissionChanged,
  
  /// 網路錯誤（暫時性）
  networkError,
  
  /// 驗證錯誤
  validationError,
}

/// 解決策略
enum ResolutionStrategy {
  /// 使用本地版本覆蓋伺服器
  forceLocal,
  
  /// 使用伺服器版本放棄本地修改
  acceptRemote,
  
  /// 合併兩個版本（如果可能）
  merge,
  
  /// 暫存並稍後重試
  queueRetry,
  
  /// 放棄操作
  abandon,
}

/// 待處理的操作
class PendingOperation {
  final String id;
  final String entityType; // 'tree_survey', 'tree_data', etc.
  final String entityId;
  final String operationType; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final int? expectedVersion;
  final DateTime createdAt;
  final int retryCount;
  final ConflictType? lastConflict;
  
  PendingOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operationType,
    required this.data,
    this.expectedVersion,
    DateTime? createdAt,
    this.retryCount = 0,
    this.lastConflict,
  }) : createdAt = createdAt ?? DateTime.now();
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'entityType': entityType,
    'entityId': entityId,
    'operationType': operationType,
    'data': data,
    'expectedVersion': expectedVersion,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    'lastConflict': lastConflict?.index,
  };
  
  factory PendingOperation.fromJson(Map<String, dynamic> json) => PendingOperation(
    id: json['id'],
    entityType: json['entityType'],
    entityId: json['entityId'],
    operationType: json['operationType'],
    data: Map<String, dynamic>.from(json['data']),
    expectedVersion: json['expectedVersion'],
    createdAt: DateTime.parse(json['createdAt']),
    retryCount: json['retryCount'] ?? 0,
    lastConflict: json['lastConflict'] != null 
      ? ConflictType.values[json['lastConflict']] 
      : null,
  );
  
  PendingOperation copyWith({
    int? retryCount,
    ConflictType? lastConflict,
  }) => PendingOperation(
    id: id,
    entityType: entityType,
    entityId: entityId,
    operationType: operationType,
    data: data,
    expectedVersion: expectedVersion,
    createdAt: createdAt,
    retryCount: retryCount ?? this.retryCount,
    lastConflict: lastConflict ?? this.lastConflict,
  );
}

/// 衝突事件資訊
class ConflictEvent {
  final PendingOperation operation;
  final ConflictType conflictType;
  final Map<String, dynamic>? remoteData;
  final String? errorMessage;
  
  ConflictEvent({
    required this.operation,
    required this.conflictType,
    this.remoteData,
    this.errorMessage,
  });
}

/// V3 衝突解決服務 - 單例模式
class ConflictResolutionService {
  static final ConflictResolutionService _instance = ConflictResolutionService._internal();
  factory ConflictResolutionService() => _instance;
  ConflictResolutionService._internal();
  
  // 設定
  static const String _storageKey = 'v3_pending_operations';
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 30);
  static const Duration _autoSyncInterval = Duration(minutes: 5);
  
  // 狀態
  final List<PendingOperation> _pendingQueue = [];
  bool _isProcessing = false;
  Timer? _autoSyncTimer;
  bool _initialized = false;
  
  // 事件流
  final _conflictController = StreamController<ConflictEvent>.broadcast();
  Stream<ConflictEvent> get conflictStream => _conflictController.stream;
  
  final _queueChangeController = StreamController<List<PendingOperation>>.broadcast();
  Stream<List<PendingOperation>> get queueChangeStream => _queueChangeController.stream;
  
  /// 取得待處理操作數量
  int get pendingCount => _pendingQueue.length;
  
  /// 取得所有待處理操作
  List<PendingOperation> get pendingOperations => List.unmodifiable(_pendingQueue);
  
  /// 初始化服務
  Future<void> initialize() async {
    if (_initialized) return;
    
    await _loadPendingOperations();
    _startAutoSync();
    _initialized = true;
    
    debugPrint('[ConflictResolutionService] 初始化完成，待處理操作: ${_pendingQueue.length}');
  }
  
  /// 釋放資源
  void dispose() {
    _autoSyncTimer?.cancel();
    _conflictController.close();
    _queueChangeController.close();
  }
  
  /// 提交操作（帶版本控制）
  /// 
  /// 返回 true 表示成功，false 表示需要處理衝突
  Future<bool> submitOperation({
    required String entityType,
    required String entityId,
    required String operationType,
    required Map<String, dynamic> data,
    int? expectedVersion,
  }) async {
    final operation = PendingOperation(
      id: '${DateTime.now().millisecondsSinceEpoch}_$entityId',
      entityType: entityType,
      entityId: entityId,
      operationType: operationType,
      data: data,
      expectedVersion: expectedVersion,
    );
    
    // 嘗試立即執行
    final result = await _executeOperation(operation);
    
    if (!result) {
      // 執行失敗，加入待處理隊列
      _pendingQueue.add(operation);
      await _savePendingOperations();
      _queueChangeController.add(_pendingQueue);
    }
    
    return result;
  }
  
  /// 執行單個操作
  Future<bool> _executeOperation(PendingOperation operation) async {
    try {
      final response = await _sendToServer(operation);
      
      if (response['success'] == true) {
        return true;
      }
      
      // 處理不同的錯誤類型
      final errorCode = response['errorCode'] as String?;
      final conflictType = _parseConflictType(errorCode);
      
      _conflictController.add(ConflictEvent(
        operation: operation,
        conflictType: conflictType,
        remoteData: response['remoteData'] as Map<String, dynamic>?,
        errorMessage: response['message'] as String?,
      ));
      
      return false;
      
    } catch (e) {
      debugPrint('[ConflictResolutionService] 執行操作失敗: $e');
      
      _conflictController.add(ConflictEvent(
        operation: operation,
        conflictType: ConflictType.networkError,
        errorMessage: e.toString(),
      ));
      
      return false;
    }
  }
  
  /// 發送到伺服器
  Future<Map<String, dynamic>> _sendToServer(PendingOperation operation) async {
    // 根據操作類型和實體類型構建 API 請求
    // 這裡使用 V3 API 端點，不影響現有 API
    final endpoint = _getV3Endpoint(operation);
    
    try {
      Map<String, dynamic> result;
      
      switch (operation.operationType) {
        case 'create':
          result = await ApiService.post(endpoint, {
            ...operation.data,
            '_v3_version': operation.expectedVersion ?? 1,
          });
          break;
          
        case 'update':
          result = await ApiService.put(endpoint, {
            ...operation.data,
            '_v3_expected_version': operation.expectedVersion,
          });
          break;
          
        case 'delete':
          result = await ApiService.delete(endpoint);
          break;
          
        default:
          throw Exception('Unknown operation type: ${operation.operationType}');
      }
      
      // 檢查 API 回應
      if (result['success'] == true) {
        return {'success': true, 'data': result};
      } else {
        return {
          'success': false,
          'errorCode': result['errorCode']?.toString() ?? 'unknown',
          'message': result['message'] ?? 'Unknown error',
        };
      }
      
    } catch (e) {
      return {
        'success': false,
        'errorCode': 'network_error',
        'message': e.toString(),
      };
    }
  }
  
  /// 取得 V3 API 端點
  String _getV3Endpoint(PendingOperation operation) {
    switch (operation.entityType) {
      case 'tree_survey':
        if (operation.operationType == 'create') {
          return '/v3/tree-surveys';
        }
        return '/v3/tree-surveys/${operation.entityId}';
        
      case 'tree_data':
        if (operation.operationType == 'create') {
          return '/v3/trees';
        }
        return '/v3/trees/${operation.entityId}';
        
      case 'project':
        if (operation.operationType == 'create') {
          return '/v3/projects';
        }
        return '/v3/projects/${operation.entityId}';
        
      default:
        return '/v3/${operation.entityType}/${operation.entityId}';
    }
  }
  
  /// 解析衝突類型
  ConflictType _parseConflictType(String? errorCode) {
    switch (errorCode) {
      case '409':
        return ConflictType.versionConflict;
      case '404':
        return ConflictType.dataDeleted;
      case '403':
        return ConflictType.permissionChanged;
      case '400':
      case '422':
        return ConflictType.validationError;
      default:
        return ConflictType.networkError;
    }
  }
  
  /// 處理衝突
  Future<bool> resolveConflict(
    PendingOperation operation,
    ResolutionStrategy strategy, {
    Map<String, dynamic>? mergedData,
  }) async {
    switch (strategy) {
      case ResolutionStrategy.forceLocal:
        // 強制使用本地版本，忽略版本檢查
        final forceOperation = PendingOperation(
          id: operation.id,
          entityType: operation.entityType,
          entityId: operation.entityId,
          operationType: operation.operationType,
          data: {
            ...operation.data,
            '_v3_force_update': true,
          },
          expectedVersion: null, // 不檢查版本
        );
        return await _executeOperation(forceOperation);
        
      case ResolutionStrategy.acceptRemote:
        // 放棄本地修改
        _removeFromQueue(operation.id);
        return true;
        
      case ResolutionStrategy.merge:
        if (mergedData == null) {
          debugPrint('[ConflictResolutionService] 合併策略需要提供 mergedData');
          return false;
        }
        // 使用合併後的資料
        final mergeOperation = PendingOperation(
          id: operation.id,
          entityType: operation.entityType,
          entityId: operation.entityId,
          operationType: operation.operationType,
          data: mergedData,
          expectedVersion: null, // 合併後強制更新
        );
        return await _executeOperation(mergeOperation);
        
      case ResolutionStrategy.queueRetry:
        // 保留在隊列中，稍後重試
        return false;
        
      case ResolutionStrategy.abandon:
        // 放棄操作
        _removeFromQueue(operation.id);
        return true;
    }
  }
  
  /// 從隊列中移除操作
  void _removeFromQueue(String operationId) {
    _pendingQueue.removeWhere((op) => op.id == operationId);
    _savePendingOperations();
    _queueChangeController.add(_pendingQueue);
  }
  
  /// 手動重試所有待處理操作
  Future<void> retryAllPending() async {
    if (_isProcessing) return;
    _isProcessing = true;
    
    try {
      final operationsToRetry = List<PendingOperation>.from(_pendingQueue);
      
      for (final operation in operationsToRetry) {
        if (operation.retryCount >= _maxRetries) {
          debugPrint('[ConflictResolutionService] 操作 ${operation.id} 已達最大重試次數');
          continue;
        }
        
        final success = await _executeOperation(operation);
        
        if (success) {
          _removeFromQueue(operation.id);
        } else {
          // 更新重試次數
          final index = _pendingQueue.indexWhere((op) => op.id == operation.id);
          if (index >= 0) {
            _pendingQueue[index] = operation.copyWith(
              retryCount: operation.retryCount + 1,
            );
          }
        }
        
        // 延遲避免請求過於頻繁
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      await _savePendingOperations();
      _queueChangeController.add(_pendingQueue);
      
    } finally {
      _isProcessing = false;
    }
  }
  
  /// 清除所有待處理操作
  Future<void> clearAllPending() async {
    _pendingQueue.clear();
    await _savePendingOperations();
    _queueChangeController.add(_pendingQueue);
  }
  
  /// 取得實體的本地快取版本
  Future<int?> getLocalVersion(String entityType, String entityId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'v3_version_${entityType}_$entityId';
    return prefs.getInt(key);
  }
  
  /// 更新實體的本地版本
  Future<void> updateLocalVersion(String entityType, String entityId, int version) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'v3_version_${entityType}_$entityId';
    await prefs.setInt(key, version);
  }
  
  /// 載入待處理操作
  Future<void> _loadPendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      
      if (jsonString == null) return;
      
      final List<dynamic> jsonList = json.decode(jsonString);
      _pendingQueue.clear();
      _pendingQueue.addAll(
        jsonList.map((j) => PendingOperation.fromJson(j as Map<String, dynamic>))
      );
      
      debugPrint('[ConflictResolutionService] 載入 ${_pendingQueue.length} 個待處理操作');
      
    } catch (e) {
      debugPrint('[ConflictResolutionService] 載入待處理操作失敗: $e');
    }
  }
  
  /// 儲存待處理操作
  Future<void> _savePendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(
        _pendingQueue.map((op) => op.toJson()).toList()
      );
      await prefs.setString(_storageKey, jsonString);
    } catch (e) {
      debugPrint('[ConflictResolutionService] 儲存待處理操作失敗: $e');
    }
  }
  
  /// 啟動自動同步
  void _startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(_autoSyncInterval, (_) {
      if (_pendingQueue.isNotEmpty) {
        retryAllPending();
      }
    });
  }
}

/// 衝突解決對話框（UI 工具）
class ConflictResolutionDialog extends StatelessWidget {
  final ConflictEvent event;
  final VoidCallback? onForceLocal;
  final VoidCallback? onAcceptRemote;
  final VoidCallback? onRetryLater;
  
  const ConflictResolutionDialog({
    Key? key,
    required this.event,
    this.onForceLocal,
    this.onAcceptRemote,
    this.onRetryLater,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _getConflictIcon(),
            color: _getConflictColor(),
          ),
          const SizedBox(width: 8),
          Text(_getConflictTitle()),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_getConflictDescription()),
          if (event.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              '詳情: ${event.errorMessage}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ],
      ),
      actions: _buildActions(context),
    );
  }
  
  IconData _getConflictIcon() {
    switch (event.conflictType) {
      case ConflictType.versionConflict:
        return Icons.sync_problem;
      case ConflictType.dataDeleted:
        return Icons.delete_forever;
      case ConflictType.permissionChanged:
        return Icons.lock;
      case ConflictType.networkError:
        return Icons.wifi_off;
      case ConflictType.validationError:
        return Icons.error_outline;
    }
  }
  
  Color _getConflictColor() {
    switch (event.conflictType) {
      case ConflictType.versionConflict:
        return Colors.orange;
      case ConflictType.dataDeleted:
        return Colors.red;
      case ConflictType.permissionChanged:
        return Colors.purple;
      case ConflictType.networkError:
        return Colors.grey;
      case ConflictType.validationError:
        return Colors.amber;
    }
  }
  
  String _getConflictTitle() {
    switch (event.conflictType) {
      case ConflictType.versionConflict:
        return '資料衝突';
      case ConflictType.dataDeleted:
        return '資料已刪除';
      case ConflictType.permissionChanged:
        return '權限變更';
      case ConflictType.networkError:
        return '網路錯誤';
      case ConflictType.validationError:
        return '驗證錯誤';
    }
  }
  
  String _getConflictDescription() {
    switch (event.conflictType) {
      case ConflictType.versionConflict:
        return '此資料已被其他使用者修改。您可以選擇使用您的版本覆蓋，或接受伺服器上的最新版本。';
      case ConflictType.dataDeleted:
        return '此資料已從伺服器刪除。';
      case ConflictType.permissionChanged:
        return '您已沒有權限執行此操作。';
      case ConflictType.networkError:
        return '網路連線失敗，操作已加入待處理隊列，將在網路恢復後自動重試。';
      case ConflictType.validationError:
        return '資料格式錯誤，請檢查輸入內容。';
    }
  }
  
  List<Widget> _buildActions(BuildContext context) {
    final actions = <Widget>[];
    
    if (event.conflictType == ConflictType.versionConflict) {
      actions.add(
        TextButton(
          onPressed: () {
            onAcceptRemote?.call();
            Navigator.of(context).pop();
          },
          child: const Text('使用伺服器版本'),
        ),
      );
      actions.add(
        ElevatedButton(
          onPressed: () {
            onForceLocal?.call();
            Navigator.of(context).pop();
          },
          child: const Text('使用我的版本'),
        ),
      );
    } else if (event.conflictType == ConflictType.networkError) {
      actions.add(
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('確定'),
        ),
      );
      actions.add(
        ElevatedButton(
          onPressed: () {
            onRetryLater?.call();
            Navigator.of(context).pop();
          },
          child: const Text('立即重試'),
        ),
      );
    } else {
      actions.add(
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('確定'),
        ),
      );
    }
    
    return actions;
  }
  
  /// 顯示衝突對話框的便捷方法
  static Future<void> show(
    BuildContext context,
    ConflictEvent event, {
    VoidCallback? onForceLocal,
    VoidCallback? onAcceptRemote,
    VoidCallback? onRetryLater,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConflictResolutionDialog(
        event: event,
        onForceLocal: onForceLocal,
        onAcceptRemote: onAcceptRemote,
        onRetryLater: onRetryLater,
      ),
    );
  }
}
