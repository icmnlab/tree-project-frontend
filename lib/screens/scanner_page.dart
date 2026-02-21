import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import '../services/scanner_service.dart';
import '../services/ar_measurement_service.dart';

/// 即時掃描頁面
///
/// 全螢幕相機預覽，串流至 WebSocket 後端，
/// 即時顯示 mask 疊加與 DBH 數值，支援 Lock 鎖定擷取。
class ScannerPage extends StatefulWidget {
  final double? initialDbh;

  const ScannerPage({super.key, this.initialDbh});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isCameraReady = false;

  final ScannerService _scanner = ScannerService();
  StreamSubscription<ScannerResponse>? _responseSub;

  // 即時回應
  Uint8List? _maskBytes;
  double? _dbh;
  double? _confidence;
  String? _connectionError;

  // 串流控制
  Timer? _captureTimer;
  bool _isStreaming = false;
  bool _isCapturePending = false;

  // Lock 鎖定結果
  double? _lockedDbh;
  double? _lockedConfidence;
  Uint8List? _lockedMask;
  File? _lockedImageFile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _connectAndListen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreaming();
    _responseSub?.cancel();
    _scanner.disconnect();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
      if (_isStreaming) _startStreaming();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();
      await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (mounted) {
        setState(() => _isCameraReady = true);
        _startStreaming();
      }
    } catch (e) {
      debugPrint('[ScannerPage] Camera init: $e');
      if (mounted) setState(() {});
    }
  }

  Future<void> _connectAndListen() async {
    try {
      await _scanner.connect();
      if (!mounted) return;
      setState(() => _connectionError = null);

      _responseSub = _scanner.responseStream?.listen((resp) {
        if (!mounted) return;
        setState(() {
          _maskBytes = resp.maskBytes;
          _dbh = resp.dbh;
          _confidence = resp.confidence;
        });
      });
    } catch (e) {
      debugPrint('[ScannerPage] Connect: $e');
      if (mounted) {
        setState(() => _connectionError = '無法連線至掃描服務');
      }
    }
  }

  void _startStreaming() {
    if (_isStreaming || _controller == null || !_controller!.value.isInitialized) return;

    _isStreaming = true;
    _scanner.startStreaming();

    _captureTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
      _captureAndSendFrame();
    });
  }

  void _stopStreaming() {
    _captureTimer?.cancel();
    _captureTimer = null;
    _isStreaming = false;
    _scanner.stopStreaming();
  }

  Future<void> _captureAndSendFrame() async {
    if (_isCapturePending || _controller == null || !_scanner.isConnected) return;

    _isCapturePending = true;
    try {
      final xFile = await _controller!.takePicture();
      final file = File(xFile.path);
      final bytes = await file.readAsBytes();

      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final resized = img.copyResize(
        decoded,
        width: ScannerService.targetWidth,
        height: ScannerService.targetHeight,
        interpolation: img.Interpolation.linear,
      );
      final jpeg = img.encodeJpg(resized, quality: 85);
      if (jpeg.isEmpty) return;

      final base64 = base64Encode(jpeg);
      _scanner.sendFrame(base64);

      try { await file.delete(); } catch (_) {}
    } catch (e) {
      debugPrint('[ScannerPage] Capture: $e');
    } finally {
      _isCapturePending = false;
    }
  }

  Future<void> _lockCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    _stopStreaming();

    try {
      final xFile = await _controller!.takePicture();
      final file = File(xFile.path);

      setState(() {
        _lockedDbh = _dbh;
        _lockedConfidence = _confidence;
        _lockedMask = _maskBytes;
        _lockedImageFile = file;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lockedDbh != null
                ? '已鎖定 DBH: ${_lockedDbh!.toStringAsFixed(1)} cm'
                : '已鎖定，DBH 待伺服器回應'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('擷取失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _useLockedResult() {
    if (_lockedDbh == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('尚未取得 DBH，請稍候再鎖定'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = MeasurementResult(
      diameterCm: _lockedDbh!,
      confidenceScore: _lockedConfidence ?? 0.8,
      method: MeasurementMethod.pureVision,
      points: [],
      capturedImagePath: _lockedImageFile?.path,
      notes: 'Scan Mode 即時掃描',
    );

    Navigator.of(context).pop(result);
  }

  void _retry() {
    _lockedDbh = null;
    _lockedConfidence = null;
    _lockedMask = null;
    _lockedImageFile?.delete();
    _lockedImageFile = null;
    setState(() {});
    _startStreaming();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          _buildMaskOverlay(),
          _buildHud(),
          _buildTopBar(),
          _buildBottomControls(),
          if (_connectionError != null) _buildConnectionBanner(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_controller != null && _isCameraReady) {
      return Center(child: CameraPreview(_controller!));
    }
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.tealAccent),
          SizedBox(height: 16),
          Text('初始化相機…', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildMaskOverlay() {
    if (_lockedMask != null) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Image.memory(
            _lockedMask!,
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.5),
          ),
        ),
      );
    }
    if (_maskBytes != null) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Image.memory(
            _maskBytes!,
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.5),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildHud() {
    final dbh = _lockedDbh ?? _dbh;
    if (dbh == null) return const SizedBox.shrink();

    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      left: 20,
      right: 20,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.tealAccent.withOpacity(0.6), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withOpacity(0.2),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.straighten,
                color: Colors.tealAccent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DBH',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                  Text(
                    '${dbh.toStringAsFixed(1)} cm',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  if (_lockedConfidence != null || _confidence != null)
                    Text(
                      '信心度 ${((_lockedConfidence ?? _confidence ?? 0) * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: Colors.tealAccent.withOpacity(0.9),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top,
          left: 8,
          right: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.6),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const Expanded(
              child: Text(
                '即時掃描',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final hasLockedResult = _lockedDbh != null || _lockedImageFile != null;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
          top: 20,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (hasLockedResult) ...[
              OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('重試', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: _useLockedResult,
                icon: const Icon(Icons.check),
                label: const Text('使用此結果'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ] else
              _buildLockButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildLockButton() {
    final canLock = _scanner.isConnected && _isCameraReady;

    return GestureDetector(
      onTap: canLock ? _lockCapture : null,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: canLock ? Colors.tealAccent : Colors.grey,
            width: 4,
          ),
          boxShadow: canLock
              ? [
                  BoxShadow(
                    color: Colors.tealAccent.withOpacity(0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Icon(
            Icons.lock,
            color: canLock ? Colors.tealAccent : Colors.grey,
            size: 36,
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionBanner() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '無法連線',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _connectionError ?? '',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '請確認 ws://localhost:8100 或 ngrok 已啟動',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
