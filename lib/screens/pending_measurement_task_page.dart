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
  
  // [Phase 3] 連續測量進度
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
      // 獲取用戶位置（可選，不阻塞任務載入）
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[PendingTask] GPS 定位失敗（不影響任務列表）: $e');
        // GPS 失敗不影響任務載入
      }
      
      // 載入待測量任務（同時包含 pending 和 in_progress）
      final pendingTrees = await _service.getPendingTrees(
        sessionId: widget.sessionId,
        status: MeasurementStatus.pending,
        userLat: position?.latitude,
        userLon: position?.longitude,
        sortByDistance: position != null,
      );
      
      final inProgressTrees = await _service.getPendingTrees(
        sessionId: widget.sessionId,
        status: MeasurementStatus.inProgress,
        userLat: position?.latitude,
        userLon: position?.longitude,
        sortByDistance: position != null,
      );
      
      // 合併：in_progress 排在前面
      final allTrees = [...inProgressTrees, ...pendingTrees];
      
      if (!mounted) return;
      setState(() {
        _pendingTrees = allTrees;
        _userPosition = position;
        _isLoading = false;
        // [Phase 3] 第一次載入時記錄總數
        if (_totalTasksInSession == 0 && allTrees.isNotEmpty) {
          _totalTasksInSession = allTrees.length;
        }
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
  
  /// [Phase 3] 當 GPS 接近目標樹木時，自動推進導航狀態
  void _checkProximityAutoAdvance(Position position) {
    if (_currentTask == null) return;
    
    final task = _currentTask!;
    
    // 計算到樹木的距離
    final distToTree = Geolocator.distanceBetween(
      position.latitude, position.longitude,
      task.treeLatitude, task.treeLongitude,
    );
    
    // 導航到測站時：到達 5m 內自動切換到「對準樹木」
    if (_navState == NavigationState.navigatingToStation && distToTree < 8) {
      _arrivedAtStation();
    }
    
    // 對準樹木時：到達 5m 內自動觸發測量
    if (_navState == NavigationState.pointingToTree && distToTree < 5) {
      _startMeasurement();
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
        // [Phase 3] 進度條
        if (_completedCount > 0 && _totalTasksInSession > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('完成進度 $_completedCount/$_totalTasksInSession',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text('${(_completedCount / _totalTasksInSession * 100).toStringAsFixed(0)}%',
                        style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _completedCount / _totalTasksInSession,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade400),
                  ),
                ),
              ],
            ),
          ),
        
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
        
        // [Phase 3] Batch transfer 按鈕（有已完成的任務時顯示）
        if (_completedCount > 0 && widget.sessionId != null)
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
    final hasGps = task.hasGpsPosition;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: task.status == MeasurementStatus.inProgress 
          ? Colors.teal.shade50 
          : (!hasGps ? Colors.orange.shade50 : null),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getPriorityColor(task.priority ?? 3),
          foregroundColor: Colors.white,
          child: Text('${index + 1}'),
        ),
        title: Row(
          children: [
            Text('ID: ${task.originalRecordId ?? "未知"}'),
            const SizedBox(width: 6),
            // 測量類型標籤
            _buildTypeBadge(task.measurementType),
            const SizedBox(width: 4),
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
            if (!hasGps) ...[
              const SizedBox(width: 4),
              Icon(Icons.gps_off, size: 14, color: Colors.orange.shade700),
            ],
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
              'HD: ${hdDistance.toStringAsFixed(1)}m  AZ: ${task.azimuth.toStringAsFixed(0)}°${!hasGps ? '  (無GPS)' : ''}',
              style: TextStyle(
                color: !hasGps ? Colors.orange.shade700 : (hdDistance < 50 ? Colors.green : Colors.orange),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            hasGps ? Icons.navigation : Icons.play_arrow,
            color: hasGps ? Colors.teal : Colors.orange,
          ),
          onPressed: () => _startTask(task),
        ),
        onTap: () => _startTask(task),
      ),
    );
  }
  
  /// 測量類型標籤 Widget
  Widget _buildTypeBadge(String? type) {
    Color bgColor;
    String label;
    switch (type?.toUpperCase()) {
      case '1P':
        bgColor = Colors.green.shade100;
        label = '1P';
        break;
      case '3P':
        bgColor = Colors.green.shade200;
        label = '3P';
        break;
      case '3D':
        bgColor = Colors.purple.shade100;
        label = '3D';
        break;
      case 'DME':
        bgColor = Colors.blue.shade100;
        label = 'DME';
        break;
      default:
        bgColor = Colors.grey.shade200;
        label = type ?? '?';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
    
    // GPS 距離（僅供參考，室內不準）
    final gpsDistance = userPos != null
        ? task.distanceToStation(userPos.latitude, userPos.longitude)
        : null;
    
    // 優先使用 GPS 導航（如果有位置）
    double? relativeAngle;
    if (userPos != null && _currentHeading != null) {
      final bearing = _calculateBearing(
        userPos.latitude, userPos.longitude,
        task.stationLatitude, task.stationLongitude,
      );
      relativeAngle = (bearing - _currentHeading! + 360) % 360;
    }
    
    // 判斷是否已接近測站（GPS 距離可信時）
    final isNearStation = gpsDistance != null && gpsDistance < 10;
    
    return Column(
      children: [
        // 測量資訊卡
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
                  if (task.measurementType != null)
                    _infoChip('類型', task.measurementType!),
                ],
              ),
            ],
          ),
        ),
        
        // 距離和方向顯示
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (gpsDistance != null) ...[
                  // GPS 距離（到測站）
                  Text(
                    gpsDistance < 1000 
                        ? '${gpsDistance.toStringAsFixed(0)}m'
                        : '${(gpsDistance / 1000).toStringAsFixed(1)}km',
                    style: TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: isNearStation ? Colors.green : Colors.teal,
                    ),
                  ),
                  Text(
                    '到測站 GPS 距離（室內誤差較大）',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ] else ...[
                  Icon(Icons.gps_off, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('GPS 定位中...', style: TextStyle(color: Colors.grey.shade600)),
                ],
                
                const SizedBox(height: 24),
                
                // 方向箭頭
                if (relativeAngle != null) ...[
                  Transform.rotate(
                    angle: relativeAngle * math.pi / 180,
                    child: Icon(
                      Icons.navigation,
                      size: 100,
                      color: Colors.teal,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getDirectionText(relativeAngle),
                    style: const TextStyle(fontSize: 18),
                  ),
                ] else ...[
                  Icon(Icons.explore_off, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('等待方向感應器...', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ],
            ),
          ),
        ),
        
        // 底部按鈕（不阻塞：隨時允許手動確認已到達）
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
    // 無GPS記錄直接跳到測量階段，不需要導航
    if (!task.hasGpsPosition) {
      setState(() {
        _currentTask = task;
        _navState = NavigationState.measuring;
      });
      if (task.id != null) {
        try {
          await _service.updateTaskStatus(task.id!, MeasurementStatus.inProgress);
        } catch (e) {
          debugPrint('[PendingTask] 設定 in_progress 失敗: $e');
        }
      }
      // 直接開始測量
      _startMeasurement();
      return;
    }
    
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
      // [Phase 3] 更新進度
      setState(() => _completedCount++);
      
      await _loadTasks();
      
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
        // 自動跳到下一棵最近的樹
        _startTask(_pendingTrees.first);
      } else {
        // [Phase 3] 全部完成，提示 batch transfer
        setState(() {
          _navState = NavigationState.selectingTask;
          _currentTask = null;
        });
        _showBatchTransferDialog();
      }
    } else {
      setState(() => _navState = NavigationState.pointingToTree);
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
  
  /// [Phase 3] 執行 batch transfer
  Future<void> _executeBatchTransfer() async {
    if (widget.sessionId == null) {
      _showError('缺少 session ID');
      return;
    }
    
    setState(() => _isTransferring = true);
    try {
      final result = await _service.transferToTreeSurvey(sessionId: widget.sessionId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? '轉移成功'),
            backgroundColor: Colors.green,
          ),
        );
      }
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
