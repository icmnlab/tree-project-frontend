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

/// 偵測結果 (bbox + confidence + label + optional seg mask width)
class TfliteBbox {
  final Rect rect; // 感測器座標空間中的 bounding box
  final double confidence;
  final String label;
  /// 方案 A: seg mask 測出的精確樹幹像素寬度（portrait 空間，可能為 null）
  final double? maskPixelWidth;

  TfliteBbox(this.rect, this.confidence, this.label, {this.maskPixelWidth});
}

/// 內部：NMS 前的原始偵測
class _RawDet {
  final double cx, cy, w, h;
  final double conf;
  final int cls;
  final String label;
  /// YOLOv8-seg mask coefficients (32 values); null if not a seg model
  final List<double>? maskCoeffs;

  _RawDet(this.cx, this.cy, this.w, this.h, this.conf, this.cls, this.label,
      {this.maskCoeffs});

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
  // NOTE: _outputMap is rebuilt each frame to avoid GPU-delegate reuse issues.
  Map<int, Object>? _outputMap;

  // 當 GPU delegate 無法處理多輸出時停用 proto output
  // (某些裝置 GPU delegate 只看到 1 個 output tensor)
  bool _protoOutputDisabled = false;

  // ── Debug: 第一幀診斷 ──
  bool _firstFrameDiagDone = false;
  bool _inferenceSuccessLogged = false;
  bool _useGpuDelegate = false;  // 記錄是否使用了 GPU delegate
  Uint8List? _modelBuffer;  // 保留模型 buffer 供 CPU fallback 重載

  // ── 預配置輸入 buffer ──
  Float32List? _inputFloat;
  Uint8List? _inputUint8;

  // ── CPU fallback 進行中 ──
  bool _cpuReloadInProgress = false;

  // ── 閾值 ──
  final double _confThreshold = 0.25;
  final double _iouThreshold = 0.45;
  static const int _maxKeep = 5;
  int _parseCallCount = 0; // debug: 記錄 parseAndNms 呼叫次數

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
    _modelBuffer = buffer;  // 保留 buffer 供 CPU fallback 使用

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
        _useGpuDelegate = true;
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

    // ── DEBUG: 列印所有 tensor 資訊 ──
    final inputTensors = interp.getInputTensors();
    debugPrint('[TFLite-DEBUG] ═══ 模型 Tensor 詳情 ═══');
    debugPrint('[TFLite-DEBUG] GPU delegate: $_useGpuDelegate');
    debugPrint('[TFLite-DEBUG] Input tensors: ${inputTensors.length}');
    for (int i = 0; i < inputTensors.length; i++) {
      final t = inputTensors[i];
      debugPrint('[TFLite-DEBUG]   input[$i] name="${t.name}" '
          'shape=${t.shape} type=${t.type}');
    }

    final outputTensors = interp.getOutputTensors();
    debugPrint('[TFLite-DEBUG] Output tensors: ${outputTensors.length}');
    for (int i = 0; i < outputTensors.length; i++) {
      final t = outputTensors[i];
      debugPrint('[TFLite-DEBUG]   output[$i] name="${t.name}" '
          'shape=${t.shape} type=${t.type} '
          'numElements=${t.numElements()}');
    }
    debugPrint('[TFLite-DEBUG] ═══════════════════════');

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
    } else {
      // GPU delegate 可能改變了 output shape
      debugPrint('[TFLite-DEBUG] ⚠ output[0] shape 不是 3D: $detShape');
      // 如果 GPU delegate 把多輸出合併成一個，shape 可能是 [1, N]
      // 其中 N = 37*8400 + 160*160*32 = 310800 + 819200 = 1130000
      if (detShape.length == 2 && detShape[1] > _numDets * _detChannels) {
        debugPrint('[TFLite-DEBUG] ⚠ GPU delegate 似乎合併了 output tensors');
      }
    }

    // ── Output 1: prototypes (optional) ──
    _numOutputs = outputTensors.length;
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

    // Prototype output (if present) — use generic shape builder to handle
    // any dimensionality (onnx2tf FP16 exports may differ from 4D).
    if (_numOutputs > 1) {
      final protoShape = _interpreter!.getOutputTensor(1).shape;
      _protoOutputBuf = _buildOutputBuffer(protoShape);
      _outputMap![1] = _protoOutputBuf!;
      debugPrint('[TFLite] proto output shape: $protoShape');
    }
  }

  /// 遞迴建立任意維度的巢狀 List，用來接收 TFLite 輸出 tensor。
  static Object _buildOutputBuffer(List<int> shape) {
    if (shape.isEmpty) return <double>[];
    if (shape.length == 1) return List<double>.filled(shape[0], 0.0);
    return List.generate(
        shape[0], (_) => _buildOutputBuffer(shape.sublist(1)));
  }

  void dispose() {
    _interpreter?.close();
    _isInitialized = false;
  }

  /// GPU delegate 推論失敗時，非同步重載為 CPU-only interpreter。
  void _scheduleReloadWithCpu() {
    if (_cpuReloadInProgress) return;
    _cpuReloadInProgress = true;
    _reloadWithCpu().then((_) {
      _cpuReloadInProgress = false;
    });
  }

  Future<void> _reloadWithCpu() async {
    debugPrint('[TFLite-RELOAD] 開始 CPU interpreter 重載...');
    try {
      _interpreter?.close();
      _interpreter = null;

      if (_modelBuffer == null) {
        debugPrint('[TFLite-RELOAD] ✗ 無 model buffer，無法重載');
        return;
      }

      // 動態決定 thread 數
      final int cpuCores = Platform.numberOfProcessors;
      final int optimalThreads = (cpuCores ~/ 2).clamp(1, 4);

      final options = InterpreterOptions()..threads = optimalThreads;
      _interpreter = Interpreter.fromBuffer(_modelBuffer!, options: options);
      _useGpuDelegate = false;

      // 重新 introspect 和分配 buffer
      _introspectModel();
      _allocateBuffers();
      _firstFrameDiagDone = false;  // 讓 CPU 模式也做一次診斷

      debugPrint('[TFLite-RELOAD] ✓ CPU interpreter 重載成功 '
          '(threads=$optimalThreads, outputs=$_numOutputs)');
    } catch (e, st) {
      debugPrint('[TFLite-RELOAD] ✗ CPU 重載失敗: $e');
      debugPrint('[TFLite-RELOAD] stack: $st');
      _isInitialized = false;
    }
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
    if (!_isInitialized || _interpreter == null || _cpuReloadInProgress) return [];

    try {
      // ── DEBUG: 第一幀影像格式診斷（在 _fillInputBuffer 之前）──
      if (!_firstFrameDiagDone) {
        debugPrint('[TFLite-DEBUG] ═══ 第一幀影像診斷 ═══');
        debugPrint('[TFLite-DEBUG] image: ${image.width}x${image.height}  '
            'format=${image.format.group}  formatRaw=${image.format.raw}  '
            'planes=${image.planes.length}');
        for (int i = 0; i < image.planes.length; i++) {
          final p = image.planes[i];
          debugPrint('[TFLite-DEBUG]   plane[$i]: '
              'bytes=${p.bytes.length}  '
              'bytesPerRow=${p.bytesPerRow}  '
              'bytesPerPixel=${p.bytesPerPixel}');
        }
        debugPrint('[TFLite-DEBUG] rotation=$rotationDegrees  '
            'inputSize=$_inputSize  inputIsFloat=$_inputIsFloat');
        debugPrint('[TFLite-DEBUG] _numOutputs=$_numOutputs  '
            '_protoOutputDisabled=$_protoOutputDisabled  '
            'GPU=$_useGpuDelegate');
      }

      // 1. 旋轉 + 縮放 → 模型輸入 buffer
      final inputBuf = _fillInputBuffer(image, rotationDegrees);
      if (inputBuf == null) {
        if (!_firstFrameDiagDone) {
          debugPrint('[TFLite-DEBUG] _fillInputBuffer 返回 null！');
        }
        _firstFrameDiagDone = true;
        return [];
      }

      // 第一幀標記
      if (!_firstFrameDiagDone) {
        _firstFrameDiagDone = true;
      }

      // 2. 每幀建立新的 outputs map（避免 GPU delegate reuse 問題）
      final Map<int, Object> outputsMap = {0: _detOutputBuf!};
      if (_numOutputs > 1 && _protoOutputBuf != null && !_protoOutputDisabled) {
        outputsMap[1] = _protoOutputBuf!;
      }

      // 3. 執行推論
      try {
        _interpreter!.runForMultipleInputs([inputBuf], outputsMap);
        if (!_inferenceSuccessLogged) {
          _inferenceSuccessLogged = true;
          debugPrint('[TFLite] ✓ 推論成功 (GPU=$_useGpuDelegate, '
              'outputs=${outputsMap.keys.toList()})');
        }
      } catch (e, st) {
        debugPrint('[TFLite-FALLBACK] runForMultipleInputs 失敗 '
            '(keys=${outputsMap.keys.toList()}): $e');
        debugPrint('[TFLite-FALLBACK] stack: $st');
        // GPU delegate 無法推論此模型 → 直接 CPU 重載
        debugPrint('[TFLite-FALLBACK] 排程 CPU interpreter 重載...');
        _scheduleReloadWithCpu();
        return [];
      }

      // 4. 解析偵測結果 + NMS
      final dets = _parseAndNms();
      if (dets.isEmpty) return [];

      // 5. 座標映射：模型空間 (640×640) → 直向 portrait 空間
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

        // ── 方案 A: 從 seg mask 計算精確像素寬度 ──
        // 利用 proto output (output[1]) + detection coefficients 重建 mask
        // 並在 letterbox 空間取 bbox 中心行的 mask 寬度，再逆映射到 portrait 空間
        double? maskPixelWidth;
        if (_numOutputs > 1 && _protoOutputBuf != null && !_protoOutputDisabled) {
          try {
            maskPixelWidth = _computeMaskWidth(d, invSX);
          } catch (_) {}
        }

        return TfliteBbox(rect, d.conf, d.label, maskPixelWidth: maskPixelWidth);
      }).toList();
    } catch (e, st) {
      debugPrint('[TFLite] 推論錯誤: $e');
      debugPrint('[TFLite] 推論錯誤 stack: $st');
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
      // camera_android (Camera2) 和 camera_android_camerax 可能產生不同平面佈局：
      //   - 3 planes: Y / U / V (YUV420) or Y / VU interleaved (NV21)
      //   - 2 planes: Y / VU interleaved
      //   - 1 plane:  全部交錯 (YUYV / NV21 packed)
      final int numPlanes = image.planes.length;

      if (numPlanes < 2) {
        // 只有 1 個 plane — 嘗試用 NV21 packed 格式解析
        // NV21 packed: [Y0 Y1 ... Yn V0 U0 V1 U1 ...]
        final data = image.planes[0].bytes;
        final yRowStride = image.planes[0].bytesPerRow;
        final int ySize = srcH * yRowStride;

        int idx = 0;
        for (int dy = 0; dy < dst; dy++) {
          for (int dx = 0; dx < dst; dx++) {
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

            final px = ((dx - padX) * stepPX).toInt();
            final py = ((dy - padY) * stepPY).toInt();

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

            final yIdx = sy * yRowStride + sx;
            final yVal = (yIdx < data.length) ? data[yIdx] : 128;

            // NV21 VU interleaved after Y plane
            final uvBase = ySize + (sy >> 1) * yRowStride + (sx & ~1);
            int vVal = 128, uVal = 128;
            if (uvBase + 1 < data.length) {
              vVal = data[uvBase];
              uVal = data[uvBase + 1];
            }

            int r = (yVal + 1.402 * (vVal - 128)).round().clamp(0, 255);
            int g = (yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128))
                .round().clamp(0, 255);
            int b = (yVal + 1.772 * (uVal - 128)).round().clamp(0, 255);

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
      // 2 or 3 planes — standard YUV420 / NV21 with separate planes
      final yPlane = image.planes[0].bytes;
      final uPlane = image.planes[1].bytes;
      // plane[2] 可能不存在 (NV21 2-plane: Y + VU interleaved)
      final vPlane = (numPlanes >= 3) ? image.planes[2].bytes : image.planes[1].bytes;
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
      } // end else (2-3 planes)
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
    _parseCallCount++;

    // Debug: 追蹤 top-5 最高信心度
    final topConfs = <double>[];

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

      // Debug: 記錄 top-5 最高信心度
      if (topConfs.length < 5) {
        topConfs.add(bestConf);
        topConfs.sort((a, b) => b.compareTo(a));
      } else if (bestConf > topConfs.last) {
        topConfs[4] = bestConf;
        topConfs.sort((a, b) => b.compareTo(a));
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

      // 提取 mask coefficients (channels 4+nc … 4+nc+31)
      final int numMaskCoeffs = _detChannels - 4 - _numClasses;
      final bool hasMask = numMaskCoeffs == 32 && _numOutputs > 1;
      List<double>? coeffs;
      if (hasMask) {
        coeffs = List<double>.generate(
            32, (k) => _detVal(det, 4 + _numClasses + k, i));
      }

      candidates.add(
          _RawDet(cx, cy, w, h, bestConf, bestCls, label, maskCoeffs: coeffs));
    }

    // Debug: 每 5 次推論輸出信心度統計
    if (_parseCallCount <= 3 || _parseCallCount % 5 == 0) {
      final topStr = topConfs.map((v) => v.toStringAsFixed(3)).join(', ');
      debugPrint('[TFLite-PARSE] #$_parseCallCount  '
          'candidates=${candidates.length}  '
          'top5conf=[$topStr]');
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

  // ================================================================
  // 方案 A: Seg Mask  精確像素寬度
  // ================================================================

  /// 從 YOLOv8-seg proto output 重建 mask，計算樹幹在 portrait 空間的像素寬度。
  ///
  /// YOLOv8-seg output[1] proto shape: [1, Ph, Pw, 32]
  /// mask = sigmoid(proto[0][y][x]  coeffs) > 0.5    logit > 0
  ///
  /// 步驟：
  ///   1. 取 bbox 中央行在 proto 空間的 y 座標
  ///   2. 對每個 x 柱做 dot(proto[0][py][px], coeffs)  logit
  ///   3. logit > 0  trunk pixel
  ///   4. 計算最長連續 mask 段的寬度，換算回 portrait pixel
  double? _computeMaskWidth(_RawDet det, double invSX) {
    if (det.maskCoeffs == null || _protoOutputBuf == null) return null;

    final proto = _protoOutputBuf as List; // [1][Ph][Pw][32]
    final protoFrame = proto[0] as List;   // [Ph][Pw][32]
    final int Ph = protoFrame.length;
    if (Ph == 0) return null;
    final int Pw = (protoFrame[0] as List).length;
    if (Pw == 0) return null;

    final coeffs = det.maskCoeffs!;

    // bbox 中央行 (letterbox 空間 0.._inputSize)
    final double midY = (det.y1 + det.y2) / 2.0;
    // letterbox  proto 座標
    final int py = ((midY / _inputSize) * Ph).round().clamp(0, Ph - 1);

    // x 範圍：bbox letterbox x1..x2  proto x
    final int pxLeft  = ((det.x1 / _inputSize) * Pw).floor().clamp(0, Pw - 1);
    final int pxRight = ((det.x2 / _inputSize) * Pw).ceil().clamp(0, Pw - 1);

    // dot product; logit > 0  sigmoid > 0.5
    int maxRun = 0, curRun = 0;
    for (int px = pxLeft; px <= pxRight; px++) {
      final protoVec = protoFrame[py][px] as List;
      double logit = 0.0;
      for (int k = 0; k < 32; k++) {
        logit += (protoVec[k] as num).toDouble() * coeffs[k];
      }
      if (logit > 0.0) {
        curRun++;
        if (curRun > maxRun) maxRun = curRun;
      } else {
        curRun = 0;
      }
    }

    if (maxRun == 0) return null;

    // proto pixels  letterbox pixels  portrait pixels
    final double lbPixelWidth = maxRun * (_inputSize / Pw);
    final double portraitPixelWidth = lbPixelWidth * invSX;
    return portraitPixelWidth;
  }
}
