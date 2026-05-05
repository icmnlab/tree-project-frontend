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
import '../../services/v3/ml_data_collector.dart';
import '../../widgets/conflict_resolution_dialog.dart';

/// V3 整合式樹木測量表單
///
/// 整合了：
/// 1. 照片拍攝與管理
/// 2. 影像 DBH 測量
/// 3. AI 樹種辨識
/// 4. 待測量任務資料確認與提交
class IntegratedTreeFormPage extends StatefulWidget {
  final PendingTreeMeasurement task;

  const IntegratedTreeFormPage({
    super.key,
    required this.task,
  });

  @override
  State<IntegratedTreeFormPage> createState() => _IntegratedTreeFormPageState();
}

class _IntegratedTreeFormPageState extends State<IntegratedTreeFormPage> {
  final PendingMeasurementService _pendingService = PendingMeasurementService();
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

  // AI 辨識暫存
  String? _autoIdentifiedSpeciesName;
  String? _autoIdentifiedSpeciesId;
  List<Map<String, dynamic>>? _aiPredictions;

  // [Phase 1] AutoPilot 進度
  String _autoPilotStatus = '';
  bool _dbhReady = false;
  bool _speciesReady = false;

  // Multi-shot: stored images for precision boost
  final List<File> _capturedImages = [];
  Map<String, dynamic> _lastExif = {};
  bool _showMultiShotHint = false;
  Timer? _speciesSearchDebounce;

  @override
  void initState() {
    super.initState();
    _initializeForm();
    _loadSpecies();
    _acquirePhoneGps();
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

  void _initializeForm() {
    _heightController.text = widget.task.treeHeight.toStringAsFixed(1);
    if (widget.task.dbhCm != null) {
      _dbhController.text = widget.task.dbhCm!.toStringAsFixed(1);
    }
    if (widget.task.speciesName != null) {
      _speciesController.text = widget.task.speciesName!;
    }
  }

  @override
  void dispose() {
    // 同步清理暫存照片（不使用 await，因 dispose 不能 async）
    _cleanupTempImages();
    _tfliteTracker.dispose();
    _speciesSearchDebounce?.cancel();
    _dbhController.dispose();
    _heightController.dispose();
    _speciesController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final File? image = await _imageService.captureImage();
      if (image != null) {
        // 清理先前的暫存照片（避免累積）
        _cleanupTempImages();
        setState(() {
          _mainImage = image;
          _capturedImages.clear();
          _showMultiShotHint = false;
        });
        // [Phase 1] 拍照後自動啟動 AutoPilot
        _runAutoPilot(image);
      }
    } catch (e) {
      _showError('拍照失敗: $e');
    }
  }

  Future<void> _importPhoto() async {
    try {
      final File? image = await _imageService.captureImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        _cleanupTempImages();
        setState(() {
          _mainImage = image;
          _capturedImages.clear();
          _showMultiShotHint = false;
        });
        _runAutoPilot(image);
      }
    } catch (e) {
      _showError('匯入照片失敗: $e');
    }
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

    // 並行執行 DBH 量測和樹種辨識
    await Future.wait([
      _autoMeasureDbh(image),
      _identifySpecies(image),
    ]);

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
        setState(() {
          _measuredDbh = result.dbhCm;
          _measurementConfidence = result.confidence;
          _measurementMethod = 'autopilot_vision';
          _dbhController.text = result.dbhCm!.toStringAsFixed(1);
          _dbhReady = conf >= 0.6;
          _capturedImages.add(image);
          _lastExif = exif;
          _showMultiShotHint = conf < 0.7 && _capturedImages.length < 3;
        });
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
        setState(() {
          _mainImage = image;
          _measuredDbh = result.dbhCm;
          _measurementConfidence = result.confidence;
          _measurementMethod = 'multi_shot_fusion';
          _dbhController.text = result.dbhCm!.toStringAsFixed(1);
          _dbhReady = (result.confidence ?? 0) >= 0.6;
          _isAutoPilotRunning = false;
          _autoPilotStatus = '多照片融合完成 (${_capturedImages.length}張)';
        });
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

          // [Policy] 學名優先；若無則退回完整學名/俗名。總之先把名字填進去，信心度只做提示
          final String? commonHint =
              (commonNames != null && commonNames.isNotEmpty)
                  ? commonNames.first.toString()
                  : null;
          String displayName = (sciNoAuthor ?? '').trim();
          if (displayName.isEmpty) displayName = (sciFull ?? '').trim();
          if (displayName.isEmpty && commonHint != null) {
            displayName = commonHint.trim();
          }
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

    setState(() => _isLoading = true);

    try {
      final dbh = double.tryParse(_dbhController.text);
      if (dbh == null) {
        _showError('請輸入有效的數值');
        setState(() => _isLoading = false);
        return;
      }

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
              'task_id': widget.task.id,
              'session_id': widget.task.sessionId,
              'original_record_id': widget.task.originalRecordId,
              'species_confidence': _speciesConfidence,
            },
          );
          if (savedImage != null) {
            // 非同步上傳到後端（不阻塞提交流程）
            _imageService.syncImage(savedImage).then((ok) {
              debugPrint('[Photo] 同步到後端: ${ok ? "成功" : "失敗/稍後重試"}');
            }).catchError((e) {
              debugPrint('[Photo] 同步異常（將在下次批次時重試）: $e');
            });
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
      if (_measuredDbh != null) {
        // 只有當有進行過 AR 測量才記錄
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

      // [T6][Phase1.5] 帶上載入當下的 updated_at 做樂觀鎖
      final expectedUpdatedAt = widget.task.updatedAt?.toIso8601String();
      var updateResp = await _pendingService.updateMeasurement(
        id: taskId,
        dbhCm: dbh,
        confidence: _measurementConfidence ?? 1.0,
        method: _measurementMethod ?? 'manual_input',
        notes: combinedNotes.isEmpty ? _selectedStatus : combinedNotes,
        speciesName: _speciesController.text,
        expectedUpdatedAt: expectedUpdatedAt,
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
            'measurement_confidence': _measurementConfidence ?? 1.0,
            'measurement_method': _measurementMethod ?? 'manual_input',
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
            confidence: _measurementConfidence ?? 1.0,
            method: _measurementMethod ?? 'manual_input',
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

      if (mounted) {
        Navigator.of(context).pop(true); // 返回 true 表示成功
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
                      label: Text(_isLoading ? '提交中...' : '完成並提交'),
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
            onTap: _isAutoPilotRunning ? null : _takePhoto,
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
                              const Text('點擊拍照 — 一鍵自動量測',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '距樹幹 1-3m，將樹幹置於畫面中央',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.teal.shade700),
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                '自動 DBH + 樹種辨識 + 填入表單',
                                style:
                                    TextStyle(fontSize: 11, color: Colors.grey),
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
                            onPressed: _isAutoPilotRunning ? null : _takePhoto,
                            icon:
                                const Icon(Icons.refresh, color: Colors.white),
                            tooltip: '重拍',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                        // AutoPilot 結果指標
                        if (!_isAutoPilotRunning &&
                            (_dbhReady || _speciesReady))
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Row(
                              children: [
                                if (_dbhReady) _buildBadge('DBH', Colors.green),
                                if (_dbhReady) const SizedBox(width: 4),
                                if (_speciesReady)
                                  _buildBadge('樹種', Colors.green),
                              ],
                            ),
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
                onPressed: _isAutoPilotRunning ? null : _takePhoto,
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

        // DBH 輸入（AutoPilot 失敗或人工覆核時可手動補值）
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _dbhController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '胸徑 (DBH)',
                  border: OutlineInputBorder(),
                  suffixText: 'cm',
                  prefixIcon: Icon(Icons.circle_outlined),
                ),
              ),
            ),
          ],
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
