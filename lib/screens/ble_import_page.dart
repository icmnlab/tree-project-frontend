import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_data_processor.dart'; // 引入解析器
import '../services/ble_packet_decoder.dart'; // 引入封包解碼器
import '../models/pending_tree_measurement.dart';
import '../services/pending_measurement_service.dart'; // 待測量服務
import '../services/auth_service.dart'; // 登入時可存取專案（BLE 指派 fallback）
import '../services/project_service.dart'; // 專案服務（手動指派 dropdown）
import '../services/tree_service.dart';
import '../services/v3/data_filter_service.dart'; // V3 數據過濾服務
import '../services/v3/project_boundary_service.dart'; // 專案邊界服務（自動匹配專案）
import '../widgets/network_aware_widgets.dart'; // 網路感知元件
import 'manual_input_page_v2.dart'; // V2 批次匯入
import 'pending_measurement_task_page.dart'; // 引入待測量任務頁面

class BleImportPage extends StatefulWidget {
  const BleImportPage({super.key});

  @override
  State<BleImportPage> createState() => _BleImportPageState();
}

class _BleImportPageState extends State<BleImportPage> {
  static final _csvCleanRegex = RegExp(r'[^0-9A-Z\.\;\-\r\n\$\#]');
  static final _recordDelimiterRegex = RegExp(r'\$;');

  // 狀態變數
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  bool _isReceiving = false;

  // 數據緩衝區
  final StringBuffer _dataBuffer = StringBuffer();
  final List<String> _hexLog = [];
  List<String> _receivedCsvLines = [];
  bool _isTransmissionSuccess = false;
  int _estimatedRecordCount = 0;

  // 關鍵 UUID (Nordic UART Service)
  final String _serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String _txCharacteristicUuid = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

  final List<int> _eotSignal = [0x5A, 0xBF, 0xFB];

  StreamSubscription? _scanSubscription;
  StreamSubscription? _isScanningSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _timeoutTimer;
  Timer? _uiUpdateTimer;
  final ScrollController _logScrollController = ScrollController();

  // 藍牙適配器狀態
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;

  // UI 節流：收集 pending 更新，由 timer 批次 flush
  bool _uiDirty = false;
  final List<String> _pendingHexEntries = [];

  @override
  void initState() {
    super.initState();
    _listenAdapterState();
    _checkPermissions();
  }

  /// 監聽藍牙適配器狀態（開/關/不支援）
  void _listenAdapterState() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (!mounted) return;
      setState(() {
        _adapterState = state;
      });
      // 藍牙關閉時，自動停止掃描並清理連接
      if (state != BluetoothAdapterState.on) {
        if (_isScanning) _stopScan();
        if (_connectedDevice != null && !_isTransmissionSuccess) {
          _handleFailure();
        }
      }
    });
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    _adapterStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _uiUpdateTimer?.cancel();

    if (_connectedDevice != null) {
      _connectedDevice!.disconnect();
    }
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
    _timeoutTimer?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  // 1. 權限檢查 (相容 Android 12+ 與舊版)
  Future<void> _checkPermissions() async {
    // 請求多個權限
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Android 11 及以下需要定位權限才能掃描藍牙
    ].request();

    // 檢查是否被永久拒絕
    if (statuses[Permission.bluetoothScan] ==
            PermissionStatus.permanentlyDenied ||
        statuses[Permission.location] == PermissionStatus.permanentlyDenied) {
      if (mounted) {
        _showPermissionDialog();
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要權限'),
        content: const Text('請在設定中允許藍牙和定位權限以連接測量儀器。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => openAppSettings(),
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  void _resetState() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _pendingHexEntries.clear();
    _uiDirty = false;
    if (mounted) {
      setState(() {
        _dataBuffer.clear();
        _receivedCsvLines.clear();
        _hexLog.clear();
        _isTransmissionSuccess = false;
        _isReceiving = false;
        _isConnecting = false;
        _scanResults.clear();
        _isScanning = false;
        _estimatedRecordCount = 0;
      });
    }
  }

  /// V3: 顯示資料過濾結果對話框
  void _showFilterResultDialog(DataFilterResult result) {
    final stats = result.stats;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.filter_list, color: Colors.orange[700]),
            const SizedBox(width: 8),
            const Text('資料過濾報告'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow('總輸入', stats.totalInput, Colors.blue),
              _buildStatRow('有效記錄', stats.validCount, Colors.green),
              if (stats.incompleteCount > 0)
                _buildStatRow('不完整', stats.incompleteCount, Colors.orange),
              if (stats.duplicateCount > 0)
                _buildStatRow('重複', stats.duplicateCount, Colors.red),
              if (stats.conflictCount > 0)
                _buildStatRow('衝突(已解決)', stats.conflictCount, Colors.purple),
              if (stats.nonTreeDropped > 0)
                _buildStatRow(
                    '非樹木類型已丟棄(DME/空)', stats.nonTreeDropped, Colors.brown),
              if (stats.missingGpsCount > 0)
                _buildStatRow(
                    '缺 GPS', stats.missingGpsCount, Colors.deepOrange),

              // GPS 品質（HDOP 分級）
              if (stats.hdopQualityCounts.values.any((v) => v > 0)) ...[
                const SizedBox(height: 12),
                const Text('GPS 品質 (HDOP):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                _buildStatRow('  良好 (≤2)', stats.hdopQualityCounts['good'] ?? 0,
                    Colors.green),
                _buildStatRow('  尚可 (≤5)', stats.hdopQualityCounts['fair'] ?? 0,
                    Colors.orange),
                _buildStatRow('  不佳 (>5)', stats.hdopQualityCounts['poor'] ?? 0,
                    Colors.red),
                if ((stats.hdopQualityCounts['unknown'] ?? 0) > 0)
                  _buildStatRow('  未知', stats.hdopQualityCounts['unknown'] ?? 0,
                      Colors.grey),
              ],

              // [v21.0] Phase C 警告統計
              if (stats.gpsJumpCount > 0 ||
                  stats.trphWarningCount > 0 ||
                  stats.posDriftWarningCount > 0) ...[
                const SizedBox(height: 12),
                const Text('資料品質警告:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                if (stats.gpsJumpCount > 0)
                  _buildStatRow('  GPS 跳變 (>100m)', stats.gpsJumpCount,
                      Colors.deepOrange),
                if (stats.trphWarningCount > 0)
                  _buildStatRow(
                      '  TRPH ≠ 1.3m', stats.trphWarningCount, Colors.amber),
                if (stats.posDriftWarningCount > 0)
                  _buildStatRow('  3P 站位漂移 (>5m)', stats.posDriftWarningCount,
                      Colors.deepOrange),
              ],

              if (stats.missingFieldCounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('缺失欄位:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...stats.missingFieldCounts.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• ${e.key}: ${e.value} 筆'),
                  ),
                ),
              ],

              // 顯示衝突詳情
              if (result.conflicts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('衝突詳情 (${result.conflicts.length}):',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.purple)),
                ...result.conflicts.take(3).map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '• 座標: ${c.lat.toStringAsFixed(6)}, ${c.lon.toStringAsFixed(6)}',
                                style: const TextStyle(fontSize: 12)),
                            Text(
                                '  衝突欄位: ${c.conflictingFields.keys.join(", ")}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey[600])),
                            Text('  保留記錄: ${c.keptRecord['id']}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.green[700])),
                          ],
                        ),
                      ),
                    ),
                if (result.conflicts.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('... 還有 ${result.conflicts.length - 3} 組衝突',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ),
              ],

              if (stats.duplicateGroups.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('重複群組 (${stats.duplicateGroups.length}):',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ...stats.duplicateGroups.take(5).map(
                      (g) => Padding(
                        padding: const EdgeInsets.only(left: 16, top: 4),
                        child:
                            Text('• $g', style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                if (stats.duplicateGroups.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('... 還有 ${stats.duplicateGroups.length - 5} 組',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, int value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$value',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // 2. 掃描設備
  Future<void> _startScan() async {
    if (_isScanning) return;

    // [FIX] 重置狀態
    _resetState();

    // [FIX] 掃描前確保沒有殘留連接，避免掃不到設備
    if (_connectedDevice != null) {
      await _disconnect();
    }

    // [FIX] 強制停止之前的掃描並重置狀態
    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;

    // [UX] 增加短暫延遲，讓藍牙堆疊有時間釋放資源 (Android 常見問題)
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      // 開始掃描
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // 監聽掃描結果
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return; // [FIX] 確保 Widget 還在掛載中

        setState(() {
          // 過濾設備：只顯示有名稱且名稱包含 Vertex 或 VLGEO 的設備
          // 或者如果測試設備名稱不同，可以調整這裡
          _scanResults = results.where((r) {
            final name = r.device.platformName.toUpperCase();
            return name.isNotEmpty &&
                (name.contains('VERTEX') || name.contains('VLGEO'));
          }).toList();
        });
      });

      _isScanningSubscription?.cancel();
      _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
        if (!mounted) return;
        setState(() {
          _isScanning = isScanning;
        });
      });
    } catch (e) {
      print('掃描錯誤: $e');
      // [FIX] 檢查 mounted 再調用 setState
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('掃描失敗: $e')),
        );
      }
    }
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _isScanningSubscription?.cancel();
    _isScanningSubscription = null;
    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  // 3. 連接設備與發現服務
  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan(); // 連接前停止掃描

    setState(() {
      _isConnecting = true;
    });

    try {
      // 使用 1.32.0 版本，可以直接調用 connect
      await device.connect(autoConnect: false);

      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _isConnecting = false;
        });
      }

      // [FIX] 設置 log level 減少不必要的 FBP 雜訊
      FlutterBluePlus.setLogLevel(LogLevel.error, color: false);

      // 監聽連接狀態
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (mounted) {
            // [FIX] 如果是在接收數據中斷線，視為傳輸完成，觸發解析邏輯
            if (_isReceiving && _dataBuffer.isNotEmpty) {
              print('設備斷線，觸發傳輸完成邏輯...');
              _onTransferComplete();
            }

            // [FIX] 斷線後取消監聽，釋放資源
            _connectionSubscription?.cancel();
            _connectionSubscription = null;
            _dataSubscription?.cancel();
            _dataSubscription = null;

            // [FIX] 檢查 mounted 再調用 setState（已在外層檢查過 mounted）
            setState(() {
              _connectedDevice = null;
              // 注意：這裡不要將 _isReceiving 設為 false，讓 _onTransferComplete 去處理
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('設備已斷開連接')),
            );
          }
        }
      });

      // 連接成功後，開始發現服務並啟動傳輸
      await _discoverServicesAndSubscribe(device);
    } catch (e) {
      print('連接錯誤: $e');
      // [FIX] 檢查 widget 是否還在樹中再調用 setState
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectedDevice = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('連接失敗: $e')),
        );
      }
    }
  }

  Future<void> _disconnect() async {
    // [FIX] 確保異步斷線並更新 UI 狀態
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    await _dataSubscription?.cancel();
    _dataSubscription = null;

    await _connectedDevice?.disconnect();

    if (mounted) {
      setState(() {
        _connectedDevice = null;
        _isReceiving = false;
        _isConnecting = false;

        // [FIX] 如果不是成功狀態 (即手動斷線或中斷)，則清除數據
        if (!_isTransmissionSuccess) {
          _dataBuffer.clear();
          _receivedCsvLines.clear();
        }
      });
    }
  }

  // 4. 核心邏輯：訂閱通知以觸發傳輸
  Future<void> _discoverServicesAndSubscribe(BluetoothDevice device) async {
    try {
      List<BluetoothService> services = await device.discoverServices();

      BluetoothCharacteristic? txCharacteristic;

      for (var service in services) {
        // 尋找 Nordic UART Service (忽略大小寫)
        if (service.uuid.toString().toUpperCase() == _serviceUuid) {
          for (var characteristic in service.characteristics) {
            // 尋找 TX Characteristic
            if (characteristic.uuid.toString().toUpperCase() ==
                _txCharacteristicUuid) {
              txCharacteristic = characteristic;
              break;
            }
          }
        }
      }

      if (txCharacteristic != null) {
        // 設置通知 (這就是觸發儀器發送檔案的關鍵動作！)
        await txCharacteristic.setNotifyValue(true);

        // [v14.0] 重置封包解碼器統計
        BlePacketDecoder.resetStats();

        // [FIX] 檢查 mounted 再調用 setState
        if (mounted) {
          setState(() {
            _isReceiving = true;
            _dataBuffer.clear(); // 清空緩衝區
            _receivedCsvLines.clear();
            _hexLog.clear(); // 清空 Hex Log
          });
        }

        _dataSubscription = txCharacteristic.lastValueStream.listen(
          (value) {
            _processReceivedData(value);
          },
          onError: (error) {
            debugPrint('[BLE] Data stream error: $error');
            if (mounted && _isReceiving) {
              _onTransferComplete();
            }
          },
        );

        _uiUpdateTimer?.cancel();
        _uiUpdateTimer = Timer.periodic(
          const Duration(milliseconds: 100),
          (_) => _flushUiUpdates(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已觸發傳輸，正在接收數據...')),
          );
        }
      } else {
        throw Exception("未找到 UART 服務或 TX 特徵值");
      }
    } catch (e) {
      print('服務發現錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('服務錯誤: $e')),
        );
      }
    }
  }

  void _processReceivedData(List<int> data) {
    try {
      final hexString = data
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');

      _pendingHexEntries.add('(${data.length}) $hexString');

      if (data.length == 3 &&
          data[0] == _eotSignal[0] &&
          data[1] == _eotSignal[1] &&
          data[2] == _eotSignal[2]) {
        debugPrint('[BLE] EOT signal received');
        _isTransmissionSuccess = true;
        _timeoutTimer?.cancel();
        BlePacketDecoder.printStats();
        _flushUiUpdates();
        _handleSuccess();
        return;
      }

      List<int> decodedData = BlePacketDecoder.decodePacket(data);

      String rawChunk;
      try {
        rawChunk = utf8.decode(decodedData);
      } catch (e) {
        rawChunk = String.fromCharCodes(decodedData);
      }

      String cleanChunk = rawChunk.replaceAll(_csvCleanRegex, '');

      _dataBuffer.write(cleanChunk);

      final newRecords = _recordDelimiterRegex.allMatches(cleanChunk).length;
      if (newRecords > 0) {
        _estimatedRecordCount += newRecords;
        _uiDirty = true;
      }

      if (!_isTransmissionSuccess) {
        _resetTimeoutTimer();
      }
    } catch (e) {
      debugPrint('[BLE] Packet processing error: $e');
    }
  }

  void _flushUiUpdates() {
    if (!mounted) return;
    if (!_uiDirty && _pendingHexEntries.isEmpty) return;

    setState(() {
      if (_pendingHexEntries.isNotEmpty) {
        _hexLog.addAll(_pendingHexEntries);
        _pendingHexEntries.clear();
        while (_hexLog.length > 50) {
          _hexLog.removeAt(0);
        }
      }
      _uiDirty = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.jumpTo(
          _logScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _resetTimeoutTimer() {
    _timeoutTimer?.cancel();
    // [OPT] 縮短超時時間至 3000ms，加快反應速度
    _timeoutTimer =
        Timer(const Duration(milliseconds: 3000), _onTransferComplete);
  }

  Future<void> _handleSuccess() async {
    if (!mounted) return;

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;

    await _disconnect();

    _parseAndShowData();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('傳輸完成 (EOT)'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 將數據解析並顯示在 UI 上的 helper
  void _parseAndShowData() {
    if (_dataBuffer.isEmpty) return;

    String fullData = _dataBuffer.toString();
    List<Map<String, dynamic>> parsedData =
        BleDataProcessor.parseCsvData(fullData);

    if (mounted) {
      setState(() {
        _receivedCsvLines = parsedData.map((data) {
          String info = 'ID: ${data['id']} | H: ${data['height']}m';
          if (data['metadata'] != null) {
            final meta = data['metadata'];
            if (meta['horizontal_distance'] != null)
              info += ' | HD: ${meta['horizontal_distance']}m';
          }
          return info;
        }).toList();

        _isReceiving = false;
      });
    }
  }

  void _onTransferComplete() {
    if (!mounted) return;

    // [FIX] 這是超時觸發的邏輯
    // 根據需求：如果沒有收到 EOT，這算是不完整/失敗 (或者只是超時但未確認完整)
    // 用戶說：「其他情況一律不算是成功... 基本上就是要回到掃描前的初始狀態」
    // 但如果是超時導致的斷線/停止，而沒有收到 EOT，我們應該視為失敗嗎？
    // 用戶的指令是 "傳輸過程中失敗或是中斷的所有情況... 回到掃描前的初始狀態"

    // 如果已經標記成功，就不做什麼
    if (_isTransmissionSuccess) return;

    // 如果沒有 EOT，視為中斷/失敗
    // [FIX] 執行失敗重置邏輯
    _handleFailure();
  }

  void _handleFailure() {
    if (!mounted) return;

    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _pendingHexEntries.clear();

    _disconnect();

    setState(() {
      _dataBuffer.clear();
      _receivedCsvLines.clear();
      _hexLog.clear();
      _isReceiving = false;
      _isTransmissionSuccess = false;
      _estimatedRecordCount = 0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('傳輸未完成或中斷')),
    );
  }

  /// 嘗試開啟藍牙（Android 可直接呼叫系統 API，iOS 需引導使用者）
  Future<void> _requestTurnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (e) {
      // iOS 不支援程式開啟藍牙，顯示系統設定引導
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('請開啟藍牙'),
            content: const Text('請前往系統設定開啟藍牙功能，以連接 VLGEO2 測量儀器。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('了解'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('前往設定'),
              ),
            ],
          ),
        );
      }
    }
  }

  /// 藍牙關閉/不支援時顯示的全頁面引導
  Widget _buildBluetoothOffView() {
    final bool isUnsupported =
        _adapterState == BluetoothAdapterState.unavailable;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isUnsupported
                  ? Icons.bluetooth_disabled
                  : Icons.bluetooth_disabled,
              size: 80,
              color: isUnsupported ? Colors.grey : Colors.orange,
            ),
            const SizedBox(height: 24),
            Text(
              isUnsupported ? '此裝置不支援藍牙' : '藍牙尚未開啟',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isUnsupported ? Colors.grey[700] : Colors.orange[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              isUnsupported
                  ? '需要藍牙功能才能連接 VLGEO2 測量儀器。\n請使用支援藍牙的裝置。'
                  : '請開啟藍牙以連接 VLGEO2 測量儀器並接收數據。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.grey[600]),
            ),
            if (!isUnsupported) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _requestTurnOnBluetooth,
                icon: const Icon(Icons.bluetooth),
                label: const Text('開啟藍牙'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('從儀器匯入數據'),
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
              tooltip: '斷開連接',
            )
        ],
      ),
      body: _adapterState != BluetoothAdapterState.on
          ? _buildBluetoothOffView()
          : Column(
              children: [
                // 狀態指示條
                if (_isConnecting)
                  const LinearProgressIndicator()
                else if (_isScanning)
                  const LinearProgressIndicator(),

                // 頂部操作區
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isScanning || _connectedDevice != null
                              ? null
                              : _startScan,
                          icon: const Icon(Icons.search),
                          label: Text(_isScanning ? '掃描中...' : '掃描 VLGEO 設備'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isScanning ? Colors.grey : Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_isScanning)
                        ElevatedButton(
                          onPressed: _stopScan,
                          child: const Text('停止'),
                        ),
                    ],
                  ),
                ),

                // 設備列表或數據顯示
                Expanded(
                  child:
                      (_connectedDevice != null || _receivedCsvLines.isNotEmpty)
                          ? _buildDataView()
                          : _buildScanResultList(),
                ),
              ],
            ),
    );
  }

  // 掃描結果列表 UI
  Widget _buildScanResultList() {
    if (_scanResults.isEmpty) {
      return const Center(
        child: Text('未發現設備\n請確保儀器已開啟藍牙並在附近', textAlign: TextAlign.center),
      );
    }

    return ListView.builder(
      itemCount: _scanResults.length,
      itemBuilder: (context, index) {
        final result = _scanResults[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.bluetooth, color: Colors.blue),
            title: Text(result.device.platformName.isNotEmpty
                ? result.device.platformName
                : '未知設備'),
            subtitle: Text(result.device.remoteId.toString()),
            trailing: ElevatedButton(
              onPressed: () => _connectToDevice(result.device),
              child: const Text('連接'),
            ),
          ),
        );
      },
    );
  }

  // 數據接收視圖 UI
  Widget _buildDataView() {
    // [FIX] 處理設備名稱為空的情況，優先顯示 platformName，否則顯示 remoteId
    String deviceName = '未知設備';
    if (_connectedDevice != null) {
      if (_connectedDevice!.platformName.isNotEmpty) {
        deviceName = _connectedDevice!.platformName;
      } else {
        deviceName = _connectedDevice!.remoteId.toString();
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [UX] 僅在已連接時顯示名稱 (傳輸結束若斷線則隱藏，避免顯示'未知設備')
        if (_connectedDevice != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '已連接: $deviceName',
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green),
            ),
          ),
        // [UX] 接收數據時顯示進度條動畫與 Hex Log
        if (_isReceiving)
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // [v14.0] 顯示接收狀態和記錄數
                  Row(
                    children: [
                      const Icon(Icons.sync, color: Colors.blue, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        '正在接收數據... ($_estimatedRecordCount 筆記錄)',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(), // 無限循環動畫
                  const SizedBox(height: 12),
                  const Text('即時數據流:',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: ListView.builder(
                        controller: _logScrollController,
                        itemCount: _hexLog.length,
                        itemBuilder: (context, index) {
                          return Text(
                            _hexLog[index],
                            style: const TextStyle(
                              fontFamily: 'Monospace',
                              fontSize: 12,
                              color: Colors.greenAccent,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // [v14.0] 改進的狀態顯示
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('已接收 ${_dataBuffer.length} bytes',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      Text('封包解碼中...',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
          )
        else ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('接收到的原始數據:'),
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey[100],
              ),
              child: ListView.builder(
                itemCount: _receivedCsvLines.length,
                itemBuilder: (context, index) {
                  return Text(
                    _receivedCsvLines[index],
                    style:
                        const TextStyle(fontFamily: 'Monospace', fontSize: 12),
                  );
                },
              ),
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 主要操作按鈕區
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _receivedCsvLines.isNotEmpty
                          ? () {
                              // 解析當前緩衝區的數據 (再次確保是最新的)
                              String fullData = _dataBuffer.toString();
                              List<Map<String, dynamic>> parsedData =
                                  BleDataProcessor.parseCsvData(fullData);

                              if (parsedData.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('尚未接收到有效數據')),
                                );
                                return;
                              }

                              // V3: 應用數據過濾（不完整資料 + 重複資料）
                              final filterResult =
                                  DataFilterService.filterBleData(
                                parsedData,
                                options: FilterOptions(keepIncomplete: false),
                              );

                              // 顯示過濾結果
                              if (filterResult.stats.incompleteCount > 0 ||
                                  filterResult.stats.duplicateCount > 0) {
                                _showFilterResultDialog(filterResult);
                              }

                              // 使用過濾後的資料
                              final filteredData = filterResult.validRecords;
                              if (filteredData.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('過濾後無有效數據')),
                                );
                                return;
                              }

                              // 使用 V2 批次匯入
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ManualInputPageV2(
                                      importedData: filteredData),
                                ),
                              ).then((_) {
                                _resetState();
                              });
                            }
                          : null,
                      child: Text('解析並匯入數據 (${_receivedCsvLines.length}筆)',
                          style: const TextStyle(
                              color: Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 兩階段測量選項
              Row(
                children: [
                  Expanded(
                    child: NetworkGuard(
                      message: '儲存到待測量需要網路連線',
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.camera_alt, size: 18),
                        label: const Text('儲存到待測量 (DBH 測量)'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purple,
                          side: const BorderSide(color: Colors.purple),
                        ),
                        onPressed: _receivedCsvLines.isNotEmpty
                            ? () => _showSaveToPendingDialog()
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // [UX] 新增返回按鈕，允許手動清除數據並返回掃描頁
              if (_connectedDevice == null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _dataBuffer.clear();
                            _receivedCsvLines.clear();
                            _hexLog.clear();
                            _isTransmissionSuccess = false;
                          });
                        },
                        child: const Text('清除並返回'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 顯示儲存到待測量的對話框
  void _showSaveToPendingDialog() {
    final batchNameController = TextEditingController(
      text: '測量批次 ${DateTime.now().toString().substring(0, 16)}',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('儲存到待測量任務'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '此功能將資料儲存為待測量任務，稍後使用 AR 功能測量 DBH。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: batchNameController,
              decoration: const InputDecoration(
                labelText: '批次名稱',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '共 ${_receivedCsvLines.length} 棵樹',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('儲存'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await _saveToPendingMeasurements(batchNameController.text);
            },
          ),
        ],
      ),
    );
  }

  // 儲存到待測量任務
  Future<void> _saveToPendingMeasurements(String batchName) async {
    bool loadingDialogShown = false;
    try {
      // 解析數據
      String fullData = _dataBuffer.toString();
      List<Map<String, dynamic>> parsedData =
          BleDataProcessor.parseCsvData(fullData);

      if (parsedData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('尚未接收到有效數據')),
        );
        return;
      }

      // 合併多 SEQ 記錄（3P 計算淨樹高、1P 取最後 SEQ）
      parsedData = BleDataProcessor.mergeMultiSeqRecords(parsedData);

      // [v21.0] 預覽 + 多選刪除：使用者可在過濾前手動排除不想匯入的記錄
      final pruned = await _resolveManualRowSelection(parsedData);
      if (pruned == null) return; // 使用者取消
      if (pruned.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已取消所有記錄，無資料可匯入')),
        );
        return;
      }
      parsedData = pruned;

      // V3: 應用數據過濾（不完整資料 + 重複資料）
      final filterResult = DataFilterService.filterBleData(
        parsedData,
        options: FilterOptions(keepIncomplete: false),
      );

      // 使用過濾後的資料
      final filteredData = filterResult.validRecords;

      // 如果有過濾，顯示摘要
      if (filterResult.stats.incompleteCount > 0 ||
          filterResult.stats.duplicateCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('過濾: ${filterResult.stats.incompleteCount} 筆不完整, '
                '${filterResult.stats.duplicateCount} 筆重複'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (filteredData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('過濾後無有效數據')),
        );
        return;
      }

      // [v21.0] GPS 來源辨識（batch 級別三選項）
      // 標記 metadata.gps_source = 'tree' | 'surveyor' | 'mixed_pending'
      final gpsSourceProceed = await _resolveGpsSourceForBatch(filteredData);
      if (!gpsSourceProceed) return;

      // [v21.0] 缺 GPS 處理（strict 預設擋下；lax 標記 requires_gps_fix）
      final missingGpsProceed = await _resolveMissingGps(filteredData);
      if (!missingGpsProceed) return;

      if (filteredData.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('移除缺 GPS 記錄後無有效資料')),
        );
        return;
      }

      // 區位/專案指派（4 種情境的互動 UI）
      // 對每筆 record 標註 _assigned_project_area / _assigned_project_code / _assigned_project_name
      final proceed = await _resolveBleProjectAssignment(filteredData);
      if (!proceed) {
        // 使用者取消
        return;
      }

      final surveyModeProceed = await _resolveSurveyModeForBatch(filteredData);
      if (!surveyModeProceed) return;

      if (!mounted) return;

      // 顯示載入中
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      loadingDialogShown = true;

      // 呼叫服務儲存（每筆 record 已經帶有自己的專案指派）
      final service = PendingMeasurementService();
      final result = await service.createAndUploadFromBle(
        bleData: filteredData,
        batchName: batchName,
      );

      // 關閉載入中
      if (mounted && loadingDialogShown) {
        Navigator.of(context).pop();
        loadingDialogShown = false;
      }

      if (result['success'] == true) {
        final count = result['count'] ?? filteredData.length;
        final sessionId = result['sessionId'] as String?;

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功儲存 $count 棵樹到待測量任務'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: '前往任務',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PendingMeasurementTaskPage(
                      sessionId: sessionId,
                    ),
                  ),
                );
              },
            ),
          ),
        );

        // 重置狀態
        _resetState();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('儲存失敗: ${result['message'] ?? '未知錯誤'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      // 安全關閉載入對話框（僅在確實有顯示時才 pop）
      if (mounted && loadingDialogShown) {
        Navigator.of(context).pop();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('發生錯誤: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BLE 區位/專案指派（4 種情境）
  // ─────────────────────────────────────────────────────────────────────────
  // A) 全部樹木落在同一專案邊界內 → 確認對話框 → 全部自動指派
  // B) 樹木跨多個專案 → 群組摘要 → 預設「依各自邊界指派」可改「全部指派至某專案」
  // C) 部分樹木在邊界外 → 詢問外側樹木處理（指派至主要專案 / 手動挑選 / 跳過）
  // D) 全部樹木在邊界外 → 必須由使用者手動挑選一個可存取專案
  //
  // 每筆 record 會被標註：
  //   _assigned_project_area / _assigned_project_code / _assigned_project_name
  // 若標註為 null 表示「無指派」（後端會以 NULL 存入 project_*）。
  Future<bool> _resolveBleProjectAssignment(
    List<Map<String, dynamic>> filteredData,
  ) async {
    final boundaryService = ProjectBoundaryService();
    try {
      await boundaryService.getAllBoundaries();
    } catch (e) {
      debugPrint('[BLE] 載入邊界失敗，將以「全部邊界外」處理: $e');
    }

    int outsideCount = 0;
    final Map<String, int> projectCounts = {};
    final Map<String, Map<String, String?>> projectInfo = {};

    for (final rec in filteredData) {
      final treePos = _estimateTreePosition(rec);
      final lat = treePos?.lat;
      final lon = treePos?.lon;
      if (lat == null || lon == null || lat == 0 || lon == 0) {
        outsideCount++;
        continue;
      }
      rec['_computed_tree_lat'] = lat;
      rec['_computed_tree_lon'] = lon;
      final match = boundaryService.findProjectByCoordinate(lat: lat, lng: lon);
      if (match.matched && match.projectName != null) {
        final key = match.projectName!;
        projectCounts[key] = (projectCounts[key] ?? 0) + 1;
        projectInfo[key] = {
          'name': match.projectName,
          'code': match.projectCode,
          'area': match.projectArea,
        };
        rec['_assigned_project_area'] = match.projectArea;
        rec['_assigned_project_code'] = match.projectCode;
        rec['_assigned_project_name'] = match.projectName;
      } else {
        outsideCount++;
        rec['_assigned_project_area'] = null;
        rec['_assigned_project_code'] = null;
        rec['_assigned_project_name'] = null;
      }
    }

    final total = filteredData.length;
    final matchedCount = total - outsideCount;
    final distinctProjects = projectCounts.length;

    debugPrint(
      '[BLE] 邊界匹配: total=$total matched=$matchedCount outside=$outsideCount '
      'distinctProjects=$distinctProjects',
    );

    if (!mounted) return false;

    // ── 情境 A：全部在同一專案內 ──
    if (distinctProjects == 1 && outsideCount == 0) {
      final pName = projectCounts.keys.first;
      final pInfo = projectInfo[pName]!;
      final ok = await _showSimpleAssignDialog(
        title: '自動指派專案',
        message:
            '全部 $total 棵樹皆位於專案【$pName】邊界內。\n區位：${pInfo['area'] ?? '（未設定）'}\n\n是否確認指派？',
      );
      return ok;
    }

    // ── 情境 D：全部在邊界外 ──
    if (matchedCount == 0) {
      final picked = await _showManualProjectPicker(
        title: '所有樹木皆在已知邊界外',
        message: '共 $total 棵樹未落在任何已知專案邊界內，請手動指派一個專案：',
      );
      if (picked == null) return false; // 使用者取消
      // picked == "__none__" 代表使用者選擇「不指派任何專案」
      if (picked['code'] == '__none__') {
        for (final rec in filteredData) {
          rec['_assigned_project_area'] = null;
          rec['_assigned_project_code'] = null;
          rec['_assigned_project_name'] = null;
        }
      } else {
        for (final rec in filteredData) {
          rec['_assigned_project_area'] = picked['area'];
          rec['_assigned_project_code'] = picked['code'];
          rec['_assigned_project_name'] = picked['name'];
        }
      }
      return true;
    }

    // ── 情境 B / C：跨多專案 或 部分邊界外 ──
    final action = await _showMixedAssignmentDialog(
      total: total,
      outsideCount: outsideCount,
      projectCounts: projectCounts,
      projectInfo: projectInfo,
    );
    if (action == null) return false; // 取消
    if (!mounted) return false;

    switch (action['kind']) {
      case 'per_tree':
        // 預設行為：每棵樹依自己的邊界匹配；邊界外的另外處理
        if (outsideCount > 0) {
          final outsideAction = await _showOutsideHandlingDialog(
            outsideCount: outsideCount,
            matchedProjectInfo: projectInfo,
            projectCounts: projectCounts,
          );
          if (outsideAction == null) return false;
          await _applyOutsideAction(filteredData, outsideAction);
        }
        return true;

      case 'force_one':
        // 全部指派至同一個專案（覆寫所有 record）
        final code = action['code'] as String?;
        final area = action['area'] as String?;
        final name = action['name'] as String?;
        for (final rec in filteredData) {
          rec['_assigned_project_area'] = area;
          rec['_assigned_project_code'] = code;
          rec['_assigned_project_name'] = name;
        }
        return true;
    }
    return false;
  }

  ({double lat, double lon})? _estimateTreePosition(Map<String, dynamic> rec) {
    final lat = (rec['lat'] as num?)?.toDouble();
    final lon = (rec['lon'] as num?)?.toDouble();
    if (lat == null || lon == null || lat == 0 || lon == 0) return null;

    final metadata = rec['metadata'] as Map<String, dynamic>? ?? {};
    final gpsSource = metadata['gps_source']?.toString() ?? 'surveyor';
    if (gpsSource == 'tree') {
      return (lat: lat, lon: lon);
    }

    final horizontalDistance =
        (metadata['horizontal_distance'] as num?)?.toDouble() ?? 0;
    final azimuth = (metadata['azimuth'] as num?)?.toDouble() ?? 0;
    if (horizontalDistance <= 0) return (lat: lat, lon: lon);
    return PendingTreeMeasurement.calculateTreePositionFromStation(
      stationLat: lat,
      stationLon: lon,
      horizontalDistance: horizontalDistance,
      azimuth: azimuth,
    );
  }

  Future<bool> _resolveSurveyModeForBatch(
    List<Map<String, dynamic>> filteredData,
  ) async {
    final treeService = TreeService();
    final projectTreeCache = <String, List<Map<String, dynamic>>>{};
    final candidatesByIndex = <int, List<Map<String, dynamic>>>{};
    final actions = List<String>.filled(filteredData.length, 'new');
    final targets =
        List<Map<String, dynamic>?>.filled(filteredData.length, null);

    for (var i = 0; i < filteredData.length; i++) {
      final rec = filteredData[i];
      final projectCode = rec['_assigned_project_code']?.toString();
      final treePos = _estimateTreePosition(rec);
      if (projectCode == null || projectCode.isEmpty || treePos == null) {
        continue;
      }

      final existingTrees = projectTreeCache.putIfAbsent(projectCode, () => []);
      if (existingTrees.isEmpty &&
          !projectTreeCache.containsKey('${projectCode}__loaded')) {
        final response = await treeService.getTreesByProjectCode(projectCode);
        if (!mounted) return false;
        projectTreeCache['${projectCode}__loaded'] = const [];
        if (response['success'] == true && response['data'] is List) {
          existingTrees.addAll(
            List<Map<String, dynamic>>.from(response['data'] as List),
          );
        } else {
          final message = response['message']?.toString() ?? '無法讀取既有樹木資料';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('既有樹比對失敗：$message'),
              backgroundColor: Colors.red,
            ),
          );
          return false;
        }
      }

      final candidates = existingTrees
          .map((tree) {
            final treeLat = _treeLat(tree);
            final treeLon = _treeLon(tree);
            if (treeLat == null || treeLon == null) return null;
            final distance = DataFilterService.calculateDistance(
              treePos.lat,
              treePos.lon,
              treeLat,
              treeLon,
            );
            if (distance > 10) return null;
            return {
              ...tree,
              '_distance_m': distance,
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => ((a['_distance_m'] as num).toDouble())
            .compareTo((b['_distance_m'] as num).toDouble()));

      if (candidates.isNotEmpty) {
        candidatesByIndex[i] = candidates.take(3).toList();
        targets[i] = candidates.first;
        if (((candidates.first['_distance_m'] as num?)?.toDouble() ?? 999) <=
            5) {
          actions[i] = 'maintenance';
        }
      }
    }

    if (candidatesByIndex.isEmpty) {
      for (final rec in filteredData) {
        _writeSurveyModeMetadata(rec, 'new', null, 'no_candidate');
      }
      return true;
    }

    if (!mounted) return false;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('新增 / 維護確認'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '系統依樹位座標尋找附近既有樹。請確認每筆要新增，或是維護既有樹。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ...filteredData.asMap().entries.map((entry) {
                    final i = entry.key;
                    final rec = entry.value;
                    final candidates =
                        candidatesByIndex[i] ?? const <Map<String, dynamic>>[];
                    final id = rec['id']?.toString() ?? '未知';
                    final nearest =
                        candidates.isNotEmpty ? candidates.first : null;
                    final nearestText = nearest == null
                        ? '無 10m 內既有樹'
                        : '${nearest['專案樹木'] ?? nearest['系統樹木'] ?? nearest['id']} '
                            '距離 ${((nearest['_distance_m'] as num).toDouble()).toStringAsFixed(1)}m';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ID: $id',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(nearestText,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700)),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: actions[i],
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: '處理方式',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'new',
                                child: Text('新增樹木'),
                              ),
                              if (candidates.isNotEmpty)
                                const DropdownMenuItem(
                                  value: 'maintenance',
                                  child: Text('維護既有樹'),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setLocal(() {
                                actions[i] = value;
                                if (value == 'maintenance' &&
                                    targets[i] == null &&
                                    candidates.isNotEmpty) {
                                  targets[i] = candidates.first;
                                }
                              });
                            },
                          ),
                          if (actions[i] == 'maintenance' &&
                              candidates.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: targets[i]?['id']?.toString() ??
                                  candidates.first['id']?.toString(),
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: '既有樹',
                                border: OutlineInputBorder(),
                              ),
                              items: candidates.map((tree) {
                                final treeId = tree['id']?.toString() ?? '';
                                final label =
                                    '${tree['專案樹木'] ?? tree['系統樹木'] ?? treeId} '
                                    '${tree['樹種名稱'] ?? ''} '
                                    '${((tree['_distance_m'] as num).toDouble()).toStringAsFixed(1)}m';
                                return DropdownMenuItem(
                                    value: treeId, child: Text(label));
                              }).toList(),
                              onChanged: (treeId) {
                                if (treeId == null) return;
                                setLocal(() {
                                  targets[i] = candidates.firstWhere(
                                    (tree) => tree['id']?.toString() == treeId,
                                    orElse: () => candidates.first,
                                  );
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'all_new'),
              child: const Text('全部當新增'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'ok'),
              child: const Text('確認'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return false;
    if (result == 'all_new') {
      for (final rec in filteredData) {
        _writeSurveyModeMetadata(rec, 'new', null, 'user_selected_new');
      }
      return true;
    }

    for (var i = 0; i < filteredData.length; i++) {
      final action = actions[i];
      final target = targets[i];
      final matchStatus = action == 'maintenance'
          ? 'matched_nearby_tree'
          : (candidatesByIndex.containsKey(i)
              ? 'user_selected_new'
              : 'no_candidate');
      _writeSurveyModeMetadata(
        filteredData[i],
        action,
        action == 'maintenance' ? target : null,
        matchStatus,
      );
    }
    return true;
  }

  double? _treeLat(Map<String, dynamic> tree) =>
      (tree['Y坐標'] as num?)?.toDouble() ??
      double.tryParse(tree['Y坐標']?.toString() ?? '');

  double? _treeLon(Map<String, dynamic> tree) =>
      (tree['X坐標'] as num?)?.toDouble() ??
      double.tryParse(tree['X坐標']?.toString() ?? '');

  void _writeSurveyModeMetadata(
    Map<String, dynamic> rec,
    String surveyMode,
    Map<String, dynamic>? target,
    String matchStatus,
  ) {
    final meta = rec['metadata'] as Map<String, dynamic>? ?? {};
    meta['survey_mode'] = surveyMode;
    meta['match_status'] = matchStatus;
    if (target != null) {
      meta['target_tree_id'] = target['id'];
      meta['target_project_tree_id'] = target['專案樹木'];
      meta['target_system_tree_id'] = target['系統樹木'];
    } else {
      meta.remove('target_tree_id');
      meta.remove('target_project_tree_id');
      meta.remove('target_system_tree_id');
    }
    rec['metadata'] = meta;
    rec['_survey_mode'] = surveyMode;
    rec['_target_tree_id'] = target?['id'];
    rec['_match_status'] = matchStatus;
  }

  Future<bool> _showSimpleAssignDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('確認指派'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<Map<String, dynamic>?> _showMixedAssignmentDialog({
    required int total,
    required int outsideCount,
    required Map<String, int> projectCounts,
    required Map<String, Map<String, String?>> projectInfo,
  }) async {
    if (!mounted) return null;

    // 主要專案（最多匹配的）
    final sortedEntries = projectCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('專案指派確認'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('共 $total 棵樹的邊界匹配結果：',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...sortedEntries.map((e) {
                final info = projectInfo[e.key]!;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${e.key}（區位：${info['area'] ?? '—'}）：${e.value} 棵',
                  ),
                );
              }),
              if (outsideCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• 邊界外/無 GPS：$outsideCount 棵',
                    style: const TextStyle(color: Colors.orange),
                  ),
                ),
              const Divider(height: 24),
              const Text('請選擇處理方式：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              // 全部指派至選定專案 → 二段式 dropdown
              final picked = await _showManualProjectPicker(
                title: '選擇要指派的專案',
                message: '所有 $total 棵樹將指派至此專案：',
                presetCandidates:
                    sortedEntries.map((e) => projectInfo[e.key]!).toList(),
              );
              if (picked != null && ctx.mounted) {
                Navigator.pop(ctx, {
                  'kind': 'force_one',
                  'code': picked['code'],
                  'area': picked['area'],
                  'name': picked['name'],
                });
              }
            },
            child: const Text('全部指派同一專案'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, {'kind': 'per_tree'}),
            child: const Text('每棵樹依邊界指派'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showOutsideHandlingDialog({
    required int outsideCount,
    required Map<String, Map<String, String?>> matchedProjectInfo,
    required Map<String, int> projectCounts,
  }) async {
    if (!mounted) return null;
    final dominantName =
        projectCounts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final dominantInfo = matchedProjectInfo[dominantName]!;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('邊界外樹木處理'),
        content: Text(
          '有 $outsideCount 棵樹位於已知專案邊界外，要如何處理？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {'kind': 'leave_unassigned'}),
            child: const Text('保留為無指派'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, {
              'kind': 'assign_to',
              'code': dominantInfo['code'],
              'area': dominantInfo['area'],
              'name': dominantInfo['name'],
            }),
            child: Text('併入主要專案\n($dominantName)', textAlign: TextAlign.center),
          ),
          ElevatedButton(
            onPressed: () async {
              final picked = await _showManualProjectPicker(
                title: '選擇邊界外樹木的專案',
                message: '$outsideCount 棵邊界外樹木將指派至：',
              );
              if (picked != null && ctx.mounted) {
                Navigator.pop(ctx, {
                  'kind': 'assign_to',
                  'code': picked['code'],
                  'area': picked['area'],
                  'name': picked['name'],
                });
              }
            },
            child: const Text('挑選其他專案'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyOutsideAction(
    List<Map<String, dynamic>> filteredData,
    Map<String, dynamic> action,
  ) async {
    if (action['kind'] == 'leave_unassigned') {
      // 已經是 null 指派，無需動作
      return;
    }
    if (action['kind'] == 'assign_to') {
      final code = action['code'] as String?;
      if (code == '__none__') return;
      final area = action['area'] as String?;
      final name = action['name'] as String?;
      for (final rec in filteredData) {
        if (rec['_assigned_project_code'] == null &&
            rec['_assigned_project_name'] == null) {
          rec['_assigned_project_area'] = area;
          rec['_assigned_project_code'] = code;
          rec['_assigned_project_name'] = name;
        }
      }
    }
  }

  /// [v21.0] GPS 來源辨識（batch 級別三選項）
  /// 寫入每筆 record metadata.gps_source 欄位
  /// - 'tree'：GPS 是樹位置（測員站樹下）
  /// - 'surveyor'：GPS 是測員位置（用 HD/AZ 偏移計算樹位置，下游需處理）
  /// - 'mixed_pending'：混合情況，下游需互動標記每筆
  /// 回傳 false 代表使用者取消整個流程
  Future<bool> _resolveGpsSourceForBatch(
    List<Map<String, dynamic>> filteredData,
  ) async {
    final hasGpsCount = filteredData.where((r) => r['hasGps'] == true).length;
    if (hasGpsCount == 0) {
      // 全部無 GPS，跳過此 dialog（後續 _resolveMissingGps 會處理）
      return true;
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('GPS 定位來源'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('共 $hasGpsCount 筆有 GPS 座標。請確認測量時 GPS 紀錄的是：',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '儀器原始設計：GPS = 操作員（按 SEND 當下儀器位置）。'
                '若採取「站樹下測量」工作流，則 GPS = 樹位置。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.park, color: Colors.green),
                title: const Text('全部都是樹位置'),
                subtitle: const Text('測員走到每棵樹下後再按 SEND 紀錄'),
                onTap: () => Navigator.pop(ctx, 'tree'),
              ),
              ListTile(
                leading:
                    const Icon(Icons.person_pin_circle, color: Colors.blue),
                title: const Text('全部都是測員站位'),
                subtitle: const Text('使用 HD + 方位角計算樹的實際位置'),
                onTap: () => Navigator.pop(ctx, 'surveyor'),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.orange),
                title: const Text('混合 / 不確定'),
                subtitle: const Text('進入後續流程逐筆檢視（標記為 pending）'),
                onTap: () => Navigator.pop(ctx, 'mixed_pending'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消整個匯入'),
          ),
        ],
      ),
    );

    if (result == null) return false;

    if (result == 'mixed_pending') {
      return _resolveMixedGpsSourcePerRecord(filteredData);
    }

    for (final rec in filteredData) {
      final meta = rec['metadata'] as Map<String, dynamic>? ?? {};
      meta['gps_source'] = result;
      rec['metadata'] = meta;
    }
    return true;
  }

  Future<bool> _resolveMixedGpsSourcePerRecord(
    List<Map<String, dynamic>> filteredData,
  ) async {
    final gpsRows =
        filteredData.where((r) => r['hasGps'] == true).toList(growable: false);
    if (gpsRows.isEmpty) return true;

    final selections = <Map<String, dynamic>, String>{
      for (final rec in gpsRows) rec: 'surveyor',
    };

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('逐筆確認 GPS 來源'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '請依每筆紀錄按 SEND 時人的位置選擇。預設為測站。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  ...gpsRows.map((rec) {
                    final meta = rec['metadata'] as Map<String, dynamic>? ?? {};
                    final id = rec['id']?.toString() ?? '未知';
                    final type = rec['type']?.toString() ?? '';
                    final hd =
                        (meta['horizontal_distance'] as num?)?.toDouble();
                    final az = (meta['azimuth'] as num?)?.toDouble();
                    final subtitle = [
                      if (type.isNotEmpty) type,
                      if (hd != null) 'HD ${hd.toStringAsFixed(1)}m',
                      if (az != null) 'AZ ${az.toStringAsFixed(0)}°',
                    ].join('  ');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ID: $id',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            if (subtitle.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(subtitle,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              initialValue: selections[rec],
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'GPS 來源',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'surveyor',
                                  child: Text('測站位置：按 SEND 時人在測量站位'),
                                ),
                                DropdownMenuItem(
                                  value: 'tree',
                                  child: Text('樹木位置：按 SEND 時人在樹下'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setLocal(() => selections[rec] = value);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('確認'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return false;
    for (final rec in gpsRows) {
      final meta = rec['metadata'] as Map<String, dynamic>? ?? {};
      meta['gps_source'] = selections[rec];
      rec['metadata'] = meta;
    }
    return true;
  }

  /// [v21.0] 預覽 + 多選刪除：解析後讓使用者勾選要匯入的記錄
  ///
  /// 回傳 null = 取消整個匯入；空 List = 全部不要；否則 = 使用者保留的 records
  Future<List<Map<String, dynamic>>?> _resolveManualRowSelection(
    List<Map<String, dynamic>> parsedData,
  ) async {
    if (parsedData.isEmpty) return parsedData;

    // 預設全部勾選
    final selected = List<bool>.filled(parsedData.length, true);

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final selectedCount = selected.where((v) => v).length;
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.checklist, color: Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('匯入預覽（$selectedCount / ${parsedData.length}）')),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.select_all, size: 18),
                        label: const Text('全選'),
                        onPressed: () {
                          setLocal(() {
                            for (var i = 0; i < selected.length; i++) {
                              selected[i] = true;
                            }
                          });
                        },
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.deselect, size: 18),
                        label: const Text('全不選'),
                        onPressed: () {
                          setLocal(() {
                            for (var i = 0; i < selected.length; i++) {
                              selected[i] = false;
                            }
                          });
                        },
                      ),
                      const Spacer(),
                      const Text(
                        '取消勾選 = 不匯入',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: parsedData.length,
                      itemBuilder: (_, i) {
                        final rec = parsedData[i];
                        final id = rec['id']?.toString() ?? '?';
                        final type = (rec['type'] ?? '').toString();
                        final hd =
                            (rec['horizontalDistance'] as num?)?.toDouble();
                        final az = (rec['azimuth'] as num?)?.toDouble();
                        final h = (rec['height'] as num?)?.toDouble();
                        final dbh = (rec['dbh'] as num?)?.toDouble();
                        final hasGps = rec['hasGps'] == true;
                        final summary = StringBuffer();
                        if (h != null) {
                          summary.write('H=${h.toStringAsFixed(1)}m  ');
                        }
                        if (dbh != null) {
                          summary.write('DBH=${dbh.toStringAsFixed(1)}cm  ');
                        }
                        if (hd != null) {
                          summary.write('HD=${hd.toStringAsFixed(1)}m  ');
                        }
                        if (az != null) {
                          summary.write('AZ=${az.toStringAsFixed(0)}°');
                        }
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: selected[i],
                          onChanged: (v) {
                            setLocal(() => selected[i] = v ?? false);
                          },
                          title: Row(
                            children: [
                              Text('ID: $id',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              if (type.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: type == 'DME'
                                        ? Colors.blue.shade50
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(type,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              const SizedBox(width: 6),
                              if (!hasGps)
                                const Icon(Icons.location_off,
                                    size: 14, color: Colors.deepOrange),
                            ],
                          ),
                          subtitle: Text(
                            summary.toString(),
                            style: const TextStyle(fontSize: 11),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消匯入'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('繼續（$selectedCount 筆）'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return null;
    final kept = <Map<String, dynamic>>[];
    for (var i = 0; i < parsedData.length; i++) {
      if (selected[i]) kept.add(parsedData[i]);
    }
    return kept;
  }

  /// [v21.0] 缺 GPS 處理：strict（預設）/ lax（保留並標記 requires_gps_fix）
  /// 回傳 false 代表使用者取消
  Future<bool> _resolveMissingGps(
    List<Map<String, dynamic>> filteredData,
  ) async {
    final missing = filteredData.where((r) => r['hasGps'] != true).toList();
    if (missing.isEmpty) return true;

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.location_off, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('缺 GPS 處理'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${missing.length} 筆記錄缺少 GPS 座標。',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                '處理方式：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                '• 嚴格模式：直接移除這些記錄，並提示請使用儀器補測。\n'
                '• 寬鬆模式：保留並標記為「需補 GPS」，匯入後在地圖上手動點選座標，'
                '或之後用儀器補測時對應 pending ID。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              const Text(
                '⚠ 不會自動套用上一筆/中位數座標（避免錯誤位置）。',
                style: TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'strict'),
            child: const Text('嚴格（移除）'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'lax'),
            child: const Text('寬鬆（保留標記）'),
          ),
        ],
      ),
    );

    if (action == null) return false;

    if (action == 'strict') {
      filteredData.removeWhere((r) => r['hasGps'] != true);
    } else if (action == 'lax') {
      for (final rec in missing) {
        final meta = rec['metadata'] as Map<String, dynamic>? ?? {};
        meta['requires_gps_fix'] = true;
        rec['metadata'] = meta;
      }
      // 顯示補測流程指引
      await _showRetestGuide(missing.length);
    }
    return true;
  }

  /// [v21.0] 顯示「使用儀器補測 GPS」標準流程指引
  Future<void> _showRetestGuide(int count) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.help_outline, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(child: Text('儀器補測 GPS 流程')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '已標記 $count 筆需補測 GPS。請依以下步驟使用 VLGEO2 儀器補測：',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('1. 清除儀器舊資料：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  'SETTINGS → MEMORY → FORMAT（清空 DATA.CSV，避免新舊混淆）',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              const Text('2. 啟用 GPS：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  'SETTINGS → GPS → USE GPS ✓，等待 HDOP < 3 才開始測',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              const Text('3. 走到第一棵待補樹下測量。',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('4. 輸入 5 位 ID 對齊 pending：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  '測完後儀器跳出 5 位 ID 輸入，輸入 = pending ID（不足前面補 0）。\n'
                  '例：pending ID 42 → 輸入 00042',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              const Text('5. 全部測完後回傳：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const Padding(
                padding: EdgeInsets.only(left: 12, top: 2),
                child: Text(
                  'FILES → SEND 透過 BLE 回傳，或 USB 拷 DATA.CSV',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Text(
                  '⚠ 補測結果以 ID 對齊覆蓋 pending 記錄（座標、HD、AZ）。\n'
                  '請確認 ID 輸入正確，否則會覆寫到錯誤的樹。',
                  style: TextStyle(fontSize: 12, color: Colors.brown),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  /// 載入 BLE 手動指派用的專案清單（GET /projects 回傳 `data`，非 `projects`）
  Future<List<Map<String, String?>>> _loadBleProjectPickerCandidates() async {
    final seen = <String>{};
    final out = <Map<String, String?>>[];

    void addFromMap(Map p) {
      final code = (p['code'] ?? p['project_code'])?.toString();
      if (code == null || code.isEmpty || seen.contains(code)) return;
      seen.add(code);
      out.add({
        'code': code,
        'area': (p['area'] ?? p['area_name'] ?? p['project_area'])?.toString(),
        'name': (p['name'] ?? p['project_name'])?.toString(),
      });
    }

    try {
      final resp = await ProjectService().getProjects(forceRefresh: true);
      if (resp['success'] == true && resp['data'] is List) {
        for (final p in resp['data'] as List) {
          if (p is Map) addFromMap(Map<String, dynamic>.from(p));
        }
      }
    } catch (e) {
      debugPrint('[BLE] 載入專案清單失敗: $e');
    }

    if (out.isEmpty) {
      try {
        for (final p in await AuthService.getAccessibleProjectDetails()) {
          addFromMap(p);
        }
      } catch (e) {
        debugPrint('[BLE] 登入專案 fallback 失敗: $e');
      }
    }

    debugPrint('[BLE] 可選專案數: ${out.length}');
    return out;
  }

  /// 手動專案挑選對話框
  /// 回傳 {'code','area','name'}；'__none__' 代表「不指派」；null 代表取消
  Future<Map<String, String?>?> _showManualProjectPicker({
    required String title,
    required String message,
    List<Map<String, String?>>? presetCandidates,
  }) async {
    if (!mounted) return null;

    // 載入可存取專案
    List<Map<String, String?>> candidates =
        presetCandidates != null ? List.of(presetCandidates) : [];
    if (candidates.isEmpty) {
      candidates.addAll(await _loadBleProjectPickerCandidates());
    }

    if (!mounted) return null;

    String? selectedKey;
    return showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setStateDialog) => AlertDialog(
            title: Text(title),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message),
                  const SizedBox(height: 12),
                  if (candidates.isEmpty)
                    const Text(
                      '（無可選擇的專案）\n'
                      '可能原因：帳號尚未被指派專案權限，或專案清單載入失敗。\n'
                      '請請業務管理員在後台將您的帳號加入 user_projects，'
                      '或重新登入後再試；仍無法選擇時請先取消匯入。',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    )
                  else
                    DropdownButton<String>(
                      isExpanded: true,
                      hint: const Text('選擇專案…'),
                      value: selectedKey,
                      items: [
                        const DropdownMenuItem<String>(
                          value: '__none__',
                          child: Text('— 不指派任何專案 —'),
                        ),
                        ...candidates.map((c) {
                          final key = c['code'] ?? c['name'] ?? '';
                          return DropdownMenuItem<String>(
                            value: key,
                            child: Text(
                              '${c['name'] ?? '(未命名)'}'
                              '${c['area'] != null && c['area']!.isNotEmpty ? '（${c['area']}）' : ''}',
                            ),
                          );
                        }),
                      ],
                      onChanged: (v) => setStateDialog(() => selectedKey = v),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: selectedKey == null
                    ? null
                    : () {
                        if (selectedKey == '__none__') {
                          Navigator.pop(ctx, {
                            'code': '__none__',
                            'area': null,
                            'name': null,
                          });
                        } else {
                          final picked = candidates.firstWhere(
                            (c) =>
                                (c['code'] ?? c['name'] ?? '') == selectedKey,
                            orElse: () => {},
                          );
                          Navigator.pop(ctx, picked);
                        }
                      },
                child: const Text('確認'),
              ),
            ],
          ),
        );
      },
    );
  }
}
