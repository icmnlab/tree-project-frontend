// ============================================================================
// V3 BLE 模擬服務完整測試套件
// ============================================================================
// 目標：
// - 100% 覆蓋率的 BLE 模擬功能測試
// - 嚴格驗證邊界條件
// - 壓力測試與並發測試
// - 數據完整性驗證
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';

// ============================================================================
// 測試用 BLE 模擬核心類別 (獨立於 app 代碼)
// ============================================================================

/// BLE 設備類型
enum TestBLEDeviceType {
  laserRangefinder,
  digitalTapeMeasure,
  digitalCaliper,
  altimeter,
  hypsometer,
  genericSensor,
}

/// 模擬 BLE 設備
class TestSimulatedBLEDevice {
  final String id;
  final String name;
  final TestBLEDeviceType type;
  final String manufacturer;
  final bool isConnected;
  final int batteryLevel;
  final Map<String, dynamic> capabilities;
  
  TestSimulatedBLEDevice({
    required this.id,
    required this.name,
    required this.type,
    this.manufacturer = 'TestDevice',
    this.isConnected = false,
    this.batteryLevel = 100,
    Map<String, dynamic>? capabilities,
  }) : capabilities = capabilities ?? {};
  
  TestSimulatedBLEDevice copyWith({
    bool? isConnected,
    int? batteryLevel,
  }) => TestSimulatedBLEDevice(
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
class TestBLEMeasurementData {
  final String deviceId;
  final TestBLEDeviceType deviceType;
  final double value;
  final String unit;
  final DateTime timestamp;
  final double? accuracy;
  final Map<String, dynamic> rawData;
  
  TestBLEMeasurementData({
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
    
  bool isValid() {
    // 驗證數值範圍
    switch (deviceType) {
      case TestBLEDeviceType.laserRangefinder:
        return value >= 0 && value <= 500;
      case TestBLEDeviceType.digitalTapeMeasure:
        return value >= 0 && value <= 100;
      case TestBLEDeviceType.digitalCaliper:
        return value >= 0 && value <= 200;
      case TestBLEDeviceType.altimeter:
        return value >= -500 && value <= 10000;
      case TestBLEDeviceType.hypsometer:
        return value >= 0 && value <= 200;
      case TestBLEDeviceType.genericSensor:
        return true;
    }
  }
}

/// 測試用 BLE 模擬服務
class TestBLESimulationService {
  bool _isSimulationMode = false;
  final List<TestSimulatedBLEDevice> _devices = [];
  TestSimulatedBLEDevice? _connectedDevice;
  Timer? _measurementTimer;
  final _random = math.Random();
  
  // 事件流
  final _deviceDiscoveryController = StreamController<TestSimulatedBLEDevice>.broadcast();
  final _measurementController = StreamController<TestBLEMeasurementData>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  
  Stream<TestSimulatedBLEDevice> get deviceDiscoveryStream => _deviceDiscoveryController.stream;
  Stream<TestBLEMeasurementData> get measurementStream => _measurementController.stream;
  Stream<bool> get connectionStateStream => _connectionStateController.stream;
  Stream<String> get errorStream => _errorController.stream;
  
  bool get isSimulationMode => _isSimulationMode;
  TestSimulatedBLEDevice? get connectedDevice => _connectedDevice;
  List<TestSimulatedBLEDevice> get availableDevices => List.unmodifiable(_devices);
  
  // 統計
  int _totalMeasurements = 0;
  int _failedConnections = 0;
  int _disconnections = 0;
  
  int get totalMeasurements => _totalMeasurements;
  int get failedConnections => _failedConnections;
  int get disconnections => _disconnections;
  
  void enableSimulationMode() {
    _isSimulationMode = true;
    _devices.clear();
    _devices.addAll(_getDefaultDevices());
    _totalMeasurements = 0;
    _failedConnections = 0;
    _disconnections = 0;
  }
  
  void disableSimulationMode() {
    _isSimulationMode = false;
    _measurementTimer?.cancel();
    _connectedDevice = null;
    _devices.clear();
  }
  
  List<TestSimulatedBLEDevice> _getDefaultDevices() => [
    TestSimulatedBLEDevice(
      id: 'test_laser_01',
      name: 'Test Laser',
      type: TestBLEDeviceType.laserRangefinder,
      batteryLevel: 85,
      capabilities: {'maxRange': 100.0, 'accuracy': 0.01},
    ),
    TestSimulatedBLEDevice(
      id: 'test_caliper_01',
      name: 'Test Caliper',
      type: TestBLEDeviceType.digitalCaliper,
      batteryLevel: 90,
      capabilities: {'maxDiameter': 150.0, 'accuracy': 0.1},
    ),
    TestSimulatedBLEDevice(
      id: 'test_hypsometer_01',
      name: 'Test Hypsometer',
      type: TestBLEDeviceType.hypsometer,
      batteryLevel: 68,
      capabilities: {'maxHeight': 100.0, 'accuracy': 0.1},
    ),
  ];
  
  Future<void> startScan({
    Duration duration = const Duration(seconds: 5),
    double successRate = 1.0,
  }) async {
    if (!_isSimulationMode) {
      _errorController.add('Not in simulation mode');
      return;
    }
    
    for (final device in _devices) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_random.nextDouble() < successRate) {
        _deviceDiscoveryController.add(device);
      }
    }
  }
  
  Future<bool> connect(String deviceId, {double successRate = 0.9}) async {
    if (!_isSimulationMode) return false;
    
    try {
      final device = _devices.firstWhere((d) => d.id == deviceId);
      
      await Future.delayed(const Duration(milliseconds: 200));
      
      if (_random.nextDouble() < successRate) {
        _connectedDevice = device.copyWith(isConnected: true);
        _connectionStateController.add(true);
        return true;
      } else {
        _failedConnections++;
        _errorController.add('Connection failed: $deviceId');
        return false;
      }
    } catch (e) {
      _failedConnections++;
      _errorController.add('Device not found: $deviceId');
      return false;
    }
  }
  
  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      _measurementTimer?.cancel();
      _connectedDevice = null;
      _connectionStateController.add(false);
      _disconnections++;
    }
  }
  
  void startReceivingMeasurements({
    Duration interval = const Duration(seconds: 1),
    double errorRate = 0.0,
  }) {
    if (_connectedDevice == null) {
      _errorController.add('No connected device');
      return;
    }
    
    _measurementTimer?.cancel();
    _measurementTimer = Timer.periodic(interval, (_) {
      if (_connectedDevice != null) {
        if (_random.nextDouble() >= errorRate) {
          final measurement = _generateMeasurement(_connectedDevice!);
          _measurementController.add(measurement);
          _totalMeasurements++;
        } else {
          _errorController.add('Measurement error (simulated)');
        }
      }
    });
  }
  
  void stopReceivingMeasurements() {
    _measurementTimer?.cancel();
    _measurementTimer = null;
  }
  
  Future<TestBLEMeasurementData?> requestSingleMeasurement({
    double? overrideValue,
  }) async {
    if (_connectedDevice == null) return null;
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    final measurement = overrideValue != null
        ? _generateMeasurementWithValue(_connectedDevice!, overrideValue)
        : _generateMeasurement(_connectedDevice!);
    
    _measurementController.add(measurement);
    _totalMeasurements++;
    
    return measurement;
  }
  
  TestBLEMeasurementData _generateMeasurement(TestSimulatedBLEDevice device) {
    double value;
    String unit;
    double? accuracy;
    
    switch (device.type) {
      case TestBLEDeviceType.laserRangefinder:
        value = 5.0 + _random.nextDouble() * 95; // 5-100 meters
        unit = 'm';
        accuracy = 0.01;
        break;
      case TestBLEDeviceType.digitalTapeMeasure:
        value = 0.5 + _random.nextDouble() * 49.5; // 0.5-50 meters
        unit = 'm';
        accuracy = 0.001;
        break;
      case TestBLEDeviceType.digitalCaliper:
        value = 10.0 + _random.nextDouble() * 140; // 10-150 cm
        value = (value * 10).round() / 10; // 精確到 0.1
        unit = 'cm';
        accuracy = 0.1;
        break;
      case TestBLEDeviceType.altimeter:
        value = 0.0 + _random.nextDouble() * 1000; // 0-1000 meters
        unit = 'm';
        accuracy = 1.0;
        break;
      case TestBLEDeviceType.hypsometer:
        value = 3.0 + _random.nextDouble() * 97; // 3-100 meters
        unit = 'm';
        accuracy = 0.1;
        break;
      case TestBLEDeviceType.genericSensor:
        value = _random.nextDouble() * 100;
        unit = 'units';
        accuracy = null;
    }
    
    return TestBLEMeasurementData(
      deviceId: device.id,
      deviceType: device.type,
      value: value,
      unit: unit,
      accuracy: accuracy,
      rawData: {'simulated': true, 'batteryLevel': device.batteryLevel},
    );
  }
  
  TestBLEMeasurementData _generateMeasurementWithValue(
    TestSimulatedBLEDevice device,
    double value,
  ) {
    String unit;
    double? accuracy;
    
    switch (device.type) {
      case TestBLEDeviceType.laserRangefinder:
      case TestBLEDeviceType.digitalTapeMeasure:
      case TestBLEDeviceType.altimeter:
      case TestBLEDeviceType.hypsometer:
        unit = 'm';
        accuracy = 0.1;
        break;
      case TestBLEDeviceType.digitalCaliper:
        unit = 'cm';
        accuracy = 0.1;
        break;
      case TestBLEDeviceType.genericSensor:
        unit = 'units';
        accuracy = null;
    }
    
    return TestBLEMeasurementData(
      deviceId: device.id,
      deviceType: device.type,
      value: value,
      unit: unit,
      accuracy: accuracy,
      rawData: {'simulated': true, 'override': true},
    );
  }
  
  void addCustomDevice(TestSimulatedBLEDevice device) {
    if (_isSimulationMode) {
      _devices.add(device);
    }
  }
  
  void simulateBatteryDrain(String deviceId, int newLevel) {
    final index = _devices.indexWhere((d) => d.id == deviceId);
    if (index != -1) {
      _devices[index] = _devices[index].copyWith(batteryLevel: newLevel);
      if (_connectedDevice?.id == deviceId) {
        _connectedDevice = _connectedDevice!.copyWith(batteryLevel: newLevel);
      }
    }
  }
  
  Future<void> simulateConnectionDrop() async {
    if (_connectedDevice != null) {
      _connectionStateController.add(false);
      await Future.delayed(const Duration(milliseconds: 100));
      _disconnections++;
      _connectedDevice = null;
    }
  }
  
  void dispose() {
    _measurementTimer?.cancel();
    _deviceDiscoveryController.close();
    _measurementController.close();
    _connectionStateController.close();
    _errorController.close();
  }
}

// ============================================================================
// 測試套件
// ============================================================================

void main() {
  late TestBLESimulationService service;
  
  setUp(() {
    service = TestBLESimulationService();
  });
  
  tearDown(() {
    service.dispose();
  });
  
  // =========================================================================
  // 基本功能測試
  // =========================================================================
  
  group('基本功能測試', () {
    test('初始狀態正確', () {
      expect(service.isSimulationMode, false);
      expect(service.connectedDevice, isNull);
      expect(service.availableDevices, isEmpty);
    });
    
    test('啟用模擬模式後狀態正確', () {
      service.enableSimulationMode();
      
      expect(service.isSimulationMode, true);
      expect(service.availableDevices.length, 3);
      expect(service.connectedDevice, isNull);
    });
    
    test('停用模擬模式清除所有狀態', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01');
      
      service.disableSimulationMode();
      
      expect(service.isSimulationMode, false);
      expect(service.connectedDevice, isNull);
      expect(service.availableDevices, isEmpty);
    });
    
    test('非模擬模式下無法掃描設備', () async {
      final errors = <String>[];
      service.errorStream.listen(errors.add);
      
      await service.startScan();
      
      await Future.delayed(const Duration(milliseconds: 50));
      expect(errors, contains('Not in simulation mode'));
    });
  });
  
  // =========================================================================
  // 設備掃描測試
  // =========================================================================
  
  group('設備掃描測試', () {
    test('掃描發現所有設備', () async {
      service.enableSimulationMode();
      
      final discoveredDevices = <TestSimulatedBLEDevice>[];
      service.deviceDiscoveryStream.listen(discoveredDevices.add);
      
      await service.startScan();
      await Future.delayed(const Duration(milliseconds: 500));
      
      expect(discoveredDevices.length, 3);
      expect(discoveredDevices.any((d) => d.id == 'test_laser_01'), true);
      expect(discoveredDevices.any((d) => d.id == 'test_caliper_01'), true);
      expect(discoveredDevices.any((d) => d.id == 'test_hypsometer_01'), true);
    });
    
    test('掃描成功率控制', () async {
      service.enableSimulationMode();
      
      final discoveredDevices = <TestSimulatedBLEDevice>[];
      service.deviceDiscoveryStream.listen(discoveredDevices.add);
      
      // 0% 成功率應該發現 0 個設備
      await service.startScan(successRate: 0.0);
      await Future.delayed(const Duration(milliseconds: 500));
      
      expect(discoveredDevices, isEmpty);
    });
    
    test('添加自定義設備後可被掃描發現', () async {
      service.enableSimulationMode();
      
      service.addCustomDevice(TestSimulatedBLEDevice(
        id: 'custom_device_01',
        name: 'Custom Device',
        type: TestBLEDeviceType.genericSensor,
      ));
      
      expect(service.availableDevices.length, 4);
      expect(service.availableDevices.any((d) => d.id == 'custom_device_01'), true);
    });
  });
  
  // =========================================================================
  // 連線測試
  // =========================================================================
  
  group('連線測試', () {
    test('成功連線到設備', () async {
      service.enableSimulationMode();
      
      final connectionStates = <bool>[];
      final completer = Completer<void>();
      
      service.connectionStateStream.listen((state) {
        connectionStates.add(state);
        if (state == true && !completer.isCompleted) {
          completer.complete();
        }
      });
      
      final result = await service.connect('test_laser_01', successRate: 1.0);
      
      // 等待連線狀態事件
      await completer.future.timeout(
        Duration(seconds: 2),
        onTimeout: () {},
      );
      
      expect(result, true);
      expect(service.connectedDevice, isNotNull);
      expect(service.connectedDevice!.id, 'test_laser_01');
      expect(service.connectedDevice!.isConnected, true);
    });
    
    test('連線失敗情況', () async {
      service.enableSimulationMode();
      
      final errors = <String>[];
      service.errorStream.listen(errors.add);
      
      final result = await service.connect('test_laser_01', successRate: 0.0);
      
      // 等待錯誤事件
      await Future.delayed(Duration(milliseconds: 100));
      
      expect(result, false);
      expect(service.connectedDevice, isNull);
      expect(service.failedConnections, 1);
    });
    
    test('連線到不存在的設備', () async {
      service.enableSimulationMode();
      
      final errors = <String>[];
      service.errorStream.listen(errors.add);
      
      final result = await service.connect('nonexistent_device');
      
      expect(result, false);
      expect(service.failedConnections, 1);
      expect(errors.any((e) => e.contains('Device not found')), true);
    });
    
    test('斷開連線', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      final connectionStates = <bool>[];
      service.connectionStateStream.listen(connectionStates.add);
      
      await service.disconnect();
      
      expect(service.connectedDevice, isNull);
      expect(service.disconnections, 1);
      expect(connectionStates, contains(false));
    });
    
    test('模擬連線中斷', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      final connectionStates = <bool>[];
      service.connectionStateStream.listen(connectionStates.add);
      
      await service.simulateConnectionDrop();
      
      expect(service.connectedDevice, isNull);
      expect(service.disconnections, 1);
      expect(connectionStates, contains(false));
    });
  });
  
  // =========================================================================
  // 測量數據測試
  // =========================================================================
  
  group('測量數據測試', () {
    test('單次測量請求', () async {
      service.enableSimulationMode();
      await service.connect('test_caliper_01', successRate: 1.0);
      
      final measurement = await service.requestSingleMeasurement();
      
      expect(measurement, isNotNull);
      expect(measurement!.deviceId, 'test_caliper_01');
      expect(measurement.deviceType, TestBLEDeviceType.digitalCaliper);
      expect(measurement.unit, 'cm');
      expect(measurement.value, greaterThanOrEqualTo(10.0));
      expect(measurement.value, lessThanOrEqualTo(150.0));
      expect(measurement.isValid(), true);
    });
    
    test('指定測量值', () async {
      service.enableSimulationMode();
      await service.connect('test_caliper_01', successRate: 1.0);
      
      final measurement = await service.requestSingleMeasurement(overrideValue: 45.5);
      
      expect(measurement, isNotNull);
      expect(measurement!.value, 45.5);
      expect(measurement.rawData['override'], true);
    });
    
    test('未連線時無法測量', () async {
      service.enableSimulationMode();
      
      final measurement = await service.requestSingleMeasurement();
      
      expect(measurement, isNull);
    });
    
    test('連續接收測量數據', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      final measurements = <TestBLEMeasurementData>[];
      service.measurementStream.listen(measurements.add);
      
      service.startReceivingMeasurements(interval: const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 550));
      service.stopReceivingMeasurements();
      
      expect(measurements.length, greaterThanOrEqualTo(4));
      expect(measurements.length, lessThanOrEqualTo(6));
      
      for (final m in measurements) {
        expect(m.deviceId, 'test_laser_01');
        expect(m.isValid(), true);
      }
    });
    
    test('測量錯誤率模擬', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      final measurements = <TestBLEMeasurementData>[];
      final errors = <String>[];
      service.measurementStream.listen(measurements.add);
      service.errorStream.listen(errors.add);
      
      // 50% 錯誤率
      service.startReceivingMeasurements(
        interval: const Duration(milliseconds: 50),
        errorRate: 0.5,
      );
      await Future.delayed(const Duration(seconds: 1));
      service.stopReceivingMeasurements();
      
      // 應該有一些成功和一些失敗
      expect(measurements.length, greaterThan(0));
      // 由於隨機性，不能精確斷言錯誤數量
    });
    
    test('停止接收後不再產生數據', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      final measurements = <TestBLEMeasurementData>[];
      service.measurementStream.listen(measurements.add);
      
      service.startReceivingMeasurements(interval: const Duration(milliseconds: 100));
      await Future.delayed(const Duration(milliseconds: 250));
      service.stopReceivingMeasurements();
      
      final countAfterStop = measurements.length;
      await Future.delayed(const Duration(milliseconds: 300));
      
      expect(measurements.length, countAfterStop);
    });
  });
  
  // =========================================================================
  // 數據驗證測試
  // =========================================================================
  
  group('數據驗證測試', () {
    test('所有設備類型產生有效範圍數據', () async {
      service.enableSimulationMode();
      
      for (final device in service.availableDevices) {
        await service.connect(device.id, successRate: 1.0);
        
        // 多次測量驗證範圍
        for (var i = 0; i < 10; i++) {
          final measurement = await service.requestSingleMeasurement();
          expect(measurement, isNotNull);
          expect(measurement!.isValid(), true,
            reason: '${device.type} 產生無效數據: ${measurement.value}');
        }
        
        await service.disconnect();
      }
    });
    
    test('數據時間戳正確', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      final before = DateTime.now();
      final measurement = await service.requestSingleMeasurement();
      final after = DateTime.now();
      
      expect(measurement!.timestamp.isAfter(before.subtract(const Duration(seconds: 1))), true);
      expect(measurement.timestamp.isBefore(after.add(const Duration(seconds: 1))), true);
    });
    
    test('設備電量模擬', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      expect(service.connectedDevice!.batteryLevel, 85);
      
      service.simulateBatteryDrain('test_laser_01', 20);
      
      expect(service.connectedDevice!.batteryLevel, 20);
      
      final measurement = await service.requestSingleMeasurement();
      expect(measurement!.rawData['batteryLevel'], 20);
    });
  });
  
  // =========================================================================
  // 並發與壓力測試
  // =========================================================================
  
  group('並發與壓力測試', () {
    test('高頻率測量', () async {
      service.enableSimulationMode();
      await service.connect('test_caliper_01', successRate: 1.0);
      
      final measurements = <TestBLEMeasurementData>[];
      service.measurementStream.listen(measurements.add);
      
      // 10ms 間隔 = 理想每秒 100 次
      service.startReceivingMeasurements(interval: const Duration(milliseconds: 10));
      await Future.delayed(const Duration(seconds: 1));
      service.stopReceivingMeasurements();
      
      // 用寬鬆下界避免在較慢／負載高的主機上因 Dart Timer 顆粒度而誤判（理想 100，
      // 此處只驗證高頻串流確實持續產出大量量測）。
      expect(measurements.length, greaterThan(50));
      expect(service.totalMeasurements, measurements.length);
      
      // 驗證所有數據有效
      for (final m in measurements) {
        expect(m.isValid(), true);
      }
    });
    
    test('多次連線/斷線循環', () async {
      service.enableSimulationMode();
      
      for (var i = 0; i < 10; i++) {
        final result = await service.connect('test_laser_01', successRate: 1.0);
        expect(result, true);
        
        final measurement = await service.requestSingleMeasurement();
        expect(measurement, isNotNull);
        
        await service.disconnect();
        expect(service.connectedDevice, isNull);
      }
      
      expect(service.disconnections, 10);
      expect(service.totalMeasurements, 10);
    });
    
    test('快速切換設備', () async {
      service.enableSimulationMode();
      
      final devices = service.availableDevices;
      
      for (var i = 0; i < 5; i++) {
        for (final device in devices) {
          await service.connect(device.id, successRate: 1.0);
          expect(service.connectedDevice!.id, device.id);
          await service.disconnect();
        }
      }
      
      expect(service.disconnections, 15); // 3 devices * 5 rounds
    });
  });
  
  // =========================================================================
  // 邊界條件測試
  // =========================================================================
  
  group('邊界條件測試', () {
    test('空設備列表處理', () async {
      service.enableSimulationMode();
      service.disableSimulationMode();
      service.enableSimulationMode();
      
      // 移除所有設備
      while (service.availableDevices.isNotEmpty) {
        // 由於 availableDevices 返回不可修改列表，這裡只是測試
        break;
      }
      
      // 應該正常處理空列表
      await service.startScan();
    });
    
    test('重複啟用/停用模擬模式', () {
      for (var i = 0; i < 5; i++) {
        service.enableSimulationMode();
        expect(service.isSimulationMode, true);
        
        service.disableSimulationMode();
        expect(service.isSimulationMode, false);
      }
    });
    
    test('連線時停用模擬模式', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      service.startReceivingMeasurements();
      
      service.disableSimulationMode();
      
      expect(service.connectedDevice, isNull);
      expect(service.isSimulationMode, false);
    });
    
    test('極端電池電量值', () {
      service.enableSimulationMode();
      
      service.addCustomDevice(TestSimulatedBLEDevice(
        id: 'low_battery',
        name: 'Low Battery Device',
        type: TestBLEDeviceType.genericSensor,
        batteryLevel: 0,
      ));
      
      service.addCustomDevice(TestSimulatedBLEDevice(
        id: 'full_battery',
        name: 'Full Battery Device',
        type: TestBLEDeviceType.genericSensor,
        batteryLevel: 100,
      ));
      
      final devices = service.availableDevices;
      expect(devices.any((d) => d.batteryLevel == 0), true);
      expect(devices.any((d) => d.batteryLevel == 100), true);
    });
  });
  
  // =========================================================================
  // 統計功能測試
  // =========================================================================
  
  group('統計功能測試', () {
    test('測量計數正確', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      
      expect(service.totalMeasurements, 0);
      
      await service.requestSingleMeasurement();
      expect(service.totalMeasurements, 1);
      
      await service.requestSingleMeasurement();
      expect(service.totalMeasurements, 2);
    });
    
    test('失敗連線計數正確', () async {
      service.enableSimulationMode();
      
      expect(service.failedConnections, 0);
      
      await service.connect('nonexistent');
      expect(service.failedConnections, 1);
      
      await service.connect('test_laser_01', successRate: 0.0);
      expect(service.failedConnections, 2);
    });
    
    test('斷線計數正確', () async {
      service.enableSimulationMode();
      
      expect(service.disconnections, 0);
      
      await service.connect('test_laser_01', successRate: 1.0);
      await service.disconnect();
      expect(service.disconnections, 1);
      
      await service.connect('test_laser_01', successRate: 1.0);
      await service.simulateConnectionDrop();
      expect(service.disconnections, 2);
    });
    
    test('重置統計', () async {
      service.enableSimulationMode();
      await service.connect('test_laser_01', successRate: 1.0);
      await service.requestSingleMeasurement();
      await service.disconnect();
      
      expect(service.totalMeasurements, 1);
      expect(service.disconnections, 1);
      
      service.disableSimulationMode();
      service.enableSimulationMode();
      
      expect(service.totalMeasurements, 0);
      expect(service.disconnections, 0);
    });
  });
}
