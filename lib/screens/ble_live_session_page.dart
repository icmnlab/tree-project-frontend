import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/maintenance_target.dart';
import '../models/pending_tree_measurement.dart';
import '../services/ble_live_packet_decoder.dart';
import '../utils/field_gps_capture.dart';
import '../utils/field_log.dart';
import '../services/pending_measurement_service.dart';
import '../widgets/ble/ble_device_scanner.dart';
import '../widgets/field/field_session_setup.dart';
import 'pending_measurement_task_page.dart';
import 'v3/integrated_tree_form_page.dart';
import '../services/locale_service.dart';

/// 現場連線模式：儀器關閉 ENABLE MEM，每測一棵按 SEND → **立即**建立任務並開表單，
/// 處理完畢後再量下一棵（非批次累積）。
class BleLiveSessionPage extends StatefulWidget {
  /// 由 [FieldSurveyFlowPage] 等入口預先選定的裝置
  final BluetoothDevice? initialDevice;

  /// 進入連線前已完成的專案／區位設定（建議由現場測量 Wizard 傳入）
  final FieldSessionSetup? initialSessionSetup;

  /// 維護量測：重測既有樹（transfer 時寫入歷次並更新 tree_survey）
  final MaintenanceTarget? maintenanceTarget;

  const BleLiveSessionPage({
    super.key,
    this.initialDevice,
    this.initialSessionSetup,
    this.maintenanceTarget,
  });

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
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isListening = false;
  bool _isProcessingTree = false;
  bool _userDisconnect = false;
  bool _reconnecting = false;
  bool _reconnectAfterProcessing = false;
  int _reconnectAttempt = 0;
  static const _maxReconnectAttempts = 5;
  BleLiveMeasurement? _gpsRetryLive;
  int? _gpsRetrySeq;
  String _status = '';

  bool get _canAutoReconnect =>
      _device != null && !_userDisconnect && !_isConnected;

  bool get _showBleScanner =>
      !_isConnected && !_isProcessingTree && (_device == null || _userDisconnect);

  int _liveSeq = 0;
  int _completedCount = 0;

  /// 同一現場場次共用 session
  String? _liveSessionId;
  String? _batchName;
  String? _gpsSource;
  String? _projectName;
  String? _projectCode;
  String? _projectArea;

  BleLiveMeasurement? _lastMeasurement;
  final List<String> _logLines = [];

  @override
  void initState() {
    super.initState();
    FieldLog.uiSink = _onFieldLogLine;
    _status = ''; // set in didChangeDependencies
    _gpsSource = 'tree';
    final setup = widget.initialSessionSetup;
    if (setup != null) {
      _batchName = setup.batchName;
      _projectName = setup.projectName;
      _projectCode = setup.projectCode;
      _projectArea = setup.projectArea;
    }
    final pre = widget.initialDevice;
    if (pre != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _connect(pre);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _logSessionStart());
  }

  Future<void> _logSessionStart() async {
    try {
      final info = await PackageInfo.fromPlatform();
      FieldLog.ble(
        '啟動 ${info.version}+${info.buildNumber} '
        '${kReleaseMode ? "release" : "debug"} '
        'logcat=${FieldLog.logcatEnabled}',
      );
    } catch (_) {
      FieldLog.ble('啟動 session');
    }
    if (widget.maintenanceTarget != null) {
      FieldLog.ble(
        '維護目標 id=${widget.maintenanceTarget!.treeSurveyId}',
      );
    }
    if (_projectCode != null) {
      FieldLog.ble('專案=$_projectCode 區=$_projectArea 場次=$_batchName');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_status.isEmpty) {
      _status = widget.initialDevice == null
          ? context.tr('ble_status_pick_device')
          : context.tr('ble_status_connect');
    }
  }

  @override
  void dispose() {
    if (FieldLog.uiSink == _onFieldLogLine) {
      FieldLog.uiSink = null;
    }
    _reconnectTimer?.cancel();
    for (final sub in _dataSubs) {
      sub.cancel();
    }
    _connSub?.cancel();
    _disconnect();
    super.dispose();
  }

  Future<void> _connect(BluetoothDevice device, {bool isReconnect = false}) async {
    _userDisconnect = false;
    if (!isReconnect) _reconnectAttempt = 0;
    _reconnectTimer?.cancel();

    setState(() {
      _device = device;
      _status = isReconnect
          ? '重新連線 ${device.platformName}…'
          : '連線中 ${device.platformName}…';
    });

    try {
      await device.connect(timeout: const Duration(seconds: 15));
      _connSub?.cancel();
      _connSub = device.connectionState.listen(_onConnectionState);

      await _subscribeTx(device);
      if (!mounted) return;
      setState(() {
        _isConnected = true;
        _reconnectAttempt = 0;
        _status = context.tr('ble_status_connected');
      });
      _appendLog('已連線 ${device.platformName} (${device.remoteId.str})');
      if (isReconnect) {
        _appendLog('自動重連成功');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('ble_reconnect_ok')),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (isReconnect) {
        _appendLog('重連失敗: $e');
        _scheduleReconnect();
      } else {
        setState(() => _status = '連線失敗: $e');
      }
    }
  }

  void _onConnectionState(BluetoothConnectionState state) {
    if (!mounted) return;
    if (state == BluetoothConnectionState.connected) {
      _reconnectAttempt = 0;
      return;
    }
    if (state == BluetoothConnectionState.disconnected) {
      _handleUnexpectedDisconnect();
    }
  }

  void _handleUnexpectedDisconnect() {
    if (_userDisconnect || _device == null) return;
    setState(() {
      _isConnected = false;
      _isListening = false;
      _status = context.tr('ble_status_disconnected');
    });
    if (_isProcessingTree) {
      _reconnectAfterProcessing = true;
      _appendLog('連線中斷（表單處理中），完成後將自動重連');
      setState(() => _status = context.tr('ble_disconnected_during_form'));
      return;
    }
    _appendLog('連線中斷，嘗試自動重連…');
    _scheduleReconnect();
  }

  Future<void> _manualReconnectNow() async {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    await _reconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    if (_userDisconnect || _device == null || !mounted) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      setState(() => _status = context.tr('ble_reconnect_failed'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('ble_reconnect_failed'))),
      );
      return;
    }
    final delay = Duration(seconds: 2 << _reconnectAttempt.clamp(0, 3));
    _reconnectAttempt++;
    setState(() {
      _status = context
          .tr('ble_reconnecting')
          .replaceAll('{n}', '$_reconnectAttempt')
          .replaceAll('{max}', '$_maxReconnectAttempts');
    });
    _reconnectTimer = Timer(delay, () async {
      if (!mounted || _userDisconnect || _device == null) return;
      await _reconnect();
    });
  }

  Future<void> _reconnect() async {
    final device = _device;
    if (device == null || _reconnecting || _userDisconnect) return;
    _reconnecting = true;
    try {
      for (final sub in _dataSubs) {
        await sub.cancel();
      }
      _dataSubs.clear();
      await _connect(device, isReconnect: true);
    } finally {
      _reconnecting = false;
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

    // 實機 VLGEO2：PHGF 由 NUS TX 送出；Haglof TX 多為 §9.3 前綴。僅訂閱一個 TX。
    tryAdd(_nusServiceUuid, _nusTxUuid);
    if (txChars.isEmpty) {
      tryAdd(_haglofServiceUuid, _haglofTxUuid);
    }

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

      // 同步加鎖，避免 setState 完成前重複 notify 啟動第二個 _processLiveMeasurement
      _isProcessingTree = true;
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

    if (mounted) {
      setState(() => _status = '第 $seq 棵：取得 GPS 並建立任務…');
    }

    try {
      if (!await _ensureLiveSessionConfigured()) {
        return;
      }

      final gps = await _resolveGpsForLiveMeasurement(seq);
      if (gps == null) {
        if (mounted) {
          setState(() {
            _gpsRetryLive = live;
            _gpsRetrySeq = seq;
            _status = context
                .tr('ble_gps_retry_banner')
                .replaceAll('{n}', '$seq');
          });
          _appendLog('#$seq 未取得 GPS — 可重測 GPS，無需再按 SEND');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('ble_gps_retry_hint')),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: context.tr('ble_gps_retry_btn'),
                onPressed: _retryPendingGps,
              ),
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _gpsRetryLive = null;
        _gpsRetrySeq = null;
      });
      await _completeLiveMeasurementAfterGps(live, seq, gps);
    } catch (e, st) {
      FieldLog.ble('process tree error: $e\n$st', toUi: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('處理失敗: $e')),
        );
      }
    } finally {
      _isProcessingTree = false;
      if (mounted) {
        setState(() {
          if (_gpsRetryLive == null) {
            _status = _isConnected
                ? context.tr('ble_status_connected')
                : _status;
          }
        });
      }
      if (_reconnectAfterProcessing && !_userDisconnect && _device != null) {
        _reconnectAfterProcessing = false;
        _appendLog('表單完成，恢復自動重連…');
        _scheduleReconnect();
      }
    }
  }

  Future<void> _completeLiveMeasurementAfterGps(
    BleLiveMeasurement live,
    int seq,
    FieldGpsCaptureResult gps,
  ) async {
    final lat = gps.latitude;
    final lon = gps.longitude;
    const hasGps = true;

    fieldGpsLog(
      'live seq=$seq mode=$_gpsSource lat=$lat lon=$lon acc=${gps.accuracyM}m',
    );

    _liveSessionId ??= PendingMeasurementService.generateSessionId();

    final recordId = 'LIVE-${DateTime.now().millisecondsSinceEpoch}';
    final maint = widget.maintenanceTarget;
    final bleRecord = live.toBleRecordMap(
      id: recordId,
      lat: lat,
      lon: lon,
      hasGps: hasGps,
      gpsSource: _gpsSource!,
      extraMetadata: {
        'phone_gps_accuracy_m': gps.accuracyM,
        'gps_sample_count': gps.sampleCount,
        'live_session_index': seq,
        if (_batchName != null) 'batch_name': _batchName,
        if (maint != null) ...{
          'survey_mode': 'maintenance',
          'target_tree_id': maint.treeSurveyId,
          'match_status': 'user_selected',
        },
      },
    );
    if (maint != null) {
      bleRecord['_survey_mode'] = 'maintenance';
      bleRecord['_target_tree_id'] = maint.treeSurveyId;
      bleRecord['_match_status'] = 'user_selected';
    }

    if (mounted) {
      setState(() => _status = '第 $seq 棵：上傳任務…');
    }

    final result = await _pendingService.createAndUploadFromBle(
      bleData: [bleRecord],
      batchName: _batchName,
      projectArea: _projectArea,
      projectCode: _projectCode,
      projectName: _projectName,
      sessionId: _liveSessionId,
    );

    if (result['success'] != true || !mounted) {
      _appendLog('#$seq 建立任務失敗: ${result['message']}');
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
    _appendLog('#$seq pending 已建立 session=$_liveSessionId');
    await _syncSessionProjectToServer();

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
        builder: (_) => IntegratedTreeFormPage(
          task: task,
          autoTransferToTreeSurvey: true,
          transferSessionId: _liveSessionId,
        ),
      ),
    );

    if (!mounted) return;

    if (success == true) {
      _completedCount++;
      _appendLog('#$seq 表單提交成功（累計 $_completedCount 棵）');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context
                .tr('ble_tree_done')
                .replaceAll('{n}', '$seq')
                .replaceAll('{total}', '$_completedCount'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      _appendLog('#$seq 表單取消，退回 pending id=${task.id}');
      await _pendingService
          .updateTaskStatus(task.id!, MeasurementStatus.pending)
          .catchError((_) => null);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('ble_tree_cancel').replaceAll('{n}', '$seq'),
          ),
        ),
      );
    }
  }

  Future<void> _retryPendingGps() async {
    final live = _gpsRetryLive;
    final seq = _gpsRetrySeq;
    if (live == null || seq == null || _isProcessingTree) return;
    _isProcessingTree = true;
    if (mounted) {
      setState(() => _status = '第 $seq 棵：重測 GPS…');
    }
    try {
      if (!await _ensureLiveSessionConfigured()) return;
      final gps = await _resolveGpsForLiveMeasurement(seq);
      if (gps == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.tr('ble_gps_required')),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _gpsRetryLive = null;
        _gpsRetrySeq = null;
      });
      await _completeLiveMeasurementAfterGps(live, seq, gps);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重測 GPS 失敗: $e')),
        );
      }
    } finally {
      _isProcessingTree = false;
      if (mounted && _gpsRetryLive == null) {
        setState(() {
          _status = _isConnected
              ? context.tr('ble_status_connected')
              : _status;
        });
      }
      if (_reconnectAfterProcessing && !_userDisconnect && _device != null) {
        _reconnectAfterProcessing = false;
        _scheduleReconnect();
      }
    }
  }

  void _dismissGpsRetry() {
    setState(() {
      _gpsRetryLive = null;
      _gpsRetrySeq = null;
      _status = _isConnected
          ? context.tr('ble_status_connected')
          : _status;
    });
    _appendLog('已放棄 GPS 重測（量測資料已捨棄，請重新 SEND）');
  }

  Future<void> _changeSessionProject() async {
    if (_isProcessingTree) return;
    if (_completedCount > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.tr('ble_change_project_title')),
          content: Text(context.tr('ble_change_project_warn')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.tr('ble_change_project_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.tr('ble_change_project_confirm')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final setup = await showFieldSessionSetupDialog(
      context,
      initial: FieldSessionSetup(
        batchName: _batchName ?? '',
        projectName: _projectName ?? '',
        projectCode: _projectCode ?? '',
        projectArea: _projectArea ?? '',
        gpsSource: 'tree',
      ),
    );
    if (setup == null || !mounted) return;
    setState(() {
      _batchName = setup.batchName;
      _projectName = setup.projectName;
      _projectCode = setup.projectCode;
      _projectArea = setup.projectArea;
      _gpsSource = 'tree';
    });
    await _syncSessionProjectToServer();
    _appendLog('已切換：${setup.projectName} · ${setup.projectArea}');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context
                .tr('ble_change_project_ok')
                .replaceAll('{project}', setup.projectName)
                .replaceAll('{area}', setup.projectArea),
          ),
        ),
      );
    }
  }

  /// 每次 SEND 皆於樹旁手動取得手機 GPS（2026-05-28 會議：固定樹木位置）
  Future<FieldGpsCaptureResult?> _resolveGpsForLiveMeasurement(int seq) async {
    return showFieldGpsCaptureDialog(
      context,
      mode: 'tree',
      title: '第 $seq 棵 · 樹旁 GPS',
    );
  }

  /// 第一棵前：專案、區位、GPS 語意、場次名稱（整場共用）
  Future<bool> _ensureLiveSessionConfigured() async {
    if (_projectCode != null &&
        _projectArea != null &&
        _gpsSource != null &&
        _batchName != null) {
      return true;
    }

    final setup = await showFieldSessionSetupDialog(
      context,
      initial: widget.initialSessionSetup ??
          (_projectCode != null
              ? FieldSessionSetup(
                  batchName: _batchName ?? '',
                  projectName: _projectName ?? '',
                  projectCode: _projectCode!,
                  projectArea: _projectArea ?? '',
                  gpsSource: 'tree',
                )
              : null),
    );
    if (setup == null) return false;

    if (mounted) {
      setState(() {
        _batchName = setup.batchName;
        _projectName = setup.projectName;
        _projectCode = setup.projectCode;
        _projectArea = setup.projectArea;
        _gpsSource = 'tree';
      });
    }
    await _syncSessionProjectToServer();
    return true;
  }

  Future<void> _syncSessionProjectToServer() async {
    final sid = _liveSessionId;
    if (sid == null ||
        _projectArea == null ||
        _projectCode == null ||
        _projectName == null) {
      return;
    }
    try {
      await _pendingService.updateSessionProject(
        sessionId: sid,
        projectArea: _projectArea!,
        projectCode: _projectCode,
        projectName: _projectName,
      );
    } catch (e) {
      FieldLog.ble('updateSessionProject: $e', toUi: true);
    }
  }

  void _onFieldLogLine(String line) {
    if (!mounted) return;
    setState(() {
      _logLines.insert(0, line);
      if (_logLines.length > 80) _logLines.removeLast();
    });
  }

  void _appendLog(String line) => FieldLog.ble(line, toUi: true);

  Future<void> _copyLogsToClipboard() async {
    if (_logLines.isEmpty) return;
    final text = _logLines.reversed.join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('日誌已複製（可貼到 LINE / 郵件回報）'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openSessionTaskList() async {
    if (_liveSessionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('ble_no_session_tasks'))),
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

  Future<void> _disconnect() async {
    _userDisconnect = true;
    _reconnectTimer?.cancel();
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

  Color _statusBannerColor(BuildContext context) {
    if (_canAutoReconnect && _reconnectAttempt >= _maxReconnectAttempts) {
      return Colors.red.shade50;
    }
    if (_canAutoReconnect || _reconnecting || _reconnectAfterProcessing) {
      return Colors.orange.shade50;
    }
    if (_isConnected) return Theme.of(context).colorScheme.primaryContainer;
    return Colors.grey.shade100;
  }

  Widget _buildReconnectPanel() {
    final deviceName = _device?.platformName.isNotEmpty == true
        ? _device!.platformName
        : (_device?.remoteId.str ?? 'VLGEO2');
    final failed = _reconnectAttempt >= _maxReconnectAttempts;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              failed ? Icons.bluetooth_disabled : Icons.bluetooth_searching,
              size: 48,
              color: failed ? Colors.red.shade700 : Colors.orange.shade800,
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('ble_reconnect_device').replaceAll('{name}', deviceName),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            if (!failed && (_reconnecting || _reconnectAttempt > 0)) ...[
              const SizedBox(height: 20),
              const CircularProgressIndicator(),
            ],
            const SizedBox(height: 24),
            if (failed || _reconnectAttempt > 0)
              FilledButton.icon(
                onPressed: _reconnecting ? null : _manualReconnectNow,
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('ble_reconnect_now')),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isProcessingTree
                  ? null
                  : () {
                      _userDisconnect = true;
                      _reconnectTimer?.cancel();
                      setState(() {
                        _device = null;
                        _reconnectAttempt = 0;
                        _status = context.tr('ble_status_pick_device');
                      });
                    },
              child: Text(context.tr('ble_reconnect_scan_other')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsRetryBanner() {
    final seq = _gpsRetrySeq ?? 0;
    return Material(
      color: Colors.orange.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.gps_off, color: Colors.orange.shade900),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('ble_gps_retry_banner').replaceAll('{n}', '$seq'),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: _isProcessingTree ? null : _retryPendingGps,
              child: Text(context.tr('ble_gps_retry_btn')),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              tooltip: context.tr('ble_gps_retry_dismiss'),
              onPressed: _isProcessingTree ? null : _dismissGpsRetry,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final last = _lastMeasurement;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('ble_live_title')),
        actions: [
          if (_logLines.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: '複製日誌',
              onPressed: _isProcessingTree ? null : _copyLogsToClipboard,
            ),
          if (_projectCode != null && !_isProcessingTree)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: context.tr('ble_change_project_title'),
              onPressed: _changeSessionProject,
            ),
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
            color: _statusBannerColor(context),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (_isConnected)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Icon(
                            Icons.bluetooth_connected,
                            size: 18,
                            color: Colors.green.shade700,
                          ),
                        ),
                      if (_canAutoReconnect && !_reconnectAfterProcessing)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          '$_status${_isListening ? ' · ${context.tr('ble_listening')}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isProcessingTree
                        ? '⏳ ${context.tr('ble_processing')}'
                        : '${context.tr('ble_flow_hint')}\n'
                            '$_completedCount · $_liveSeq NMEA',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (_projectName != null)
                    Text(
                      context
                          .tr('ble_session_line')
                          .replaceAll('{project}', _projectName!)
                          .replaceAll('{area}', _projectArea ?? '—'),
                      style: const TextStyle(fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          if (_gpsRetryLive != null) _buildGpsRetryBanner(),
          if (_canAutoReconnect && !_isProcessingTree) _buildReconnectPanel()
          else if (_showBleScanner)
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
