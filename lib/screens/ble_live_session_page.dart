import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/pending_tree_measurement.dart';
import '../services/ble_live_packet_decoder.dart';
import '../utils/location_helper.dart';
import '../services/pending_measurement_service.dart';
import '../widgets/ble/ble_device_scanner.dart';
import 'pending_measurement_task_page.dart';
import 'v3/integrated_tree_form_page.dart';
import '../services/locale_service.dart';

/// 現場連線模式：儀器關閉 ENABLE MEM，每測一棵按 SEND → **立即**建立任務並開表單，
/// 處理完畢後再量下一棵（非批次累積）。
class BleLiveSessionPage extends StatefulWidget {
  /// 由 [FieldSurveyFlowPage] 等入口預先選定的裝置
  final BluetoothDevice? initialDevice;

  const BleLiveSessionPage({super.key, this.initialDevice});

  @override
  State<BleLiveSessionPage> createState() => _BleLiveSessionPageState();
}

class _BleLiveSessionPageState extends State<BleLiveSessionPage> {
  static const _haglofServiceUuid = '9E000000-F685-4EA5-B58A-85287CB04965';
  static const _haglofTxUuid = '9E010000-F685-4EA5-B58A-85287CB04965';
  static const _nusServiceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _nusTxUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';
  static const _eotBatch = [0x5A, 0xBF, 0xFB];

  final BleLiveNmeaAssembler _nmeaAssembler = BleLiveNmeaAssembler();
  final PendingMeasurementService _pendingService = PendingMeasurementService();

  BluetoothDevice? _device;
  final List<StreamSubscription<List<int>>> _dataSubs = [];
  StreamSubscription<BluetoothConnectionState>? _connSub;
  bool _isConnected = false;
  bool _isListening = false;
  bool _isProcessingTree = false;
  String _status = '請掃描 VLGEO2 裝置';

  int _liveSeq = 0;
  int _completedCount = 0;

  /// 同一現場場次共用 session
  String? _liveSessionId;
  String? _batchName;
  String? _gpsSource;

  BleLiveMeasurement? _lastMeasurement;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    final pre = widget.initialDevice;
    if (pre != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect(pre);
      });
    } else {
      _status = '請從列表選擇 VLGEO2 裝置';
    }
  }

  @override
  void dispose() {
    for (final sub in _dataSubs) {
      sub.cancel();
    }
    _connSub?.cancel();
    _disconnect();
    super.dispose();
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _device = device;
      _status = '連線中 ${device.platformName}…';
    });

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connSub = device.connectionState.listen((state) {
        if (!mounted) return;
        if (state == BluetoothConnectionState.disconnected) {
          setState(() {
            _isConnected = false;
            _isListening = false;
            _status = '連線已中斷';
          });
        }
      });

      await _subscribeTx(device);
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _status = '已連線。量一棵 → SEND → 處理完再下一棵';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '連線失敗: $e');
    }
  }

  Future<void> _subscribeTx(BluetoothDevice device) async {
    final services = await device.discoverServices();
    final txChars = <BluetoothCharacteristic>[];

    void tryAdd(String svcUuid, String txUuid) {
      for (final s in services) {
        if (s.uuid.toString().toUpperCase() != svcUuid) continue;
        for (final c in s.characteristics) {
          if (c.uuid.toString().toUpperCase() == txUuid &&
              c.properties.notify) {
            txChars.add(c);
            return;
          }
        }
      }
    }

    tryAdd(_haglofServiceUuid, _haglofTxUuid);
    tryAdd(_nusServiceUuid, _nusTxUuid);

    if (txChars.isEmpty) {
      throw Exception('找不到 Haglof / NUS 的 notify TX');
    }

    for (final c in txChars) {
      await c.setNotifyValue(true);
      _dataSubs.add(c.lastValueStream.listen(_onPacket));
      _appendLog('訂閱 ${c.uuid}');
    }

    if (mounted) {
      setState(() => _isListening = true);
    }
  }

  bool _isBatchEot(List<int> data) {
    if (data.length != 3) return false;
    if (data[0] == 0x04 && data[1] == 0x7C) return true;
    if (data[0] == _eotBatch[0] &&
        data[1] == _eotBatch[1] &&
        data[2] == _eotBatch[2]) {
      return true;
    }
    return false;
  }

  void _onPacket(List<int> data) {
    if (data.isEmpty) return;

    if (_isBatchEot(data)) {
      _appendLog('收到批次 EOT — 請關 ENABLE MEM，勿用 SEND FILES');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('偵測到整檔傳輸模式。現場連線請關閉儀器記憶體儲存，勿使用 SEND FILES。'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    final completed = _nmeaAssembler.feed(data);
    for (final live in completed) {
      _liveSeq++;
      _lastMeasurement = live;
      _appendLog(
        '#$_liveSeq NMEA H=${live.heightM} HD=${live.horizontalDistanceM} '
        'SD=${live.slopeDistanceM} AZ=${live.azimuthDeg} pitch=${live.pitchDeg}',
      );
      _appendLog('  raw: ${live.rawNmea}');

      if (_isProcessingTree) {
        _appendLog('  ⚠ 上一棵尚未處理完，請完成表單後再按 SEND');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('請先完成目前這棵樹的現場紀錄，再量下一棵'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      unawaited(_processLiveMeasurement(live, seq: _liveSeq));
      return;
    }

    if (data.any((b) => b == 0x24 || b == 0x2C)) {
      final preview = String.fromCharCodes(
        data.where((b) => b >= 0x20 && b <= 0x7E),
      );
      if (preview.isNotEmpty) {
        _appendLog('分片 (${data.length}B): $preview');
      }
    }
  }

  /// 收到一筆 NMEA → 上傳單棵 → 開 IntegratedTreeFormPage → 回來後才可下一棵
  Future<void> _processLiveMeasurement(
    BleLiveMeasurement live, {
    required int seq,
  }) async {
    if (!mounted) return;

    setState(() {
      _isProcessingTree = true;
      _status = '第 $seq 棵：取得 GPS 並建立任務…';
    });

    try {
      if (!await _ensureLiveSessionConfigured()) {
        return;
      }

      final pos = await getHighAccuracyPosition(
        timeout: const Duration(seconds: 12),
      );
      final lat = pos?.latitude ?? 0.0;
      final lon = pos?.longitude ?? 0.0;
      final hasGps = pos != null;

      if (!hasGps && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('無法取得手機 GPS，仍會建立任務但樹位可能需稍後補'),
            backgroundColor: Colors.orange,
          ),
        );
      }

      _liveSessionId ??= PendingMeasurementService.generateSessionId();

      final recordId = 'LIVE-${DateTime.now().millisecondsSinceEpoch}';
      final bleRecord = live.toBleRecordMap(
        id: recordId,
        lat: lat,
        lon: lon,
        hasGps: hasGps,
        gpsSource: _gpsSource!,
        extraMetadata: {
          if (pos != null) 'phone_gps_accuracy_m': pos.accuracy,
          'live_session_index': seq,
          if (_batchName != null) 'batch_name': _batchName,
        },
      );

      if (mounted) {
        setState(() => _status = '第 $seq 棵：上傳任務…');
      }

      final result = await _pendingService.createAndUploadFromBle(
        bleData: [bleRecord],
        batchName: _batchName,
        sessionId: _liveSessionId,
      );

      if (result['success'] != true || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']?.toString() ?? '建立任務失敗'),
            ),
          );
        }
        return;
      }

      _liveSessionId = result['sessionId'] as String? ?? _liveSessionId;

      final tasks = result['tasks'] as List<PendingTreeMeasurement>?;
      if (tasks == null || tasks.isEmpty || tasks.first.id == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('任務已上傳但無法取得 ID')),
          );
        }
        return;
      }

      var task = tasks.first;
      final lockTs = await _pendingService.updateTaskStatus(
        task.id!,
        MeasurementStatus.inProgress,
      );
      task = task.copyWith(
        status: MeasurementStatus.inProgress,
        updatedAt: lockTs ?? task.updatedAt,
      );

      if (!mounted) return;
      setState(() => _status = '第 $seq 棵：現場紀錄（拍照 / DBH / 提交）…');

      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);

      final success = await nav.push<bool>(
        MaterialPageRoute(
          builder: (_) => IntegratedTreeFormPage(task: task),
        ),
      );

      if (!mounted) return;

      if (success == true) {
        _completedCount++;
        messenger.showSnackBar(
          SnackBar(
            content: Text('第 $seq 棵已完成（本場 $_completedCount 棵）'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        await _pendingService
            .updateTaskStatus(task.id!, MeasurementStatus.pending)
            .catchError((_) => null);
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('第 $seq 棵已取消或未完成，可從待測量列表繼續'),
          ),
        );
      }
    } catch (e) {
      debugPrint('[BleLive] process tree error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('處理失敗: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingTree = false;
          _status = _isConnected
              ? '已完成 $_completedCount 棵。請在儀器量下一棵並按 SEND'
              : _status;
        });
      }
    }
  }

  /// 第一棵前詢問場次名稱與 GPS 語意（整場共用）
  Future<bool> _ensureLiveSessionConfigured() async {
    if (_batchName != null && _gpsSource != null) return true;

    final batchName = await _promptBatchName();
    if (batchName == null || batchName.isEmpty) return false;

    final gpsSource = await _confirmGpsSource();
    if (gpsSource == null) return false;

    if (mounted) {
      setState(() {
        _batchName = batchName;
        _gpsSource = gpsSource;
      });
    }
    return true;
  }

  void _appendLog(String line) {
    if (!mounted) return;
    setState(() {
      _logLines.insert(0, line);
      if (_logLines.length > 40) _logLines.removeLast();
    });
  }

  Future<String?> _promptBatchName() async {
    final controller = TextEditingController(
      text: _batchName ?? '現場連線-${DateTime.now().month}/${DateTime.now().day}',
    );
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('現場場次名稱'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '本場所有樹木共用此名稱，第一棵前設定一次即可。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '例如：東華樣區-A'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('開始'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSessionTaskList() async {
    if (_liveSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚無本場次任務')),
      );
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PendingMeasurementTaskPage(sessionId: _liveSessionId),
      ),
    );
  }

  Future<String?> _confirmGpsSource() async {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('GPS 語意（手機座標）'),
        content: const Text(
          '每棵樹在按 SEND 當下會取一次手機 GPS。\n\n'
          '• 測站模式：您在測站持機，依 HD+方位推算樹位\n'
          '• 樹旁模式：您站在樹旁，座標即樹位',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'surveyor'),
            child: const Text('測站'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'tree'),
            child: const Text('樹旁'),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnect() async {
    for (final sub in _dataSubs) {
      await sub.cancel();
    }
    _dataSubs.clear();
    _connSub?.cancel();
    if (_device != null) {
      try {
        await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isListening = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _lastMeasurement;
    return Scaffold(
      appBar: AppBar(
        title: const Text('VLGEO2 現場連線'),
        actions: [
          if (_liveSessionId != null)
            IconButton(
              icon: const Icon(Icons.list_alt),
              tooltip: '本場次任務',
              onPressed: _isProcessingTree ? null : _openSessionTaskList,
            ),
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.link_off),
              onPressed: _isProcessingTree ? null : _disconnect,
              tooltip: '中斷連線',
            ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_status${_isListening ? ' · ${context.tr('ble_listening')}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isProcessingTree
                        ? '⏳ 處理中 — 請完成表單後再量下一棵'
                        : '流程：量一棵 → SEND → 拍照/DBH/提交 → 再下一棵\n'
                            '已完成 $_completedCount 棵 · 已接收 $_liveSeq 筆 NMEA',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (_batchName != null)
                    Text(
                      '場次：$_batchName · GPS：${_gpsSource == 'tree' ? '樹旁' : '測站'}',
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          if (!_isConnected && !_isProcessingTree)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: BleDeviceScanner(
                  onDeviceSelected: (device) {
                    if (_isProcessingTree) return;
                    _connect(device);
                  },
                ),
              ),
            ),
          if (last != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('$_liveSeq'),
                ),
                title: Text(
                  last.remoteDiameterCm != null
                      ? '樹高 ${last.heightM} m · Remote Dia ${last.remoteDiameterCm!.toStringAsFixed(1)} cm'
                      : '樹高 ${last.heightM} m',
                ),
                subtitle: Text(
                  'HD ${last.horizontalDistanceM} m · AZ ${last.azimuthDeg}°',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          if (_isConnected && _logLines.isNotEmpty)
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey.shade100,
                padding: const EdgeInsets.all(8),
                child: ListView(
                  children: _logLines
                      .map((l) => Text(l, style: const TextStyle(fontSize: 11)))
                      .toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
