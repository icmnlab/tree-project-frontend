import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 共用 BLE 掃描列表：顯示裝置供使用者點選（不自動連線第一台）
class BleDeviceScanner extends StatefulWidget {
  /// 僅列出名稱含 VLGEO 的裝置
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
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  String? _status;

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _stopScan();
    setState(() {
      _isScanning = true;
      _results.clear();
      _status = '掃描中…';
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      if (!mounted) return;
      final filtered = widget.vlgeoOnly
          ? list.where((r) {
              final n = r.device.platformName.toUpperCase();
              return n.contains('VLGEO') || n.contains('HAGLOF');
            })
          : list;
      setState(() {
        _results
          ..clear()
          ..addAll(filtered);
        _results.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    Future.delayed(const Duration(seconds: 15), () {
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
      setState(() {
        _isScanning = false;
        _status = _results.isEmpty ? '掃描結束，可再試一次' : '掃描結束';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
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
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: _results.isEmpty
              ? Center(
                  child: Text(
                    _isScanning
                        ? '尋找 VLGEO2…'
                        : '尚未發現裝置\n請確認儀器藍牙已開啟',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  itemCount: _results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = _results[i];
                    final name = r.device.platformName.isNotEmpty
                        ? r.device.platformName
                        : '未知裝置';
                    return ListTile(
                      leading: const Icon(Icons.sensors),
                      title: Text(name),
                      subtitle: Text(
                        '${r.device.remoteId.str}  ·  RSSI ${r.rssi}',
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
