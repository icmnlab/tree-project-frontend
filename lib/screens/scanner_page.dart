import 'dart:async';
import 'dart:io';
import 'dart:math' show atan, min, max;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:exif/exif.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/pure_vision_dbh_service.dart';
import '../services/ar_measurement_service.dart';
import '../services/tflite_tracking_service.dart';

/// 純視覺 DBH 測量頁面 (ScannerPage)
///
/// 流程：
/// 1. 相機拍攝 (實時 AR Bounding Box) → 2. AI 推論 → 3. 顯示結果
class ScannerPage extends StatefulWidget {
  final double? initialDbh;
  final String? speciesName;

  const ScannerPage({
    super.key,
    this.initialDbh,
    this.speciesName,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

enum _PageStep { camera, drawBbox, processing, result }

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  // Camera
  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // State
  _PageStep _step = _PageStep.camera;
  File? _capturedImage;
  Size? _imageSize; // 原始照片尺寸

  // Bbox drawing
  Offset? _bboxStart;
  Offset? _bboxEnd;
  Rect? _currentBbox;

  // Result
  PureVisionDbhResult? _result;
  AutoMeasureResult? _autoResult;
  String? _errorMessage;

  // Auto mode
  bool _isAutoMode = true;

  // EXIF 焦距
  double? _focalLengthMm;
  double? _focalLength35mm;

  // EXIF 手機型號 (用於感測器寬度查詢)
  String? _phoneMake;
  String? _phoneModel;

  // Service
  final PureVisionDbhService _service = PureVisionDbhService();
  bool _serviceAvailable = false;

  // YOLOv8n-seg edge tracking
  final TfliteObjectTrackingService _tfliteTracker =
      TfliteObjectTrackingService();
  bool _isDetecting = false;
  int _lastInferenceMs = 0; // 推論節流：上次推論完成時間
  // 自適應推論冷卻：根據實際推論時間動態調整，避免針對特定手機
  int _inferCooldownMs = 300; // 初始值，會自動調整
  int _lastInferenceDurationMs = 0; // 用於自適應
  int _inferCount = 0; // 推論計數器（debug 用）
  Rect? _trackedBbox; // Current tracked bbox from YOLO
  double? _trackedConfidence; // 最新偵測信心度
  String? _trackedLabel; // 最新偵測標籤

  // 方向感測器：偵測手機是否橫拿
  StreamSubscription? _accelSubscription;
  bool _isLandscapeHeld = false; // true = 手機橫拿，應提示使用者

  // 即時影像串流是否可用（LEGACY 裝置可能不支援同時 3 個 camera use case）
  bool _liveDetectionAvailable = true;

  // 重試 ML 服務連線
  bool _isRetryingService = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 強制鎖定螢幕方向為直向
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    _initializeTflite();
    _initializeCamera();
    _checkService();
    _startOrientationMonitor();
  }

  Future<void> _initializeTflite() async {
    await _tfliteTracker.initialize();
    if (!_tfliteTracker.isInitialized) {
      debugPrint('[Scanner] YOLO 初始化失敗，即時偵測停用');
      if (mounted) {
        setState(() {
          _liveDetectionAvailable = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accelSubscription?.cancel();
    // 恢復允許所有方向
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    try {
      if (_cameraController?.value.isStreamingImages == true) {
        _cameraController?.stopImageStream();
      }
    } catch (_) {}
    _cameraController?.dispose();
    _tfliteTracker.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _cameraController;
    if (state == AppLifecycleState.inactive) {
      // 清理相機資源；先停止影像串流再 dispose
      try {
        if (ctrl?.value.isStreamingImages == true) {
          ctrl?.stopImageStream();
        }
        ctrl?.dispose();
      } catch (_) {}
      _cameraController = null;
      _isCameraInitialized = false;
      _isDetecting = false;
    } else if (state == AppLifecycleState.resumed &&
        _step == _PageStep.camera) {
      _initializeCamera();
    }
  }

  /// 從 EXIF 欄位字串（可能含 "mm"、空白、單位符號）抽出數字部分。
  /// 保留小數點 / 負號 / 正號，去掉其他字元。
  /// 若抽不到有效字串，回傳空字串（讓 double.tryParse 回傳 null）。
  String _stripNonNumeric(String s) {
    final buf = StringBuffer();
    bool dotSeen = false;
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      if (RegExp(r'[0-9]').hasMatch(c)) {
        buf.write(c);
      } else if (c == '.' && !dotSeen) {
        buf.write(c);
        dotSeen = true;
      } else if (c == '-' && buf.isEmpty) {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  Future<void> _checkService() async {
    _serviceAvailable = await _service.isServiceAvailable();
    if (mounted) setState(() {});
  }

  Future<void> _retryServiceCheck() async {
    if (_isRetryingService) return;
    setState(() => _isRetryingService = true);
    _serviceAvailable = await _service.isServiceAvailable();
    if (mounted) setState(() => _isRetryingService = false);
  }

  /// 重新啟動影像串流（從結果頁或 bbox 頁返回相機時呼叫）
  void _restartImageStream() {
    // 若裝置不支援即時影像串流（如 LEGACY 相機），跳過
    if (!_liveDetectionAvailable) return;

    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) {
      // Controller 已經不可用，需要重新初始化
      _initializeCamera();
      return;
    }
    // 若已在串流中，不重複啟動
    if (ctrl.value.isStreamingImages) return;
    // 嘗試重啟影像串流
    try {
      final cameras = ctrl.description;
      ctrl.startImageStream((CameraImage image) {
        if (_isDetecting || !_isAutoMode || _step != _PageStep.camera) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - _lastInferenceMs < _inferCooldownMs) return;
        _isDetecting = true;
        _processCameraImage(image, cameras);
      });
    } catch (e) {
      debugPrint('[ScannerPage] 重啟串流失敗，重新初始化相機: $e');
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // 嘗試不同解析度初始化（某些裝置在高解析度下可能失敗）
      CameraController? controller;
      for (final preset in [
        ResolutionPreset.high,
        ResolutionPreset.medium,
        ResolutionPreset.low
      ]) {
        try {
          controller = CameraController(
            camera,
            preset,
            enableAudio: false,
            imageFormatGroup: Platform.isAndroid
                ? ImageFormatGroup.nv21
                : ImageFormatGroup.bgra8888,
          );
          await controller.initialize();
          debugPrint('[ScannerPage] 相機初始化成功 (preset: $preset)');
          break;
        } catch (e) {
          debugPrint('[ScannerPage] 相機初始化失敗 (preset: $preset): $e');
          try {
            controller?.dispose();
          } catch (_) {}
          controller = null;
        }
      }

      if (controller == null) {
        debugPrint('[ScannerPage] 所有解析度都無法初始化相機');
        return;
      }
      _cameraController = controller;

      try {
        await _cameraController!
            .lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (e) {
        debugPrint('[ScannerPage] lockCaptureOrientation 失敗（繼續）: $e');
      }

      // 記錄相機解析度，供除錯使用
      final ps = _cameraController!.value.previewSize;
      if (ps != null) {
        debugPrint('[ScannerPage] 相機預覽解析度: ${ps.width}x${ps.height}'
            ' (sensor orientation: ${camera.sensorOrientation}°)');
      }

      // 嘗試開始影像串流進行物件追蹤
      // LEGACY 裝置可能無法同時使用 Preview + ImageCapture + ImageAnalysis
      _liveDetectionAvailable = false;
      try {
        _cameraController!.startImageStream((CameraImage image) {
          if (_isDetecting || !_isAutoMode || _step != _PageStep.camera) return;
          // 推論冷卻：避免在低階 GPU 上連續推論導致 Camera2 pipeline 超時
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - _lastInferenceMs < _inferCooldownMs) return;
          _isDetecting = true;
          _processCameraImage(image, camera);
        });
        _liveDetectionAvailable = true;
      } catch (e) {
        debugPrint('[ScannerPage] startImageStream 失敗 '
            '(裝置可能不支援同時使用 3 個 camera use case): $e');
        // CameraX 在 startImageStream 失敗時可能已 unbind 所有 use case，
        // 需重新初始化 (僅 Preview + ImageCapture)
        try {
          await _cameraController!.dispose();
        } catch (_) {}
        _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
        );
        try {
          await _cameraController!.initialize();
          await _cameraController!
              .lockCaptureOrientation(DeviceOrientation.portraitUp);
          debugPrint('[ScannerPage] 相機重新初始化成功（無即時偵測模式）');
        } catch (e2) {
          debugPrint('[ScannerPage] 相機重新初始化也失敗: $e2');
        }
      }

      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('相機初始化完全失敗: $e');
    }
  }

  /// 加速度計偵測手機是否被橫向持握。
  /// 利用重力方向判斷：手機直立時 y 軸重力 ≈ ±9.8，橫拿時 x 軸重力 ≈ ±9.8。
  /// 當 |x| > |y| 且差距明顯時視為橫拿。
  void _startOrientationMonitor() {
    _accelSubscription = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 500),
    ).listen((event) {
      // x: 左右傾斜, y: 前後傾斜, z: 上下
      final ax = event.x.abs();
      final ay = event.y.abs();
      // 手機橫拿: |x| 明顯大於 |y| (至少 2.0 m/s² 的差距避免誤判)
      final landscape = ax > ay && (ax - ay) > 2.0;
      if (landscape != _isLandscapeHeld && mounted) {
        setState(() => _isLandscapeHeld = landscape);
      }
    });
  }

  Future<void> _processCameraImage(
      CameraImage image, CameraDescription camera) async {
    // Note: _isDetecting is set to true by the caller (startImageStream callback)
    // so we do NOT check it here again — the caller already ensures single-entry.
    try {
      // 影像串流持續運行；_isDetecting 旗標確保同一時間只有一幀在推論，
      // 其餘幀在 callback 中直接 return（不累積、不重建 Camera2 session）。
      final sensorOrientation = camera.sensorOrientation;
      var rotationCompensation = 0;
      if (Platform.isAndroid) {
        if (sensorOrientation == 90) rotationCompensation = 90;
        if (sensorOrientation == 270) rotationCompensation = 270;
      }

      final sw = Stopwatch()..start();
      final bboxes =
          _tfliteTracker.processCameraImage(image, rotationCompensation);
      sw.stop();
      _inferCount++;
      _lastInferenceDurationMs = sw.elapsedMilliseconds;

      // 自適應冷卻：推論時間的 1.5 倍
      // 快手機 (S22U ~50ms) → 200ms 冷卻，流暢
      // 慢手機 (Mi A1 ~7000ms) → 5000ms 冷卻，避免 UI 卡死
      _inferCooldownMs =
          (sw.elapsedMilliseconds * 1.5).round().clamp(200, 5000);

      if (_inferCount == 1) {
        _tfliteTracker.notifyInferenceTime(sw.elapsedMilliseconds);
      }

      // 前 10 次每次都記錄，之後每 10 次
      if (_inferCount <= 10 || _inferCount % 10 == 0) {
        debugPrint(
            '[ScannerPage] 推論 #$_inferCount  ${sw.elapsedMilliseconds}ms  '
            'bbox=${bboxes.length}  cooldown=${_inferCooldownMs}ms');
      }
      if (mounted && _step == _PageStep.camera) {
        setState(() {
          if (bboxes.isNotEmpty) {
            bboxes.sort((a, b) => b.confidence.compareTo(a.confidence));
            final bestBbox = bboxes.first;

            if (bestBbox.rect.width > 10 && bestBbox.rect.height > 10) {
              _trackedBbox = bestBbox.rect;
              _trackedConfidence = bestBbox.confidence;
              _trackedLabel = bestBbox.label;
              if (_inferCount <= 5 || _inferCount % 10 == 0) {
                debugPrint('[ScannerPage-UI] bbox SET: '
                    'L=${bestBbox.rect.left.toStringAsFixed(0)} '
                    'T=${bestBbox.rect.top.toStringAsFixed(0)} '
                    'R=${bestBbox.rect.right.toStringAsFixed(0)} '
                    'B=${bestBbox.rect.bottom.toStringAsFixed(0)} '
                    'W=${bestBbox.rect.width.toStringAsFixed(0)} '
                    'H=${bestBbox.rect.height.toStringAsFixed(0)} '
                    'conf=${bestBbox.confidence.toStringAsFixed(3)}');
              }
            } else {
              _trackedBbox = null;
              _trackedConfidence = null;
              _trackedLabel = null;
              debugPrint('[ScannerPage-UI] bbox TOO SMALL: '
                  'W=${bestBbox.rect.width.toStringAsFixed(0)} '
                  'H=${bestBbox.rect.height.toStringAsFixed(0)}');
            }
          } else {
            _trackedBbox = null;
            _trackedConfidence = null;
            _trackedLabel = null;
          }
        });
      }
    } catch (e) {
      debugPrint('物件偵測錯誤: $e');
    } finally {
      _lastInferenceMs = DateTime.now().millisecondsSinceEpoch;
      _isDetecting = false;
      // 串流持續運行，下一幀到達時若 cooldown 已過會自動觸發推論
    }
  }

  Future<void> _takePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    // 防止橫向拍攝
    if (_isLandscapeHeld) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('請將手機直立拿著拍攝，橫向拍攝會影響測量精度'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    try {
      // Bug fix: 停止影像串流再拍照，避免某些 Android 裝置崩潰
      try {
        if (_cameraController!.value.isStreamingImages) {
          await _cameraController!.stopImageStream();
        }
      } catch (_) {
        // 可能已經停止了，忽略
      }

      final xFile = await _cameraController!.takePicture();
      final file = File(xFile.path);

      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);

      double? focalMm;
      double? focal35;
      String? phoneMake;
      String? phoneModel;
      try {
        final exifData = await readExifFromBytes(bytes);
        final focalTag = exifData['EXIF FocalLength'];
        if (focalTag != null) {
          final ratio = focalTag.values;
          if (ratio is IfdRatios && ratio.ratios.isNotEmpty) {
            focalMm =
                ratio.ratios.first.numerator / ratio.ratios.first.denominator;
          } else {
            // printable 可能包含單位 / 空白 / 分數表示法 (例如 "5.4 mm", "27/5")
            // 先嘗試分數，再做保守的數字抽取
            final raw = focalTag.printable.trim();
            if (raw.contains('/')) {
              final parts = raw.split('/');
              if (parts.length == 2) {
                final n = double.tryParse(_stripNonNumeric(parts[0]));
                final d = double.tryParse(_stripNonNumeric(parts[1]));
                if (n != null && d != null && d != 0) focalMm = n / d;
              }
            }
            focalMm ??= double.tryParse(_stripNonNumeric(raw));
          }
        }
        final focal35Tag = exifData['EXIF FocalLengthIn35mmFilm'];
        if (focal35Tag != null) {
          focal35 = double.tryParse(_stripNonNumeric(focal35Tag.printable));
        }
        final makeTag = exifData['Image Make'];
        if (makeTag != null) {
          phoneMake = makeTag.printable.trim();
        }
        final modelTag = exifData['Image Model'];
        if (modelTag != null) {
          phoneModel = modelTag.printable.trim();
        }
      } catch (e) {
        debugPrint('[EXIF] Failed to read: $e');
      }

      setState(() {
        _capturedImage = file;
        _imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
        _focalLengthMm = focalMm;
        _focalLength35mm = focal35;
        _phoneMake = phoneMake;
        _phoneModel = phoneModel;
        _currentBbox = null;
        _bboxStart = null;
        _bboxEnd = null;
        if (_isAutoMode) {
          _step = _PageStep.processing;
        } else {
          _step = _PageStep.drawBbox;
        }
      });

      if (_isAutoMode) {
        Rect? mappedBbox;
        if (_trackedBbox != null && _cameraController != null) {
          final previewSize = _cameraController!.value.previewSize!;
          final double imgW = _imageSize!.width;
          final double imgH = _imageSize!.height;

          // ─── 座標系統說明 ───
          //
          // TFLite YOLO 在 _fillInputBuffer 已把影像採樣成直向，輸出座標在
          // 「直向 portrait」空間：
          //   X ∈ [0, portraitW]  (portraitW = sensorH = previewSize.height)
          //   Y ∈ [0, portraitH]  (portraitH = sensorW = previewSize.width)
          // 拍攝的照片 (decoded) 經 EXIF 旋轉後也是直向 (imgW < imgH)。
          // 因此 portrait → photo 只需要等比縮放，不需要旋轉映射。

          final bool isPortraitImage = imgH > imgW;
          final bool isSensorLandscape = previewSize.width > previewSize.height;

          // bboxSX: scale factor from portrait-preview-space → photo-space.
          double bboxSX;

          if (isPortraitImage && isSensorLandscape) {
            // bbox 在直向空間 (portraitW × portraitH)
            // 照片也是直向 (imgW × imgH)
            // 直接等比縮放
            final double portraitW = previewSize.height.toDouble(); // sensorH
            final double portraitH = previewSize.width.toDouble(); // sensorW
            bboxSX = imgW / portraitW;
            final double sY = imgH / portraitH;

            mappedBbox = Rect.fromLTRB(
              _trackedBbox!.left * bboxSX,
              _trackedBbox!.top * sY,
              _trackedBbox!.right * bboxSX,
              _trackedBbox!.bottom * sY,
            );
          } else {
            // 無旋轉（iOS 或特殊裝置）：直接縮放
            bboxSX = imgW / previewSize.width;
            final double sY = imgH / previewSize.height;
            mappedBbox = Rect.fromLTRB(
              _trackedBbox!.left * bboxSX,
              _trackedBbox!.top * sY,
              _trackedBbox!.right * bboxSX,
              _trackedBbox!.bottom * sY,
            );
          }

          // 確保不超出圖片範圍
          mappedBbox = Rect.fromLTRB(
            mappedBbox.left.clamp(0, imgW),
            mappedBbox.top.clamp(0, imgH),
            mappedBbox.right.clamp(0, imgW),
            mappedBbox.bottom.clamp(0, imgH),
          );
        }

        _submitAutoMeasurement(localBbox: mappedBbox);
      }
    } catch (e) {
      debugPrint('拍照失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失敗: $e')),
        );
      }
    }
  }

  // ===========================================================
  // 步驟 2: 框選樹幹
  // ===========================================================

  Rect _screenBboxToImageBbox(Rect screenBbox, Size displaySize) {
    if (_imageSize == null) return screenBbox;

    final scale = _containScale(displaySize);
    final renderedW = _imageSize!.width * scale;
    final renderedH = _imageSize!.height * scale;
    final offsetX = (displaySize.width - renderedW) / 2.0;
    final offsetY = (displaySize.height - renderedH) / 2.0;

    double toImgX(double sx) =>
        ((sx - offsetX) / scale).clamp(0, _imageSize!.width);
    double toImgY(double sy) =>
        ((sy - offsetY) / scale).clamp(0, _imageSize!.height);

    final x1 = toImgX(screenBbox.left);
    final y1 = toImgY(screenBbox.top);
    final x2 = toImgX(screenBbox.right);
    final y2 = toImgY(screenBbox.bottom);

    return Rect.fromLTRB(
      min(x1, x2),
      min(y1, y2),
      max(x1, x2),
      max(y1, y2),
    );
  }

  double _containScale(Size displaySize) {
    if (_imageSize == null) return 1.0;
    return (displaySize.width / _imageSize!.width)
        .clamp(0, displaySize.height / _imageSize!.height)
        .toDouble();
  }

  // ===========================================================
  // 步驟 3: 發送 API 請求
  // ===========================================================

  Future<void> _submitMeasurement(Size displaySize) async {
    if (_currentBbox == null || _capturedImage == null) return;

    if (_currentBbox!.width < 20 || _currentBbox!.height < 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('框選範圍太小，請框選更大的樹幹區域'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _step = _PageStep.processing;
      _errorMessage = null;
    });

    try {
      final imgBbox = _screenBboxToImageBbox(_currentBbox!, displaySize);

      double? fovDeg;
      if (_focalLength35mm != null && _focalLength35mm! > 0) {
        fovDeg = 2 * atan(36.0 / (2 * _focalLength35mm!)) * 180.0 / 3.14159265;
      }

      final result = await _service.measureDbh(
        imageFile: _capturedImage!,
        bboxX1: imgBbox.left.round(),
        bboxY1: imgBbox.top.round(),
        bboxX2: imgBbox.right.round(),
        bboxY2: imgBbox.bottom.round(),
        focalLengthMm: _focalLengthMm,
        focalLength35mm: _focalLength35mm,
        fovDegrees: fovDeg,
        phoneMake: _phoneMake,
        phoneModel: _phoneModel,
        returnVisualization: true,
      );

      if (mounted) {
        setState(() {
          _result = result;
          _step = _PageStep.result;
        });
      }
    } on PureVisionException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _step = _PageStep.drawBbox;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _errorMessage = '請求逾時，伺服器可能正在喚醒，請稍後再試';
          _step = _PageStep.drawBbox;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('請求逾時 — 伺服器可能正在喚醒中，請稍後再試'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _step = _PageStep.drawBbox;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錯誤: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================
  // 步驟 3b: 自動偵測 + 量測 (Auto Mode)
  // ===========================================================

  Future<void> _submitAutoMeasurement({Rect? localBbox}) async {
    if (_capturedImage == null) return;

    setState(() {
      _step = _PageStep.processing;
      _errorMessage = null;
      _autoResult = null;
    });

    try {
      double? fovDeg;
      if (_focalLength35mm != null && _focalLength35mm! > 0) {
        fovDeg = 2 * atan(36.0 / (2 * _focalLength35mm!)) * 180.0 / 3.14159265;
      }

      final result = await _service.autoMeasureDbh(
        imageFile: _capturedImage!,
        focalLengthMm: _focalLengthMm,
        focalLength35mm: _focalLength35mm,
        fovDegrees: fovDeg,
        phoneMake: _phoneMake,
        phoneModel: _phoneModel,
        localBbox: localBbox,
        useServerYoloMask: true,
        returnVisualization: true,
        returnDetectionVisualization: true,
      );

      if (mounted) {
        if (result.success) {
          setState(() {
            _autoResult = result;
            _step = _PageStep.result;
          });
        } else {
          setState(() {
            _autoResult = result;
            _errorMessage = result.errorMessage ?? '未偵測到樹幹，請改用手動框選';
            _step = _PageStep.drawBbox;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('自動偵測未找到樹幹 — 已切換至手動模式'),
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: '了解',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
          _isAutoMode = false;
        }
      }
    } on PureVisionException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isAutoMode = false;
          _step = _PageStep.drawBbox;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _errorMessage = '請求逾時，伺服器可能正在喚醒，請稍後再試';
          _isAutoMode = false;
          _step = _PageStep.drawBbox;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('請求逾時 — 伺服器可能正在喚醒中，請稍後再試'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isAutoMode = false;
          _step = _PageStep.drawBbox;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('錯誤: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ===========================================================
  // 使用自動量測結果 → 回傳 MeasurementResult
  // ===========================================================

  void _useAutoResult() {
    final r = _autoResult;
    if (r == null || !r.success) return;

    final measureResult = MeasurementResult(
      diameterCm: r.dbhCm!,
      confidenceScore: r.confidence ?? 0,
      method: MeasurementMethod.pureVision,
      points: [],
      capturedImagePath: _capturedImage?.path,
      notes: '自動偵測 AI 測量 | '
          '深度: ${r.trunkDepthM?.toStringAsFixed(2) ?? "?"}m | '
          '信心度: ${r.confidenceLevel} | '
          '距離: ${r.distanceMessage} | '
          '推論: ${r.totalMs.toStringAsFixed(0)}ms',
    );

    Navigator.of(context).pop(measureResult);
  }

  // ===========================================================
  // 使用結果 → 回傳 MeasurementResult
  // ===========================================================

  void _useResult() {
    if (_result == null) return;

    final measureResult = MeasurementResult(
      diameterCm: _result!.dbhCm,
      confidenceScore: _result!.confidence,
      method: MeasurementMethod.pureVision,
      points: [],
      capturedImagePath: _capturedImage?.path,
      notes: '純視覺 AI 測量 | '
          '深度: ${_result!.trunkDepthM.toStringAsFixed(2)}m | '
          '信心度: ${_result!.confidenceLevel} | '
          '推論: ${_result!.totalMs.toStringAsFixed(0)}ms',
    );

    Navigator.of(context).pop(measureResult);
  }

  // ===========================================================
  // UI Build
  // ===========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: switch (_step) {
          _PageStep.camera => _buildCameraStep(),
          _PageStep.drawBbox => _buildDrawBboxStep(),
          _PageStep.processing => _buildProcessingStep(),
          _PageStep.result => _buildResultStep(),
        },
      ),
    );
  }

  // -----------------------------------------------------------
  // 步驟 1: 相機預覽
  // -----------------------------------------------------------

  Widget _buildCameraStep() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_isCameraInitialized && _cameraController != null)
          Center(
            child: Stack(
              children: [
                CameraPreview(_cameraController!),
                // [Edge AI] 實時顯示小模型抓到的追蹤框
                if (_trackedBbox != null &&
                    _cameraController!.value.previewSize != null)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _LiveBboxPainter(
                          bbox: _trackedBbox!,
                          previewSize: _cameraController!.value.previewSize!,
                          confidence: _trackedConfidence,
                          label: _trackedLabel,
                        ),
                      ),
                    ),
                  ),
                // [Debug] 推論狀態指示器（小角標，不影響使用）
                if (_inferCount > 0)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#$_inferCount ${_lastInferenceDurationMs}ms '
                        '${_trackedBbox != null ? "✓" : "−"}'
                        '${_trackedConfidence != null ? " ${(_trackedConfidence! * 100).toStringAsFixed(0)}%" : ""}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          const Center(child: CircularProgressIndicator()),

        // 頂部列
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildCameraAppBar(),
        ),

        // 服務狀態
        if (!_serviceAvailable)
          Positioned(
            top: 60,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ML 服務未連線\n請重新登入或確認手機可連到 ML 位址',
                      style: TextStyle(
                          color: Colors.white, fontSize: 13, height: 1.3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _retryServiceCheck,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: _isRetryingService
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('重試',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 橫向警告
        if (_isLandscapeHeld)
          Positioned(
            top: _serviceAvailable ? 60 : 110,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orangeAccent, width: 1.5),
              ),
              child: const Row(
                children: [
                  Icon(Icons.screen_rotation,
                      color: Colors.orangeAccent, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '請將手機直立拿著拍攝\n橫向拍攝會影響測量精度',
                      style: TextStyle(
                          color: Colors.white, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 提示
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: _buildInstructionChip(
            _isLandscapeHeld
                ? '⚠️ 請直立手機'
                : (_isAutoMode ? '🤖 AI 自動偵測模式' : '📸 手動框選模式'),
            subtitle: _isLandscapeHeld
                ? '測量功能需要直立拍攝才能正確運作'
                : (_isAutoMode ? '對準樹幹拍照，AI 自動辨識並量測' : '拍照後手動框選樹幹範圍'),
          ),
        ),

        // 模式切換
        Positioned(
          bottom: 104,
          right: 16,
          child: GestureDetector(
            onTap: () {
              setState(() => _isAutoMode = !_isAutoMode);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _isAutoMode
                    ? Colors.tealAccent.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isAutoMode ? Colors.tealAccent : Colors.grey,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isAutoMode ? Icons.auto_awesome : Icons.touch_app,
                    color: _isAutoMode ? Colors.tealAccent : Colors.grey,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isAutoMode ? '自動' : '手動',
                    style: TextStyle(
                      color: _isAutoMode ? Colors.tealAccent : Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 拍照按鈕
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap:
                  (_serviceAvailable && !_isLandscapeHeld) ? _takePhoto : null,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (_serviceAvailable && !_isLandscapeHeld)
                        ? Colors.white
                        : Colors.grey,
                    width: 4,
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (_serviceAvailable && !_isLandscapeHeld)
                        ? Colors.white
                        : Colors.grey,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // -----------------------------------------------------------
  // 步驟 2: 框選樹幹
  // -----------------------------------------------------------

  Widget _buildDrawBboxStep() {
    return LayoutBuilder(builder: (context, constraints) {
      final displaySize = Size(constraints.maxWidth, constraints.maxHeight);

      return Stack(
        fit: StackFit.expand,
        children: [
          if (_capturedImage != null)
            Image.file(
              _capturedImage!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          GestureDetector(
            onPanStart: (details) {
              setState(() {
                _bboxStart = details.localPosition;
                _bboxEnd = details.localPosition;
                _currentBbox = null;
              });
            },
            onPanUpdate: (details) {
              setState(() {
                _bboxEnd = details.localPosition;
                if (_bboxStart != null) {
                  _currentBbox = Rect.fromPoints(_bboxStart!, _bboxEnd!);
                }
              });
            },
            onPanEnd: (details) {
              if (_bboxStart != null && _bboxEnd != null) {
                setState(() {
                  _currentBbox = Rect.fromPoints(_bboxStart!, _bboxEnd!);
                });
              }
            },
            child: CustomPaint(
              painter: _BboxOverlayPainter(bbox: _currentBbox),
              child: Container(color: Colors.transparent),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildAppBar('框選樹幹'),
          ),
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null)
                  Container(
                    margin:
                        const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_errorMessage!,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center),
                  ),
                _buildInstructionChip(
                  '✋ 用手指框選樹幹範圍',
                  subtitle: '儘量貼緊樹幹邊緣',
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'retake',
                  onPressed: () {
                    setState(() {
                      _step = _PageStep.camera;
                      _capturedImage = null;
                      _currentBbox = null;
                    });
                    _restartImageStream();
                  },
                  backgroundColor: Colors.grey[700],
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                if (_currentBbox != null)
                  FloatingActionButton(
                    heroTag: 'clear',
                    onPressed: () {
                      setState(() {
                        _currentBbox = null;
                        _bboxStart = null;
                        _bboxEnd = null;
                      });
                    },
                    backgroundColor: Colors.orange,
                    child: const Icon(Icons.clear, color: Colors.white),
                  ),
                FloatingActionButton.extended(
                  heroTag: 'submit',
                  onPressed: _currentBbox != null
                      ? () => _submitMeasurement(displaySize)
                      : null,
                  backgroundColor:
                      _currentBbox != null ? Colors.green : Colors.grey,
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text('AI 分析',
                      style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      );
    });
  }

  // -----------------------------------------------------------
  // 步驟 3: 處理中
  // -----------------------------------------------------------

  Widget _buildProcessingStep() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(Colors.tealAccent),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isAutoMode ? 'AI 自動偵測中...' : 'AI 深度估計中...',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isAutoMode ? '正在自動辨識樹幹並計算胸徑' : '正在使用 Depth Anything V2 分析影像',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '首次請求可能需要 30-60 秒（伺服器喚醒）',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (_isAutoMode) {
                    _step = _PageStep.camera;
                  } else {
                    _step = _PageStep.drawBbox;
                  }
                  _errorMessage = '已取消分析';
                });
                if (_isAutoMode) _restartImageStream();
              },
              icon: const Icon(Icons.cancel_outlined,
                  color: Colors.white54, size: 18),
              label: const Text('取消', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------
  // 步驟 4: 結果
  // -----------------------------------------------------------

  Widget _buildResultStep() {
    if (_isAutoMode && _autoResult != null) {
      return _buildAutoResultView();
    }
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    return _buildManualResultView(r);
  }

  Widget _buildAutoResultView() {
    final r = _autoResult!;
    final dbh = r.dbhCm ?? 0;
    final conf = r.confidence ?? 0;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildAppBar('自動偵測結果'),
          if (r.distanceStatus != 'ok' && r.distanceMessage.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _distanceStatusColor(r.distanceStatus)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _distanceStatusColor(r.distanceStatus)
                      .withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _distanceStatusIcon(r.distanceStatus),
                    color: _distanceStatusColor(r.distanceStatus),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      r.distanceMessage,
                      style: TextStyle(
                        color: _distanceStatusColor(r.distanceStatus),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (r.detectionVisualizationBytes != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Image.memory(
                    r.detectionVisualizationBytes!,
                    fit: BoxFit.contain,
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    color: Colors.grey[900],
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome,
                            color: Colors.tealAccent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '自動偵測 · 信心度 ${(r.detectionConfidence * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        Text(
                          '${r.allTrunks.length} 棵樹幹',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (r.visualizationBytes != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                r.visualizationBytes!,
                fit: BoxFit.contain,
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade700, Colors.teal.shade900],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome,
                        color: Colors.tealAccent, size: 18),
                    SizedBox(width: 6),
                    Text('自動偵測 DBH (胸徑)',
                        style: TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${dbh.toStringAsFixed(1)} cm',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.center,
                  children: [
                    _buildBadge(
                        '信心度: ${r.confidenceLevel}', _confidenceColor(conf)),
                    _buildBadge(
                        '深度: ${r.trunkDepthM?.toStringAsFixed(2) ?? "?"}m',
                        Colors.blueGrey),
                    _buildBadge(_distanceStatusLabel(r.distanceStatus),
                        _distanceStatusColor(r.distanceStatus)),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('詳細資料',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Divider(color: Colors.grey),
                _buildDetailRow('偵測方式', '自動 (深度分析)'),
                if (r.trunkPixelWidth != null)
                  _buildDetailRow(
                      '樹幹像素寬度', '${r.trunkPixelWidth!.toStringAsFixed(0)} px'),
                if (r.chordLengthM != null)
                  _buildDetailRow(
                      '弦長', '${r.chordLengthM!.toStringAsFixed(4)} m'),
                if (r.focalLengthPx != null)
                  _buildDetailRow(
                      '焦距', '${r.focalLengthPx!.toStringAsFixed(1)} px'),
                if (r.method != null) _buildDetailRow('測量方法', r.method!),
                _buildDetailRow(
                    '深度估計耗時', '${r.depthEstimationMs.toStringAsFixed(0)} ms'),
                _buildDetailRow(
                    '偵測耗時', '${r.detectionMs.toStringAsFixed(0)} ms'),
                _buildDetailRow(
                    'DBH 計算耗時', '${r.dbhCalculationMs.toStringAsFixed(0)} ms'),
                _buildDetailRow('總耗時', '${r.totalMs.toStringAsFixed(0)} ms'),
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('備註:',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ...r.notes.map((n) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('• $n',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _step = _PageStep.camera;
                        _capturedImage = null;
                        _currentBbox = null;
                        _result = null;
                        _autoResult = null;
                        _isAutoMode = true;
                      });
                      _restartImageStream();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新測量'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _useAutoResult,
                    icon: const Icon(Icons.check),
                    label: const Text('使用此結果'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildManualResultView(PureVisionDbhResult r) {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildAppBar('測量結果'),
          if (r.visualizationBytes != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[700]!),
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.memory(
                r.visualizationBytes!,
                fit: BoxFit.contain,
              ),
            ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.teal.shade700, Colors.teal.shade900],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text('DBH (胸徑)',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  '${r.dbhCm.toStringAsFixed(1)} cm',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildBadge('信心度: ${r.confidenceLevel}',
                        _confidenceColor(r.confidence)),
                    const SizedBox(width: 8),
                    _buildBadge('深度: ${r.trunkDepthM.toStringAsFixed(2)}m',
                        Colors.blueGrey),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('詳細資料',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const Divider(color: Colors.grey),
                _buildDetailRow(
                    '樹幹像素寬度', '${r.trunkPixelWidth.toStringAsFixed(0)} px'),
                _buildDetailRow('弦長', '${r.chordLengthM.toStringAsFixed(4)} m'),
                _buildDetailRow(
                    '焦距', '${r.focalLengthPx.toStringAsFixed(1)} px'),
                _buildDetailRow('測量方法', r.method),
                _buildDetailRow(
                    '深度估計耗時', '${r.depthEstimationMs.toStringAsFixed(0)} ms'),
                _buildDetailRow(
                    'DBH 計算耗時', '${r.dbhCalculationMs.toStringAsFixed(0)} ms'),
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('備註:',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ...r.notes.map((n) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text('• $n',
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                      )),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _step = _PageStep.camera;
                        _capturedImage = null;
                        _currentBbox = null;
                        _result = null;
                        _autoResult = null;
                        _isAutoMode = true;
                      });
                      _restartImageStream();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新測量'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _useResult,
                    icon: const Icon(Icons.check),
                    label: const Text('使用此結果'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildAppBar(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.black54,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: _showHelp,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.black54,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              '純視覺 AI 測量',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: _showHelp,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionChip(String text, {String? subtitle}) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Color _confidenceColor(double c) {
    if (c >= 0.75) return Colors.green;
    if (c >= 0.5) return Colors.orange;
    return Colors.red;
  }

  Color _distanceStatusColor(String status) {
    switch (status) {
      case 'ok':
        return Colors.green;
      case 'warning':
        return Colors.orange;
      case 'too_close':
        return Colors.red;
      case 'too_far':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _distanceStatusIcon(String status) {
    switch (status) {
      case 'ok':
        return Icons.check_circle;
      case 'warning':
        return Icons.warning_amber;
      case 'too_close':
        return Icons.zoom_in;
      case 'too_far':
        return Icons.zoom_out;
      default:
        return Icons.info_outline;
    }
  }

  String _distanceStatusLabel(String status) {
    switch (status) {
      case 'ok':
        return '距離適中';
      case 'warning':
        return '距離偏遠';
      case 'too_close':
        return '距離過近';
      case 'too_far':
        return '距離過遠';
      default:
        return '距離未知';
    }
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('純視覺 AI 測量'),
        content: const Text(
          '此功能使用 Depth Anything V2 深度估計模型，'
          '從單張 RGB 照片自動推算樹幹直徑。\n\n'
          '🤖 自動模式（預設）：\n'
          '1. 距離樹幹 1-5 公尺處拍照\n'
          '2. AI 自動偵測樹幹位置\n'
          '3. 自動計算 DBH 並顯示結果\n'
          '4. 若偵測失敗會自動切換至手動模式\n\n'
          '✋ 手動模式：\n'
          '1. 拍照後用手指框選樹幹範圍\n'
          '2. 點擊「AI 分析」等待結果\n\n'
          '提示：\n'
          '• 確保光線充足\n'
          '• 距離太近或太遠會影響精準度\n'
          '• 畫面中應有明顯的樹幹',
        ),
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

class _BboxOverlayPainter extends CustomPainter {
  final Rect? bbox;

  _BboxOverlayPainter({this.bbox});

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox == null) return;

    final Path fullPath = Path()..addRect(Offset.zero & size);
    final Path bboxPath = Path()..addRect(bbox!);
    final Path dimPath =
        Path.combine(PathOperation.difference, fullPath, bboxPath);
    canvas.drawPath(
        dimPath, Paint()..color = Colors.black.withValues(alpha: 0.45));

    final borderPaint = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(bbox!, borderPaint);

    const cornerLen = 20.0;
    const cornerWidth = 4.0;
    final cornerPaint = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerWidth
      ..strokeCap = StrokeCap.round;

    final corners = [
      bbox!.topLeft,
      bbox!.topRight,
      bbox!.bottomLeft,
      bbox!.bottomRight
    ];
    final dirs = [
      [const Offset(1, 0), const Offset(0, 1)],
      [const Offset(-1, 0), const Offset(0, 1)],
      [const Offset(1, 0), const Offset(0, -1)],
      [const Offset(-1, 0), const Offset(0, -1)],
    ];

    for (int i = 0; i < 4; i++) {
      final c = corners[i];
      canvas.drawLine(c, c + dirs[i][0] * cornerLen, cornerPaint);
      canvas.drawLine(c, c + dirs[i][1] * cornerLen, cornerPaint);
    }

    final cx = bbox!.center.dx;
    final cy = bbox!.center.dy;
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), crossPaint);

    final w = bbox!.width.round();
    final h = bbox!.height.round();
    _drawLabel(canvas, '${w}x$h', bbox!.bottomCenter + const Offset(0, 8));
  }

  void _drawLabel(Canvas canvas, String text, Offset position) {
    final ts = TextSpan(
      text: text,
      style: const TextStyle(
        color: Colors.tealAccent,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black)
        ],
      ),
    );
    final tp = TextPainter(text: ts, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, position - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _BboxOverlayPainter old) => old.bbox != bbox;
}

class _LiveBboxPainter extends CustomPainter {
  final Rect bbox;
  final Size previewSize;
  final double? confidence;
  final String? label;

  _LiveBboxPainter({
    required this.bbox,
    required this.previewSize,
    this.confidence,
    this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // bbox 座標在 portrait 空間：
    //   X ∈ [0, portraitW]  (portraitW = 感測器短邊)
    //   Y ∈ [0, portraitH]  (portraitH = 感測器長邊)
    // previewSize 在某些裝置是 landscape (W>H)，某些是 portrait (W<H)，
    // 必須統一取短邊 = portraitW、長邊 = portraitH。
    final double portraitW = min(previewSize.width, previewSize.height);
    final double portraitH = max(previewSize.width, previewSize.height);

    final double scaleX = size.width / portraitW;
    final double scaleY = size.height / portraitH;

    final rect = Rect.fromLTRB(
      (bbox.left * scaleX).clamp(0.0, size.width),
      (bbox.top * scaleY).clamp(0.0, size.height),
      (bbox.right * scaleX).clamp(0.0, size.width),
      (bbox.bottom * scaleY).clamp(0.0, size.height),
    );

    debugPrint(
        '[LiveBbox-PAINT] canvas=${size.width.toStringAsFixed(0)}x${size.height.toStringAsFixed(0)} '
        'preview=${previewSize.width.toStringAsFixed(0)}x${previewSize.height.toStringAsFixed(0)} '
        'portraitWH=${portraitW.toStringAsFixed(0)}x${portraitH.toStringAsFixed(0)} '
        'bbox=L${bbox.left.toStringAsFixed(0)},T${bbox.top.toStringAsFixed(0)},'
        'R${bbox.right.toStringAsFixed(0)},B${bbox.bottom.toStringAsFixed(0)} '
        '→ rect=L${rect.left.toStringAsFixed(0)},T${rect.top.toStringAsFixed(0)},'
        'R${rect.right.toStringAsFixed(0)},B${rect.bottom.toStringAsFixed(0)}');

    // 半透明填充
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.greenAccent.withValues(alpha: 0.25);
    canvas.drawRect(rect, fillPaint);

    // 邊框（加粗以確保可見）
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..color = Colors.greenAccent;
    canvas.drawRect(rect, borderPaint);

    // 標籤 + 信心度
    if (confidence != null) {
      final text =
          '${label ?? "trunk"} ${(confidence! * 100).toStringAsFixed(0)}%';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(blurRadius: 3, color: Colors.black),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      // 標籤背景
      final bgRect = Rect.fromLTWH(
        rect.left,
        rect.top - tp.height - 4,
        tp.width + 8,
        tp.height + 4,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bgRect, const Radius.circular(4)),
        Paint()..color = Colors.greenAccent.withValues(alpha: 0.85),
      );
      tp.paint(canvas, Offset(rect.left + 4, rect.top - tp.height - 2));
    }
  }

  @override
  bool shouldRepaint(covariant _LiveBboxPainter old) =>
      old.bbox != bbox ||
      old.previewSize != previewSize ||
      old.confidence != confidence;
}
