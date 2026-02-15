import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for DeviceOrientation
import 'package:camera/camera.dart';
import 'package:geolocator/geolocator.dart'; // [New] For GPS distance
import 'package:latlong2/latlong.dart' as latlong; // [New] For distance calculation
import '../services/ar_measurement_service.dart';
import 'pure_vision_dbh_page.dart';

/// 現代化 AR 測量介面 (iPhone 測距儀風格)
///
/// 核心功能：
/// 1. Live Camera Preview (全螢幕即時預覽)
/// 2. 根部參照物定位 (或 GPS 自動距離) -> 自動延伸 1.3m 虛擬尺
/// 3. 一鍵測量 DBH
class ARDBHMeasurementPage extends StatefulWidget {
  final double? initialDbh;
  final String? speciesName;
  final double? knownDistance;
  
  // [New] 樹木座標，用於 GPS 自動測距
  final double? targetLat;
  final double? targetLon;

  const ARDBHMeasurementPage({
    super.key,
    this.initialDbh,
    this.speciesName,
    this.knownDistance,
    this.targetLat,
    this.targetLon,
  });

  @override
  State<ARDBHMeasurementPage> createState() => _ARDBHMeasurementPageState();
}

class _ARDBHMeasurementPageState extends State<ARDBHMeasurementPage>
    with WidgetsBindingObserver {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  // Measurement State
  int _step = 0;

  // Measurement Mode
  bool _useDistanceMode = false; // 是否使用「已知距離模式」

  // Reference Object
  ReferenceObject _selectedReference = ReferenceObject.commonObjects[0]; // Default Credit Card
  Rect? _referenceRect;
  Offset? _dragStart;
  Offset? _dragCurrent;

  // Manual/GPS Distance Input
  late TextEditingController _distanceController;
  bool _isLocating = false; // GPS 定位中

  // Virtual Ruler
  double? _pixelsPerCm;
  double? _virtualLineY;

  // Tree Width Measurement
  Offset? _measureLineStart;
  Offset? _measureLineEnd;

  // Result
  MeasurementResult? _currentResult;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 初始化距離：優先使用傳入的已知距離
    _distanceController = TextEditingController(
      text: widget.knownDistance?.toString() ?? '1.5',
    );
    
    // 如果有傳入樹木座標，且沒有已知距離，預設開啟距離模式並嘗試自動計算
    if (widget.targetLat != null && widget.targetLon != null && widget.knownDistance == null) {
      _useDistanceMode = true;
      // 延遲執行，以免在 initState 中觸發 setState
      Future.delayed(Duration.zero, _calculateDistanceByGPS);
    } else if (widget.knownDistance != null) {
      // 如果有 VLGEO 傳來的已知距離，也預設開啟距離模式
      _useDistanceMode = true;
    }

    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _cameraController;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.jpeg : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _cameraController!.lockCaptureOrientation(DeviceOrientation.portraitUp);

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('相機初始化失敗: $e');
    }
  }

  // [New] 使用 GPS 計算與樹木的距離
  Future<void> _calculateDistanceByGPS() async {
    if (widget.targetLat == null || widget.targetLon == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無樹木座標資料，無法使用 GPS 測距')),
      );
      return;
    }

    setState(() => _isLocating = true);

    try {
      // 檢查定位權限
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw '定位權限被拒絕';
        }
      }

      // 獲取當前位置 (高精度)
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      // 計算距離 (使用 latlong2 的 Distance)
      final latlong.Distance distance = latlong.Distance();
      final double meter = distance(
        latlong.LatLng(position.latitude, position.longitude),
        latlong.LatLng(widget.targetLat!, widget.targetLon!),
      );

      // 更新 UI
      if (mounted) {
        setState(() {
          _distanceController.text = meter.toStringAsFixed(2);
          _isLocating = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS 自動測距: ${meter.toStringAsFixed(2)} 公尺'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('GPS 測距失敗: $e');
      if (mounted) {
        setState(() => _isLocating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS 測距失敗: $e')),
        );
      }
    }
  }

  // [New] 開啟純視覺 AI 測量頁面
  Future<void> _openPureVisionMode() async {
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (context) => PureVisionDbhPage(
          initialDbh: widget.initialDbh,
          speciesName: widget.speciesName,
        ),
      ),
    );

    if (result != null && mounted) {
      // 直接回傳結果給上層 (透傳)
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: CameraPreview(_cameraController!)),
          GestureDetector(
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            child: CustomPaint(
              painter: _AROverlayPainter(
                step: _step,
                referenceRect: _referenceRect,
                dragStart: _dragStart,
                dragCurrent: _dragCurrent,
                virtualLineY: _virtualLineY,
                measureLineStart: _measureLineStart,
                measureLineEnd: _measureLineEnd,
                pixelsPerCm: _pixelsPerCm,
                useDistanceMode: _useDistanceMode,
              ),
              child: Container(color: Colors.transparent),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
              const Spacer(),
                _buildInstructionOverlay(),
                const SizedBox(height: 20),
                _buildBottomControls(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black45,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
            Column(
              children: [
              const Text(
                'AR 智慧測量',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (widget.targetLat != null)
                      Text(
                  '樹木座標: ${widget.targetLat!.toStringAsFixed(5)}, ${widget.targetLon!.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                            ),
                          ],
                        ),
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionOverlay() {
    String text = '';
    Color bgColor = Colors.black54;

    switch (_step) {
      case 0:
        text = _useDistanceMode 
            ? '請輸入距離 (可使用 GPS 自動計算)\n或輸入 VLGEO 測量數據'
            : '請將 [${_selectedReference.nameZh}] 放在樹根地面\n點擊下方按鈕開始標記';
        break;
      case 1:
        text = '在螢幕上框選地面的參照物\n(確保框線貼合邊緣)';
        break;
      case 2:
        text = _useDistanceMode
            ? '滑動黃色測量線的兩端\n使其對齊樹幹寬度'
            : '綠線為地面向上 1.3m 處\n調整手機讓綠線對準樹幹胸高\n然後滑動綠線兩端測量寬度';
        bgColor = Colors.green.withOpacity(0.6);
        break;
      case 3:
        text = '測量完成！\nDBH: ${_currentResult?.diameterCm.toStringAsFixed(1)} cm';
        bgColor = Colors.blue.withOpacity(0.6);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(30),
      ),
        child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }

  Widget _buildBottomControls() {
    if (_step == 0) {
      return Column(
        children: [
          // 純視覺 AI 模式入口
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ElevatedButton.icon(
              onPressed: _openPureVisionMode,
              icon: const Icon(Icons.auto_awesome, size: 20),
              label: const Text('🤖 純視覺 AI 測量 (推薦)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
      children: [
                _buildModeButton('參照物模式', !_useDistanceMode, () {
                  setState(() => _useDistanceMode = false);
                }),
                _buildModeButton('距離模式 (GPS)', _useDistanceMode, () {
                  setState(() => _useDistanceMode = true);
                }),
              ],
            ),
          ),
          
          if (!_useDistanceMode) ...[
            Container(
              height: 50,
              margin: const EdgeInsets.only(bottom: 16),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: ReferenceObject.commonObjects.length,
                itemBuilder: (context, index) {
                  final ref = ReferenceObject.commonObjects[index];
                  final isSelected = ref.name == _selectedReference.name;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedReference = ref),
                    child: Container(
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
                        color: isSelected ? Colors.teal : Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected ? Border.all(color: Colors.white, width: 2) : null,
                      ),
                      alignment: Alignment.center,
      child: Text(
                        ref.nameZh,
        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            FloatingActionButton.extended(
              onPressed: () => setState(() => _step = 1),
              icon: const Icon(Icons.crop_free),
              label: const Text('開始標記參照物'),
              backgroundColor: Colors.teal,
            ),
          ] else ...[
            // [Modified] 距離輸入介面 (整合 GPS 按鈕)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
          children: [
            Expanded(
              child: TextField(
                      controller: _distanceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontSize: 24),
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: '距離 (公尺)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.tealAccent)),
                        suffixText: 'm',
                        suffixStyle: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
            const SizedBox(width: 12),
                  // GPS 定位按鈕
                  SizedBox(
                    height: 56,
                    width: 56,
                    child: ElevatedButton(
                      onPressed: (widget.targetLat == null || _isLocating) 
                          ? null 
                          : _calculateDistanceByGPS,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLocating 
                          ? const SizedBox(
                              width: 24, height: 24, 
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                            )
                          : const Icon(Icons.gps_fixed, color: Colors.white),
              ),
            ),
          ],
        ),
            ),
            FloatingActionButton.extended(
              onPressed: _startDistanceMeasurement,
              icon: const Icon(Icons.straighten),
              label: const Text('開始測量'),
              backgroundColor: Colors.orange,
            ),
          ],
        ],
      );
    } else if (_step == 1) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          FloatingActionButton(
            onPressed: () => setState(() {
              _step = 0;
              _referenceRect = null;
            }),
            backgroundColor: Colors.grey,
            child: const Icon(Icons.arrow_back),
          ),
          if (_referenceRect != null)
            FloatingActionButton.extended(
              onPressed: _calculateScaleAndProceed,
              icon: const Icon(Icons.check),
              label: const Text('確認參照物'),
              backgroundColor: Colors.green,
            ),
        ],
      );
    } else if (_step == 2) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
          FloatingActionButton(
            onPressed: () => setState(() => _step = _useDistanceMode ? 0 : 1),
            backgroundColor: Colors.grey,
            child: const Icon(Icons.arrow_back),
          ),
          FloatingActionButton.extended(
            onPressed: _measureAndFinish,
            icon: const Icon(Icons.camera),
            label: const Text('完成測量'),
            backgroundColor: Colors.blue,
          ),
        ],
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
          FloatingActionButton.extended(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.refresh),
            label: const Text('重測'),
            backgroundColor: Colors.orange,
          ),
          FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).pop(_currentResult),
            icon: const Icon(Icons.check),
            label: const Text('使用此結果'),
            backgroundColor: Colors.green,
          ),
        ],
      );
    }
  }
  
  Widget _buildModeButton(String text, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
              child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
                ),
                  child: Text(
          text,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    if (_step == 1) {
        setState(() {
        _dragStart = details.localPosition;
        _dragCurrent = details.localPosition;
        _referenceRect = null;
      });
    }
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_step == 1) {
    setState(() {
        _dragCurrent = details.localPosition;
        if (_dragStart != null) {
          _referenceRect = Rect.fromPoints(_dragStart!, _dragCurrent!);
        }
      });
    } else if (_step == 2) {
      if (_measureLineStart == null) {
         final center = details.localPosition;
         _measureLineStart = center - const Offset(50, 0);
         _measureLineEnd = center + const Offset(50, 0);
      }
      
      setState(() {
        _virtualLineY = details.localPosition.dy;
        if (_measureLineStart != null && _measureLineEnd != null) {
           double width = (_measureLineEnd!.dx - _measureLineStart!.dx).abs();
           double centerX = details.localPosition.dx;
           _measureLineStart = Offset(centerX - width/2, _virtualLineY!);
           _measureLineEnd = Offset(centerX + width/2, _virtualLineY!);
        }
      });
    }
  }
  
  void _handlePanEnd(DragEndDetails details) {
    if (_step == 1) {
    setState(() {
        _dragStart = null;
        _dragCurrent = null;
      });
    }
  }

  void _startDistanceMeasurement() {
    double? dist = double.tryParse(_distanceController.text);
    if (dist == null || dist <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請輸入有效距離')));
      return;
    }
    
    double centerX = MediaQuery.of(context).size.width / 2;
    double centerY = MediaQuery.of(context).size.height / 2;
    
    _measureLineStart = Offset(centerX - 100, centerY);
    _measureLineEnd = Offset(centerX + 100, centerY);
    _virtualLineY = centerY;
    
    setState(() {
      _step = 2;
    });
  }

  void _calculateScaleAndProceed() {
    if (_referenceRect == null) return;

    double refPixelHeight = _referenceRect!.height;
    double realHeight = _selectedReference.heightCm;
    _pixelsPerCm = refPixelHeight / realHeight;

    double offsetPixels = 130.0 * _pixelsPerCm!;
    _virtualLineY = _referenceRect!.bottom - offsetPixels;

    double initialWidthPixels = 30.0 * _pixelsPerCm!;
    double centerX = MediaQuery.of(context).size.width / 2;
    _measureLineStart = Offset(centerX - initialWidthPixels / 2, _virtualLineY!);
    _measureLineEnd = Offset(centerX + initialWidthPixels / 2, _virtualLineY!);

    setState(() {
      _step = 2;
    });
  }

  void _measureAndFinish() {
    if (_measureLineStart == null || _measureLineEnd == null) return;

    double diameterCm = 0;
    String methodNote = '';

    if (_useDistanceMode) {
      double distanceM = double.tryParse(_distanceController.text) ?? 1.5;
      double pixelWidth = (_measureLineEnd!.dx - _measureLineStart!.dx).abs();
      double screenWidth = MediaQuery.of(context).size.width;
      
      // 經驗法則焦距
      double focalLengthPx = screenWidth * 4.0;
      
      double diameterM = (pixelWidth * distanceM) / focalLengthPx;
      diameterCm = diameterM * 100;
      methodNote = '距離模式: ${distanceM}m (GPS/輸入)';
      
    } else {
      if (_pixelsPerCm == null) return;
      double pixelWidth = (_measureLineEnd!.dx - _measureLineStart!.dx).abs();
      diameterCm = pixelWidth / _pixelsPerCm!;
      methodNote = '參照物: ${_selectedReference.nameZh}';
    }

    setState(() {
      _currentResult = MeasurementResult(
        diameterCm: diameterCm,
        confidenceScore: _useDistanceMode ? 0.6 : 0.85,
        method: _useDistanceMode ? MeasurementMethod.twoPoint : MeasurementMethod.reference,
        points: [],
        notes: methodNote,
      );
      _step = 3;
    });
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('如何使用'),
        content: Text(
          _useDistanceMode
          ? '1. 點擊 GPS 按鈕自動計算距離 (需有樹木座標)\n'
            '2. 或手動輸入距離。\n'
            '3. 螢幕會出現黃色測量線。\n'
            '4. 對準樹幹胸高位置 (1.3m) 並調整寬度。'
          : '1. 將標準參照物（如信用卡）放在樹根地面。\n'
            '2. 用手指框選畫面中的參照物。\n'
            '3. 系統會自動畫出一條綠線，代表離地 1.3m 的位置。\n'
            '4. 調整綠線使其切過樹幹，並拉動綠線兩端來測量直徑。'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('了解')),
        ],
      ),
    );
  }
}

class _AROverlayPainter extends CustomPainter {
  final int step;
  final Rect? referenceRect;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final double? virtualLineY;
  final Offset? measureLineStart;
  final Offset? measureLineEnd;
  final double? pixelsPerCm;
  final bool useDistanceMode;

  _AROverlayPainter({
    required this.step,
    this.referenceRect,
    this.dragStart,
    this.dragCurrent,
    this.virtualLineY,
    this.measureLineStart,
    this.measureLineEnd,
    this.pixelsPerCm,
    this.useDistanceMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (step == 1 && !useDistanceMode) {
      final Paint borderPaint = Paint()
        ..color = Colors.tealAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final Paint fillPaint = Paint()
        ..color = Colors.teal.withOpacity(0.2)
        ..style = PaintingStyle.fill;

      Rect? rectToDraw = referenceRect;
      
      if (dragStart != null && dragCurrent != null) {
        rectToDraw = Rect.fromPoints(dragStart!, dragCurrent!);
      }

      if (rectToDraw != null) {
        canvas.drawRect(rectToDraw, fillPaint);
        canvas.drawRect(rectToDraw, borderPaint);
        _drawText(canvas, '參照物', rectToDraw.topCenter - const Offset(0, 20), Colors.tealAccent);
      }
    }

    if (step == 2 && virtualLineY != null) {
      if (!useDistanceMode) {
        final Paint guidePaint = Paint()
          ..color = Colors.green.withOpacity(0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
        
        double dashWidth = 5, dashSpace = 5, startX = 0;
        while (startX < size.width) {
          canvas.drawLine(Offset(startX, virtualLineY!), Offset(startX + dashWidth, virtualLineY!), guidePaint);
          startX += dashWidth + dashSpace;
        }
        _drawText(canvas, '1.3m 高度', Offset(size.width - 60, virtualLineY! - 15), Colors.green);
        
        if (referenceRect != null) {
          canvas.drawRect(referenceRect!, Paint()..color = Colors.white.withOpacity(0.1)..style = PaintingStyle.stroke);
          canvas.drawLine(
            referenceRect!.topCenter,
            Offset(referenceRect!.center.dx, virtualLineY!),
            Paint()..color = Colors.white.withOpacity(0.3)..style = PaintingStyle.stroke..strokeWidth = 1.0
          );
        }
      } else {
        canvas.drawLine(
          Offset(0, virtualLineY!), 
          Offset(size.width, virtualLineY!), 
          Paint()..color = Colors.white24..strokeWidth = 1.0
        );
      }

      if (measureLineStart != null && measureLineEnd != null) {
        final Paint measurePaint = Paint()
          ..color = Colors.yellow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(measureLineStart!, measureLineEnd!, measurePaint);
        canvas.drawCircle(measureLineStart!, 8.0, Paint()..color = Colors.yellow);
        canvas.drawCircle(measureLineEnd!, 8.0, Paint()..color = Colors.yellow);

        if (!useDistanceMode && pixelsPerCm != null) {
          double widthPx = (measureLineEnd!.dx - measureLineStart!.dx).abs();
          double widthCm = widthPx / pixelsPerCm!;
          _drawText(
            canvas, 
            '${widthCm.toStringAsFixed(1)} cm', 
            Offset((measureLineStart!.dx + measureLineEnd!.dx)/2, virtualLineY! - 30), 
            Colors.yellow,
            fontSize: 24,
                              fontWeight: FontWeight.bold,
          );
        }
      }
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, Color color, 
      {double fontSize = 14, FontWeight fontWeight = FontWeight.normal}) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight, shadows: [
        const Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
      ]),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, position - Offset(textPainter.width / 2, 0));
  }
  
  @override
  bool shouldRepaint(covariant _AROverlayPainter oldDelegate) {
    return oldDelegate.step != step ||
           oldDelegate.dragCurrent != dragCurrent ||
           oldDelegate.virtualLineY != virtualLineY ||
           oldDelegate.measureLineStart != measureLineStart ||
           oldDelegate.useDistanceMode != useDistanceMode;
  }
}
