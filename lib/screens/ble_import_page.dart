import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_data_processor.dart'; // 引入解析器
import '../services/ble_packet_decoder.dart'; // 引入封包解碼器
import '../services/pending_measurement_service.dart'; // 待測量服務
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
  // 狀態變數
  bool _isScanning = false;
  // V2 批次匯入模式（V1 已退役）
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  bool _isReceiving = false;

  // 數據緩衝區
  final StringBuffer _dataBuffer = StringBuffer();
  final List<String> _hexLog = []; // [UX] 用於顯示即時 Hex 數據流
  List<String> _receivedCsvLines = [];
  bool _isTransmissionSuccess = false; // [FIX] 追蹤傳輸是否成功
  int _estimatedRecordCount = 0; // [v14.0] 即時記錄數統計

  // 關鍵 UUID (Nordic UART Service)
  final String _serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String _txCharacteristicUuid =
      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // 接收數據 (Notify)

  // [FIX] EOT 訊號: 0x5A (Z), 0xBF, 0xFB
  final List<int> _eotSignal = [0x5A, 0xBF, 0xFB];
  // final String _rxCharacteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // 發送指令 (Write) - 這次不需要

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;
  Timer? _timeoutTimer;
  final ScrollController _logScrollController = ScrollController(); // [UX] 自動捲動

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    // 確保在頁面銷毀前停止掃描並斷開連接
    // [FIX] 避免在 dispose 中呼叫 setState
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();

    // 使用 unawaited 確保不會阻塞 UI 銷毀，但會執行斷線
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

  // [FIX] 強制重置所有狀態，防止重入崩潰
  void _resetState() {
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
        _estimatedRecordCount = 0; // [v14.0] 重置記錄數統計
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
              
              if (stats.missingFieldCounts.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('缺失欄位:', style: TextStyle(fontWeight: FontWeight.bold)),
                ...stats.missingFieldCounts.entries.map((e) => 
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• ${e.key}: ${e.value} 筆'),
                  ),
                ),
              ],
              
              // 顯示衝突詳情
              if (result.conflicts.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('衝突詳情 (${result.conflicts.length}):', 
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                ...result.conflicts.take(3).map((c) => 
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• 座標: ${c.lat.toStringAsFixed(6)}, ${c.lon.toStringAsFixed(6)}', 
                          style: const TextStyle(fontSize: 12)),
                        Text('  衝突欄位: ${c.conflictingFields.keys.join(", ")}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                        Text('  保留記錄: ${c.keptRecord['id']}',
                          style: TextStyle(fontSize: 11, color: Colors.green[700])),
                      ],
                    ),
                  ),
                ),
                if (result.conflicts.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('... 還有 ${result.conflicts.length - 3} 組衝突',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ),
              ],
              
              if (stats.duplicateGroups.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('重複群組 (${stats.duplicateGroups.length}):', 
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                ...stats.duplicateGroups.take(5).map((g) => 
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('• $g', style: const TextStyle(fontSize: 12)),
                  ),
                ),
                if (stats.duplicateGroups.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Text('... 還有 ${stats.duplicateGroups.length - 5} 組',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
              color: color.withOpacity(0.1),
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

      // 監聽掃描結束
      FlutterBluePlus.isScanning.listen((isScanning) {
        if (!mounted) return; // [FIX] 確保 Widget 還在掛載中

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

        // 監聯數據流
        _dataSubscription = txCharacteristic.lastValueStream.listen((value) {
          _processReceivedData(value);
        });

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

  // 5. 數據處理 (Task 5: 緩衝區優化與拼接)
  void _processReceivedData(List<int> data) {
    // [DEBUG] 輸出原始 HEX 數據，以診斷亂碼問題
    // 將 List<int> 轉換為 HEX 字串 (e.g., "5A BF FB")
    final hexString = data
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    print('[BLE RAW] len=${data.length} $hexString');

    // [UX] 更新 Hex Log (只保留最後 50 行以節省資源)
    // [FIX] 檢查 mounted 再調用 setState
    if (mounted) {
      setState(() {
        _hexLog.add('(${data.length}) $hexString');
        if (_hexLog.length > 50) {
          _hexLog.removeAt(0);
        }
      });
    }
    // 自動捲動到底部
    if (_logScrollController.hasClients) {
      _logScrollController
          .jumpTo(_logScrollController.position.maxScrollExtent);
    }

    // [FIX] 檢查是否為傳輸結束訊號
    // 先進行簡單的 listEquals 檢查 (雖然 listEquals 需要 collection 包，這裡手動比對比較快)
    if (data.length == 3 &&
        data[0] == _eotSignal[0] &&
        data[1] == _eotSignal[1] &&
        data[2] == _eotSignal[2]) {
      // 偵測到 EOT 訊號
      print('偵測到 EOT 訊號，傳輸成功。');
      _isTransmissionSuccess = true;
      // 停止超時檢測 (因為已經明確結束)
      _timeoutTimer?.cancel();
      // 列印封包解碼統計
      BlePacketDecoder.printStats();
      // 觸發成功處理邏輯
      _handleSuccess();
      return;
    }

    // [v14.0] 使用協議級封包解碼器
    // 基於 VLGEO2 BLE 協議深度分析：
    // - 正常封包 (20 bytes): 保留全部
    // - 殘留封包 (5 bytes): 只保留前 3 bytes (後 2 bytes 是雜訊)
    // - 標記封包 (20 bytes, 以 44 xx 00 開頭): 跳過前 3 bytes
    List<int> decodedData = BlePacketDecoder.decodePacket(data);

    // 1. 解碼 - 使用解碼後的 byte 陣列
    String rawChunk;
    try {
      rawChunk = utf8.decode(decodedData);
    } catch (e) {
      rawChunk = String.fromCharCodes(decodedData);
    }

    // 2. 字串級白名單過濾 (最後一道防線)
    // VLGEO CSV 實際使用的字元 (基於 DATA_2.CSV 分析)：
    // - 數字: 0-9
    // - 分隔符: ; (分號)
    // - 數值符號: . (小數點), - (負號)
    // - 標記符號: $ (資料行), # (設定行)
    // - 座標方向: N, S, E, W
    // - 測量類型: P, Q, R, D, M
    // - Header 關鍵字: MARK, STATUS, TYPE, SET... (都是大寫英文字母)
    // - 換行: \r\n
    // [CRITICAL] 移除小寫字母、括號、斜線等非標準字元
    String cleanChunk =
        rawChunk.replaceAll(RegExp(r'[^0-9A-Z\.\;\-\r\n\$\#]'), '');

    // [DEBUG] 如果清洗後內容有變，印出差異
    if (rawChunk != cleanChunk) {
      print('[BLE CLEANED] "$rawChunk" -> "$cleanChunk"');
    }

    // 3. 寫入緩衝區
    _dataBuffer.write(cleanChunk);

    // [v14.0] 即時統計記錄數 (以 '$;' 開頭的行數)
    // 這是一個簡單的估算，實際數量以最終解析為準
    String bufferContent = _dataBuffer.toString();
    int recordCount = RegExp(r'\$;').allMatches(bufferContent).length;
    if (recordCount != _estimatedRecordCount && mounted) {
      setState(() {
        _estimatedRecordCount = recordCount;
      });
    }

    // 4. 超時檢測 (Silence Timeout)
    // 如果 3000 毫秒內沒有收到新數據，假設傳輸結束
    // [FIX] 僅當未成功時才依賴超時
    if (!_isTransmissionSuccess) {
      _resetTimeoutTimer();
    }
  }

  void _resetTimeoutTimer() {
    _timeoutTimer?.cancel();
    // [OPT] 縮短超時時間至 3000ms，加快反應速度
    _timeoutTimer =
        Timer(const Duration(milliseconds: 3000), _onTransferComplete);
  }

  // [FIX] 專門處理 EOT 成功情況
  void _handleSuccess() {
    if (!mounted) return;

    // 觸發斷線 (優雅斷開)
    // 注意：這裡呼叫 _disconnect，但我們需要確保它不會清除數據
    _disconnect();

    // 處理接收到的數據以供顯示
    _parseAndShowData();

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

    // 斷開連接
    _disconnect();

    // 清除數據 (回到掃描前的初始狀態)
    setState(() {
      _dataBuffer.clear();
      _receivedCsvLines.clear();
      _hexLog.clear();
      _isReceiving = false;
      _isTransmissionSuccess = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('傳輸未完成或中斷')),
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
      body: Column(
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
                      backgroundColor: _isScanning ? Colors.grey : Colors.blue,
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
            child: (_connectedDevice != null || _receivedCsvLines.isNotEmpty)
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
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text('封包解碼中...',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
                              final filterResult = DataFilterService.filterBleData(
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
                                  builder: (context) =>
                                      ManualInputPageV2(importedData: filteredData),
                                ),
                              ).then((_) {
                                _resetState();
                              });
                            }
                          : null,
                      child: Text(
                          '解析並匯入數據 (${_receivedCsvLines.length}筆)',
                          style: const TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold)),
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
            content: Text(
              '過濾: ${filterResult.stats.incompleteCount} 筆不完整, '
              '${filterResult.stats.duplicateCount} 筆重複'
            ),
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

      // 顯示載入中
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
        loadingDialogShown = true;
      }

      // 嘗試根據第一棵樹的 GPS 座標自動匹配專案
      String? autoProjectArea;
      String? autoProjectCode;
      String? autoProjectName;
      try {
        final firstTree = filteredData.first;
        final lat = double.tryParse(firstTree['latitude']?.toString() ?? '');
        final lon = double.tryParse(firstTree['longitude']?.toString() ?? '');
        if (lat != null && lon != null && lat != 0 && lon != 0) {
          final boundaryService = ProjectBoundaryService();
          await boundaryService.getAllBoundaries(); // 確保快取已載入
          final matchResult = boundaryService.findProjectByCoordinate(lat: lat, lng: lon);
          if (matchResult.matched) {
            autoProjectName = matchResult.projectName;
            autoProjectCode = matchResult.projectCode;
            debugPrint('[BLE] 自動匹配專案: $autoProjectName ($autoProjectCode)');
          }
        }
      } catch (e) {
        debugPrint('[BLE] 專案自動匹配失敗（不影響儲存）: $e');
      }

      // 呼叫服務儲存（使用過濾後的資料，附帶自動匹配的專案資訊）
      final service = PendingMeasurementService();
      final result = await service.createAndUploadFromBle(
        bleData: filteredData,
        batchName: batchName,
        projectArea: autoProjectArea,
        projectCode: autoProjectCode,
        projectName: autoProjectName,
      );

      // 關閉載入中
      if (mounted && loadingDialogShown) {
        Navigator.of(context).pop();
        loadingDialogShown = false;
      }

      if (result['success'] == true) {
        final count = result['count'] ?? filteredData.length;
        final sessionId = result['sessionId'] as String?;
        
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
}
