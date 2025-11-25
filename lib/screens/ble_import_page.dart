import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../widgets/loading_indicator.dart';

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
  List<String> _receivedCsvLines = [];

  // 關鍵 UUID (Nordic UART Service)
  final String _serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  final String _txCharacteristicUuid =
      "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // 接收數據 (Notify)
  // final String _rxCharacteristicUuid = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // 發送指令 (Write) - 這次不需要

  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _dataSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  @override
  void dispose() {
    _stopScan();
    _disconnect();
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

  // 2. 掃描設備
  Future<void> _startScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _scanResults.clear();
    });

    try {
      // 開始掃描
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // 監聽掃描結果
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            // 過濾設備：只顯示有名稱且名稱包含 Vertex 或 VLGEO 的設備
            // 或者如果測試設備名稱不同，可以調整這裡
            _scanResults = results.where((r) {
              final name = r.device.platformName.toUpperCase();
              return name.isNotEmpty &&
                  (name.contains('VERTEX') || name.contains('VLGEO'));
            }).toList();
          });
        }
      });

      // 監聽掃描結束
      FlutterBluePlus.isScanning.listen((isScanning) {
        if (mounted) {
          setState(() {
            _isScanning = isScanning;
          });
        }
      });
    } catch (e) {
      print('掃描錯誤: $e');
      setState(() => _isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('掃描失敗: $e')),
        );
      }
    }
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    setState(() => _isScanning = false);
  }

  // 3. 連接設備與發現服務
  Future<void> _connectToDevice(BluetoothDevice device) async {
    _stopScan(); // 連接前停止掃描

    setState(() {
      _isConnecting = true;
    });

    try {
      // 使用 autoConnect: false 確保連接行為穩定
      await device.connect(autoConnect: false);

      if (mounted) {
        setState(() {
          _connectedDevice = device;
          _isConnecting = false;
        });
      }

      // 監聽連接狀態
      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          if (mounted) {
            setState(() {
              _connectedDevice = null;
              _isReceiving = false;
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
      setState(() {
        _isConnecting = false;
        _connectedDevice = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('連接失敗: $e')),
        );
      }
    }
  }

  void _disconnect() {
    _connectedDevice?.disconnect();
    _connectionSubscription?.cancel();
    _dataSubscription?.cancel();
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

        setState(() {
          _isReceiving = true;
          _dataBuffer.clear(); // 清空緩衝區
          _receivedCsvLines.clear();
        });

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

  // 5. 數據處理
  void _processReceivedData(List<int> data) {
    // 將 bytes 轉換為字串 (假設是 UTF-8 或 ASCII)
    String chunk = utf8.decode(data, allowMalformed: true);
    _dataBuffer.write(chunk);

    // 嘗試分割成行
    String bufferContent = _dataBuffer.toString();
    if (bufferContent.contains('\n')) {
      List<String> lines = const LineSplitter().convert(bufferContent);

      // 如果最後一行不完整 (沒有換行符)，保留到緩衝區
      // LineSplitter 會吃掉換行符，所以我們比較簡單的做法是：
      // 檢查最後接收到的 chunk 是否以換行結尾

      // 這裡採用簡單策略：如果 buffer 很大了，或者有一段時間沒數據了，才視為結束
      // 但為了即時顯示，我們先直接更新 UI

      setState(() {
        _receivedCsvLines = lines;
      });
    }
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
            child: _connectedDevice != null
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '已連接: ${_connectedDevice?.platformName}',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ),
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
                  style: const TextStyle(fontFamily: 'Monospace', fontSize: 12),
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _receivedCsvLines.isNotEmpty
                  ? () {
                      // TODO: 導航到數據解析與確認頁面
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('準備解析數據... (下一步開發)')),
                      );
                    }
                  : null,
              child: const Text('解析並匯入數據'),
            ),
          ),
        ),
      ],
    );
  }
}
