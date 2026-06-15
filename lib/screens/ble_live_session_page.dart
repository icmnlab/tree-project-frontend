import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/maintenance_target.dart';
import '../models/pending_tree_measurement.dart';
import '../services/ble_live_packet_decoder.dart';
import '../utils/field_gps_capture.dart';
import '../utils/field_log.dart';
import '../utils/maintenance_gps_flow.dart';
import '../utils/ble_transfer_signals.dart';
import '../utils/ble_uart_discovery.dart';
import '../utils/tree_id_display.dart';
import '../utils/transfer_result.dart';
import '../services/pending_measurement_service.dart';
import '../widgets/ble/ble_device_scanner.dart';
import '../widgets/ble/ble_instrument_checklist.dart';
import '../widgets/field/field_session_setup.dart';
import 'pending_measurement_task_page.dart';
import 'v3/integrated_tree_form_page.dart';
import '../services/locale_service.dart';
import '../debug/debug_session_log.dart';

/// 現場連線模式：儀器關閉 ENABLE MEM，每測一棵按 SEND → **立即**建立任務並開表單，
/// 處理完畢後再量下一棵（非批次累積）。
class BleLiveSessionPage extends StatefulWidget {
  /// 由首頁等入口預先選定的裝置
  final BluetoothDevice? initialDevice;

  /// 進入連線前已完成的專案／區位設定（建議由現場測量 Wizard 傳入）
  final FieldSessionSetup? initialSessionSetup;

  /// 維護量測：重測既有樹（transfer 時寫入歷次並更新 tree_survey）
  final MaintenanceTarget? maintenanceTarget;

  /// 由 [MaintenanceSurveyPage] 進入：新增樹完成後返回清單（非留 BLE 連測）
  final bool maintenanceSessionContext;

  const BleLiveSessionPage({
    super.key,
    this.initialDevice,
    this.initialSessionSetup,
    this.maintenanceTarget,
    this.maintenanceSessionContext = false,
  });

  @override
  State<BleLiveSessionPage> createState() => _BleLiveSessionPageState();
}

class _BleLiveSessionPageState extends State<BleLiveSessionPage> {
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
  bool _formOpen = false;
  bool _gpsDialogOpen = false;
  int _reconnectAttempt = 0;
  int _processGen = 0;
  static const _maxReconnectAttempts = 5;
  static const _connectMaxAttempts = 3;
  BleLiveMeasurement? _gpsRetryLive;
  int? _gpsRetrySeq;
  /// GPS 階段若儀器連按 SEND，只更新此值，避免重複建立 pending
  BleLiveMeasurement? _inProgressLive;
  int? _inProgressSendSeq;
  String _status = '';

  bool get _canAutoReconnect =>
      _device != null && !_userDisconnect && !_isConnected;

  bool get _showBleScanner =>
      !_isConnected && !_isProcessingTree && (_device == null || _userDisconnect);

  int _liveSeq = 0;
  int _completedCount = 0;

  /// UI「第幾棵」：僅在表單提交成功後遞增 [_completedCount]；連續 SEND 覆蓋不變。
  int get _displayTreeSeq => _completedCount + 1;

  /// 同一現場場次共用 session
  String? _liveSessionId;
  String? _batchName;
  String? _gpsSource;
  String? _projectName;
  String? _projectCode;
  String? _projectArea;

  /// 維護重測：SEND 後 GPS 流程決定是否寫回 tree_survey 座標
  bool _pendingUpdateTreeLocation = false;

  BleLiveMeasurement? _lastMeasurement;
  Completer<void>? _blePrepare;
  int _scannerEpoch = 0;
  bool _checklistReady = false;

  @override
  void initState() {
    super.initState();
    _status = ''; // set in didChangeDependencies
    _gpsSource = 'tree';
    final setup = widget.initialSessionSetup;
    if (setup != null) {
      _batchName = setup.batchName;
      _projectName = setup.projectName;
      _projectCode = setup.projectCode;
      _projectArea = setup.projectArea;
    }
    if (widget.initialDevice == null) {
      _beginBlePrepare();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _logSessionStart();
      await _ensureInstrumentChecklist();
    });
  }

  Future<void> _ensureInstrumentChecklist() async {
    final ok = await BleInstrumentChecklist.ensureAcknowledged(context);
    if (!mounted) return;
    setState(() => _checklistReady = ok);
    if (!ok) return;
    final pre = widget.initialDevice;
    if (pre != null && !_isConnected && _device == null) {
      await _connect(pre);
    }
  }

  void _beginBlePrepare() {
    _blePrepare = Completer<void>();
    unawaited(() async {
      await _releaseBleForRescan();
      _blePrepare?.complete();
    }());
  }

  Future<void> _safeStopScan() async {
    try {
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }
    } catch (_) {}
  }

  /// 進入掃描前釋放殘留連線（避免掃不到儀器）
  Future<void> _releaseBleForRescan() async {
    try {
      await _safeStopScan();
      for (final d in FlutterBluePlus.connectedDevices) {
        if (d.isConnected) {
          await d.disconnect();
        }
      }
      // #region agent log
      DebugSessionLog.emit(
        'ble_live_session_page.dart:_releaseBleForRescan',
        'released stale ble',
        hypothesisId: 'H-E',
        runId: 'post-fix',
      );
      // #endregion
    } catch (e) {
      DebugSessionLog.emit(
        'ble_live_session_page.dart:_releaseBleForRescan',
        'release failed',
        hypothesisId: 'H-E',
        data: {'error': e.toString()},
        runId: 'post-fix',
      );
    }
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
    _reconnectTimer?.cancel();
    for (final sub in _dataSubs) {
      sub.cancel();
    }
    _connSub?.cancel();
    unawaited(_teardownBleOnExit());
    super.dispose();
  }

  /// 離開頁面時釋放掃描與連線，避免下次進入掃不到儀器
  Future<void> _teardownBleOnExit() async {
    // #region agent log
    DebugSessionLog.emit(
      'ble_live_session_page.dart:_teardownBleOnExit',
      'page dispose teardown',
      hypothesisId: 'H-E',
      data: {
        'hadDevice': _device != null,
        'wasConnected': _isConnected,
        'userDisconnect': _userDisconnect,
      },
    );
    // #endregion
    await _safeStopScan();
    final d = _device;
    if (d != null) {
      try {
        if (d.isConnected) await d.disconnect();
      } catch (_) {}
    }
  }

  bool _isRetriableConnectError(Object e) {
    final m = e.toString().toLowerCase();
    return m.contains('133') ||
        m.contains('android_specific') ||
        m.contains('timeout') ||
        m.contains('gatt') ||
        m.contains('connection');
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

    Object? lastError;
    for (var attempt = 1; attempt <= _connectMaxAttempts; attempt++) {
      if (!mounted) return;
      if (attempt > 1) {
        setState(() {
          _status = context
              .tr('ble_connect_retry')
              .replaceAll('{n}', '$attempt')
              .replaceAll('{max}', '$_connectMaxAttempts');
        });
        _appendLog('連線重試 $attempt/$_connectMaxAttempts…');
        try {
          if (device.isConnected) await device.disconnect();
        } catch (_) {}
        await Future<void>.delayed(Duration(milliseconds: 500 + attempt * 350));
      }

      try {
        await _connectOnce(device);
        if (!mounted) return;
        // #region agent log
        DebugSessionLog.emit(
          'ble_live_session_page.dart:_connect',
          'connected',
          hypothesisId: 'H-B',
          data: {
            'device': device.remoteId.str,
            'isReconnect': isReconnect,
            'attempt': attempt,
          },
        );
        // #endregion
        setState(() {
          _isConnected = true;
          _reconnectAttempt = 0;
          _status = context.tr('ble_status_ready');
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
        return;
      } catch (e) {
        lastError = e;
        _appendLog('連線失敗 (attempt $attempt): $e');
        if (!_isRetriableConnectError(e) || attempt >= _connectMaxAttempts) {
          break;
        }
      }
    }

    if (!mounted) return;
    if (isReconnect) {
      _scheduleReconnect();
    } else {
      setState(() {
        _isConnected = false;
        _status = context.tr('ble_connect_failed');
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lastError != null
                ? '${context.tr('ble_connect_failed')}\n$lastError'
                : context.tr('ble_connect_failed'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _connectOnce(BluetoothDevice device) async {
    await _safeStopScan();
    _appendLog('停止掃描，連線 ${device.remoteId.str}…');

    try {
      if (device.isConnected) {
        await device.disconnect();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {}

    await device.connect(
      timeout: const Duration(seconds: 20),
      autoConnect: false,
    );
    _connSub?.cancel();
    _connSub = device.connectionState.listen(_onConnectionState);

    await Future<void>.delayed(const Duration(milliseconds: 450));
    await _subscribeTx(device);
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
    final tx = BleUartDiscovery.findNotifyTx(services, preferNus: true);
    if (tx == null) {
      throw Exception('找不到 Haglof / NUS 的 notify TX');
    }

    await tx.setNotifyValue(true);
    _dataSubs.add(tx.lastValueStream.listen(_onPacket));
    _appendLog('訂閱 ${tx.uuid}');

    if (mounted) {
      setState(() => _isListening = true);
    }
  }

  bool _isBatchEot(List<int> data) => BleTransferSignals.isBatchFileEot(data);

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
      final displaySeq = _displayTreeSeq;
      _lastMeasurement = live;
      _appendLog(
        '[樹 $displaySeq] SEND#$_liveSeq NMEA H=${live.heightM} HD=${live.horizontalDistanceM} '
        'SD=${live.slopeDistanceM} AZ=${live.azimuthDeg} pitch=${live.pitchDeg}',
      );
      _appendLog('  raw: ${live.rawNmea}');

      if (_isProcessingTree) {
        if (_formOpen) {
          _appendLog('  ⚠ 表單進行中，請完成或取消後再 SEND');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('請先完成或取消目前表單，再量下一棵'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        // GPS 階段：只保留最新 NMEA，不重跑 GPS／不重複建立 pending
        _inProgressLive = live;
        _inProgressSendSeq = _liveSeq;
        _appendLog('  新 SEND 覆蓋進行中流程（仍為第 $displaySeq 棵）');
        return;
      }

      _processGen++;
      _isProcessingTree = true;
      _inProgressLive = live;
      _inProgressSendSeq = _liveSeq;
      unawaited(
        _processLiveMeasurement(
          live,
          displaySeq: displaySeq,
          sendSeq: _liveSeq,
          gen: _processGen,
        ),
      );
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
    required int displaySeq,
    required int sendSeq,
    required int gen,
  }) async {
    if (!mounted || gen != _processGen) return;

    if (mounted) {
      setState(() => _status = '第 $displaySeq 棵：取得 GPS 並建立任務…');
    }

    try {
      if (!await _ensureLiveSessionConfigured()) {
        return;
      }
      if (!mounted || gen != _processGen) return;

      final gps = await _resolveGpsForLiveMeasurement(displaySeq);
      if (!mounted || gen != _processGen) return;
      if (gps == null) {
        if (mounted) {
          setState(() {
            _gpsRetryLive = live;
            _gpsRetrySeq = displaySeq;
            _status = context
                .tr('ble_gps_retry_banner')
                .replaceAll('{n}', '$displaySeq');
          });
          _appendLog('[樹 $displaySeq] 未取得 GPS — 可重測 GPS，無需再按 SEND');
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
      if (!mounted || gen != _processGen) return;
      setState(() {
        _gpsRetryLive = null;
        _gpsRetrySeq = null;
      });
      final effectiveLive = _inProgressLive ?? live;
      final effectiveSend = _inProgressSendSeq ?? sendSeq;
      await _completeLiveMeasurementAfterGps(
        effectiveLive,
        displaySeq: displaySeq,
        sendSeq: effectiveSend,
        gps: gps,
        gen: gen,
      );
    } catch (e, st) {
      FieldLog.ble('process tree error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('處理失敗: $e')),
        );
      }
    } finally {
      if (gen == _processGen) {
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
      }
      if (_reconnectAfterProcessing && !_userDisconnect && _device != null) {
        _reconnectAfterProcessing = false;
        _appendLog('表單完成，恢復自動重連…');
        _scheduleReconnect();
      }
    }
  }

  Future<void> _completeLiveMeasurementAfterGps(
    BleLiveMeasurement live, {
    required int displaySeq,
    required int sendSeq,
    required FieldGpsCaptureResult gps,
    required int gen,
  }) async {
    if (!mounted || gen != _processGen) return;
    final lat = gps.latitude;
    final lon = gps.longitude;
    const hasGps = true;

    fieldGpsLog(
      'live tree=$displaySeq send=$sendSeq mode=$_gpsSource lat=$lat lon=$lon acc=${gps.accuracyM}m',
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
        'live_session_index': displaySeq,
        'live_send_index': sendSeq,
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
      setState(() => _status = '第 $displaySeq 棵：上傳任務…');
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
      _appendLog('[樹 $displaySeq] 建立任務失敗: ${result['message']}');
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
    _appendLog('[樹 $displaySeq] pending 已建立 session=$_liveSessionId');
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

    if (!mounted || gen != _processGen) return;
    setState(() => _status = '第 $displaySeq 棵：現場紀錄（人工 DBH / 拍照 / 提交）…');

    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    _formOpen = true;
    final isMaintRemeasure = widget.maintenanceTarget != null;
    // 表單內 auto-transfer 取得的正式 tree_survey_id；新增樹用它標記「本場新增」，
    // 避免回來後再做一次冪等 transfer（回空 id_mapping）而遺失 id。
    int? formTransferredTreeId;
    final success = await nav.push<bool>(
      MaterialPageRoute(
        builder: (_) => IntegratedTreeFormPage(
          task: task,
          autoTransferToTreeSurvey: true,
          transferSessionId: _liveSessionId,
          initialUpdateTreeLocation:
              isMaintRemeasure ? _pendingUpdateTreeLocation : null,
          initialSpeciesName:
              isMaintRemeasure ? widget.maintenanceTarget!.speciesName : null,
          initialSpeciesId:
              isMaintRemeasure ? widget.maintenanceTarget!.speciesId : null,
          onTreeSurveyTransferred: (id) => formTransferredTreeId = id,
        ),
      ),
    );
    _formOpen = false;
    _pendingUpdateTreeLocation = false;

    if (!mounted || gen != _processGen) return;

    if (success == true) {
      _completedCount++;
      _appendLog('[樹 $displaySeq] 表單提交成功（累計 $_completedCount 棵）');
      final sid = _liveSessionId;
      Map<String, dynamic>? transferResult;
      if (sid != null && sid.isNotEmpty) {
        try {
          final tr = await _pendingService.transferToTreeSurvey(sessionId: sid);
          transferResult = tr;
          if (tr['success'] == true) {
            final n = (tr['transferred_tree_ids'] as List?)?.length ?? 0;
            _appendLog(
              n > 0
                  ? '[樹 $displaySeq] 已轉入正式資料庫（本批 $n 筆）'
                  : '[樹 $displaySeq] 已在正式資料庫（冪等略過）',
            );
          } else {
            _appendLog(
              '[樹 $displaySeq] 自動轉移未完成: ${tr['message'] ?? '未知'}',
            );
            // [審計#19] 失敗不可只寫 log：明顯告警，避免調查員以為已入庫。
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    '⚠️ 樹 $displaySeq 尚未轉入正式資料庫：${tr['message'] ?? '未知原因'}\n'
                    '資料仍保留在待測量清單，可稍後於「待測量任務」重試。',
                  ),
                  backgroundColor: Colors.orange.shade800,
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          }
        } catch (e) {
          _appendLog('[樹 $displaySeq] 自動轉移失敗: $e');
          // [審計#19] 同上：網路錯誤等也要浮出，資料在 pending 未遺失。
          if (mounted) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  '⚠️ 樹 $displaySeq 轉移失敗（$e）\n'
                  '量測資料已保留在待測量清單，恢復連線後可於「待測量任務」重試。',
                ),
                backgroundColor: Colors.orange.shade800,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }
      if (!mounted) return;
      if (widget.maintenanceSessionContext && widget.maintenanceTarget == null) {
        // 優先用表單轉移當下取得的 id；第二次冪等 transfer 僅作後備。
        final newId =
            formTransferredTreeId ?? _treeSurveyIdFromTransfer(transferResult);
        nav.pop(
          MaintenanceSessionResult(
            success: true,
            treeSurveyId: newId,
            isNewTree: true,
          ),
        );
        return;
      }
      if (widget.maintenanceTarget != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(context.tr('maintain_done_short')),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        nav.pop(
          MaintenanceSessionResult(
            success: true,
            treeSurveyId: widget.maintenanceTarget!.treeSurveyId,
            projectTreeId: widget.maintenanceTarget!.projectTreeId,
            isNewTree: false,
          ),
        );
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context
                .tr('ble_tree_done')
                .replaceAll('{n}', '$displaySeq')
                .replaceAll('{total}', '$_completedCount'),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      _appendLog('[樹 $displaySeq] 表單取消，退回 pending id=${task.id}');
      await _pendingService
          .updateTaskStatus(task.id!, MeasurementStatus.pending)
          .catchError((_) => null);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            context.tr('ble_tree_cancel').replaceAll('{n}', '$displaySeq'),
          ),
        ),
      );
    }
  }

  Future<void> _retryPendingGps() async {
    final live = _gpsRetryLive;
    final seq = _gpsRetrySeq;
    if (live == null || seq == null || _isProcessingTree) return;
    _processGen++;
    final gen = _processGen;
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
      if (!mounted || gen != _processGen) return;
      setState(() {
        _gpsRetryLive = null;
        _gpsRetrySeq = null;
      });
      await _completeLiveMeasurementAfterGps(
        live,
        displaySeq: seq,
        sendSeq: _liveSeq,
        gps: gps,
        gen: gen,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重測 GPS 失敗: $e')),
        );
      }
    } finally {
      if (gen == _processGen) {
        _isProcessingTree = false;
        if (mounted && _gpsRetryLive == null) {
          setState(() {
            _status = _isConnected
                ? context.tr('ble_status_connected')
                : _status;
          });
        }
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
      if (!mounted) return;
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
  /// 維護重測：先問是否更新樹位；若要才定位，否則沿用原座標。
  Future<FieldGpsCaptureResult?> _resolveGpsForLiveMeasurement(int seq) async {
    _gpsDialogOpen = true;
    try {
      final maint = widget.maintenanceTarget;
      if (maint != null) {
        final label = TreeIdDisplay.fieldListLabel(
          projectTreeId: maint.projectTreeId,
          systemTreeId: maint.systemTreeId,
        );
        final decision = await showMaintenanceRemeasureGpsFlow(
          context,
          treeLabel: label,
        );
        if (decision == null) return null;
        _pendingUpdateTreeLocation = decision.updateTreeLocation;
        final gps = resolveMaintenancePendingGps(
          decision: decision,
          existingLat: maint.treeLatitude,
          existingLon: maint.treeLongitude,
        );
        if (gps == null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('此樹尚無座標，請選擇「更新 GPS」'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return gps;
      }
      _pendingUpdateTreeLocation = false;
      return await showFieldGpsCaptureDialog(
        context,
        mode: 'tree',
        title: '第 $seq 棵 · 樹旁 GPS',
      );
    } finally {
      _gpsDialogOpen = false;
    }
  }

  int? _treeSurveyIdFromTransfer(Map<String, dynamic>? tr) =>
      treeSurveyIdFromTransfer(tr);

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

  void _appendLog(String line) => FieldLog.ble(line);

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
    await _safeStopScan();
    if (_device != null) {
      try {
        if (_device!.isConnected) await _device!.disconnect();
      } catch (_) {}
    }
    _device = null;
    if (mounted) {
      setState(() {
        _isConnected = false;
        _isListening = false;
        _status = context.tr('ble_status_pick_device');
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

  Future<void> _pickAnotherDevice() async {
    // #region agent log
    DebugSessionLog.emit(
      'ble_live_session_page.dart:_pickAnotherDevice',
      'pick another device',
      hypothesisId: 'H-B',
      data: {
        'beforeConnected': _isConnected,
        'deviceId': _device?.remoteId.str,
      },
      runId: 'post-fix',
    );
    // #endregion
    await _disconnect();
    if (!mounted) return;
    setState(() {
      _reconnectAttempt = 0;
      _scannerEpoch++;
    });
    _beginBlePrepare();
    // #region agent log
    DebugSessionLog.emit(
      'ble_live_session_page.dart:_pickAnotherDevice',
      'after disconnect',
      hypothesisId: 'H-B',
      data: {
        'showScanner': _showBleScanner,
        'userDisconnect': _userDisconnect,
        'deviceNull': _device == null,
      },
    );
    // #endregion
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
              onPressed: _isProcessingTree ? null : _pickAnotherDevice,
              child: Text(context.tr('ble_reconnect_scan_other')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadyPanel() {
    final hasData = _lastMeasurement != null;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Card(
              elevation: 0,
              color: Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      hasData ? Icons.check_circle : Icons.touch_app,
                      size: 52,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('ble_ready_title'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    _readyStep(context.tr('ble_ready_step1')),
                    _readyStep(context.tr('ble_ready_step2')),
                    _readyStep(context.tr('ble_ready_step3')),
                    if (!hasData) ...[
                      const SizedBox(height: 16),
                      Text(
                        context.tr('ble_ready_waiting'),
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Spacer(),
            if (!_isProcessingTree)
              TextButton.icon(
                onPressed: _pickAnotherDevice,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(context.tr('ble_reconnect_scan_other')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _readyStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right, size: 20, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _buildChecklistGate() {
    return Expanded(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.fact_check_outlined,
                  size: 48, color: Colors.teal.shade700),
              const SizedBox(height: 16),
              Text(
                context.tr('ble_checklist_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await BleInstrumentChecklist.show(context);
                  if (!mounted) return;
                  setState(() => _checklistReady = ok);
                  if (ok && widget.initialDevice != null && _device == null) {
                    await _connect(widget.initialDevice!);
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: Text(context.tr('ble_checklist_confirm')),
              ),
            ],
          ),
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
                            '已完成 $_completedCount 棵 · 目前第 $_displayTreeSeq 棵',
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
                  if (_device != null)
                    Text(
                      _isConnected
                          ? '已連線：${_device!.platformName.isNotEmpty ? _device!.platformName : _device!.remoteId.str}'
                          : '儀器：${_device!.remoteId.str}（未連線）',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isConnected
                            ? Colors.green.shade800
                            : Colors.orange.shade800,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_gpsRetryLive != null) _buildGpsRetryBanner(),
          if (_canAutoReconnect && !_isProcessingTree)
            _buildReconnectPanel()
          else if (!_checklistReady)
            _buildChecklistGate()
          else if (_showBleScanner)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: BleDeviceScanner(
                  key: ValueKey('ble_scan_$_scannerEpoch'),
                  prepareFuture: _blePrepare?.future,
                  onDeviceSelected: (device) {
                    if (_isProcessingTree) return;
                    _connect(device);
                  },
                ),
              ),
            )
          else if (_isConnected && !_isProcessingTree)
            _buildReadyPanel(),
          if (last != null)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text('$_displayTreeSeq'),
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
        ],
      ),
    );
  }
}
