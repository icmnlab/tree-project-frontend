import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/pending_tree_measurement.dart';
import '../services/pending_measurement_service.dart';
import '../services/v3/tree_image_service.dart';
import '../utils/location_helper.dart';
import 'v3/integrated_tree_form_page.dart';

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
  bool _isProcessing = false;
  bool _abandoned = false;
  
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
  double? _currentHeading;
  AccelerometerEvent? _lastAccelEvent;
  int _lastHeadingUpdateMs = 0;
  
  // 導航狀態
  NavigationState _navState = NavigationState.selectingTask;
  bool _hasVibratedArrival = false;
  
  // 羅盤平滑化
  double? _smoothedHeading;
  double? _magneticFieldStrength; // 磁力計強度，用於判斷是否需要校準
  bool _showCalibrationHint = false;
  
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
    // 確保離開頁面時不會遺留 in_progress 狀態的任務
    final taskId = _currentTask?.id;
    if (taskId != null && _navState != NavigationState.selectingTask) {
      _service.updateTaskStatus(taskId, MeasurementStatus.pending)
          .catchError((_) {});
    }
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
      // 使用較短超時+接受快取位置，避免 GPS 不可用時每次等待 5 秒凍結 UI
      final position = _userPosition ?? await getHighAccuracyPosition(
        timeout: const Duration(seconds: 3),
      );
      
      final results = await Future.wait([
        _service.getPendingTrees(
          sessionId: _activeSessionId,
          status: MeasurementStatus.pending,
          userLat: position?.latitude,
          userLon: position?.longitude,
          sortByDistance: position != null,
        ),
        _service.getPendingTrees(
          sessionId: _activeSessionId,
          status: MeasurementStatus.inProgress,
          userLat: position?.latitude,
          userLon: position?.longitude,
          sortByDistance: position != null,
        ),
        _service.getSessions(),
      ]);
      
      final pendingTrees = results[0] as List<PendingTreeMeasurement>;
      final inProgressTrees = results[1] as List<PendingTreeMeasurement>;
      final freshSessions = results[2] as List<MeasurementSession>;
      
      final allTrees = [...inProgressTrees, ...pendingTrees];
      _sessions = freshSessions;
      
      if (_activeSessionId != null) {
        final updated = _sessions.where((s) => s.sessionId == _activeSessionId).toList();
        if (updated.isNotEmpty) {
          _totalTasksInSession = updated.first.totalTrees;
          _completedCount = updated.first.completedTrees;
        }
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
  
  Future<void> _startLocationTracking() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final newPerm = await Geolocator.requestPermission();
        if (newPerm == LocationPermission.denied || newPerm == LocationPermission.deniedForever) {
          debugPrint('[GPS] Permission denied');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Permission permanently denied');
        return;
      }
      
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: buildLocationSettings(distanceFilter: 3),
      ).listen((position) {
        if (mounted) {
          setState(() {
            _userPosition = position;
            if (position.heading >= 0 && position.speed > 0.3) {
              _currentHeading = position.heading;
            }
          });
          // proximity check removed — user manually confirms arrival
        }
      });
      
      _accelerometerSubscription = accelerometerEventStream()?.listen((event) {
        _lastAccelEvent = event;
      });
      
      _magnetometerSubscription = magnetometerEventStream()?.listen((event) {
        if (!mounted) return;
        
        // 磁力計強度檢測（判斷羅盤是否需要校準）
        final magnitude = math.sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
        _magneticFieldStrength = magnitude;
        // 地球磁場約 25–65 µT，<15 µT 或 >100 µT 表示可能未校準或受干擾
        final needsCal = magnitude < 15 || magnitude > 100;
        if (needsCal != _showCalibrationHint) {
          setState(() => _showCalibrationHint = needsCal);
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastHeadingUpdateMs < 100) return;
        _lastHeadingUpdateMs = now;
        
        double heading;
        final accel = _lastAccelEvent;
        
        if (accel != null) {
          final ax = accel.x, ay = accel.y, az = accel.z;
          final norm = math.sqrt(ax * ax + ay * ay + az * az);
          if (norm > 0.1) {
            final pitch = math.asin(-ax / norm);
            final roll = math.asin(ay / norm);
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
        
        if (_userPosition == null || _userPosition!.speed <= 0.3) {
          // 低通濾波平滑化羅盤方向，避免箭頭劇烈抖動
          if (_smoothedHeading == null) {
            _smoothedHeading = heading;
          } else {
            // 處理 0°↔360° 跨界
            double diff = heading - _smoothedHeading!;
            if (diff > 180) diff -= 360;
            if (diff < -180) diff += 360;
            _smoothedHeading = (_smoothedHeading! + diff * 0.15) % 360;
          }
          setState(() {
            _currentHeading = _smoothedHeading;
          });
        }
      });
      
    } catch (e) {
      debugPrint('[GPS] 位置追蹤失敗: $e');
    }
  }
  
  // GPS 接近時不自動推進 — 由使用者手動確認「已到達」

  Future<void> _abandonCurrentTask() async {
    _abandoned = true;
    final taskId = _currentTask?.id;
    // 先重置 UI 狀態，再做網路請求，避免使用者重複觸發
    if (!mounted) return;
    setState(() {
      _navState = NavigationState.selectingTask;
      _currentTask = null;
      _isProcessing = false;
    });
    // 背景恢復 pending 狀態
    if (taskId != null) {
      try {
        await _service.updateTaskStatus(taskId, MeasurementStatus.pending);
      } catch (e) {
        debugPrint('[PendingTask] 恢復 pending 狀態失敗: $e');
      }
    }
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
                  () {
                    final withDia = _pendingTrees.where((t) => t.hasInstrumentDbh).length;
                    final needDbh = _pendingTrees.where((t) => t.needsDbhMeasurement).length;
                    if (withDia > 0) {
                      return Text(
                        '$withDia 棵已有 Remote Dia ・ $needDbh 棵需補測',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      );
                    }
                    return Text(
                      '最近: HD ${_pendingTrees.first.horizontalDistance.toStringAsFixed(1)}m',
                      style: const TextStyle(color: Colors.white70),
                    );
                  }(),
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
            if (task.hasInstrumentDbh)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  'Remote Dia: ${task.instrumentDbhCm!.toStringAsFixed(1)} cm',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            else if (task.needsDbhMeasurement)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Text(
                  '需補測 DBH',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.amber.shade800,
                    fontWeight: FontWeight.w600,
                  ),
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
  
  Widget _buildNavigationView() {
    if (_currentTask == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final task = _currentTask!;
    final userPos = _userPosition;
    
    final gpsDistance = userPos != null
        ? task.distanceToStation(userPos.latitude, userPos.longitude)
        : null;
    
    // Bearing from user to station
    double? bearingToStation;
    double? relativeAngle;
    if (userPos != null && task.stationLatitude != 0 && task.stationLongitude != 0) {
      bearingToStation = Geolocator.bearingBetween(
        userPos.latitude, userPos.longitude,
        task.stationLatitude, task.stationLongitude,
      );
      if (_currentHeading != null) {
        relativeAngle = (bearingToStation - _currentHeading! + 360) % 360;
      }
    }
    
    // 港口附近 GPS 精度約 5-10m，設 10m 進精確模式，5m 顯示到達
    final isClose = gpsDistance != null && gpsDistance < 10;
    final hasArrived = gpsDistance != null && gpsDistance < 5;
    
    if (hasArrived && !_hasVibratedArrival) {
      _hasVibratedArrival = true;
      HapticFeedback.heavyImpact();
    }
    
    return Column(
      children: [
        // 羅盤校準警告
        if (_showCalibrationHint)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 20, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '羅盤可能需要校準 — 請拿起手機畫 8 字形',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        
        // Info card
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _infoChip('HD', '${task.horizontalDistance.toStringAsFixed(1)}m'),
              _infoChip('AZ', '${task.azimuth.toStringAsFixed(0)}°'),
              _infoChip('樹高', '${task.treeHeight.toStringAsFixed(1)}m'),
              if (task.measurementType != null && task.measurementType!.isNotEmpty)
                _infoChip('類型', task.measurementType!),
            ],
          ),
        ),

        // GPS 精度指示器
        if (userPos != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  userPos.accuracy < 10 ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 14,
                  color: userPos.accuracy < 10 
                      ? Colors.green.shade600 
                      : userPos.accuracy < 20 
                          ? Colors.orange.shade600 
                          : Colors.red.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  'GPS 精度 ±${userPos.accuracy.toStringAsFixed(0)}m',
                  style: TextStyle(
                    fontSize: 11,
                    color: userPos.accuracy < 10 
                        ? Colors.green.shade700 
                        : userPos.accuracy < 20 
                            ? Colors.orange.shade700 
                            : Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        
        Expanded(
          child: Center(
            child: isClose
                ? _buildPreciseStakeoutView(gpsDistance, relativeAngle, hasArrived)
                : _buildDistanceArrowView(gpsDistance, relativeAngle, bearingToStation, task),
          ),
        ),
        
        // Arrival banner
        if (hasArrived)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: Colors.green.shade400,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('已到達測站!', style: TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold,
                )),
              ],
            ),
          ),
        
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
                  icon: Icon(hasArrived ? Icons.arrow_forward : Icons.check),
                  label: Text(hasArrived ? '確認，開始找樹' : '已到達測站'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: hasArrived ? Colors.green : Colors.teal,
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

  Widget _buildDistanceArrowView(double? gpsDistance, double? relativeAngle, double? bearing, PendingTreeMeasurement task) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // GPS distance
        if (gpsDistance != null) ...[
          Text(
            '${gpsDistance.toStringAsFixed(0)}m',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.bold,
              color: gpsDistance < 10 ? Colors.orange : Colors.teal,
            ),
          ),
          Text('GPS 距測站', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
        ] else ...[
          Icon(Icons.gps_off, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('等待 GPS 定位...', style: TextStyle(color: Colors.grey.shade600)),
        ],
        
        const SizedBox(height: 24),
        
        if (relativeAngle != null) ...[
          Transform.rotate(
            angle: relativeAngle * math.pi / 180,
            child: Icon(
              Icons.navigation,
              size: 100,
              color: Colors.teal.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getDirectionText(relativeAngle),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          Text(
            '方位 ${bearing?.toStringAsFixed(0) ?? "--"}°',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
        ] else ...[
          Icon(Icons.explore_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('等待羅盤...', style: TextStyle(color: Colors.grey.shade600)),
        ],
      ],
    );
  }

  Widget _buildPreciseStakeoutView(double distance, double? relativeAngle, bool arrived) {
    final radarSize = 200.0;
    final centerX = radarSize / 2;
    final centerY = radarSize / 2;
    
    double dotX = centerX;
    double dotY = centerY;
    if (relativeAngle != null && distance > 0) {
      final maxPixelDist = radarSize / 2 - 16;
      final pixelDist = math.min(distance / 5.0 * maxPixelDist, maxPixelDist);
      final rad = (relativeAngle - 90) * math.pi / 180;
      dotX = centerX + pixelDist * math.cos(rad);
      dotY = centerY + pixelDist * math.sin(rad);
    }
    
    final bgColor = arrived ? Colors.green.shade50 : Colors.orange.shade50;
    final ringColor = arrived ? Colors.green : Colors.orange;
    final dotColor = arrived ? Colors.green.shade700 : Colors.blue;
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          arrived ? '到達!' : '接近中...',
          style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.bold,
            color: arrived ? Colors.green.shade700 : Colors.orange.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${distance.toStringAsFixed(1)}m',
          style: TextStyle(
            fontSize: 48, fontWeight: FontWeight.bold,
            color: arrived ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(height: 16),
        
        // Radar circle
        SizedBox(
          width: radarSize,
          height: radarSize,
          child: CustomPaint(
            painter: _StakeoutRadarPainter(
              bgColor: bgColor,
              ringColor: ringColor,
              dotColor: dotColor,
              dotX: dotX,
              dotY: dotY,
              centerX: centerX,
              centerY: centerY,
            ),
          ),
        ),
        
        const SizedBox(height: 8),
        Text('十字=測站, 藍點=你的位置', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
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
  
  Widget _buildPointingView() {
    if (_currentTask == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final task = _currentTask!;
    final targetAz = task.azimuth;
    final heading = _currentHeading ?? 0;
    final relativeAngle = (targetAz - heading + 360) % 360;
    final offsetDeg = relativeAngle > 180 ? 360 - relativeAngle : relativeAngle;
    final isAligned = offsetDeg < 20;
    
    return Column(
      children: [
        // 羅盤校準警告（在此頁面特別重要，因為要靠羅盤找方向）
        if (_showCalibrationHint)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade400),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber, size: 20, color: Colors.amber.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '羅盤精度不足 — 請遠離金屬物品，拿起手機畫 8 字形校準',
                    style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        
        // Tree info + instruction
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.park, size: 36, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('找到目標樹木', style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16,
                          color: Colors.green.shade700,
                        )),
                        Text('樹在 AZ ${targetAz.toStringAsFixed(0)}° 方向，距離約 ${task.horizontalDistance.toStringAsFixed(1)}m'),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _infoChip('水平距離', '${task.horizontalDistance.toStringAsFixed(1)}m'),
                  _infoChip('方位角', '${targetAz.toStringAsFixed(0)}°'),
                  _infoChip('樹高', '${task.treeHeight.toStringAsFixed(1)}m'),
                ],
              ),
            ],
          ),
        ),
        
        // Direction arrow + alignment feedback
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isAligned ? '已對準目標方向!' : '轉向 AZ ${targetAz.toStringAsFixed(0)}° 方向',
                  style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold,
                    color: isAligned ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '偏移 ${offsetDeg.toStringAsFixed(0)}°  ${relativeAngle <= 180 ? "→ 右轉" : "← 左轉"}',
                  style: TextStyle(
                    fontSize: 14,
                    color: isAligned ? Colors.green.shade600 : Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 20),
                
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: EdgeInsets.all(isAligned ? 20 : 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAligned
                        ? Colors.green.withValues(alpha:0.1)
                        : Colors.transparent,
                  ),
                  child: Transform.rotate(
                    angle: relativeAngle * math.pi / 180,
                    child: Icon(
                      Icons.navigation,
                      size: 120,
                      color: isAligned ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                if (!isAligned)
                  Text(
                    '面向此方向後即可拍照測量',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _startMeasurement,
            icon: const Icon(Icons.camera_alt),
            label: const Text('開始拍照測量 DBH'),
            style: ElevatedButton.styleFrom(
              backgroundColor: isAligned ? Colors.green : Colors.teal,
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
  
  Future<void> _startTask(PendingTreeMeasurement task) async {
    if (_isProcessing) return;
    _isProcessing = true;
    _abandoned = false;
    _hasVibratedArrival = false;
    
    // 無 GPS 座標（stationLat/Lon 為 0）→ 跳過導航，直接進入測量
    final bool hasStationGps = task.stationLatitude != 0 || task.stationLongitude != 0;
    
    setState(() {
      _currentTask = task;
      _navState = hasStationGps
          ? NavigationState.navigatingToStation
          : NavigationState.pointingToTree;  // 跳過導航，直接對準樹木方向
    });
    
    if (!hasStationGps && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('此紀錄無 GPS 座標，跳過導航。請依方位角找到目標樹木。'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
    
    if (task.id != null) {
      try {
        await _service.updateTaskStatus(task.id!, MeasurementStatus.inProgress);
      } catch (e) {
        debugPrint('[PendingTask] 設定 in_progress 失敗: $e');
      }
    }
    if (mounted) _isProcessing = false;
  }
  
  void _arrivedAtStation() {
    setState(() {
      _navState = NavigationState.pointingToTree;
    });
  }
  
  Future<void> _startMeasurement() async {
    if (_isProcessing || _currentTask == null) return;
    _isProcessing = true;
    
    setState(() => _navState = NavigationState.measuring);
    
    final taskRef = _currentTask!;
    
    bool? success;
    try {
      success = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => IntegratedTreeFormPage(
            task: taskRef,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[PendingTask] IntegratedTreeFormPage 異常: $e');
    }
    
    _isProcessing = false;
    if (!mounted || _abandoned) {
      // 頁面已被銷毀或放棄 — 確保任務不會永遠卡在 in_progress
      if (taskRef.id != null && success != true) {
        _service.updateTaskStatus(taskRef.id!, MeasurementStatus.pending)
            .catchError((_) {});
      }
      return;
    }
    
    if (success == true) {
      await _loadTasks();
      if (!mounted) return;
      
      if (_pendingTrees.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('完成 $_completedCount/$_totalTasksInSession — 自動跳轉下一棵'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        _startTask(_pendingTrees.first);
      } else {
        setState(() {
          _navState = NavigationState.selectingTask;
          _currentTask = null;
        });
        _showBatchTransferDialog();
      }
    } else {
      // 使用者取消或測量失敗 — 恢復 pending
      if (taskRef.id != null) {
        try {
          await _service.updateTaskStatus(
            taskRef.id!, MeasurementStatus.pending,
          );
        } catch (e) {
          debugPrint('[PendingTask] 恢復 pending 狀態失敗: $e');
        }
      }
      if (!mounted) return;
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
    if (_isTransferring) return;
    
    final sid = _activeSessionId
        ?? _currentTask?.sessionId
        ?? (_pendingTrees.isNotEmpty ? _pendingTrees.first.sessionId : null);
    
    if (sid == null) {
      _showError('缺少 session ID，無法轉移');
      return;
    }
    
    setState(() => _isTransferring = true);
    try {
      // 轉移前先同步未上傳的照片到後端
      final imageService = TreeImageService();
      final syncResult = await imageService.syncAllPendingImages();
      if (((syncResult['failed'] as num?)?.toInt() ?? 0) > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('照片同步: ${syncResult['success']} 成功, ${syncResult['failed']} 失敗 (將後續重試)'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (((syncResult['success'] as num?)?.toInt() ?? 0) > 0 && mounted) {
        debugPrint('[Transfer] 照片同步完成: ${syncResult['success']} 張');
      }

      final result = await _service.transferToTreeSurvey(sessionId: sid);

      // 轉移成功後，重新映射本地照片索引 (pending_id → tree_survey_id)
      try {
        final idMapping = result['id_mapping'] as List<dynamic>?;
        if (idMapping != null) {
          for (final m in idMapping) {
            if (m is! Map) continue; // 安全檢查：跳過非 Map 項目
            final pendingId = m['pending_id']?.toString();
            final surveyId = m['tree_survey_id']?.toString();
            if (pendingId != null && surveyId != null) {
              await imageService.remapTreeId(pendingId, surveyId);
            }
          }
          // 清理已同步的本地檔案，釋放裝置空間
          await imageService.cleanupSyncedImages();
        }
      } catch (mapErr) {
        debugPrint('[Transfer] 照片重新映射失敗（不影響資料轉移）: $mapErr');
      }

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
  
  Future<void> _skipCurrentTask() async {
    if (_isProcessing || _currentTask?.id == null) return;
    _isProcessing = true;
    
    try {
      await _service.skipMeasurement(_currentTask!.id!);
      if (!mounted) return;
      await _loadTasks();
      if (!mounted) return;
      
      if (_pendingTrees.isNotEmpty) {
        _isProcessing = false;
        _startTask(_pendingTrees.first);
      } else {
        setState(() {
          _navState = NavigationState.selectingTask;
          _currentTask = null;
        });
        _isProcessing = false;
      }
    } catch (e) {
      debugPrint('跳過失敗: $e');
      _isProcessing = false;
      if (mounted) {
        _showError('跳過失敗: $e');
      }
    }
  }
  
}

/// 導航狀態
enum NavigationState {
  selectingTask,
  navigatingToStation,
  pointingToTree,
  measuring,
}

class _StakeoutRadarPainter extends CustomPainter {
  final Color bgColor;
  final Color ringColor;
  final Color dotColor;
  final double dotX;
  final double dotY;
  final double centerX;
  final double centerY;

  _StakeoutRadarPainter({
    required this.bgColor,
    required this.ringColor,
    required this.dotColor,
    required this.dotX,
    required this.dotY,
    required this.centerX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = bgColor..style = PaintingStyle.fill;
    final ringPaint = Paint()
      ..color = ringColor.withValues(alpha:0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final crossPaint = Paint()
      ..color = ringColor.withValues(alpha:0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final dotPaint = Paint()..color = dotColor..style = PaintingStyle.fill;

    final r = size.width / 2;
    final center = Offset(centerX, centerY);

    canvas.drawCircle(center, r, bgPaint);
    canvas.drawCircle(center, r * 0.33, ringPaint);
    canvas.drawCircle(center, r * 0.66, ringPaint);
    canvas.drawCircle(center, r, ringPaint);

    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), crossPaint);
    canvas.drawLine(Offset(centerX, 0), Offset(centerX, size.height), crossPaint);

    canvas.drawCircle(Offset(dotX, dotY), 10, dotPaint);
    canvas.drawCircle(Offset(dotX, dotY), 10, Paint()
      ..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _StakeoutRadarPainter old) {
    return old.dotX != dotX || old.dotY != dotY || old.bgColor != bgColor;
  }
}
