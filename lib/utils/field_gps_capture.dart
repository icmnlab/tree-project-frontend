import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'field_log.dart';
import 'location_helper.dart';
import '../debug/debug_session_log.dart';

/// 僅供參考：精度較差時顯示提醒，不阻擋確認
const double kGpsAccuracyWarnM = 20.0;

class FieldGpsCaptureResult {
  final double latitude;
  final double longitude;
  final double accuracyM;
  final int sampleCount;
  final String mode;

  const FieldGpsCaptureResult({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.sampleCount,
    required this.mode,
  });
}

void fieldGpsLog(String message) {
  FieldLog.gps(message);
}

Future<FieldGpsCaptureResult?> showFieldGpsCaptureDialog(
  BuildContext context, {
  required String mode,
  String? title,
}) {
  return showDialog<FieldGpsCaptureResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FieldGpsCaptureDialog(mode: mode, title: title),
  );
}

class _FieldGpsCaptureDialog extends StatefulWidget {
  final String mode;
  final String? title;

  const _FieldGpsCaptureDialog({required this.mode, this.title});

  @override
  State<_FieldGpsCaptureDialog> createState() => _FieldGpsCaptureDialogState();
}

class _FieldGpsCaptureDialogState extends State<_FieldGpsCaptureDialog> {
  bool _busy = false;
  String _status = '請站定樹旁後按「取得 GPS」';
  Position? _lastPosition;

  static bool _coordsValid(Position p) =>
      p.latitude != 0 || p.longitude != 0;

  String? get _accuracyHint {
    final p = _lastPosition;
    if (p == null) return null;
    if (p.accuracy <= 0) {
      return '未取得精度資訊，請確認座標是否合理';
    }
    if (p.accuracy > kGpsAccuracyWarnM) {
      return '精度約 ±${p.accuracy.toStringAsFixed(0)} m，建議移至空曠處或稍後再測';
    }
    return '精度約 ±${p.accuracy.toStringAsFixed(0)} m';
  }

  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _status = '位置權限被永久拒絕，請至設定開啟');
      }
      return false;
    }
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _status = '需要位置權限才能定位');
      }
      return false;
    }
    return true;
  }

  Future<void> _manualCapture() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _status = '取得 GPS 中…';
    });
    try {
      if (!await _ensurePermission()) return;
      final p = await getHighAccuracyPosition(
        timeout: const Duration(seconds: 15),
      );
      if (!mounted) {
        // #region agent log
        DebugSessionLog.emit(
          'field_gps_capture.dart:_manualCapture',
          'unmounted after gps',
          hypothesisId: 'H-C',
        );
        // #endregion
        return;
      }
      if (p == null || !_coordsValid(p)) {
        setState(() => _status = '無法取得 GPS，請確認定位已開啟');
        return;
      }
      _lastPosition = p;
      fieldGpsLog(
        'capture lat=${p.latitude} lon=${p.longitude} acc=${p.accuracy}m',
      );
      setState(() => _status = '已取得座標，請確認後按「確認」');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirm() {
    final p = _lastPosition;
    if (p == null || !_coordsValid(p)) return;
    Navigator.pop(
      context,
      FieldGpsCaptureResult(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyM: p.accuracy > 0 ? p.accuracy : 999,
        sampleCount: 1,
        mode: widget.mode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _lastPosition;
    final canConfirm = p != null && _coordsValid(p);
    return AlertDialog(
      title: Text(widget.title ?? '樹旁 GPS 定位'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (p != null) ...[
            const SizedBox(height: 8),
            Text(
              '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (_accuracyHint != null) ...[
            const SizedBox(height: 8),
            Text(
              _accuracyHint!,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _busy ? null : _manualCapture,
          child: const Text('取得 GPS'),
        ),
        ElevatedButton(
          onPressed: canConfirm && !_busy ? _confirm : null,
          child: const Text('確認'),
        ),
      ],
    );
  }
}
