import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:camera/camera.dart';

// ================================================================
// 資料結構
// ================================================================

/// 偵測結果 (bbox + confidence + label)
class TfliteBbox {
  final Rect rect; // 感測器座標空間中的 bounding box
  final double confidence;
  final String label;

  TfliteBbox(this.rect, this.confidence, this.label);
}

/// 內部：NMS 前的原始偵測
class _RawDet {
  final double cx, cy, w, h;
  final double conf;
  final int cls;
  final String label;

  _RawDet(this.cx, this.cy, this.w, this.h, this.conf, this.cls, this.label);

  double get x1 => cx - w / 2;
  double get y1 => cy - h / 2;
  double get x2 => cx + w / 2;
  double get y2 => cy + h / 2;
}

// ================================================================
// YOLOv8n-seg 樹幹偵測服務
// ================================================================

/// 使用 Colab 訓練的 YOLOv8n-seg (tree_trunk) TFLite FLOAT32 模型
/// 進行即時邊緣推論，取代原 SSD MobileNet COCO 通用偵測。
class TfliteObjectTrackingService {
  Interpreter? _interpreter;
  List<String>? _labels;
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ── 模型幾何 (initialize 時從 tensor shape 偵測) ──
  int _inputSize = 640;
  int _numDets = 8400; // 80² + 40² + 20²
  int _detChannels = 37; // 4 + nc + 32
  int _numClasses = 1;
  bool _detTransposed = false; // true = [1, ch, dets], false = [1, dets, ch]
  bool _inputIsFloat = true;
  int _numOutputs = 1;

  // ── 預配置輸出 buffer (init 時分配，每幀重用) ──
  Object? _detOutputBuf;
  Object? _protoOutputBuf;
  late Map<int, Object> _outputMap;

  // ── 預配置輸入 buffer ──
  Float32List? _inputFloat;
  Uint8List? _inputUint8;

  // ── 閾值 ──
  final double _confThreshold = 0.35;
  final double _iouThreshold = 0.45;
  static const int _maxKeep = 5;

  // ── Letterbox 狀態 (每幀更新，用於座標逆映射) ──
  int _lbPadX = 0;
  int _lbPadY = 0;
  int _lbScaledW = 640;
  int _lbScaledH = 640;

  // ================================================================
  // 初始化
  // ================================================================

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _interpreter = await _loadInterpreter();

      // 標籤
      final raw =
          await rootBundle.loadString('assets/ml/tree_trunk_labels.txt');
      _labels =
          raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      _numClasses = _labels!.length;

      _introspectModel();
      _allocateBuffers();

      _isInitialized = true;
      debugPrint('[TFLite] YOLOv8n-seg 初始化完成  '
          'input=$_inputSize  dets=$_numDets  ch=$_detChannels  '
          'classes=$_numClasses  outputs=$_numOutputs  '
          'transposed=$_detTransposed  float=$_inputIsFloat');
    } catch (e, st) {
      debugPrint('[TFLite] 初始化失敗: $e');
      debugPrint('[TFLite] StackTrace: $st');
    }
  }

  /// 多策略載入 TFLite 模型
  ///
  /// 自動偵測裝置能力，依次嘗試：
  ///  1. GPU delegate（高階裝置可加速 5-10x）
  ///  2. 多執行緒 CPU（依 CPU 核心數動態分配）
  ///  3. 單執行緒 CPU（最大相容性 fallback）
  ///
  /// 所有策略都使用 fromBuffer（比 fromAsset 更可靠）。
  Future<Interpreter> _loadInterpreter() async {
    const modelPath = 'assets/ml/tree_trunk_seg.tflite';

    // 先載入並驗證模型檔案
    final modelData = await rootBundle.load(modelPath);
    final buffer = modelData.buffer.asUint8List(
      modelData.offsetInBytes,
      modelData.lengthInBytes,
    );
    debugPrint('[TFLite] 模型大小: ${buffer.length} bytes  '
        'magic: ${buffer.length >= 8 ? String.fromCharCodes(buffer.sublist(4, 8)) : "?"}');

    // 動態決定最佳 thread 數（CPU 核心數的一半，至少 1，最多 4）
    final int cpuCores = Platform.numberOfProcessors;
    final int optimalThreads = (cpuCores ~/ 2).clamp(1, 4);
    debugPrint('[TFLite] CPU 核心: $cpuCores → threads=$optimalThreads');

    // 策略 1: GPU delegate（高階裝置：Adreno 6xx+, Mali-G7x+ 等）
    if (Platform.isAndroid) {
      try {
        final gpuDelegate = GpuDelegateV2();
        final options = InterpreterOptions()
          ..threads = optimalThreads
          ..addDelegate(gpuDelegate);
        final interp = Interpreter.fromBuffer(buffer, options: options);
        debugPrint('[TFLite] ✓ GPU delegate 載入成功 (threads=$optimalThreads)');
        return interp;
      } catch (e) {
        debugPrint('[TFLite] GPU delegate 不支援，fallback CPU: $e');
      }
    }

    // 策略 2: 多執行緒 CPU（最常見路徑）
    try {
      final options = InterpreterOptions()..threads = optimalThreads;
      final interp = Interpreter.fromBuffer(buffer, options: options);
      debugPrint('[TFLite] ✓ CPU 載入成功 (threads=$optimalThreads)');
      return interp;
    } catch (e1) {
      debugPrint('[TFLite] CPU threads=$optimalThreads 失敗: $e1');
    }

    // 策略 3: 單執行緒 CPU（最大相容性）
    try {
      final options = InterpreterOptions()..threads = 1;
      final interp = Interpreter.fromBuffer(buffer, options: options);
      debugPrint('[TFLite] ✓ CPU 單執行緒載入成功');
      return interp;
    } catch (e2) {
      debugPrint('[TFLite] CPU 單執行緒失敗: $e2');
    }

    // 策略 4: fromAsset（最後手段）
    debugPrint('[TFLite] 嘗試 fromAsset...');
    final interp = await Interpreter.fromAsset(modelPath);
    debugPrint('[TFLite] ✓ fromAsset 載入成功');
    return interp;
  }

  /// 讀取模型 tensor shape 並設定內部參數
  void _introspectModel() {
    final interp = _interpreter!;

    // ── Input ──
    final inT = interp.getInputTensor(0);
    final inShape = inT.shape; // e.g. [1, 640, 640, 3]
    _inputSize = inShape[1];
    _inputIsFloat = (inT.type == TensorType.float32);

    // ── Output 0: detections ──
    final detShape = interp.getOutputTensor(0).shape;
    // 可能是 [1, 37, 8400] 或 [1, 8400, 37]
    if (detShape.length == 3) {
      if (detShape[1] < detShape[2]) {
        // [1, 37, 8400]
        _detChannels = detShape[1];
        _numDets = detShape[2];
        _detTransposed = true;
      } else {
        // [1, 8400, 37]
        _numDets = detShape[1];
        _detChannels = detShape[2];
        _detTransposed = false;
      }
    }

    // ── Output 1: prototypes (optional) ──
    _numOutputs = interp.getOutputTensors().length;
  }

  /// 預分配輸入 / 輸出 buffer（避免每幀 GC 壓力）
  void _allocateBuffers() {
    final pixels = _inputSize * _inputSize * 3;
    if (_inputIsFloat) {
      _inputFloat = Float32List(pixels);
    } else {
      _inputUint8 = Uint8List(pixels);
    }

    // Detection output
    if (_detTransposed) {
      // [1, ch, dets]
      _detOutputBuf = List.generate(
          1,
          (_) => List.generate(
              _detChannels, (_) => List<double>.filled(_numDets, 0)));
    } else {
      // [1, dets, ch]
      _detOutputBuf = List.generate(
          1,
          (_) => List.generate(
              _numDets, (_) => List<double>.filled(_detChannels, 0)));
    }

    _outputMap = {0: _detOutputBuf!};

    // Prototype output (if present)
    if (_numOutputs > 1) {
      final protoShape = _interpreter!.getOutputTensor(1).shape;
      if (protoShape.length == 4) {
        _protoOutputBuf = List.generate(
            protoShape[0],
            (_) => List.generate(
                protoShape[1],
                (_) => List.generate(
                    protoShape[2],
                    (_) => List<double>.filled(protoShape[3], 0))));
        _outputMap[1] = _protoOutputBuf!;
      }
    }
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }

  // ================================================================
  // 每幀推論
  // ================================================================

  /// 從相機影像即時偵測樹幹
  ///
  /// [rotationDegrees] 表示感測器相對裝置自然方向的旋轉角度。
  /// Android sensorOrientation=90 時，感測器影像為橫向，需旋轉 90° CW
  /// 才能得到直向影像供模型辨識。
  ///
  /// 回傳的 [Rect] 座標在「直向」(portrait) 空間：
  ///   - X ∈ [0, portraitW]  (portraitW = sensorH)
  ///   - Y ∈ [0, portraitH]  (portraitH = sensorW)
  /// 與 _LiveBboxPainter 的 scaleX/scaleY 映射一致。
  List<TfliteBbox> processCameraImage(
      CameraImage image, int rotationDegrees) {
    if (!_isInitialized || _interpreter == null) return [];

    try {
      // 1. 旋轉 + 縮放 → 模型輸入 buffer
      final inputBuf = _fillInputBuffer(image, rotationDegrees);
      if (inputBuf == null) return [];

      // 2. 執行推論
      _interpreter!.runForMultipleInputs([inputBuf], _outputMap);

      // 3. 解析偵測結果 + NMS
      final dets = _parseAndNms();
      if (dets.isEmpty) return [];

      // 4. 座標映射：模型空間 (640×640) → 直向 portrait 空間
      //    需要「去 letterbox」：先減去 padding 偏移，再按比例縮放。
      final double portraitW, portraitH;
      if (rotationDegrees == 90 || rotationDegrees == 270) {
        portraitW = image.height.toDouble(); // sensorH
        portraitH = image.width.toDouble();  // sensorW
      } else {
        portraitW = image.width.toDouble();
        portraitH = image.height.toDouble();
      }

      final double invSX = portraitW / _lbScaledW;
      final double invSY = portraitH / _lbScaledH;

      return dets.map((d) {
        final rect = Rect.fromLTRB(
          ((d.x1 - _lbPadX) * invSX).clamp(0.0, portraitW),
          ((d.y1 - _lbPadY) * invSY).clamp(0.0, portraitH),
          ((d.x2 - _lbPadX) * invSX).clamp(0.0, portraitW),
          ((d.y2 - _lbPadY) * invSY).clamp(0.0, portraitH),
        );
        return TfliteBbox(rect, d.conf, d.label);
      }).toList();
    } catch (e) {
      debugPrint('[TFLite] 推論錯誤: $e');
      return [];
    }
  }

  // ================================================================
  // 輸入前處理
  // ================================================================

  /// 高效率 YUV/BGRA → RGB letterbox + 旋轉。
  ///
  /// 關鍵設計：
  /// 1. **旋轉**：Android 手機直立拿著時，感測器輸出橫向影像 (如 1920×1080)。
  ///    如果不旋轉就餵給模型，樹幹會呈現水平 → 模型偵測不到。
  /// 2. **Letterbox**：YOLOv8 訓練時使用 letterbox（保持比例 + 灰色padding），
  ///    如果直接 stretch 會造成幾何失真 → 偵測精度下降 + bbox 座標錯誤。
  ///
  /// 此函式在採樣時同時完成旋轉 + letterbox，避免額外的完整影像轉換：
  /// - rotation=0: 直接採樣 (iOS portrait 或無需旋轉)
  /// - rotation=90: 90° CW 旋轉採樣 (大多數 Android 手機)
  /// - rotation=270: 270° CW 旋轉採樣 (少數 Android 前鏡頭)
  ///
  /// Letterbox 參數儲存至 _lbPadX/_lbPadY/_lbScaledW/_lbScaledH，
  /// 供 processCameraImage 做座標逆映射。
  ByteBuffer? _fillInputBuffer(CameraImage image, int rotationDegrees) {
    final srcW = image.width;   // 感測器原始寬 (通常是橫向較大值)
    final srcH = image.height;  // 感測器原始高
    final dst = _inputSize;

    // 旋轉後的「直向」尺寸
    final int portraitW, portraitH;
    if (rotationDegrees == 90 || rotationDegrees == 270) {
      portraitW = srcH;  // 感測器高 → 直向寬
      portraitH = srcW;  // 感測器寬 → 直向高
    } else {
      portraitW = srcW;
      portraitH = srcH;
    }

    // ── Letterbox：保持比例縮放 + 灰色padding ──
    // YOLOv8 訓練預設 pad 值 = 114 (RGB), 即 114/255 ≈ 0.447 (float)
    final double lbScale = min(dst / portraitW, dst / portraitH);
    final int scaledW = (portraitW * lbScale).round().clamp(1, dst);
    final int scaledH = (portraitH * lbScale).round().clamp(1, dst);
    final int padX = (dst - scaledW) ~/ 2;
    final int padY = (dst - scaledH) ~/ 2;

    // 儲存 letterbox 參數供座標逆映射使用
    _lbPadX = padX;
    _lbPadY = padY;
    _lbScaledW = scaledW;
    _lbScaledH = scaledH;

    // 從 letterbox 內容區域到 portrait 像素的步長
    final double stepPX = portraitW / scaledW;
    final double stepPY = portraitH / scaledH;

    // padding 像素值
    const double padFloat = 114.0 / 255.0; // ≈ 0.447
    const int padByte = 114;

    if (image.format.group == ImageFormatGroup.bgra8888) {
      // ── iOS BGRA ──
      final plane = image.planes[0].bytes;
      final rowBytes = image.planes[0].bytesPerRow;
      int idx = 0;
      for (int dy = 0; dy < dst; dy++) {
        for (int dx = 0; dx < dst; dx++) {
          // 判斷是否在 padding 區域
          if (dx < padX || dx >= padX + scaledW ||
              dy < padY || dy >= padY + scaledH) {
            if (_inputIsFloat) {
              _inputFloat![idx++] = padFloat;
              _inputFloat![idx++] = padFloat;
              _inputFloat![idx++] = padFloat;
            } else {
              _inputUint8![idx++] = padByte;
              _inputUint8![idx++] = padByte;
              _inputUint8![idx++] = padByte;
            }
            continue;
          }

          // 內容區域：從 letterbox 座標映射到 portrait 座標
          final px = ((dx - padX) * stepPX).toInt();
          final py = ((dy - padY) * stepPY).toInt();

          // portrait → sensor 座標轉換
          int sx, sy;
          if (rotationDegrees == 90) {
            sx = py.clamp(0, srcW - 1);
            sy = (srcH - 1 - px).clamp(0, srcH - 1);
          } else if (rotationDegrees == 270) {
            sx = (srcW - 1 - py).clamp(0, srcW - 1);
            sy = px.clamp(0, srcH - 1);
          } else {
            sx = px.clamp(0, srcW - 1);
            sy = py.clamp(0, srcH - 1);
          }

          final off = sy * rowBytes + sx * 4;
          if (off + 2 >= plane.length) continue;
          final b = plane[off];
          final g = plane[off + 1];
          final r = plane[off + 2];
          if (_inputIsFloat) {
            _inputFloat![idx++] = r / 255.0;
            _inputFloat![idx++] = g / 255.0;
            _inputFloat![idx++] = b / 255.0;
          } else {
            _inputUint8![idx++] = r;
            _inputUint8![idx++] = g;
            _inputUint8![idx++] = b;
          }
        }
      }
    } else if (image.format.group == ImageFormatGroup.yuv420 ||
        image.format.group == ImageFormatGroup.nv21) {
      // ── Android YUV420 / NV21 ──
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      final vPlane = image.planes[2].bytes;
      final yRowStride = image.planes[0].bytesPerRow;
      final uvRowStride = image.planes[1].bytesPerRow;
      final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      final uLen = uPlane.length;
      final vLen = vPlane.length;

      int idx = 0;
      for (int dy = 0; dy < dst; dy++) {
        for (int dx = 0; dx < dst; dx++) {
          // 判斷是否在 padding 區域
          if (dx < padX || dx >= padX + scaledW ||
              dy < padY || dy >= padY + scaledH) {
            if (_inputIsFloat) {
              _inputFloat![idx++] = padFloat;
              _inputFloat![idx++] = padFloat;
              _inputFloat![idx++] = padFloat;
            } else {
              _inputUint8![idx++] = padByte;
              _inputUint8![idx++] = padByte;
              _inputUint8![idx++] = padByte;
            }
            continue;
          }

          // 內容區域：從 letterbox 座標映射到 portrait 座標
          final px = ((dx - padX) * stepPX).toInt();
          final py = ((dy - padY) * stepPY).toInt();

          // portrait → sensor 座標轉換
          int sx, sy;
          if (rotationDegrees == 90) {
            sx = py.clamp(0, srcW - 1);
            sy = (srcH - 1 - px).clamp(0, srcH - 1);
          } else if (rotationDegrees == 270) {
            sx = (srcW - 1 - py).clamp(0, srcW - 1);
            sy = px.clamp(0, srcH - 1);
          } else {
            sx = px.clamp(0, srcW - 1);
            sy = py.clamp(0, srcH - 1);
          }

          // 邊界檢查避免越界 crash
          final yIdx = sy * yRowStride + sx;
          final uvOff = (sy >> 1) * uvRowStride + (sx >> 1) * uvPixelStride;

          final yVal = (yIdx < yPlane.length) ? yPlane[yIdx] : 128;
          final uVal = (uvOff < uLen) ? uPlane[uvOff] : 128;
          final vVal = (uvOff < vLen) ? vPlane[uvOff] : 128;

          int r = (yVal + 1.402 * (vVal - 128)).round();
          int g =
              (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
                  .round();
          int b = (yVal + 1.772 * (uVal - 128)).round();
          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          if (_inputIsFloat) {
            _inputFloat![idx++] = r / 255.0;
            _inputFloat![idx++] = g / 255.0;
            _inputFloat![idx++] = b / 255.0;
          } else {
            _inputUint8![idx++] = r;
            _inputUint8![idx++] = g;
            _inputUint8![idx++] = b;
          }
        }
      }
    } else {
      return null;
    }

    return _inputIsFloat ? _inputFloat!.buffer : _inputUint8!.buffer;
  }

  // ================================================================
  // 輸出後處理
  // ================================================================

  /// 解析 YOLOv8 detection output → confidence 過濾 → NMS
  List<_RawDet> _parseAndNms() {
    // ── 1. 解析全部候選框 ──
    final List<_RawDet> candidates = [];
    final det = _detOutputBuf!;

    for (int i = 0; i < _numDets; i++) {
      // 讀取 class confidence (取最大 class)
      double bestConf = -1;
      int bestCls = 0;
      for (int c = 0; c < _numClasses; c++) {
        final v = _detVal(det, 4 + c, i);
        if (v > bestConf) {
          bestConf = v;
          bestCls = c;
        }
      }
      if (bestConf < _confThreshold) continue;

      final cx = _detVal(det, 0, i);
      final cy = _detVal(det, 1, i);
      final w = _detVal(det, 2, i);
      final h = _detVal(det, 3, i);

      if (w <= 0 || h <= 0) continue;

      final label =
          (_labels != null && bestCls < _labels!.length)
              ? _labels![bestCls]
              : 'tree_trunk';

      candidates.add(_RawDet(cx, cy, w, h, bestConf, bestCls, label));
    }

    if (candidates.isEmpty) return [];

    // ── 2. NMS ──
    candidates.sort((a, b) => b.conf.compareTo(a.conf));
    final kept = <_RawDet>[];
    final suppressed = List<bool>.filled(candidates.length, false);

    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;
      kept.add(candidates[i]);
      if (kept.length >= _maxKeep) break;
      for (int j = i + 1; j < candidates.length; j++) {
        if (suppressed[j]) continue;
        if (_iou(candidates[i], candidates[j]) > _iouThreshold) {
          suppressed[j] = true;
        }
      }
    }

    return kept;
  }

  /// 從 (可能轉置的) 偵測 tensor 讀取 [channel][detIdx]
  double _detVal(Object det, int channel, int detIdx) {
    if (_detTransposed) {
      // [1, ch, dets]
      return ((det as List)[0][channel][detIdx] as num).toDouble();
    } else {
      // [1, dets, ch]
      return ((det as List)[0][detIdx][channel] as num).toDouble();
    }
  }

  /// IoU 計算
  double _iou(_RawDet a, _RawDet b) {
    final ix1 = max(a.x1, b.x1);
    final iy1 = max(a.y1, b.y1);
    final ix2 = min(a.x2, b.x2);
    final iy2 = min(a.y2, b.y2);
    if (ix2 <= ix1 || iy2 <= iy1) return 0;
    final inter = (ix2 - ix1) * (iy2 - iy1);
    final union = a.w * a.h + b.w * b.h - inter;
    return union > 0 ? inter / union : 0;
  }
}