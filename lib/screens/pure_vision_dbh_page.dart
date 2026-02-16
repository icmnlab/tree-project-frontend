import 'dart:async';
import 'dart:io';
import 'dart:math' show atan;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:exif/exif.dart';
import '../services/pure_vision_dbh_service.dart';
import '../services/ar_measurement_service.dart';

/// 純視覺 DBH 測量頁面
///
/// 流程：
/// 1. 相機拍攝 → 2. 框選樹幹 → 3. AI 推論 → 4. 顯示結果
///
/// 回傳 [MeasurementResult] 以相容現有的測量流程。
class PureVisionDbhPage extends StatefulWidget {
  final double? initialDbh;
  final String? speciesName;

  const PureVisionDbhPage({
    super.key,
    this.initialDbh,
    this.speciesName,
  });

  @override
  State<PureVisionDbhPage> createState() => _PureVisionDbhPageState();
}

enum _PageStep { camera, drawBbox, processing, result }

class _PureVisionDbhPageState extends State<PureVisionDbhPage>
    with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _checkService();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _cameraController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed && _step == _PageStep.camera) {
      _initializeCamera();
    }
  }

  Future<void> _checkService() async {
    _serviceAvailable = await _service.isServiceAvailable();
    if (mounted) setState(() {});
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.jpeg
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _cameraController!
          .lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (mounted) {
        setState(() => _isCameraInitialized = true);
      }
    } catch (e) {
      debugPrint('相機初始化失敗: $e');
    }
  }

  // ===========================================================
  // 步驟 1: 拍照
  // ===========================================================

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final xFile = await _cameraController!.takePicture();
      final file = File(xFile.path);

      // 讀取照片尺寸
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);

      // 提取 EXIF 焦距 + 手機型號
      double? focalMm;
      double? focal35;
      String? phoneMake;
      String? phoneModel;
      try {
        final exifData = await readExifFromBytes(bytes);
        // FocalLength: e.g. "471/100" → 4.71mm
        final focalTag = exifData['EXIF FocalLength'];
        if (focalTag != null) {
          final ratio = focalTag.values;
          if (ratio is IfdRatios && ratio.ratios.isNotEmpty) {
            focalMm = ratio.ratios.first.numerator / ratio.ratios.first.denominator;
          } else {
            focalMm = double.tryParse(focalTag.printable.replaceAll(' ', ''));
          }
        }
        // FocalLengthIn35mmFilm: integer
        final focal35Tag = exifData['EXIF FocalLengthIn35mmFilm'];
        if (focal35Tag != null) {
          focal35 = double.tryParse(focal35Tag.printable.replaceAll(' ', ''));
        }
        // Make & Model for sensor width lookup
        final makeTag = exifData['Image Make'];
        if (makeTag != null) {
          phoneMake = makeTag.printable.trim();
        }
        final modelTag = exifData['Image Model'];
        if (modelTag != null) {
          phoneModel = modelTag.printable.trim();
        }
        debugPrint('[EXIF] Make: $phoneMake, Model: $phoneModel, '
            'FocalLength: ${focalMm}mm, 35mm equiv: $focal35');
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
          // 自動模式：跳過框選，直接進入 AI 自動偵測
          _step = _PageStep.processing;
        } else {
          _step = _PageStep.drawBbox;
        }
      });

      // 自動模式下自動送出
      if (_isAutoMode) {
        _submitAutoMeasurement();
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

  /// 將螢幕座標轉換為原始圖片座標
  /// 使用 BoxFit.contain 計算: 圖片等比縮放並置中，需扣除 letterbox 偏移量
  Rect _screenBboxToImageBbox(Rect screenBbox, Size displaySize) {
    if (_imageSize == null) return screenBbox;

    // BoxFit.contain: 等比縮放至完全顯示
    final scale = _containScale(displaySize);
    final renderedW = _imageSize!.width * scale;
    final renderedH = _imageSize!.height * scale;
    // letterbox 偏移量 (黑邊)
    final offsetX = (displaySize.width - renderedW) / 2.0;
    final offsetY = (displaySize.height - renderedH) / 2.0;

    // 螢幕座標 → 原圖座標
    double toImgX(double sx) => ((sx - offsetX) / scale).clamp(0, _imageSize!.width);
    double toImgY(double sy) => ((sy - offsetY) / scale).clamp(0, _imageSize!.height);

    final x1 = toImgX(screenBbox.left);
    final y1 = toImgY(screenBbox.top);
    final x2 = toImgX(screenBbox.right);
    final y2 = toImgY(screenBbox.bottom);

    // 確保 x1 < x2, y1 < y2（防止 clamp 後座標反轉或重疊）
    return Rect.fromLTRB(
      x1 < x2 ? x1 : x2,
      y1 < y2 ? y1 : y2,
      x1 < x2 ? x2 : x1 + 1,
      y1 < y2 ? y2 : y1 + 1,
    );
  }

  /// BoxFit.contain 的縮放比例
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

    // 前端先驗證 bbox 最小尺寸（螢幕座標至少 20px）
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
      // 轉換座標（Rect.fromPoints 已正規化，left<=right, top<=bottom）
      final imgBbox = _screenBboxToImageBbox(_currentBbox!, displaySize);

      // 計算 FOV (如果有 35mm 等效焦距)
      // FOV = 2 * atan(36 / (2 * f_35mm)) * 180 / pi
      // 36mm = 35mm 片幅寬度
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
        returnVisualization: false,
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

  Future<void> _submitAutoMeasurement() async {
    if (_capturedImage == null) return;

    setState(() {
      _step = _PageStep.processing;
      _errorMessage = null;
      _autoResult = null;
    });

    try {
      // 計算 FOV (如果有 35mm 等效焦距)
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
        returnVisualization: false,
        returnDetectionVisualization: false,
      );

      if (mounted) {
        if (result.success) {
          setState(() {
            _autoResult = result;
            _step = _PageStep.result;
          });
        } else {
          // 自動偵測失敗 — 顯示偵測視覺化圖，並提供手動模式
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
          // 自動切換成手動模式
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
          Center(child: CameraPreview(_cameraController!))
        else
          const Center(child: CircularProgressIndicator()),

        // 頂部列
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildAppBar('純視覺 AI 測量'),
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
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ML 服務未連線，請確認伺服器已啟動',
                      style: TextStyle(color: Colors.white, fontSize: 13),
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
            _isAutoMode ? '🤖 AI 自動偵測模式' : '📸 手動框選模式',
            subtitle: _isAutoMode
                ? '對準樹幹拍照，AI 自動辨識並量測'
                : '拍照後手動框選樹幹範圍',
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
              onTap: _serviceAvailable ? _capturePhoto : null,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _serviceAvailable ? Colors.white : Colors.grey,
                    width: 4,
                  ),
                ),
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _serviceAvailable ? Colors.white : Colors.grey,
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
          // 已拍攝的照片
          if (_capturedImage != null)
            Image.file(
              _capturedImage!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),

          // Bbox 繪圖層
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

          // 頂部列
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildAppBar('框選樹幹'),
          ),

          // 提示
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade900.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textAlign: TextAlign.center),
                  ),
                _buildInstructionChip(
              '✋ 用手指框選樹幹範圍',
              subtitle: '儘量貼緊樹幹邊緣',
            ),
              ],
            ),
          ),

          // 底部按鈕
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 重拍
                FloatingActionButton(
                  heroTag: 'retake',
                  onPressed: () {
                    setState(() {
                      _step = _PageStep.camera;
                      _capturedImage = null;
                      _currentBbox = null;
                    });
                  },
                  backgroundColor: Colors.grey[700],
                  child: const Icon(Icons.camera_alt, color: Colors.white),
                ),
                // 清除框選
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
                // 確認並送出
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
              _isAutoMode
                  ? '正在自動辨識樹幹並計算胸徑'
                  : '正在使用 Depth Anything V2 分析影像',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              '首次請求可能需要 30-60 秒（伺服器喚醒）',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
            const SizedBox(height: 24),
            // 取消按鈕
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
              },
              icon: const Icon(Icons.cancel_outlined, color: Colors.white54, size: 18),
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
    // 根據模式選擇結果來源
    if (_isAutoMode && _autoResult != null) {
      return _buildAutoResultView();
    }
    final r = _result;
    if (r == null) return const SizedBox.shrink();
    return _buildManualResultView(r);
  }

  /// 自動偵測模式的結果頁
  Widget _buildAutoResultView() {
    final r = _autoResult!;
    final dbh = r.dbhCm ?? 0;
    final conf = r.confidence ?? 0;

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildAppBar('自動偵測結果'),

          // 距離狀態提示
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

          // 偵測視覺化 + 量測視覺化
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    color: Colors.grey[900],
                    child: Row(
                      children: [
                        Icon(Icons.auto_awesome,
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

          // DBH 主數值
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.auto_awesome,
                        color: Colors.tealAccent, size: 18),
                    const SizedBox(width: 6),
                    const Text('自動偵測 DBH (胸徑)',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14)),
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
                    _buildBadge('信心度: ${r.confidenceLevel}',
                        _confidenceColor(conf)),
                    _buildBadge(
                        '深度: ${r.trunkDepthM?.toStringAsFixed(2) ?? "?"}m',
                        Colors.blueGrey),
                    _buildBadge(
                      _distanceStatusLabel(r.distanceStatus),
                      _distanceStatusColor(r.distanceStatus),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 詳細資料
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
                  _buildDetailRow('樹幹像素寬度',
                      '${r.trunkPixelWidth!.toStringAsFixed(0)} px'),
                if (r.chordLengthM != null)
                  _buildDetailRow(
                      '弦長', '${r.chordLengthM!.toStringAsFixed(4)} m'),
                if (r.focalLengthPx != null)
                  _buildDetailRow(
                      '焦距', '${r.focalLengthPx!.toStringAsFixed(1)} px'),
                if (r.method != null)
                  _buildDetailRow('測量方法', r.method!),
                _buildDetailRow('深度估計耗時',
                    '${r.depthEstimationMs.toStringAsFixed(0)} ms'),
                _buildDetailRow(
                    '偵測耗時', '${r.detectionMs.toStringAsFixed(0)} ms'),
                _buildDetailRow(
                    'DBH 計算耗時',
                    '${r.dbhCalculationMs.toStringAsFixed(0)} ms'),
                _buildDetailRow('總耗時',
                    '${r.totalMs.toStringAsFixed(0)} ms'),
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('備註:',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 12)),
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

          // 底部按鈕
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

  /// 手動框選模式的結果頁（原有邏輯）
  Widget _buildManualResultView(PureVisionDbhResult r) {

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildAppBar('測量結果'),

          // 視覺化圖片
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

          // DBH 主數值
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

          // 詳細資料
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
                _buildDetailRow('樹幹像素寬度',
                    '${r.trunkPixelWidth.toStringAsFixed(0)} px'),
                _buildDetailRow(
                    '弦長', '${r.chordLengthM.toStringAsFixed(4)} m'),
                _buildDetailRow(
                    '焦距', '${r.focalLengthPx.toStringAsFixed(1)} px'),
                _buildDetailRow('測量方法', r.method),
                _buildDetailRow('深度估計耗時',
                    '${r.depthEstimationMs.toStringAsFixed(0)} ms'),
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

          // 底部按鈕
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

  // ===========================================================
  // Helper Widgets
  // ===========================================================

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
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ],
      ),
    );
  }

  Color _confidenceColor(double c) {
    if (c >= 0.75) return Colors.green;
    if (c >= 0.5) return Colors.orange;
    return Colors.red;
  }

  /// 距離狀態顏色
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

  /// 距離狀態圖標
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

  /// 距離狀態標籤
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

// ===========================================================
// Bounding Box 繪圖器
// ===========================================================

class _BboxOverlayPainter extends CustomPainter {
  final Rect? bbox;

  _BboxOverlayPainter({this.bbox});

  @override
  void paint(Canvas canvas, Size size) {
    if (bbox == null) return;

    // 半透明遮罩 (框外區域變暗)
    final Path fullPath = Path()..addRect(Offset.zero & size);
    final Path bboxPath = Path()..addRect(bbox!);
    final Path dimPath =
        Path.combine(PathOperation.difference, fullPath, bboxPath);
    canvas.drawPath(
      dimPath,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );

    // 框線
    final borderPaint = Paint()
      ..color = Colors.tealAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(bbox!, borderPaint);

    // 四角標記
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
      bbox!.bottomRight,
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

    // 中心十字
    final cx = bbox!.center.dx;
    final cy = bbox!.center.dy;
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx - 12, cy), Offset(cx + 12, cy), crossPaint);
    canvas.drawLine(Offset(cx, cy - 12), Offset(cx, cy + 12), crossPaint);

    // 尺寸標籤
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
        shadows: [Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black)],
      ),
    );
    final tp = TextPainter(text: ts, textDirection: TextDirection.ltr);
    tp.layout();
    tp.paint(canvas, position - Offset(tp.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _BboxOverlayPainter old) => old.bbox != bbox;
}
