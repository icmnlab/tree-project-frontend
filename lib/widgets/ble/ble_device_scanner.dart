import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// 共用 BLE 掃描列表：權限／藍牙狀態檢查後掃描，供使用者點選（不自動連線第一台）
class BleDeviceScanner extends StatefulWidget {
  /// 預設僅列 VLGEO / Haglof 候選；可切換顯示全部
  final bool vlgeoOnly;

  final void Function(BluetoothDevice device) onDeviceSelected;

  const BleDeviceScanner({
    super.key,
    this.vlgeoOnly = true,
    required this.onDeviceSelected,
  });

  @override
  State<BleDeviceScanner> createState() => _BleDeviceScannerState();
}

class _BleDeviceScannerState extends State<BleDeviceScanner> {
  bool _isScanning = false;
  bool _showAllDevices = false;
  bool _permissionsReady = false;
  final List<ScanResult> _allResults = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  String? _status;

  @override
  void initState() {
    super.initState();
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      if (!mounted) return;
      setState(() => _adapterState = s);
      if (s == BluetoothAdapterState.on && _permissionsReady && !_isScanning) {
        _startScan();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _stopScan();
    _adapterSub?.cancel();
    super.dispose();
  }

  List<ScanResult> get _visibleResults {
    if (_showAllDevices || !widget.vlgeoOnly) return _allResults;
    return _allResults.where(_isVlgeoCandidate).toList();
  }

  static String _deviceLabel(ScanResult r) {
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    return r.device.remoteId.str;
  }

  static bool _hasInstrumentService(ScanResult r) {
    for (final g in r.advertisementData.serviceUuids) {
      final u = g.toString().toUpperCase();
      if (u.contains('9E000000') || u.contains('6E400001')) return true;
    }
    return false;
  }

  static bool _isVlgeoCandidate(ScanResult r) {
    final n = _deviceLabel(r).toUpperCase();
    if (n.contains('VLGEO') ||
        n.contains('HAGLOF') ||
        n.contains('VERTEX')) {
      return true;
    }
    return _hasInstrumentService(r);
  }

  Future<void> _bootstrap() async {
    final ok = await _ensurePermissions();
    if (!mounted) return;
    setState(() {
      _permissionsReady = ok;
      if (!ok) {
        _status = '需要藍牙與定位權限才能掃描 VLGEO2';
      }
    });
    if (!ok) return;

    final state = await FlutterBluePlus.adapterState.first;
    if (!mounted) return;
    setState(() => _adapterState = state);
    if (state == BluetoothAdapterState.on) {
      await _startScan();
    } else {
      setState(() => _status = '請先開啟手機藍牙');
    }
  }

  Future<bool> _ensurePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    final scan = statuses[Permission.bluetoothScan];
    final connect = statuses[Permission.bluetoothConnect];
    final loc = statuses[Permission.location];

    if (scan == PermissionStatus.permanentlyDenied ||
        connect == PermissionStatus.permanentlyDenied ||
        loc == PermissionStatus.permanentlyDenied) {
      if (mounted) _showPermissionDialog();
      return false;
    }
    return scan?.isGranted == true && connect?.isGranted == true;
  }

  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要權限'),
        content: const Text(
          '請在系統設定中允許「附近裝置／藍牙」與「定位」權限，才能掃描 VLGEO2。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestTurnOnBluetooth() async {
    try {
      await FlutterBluePlus.turnOn();
    } catch (_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('請開啟藍牙'),
          content: const Text('請在系統設定開啟藍牙，再返回此頁掃描 VLGEO2。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('了解'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _startScan() async {
    if (!_permissionsReady) {
      final ok = await _ensurePermissions();
      if (!ok || !mounted) return;
      setState(() => _permissionsReady = true);
    }

    if (_adapterState != BluetoothAdapterState.on) {
      setState(() => _status = '藍牙未開啟');
      return;
    }

    await _stopScan();
    setState(() {
      _isScanning = true;
      _allResults.clear();
      _status = '掃描中…';
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 20),
        androidUsesFineLocation: false,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _status = '掃描失敗: $e';
        });
      }
      return;
    }

    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      if (!mounted) return;
      setState(() {
        _allResults
          ..clear()
          ..addAll(list);
        _allResults.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isScanning) _stopScan();
    });
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    if (mounted) {
      final n = _visibleResults.length;
      setState(() {
        _isScanning = false;
        _status = n == 0 ? '掃描結束，可再試一次' : '掃描結束（$n 台）';
      });
    }
  }

  Widget _buildBluetoothOff() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: Colors.orange.shade700),
            const SizedBox(height: 16),
            const Text(
              '藍牙尚未開啟',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '請開啟藍牙以掃描 VLGEO2',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _requestTurnOnBluetooth,
              icon: const Icon(Icons.bluetooth),
              label: const Text('開啟藍牙'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionsReady) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('需要藍牙權限才能掃描儀器'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _bootstrap,
                child: const Text('授予權限並掃描'),
              ),
            ],
          ),
        ),
      );
    }

    if (_adapterState != BluetoothAdapterState.on) {
      return _buildBluetoothOff();
    }

    final results = _visibleResults;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _isScanning ? null : _startScan,
                icon: const Icon(Icons.bluetooth_searching),
                label: Text(_isScanning ? '掃描中…' : '掃描 BLE 裝置'),
              ),
            ),
            if (_isScanning) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: _stopScan,
                icon: const Icon(Icons.stop),
                tooltip: '停止掃描',
              ),
            ],
          ],
        ),
        if (widget.vlgeoOnly) ...[
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('顯示全部 BLE 裝置', style: TextStyle(fontSize: 13)),
            subtitle: const Text(
              '若找不到 VLGEO2，可開啟後依 MAC／訊號選擇',
              style: TextStyle(fontSize: 11),
            ),
            value: _showAllDevices,
            onChanged: _isScanning
                ? null
                : (v) => setState(() => _showAllDevices = v),
          ),
        ],
        if (_status != null) ...[
          const SizedBox(height: 4),
          Text(_status!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    _isScanning
                        ? '尋找 VLGEO2…\n（名稱或 Haglof/NUS 服務）'
                        : '尚未發現裝置\n'
                            '1. 確認儀器藍牙已開\n'
                            '2. 手機靠近儀器\n'
                            '3. 可開啟「顯示全部」再掃一次',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                )
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = results[i];
                    final name = _deviceLabel(r);
                    final tag = _isVlgeoCandidate(r) ? 'VLGEO?' : '其他';
                    return ListTile(
                      leading: Icon(
                        Icons.sensors,
                        color: _isVlgeoCandidate(r)
                            ? Colors.teal.shade700
                            : Colors.grey,
                      ),
                      title: Text(name),
                      subtitle: Text(
                        '$tag · ${r.device.remoteId.str} · RSSI ${r.rssi}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        _stopScan();
                        widget.onDeviceSelected(r.device);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
