import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/pending_tree_measurement.dart';
import '../services/pending_measurement_service.dart';
import 'v3/integrated_tree_form_page.dart'; // V3 整合表單

/// 待測量任務頁面
/// 
/// 功能：
/// 1. 顯示待測量任務列表
/// 2. 導航引導到測站位置
/// 3. 箭頭指向目標樹木
/// 4. 整合 DBH 測量 (使用 V3 IntegratedTreeFormPage)
class PendingMeasurementTaskPage extends StatefulWidget {
  final String? sessionId;
  
  const PendingMeasurementTaskPage({
    super.key,
    this.sessionId,
  });

  @override
  State<PendingMeasurementTaskPage> createState() => _PendingMeasurementTaskPageState();
}

class _PendingMeasurementTaskPageState extends State<PendingMeasurementTaskPage>
    with SingleTickerProviderStateMixin {
  final PendingMeasurementService _service = PendingMeasurementService();
  
  // 狀態
  bool _isLoading = true;
  String? _error;
  List<PendingTreeMeasurement> _pendingTrees = [];
  PendingTreeMeasurement? _currentTask;
  
  // Session 管理
  String? _activeSessionId;
  List<MeasurementSession> _sessions = [];
  int _totalTasksInSession = 0;
  int _completedCount = 0;
  bool _isTransferring = false;
  
  // 位置追蹤
  Position? _userPosition;
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  double? _currentHeading; // 用戶朝向（磁北基準）
  AccelerometerEvent? _lastAccelEvent; // 用於傾斜補償
  
  // 導航狀態
  NavigationState _navState = NavigationState.selectingTask;
  
  // 動畫
  late AnimationController _arrowAnimController;
  
  @override
  void initState() {
    super.initState();
    _activeSessionId = widget.sessionId;
    _arrowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _initLoad();
    _startLocationTracking();
  }
  
  Future<void> _initLoad() async {
    if (_activeSessionId == null) {
      try {
        _sessions = await _service.getSessions();
        if (_sessions.length == 1) {
          _activeSessionId = _sessions.first.sessionId;
        }
      } catch (e) {
        debugPrint('[PendingTask] 載入 sessions 失敗: $e');
      }
    }
    await _loadTasks();
  }
  
  @override
  void dispose() {
    _positionSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _arrowAnimController.dispose();
    super.dispose();
  }
  
  Future<void> _loadTasks() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[PendingTask] GPS 定位失敗（不影響任務列表）: $e');
      }
      
      final pendingTrees = await _service.getPendingTrees(
        sessionId: _activeSessionId,
        status: MeasurementStatus.pending,
        userLat: position?.latitude,
        userLon: position?.longitude,
        sortByDistance: position != null,
      );
      
      final inProgressTrees = await _service.getPendingTrees(
        sessionId: _activeSessionId,
        status: MeasurementStatus.inProgress,
        userLat: position?.latitude,
        userLon: position?.longitude,
        sortByDistance: position != null,
      );
      
      final allTrees = [...inProgressTrees, ...pendingTrees];
      
      // Compute progress from session stats if available
      if (_activeSessionId != null) {
        try {
          final session = _sessions.isNotEmpty
              ? _sessions.firstWhere((s) => s.sessionId == _activeSessionId,
                  orElse: () => _sessions.first)
              : null;
          if (session != null) {
            _totalTasksInSession = session.totalTrees;
            _completedCount = session.completedTrees;
          }
        } catch (_) {}
        // Refresh sessions for accurate counts
        try {
          _sessions = await _service.getSessions();
          final updated = _sessions.where((s) => s.sessionId == _activeSessionId).toList();
          if (updated.isNotEmpty) {
            _totalTasksInSession = updated.first.totalTrees;
            _completedCount = updated.first.completedTrees;
          }
        } catch (_) {}
      }
      
      if (!mounted) return;
      setState(() {
        _pendingTrees = allTrees;
        _userPosition = position;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '載入任務失敗: $e';
        _isLoading = false;
      });
    }
  }
  
  void _startLocationTracking() async {
    try {
      // 檢查權限
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      
      // 開始追蹤位置（含方向）
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 1,
        ),
      ).listen((position) {
        if (mounted) {
          setState(() {
            _userPosition = position;
            if (position.heading >= 0 && position.speed > 0.3) {
              _currentHeading = position.heading;
            }
          });
          
          // [Phase 3] GPS 接近目標時自動推進流程
          _checkProximityAutoAdvance(position);
        }
      });
      
      // 加速度計（用於傾斜補償）
      _accelerometerSubscription = accelerometerEventStream()?.listen((event) {
        _lastAccelEvent = event;
      });
      
      // 磁力計 + 傾斜補償
      _magnetometerSubscription = magnetometerEventStream()?.listen((event) {
        if (!mounted) return;
        
        double heading;
        final accel = _lastAccelEvent;
        
        if (accel != null) {
          // 傾斜補償：用加速度計修正磁力計讀數
          final ax = accel.x, ay = accel.y, az = accel.z;
          final norm = math.sqrt(ax * ax + ay * ay + az * az);
          if (norm > 0.1) {
            final pitch = math.asin(-ax / norm);
            final roll = math.asin(ay / norm);
            // 補償後的磁力分量
            final compX = event.x * math.cos(pitch) + event.z * math.sin(pitch);
            final compY = event.x * math.sin(roll) * math.sin(pitch) 
                        + event.y * math.cos(roll) 
                        - event.z * math.sin(roll) * math.cos(pitch);
            heading = (math.atan2(-compX, compY) * 180 / math.pi + 360) % 360;
          } else {
            heading = (math.atan2(-event.x, event.y) * 180 / math.pi + 360) % 360;
          }
        } else {
          heading = (math.atan2(-event.x, event.y) * 180 / math.pi + 360) % 360;
        }
        
        setState(() {
          if (_userPosition == null || _userPosition!.speed <= 0.3) {
            _currentHeading = heading;
          }
        });
      });
      
    } catch (e) {
      debugPrint('位置追蹤失敗: $e');
    }
  }
  
  /// GPS 接近時不自動推進，改為純手動確認
  /// GPS 室內誤差大（15m+），自動推進會導致誤觸發
  void _checkProximityAutoAdvance(Position position) {
    // 不再自動推進，完全由使用者手動確認「已到達」
  }

  /// Revert current task to pending and return to task list
  Future<void> _abandonCurrentTask() async {
    if (_currentTask?.id != null) {
      try {
        await _service.updateTaskStatus(
          _currentTask!.id!, MeasurementStatus.pending,
        );
      } catch (e) {
        debugPrint('[PendingTask] 恢復 pending 狀態失敗: $e');
      }
    }
    setState(() {
      _navState = NavigationState.selectingTask;
      _currentTask = null;
    });
    _loadTasks();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _navState == NavigationState.selectingTask,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _navState != NavigationState.selectingTask) {
          _abandonCurrentTask();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_navState != NavigationState.selectingTask)
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: '返回列表',
              onPressed: _abandonCurrentTask,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: _buildBody(),
    ),
    );
  }
  
  String _getAppBarTitle() {
    switch (_navState) {
      case NavigationState.selectingTask:
        return '待測量任務 (${_pendingTrees.length})';
      case NavigationState.navigatingToStation:
        return '導航到測站';
      case NavigationState.pointingToTree:
        return '對準樹木';
      case NavigationState.measuring:
        return '測量中';
    }
  }
  
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTasks,
              icon: const Icon(Icons.refresh),
              label: const Text('重試'),
            ),
          ],
        ),
      );
    }
    
    switch (_navState) {
      case NavigationState.selectingTask:
        return _buildTaskList();
      case NavigationState.navigatingToStation:
        return _buildNavigationView();
      case NavigationState.pointingToTree:
        return _buildPointingView();
      case NavigationState.measuring:
        return _buildMeasuringView();
    }
  }
  
  /// 任務列表
  Widget _buildTaskList() {
    // No session selected and multiple sessions exist — show picker
    if (_activeSessionId == null && _sessions.length > 1) {
      return _buildSessionPicker();
    }
    
    if (_pendingTrees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text(
              '所有任務已完成',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '目前沒有待測量的樹木',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (_completedCount > 0) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isTransferring ? null : _executeBatchTransfer,
                icon: const Icon(Icons.upload),
                label: const Text('轉移到正式資料庫'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _activeSessionId = null;
                });
                _initLoad();
              },
              icon: const Icon(Icons.swap_horiz),
              label: const Text('切換批次'),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // 進度條（從後端 session stats 計算）
        if (_totalTasksInSession > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('完成進度 $_completedCount/$_totalTasksInSession',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('${(_totalTasksInSession > 0 ? (_completedCount / _totalTasksInSession * 100) : 0).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _totalTasksInSession > 0 ? _completedCount / _totalTasksInSession : 0,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade400),
                  ),
                ),
              ],
            ),
          ),
        
        // 專案資訊提示（如果未指定）
        _buildProjectInfoBanner(),
        
        // 統計卡片
        _buildStatsCard(),
        
        // 任務列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _pendingTrees.length,
            itemBuilder: (context, index) {
              return _buildTaskCard(_pendingTrees[index], index);
            },
          ),
        ),
        
        // Batch transfer 按鈕
        if (_completedCount > 0 && _activeSessionId != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: _isTransferring ? null : _executeBatchTransfer,
              icon: _isTransferring
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.upload),
              label: Text(_isTransferring ? '轉移中...' : '轉移已完成的測量到正式資料庫'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),
      ],
    );
  }
  
  Widget _buildSessionPicker() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('選擇測量批次', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal.shade700,
        )),
        const SizedBox(height: 4),
        Text('您有多個測量批次，請選擇要操作的批次', style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        ..._sessions.map((session) {
          final progress = session.totalTrees > 0
              ? session.completedTrees / session.totalTrees
              : 0.0;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() => _activeSessionId = session.sessionId);
                _loadTasks();
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.folder_open, color: Colors.teal.shade600),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          session.projectArea ?? session.sessionId,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        )),
                        Text('${session.completedTrees}/${session.totalTrees}',
                            style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (session.projectCode != null) ...[
                      const SizedBox(height: 4),
                      Text(session.projectCode!, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                    ],
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          session.isComplete ? Colors.green : Colors.teal.shade400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
  
  Widget _buildProjectInfoBanner() {
    if (_pendingTrees.isEmpty) return const SizedBox.shrink();
    final firstTree = _pendingTrees.first;
    final hasProject = firstTree.projectArea != null && firstTree.projectArea!.isNotEmpty;
    
    if (hasProject) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: InkWell(
        onTap: _showProjectSelectionSheet,
        child: Row(
          children: [
            Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '尚未指定專案區位 — 點此選擇',
                style: TextStyle(fontSize: 13, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.orange.shade600),
          ],
        ),
      ),
    );
  }
  
  void _showProjectSelectionSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16, right: 16, top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('指定專案區位', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal.shade700,
            )),
            const SizedBox(height: 8),
            const Text('將套用到此批次的所有樹木'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: '專案區位名稱',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.location_on),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  final name = controller.text.trim();
                  if (name.isEmpty || _activeSessionId == null) return;
                  Navigator.of(ctx).pop();
                  try {
                    await _service.updateSessionProject(
                      sessionId: _activeSessionId!,
                      projectArea: name,
                    );
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已設定專案區位: $name'), backgroundColor: Colors.green),
                      );
                    }
                    _loadTasks();
                  } catch (e) {
                    _showError('設定失敗: $e');
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                child: const Text('確定'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.teal.shade400, Colors.teal.shade600],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_pendingTrees.length} 棵樹待測量',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_pendingTrees.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '最近: HD ${_pendingTrees.first.horizontalDistance.toStringAsFixed(1)}m',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: _pendingTrees.isNotEmpty ? () => _startTask(_pendingTrees.first) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('開始'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTaskCard(PendingTreeMeasurement task, int index) {
    final hdDistance = task.horizontalDistance;
    final statusLabel = task.status == MeasurementStatus.inProgress ? ' ▶ 進行中' : '';
    
    final typeLabel = task.measurementType ?? '';

    Color typeBg = Colors.grey.shade100;
    Color typeFg = Colors.grey.shade700;
    Color typeBorder = Colors.grey.shade400;
    if (typeLabel == '1P') {
      typeBg = Colors.green.shade50;
      typeFg = Colors.green.shade700;
      typeBorder = Colors.green.shade300;
    } else if (typeLabel == 'DME') {
      typeBg = Colors.blue.shade50;
      typeFg = Colors.blue.shade700;
      typeBorder = Colors.blue.shade300;
    } else if (typeLabel == '3P') {
      typeBg = Colors.orange.shade50;
      typeFg = Colors.orange.shade700;
      typeBorder = Colors.orange.shade300;
    } else if (typeLabel == '3D') {
      typeBg = Colors.purple.shade50;
      typeFg = Colors.purple.shade700;
      typeBorder = Colors.purple.shade300;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: task.status == MeasurementStatus.inProgress 
          ? Colors.teal.shade50 
          : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getPriorityColor(task.priority ?? 3),
          foregroundColor: Colors.white,
          child: Text('${index + 1}'),
        ),
        title: Row(
          children: [
            Text('ID: ${task.originalRecordId ?? "未知"}'),
            const SizedBox(width: 8),
            if (typeLabel.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: typeBg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: typeBorder),
                ),
                child: Text(
                  typeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: typeFg,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.teal.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '樹高 ${task.treeHeight.toStringAsFixed(1)}m',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.teal.shade700,
                ),
              ),
            ),
            if (statusLabel.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(statusLabel, style: TextStyle(fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.speciesName != null)
              Text('樹種: ${task.speciesName}'),
            Text(
              'HD: ${hdDistance.toStringAsFixed(1)}m  AZ: ${task.azimuth.toStringAsFixed(0)}°',
              style: TextStyle(
                color: hdDistance < 50 ? Colors.green : Colors.orange,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.navigation, color: Colors.teal),
          onPressed: () => _startTask(task),
        ),
        onTap: () => _startTask(task),
      ),
    );
  }
  
  Color _getPriorityColor(int priority) {
    switch (priority) {
      case 1: return Colors.green;
      case 2: return Colors.lightGreen;
      case 3: return Colors.orange;
      case 4: return Colors.deepOrange;
      default: return Colors.red;
    }
  }
  
  /// 導航視圖 - 引導到測站位置
  Widget _buildNavigationView() {
    if (_currentTask == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final task = _currentTask!;
    final userPos = _userPosition;
    
    // GPS 距離僅供參考
    final gpsDistance = userPos != null
        ? task.distanceToStation(userPos.latitude, userPos.longitude)
        : null;
    
    // 方向：用儀器 AZ 作為目標方位，搭配手機 heading 計算相對轉向
    double? relativeAngle;
    if (_currentHeading != null) {
      relativeAngle = (task.azimuth - _currentHeading! + 360) % 360;
    }
    
    return Column(
      children: [
        // 儀器量測資訊卡
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.straighten, color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  Text('儀器量測資料', style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700,
                  )),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _infoChip('HD', '${task.horizontalDistance.toStringAsFixed(1)}m'),
                  _infoChip('AZ', '${task.azimuth.toStringAsFixed(0)}°'),
                  _infoChip('樹高', '${task.treeHeight.toStringAsFixed(1)}m'),
                  if (task.measurementType != null && task.measurementType!.isNotEmpty)
                    _infoChip('類型', task.measurementType!),
                ],
              ),
            ],
          ),
        ),
        
        // 主要距離顯示（儀器 HD）+ 方向
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${task.horizontalDistance.toStringAsFixed(1)}m',
                  style: const TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const Text(
                  '儀器量測距離 (HD)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                if (gpsDistance != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'GPS 參考距離: ${gpsDistance.toStringAsFixed(0)}m（室內誤差大）',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // 方向箭頭（用儀器 AZ + 手機 heading）
                if (relativeAngle != null) ...[
                  Transform.rotate(
                    angle: relativeAngle * math.pi / 180,
                    child: const Icon(
                      Icons.navigation,
                      size: 100,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_getDirectionText(relativeAngle)}  (AZ ${task.azimuth.toStringAsFixed(0)}°)',
                    style: const TextStyle(fontSize: 18),
                  ),
                ] else ...[
                  Icon(Icons.explore_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    '目標方位: AZ ${task.azimuth.toStringAsFixed(0)}°（等待羅盤...）',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // 底部按鈕
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _skipCurrentTask,
                  icon: const Icon(Icons.skip_next),
                  label: const Text('跳過'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _arrivedAtStation,
                  icon: const Icon(Icons.check),
                  label: const Text('已到達測站'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  String _getDirectionText(double angle) {
    if (angle < 22.5 || angle >= 337.5) return '直走';
    if (angle < 67.5) return '右前方';
    if (angle < 112.5) return '右轉';
    if (angle < 157.5) return '右後方';
    if (angle < 202.5) return '後轉';
    if (angle < 247.5) return '左後方';
    if (angle < 292.5) return '左轉';
    return '左前方';
  }
  
  Widget _infoChip(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(
          fontSize: 18, fontWeight: FontWeight.bold,
        )),
        Text(label, style: TextStyle(
          fontSize: 12, color: Colors.grey.shade600,
        )),
      ],
    );
  }
  
  /// 對準樹木視圖
  Widget _buildPointingView() {
    if (_currentTask == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final task = _currentTask!;
    final bearingToTree = task.bearingToTree();
    final heading = _currentHeading ?? 0;
    final relativeAngle = (bearingToTree - heading + 360) % 360;
    
    // 判斷是否對準 (±15度)
    final isAligned = relativeAngle < 15 || relativeAngle > 345;
    
    return Column(
      children: [
        // 樹木資訊卡
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.park, size: 48, color: Colors.green.shade700),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '目標樹木',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    Text('樹高: ${task.treeHeight.toStringAsFixed(1)} m'),
                    Text('距離: ${task.horizontalDistance.toStringAsFixed(1)} m'),
                    Text('方位: ${bearingToTree.toStringAsFixed(0)}°'),
                  ],
                ),
              ),
            ],
          ),
        ),
        
        // 指向箭頭
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isAligned ? '✓ 已對準' : '請轉向目標樹木',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isAligned ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 24),
                Transform.rotate(
                  angle: relativeAngle * math.pi / 180,
                  child: Icon(
                    Icons.arrow_upward,
                    size: 150,
                    color: isAligned ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '偏移: ${relativeAngle > 180 ? (360 - relativeAngle).toStringAsFixed(0) : relativeAngle.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // 底部按鈕
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: isAligned ? _startMeasurement : null,
            icon: const Icon(Icons.camera_alt),
            label: Text(isAligned ? '開始測量 DBH' : '請先對準樹木'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
            ),
          ),
        ),
      ],
    );
  }
  
  /// 測量中視圖 (簡化版，實際會跳轉到 AR 頁面)
  Widget _buildMeasuringView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('正在開啟測量工具...'),
        ],
      ),
    );
  }
  
  // === 事件處理 ===
  
  void _startTask(PendingTreeMeasurement task) async {
    setState(() {
      _currentTask = task;
      _navState = NavigationState.navigatingToStation;
    });
    
    // 標記為進行中（使用正確的狀態更新）
    if (task.id != null) {
      try {
        await _service.updateTaskStatus(task.id!, MeasurementStatus.inProgress);
      } catch (e) {
        debugPrint('[PendingTask] 設定 in_progress 失敗: $e');
      }
    }
  }
  
  void _arrivedAtStation() {
    setState(() {
      _navState = NavigationState.pointingToTree;
    });
  }
  
  void _startMeasurement() async {
    setState(() => _navState = NavigationState.measuring);
    
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => IntegratedTreeFormPage(
          task: _currentTask!,
        ),
      ),
    );
    
    if (success == true) {
      await _loadTasks(); // Progress counts refresh from backend
      
      if (_pendingTrees.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('完成 $_completedCount/$_totalTasksInSession — 自動跳轉下一棵'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        _startTask(_pendingTrees.first);
      } else {
        setState(() {
          _navState = NavigationState.selectingTask;
          _currentTask = null;
        });
        _showBatchTransferDialog();
      }
    } else {
      // User cancelled/backed out — revert status back to pending
      if (_currentTask?.id != null) {
        try {
          await _service.updateTaskStatus(
            _currentTask!.id!, MeasurementStatus.pending,
          );
        } catch (e) {
          debugPrint('[PendingTask] 恢復 pending 狀態失敗: $e');
        }
      }
      setState(() {
        _navState = NavigationState.selectingTask;
        _currentTask = null;
      });
      await _loadTasks();
    }
  }
  
  /// [Phase 3] 全部完成後顯示 batch transfer 對話框
  void _showBatchTransferDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('所有測量已完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade400),
            const SizedBox(height: 12),
            Text('已完成 $_completedCount 棵樹的測量。'),
            const SizedBox(height: 8),
            const Text('要立即將數據轉移到正式資料庫嗎？'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('稍後再說'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _executeBatchTransfer();
            },
            icon: const Icon(Icons.upload),
            label: const Text('立即轉移'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          ),
        ],
      ),
    );
  }
  
  Future<void> _executeBatchTransfer() async {
    // Use _activeSessionId, or infer from current task
    final sid = _activeSessionId
        ?? _currentTask?.sessionId
        ?? (_pendingTrees.isNotEmpty ? _pendingTrees.first.sessionId : null);
    
    if (sid == null) {
      _showError('缺少 session ID，無法轉移');
      return;
    }
    
    setState(() => _isTransferring = true);
    try {
      final result = await _service.transferToTreeSurvey(sessionId: sid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? '轉移成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await _loadTasks();
    } catch (e) {
      _showError('轉移失敗: $e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }
  
  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
  
  void _skipCurrentTask() async {
    if (_currentTask?.id != null) {
      try {
        await _service.skipMeasurement(_currentTask!.id!);
        await _loadTasks();
        
        if (_pendingTrees.isNotEmpty) {
          _startTask(_pendingTrees.first);
        } else {
          setState(() {
            _navState = NavigationState.selectingTask;
            _currentTask = null;
          });
        }
      } catch (e) {
        debugPrint('跳過失敗: $e');
      }
    }
  }
  
}

/// 導航狀態
enum NavigationState {
  selectingTask,       // 選擇任務
  navigatingToStation, // 導航到測站
  pointingToTree,      // 對準樹木
  measuring,           // 測量中
}
