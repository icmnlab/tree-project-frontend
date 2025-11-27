import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ble_data_processor.dart'; // 引入解析器
import 'manual_input_page.dart'; // 引入手動補全頁面

class BleImportPage extends StatefulWidget {
  const BleImportPage({super.key});

  @override
  State<BleImportPage> createState() => _BleImportPageState();
}

class _BleImportPageState extends State<BleImportPage> {
  // 狀態變數
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  bool _isReceiving = false;

  // 數據緩衝區
  final StringBuffer _dataBuffer = StringBuffer();
  final List<String> _hexLog = []; // [UX] 用於顯示即時 Hex 數據流
  List<String> _receivedCsvLines = [];
  bool _isTransmissionSuccess = false; // [FIX] 追蹤傳輸是否成功

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
      });
    }
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

        // [FIX] 檢查 mounted 再調用 setState
        if (mounted) {
          setState(() {
            _isReceiving = true;
            _dataBuffer.clear(); // 清空緩衝區
            _receivedCsvLines.clear();
            _hexLog.clear(); // 清空 Hex Log
          });
        }

        // 監聽數據流
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
    print('[BLE RAW] $hexString'); // 這樣我們就能看到儀器真正傳了什麼

    // [UX] 更新 Hex Log (只保留最後 50 行以節省資源)
    // [FIX] 檢查 mounted 再調用 setState
    if (mounted) {
      setState(() {
        _hexLog.add(hexString);
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
      // 觸發成功處理邏輯
      _handleSuccess();
      return;
    }

    // [v13.5+ ENHANCED] Byte-Level PacketLogger 雜訊過濾器 (兩階段)
    // 基於 serial_20251125_200547(DATA_2).txt 的完整 Hex 分析
    // 以及 trace_final_3_hex.py 的原始 Hex 追蹤
    //
    // PacketLogger 雜訊特徵 (完整破解)：
    // 1. 固定封包頭：0x44 0xCD 0x00, 0x44 0x36 0x00, 0x44 0x86 0x00
    // 2. 配對雜訊：Non-ASCII + ASCII 組合 (例如 0xEE 0x35 → '簾5')
    //    - 關鍵發現 (ID=10031)：配對雜訊可出現在**任何位置**，不限於封包頭前
    //    - 決定性案例：31 3B 31 [EE 35] → "1;1簾5" → SEQ 從 '1' 變成 '15'
    // 3. 字母殘留：封包頭第一個 byte 0x44 ('D') 單獨出現
    // 4. 數字重複：封包邊界 + 雜訊導致數字切分重複
    //
    // 策略：兩階段清理
    //   Stage 1: 封包頭檢測 + 回溯配對清理 (v13.1 原有)
    //   Stage 2: 全域配對雜訊清理 (v13.2 新增，關鍵突破)

    // === Stage 1: 封包頭檢測 + 回溯配對清理 ===
    List<int> stage1Cleaned = [];
    int i = 0;
    while (i < data.length) {
      // 偵測 PacketLogger 封包頭
      bool isPacketLoggerHeader = false;
      int headerLength = 0;

      // 檢測三種已知封包頭
      if (i + 2 < data.length && data[i] == 0x44) {
        if (data[i + 1] == 0xCD && data[i + 2] == 0x00) {
          isPacketLoggerHeader = true;
          headerLength = 3;
        } else if (data[i + 1] == 0x36 && data[i + 2] == 0x00) {
          isPacketLoggerHeader = true;
          headerLength = 3;
        } else if (data[i + 1] == 0x86 && data[i + 2] == 0x00) {
          // 在 old_data 中發現的第三種封包頭
          isPacketLoggerHeader = true;
          headerLength = 3;
        }
      }

      if (isPacketLoggerHeader) {
        // [CRITICAL] 回溯清理：檢查前 2-3 個 bytes 是否為雜訊對
        // 移除已經加入 stage1Cleaned 的最後 2 個 bytes (如果它們是 Non-ASCII)
        if (stage1Cleaned.length >= 2) {
          // 檢查最後 2 個 bytes
          if (stage1Cleaned[stage1Cleaned.length - 1] > 0x7E ||
              stage1Cleaned[stage1Cleaned.length - 2] > 0x7E) {
            stage1Cleaned.removeLast();
            stage1Cleaned.removeLast();
          }
        } else if (stage1Cleaned.length == 1 && stage1Cleaned.last > 0x7E) {
          stage1Cleaned.removeLast();
        }

        i += headerLength; // 跳過封包頭本身
        continue;
      }

      // 獨立的 Non-ASCII byte (保留換行符)
      if (data[i] > 0x7E && data[i] != 0x0D && data[i] != 0x0A) {
        i++;
        continue;
      }

      // 保留正常 byte
      stage1Cleaned.add(data[i]);
      i++;
    }

    // === Stage 2: 全域配對雜訊清理 (v13.2 關鍵突破) ===
    // 掃描整個數據流，移除所有「Non-ASCII + ASCII」配對
    // 關鍵：不限位置（這是與 v13.1 的本質差異）
    //
    // 決定性案例 (ID=10031)：
    //   31 3B 31 [EE 35] → "1;1[簾]5"
    //   配對雜訊 0xEE 0x35 在數據流中間，導致 SEQ '1' → '15'
    List<int> stage2Cleaned = [];
    int j = 0;

    while (j < stage1Cleaned.length) {
      int currentByte = stage1Cleaned[j];

      // 檢測 Non-ASCII（非換行符）
      if (currentByte > 0x7E && currentByte != 0x0D && currentByte != 0x0A) {
        // 檢查下一個 byte 是否為 ASCII 可見字元
        if (j + 1 < stage1Cleaned.length) {
          int nextByte = stage1Cleaned[j + 1];
          if (nextByte >= 0x20 && nextByte <= 0x7E) {
            // 配對雜訊！兩個都移除
            // 例如：0xEE 0x35 → '簾' '5'
            j += 2;
            continue;
          }
        }
        // 獨立的 Non-ASCII，移除
        j++;
        continue;
      }

      // 保留正常 byte
      stage2Cleaned.add(currentByte);
      j++;
    }

    List<int> cleanedData = stage2Cleaned;

    // 1. 解碼 (混合策略) - 使用清洗後的 byte 陣列
    String rawChunk;
    try {
      rawChunk = utf8.decode(cleanedData);
    } catch (e) {
      rawChunk = String.fromCharCodes(cleanedData);
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
    } else {
      // print('[BLE OK] "$cleanChunk"');
    }

    // 3. 寫入緩衝區
    _dataBuffer.write(cleanChunk);

    // 3. 即時更新 UI 顯示原始數據 (可選，僅用於調試)
    // 這裡我們不直接更新 _receivedCsvLines，而是等傳輸結束或偵測到換行時才處理

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
                  const Text('正在接收數據...', style: TextStyle(color: Colors.blue)),
                  const SizedBox(height: 4),
                  const LinearProgressIndicator(), // 無限循環動畫
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 4),
                  Text('已接收 ${_dataBuffer.length} bytes',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
          child: Row(
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

                          // 導航到手動補全頁面，並在返回後重置狀態
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  ManualInputPage(importedData: parsedData),
                            ),
                          ).then((_) {
                            // [FIX] 從手動頁面返回時，重置所有狀態，防止殘留數據導致的崩潰
                            _resetState();
                          });
                        }
                      : null,
                  child: Text('解析並匯入數據 (${_receivedCsvLines.length}筆)'),
                ),
              ),
              // [UX] 新增返回按鈕，允許手動清除數據並返回掃描頁
              if (_connectedDevice == null) ...[
                const SizedBox(width: 8),
                OutlinedButton(
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
              ],
            ],
          ),
        ),
      ],
    );
  }
}
