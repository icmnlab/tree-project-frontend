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
    _arrowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _loadTasks();
    _startLocationTracking();
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
      // 獲取用戶位置
      final position = await Geolocator.getCurrentPosition();
      
      final trees = await _service.getPendingTrees(
        sessionId: widget.sessionId,
        status: MeasurementStatus.pending,
        userLat: position.latitude,
        userLon: position.longitude,
        sortByDistance: true,
      );
      
      if (!mounted) return;
      setState(() {
        _pendingTrees = trees;
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
          distanceFilter: 1, // 每移動 1m 更新
        ),
      ).listen((position) {
        if (mounted) {
          setState(() {
            _userPosition = position;
            // Position.heading 是移動方向（0-360 度），速度夠快時才準確
            if (position.heading >= 0 && position.speed > 0.3) {
              _currentHeading = position.heading;
            }
          });
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (_navState != NavigationState.selectingTask)
            IconButton(
              icon: const Icon(Icons.list),
              tooltip: '返回列表',
              onPressed: () => setState(() {
                _navState = NavigationState.selectingTask;
                _currentTask = null;
              }),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: _buildBody(),
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
    if (_pendingTrees.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, size: 80, color: Colors.green.shade300),
            const SizedBox(height: 16),
            const Text(
              '太棒了！所有任務已完成',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              '目前沒有待測量的樹木',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
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
      ],
    );
  }
  
  Widget _buildStatsCard() {
    final userPos = _userPosition;
    
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
                if (userPos != null && _pendingTrees.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '最近的樹距離: ${_pendingTrees.first.distanceToStation(userPos.latitude, userPos.longitude).toStringAsFixed(0)}m',
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
    final userPos = _userPosition;
    final distance = userPos != null 
        ? task.distanceToStation(userPos.latitude, userPos.longitude)
        : null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
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
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task.speciesName != null)
              Text('樹種: ${task.speciesName}'),
            if (distance != null)
              Text(
                '距離: ${distance.toStringAsFixed(0)}m',
                style: TextStyle(
                  color: distance < 50 ? Colors.green : Colors.orange,
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
    if (_currentTask == null || _userPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    final task = _currentTask!;
    final userPos = _userPosition!;
    final distance = task.distanceToStation(userPos.latitude, userPos.longitude);
    
    // 計算方位
    final bearing = _calculateBearing(
      userPos.latitude, userPos.longitude,
      task.stationLatitude, task.stationLongitude,
    );
    
    // 相對於用戶朝向的角度
    final heading = _currentHeading ?? 0;
    final relativeAngle = (bearing - heading + 360) % 360;
    
    return Column(
      children: [
        // 距離和方向顯示
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 大距離數字
                Text(
                  distance < 1000 
                      ? '${distance.toStringAsFixed(0)}m'
                      : '${(distance / 1000).toStringAsFixed(1)}km',
                  style: TextStyle(
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    color: distance < 10 ? Colors.green : Colors.teal,
                  ),
                ),
                const Text('到測站距離', style: TextStyle(color: Colors.grey)),
                
                const SizedBox(height: 32),
                
                // 方向箭頭
                Transform.rotate(
                  angle: relativeAngle * math.pi / 180,
                  child: Icon(
                    Icons.navigation,
                    size: 120,
                    color: Colors.teal,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  _getDirectionText(relativeAngle),
                  style: const TextStyle(fontSize: 18),
                ),
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
                  onPressed: distance < 10 ? _arrivedAtStation : null,
                  icon: const Icon(Icons.check),
                  label: Text(distance < 10 ? '已到達測站' : '請繼續前進'),
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
  
  /// 對準樹木視圖
  Widget _buildPointingView() {
    if (_currentTask == null || _userPosition == null) {
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
    
    // 標記為進行中（讓其他用戶看到此樹正在被處理）
    if (task.id != null) {
      try {
        await _service.updateMeasurement(task.id!, {'status': 'in_progress'});
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
    
    // 跳轉到 V3 整合式表單頁面
    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => IntegratedTreeFormPage(
          task: _currentTask!,
        ),
      ),
    );
    
    if (success == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('測量已完成並提交'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      // 載入下一個任務
      await _loadTasks();
      
      if (_pendingTrees.isNotEmpty) {
        _startTask(_pendingTrees.first);
      } else {
        setState(() {
          _navState = NavigationState.selectingTask;
          _currentTask = null;
        });
      }
    } else {
      // 用戶取消或返回
      setState(() => _navState = NavigationState.pointingToTree);
    }
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
  
  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    double dLon = (lon2 - lon1) * math.pi / 180;
    double lat1Rad = lat1 * math.pi / 180;
    double lat2Rad = lat2 * math.pi / 180;
    
    double x = math.sin(dLon) * math.cos(lat2Rad);
    double y = math.cos(lat1Rad) * math.sin(lat2Rad) -
        math.sin(lat1Rad) * math.cos(lat2Rad) * math.cos(dLon);
    
    double bearing = math.atan2(x, y);
    return (bearing * 180 / math.pi + 360) % 360;
  }
}

/// 導航狀態
enum NavigationState {
  selectingTask,       // 選擇任務
  navigatingToStation, // 導航到測站
  pointingToTree,      // 對準樹木
  measuring,           // 測量中
}
