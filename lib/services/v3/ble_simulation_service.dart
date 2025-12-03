// ============================================================================
// V3 BLE 數據模擬測試服務 (BLE Simulation Service)
// ============================================================================
// 採用「兼容式開發」原則：
// - 獨立的 V3 服務，不修改現有 BLE 功能
// - 提供模擬 BLE 設備數據供開發測試
// - 支援多種測量儀器的模擬
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// BLE 設備類型
enum BLEDeviceType {
  /// 雷射測距儀
  laserRangefinder,
  
  /// 電子捲尺
  digitalTapeMeasure,
  
  /// 樹徑尺（電子）
  digitalCaliper,
  
  /// 高度計
  altimeter,
  
  /// 測高儀
  hypsometer,
  
  /// 通用感測器
  genericSensor,
}

/// 模擬 BLE 設備
class SimulatedBLEDevice {
  final String id;
  final String name;
  final BLEDeviceType type;
  final String manufacturer;
  final bool isConnected;
  final int batteryLevel;
  final Map<String, dynamic> capabilities;
  
  SimulatedBLEDevice({
    required this.id,
    required this.name,
    required this.type,
    this.manufacturer = 'Simulated',
    this.isConnected = false,
    this.batteryLevel = 100,
    Map<String, dynamic>? capabilities,
  }) : capabilities = capabilities ?? {};
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'manufacturer': manufacturer,
    'isConnected': isConnected,
    'batteryLevel': batteryLevel,
    'capabilities': capabilities,
  };
  
  SimulatedBLEDevice copyWith({
    bool? isConnected,
    int? batteryLevel,
  }) => SimulatedBLEDevice(
    id: id,
    name: name,
    type: type,
    manufacturer: manufacturer,
    isConnected: isConnected ?? this.isConnected,
    batteryLevel: batteryLevel ?? this.batteryLevel,
    capabilities: capabilities,
  );
}

/// BLE 測量數據
class BLEMeasurementData {
  final String deviceId;
  final BLEDeviceType deviceType;
  final double value;
  final String unit;
  final DateTime timestamp;
  final double? accuracy;
  final Map<String, dynamic> rawData;
  
  BLEMeasurementData({
    required this.deviceId,
    required this.deviceType,
    required this.value,
    required this.unit,
    DateTime? timestamp,
    this.accuracy,
    Map<String, dynamic>? rawData,
  }) : 
    timestamp = timestamp ?? DateTime.now(),
    rawData = rawData ?? {};
  
  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceType': deviceType.name,
    'value': value,
    'unit': unit,
    'timestamp': timestamp.toIso8601String(),
    'accuracy': accuracy,
    'rawData': rawData,
  };
}

/// 模擬情境
class SimulationScenario {
  final String id;
  final String name;
  final String description;
  final List<BLEMeasurementData> measurements;
  final Duration duration;
  
  SimulationScenario({
    required this.id,
    required this.name,
    required this.description,
    required this.measurements,
    this.duration = const Duration(seconds: 30),
  });
}

/// V3 BLE 模擬服務 - 單例模式
class BLESimulationService {
  static final BLESimulationService _instance = BLESimulationService._internal();
  factory BLESimulationService() => _instance;
  BLESimulationService._internal();
  
  // 狀態
  bool _isSimulationMode = false;
  final List<SimulatedBLEDevice> _simulatedDevices = [];
  SimulatedBLEDevice? _connectedDevice;
  Timer? _measurementTimer;
  final _random = math.Random();
  
  // 事件流
  final _deviceDiscoveryController = StreamController<SimulatedBLEDevice>.broadcast();
  Stream<SimulatedBLEDevice> get deviceDiscoveryStream => _deviceDiscoveryController.stream;
  
  final _measurementController = StreamController<BLEMeasurementData>.broadcast();
  Stream<BLEMeasurementData> get measurementStream => _measurementController.stream;
  
  final _connectionStateController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  
  /// 是否處於模擬模式
  bool get isSimulationMode => _isSimulationMode;
  
  /// 取得已連接的設備
  SimulatedBLEDevice? get connectedDevice => _connectedDevice;
  
  /// 取得可用的模擬設備
  List<SimulatedBLEDevice> get availableDevices => List.unmodifiable(_simulatedDevices);
  
  /// 預定義的模擬設備
  static List<SimulatedBLEDevice> get predefinedDevices => [
    SimulatedBLEDevice(
      id: 'sim_laser_01',
      name: 'Simulated Laser Rangefinder',
      type: BLEDeviceType.laserRangefinder,
      manufacturer: 'SimuTech',
      batteryLevel: 85,
      capabilities: {
        'maxRange': 100.0, // meters
        'accuracy': 0.01, // meters
        'autoMeasure': true,
      },
    ),
    SimulatedBLEDevice(
      id: 'sim_tape_01',
      name: 'Simulated Digital Tape',
      type: BLEDeviceType.digitalTapeMeasure,
      manufacturer: 'SimuTech',
      batteryLevel: 72,
      capabilities: {
        'maxLength': 50.0, // meters
        'accuracy': 0.001, // meters
      },
    ),
    SimulatedBLEDevice(
      id: 'sim_caliper_01',
      name: 'Simulated Tree Caliper',
      type: BLEDeviceType.digitalCaliper,
      manufacturer: 'ForestTools Sim',
      batteryLevel: 90,
      capabilities: {
        'maxDiameter': 150.0, // cm
        'accuracy': 0.1, // cm
      },
    ),
    SimulatedBLEDevice(
      id: 'sim_hypsometer_01',
      name: 'Simulated Hypsometer',
      type: BLEDeviceType.hypsometer,
      manufacturer: 'TreeHeight Sim',
      batteryLevel: 68,
      capabilities: {
        'maxHeight': 100.0, // meters
        'accuracy': 0.1, // meters
        'distanceMeasure': true,
      },
    ),
  ];
  
  /// 預定義的測試情境
  List<SimulationScenario> get predefinedScenarios => [
    SimulationScenario(
      id: 'scenario_dbh_single',
      name: '單株 DBH 測量',
      description: '模擬測量單株樹木的胸徑',
      measurements: [
        BLEMeasurementData(
          deviceId: 'sim_caliper_01',
          deviceType: BLEDeviceType.digitalCaliper,
          value: 45.2,
          unit: 'cm',
          accuracy: 0.1,
        ),
      ],
    ),
    SimulationScenario(
      id: 'scenario_dbh_multiple',
      name: '多株 DBH 測量',
      description: '連續測量多株樹木的胸徑',
      measurements: [
        BLEMeasurementData(
          deviceId: 'sim_caliper_01',
          deviceType: BLEDeviceType.digitalCaliper,
          value: 32.5,
          unit: 'cm',
        ),
        BLEMeasurementData(
          deviceId: 'sim_caliper_01',
          deviceType: BLEDeviceType.digitalCaliper,
          value: 48.3,
          unit: 'cm',
        ),
        BLEMeasurementData(
          deviceId: 'sim_caliper_01',
          deviceType: BLEDeviceType.digitalCaliper,
          value: 27.8,
          unit: 'cm',
        ),
        BLEMeasurementData(
          deviceId: 'sim_caliper_01',
          deviceType: BLEDeviceType.digitalCaliper,
          value: 55.1,
          unit: 'cm',
        ),
      ],
      duration: const Duration(seconds: 60),
    ),
    SimulationScenario(
      id: 'scenario_height_laser',
      name: '樹高雷射測量',
      description: '使用雷射測距儀測量樹高',
      measurements: [
        BLEMeasurementData(
          deviceId: 'sim_hypsometer_01',
          deviceType: BLEDeviceType.hypsometer,
          value: 15.0, // 距離
          unit: 'm',
          rawData: {'measureType': 'distance'},
        ),
        BLEMeasurementData(
          deviceId: 'sim_hypsometer_01',
          deviceType: BLEDeviceType.hypsometer,
          value: 18.5, // 樹高
          unit: 'm',
          rawData: {'measureType': 'height'},
        ),
      ],
    ),
    SimulationScenario(
      id: 'scenario_intermittent',
      name: '間歇性連線',
      description: '模擬 BLE 連線不穩定的情況',
      measurements: [],
      duration: const Duration(seconds: 45),
    ),
  ];
  
  /// 啟用模擬模式
  void enableSimulationMode() {
    _isSimulationMode = true;
    _simulatedDevices.clear();
    _simulatedDevices.addAll(predefinedDevices);
    debugPrint('[BLESimulation] 模擬模式已啟用');
  }
  
  /// 停用模擬模式
  void disableSimulationMode() {
    _isSimulationMode = false;
    _measurementTimer?.cancel();
    _connectedDevice = null;
    _simulatedDevices.clear();
    debugPrint('[BLESimulation] 模擬模式已停用');
  }
  
  /// 開始掃描模擬設備
  Future<void> startScan({Duration duration = const Duration(seconds: 5)}) async {
    if (!_isSimulationMode) {
      debugPrint('[BLESimulation] 非模擬模式，無法掃描');
      return;
    }
    
    debugPrint('[BLESimulation] 開始掃描模擬設備...');
    
    // 模擬逐步發現設備
    for (var i = 0; i < _simulatedDevices.length; i++) {
      await Future.delayed(Duration(milliseconds: 500 + _random.nextInt(1000)));
      _deviceDiscoveryController.add(_simulatedDevices[i]);
    }
    
    debugPrint('[BLESimulation] 掃描完成，發現 ${_simulatedDevices.length} 個設備');
  }
  
  /// 連接到模擬設備
  Future<bool> connect(String deviceId) async {
    if (!_isSimulationMode) return false;
    
    final device = _simulatedDevices.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => throw Exception('Device not found: $deviceId'),
    );
    
    // 模擬連接延遲
    await Future.delayed(Duration(milliseconds: 500 + _random.nextInt(1500)));
    
    // 90% 成功率
    if (_random.nextDouble() < 0.9) {
      _connectedDevice = device.copyWith(isConnected: true);
      _connectionStateController.add(true);
      debugPrint('[BLESimulation] 已連接到 ${device.name}');
      return true;
    } else {
      debugPrint('[BLESimulation] 連接失敗（模擬）');
      return false;
    }
  }
  
  /// 斷開連接
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      _measurementTimer?.cancel();
      _connectedDevice = null;
      _connectionStateController.add(false);
      debugPrint('[BLESimulation] 已斷開連接');
    }
  }
  
  /// 開始接收模擬測量數據
  void startReceivingMeasurements({
    Duration interval = const Duration(seconds: 3),
    BLEDeviceType? filterType,
  }) {
    if (_connectedDevice == null) {
      debugPrint('[BLESimulation] 無已連接設備');
      return;
    }
    
    _measurementTimer?.cancel();
    _measurementTimer = Timer.periodic(interval, (_) {
      if (_connectedDevice != null) {
        final measurement = _generateMeasurement(_connectedDevice!);
        _measurementController.add(measurement);
      }
    });
    
    debugPrint('[BLESimulation] 開始接收測量數據，間隔: ${interval.inSeconds}秒');
  }
  
  /// 停止接收測量數據
  void stopReceivingMeasurements() {
    _measurementTimer?.cancel();
    _measurementTimer = null;
    debugPrint('[BLESimulation] 停止接收測量數據');
  }
  
  /// 發送單次測量請求
  Future<BLEMeasurementData?> requestSingleMeasurement() async {
    if (_connectedDevice == null) return null;
    
    // 模擬測量延遲
    await Future.delayed(Duration(milliseconds: 300 + _random.nextInt(700)));
    
    final measurement = _generateMeasurement(_connectedDevice!);
    _measurementController.add(measurement);
    
    return measurement;
  }
  
  /// 執行預定義情境
  Future<void> runScenario(String scenarioId) async {
    final scenario = predefinedScenarios.firstWhere(
      (s) => s.id == scenarioId,
      orElse: () => throw Exception('Scenario not found: $scenarioId'),
    );
    
    debugPrint('[BLESimulation] 執行情境: ${scenario.name}');
    
    if (scenario.id == 'scenario_intermittent') {
      // 間歇性連線情境
      await _runIntermittentScenario();
      return;
    }
    
    // 正常情境 - 逐一發送測量數據
    final delayPerMeasurement = scenario.duration.inMilliseconds ~/ 
        math.max(scenario.measurements.length, 1);
    
    for (final measurement in scenario.measurements) {
      await Future.delayed(Duration(milliseconds: delayPerMeasurement));
      _measurementController.add(measurement);
    }
    
    debugPrint('[BLESimulation] 情境完成');
  }
  
  /// 生成模擬測量數據
  BLEMeasurementData _generateMeasurement(SimulatedBLEDevice device) {
    double value;
    String unit;
    double? accuracy;
    
    switch (device.type) {
      case BLEDeviceType.laserRangefinder:
        value = 5.0 + _random.nextDouble() * 20; // 5-25 meters
        unit = 'm';
        accuracy = 0.01;
        break;
        
      case BLEDeviceType.digitalTapeMeasure:
        value = 0.5 + _random.nextDouble() * 10; // 0.5-10.5 meters
        unit = 'm';
        accuracy = 0.001;
        break;
        
      case BLEDeviceType.digitalCaliper:
        value = 15.0 + _random.nextDouble() * 80; // 15-95 cm
        // 添加小量隨機變化模擬真實測量
        value = (value * 10).round() / 10; // 精確到 0.1
        unit = 'cm';
        accuracy = 0.1;
        break;
        
      case BLEDeviceType.altimeter:
        value = 100.0 + _random.nextDouble() * 500; // 100-600 meters
        unit = 'm';
        accuracy = 1.0;
        break;
        
      case BLEDeviceType.hypsometer:
        value = 5.0 + _random.nextDouble() * 30; // 5-35 meters
        unit = 'm';
        accuracy = 0.1;
        break;
        
      case BLEDeviceType.genericSensor:
        value = _random.nextDouble() * 100;
        unit = 'units';
        accuracy = null;
    }
    
    return BLEMeasurementData(
      deviceId: device.id,
      deviceType: device.type,
      value: value,
      unit: unit,
      accuracy: accuracy,
      rawData: {
        'simulated': true,
        'batteryLevel': device.batteryLevel,
      },
    );
  }
  
  /// 間歇性連線情境
  Future<void> _runIntermittentScenario() async {
    for (var i = 0; i < 5; i++) {
      // 連接
      _connectionStateController.add(true);
      await Future.delayed(Duration(seconds: 2 + _random.nextInt(5)));
      
      // 發送一些數據
      for (var j = 0; j < 2; j++) {
        if (_connectedDevice != null) {
          _measurementController.add(_generateMeasurement(_connectedDevice!));
        }
        await Future.delayed(const Duration(seconds: 1));
      }
      
      // 斷開
      _connectionStateController.add(false);
      await Future.delayed(Duration(seconds: 1 + _random.nextInt(3)));
    }
    
    // 最終恢復連接
    _connectionStateController.add(true);
  }
  
  /// 新增自定義模擬設備
  void addCustomDevice(SimulatedBLEDevice device) {
    if (_isSimulationMode) {
      _simulatedDevices.add(device);
      debugPrint('[BLESimulation] 新增自定義設備: ${device.name}');
    }
  }
  
  /// 釋放資源
  void dispose() {
    _measurementTimer?.cancel();
    _deviceDiscoveryController.close();
    _measurementController.close();
    _connectionStateController.close();
  }
}

/// BLE 模擬控制面板 Widget
class BLESimulationControlPanel extends StatefulWidget {
  final VoidCallback? onMeasurementReceived;
  
  const BLESimulationControlPanel({
    Key? key,
    this.onMeasurementReceived,
  }) : super(key: key);
  
  @override
  State<BLESimulationControlPanel> createState() => _BLESimulationControlPanelState();
}

class _BLESimulationControlPanelState extends State<BLESimulationControlPanel> {
  final BLESimulationService _service = BLESimulationService();
  final List<BLEMeasurementData> _recentMeasurements = [];
  StreamSubscription<BLEMeasurementData>? _measurementSub;
  
  @override
  void initState() {
    super.initState();
    _measurementSub = _service.measurementStream.listen((data) {
      setState(() {
        _recentMeasurements.insert(0, data);
        if (_recentMeasurements.length > 10) {
          _recentMeasurements.removeLast();
        }
      });
      widget.onMeasurementReceived?.call();
    });
  }
  
  @override
  void dispose() {
    _measurementSub?.cancel();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 標題
            Row(
              children: [
                Icon(
                  Icons.bluetooth,
                  color: _service.isSimulationMode ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 8),
                const Text(
                  'BLE 模擬控制面板',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _service.isSimulationMode,
                  onChanged: (value) {
                    setState(() {
                      if (value) {
                        _service.enableSimulationMode();
                      } else {
                        _service.disableSimulationMode();
                      }
                    });
                  },
                ),
              ],
            ),
            
            if (_service.isSimulationMode) ...[
              const Divider(),
              
              // 設備列表
              const Text(
                '可用設備:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _service.availableDevices.length,
                  itemBuilder: (context, index) {
                    final device = _service.availableDevices[index];
                    final isConnected = _service.connectedDevice?.id == device.id;
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(
                          _getDeviceIcon(device.type),
                          size: 18,
                          color: isConnected ? Colors.white : Colors.blue,
                        ),
                        label: Text(device.name),
                        backgroundColor: isConnected ? Colors.blue : null,
                        labelStyle: TextStyle(
                          color: isConnected ? Colors.white : null,
                        ),
                        onPressed: () async {
                          if (isConnected) {
                            await _service.disconnect();
                          } else {
                            await _service.connect(device.id);
                          }
                          setState(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 操作按鈕
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('接收數據'),
                    onPressed: _service.connectedDevice != null
                        ? () => _service.startReceivingMeasurements()
                        : null,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.stop),
                    label: const Text('停止'),
                    onPressed: () => _service.stopReceivingMeasurements(),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.touch_app),
                    label: const Text('單次'),
                    onPressed: _service.connectedDevice != null
                        ? () => _service.requestSingleMeasurement()
                        : null,
                  ),
                ],
              ),
              
              if (_recentMeasurements.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  '最近測量:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: _recentMeasurements.length,
                    itemBuilder: (context, index) {
                      final data = _recentMeasurements[index];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          _getDeviceIcon(data.deviceType),
                          size: 20,
                        ),
                        title: Text(
                          '${data.value.toStringAsFixed(2)} ${data.unit}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '${data.deviceType.name} • ${_formatTime(data.timestamp)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
  
  IconData _getDeviceIcon(BLEDeviceType type) {
    switch (type) {
      case BLEDeviceType.laserRangefinder:
        return Icons.straighten;
      case BLEDeviceType.digitalTapeMeasure:
        return Icons.architecture;
      case BLEDeviceType.digitalCaliper:
        return Icons.circle_outlined;
      case BLEDeviceType.altimeter:
        return Icons.height;
      case BLEDeviceType.hypsometer:
        return Icons.park;
      case BLEDeviceType.genericSensor:
        return Icons.sensors;
    }
  }
  
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
           '${time.minute.toString().padLeft(2, '0')}:'
           '${time.second.toString().padLeft(2, '0')}';
  }
}
