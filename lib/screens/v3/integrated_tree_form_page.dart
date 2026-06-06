import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:exif/exif.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/pending_tree_measurement.dart';
import '../../services/pending_measurement_service.dart';
import '../../services/species_identification_service.dart';
import '../../services/species_service.dart';
import '../../services/pure_vision_dbh_service.dart';
import '../../services/tflite_tracking_service.dart';
import '../../services/v3/tree_image_service.dart';
import '../../services/v3/project_boundary_coordinator.dart';
import '../../services/v3/ml_data_collector.dart';
import '../../services/carbon_calculation_service.dart';
import '../../utils/carbon_display.dart';
import '../../services/dbh_measurement_engine.dart';
import '../../services/camera_capture_service.dart';
import '../../services/ar_measurement_service.dart';
import '../../models/camera_capture_mode.dart';
import '../../services/locale_service.dart';
import '../../widgets/tree_measurement_history_panel.dart';
import '../../widgets/conflict_resolution_dialog.dart';
import '../../config/survey_settings.dart';

/// V3 整合式樹木測量表單
///
/// 整合了：
/// 1. 照片拍攝與管理
/// 2. 影像 DBH 測量
/// 3. AI 樹種辨識
/// 4. 待測量任務資料確認與提交
class IntegratedTreeFormPage extends StatefulWidget {
  final PendingTreeMeasurement task;

  /// 提交成功後自動將此 session 內「已完成」筆數轉入 tree_survey（現場連線用）
  final bool autoTransferToTreeSurvey;

  /// 與 [autoTransferToTreeSurvey] 搭配；未提供則用 [task.sessionId]
  final String? transferSessionId;

  /// 碳匯手冊合規：DBH 僅接受現場人工量測。null 時依 [SurveySettings]。
  final bool? handbookCompliantMode;

  const IntegratedTreeFormPage({
    super.key,
    required this.task,
    this.autoTransferToTreeSurvey = false,
    this.transferSessionId,
    this.handbookCompliantMode,
  });

  @override
  State<IntegratedTreeFormPage> createState() => _IntegratedTreeFormPageState();
}

class _IntegratedTreeFormPageState extends State<IntegratedTreeFormPage> {
  final PendingMeasurementService _pendingService = PendingMeasurementService();
  /// 樂觀鎖基準（進入表單時向伺服器刷新，避免 in_progress PATCH 造成假 409）
  DateTime? _lockUpdatedAt;
  final TreeImageService _imageService = TreeImageService();
  final TreeSpeciesService _speciesService = TreeSpeciesService();
  final TfliteObjectTrackingService _tfliteTracker =
      TfliteObjectTrackingService();

  // 表單控制器
  final TextEditingController _dbhController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _speciesController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  // 狀態
  String _selectedStatus = '正常';
  final List<String> _statusOptions = [
    '正常',
    '枯死',
    '病蟲害',
    '傾斜',
    '斷梢',
    '空洞',
    '其他'
  ];

  bool _isLoading = false;
  bool _isAutoPilotRunning = false;
  File? _mainImage;
  String? _speciesConfidence;

  // [Phase 0.5] 手機 GPS 定位
  double? _phoneToTreeDistance;
  double? _gpsAccuracyM;
  String _distanceSource = 'none'; // 'gps', 'instrument', 'none'

  // 樹種資料
  List<Map<String, dynamic>> _allSpecies = [];
  List<Map<String, dynamic>> _speciesSearchResults = [];
  String? _speciesId;

  // 測量結果暫存
  double? _measuredDbh;
  double? _measurementConfidence;
  String? _measurementMethod;

  /// 使用者選定的 DBH 來源：remote_diameter / vision / manual
  String? _activeDbhSource;
  double? _storedVisionDbhCm;
  double? _storedVisionConfidence;
  String? _storedVisionMethod;
  bool _programmaticDbhChange = false;
  List<String> _visionNotes = const [];
  DbhHardwareCapabilities? _deviceCaps;

  void _logDbh(String message) {
    debugPrint('[DBH] $message');
  }

  // AI 辨識暫存
  String? _autoIdentifiedSpeciesName;
  String? _autoIdentifiedSpeciesId;
  List<Map<String, dynamic>>? _aiPredictions;

  // [Phase 1] AutoPilot 進度
  String _autoPilotStatus = '';
  bool _dbhReady = false;
  bool _speciesReady = false;
  double? _previewCarbonKg;

  // Multi-shot: stored images for precision boost
  final List<File> _capturedImages = [];
  Map<String, dynamic> _lastExif = {};
  bool _showMultiShotHint = false;
  Timer? _speciesSearchDebounce;

  bool get _handbook =>
      widget.handbookCompliantMode ?? SurveySettings.instance.handbookCompliantMode;

  @override
  void initState() {
    super.initState();
    _preferredCaptureMode = _handbook
        ? CameraCaptureMode.plainPhoto
        : CameraCaptureMode.integrated;
    if (_handbook) _activeDbhSource = 'manual';
    _lockUpdatedAt = widget.task.updatedAt;
    _refreshLockBaseline();
    _initializeForm();
    _loadDbhCapabilities();
    _dbhController.addListener(_onDbhFieldEdited);
    _dbhController.addListener(_updateCarbonPreview);
    _heightController.addListener(_updateCarbonPreview);
    _speciesController.addListener(_updateCarbonPreview);
    _updateCarbonPreview();
    _loadSpecies();
    _acquirePhoneGps();
  }

  Future<void> _refreshLockBaseline() async {
    final id = widget.task.id;
    if (id == null) return;
    final fresh = await _pendingService.fetchTaskById(id);
    if (!mounted || fresh?.updatedAt == null) return;
    setState(() => _lockUpdatedAt = fresh!.updatedAt);
  }

  String? _lockIsoString() =>
      _lockUpdatedAt?.toUtc().toIso8601String();

  void _updateCarbonPreview() {
    final dbh = double.tryParse(_dbhController.text) ?? 0;
    final h = double.tryParse(_heightController.text) ?? widget.task.treeHeight;
    final species = _speciesController.text.trim();
    if (dbh <= 0 || h <= 0 || species.isEmpty) {
      if (_previewCarbonKg != null) setState(() => _previewCarbonKg = null);
      return;
    }
    final v = CarbonCalculationService.calculateCarbonStorage(species, h, dbh);
    if (_previewCarbonKg != v) setState(() => _previewCarbonKg = v);
  }

  /// 取得手機 GPS 位置，提供現場位置提示；DBH 量測距離由 ML 深度模型決定。
  ///
  /// 三層保護機制：
  /// 1. 無 GPS 座標（treeLat/Lon=0）→ 顯示儀器 HD 作為現場距離提示
  /// 2. GPS 精度太差（accuracy > 20m）→ 顯示儀器 HD 作為現場距離提示
  /// 3. GPS 距離與儀器 HD 差距 > 100% → 警告並顯示儀器 HD
  Future<void> _acquirePhoneGps() async {
    final instrumentHD = widget.task.horizontalDistance;

    // 保護 1: 無樹木 GPS 座標時，顯示儀器 HD 作為現場距離提示
    if (widget.task.treeLatitude == 0 && widget.task.treeLongitude == 0) {
      debugPrint('[GPS] 樹木無 GPS 座標，顯示儀器 HD=${instrumentHD}m');
      setState(() {
        _phoneToTreeDistance = instrumentHD;
        _distanceSource = 'instrument';
      });
      return;
    }

    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        debugPrint('[GPS] Permission permanently denied');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('定位權限被永久拒絕，請到設定中開啟'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: '開啟設定',
                textColor: Colors.white,
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
        return;
      }
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint('[GPS] Permission denied after request');
          setState(() {
            _phoneToTreeDistance = instrumentHD;
            _distanceSource = 'instrument';
          });
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      _gpsAccuracyM = position.accuracy;

      // 保護 2: GPS 精度太差，顯示儀器 HD 作為現場距離提示
      if (position.accuracy > 20) {
        debugPrint(
            '[GPS] 精度太差 (${position.accuracy.toStringAsFixed(0)}m)，顯示儀器 HD');
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'GPS 精度不足 (±${position.accuracy.toStringAsFixed(0)}m)，顯示儀器距離提示 ${instrumentHD.toStringAsFixed(1)}m'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final gpsDist = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        widget.task.treeLatitude,
        widget.task.treeLongitude,
      );

      // 保護 3: GPS 與儀器 HD 嚴重不一致（差距 > 100%）
      if (instrumentHD <= 0) {
        debugPrint(
            '[GPS] instrumentHD<=0, using GPS distance directly: ${gpsDist.toStringAsFixed(1)}m');
        setState(() {
          _phoneToTreeDistance = gpsDist;
          _distanceSource = 'gps';
        });
        return;
      }
      final deviation = (gpsDist - instrumentHD).abs();
      final deviationPct = deviation / instrumentHD;

      if (deviationPct > 1.0) {
        debugPrint(
            '[GPS] GPS(${gpsDist.toStringAsFixed(1)}m) 與儀器HD(${instrumentHD.toStringAsFixed(1)}m) 差距 ${(deviationPct * 100).toStringAsFixed(0)}%，顯示儀器 HD');
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'GPS 距離 (${gpsDist.toStringAsFixed(0)}m) 與儀器 (${instrumentHD.toStringAsFixed(1)}m) 差異過大，顯示儀器距離提示'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      // GPS 品質合格，顯示 GPS 距離提示
      setState(() {
        _phoneToTreeDistance = gpsDist;
        _distanceSource = 'gps';
      });

      if (gpsDist > 15 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('距離目標樹木約 ${gpsDist.toStringAsFixed(0)}m，請確認是否在正確位置'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('[GPS] 定位失敗: $e — 顯示儀器 HD');
      if (mounted) {
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('GPS 不可用，顯示儀器距離提示 ${instrumentHD.toStringAsFixed(1)}m'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _loadSpecies() async {
    try {
      // 優先載入增強版列表（含同義詞）
      final species = await _speciesService.getEnhancedSpecies();
      if (mounted) {
        setState(() {
          _allSpecies = species;
        });
      }
    } catch (e) {
      debugPrint('載入樹種失敗: $e');
    }
  }

  Future<void> _loadDbhCapabilities() async {
    _deviceCaps = await DbhCapabilityService.instance.ensureLoaded();
  }

  void _initializeForm() {
    _heightController.text = widget.task.treeHeight.toStringAsFixed(1);
    if (!_handbook && widget.task.hasInstrumentDbh) {
      _activeDbhSource = 'remote_diameter';
      _applyDbhFromSource(silent: true);
      _logDbh(
        'init task=${widget.task.id} instrumentDbh='
        '${widget.task.instrumentDbhCm!.toStringAsFixed(1)} cm '
        '(VLGEO2 Remote Dia, height=user-aimed, not fixed 1.3m)',
      );
    } else if (widget.task.dbhCm != null && widget.task.dbhCm! > 0) {
      _dbhController.text = widget.task.dbhCm!.toStringAsFixed(1);
    }
    if (widget.task.speciesName != null) {
      _speciesController.text = widget.task.speciesName!;
    }
  }

  void _onDbhFieldEdited() {
    if (_programmaticDbhChange) return;
    final parsed = double.tryParse(_dbhController.text.trim());
    if (parsed == null) return;

    final inst = widget.task.instrumentDbhCm;
    if (_activeDbhSource == 'remote_diameter' &&
        inst != null &&
        (parsed - inst).abs() < 0.05) {
      return;
    }
    if (_activeDbhSource == 'vision' &&
        _storedVisionDbhCm != null &&
        (parsed - _storedVisionDbhCm!).abs() < 0.05) {
      return;
    }
    if (_activeDbhSource != 'manual') {
      setState(() => _activeDbhSource = 'manual');
    }
  }

  void _selectDbhSource(String source) {
    if (source == 'vision' && _storedVisionDbhCm == null) return;
    if (source == 'remote_diameter' && !widget.task.hasInstrumentDbh) return;
    _logDbh(
      'select source=$source '
      '(instrument=${widget.task.instrumentDbhCm}, '
      'vision=$_storedVisionDbhCm, manual=${_dbhController.text})',
    );
    setState(() {
      _activeDbhSource = source;
      if (source != 'manual') {
        _applyDbhFromSource(silent: true);
      }
    });
  }

  void _applyDbhFromSource({bool silent = false}) {
    double? value;
    switch (_activeDbhSource) {
      case 'remote_diameter':
        value = widget.task.instrumentDbhCm;
        _measurementMethod = 'remote_diameter';
        _measurementConfidence = 1.0;
        _dbhReady = value != null && value > 0;
        break;
      case 'vision':
        value = _storedVisionDbhCm;
        _measurementMethod = _storedVisionMethod ?? 'autopilot_vision';
        _measurementConfidence = _storedVisionConfidence;
        _dbhReady = (_storedVisionConfidence ?? 0) >= 0.6;
        break;
      default:
        return;
    }
    if (value == null || value <= 0) return;
    _programmaticDbhChange = true;
    _dbhController.text = value.toStringAsFixed(1);
    _programmaticDbhChange = false;
    if (!silent && mounted) setState(() {});
  }

  Future<void> _promptDbhSourceAfterVision({
    required double visionDbhCm,
    required double? confidence,
    required String method,
    required File image,
    Map<String, dynamic>? exif,
    int? measurementRow,
    int? imageHeight,
    double? trunkDepthM,
    List<String>? notes,
  }) async {
    if (_handbook) {
      if (!mounted) return;
      setState(() {
        _mainImage = image;
        if (exif != null) _lastExif = exif;
        if (!_capturedImages.contains(image)) _capturedImages.add(image);
      });
      return;
    }
    _storedVisionDbhCm = visionDbhCm;
    _storedVisionConfidence = confidence;
    _storedVisionMethod = method;
    _measuredDbh = visionDbhCm;
    _visionNotes = notes ?? const [];

    _logDbh(
      'vision dbh=${visionDbhCm.toStringAsFixed(1)} cm '
      'conf=${confidence != null ? (confidence * 100).toStringAsFixed(0) : "?"}% '
      'method=$method '
      'row=$measurementRow/${imageHeight ?? "?"} '
      'trunkDepth=${trunkDepthM?.toStringAsFixed(2) ?? "?"} m',
    );
    _logDbh(
      'vision height note: measures at YOLO bbox center row in photo, '
      'NOT ground-referenced 1.3 m breast height (1.3m RANSAC = roadmap)',
    );
    if (_visionNotes.isNotEmpty) {
      _logDbh('vision notes: ${_visionNotes.join("; ")}');
    }

    if (!widget.task.hasInstrumentDbh) {
      if (!mounted) return;
      setState(() {
        _activeDbhSource = 'vision';
        _mainImage = image;
        if (exif != null) _lastExif = exif;
        _capturedImages.add(image);
        _applyDbhFromSource(silent: true);
      });
      return;
    }

    final inst = widget.task.instrumentDbhCm!;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DBH 來源選擇'),
        content: Text(
          '此樹已有儀器 Remote Diameter：${inst.toStringAsFixed(1)} cm\n'
          '影像 AutoPilot 量得：${visionDbhCm.toStringAsFixed(1)} cm'
          '${confidence != null ? '（信心 ${(confidence * 100).toStringAsFixed(0)}%）' : ''}\n\n'
          'Remote Diameter 與標準胸高（1.3 m）位置可能不同。\n'
          '影像 DBH 量的是照片中樹幹偵測框中心高度，亦未對準 1.3 m。\n\n'
          '請選擇要採用的 DBH 來源。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'instrument'),
            child: Text('採用儀器 ${inst.toStringAsFixed(1)} cm'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'vision'),
            child: Text('改用影像 ${visionDbhCm.toStringAsFixed(1)} cm'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('稍後再決定'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    setState(() {
      _mainImage = image;
      if (exif != null) _lastExif = exif;
      if (!_capturedImages.contains(image)) {
        _capturedImages.add(image);
      }
      if (choice == 'vision') {
        _activeDbhSource = 'vision';
        _applyDbhFromSource(silent: true);
        _logDbh('user chose vision ${visionDbhCm.toStringAsFixed(1)} cm');
      } else if (choice == 'instrument') {
        _activeDbhSource = 'remote_diameter';
        _applyDbhFromSource(silent: true);
        _logDbh('user chose instrument ${inst.toStringAsFixed(1)} cm');
      } else {
        _logDbh('user deferred choice; vision stored as optional chip');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '影像 DBH ${visionDbhCm.toStringAsFixed(1)} cm 已備選，'
              '可在下方「DBH 來源」切換',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  String _dbhSourceLabel(String source) {
    switch (source) {
      case 'remote_diameter':
        return '儀器 Remote Dia';
      case 'vision':
        return '影像 DBH';
      case 'manual':
        return '手動輸入';
      default:
        return '未指定';
    }
  }

  String _resolveSubmitMethod() {
    if (_handbook) return DbhEngine.manual.defaultMeasurementMethod;
    final engine = DbhEngineResolver.fromFormSource(_activeDbhSource);
    if (engine == DbhEngine.visionMono &&
        _storedVisionMethod != null &&
        _storedVisionMethod!.isNotEmpty) {
      return _storedVisionMethod!;
    }
    return engine.defaultMeasurementMethod;
  }

  double _resolveSubmitConfidence() {
    if (_handbook) return 1.0;
    final engine = DbhEngineResolver.fromFormSource(_activeDbhSource);
    switch (engine) {
      case DbhEngine.instrumentRemote:
        return 1.0;
      case DbhEngine.visionMono:
        return _storedVisionConfidence ?? _measurementConfidence ?? 0.8;
      case DbhEngine.xiangLidar:
        return _storedVisionConfidence ?? _measurementConfidence ?? 0.9;
      case DbhEngine.manual:
        return _measurementConfidence ?? 1.0;
    }
  }

  @override
  void dispose() {
    // 同步清理暫存照片（不使用 await，因 dispose 不能 async）
    _cleanupTempImages();
    _tfliteTracker.dispose();
    _speciesSearchDebounce?.cancel();
    _dbhController.removeListener(_onDbhFieldEdited);
    _dbhController.removeListener(_updateCarbonPreview);
    _heightController.removeListener(_updateCarbonPreview);
    _speciesController.removeListener(_updateCarbonPreview);
    _dbhController.dispose();
    _heightController.dispose();
    _speciesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// 手冊模式：單純拍照；研究模式：整合拍照（DBH + 樹種）
  late CameraCaptureMode _preferredCaptureMode;

  Future<void> _showCaptureModeSheet({ImageSource source = ImageSource.camera}) async {
    final mode = await showModalBottomSheet<CameraCaptureMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ctx.tr('capture_mode_title'),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            for (final m in _handbook
                ? [
                    CameraCaptureMode.plainPhoto,
                    CameraCaptureMode.photoWithSpecies,
                  ]
                : CameraCaptureMode.values)
              ListTile(
                leading: Icon(_iconForCaptureMode(m)),
                title: Text(ctx.tr(m.titleKey)),
                subtitle: Text(ctx.tr(m.subtitleKey)),
                onTap: () => Navigator.pop(ctx, m),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode != null) {
      setState(() => _preferredCaptureMode = mode);
      await _captureWithMode(mode, source: source);
    }
  }

  IconData _iconForCaptureMode(CameraCaptureMode m) {
    switch (m) {
      case CameraCaptureMode.plainPhoto:
        return Icons.photo_camera_outlined;
      case CameraCaptureMode.integrated:
        return Icons.center_focus_strong;
      case CameraCaptureMode.photoWithSpecies:
        return Icons.eco_outlined;
    }
  }

  Future<void> _importPhoto() =>
      _showCaptureModeSheet(source: ImageSource.gallery);

  Future<void> _captureWithMode(
    CameraCaptureMode mode, {
    ImageSource source = ImageSource.camera,
  }) async {
    try {
      final initialDbh = double.tryParse(_dbhController.text);
      final result = await CameraCaptureService.capture(
        context,
        mode: mode,
        source: source,
        initialDbh: initialDbh,
        speciesName: _speciesController.text.trim().isEmpty
            ? null
            : _speciesController.text.trim(),
      );
      if (result == null || !mounted) return;

      _cleanupTempImages();
      setState(() {
        _mainImage = result.imageFile;
        _capturedImages.clear();
        _showMultiShotHint = false;
        _dbhReady = false;
        _speciesReady = false;
      });

      switch (mode) {
        case CameraCaptureMode.plainPhoto:
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已儲存照片（未自動分析）')),
            );
          }
          break;
        case CameraCaptureMode.integrated:
          if (_handbook) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(context.tr('handbook_photo_hint'))),
              );
            }
            break;
          }
          if (result.measurement != null) {
            await _applyScannerMeasurement(result.measurement!);
            if (mounted &&
                _speciesController.text.trim().isEmpty) {
              setState(() {
                _isAutoPilotRunning = true;
                _autoPilotStatus = '樹種辨識中...';
              });
              await _identifySpecies(result.imageFile);
              if (mounted) {
                setState(() {
                  _isAutoPilotRunning = false;
                  _autoPilotStatus = _speciesReady ? '分析完成' : '樹種需確認';
                });
              }
            }
          } else {
            await _runAutoPilot(result.imageFile);
          }
          break;
        case CameraCaptureMode.photoWithSpecies:
          setState(() {
            _isAutoPilotRunning = true;
            _autoPilotStatus = '樹種辨識中...';
          });
          await _identifySpecies(result.imageFile);
          if (mounted) {
            setState(() {
              _isAutoPilotRunning = false;
              _autoPilotStatus = _speciesReady ? '樹種已辨識' : '樹種需確認';
            });
          }
          break;
      }
    } catch (e) {
      _showError('拍照失敗: $e');
    }
  }

  Future<void> _applyScannerMeasurement(MeasurementResult m) async {
    if (!mounted) return;
    if (_handbook) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('handbook_photo_hint'))),
        );
      }
      return;
    }
    setState(() {
      _measuredDbh = m.diameterCm;
      _measurementConfidence = m.confidenceScore;
      _measurementMethod = m.method.name;
      _storedVisionDbhCm = m.diameterCm;
      _storedVisionMethod = m.method.name;
      _dbhController.text = m.diameterCm.toStringAsFixed(1);
      _activeDbhSource = 'vision';
      _storedVisionConfidence = m.confidenceScore;
      _dbhReady = true;
    });
    _logDbh(
      'scanner integrated capture dbh=${m.diameterCm} '
      'bbox=${m.trunkBboxNormalized}',
    );
    _updateCarbonPreview();
  }

  /// 清理先前拍攝的暫存照片，釋放儲存空間
  void _cleanupTempImages() {
    for (final img in _capturedImages) {
      try {
        if (img.existsSync() && img.path != _mainImage?.path) {
          img.deleteSync();
        }
      } catch (_) {}
    }
  }

  /// [Phase 1] AutoPilot 一鍵量測
  /// 同時觸發 DBH 測量和樹種辨識（並行），自動填入結果
  Future<void> _runAutoPilot(File image) async {
    if (_isAutoPilotRunning) return;
    setState(() {
      _isAutoPilotRunning = true;
      _autoPilotStatus = 'AI 分析中...';
      _dbhReady = false;
      _speciesReady = false;
    });

    if (_handbook) {
      await _identifySpecies(image);
    } else {
      await Future.wait([
        _autoMeasureDbh(image),
        _identifySpecies(image),
      ]);
    }

    if (mounted) {
      setState(() {
        _isAutoPilotRunning = false;
        _autoPilotStatus = _dbhReady && _speciesReady
            ? '分析完成'
            : _dbhReady
                ? '樹種辨識需確認'
                : _speciesReady
                    ? 'DBH 需確認'
                    : '需手動確認';
      });
    }
  }

  /// Extract EXIF focal length and phone info from image file
  Future<Map<String, dynamic>> _extractExif(File imageFile) async {
    final exifInfo = <String, dynamic>{};
    try {
      final bytes = await imageFile.readAsBytes();
      final exifData = await readExifFromBytes(bytes);

      final focalTag = exifData['EXIF FocalLength'];
      if (focalTag != null) {
        final ratio = focalTag.values;
        if (ratio is IfdRatios && ratio.ratios.isNotEmpty) {
          final r = ratio.ratios.first;
          exifInfo['focalMm'] = r.denominator != 0
              ? r.numerator.toDouble() / r.denominator.toDouble()
              : null;
        } else {
          exifInfo['focalMm'] =
              double.tryParse(focalTag.printable.replaceAll(' ', ''));
        }
      }

      final focal35Tag = exifData['EXIF FocalLengthIn35mmFilm'];
      if (focal35Tag != null) {
        exifInfo['focal35'] =
            double.tryParse(focal35Tag.printable.replaceAll(' ', ''));
      }

      final makeTag = exifData['Image Make'];
      if (makeTag != null) exifInfo['make'] = makeTag.printable.trim();

      final modelTag = exifData['Image Model'];
      if (modelTag != null) exifInfo['model'] = modelTag.printable.trim();

      debugPrint('[EXIF] $exifInfo');
    } catch (e) {
      debugPrint('[EXIF] Read failed: $e');
    }
    return exifInfo;
  }

  /// 自動 DBH 量測（附帶 EXIF 焦距提取）
  Future<void> _autoMeasureDbh(File image) async {
    if (_handbook) return;
    try {
      if (mounted) setState(() => _autoPilotStatus = '深度估計中...');

      final service = PureVisionDbhService();
      final available = await service.isServiceAvailable();
      if (!available) {
        debugPrint('[AutoPilot] ML Service 不可用，跳過自動 DBH');
        if (mounted) {
          setState(() => _autoPilotStatus = 'ML 服務無法連線');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ML 量測服務無法連線，DBH 需手動輸入\n'
                  '請重新登入或確認手機可連到 ML 位址'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Extract EXIF for better focal length accuracy
      final exif = await _extractExif(image);

      if (!mounted) return;
      setState(() => _autoPilotStatus = '手機偵測樹幹中...');

      final localBbox = await _detectTrunkBbox(image);

      if (!mounted) return;
      setState(() => _autoPilotStatus =
          localBbox != null ? '後端遮罩與深度估計中...' : '後端偵測樹幹中...');

      final caps =
          _deviceCaps ?? await DbhCapabilityService.instance.ensureLoaded();
      _deviceCaps = caps;
      final routing = DbhEngineResolver.resolveForAutoMeasure(
        hardware: caps,
        // TODO(Xiang): ARKit Scene Depth 采集後設 hasLidarDepthFrame=true
        hasLidarDepthFrame: false,
        xiangPreflightOk: false,
      );
      _logDbh('autoMeasure routing: ${routing.summary}');

      if (routing.apiEngine == DbhEngine.xiangLidar) {
        // TODO(Xiang): PureVisionDbhService.measureDbhXiang(...) when backend ready
        _logDbh('xiang API selected but not wired — should not happen yet');
      }

      final result = await service.autoMeasureDbh(
        imageFile: image,
        focalLengthMm: exif['focalMm'] as double?,
        focalLength35mm: exif['focal35'] as double?,
        phoneMake: exif['make'] as String?,
        phoneModel: exif['model'] as String?,
        localBbox: localBbox,
        useServerYoloMask: true,
      );

      if (result.success && result.dbhCm != null && mounted) {
        final conf = result.confidence ?? 0;
        await _promptDbhSourceAfterVision(
          visionDbhCm: result.dbhCm!,
          confidence: conf,
          method: result.method ?? 'autopilot_vision',
          image: image,
          exif: exif,
          measurementRow: result.measurementRow,
          trunkDepthM: result.trunkDepthM,
          notes: result.notes,
        );
        _logDbh('detected_bbox=${result.detectedBbox} fovRatio=${result.fovRatio}');
        _logDbh('autoMeasure api=visionMono dbh=${result.dbhCm} row=${result.measurementRow}');
        if (mounted) {
          setState(() {
            _showMultiShotHint = conf < 0.7 && _capturedImages.length < 3;
          });
        }
      }
    } catch (e) {
      debugPrint('[AutoPilot] DBH 自動量測失敗: $e');
      if (mounted) {
        setState(() => _autoPilotStatus = 'DBH 量測失敗');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DBH 自動量測失敗，請重拍或手動輸入'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<Rect?> _detectTrunkBbox(File image) async {
    try {
      if (!_tfliteTracker.isInitialized) {
        await _tfliteTracker.initialize();
      }
      if (!_tfliteTracker.isInitialized) {
        debugPrint('[AutoPilot] TFLite bbox 初始化失敗，改由後端偵測');
        return null;
      }

      final detections = await _tfliteTracker.processImageFile(image);
      if (detections.isEmpty) {
        debugPrint('[AutoPilot] 靜態照片未偵測到 bbox，改由後端偵測');
        return null;
      }

      final best = detections.first;
      debugPrint('[AutoPilot] 靜態照片 bbox=${best.rect} '
          'conf=${best.confidence.toStringAsFixed(3)}');
      return best.rect;
    } catch (e, st) {
      debugPrint('[AutoPilot] 靜態 bbox 偵測失敗: $e');
      debugPrint('[AutoPilot] 靜態 bbox stack: $st');
      return null;
    }
  }

  Future<void> _takeMultiShotPhoto() async {
    if (_isAutoPilotRunning) return;
    if (_capturedImages.length >= 5) {
      _showError('最多拍攝 5 張照片');
      return;
    }
    try {
      final File? image = await _imageService.captureImage();
      if (image == null) return;

      setState(() {
        _isAutoPilotRunning = true;
        _autoPilotStatus = '多照片融合分析中...';
        _showMultiShotHint = false;
      });

      _capturedImages.add(image);

      final service = PureVisionDbhService();
      final imagesCopy = List<File>.from(_capturedImages);
      final result = await service.autoMeasureDbhMulti(
        imageFiles: imagesCopy,
        focalLengthMm: _lastExif['focalMm'] as double?,
        focalLength35mm: _lastExif['focal35'] as double?,
        phoneMake: _lastExif['make'] as String?,
        phoneModel: _lastExif['model'] as String?,
      );

      if (result.success && result.dbhCm != null && mounted) {
        await _promptDbhSourceAfterVision(
          visionDbhCm: result.dbhCm!,
          confidence: result.confidence,
          method: 'multi_shot_fusion',
          image: image,
          measurementRow: result.measurementRow,
          trunkDepthM: result.trunkDepthM,
          notes: result.notes,
        );
        if (mounted) {
          setState(() {
            _isAutoPilotRunning = false;
            _autoPilotStatus = '多照片融合完成 (${_capturedImages.length}張)';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isAutoPilotRunning = false;
            _autoPilotStatus = '融合失敗，使用單張結果';
          });
        }
      }
    } catch (e) {
      debugPrint('[MultiShot] 失敗: $e');
      if (mounted) {
        setState(() {
          _isAutoPilotRunning = false;
          _autoPilotStatus = '融合失敗';
        });
      }
    }
  }

  Future<void> _identifySpecies(File image) async {
    try {
      final result = await SpeciesIdentificationService.identifyFromFile(
        image,
        lang: 'zh',
      );

      if (result['success'] == true && mounted) {
        final results = result['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final bestMatch = results.first;
          final Map<String, dynamic>? speciesObj = bestMatch['species'] is Map
              ? Map<String, dynamic>.from(bestMatch['species'] as Map)
              : null;
          final String? sciNoAuthor =
              (speciesObj?['scientificNameWithoutAuthor'] ??
                  bestMatch['scientificNameWithoutAuthor']) as String?;
          final String? sciFull = (speciesObj?['scientificName'] ??
              bestMatch['scientificName']) as String?;
          final commonNames =
              (speciesObj?['commonNames'] ?? bestMatch['commonNames']) as List?;
          final scoreNum = ((bestMatch['score'] as num?) ?? 0).toDouble();
          final score = (scoreNum * 100).toStringAsFixed(1);

          // [Policy] 現場以中文俗名為主（與 DB species_name、碳計算一致）；學名作對照
          final String? commonHint =
              (commonNames != null && commonNames.isNotEmpty)
                  ? commonNames.first.toString()
                  : null;
          String displayName = (commonHint ?? '').trim();
          if (displayName.isEmpty) displayName = (sciNoAuthor ?? '').trim();
          if (displayName.isEmpty) displayName = (sciFull ?? '').trim();
          if (displayName.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('辨識結果不完整，請手動輸入樹種')),
              );
            }
            return;
          }
          final String? speciesName = sciNoAuthor ?? sciFull;

          String? matchedId;
          final localMatch = result['localMatch'] as Map<String, dynamic>?;
          final wasAutoAdded = result['autoAdded'] == true;

          if (localMatch != null && localMatch['id'] != null) {
            matchedId = localMatch['id'].toString();
            if (wasAutoAdded && mounted) {
              setState(() {
                _allSpecies.add({
                  'id': localMatch['id'],
                  'name': localMatch['name'] ?? displayName,
                  'scientific_name':
                      localMatch['scientificName'] ?? speciesName,
                });
                _allSpecies.sort((a, b) => (a['name'] ?? '')
                    .toString()
                    .compareTo((b['name'] ?? '').toString()));
              });
            }
          } else {
            try {
              final match = _allSpecies.firstWhere((s) {
                final dbName = (s['name'] ?? '').toString().toLowerCase();
                final dbSciName =
                    (s['scientific_name'] ?? '').toString().toLowerCase();
                final synonyms = (s['synonyms'] as List?)
                        ?.map((e) => e.toString().toLowerCase())
                        .toList() ??
                    [];
                final displayLower = displayName.toLowerCase();
                final sciLower = (speciesName ?? '').toLowerCase();
                return dbName == displayLower ||
                    (dbSciName.isNotEmpty && dbSciName == sciLower) ||
                    synonyms.contains(displayLower);
              });
              matchedId = (match['id'] ?? match['樹種編號'])?.toString();
            } catch (_) {}
          }

          // [v18.5.2] 不再用信心度當門檻：只要欄位空白就自動填入學名，信心度僅作為提示
          final bool willAutoFill = _speciesController.text.isEmpty;
          setState(() {
            _autoIdentifiedSpeciesName = displayName;
            _autoIdentifiedSpeciesId = matchedId;
            _aiPredictions = results.cast<Map<String, dynamic>>();
            _speciesConfidence = score;
            if (willAutoFill) {
              _speciesController.text = displayName;
              if (matchedId != null) _speciesId = matchedId;
              _speciesReady = true;
            }
          });

          if (mounted && !_isAutoPilotRunning) {
            final hint = commonHint != null ? ' / $commonHint' : '';
            final double scorePct = scoreNum * 100;
            final Color bg = scorePct >= 50
                ? Colors.green
                : scorePct >= 20
                    ? Colors.orange
                    : Colors.red;
            final String prefix = willAutoFill ? '已自動套用' : '辨識結果';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$prefix: $displayName$hint (信心度: $score%)'),
                backgroundColor: bg,
                duration: const Duration(seconds: 4),
                action: willAutoFill
                    ? null
                    : SnackBarAction(
                        label: '覆蓋',
                        onPressed: () {
                          setState(() {
                            _speciesController.text = displayName;
                            if (matchedId != null) _speciesId = matchedId;
                            _speciesReady = true;
                          });
                        },
                      ),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('辨識失敗: ${result['error'] ?? "未知錯誤"}')),
          );
        }
      }
    } catch (e) {
      debugPrint('樹種辨識錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('樹種辨識失敗，請手動選擇'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _searchSpecies(String query) async {
    if (query.isEmpty) {
      setState(() => _speciesSearchResults = []);
      return;
    }

    // 先嘗試 server-side 搜尋（含同義詞）
    try {
      final serverResults = await _speciesService.searchSpecies(query);
      if (serverResults.isNotEmpty && mounted) {
        setState(() => _speciesSearchResults = serverResults);
        return;
      }
    } catch (_) {}

    // Fallback: 從已載入的樹種列表中搜尋（含同義詞）
    final results = _allSpecies.where((s) {
      final name = (s['name'] ?? s['樹種名稱']).toString().toLowerCase();
      final id = (s['id'] ?? s['樹種編號']).toString().toLowerCase();
      final sciName = (s['scientific_name'] ?? '').toString().toLowerCase();
      final synonyms = (s['synonyms'] as List?)?.join(' ').toLowerCase() ?? '';
      final q = query.toLowerCase();
      return name.contains(q) ||
          id.contains(q) ||
          sciName.contains(q) ||
          synonyms.contains(q);
    }).toList();

    if (mounted) {
      setState(() {
        _speciesSearchResults = results;
      });
    }
  }

  /// 提交前確保 _speciesId 已綁定（多人並發安全）。
  /// 1) 已綁定 → 直接通過。
  /// 2) Server-side 同義詞搜尋；若有命中 → 採用該 id。
  /// 3) 否則呼叫 POST /tree_species 自動建檔。後端在 transaction 內以 (LOWER(name)) 互斥，
  ///    並對 23505 衝突 fallback 回傳既有 id (exists=true)，因此多用戶同時新增同名也安全。
  Future<bool> _ensureSpeciesId() async {
    final name = _speciesController.text.trim();
    if (name.isEmpty) return true; // 由外層必填檢查處理
    if (_speciesId != null && _speciesId!.isNotEmpty) return true;

    // (a) 先以 server-side 搜尋（含同義詞）匹配既有樹種
    try {
      final matches = await _speciesService.searchSpecies(name);
      if (matches.isNotEmpty) {
        final m = matches.first;
        final mid = (m['id'] ?? m['樹種編號'])?.toString();
        if (mid != null && mid.isNotEmpty) {
          _speciesId = mid;
          return true;
        }
      }
    } catch (_) {/* 容忍搜尋失敗，落到自動建檔 */}

    // (b) 自動建檔（後端互斥保證多人安全）
    try {
      final r = await _speciesService.addSpecies(name);
      if (!mounted) return false;
      if (r['success'] == true && r['id'] != null) {
        _speciesId = r['id'].toString();
        // 同步更新本地列表，避免下次再 round-trip
        if (!_allSpecies.any((s) => s['id']?.toString() == _speciesId)) {
          _allSpecies.add({
            'id': r['id'],
            'name': r['name'] ?? name,
            'scientific_name': r['scientific_name'],
          });
        }
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('樹種建檔失敗: ${r['message'] ?? '未知錯誤'}')),
      );
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('樹種建檔錯誤: $e')),
        );
      }
      return false;
    }
  }

  Future<void> _submitForm() async {
    if (_isLoading) return;
    if (_dbhController.text.isEmpty) {
      _showError('請輸入胸徑 (DBH)');
      return;
    }

    // 提前檢查 task.id — 不能為 null 才能更新後端
    final taskId = widget.task.id;
    if (taskId == null) {
      _showError('任務 ID 不存在，無法提交');
      return;
    }

    final projectName = widget.task.projectName?.trim() ?? '';
    final tLat = widget.task.treeLatitude;
    final tLon = widget.task.treeLongitude;
    if (projectName.isNotEmpty &&
        tLat.abs() > 1e-6 &&
        tLon.abs() > 1e-6 &&
        (tLat != 0 || tLon != 0)) {
      final boundaryCheck =
          await ProjectBoundaryCoordinator.instance.evaluateSubmit(
        projectName: projectName,
        lat: tLat,
        lng: tLon,
        enforcement: BoundaryEnforcement.warnOnly,
      );
      if (boundaryCheck.hasBoundary &&
          !boundaryCheck.isInside &&
          mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('座標在專案邊界外'),
            content: Text(
              '${boundaryCheck.message}\n\n仍要提交這棵樹的測量結果嗎？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('返回'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('仍要提交'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    setState(() => _isLoading = true);

    try {
      await _refreshLockBaseline();

      final dbh = double.tryParse(_dbhController.text);
      if (dbh == null) {
        _showError('請輸入有效的數值');
        setState(() => _isLoading = false);
        return;
      }

      final submitSource = _handbook ? 'manual' : _activeDbhSource;
      _logDbh(
        'submit task=$taskId dbh=${dbh.toStringAsFixed(1)} cm '
        'source=$submitSource engine=${DbhEngineResolver.fromFormSource(submitSource).logTag} '
        'method=${_resolveSubmitMethod()} confidence=${_resolveSubmitConfidence()}',
      );

      // [Auto-Add] 提交前確保樹種已建檔（取代舊的「新增樹種」按鈕；多人並發安全）
      final speciesOk = await _ensureSpeciesId();
      if (!speciesOk) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. 儲存照片 (如果有)
      // 使用 task.id（DB PK）作為 treeId，確保唯一且能與 pending_tree_measurements 對應
      final photoTreeId = widget.task.id?.toString();
      if (_mainImage != null && photoTreeId != null) {
        // 驗證檔案是否存在（暫存檔可能被 OS 清理）
        if (await _mainImage!.exists()) {
          final savedImage = await _imageService.saveMeasurementImage(
            treeId: photoTreeId,
            image: _mainImage!,
            type: TreeImageType.trunk,
            metadata: {
              'source': 'pending',
              'task_id': widget.task.id,
              'session_id': widget.task.sessionId,
              'original_record_id': widget.task.originalRecordId,
              'species_confidence': _speciesConfidence,
            },
          );
          if (savedImage != null) {
            // 先完成上傳再轉移，避免 transfer 時 tree_images 尚未寫入
            final synced = await _imageService.syncImage(savedImage);
            debugPrint('[Photo] 同步到後端: ${synced ? "成功" : "失敗/稍後重試"}');
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('照片儲存失敗，但測量結果已提交'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          debugPrint('[Photo] 暫存檔已不存在，照片未儲存: ${_mainImage!.path}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('照片暫存檔已過期，照片未儲存'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }

      // [ML Data Collection] 收集訓練數據
      // 1. AR 測量修正記錄
      if (_measuredDbh != null && _activeDbhSource == 'vision') {
        // 僅在使用者選擇影像 DBH 時記錄修正
        await MLDataCollector.recordARMeasurementModification(
          treeId: widget.task.originalRecordId ?? widget.task.id.toString(),
          referenceObjectType: 'unknown', // 如果有紀錄參考物類型需傳入
          referenceActualSizeCm: 0, // 需傳入
          autoMeasuredDbh: _measuredDbh!,
          userModifiedDbh: dbh,
          confidence: _measurementConfidence,
          imagePath: _mainImage?.path,
          metadata: {
            'method': _measurementMethod,
            'task_id': widget.task.id,
          },
        );
      }

      // 2. 樹種辨識修正記錄
      if (_autoIdentifiedSpeciesName != null) {
        await MLDataCollector.recordSpeciesModification(
          treeId: widget.task.originalRecordId ?? widget.task.id.toString(),
          autoIdentifiedSpeciesId: _autoIdentifiedSpeciesId ?? 'unknown',
          autoIdentifiedSpeciesName: _autoIdentifiedSpeciesName!,
          userSelectedSpeciesId:
              _speciesId ?? 'unknown', // 使用者輸入的可能沒有 ID，除非是選單選的
          userSelectedSpeciesName: _speciesController.text,
          confidence: _speciesConfidence != null
              ? (double.tryParse(_speciesConfidence!) ?? 0) / 100.0
              : null,
          topPredictions: _aiPredictions,
          imagePath: _mainImage?.path,
        );
      }

      // 2. 更新測量結果（含樹木狀態）
      final combinedNotes = [
        if (_selectedStatus != '正常') '樹況: $_selectedStatus',
        if (_notesController.text.isNotEmpty) _notesController.text,
      ].join(' | ');

      // [T6][Phase1.5] 帶上載入當下的 updated_at 做樂觀鎖（UTC ISO）
      final expectedUpdatedAt = _lockIsoString();
      var updateResp = await _pendingService.updateMeasurement(
        id: taskId,
        dbhCm: dbh,
        confidence: _resolveSubmitConfidence(),
        method: _resolveSubmitMethod(),
        notes: combinedNotes.isEmpty ? _selectedStatus : combinedNotes,
        speciesName: _speciesController.text,
        expectedUpdatedAt: expectedUpdatedAt,
        dbhSource: _handbook ? 'manual' : _activeDbhSource,
      );

      // [T6] 409 衝突 → 三選一
      if (updateResp['code'] == 'CONFLICT' && mounted) {
        final server =
            (updateResp['serverVersion'] as Map?)?.cast<String, dynamic>() ??
                {};
        final action = await showConflictResolutionDialog(
          context,
          serverVersion: server,
          myDraft: {
            'measured_dbh_cm': dbh,
            'measurement_confidence': _resolveSubmitConfidence(),
            'measurement_method': _resolveSubmitMethod(),
            'measurement_notes': combinedNotes,
            'species_name': _speciesController.text,
            'status': 'completed',
          },
        );
        if (action == ConflictAction.keepMine) {
          // 強制覆寫：不帶 expected_updated_at 重送
          updateResp = await _pendingService.updateMeasurement(
            id: taskId,
            dbhCm: dbh,
            confidence: _resolveSubmitConfidence(),
            method: _resolveSubmitMethod(),
            notes: combinedNotes.isEmpty ? _selectedStatus : combinedNotes,
            speciesName: _speciesController.text,
          );
        } else if (action == ConflictAction.useServer) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已捽棄本次測量，返回任務列表')),
            );
            Navigator.of(context).pop(false);
          }
          return;
        } else if (action == ConflictAction.manualMerge) {
          // 載回伺服器最新值讓使用者重調
          if (mounted) {
            final srvDbh = server['measured_dbh_cm'];
            if (srvDbh != null) {
              _dbhController.text = srvDbh.toString();
            }
            final srvSpecies = server['species_name']?.toString();
            if (srvSpecies != null && srvSpecies.isNotEmpty) {
              _speciesController.text = srvSpecies;
            }
            final srvNotes = server['measurement_notes']?.toString();
            if (srvNotes != null) {
              _notesController.text = srvNotes;
            }
            final srvUpdated = server['updated_at']?.toString();
            if (srvUpdated != null) {
              _lockUpdatedAt = DateTime.tryParse(srvUpdated);
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已載入伺服器最新版本，請重新調整後再儲存')),
            );
          }
          return;
        } else {
          return; // 取消
        }
      }

      // [T6][S5] 410 該筆已刪 / 已轉移
      if (updateResp['code'] == 'DELETED' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('資料已被刪除或已轉移，返回任務列表')),
        );
        Navigator.of(context).pop(false);
        return;
      }

      if (updateResp['success'] != true) {
        _showError(updateResp['message']?.toString() ?? '更新失敗');
        return;
      }

      final newUpdated = updateResp['data']?['updated_at']?.toString();
      if (newUpdated != null) {
        _lockUpdatedAt = DateTime.tryParse(newUpdated);
      }

      if (widget.autoTransferToTreeSurvey) {
        final sessionId =
            widget.transferSessionId ?? widget.task.sessionId;
        if (sessionId != null && sessionId.isNotEmpty) {
          try {
            final tr = await _pendingService.transferToTreeSurvey(
              sessionId: sessionId,
            );
            if (tr['success'] == true) {
              try {
                final idMapping = tr['id_mapping'] as List<dynamic>?;
                if (idMapping != null) {
                  for (final m in idMapping) {
                    if (m is! Map) continue;
                    final pendingId = m['pending_id']?.toString();
                    final surveyId = m['tree_survey_id']?.toString();
                    if (pendingId != null && surveyId != null) {
                      await _imageService.remapTreeId(pendingId, surveyId);
                    }
                  }
                }
              } catch (e) {
                debugPrint('[IntegratedForm] photo remap failed: $e');
              }
            }
            if (mounted && tr['success'] == true) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tr['message']?.toString() ??
                        context.tr('transfer_auto_ok'),
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tr['message']?.toString() ??
                        context.tr('transfer_auto_fail'),
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          } catch (e) {
            debugPrint('[IntegratedForm] auto-transfer failed: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${context.tr('transfer_auto_fail')}: $e',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      _showError('提交失敗: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  bool get _hasUnsavedData =>
      _mainImage != null ||
      _measuredDbh != null ||
      _dbhController.text.isNotEmpty;

  Future<bool> _confirmExit() async {
    if (!_hasUnsavedData) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有未儲存的測量結果'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_measuredDbh != null)
              Text('DBH: ${_measuredDbh!.toStringAsFixed(1)} cm'),
            if (_speciesController.text.isNotEmpty)
              Text('樹種: ${_speciesController.text}'),
            const SizedBox(height: 8),
            const Text('確定要離開嗎？未儲存的資料會遺失。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('繼續測量'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('放棄'),
          ),
        ],
      ),
    );
    return result == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldLeave = await _confirmExit();
        if (shouldLeave && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('V3 樹木測量'),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final shouldLeave = await _confirmExit();
              if (shouldLeave && context.mounted) {
                Navigator.of(context).pop(false);
              }
            },
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPhotoSection(),
                    if (_showMultiShotHint)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Material(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _isAutoPilotRunning
                                ? null
                                : _takeMultiShotPhoto,
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.add_a_photo,
                                      color: Colors.amber.shade800),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('再拍一張可提高精度',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.amber.shade900)),
                                        Text(
                                            '目前信心度 ${((_measurementConfidence ?? 0) * 100).toStringAsFixed(0)}%，多張照片融合可降低誤差',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.amber.shade700)),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.arrow_forward_ios,
                                      size: 16, color: Colors.amber.shade600),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    _buildInfoCard(),
                    if (widget.task.targetTreeId != null) ...[
                      const SizedBox(height: 16),
                      _buildHistoryCard(),
                    ],
                    const SizedBox(height: 24),
                    _buildMeasurementForm(),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submitForm,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_circle),
                      label: Text(
                        _isLoading
                            ? context.tr('integrated_submitting')
                            : context.tr('integrated_submit'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLoading ? Colors.grey : Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        textStyle: const TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Column(
      children: [
        if (_phoneToTreeDistance != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: _distanceSource == 'gps'
                  ? Colors.green.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _distanceSource == 'gps'
                    ? Colors.green.shade300
                    : Colors.blue.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _distanceSource == 'gps' ? Icons.gps_fixed : Icons.straighten,
                  size: 16,
                  color: _distanceSource == 'gps'
                      ? Colors.green.shade700
                      : Colors.blue.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _distanceSource == 'gps'
                        ? '距目標 ${_phoneToTreeDistance!.toStringAsFixed(1)}m (GPS${_gpsAccuracyM != null ? " ±${_gpsAccuracyM!.toStringAsFixed(0)}m" : ""})'
                        : '現場距離提示 ${_phoneToTreeDistance!.toStringAsFixed(1)}m (儀器 HD)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _distanceSource == 'gps'
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        AspectRatio(
          aspectRatio: 16 / 9,
          child: GestureDetector(
            onTap: _isAutoPilotRunning ? null : _showCaptureModeSheet,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade400),
                image: _mainImage != null
                    ? DecorationImage(
                        image: FileImage(_mainImage!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _mainImage == null
                  ? Stack(
                      children: [
                        // Vertical guide line
                        Center(
                          child: Container(
                            width: 1.5,
                            height: double.infinity,
                            color: Colors.teal.withValues(alpha: 0.2),
                          ),
                        ),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_awesome,
                                  size: 48, color: Colors.teal.shade400),
                              const SizedBox(height: 8),
                              Text(
                                '點擊選擇拍照模式',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade800),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  context.tr(_preferredCaptureMode.subtitleKey),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.teal.shade700),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _handbook
                                    ? context.tr('handbook_photo_hint')
                                    : '建議：整合拍照（含即時樹幹框）',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : Stack(
                      children: [
                        if (_isAutoPilotRunning)
                          Container(
                            color: Colors.black54,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(
                                      color: Colors.white),
                                  const SizedBox(height: 8),
                                  Text(_autoPilotStatus,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: IconButton(
                            onPressed: _isAutoPilotRunning
                                ? null
                                : _showCaptureModeSheet,
                            icon:
                                const Icon(Icons.refresh, color: Colors.white),
                            tooltip: '重拍／變更模式',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                        // AutoPilot 結果指標
                        if (!_isAutoPilotRunning && _speciesReady)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _buildBadge('樹種', Colors.green),
                          ),
                        if (!_handbook &&
                            !_isAutoPilotRunning &&
                            _dbhReady &&
                            !_speciesReady)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: _buildBadge('DBH', Colors.green),
                          ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _isAutoPilotRunning ? null : _showCaptureModeSheet,
                icon: const Icon(Icons.camera_alt),
                label: Text(_mainImage == null ? '拍照' : '重拍'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isAutoPilotRunning ? null : _importPhoto,
                icon: const Icon(Icons.photo_library),
                label: const Text('匯入照片'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildHistoryCard() {
    final treeId = widget.task.targetTreeId;
    if (treeId == null) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  context.tr('history_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            TreeMeasurementHistoryPanel(treeId: treeId, initialLimit: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.teal),
                const SizedBox(width: 8),
                Text(
                  '待測量任務 ID: ${widget.task.originalRecordId ?? widget.task.id}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            _buildInfoRow(
                '樹高', '${widget.task.treeHeight.toStringAsFixed(1)} m'),
            _buildInfoRow(
                '距離', '${widget.task.horizontalDistance.toStringAsFixed(1)} m'),
            _buildInfoRow('方位角', '${widget.task.azimuth.toStringAsFixed(0)}°'),
            if (widget.task.hasInstrumentDbh)
              _buildInfoRow(
                '儀器 Remote Dia',
                '${widget.task.instrumentDbhCm!.toStringAsFixed(1)} cm',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandbookDbhBanner() {
    return Card(
      color: Colors.teal.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten, size: 18, color: Colors.teal.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    context.tr('handbook_dbh_title'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('handbook_dbh_hint'),
              style: TextStyle(fontSize: 12, color: Colors.teal.shade900),
            ),
            if (widget.task.hasInstrumentDbh) ...[
              const SizedBox(height: 8),
              Text(
                '儀器 Remote Dia 參考：'
                '${widget.task.instrumentDbhCm!.toStringAsFixed(1)} cm'
                '（非手冊 DBH）',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDbhSourceCard() {
    if (_handbook) return const SizedBox.shrink();
    final chips = <Widget>[];

    if (widget.task.hasInstrumentDbh) {
      final v = widget.task.instrumentDbhCm!;
      chips.add(
        ChoiceChip(
          label: Text('儀器 ${v.toStringAsFixed(1)} cm'),
          selected: _activeDbhSource == 'remote_diameter',
          onSelected: (_) => _selectDbhSource('remote_diameter'),
        ),
      );
    }

    if (_storedVisionDbhCm != null) {
      final v = _storedVisionDbhCm!;
      chips.add(
        ChoiceChip(
          label: Text('影像 ${v.toStringAsFixed(1)} cm'),
          selected: _activeDbhSource == 'vision',
          onSelected: (_) => _selectDbhSource('vision'),
        ),
      );
    }

    chips.add(
      ChoiceChip(
        label: const Text('手動輸入'),
        selected: _activeDbhSource == 'manual',
        onSelected: (_) => setState(() => _activeDbhSource = 'manual'),
      ),
    );

    return Card(
      color: Colors.blue.shade50,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.straighten, size: 18, color: Colors.blue.shade800),
                const SizedBox(width: 6),
                Text(
                  'DBH 來源',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
              ],
            ),
            if (widget.task.hasInstrumentDbh) ...[
              const SizedBox(height: 6),
              Text(
                'VLGEO2 Remote Diameter 已量得 '
                '${widget.task.instrumentDbhCm!.toStringAsFixed(1)} cm'
                '（儀器瞄準高度，非固定 1.3 m）。'
                '您仍可拍照做影像 DBH、手動輸入（胸徑尺/捲尺），'
                '或日後 LiDAR；不會自動覆蓋，請在此選擇來源。',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
              ),
            ] else ...[
              const SizedBox(height: 6),
              Text(
                '影像 DBH 在照片中樹幹偵測框中心量測，'
                '尚未對準地面 1.3 m 胸高；可改用手動輸入傳統量法。',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: chips),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildMeasurementForm() {
    return Column(
      children: [
        // 樹種輸入
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _speciesController,
                decoration: const InputDecoration(
                  labelText: '樹種名稱',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.park),
                ),
                onChanged: (value) {
                  // 使用者手動編輯名稱 → 解除既有的 species_id 綁定
                  // 提交時若仍未匹配，會由 _ensureSpeciesId() 自動建檔
                  if (_speciesId != null) _speciesId = null;
                  _speciesSearchDebounce?.cancel();
                  _speciesSearchDebounce = Timer(
                    const Duration(milliseconds: 300),
                    () => _searchSpecies(value),
                  );
                },
              ),
            ),
          ],
        ),

        if (_speciesSearchResults.isNotEmpty)
          Container(
            height: 150,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              itemCount: _speciesSearchResults.length,
              itemBuilder: (context, index) {
                final species = _speciesSearchResults[index];
                final matchType = species['match_type'];
                final matchedVariant = species['matched_variant'];
                return ListTile(
                  leading: Icon(
                    matchType == 'synonym' ? Icons.swap_horiz : Icons.park,
                    color:
                        matchType == 'synonym' ? Colors.orange : Colors.green,
                    size: 20,
                  ),
                  title: Text(species['name'] ?? species['樹種名稱'] ?? ''),
                  subtitle: Text(
                    matchType == 'synonym' && matchedVariant != null
                        ? '同義: $matchedVariant | ${species['scientific_name'] ?? ''}'
                        : species['scientific_name'] ?? species['樹種編號'] ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    setState(() {
                      _speciesController.text =
                          species['name'] ?? species['樹種名稱'];
                      _speciesId =
                          (species['id'] ?? species['樹種編號'])?.toString();
                      _speciesSearchResults.clear();
                    });
                  },
                );
              },
            ),
          ),

        const SizedBox(height: 16),

        if (_handbook)
          _buildHandbookDbhBanner()
        else if (widget.task.hasInstrumentDbh || _storedVisionDbhCm != null)
          _buildDbhSourceCard(),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _dbhController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '胸徑 (DBH)',
                  border: const OutlineInputBorder(),
                  suffixText: 'cm',
                  prefixIcon: const Icon(Icons.circle_outlined),
                  helperText: _handbook
                      ? '請於 1.3 m 胸高以胸徑尺／捲尺量測'
                      : (_activeDbhSource != null
                          ? '目前採用：${_dbhSourceLabel(_activeDbhSource!)}'
                          : null),
                ),
              ),
            ),
          ],
        ),

        if (_previewCarbonKg != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              '${CarbonDisplay.previewLabelStorage()}: ${CarbonDisplay.formatStorage(_previewCarbonKg)}',
              style: TextStyle(
                fontSize: 13,
                color: Colors.teal.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

        if (_measurementConfidence != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 14,
                    color: _measurementConfidence! > 0.8
                        ? Colors.green
                        : Colors.orange),
                const SizedBox(width: 4),
                Text(
                  '測量信心度: ${(_measurementConfidence! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: _measurementConfidence! > 0.8
                        ? Colors.green
                        : Colors.orange,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // 備註輸入
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '備註',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.note),
            alignLabelWithHint: true,
          ),
        ),

        const SizedBox(height: 16),

        // 狀態選擇
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('樹木狀況', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _statusOptions.map((status) {
                return ChoiceChip(
                  label: Text(status),
                  selected: _selectedStatus == status,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedStatus = status);
                    }
                  },
                  selectedColor: Colors.teal.shade100,
                  labelStyle: TextStyle(
                    color: _selectedStatus == status
                        ? Colors.teal.shade900
                        : Colors.black,
                    fontWeight: _selectedStatus == status
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ],
    );
  }
}
