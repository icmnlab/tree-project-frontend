import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'location_helper.dart';

class FieldGpsQuality {
  static const double maxAccuracyM = 5.0;
  static const int requiredSamples = 5;
  static const double maxSampleSpreadM = 5.0;
  static const Duration autoTimeout = Duration(seconds: 90);
}

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
  debugPrint('[FieldGPS] $message');
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
  StreamSubscription<Position>? _sub;
  Timer? _timeoutTimer;
  bool _busy = false;
  String _status = '準備中…';
  Position? _lastPosition;
  final List<Position> _samples = [];

  bool get _isTreeMode => widget.mode == 'tree';

  @override
  void initState() {
    super.initState();
    fieldGpsLog('open mode=${widget.mode}');
    if (_isTreeMode) {
      _status = '請站定位置後按「取得 GPS」';
    } else {
      _startAutoCapture();
    }
  }

  @override
  void dispose() {
    _stopStream();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _stopStream() {
    _sub?.cancel();
    _sub = null;
  }

  Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) {
      setState(() => _status = '位置權限被永久拒絕，請至設定開啟');
      return false;
    }
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = '需要位置權限才能定位');
      return false;
    }
    return true;
  }

  bool _accuracyOk(double accuracy) =>
      accuracy > 0 && accuracy <= FieldGpsQuality.maxAccuracyM;

  void _pushSample(Position p) {
    if ((p.latitude == 0 && p.longitude == 0) || !_accuracyOk(p.accuracy)) {
      return;
    }
    _samples.add(p);
    if (_samples.length > FieldGpsQuality.requiredSamples + 2) {
      _samples.removeAt(0);
    }
  }

  bool _samplesStable() {
    if (_samples.length < FieldGpsQuality.requiredSamples) return false;
    final recent =
        _samples.sublist(_samples.length - FieldGpsQuality.requiredSamples);
    final lat =
        recent.map((p) => p.latitude).reduce((a, b) => a + b) / recent.length;
    final lon =
        recent.map((p) => p.longitude).reduce((a, b) => a + b) / recent.length;
    for (final p in recent) {
      if (Geolocator.distanceBetween(
            lat,
            lon,
            p.latitude,
            p.longitude,
          ) >
          FieldGpsQuality.maxSampleSpreadM) {
        return false;
      }
    }
    return true;
  }

  FieldGpsCaptureResult? _buildResult() {
    if (_samples.isEmpty) return null;
    final recent = _samples.length >= FieldGpsQuality.requiredSamples
        ? _samples.sublist(_samples.length - FieldGpsQuality.requiredSamples)
        : _samples;
    final lat =
        recent.map((p) => p.latitude).reduce((a, b) => a + b) / recent.length;
    final lon =
        recent.map((p) => p.longitude).reduce((a, b) => a + b) / recent.length;
    final acc = recent.map((p) => p.accuracy).reduce(math.min);
    return FieldGpsCaptureResult(
      latitude: lat,
      longitude: lon,
      accuracyM: acc,
      sampleCount: recent.length,
      mode: widget.mode,
    );
  }

  void _onPosition(Position p) {
    if (!mounted) return;
    _lastPosition = p;
    final ok = _accuracyOk(p.accuracy);
    fieldGpsLog(
      'mode=${widget.mode} acc=${p.accuracy.toStringAsFixed(1)}m '
      'samples=${_samples.length} ok=$ok',
    );
    if (!ok) {
      setState(() {
        _status =
            '等待高品質 GPS… ±${p.accuracy.toStringAsFixed(0)}m (需 ≤${FieldGpsQuality.maxAccuracyM.toStringAsFixed(0)}m)';
      });
      return;
    }
    _pushSample(p);
    final stable = !_isTreeMode && _samplesStable();
    setState(() {
      _status = stable
          ? 'GPS 已鎖定 ±${p.accuracy.toStringAsFixed(1)}m'
          : '取樣 ${_samples.length}/${FieldGpsQuality.requiredSamples}';
    });
    if (stable) {
      final result = _buildResult();
      if (result != null) {
        _stopStream();
        Navigator.pop(context, result);
      }
    }
  }

  Future<void> _startAutoCapture() async {
    if (!await _ensurePermission()) return;
    setState(() {
      _busy = true;
      _status = '自動定位中…';
    });
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(FieldGpsQuality.autoTimeout, () {
      if (!mounted || _isTreeMode) return;
      setState(() {
        _status = '定位逾時，請移至空曠處後重試';
        _busy = false;
      });
      _stopStream();
    });
    _sub = Geolocator.getPositionStream(
      locationSettings: buildLocationSettings(
        distanceFilter: 1,
        intervalMs: 800,
      ),
    ).listen(_onPosition, onError: (e) {
      if (mounted) setState(() => _status = 'GPS 錯誤: $e');
    });
  }

  Future<void> _manualCapture() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '取得 GPS 中…';
    });
    try {
      if (!await _ensurePermission()) return;
      final p = await getHighAccuracyPosition(
        timeout: const Duration(seconds: 15),
      );
      if (p == null) {
        setState(() => _status = '無法取得 GPS');
        return;
      }
      _lastPosition = p;
      if (!_accuracyOk(p.accuracy)) {
        setState(() {
          _status =
              '精度 ±${p.accuracy.toStringAsFixed(0)}m 不足，需 ≤${FieldGpsQuality.maxAccuracyM.toStringAsFixed(0)}m';
        });
        return;
      }
      _samples
        ..clear()
        ..add(p);
      setState(() => _status = '已取得 ±${p.accuracy.toStringAsFixed(1)}m');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmManual() {
    final result = _buildResult();
    if (result != null) Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _isTreeMode &&
        _samples.isNotEmpty &&
        _lastPosition != null &&
        _accuracyOk(_lastPosition!.accuracy);
    return AlertDialog(
      title: Text(widget.title ??
          (_isTreeMode ? '樹旁 GPS 定位' : '測站 GPS 自動定位')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_status, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (_lastPosition != null)
            Text(
              '${_lastPosition!.latitude.toStringAsFixed(6)}, '
              '${_lastPosition!.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 12),
            ),
          if (!_isTreeMode)
            LinearProgressIndicator(
              value: (_samples.length / FieldGpsQuality.requiredSamples)
                  .clamp(0.0, 1.0),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (_isTreeMode) ...[
          TextButton(
            onPressed: _busy ? null : _manualCapture,
            child: const Text('取得 GPS'),
          ),
          ElevatedButton(
            onPressed: canConfirm ? _confirmManual : null,
            child: const Text('確認'),
          ),
        ] else
          TextButton(
            onPressed: _busy ? null : _startAutoCapture,
            child: const Text('重試'),
          ),
      ],
    );
  }
}
