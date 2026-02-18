import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:exif/exif.dart';
import '../../models/pending_tree_measurement.dart';
import '../../services/pending_measurement_service.dart';
import '../../services/species_identification_service.dart';
import '../../services/species_service.dart';
import '../../services/pure_vision_dbh_service.dart';
import '../../services/v3/tree_image_service.dart';
import '../../services/v3/ml_data_collector.dart';
import '../../services/ar_measurement_service.dart';
import '../pure_vision_dbh_page.dart';

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
  
  // 表單控制器
  final TextEditingController _dbhController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _speciesController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  
  // 狀態
  String _selectedStatus = '正常';
  final List<String> _statusOptions = ['正常', '枯死', '病蟲害', '傾斜', '斷梢', '空洞', '其他'];

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

  @override
  void initState() {
    super.initState();
    _initializeForm();
    _loadSpecies();
    _acquirePhoneGps();
  }
  
  /// 取得手機 GPS 位置，智慧選擇最佳參考距離
  ///
  /// 三層保護機制：
  /// 1. 無 GPS 座標（treeLat/Lon=0）→ fallback 到儀器 HD
  /// 2. GPS 精度太差（accuracy > 20m）→ fallback 到儀器 HD
  /// 3. GPS 距離與儀器 HD 差距 > 100% → 警告，優先用儀器 HD
  Future<void> _acquirePhoneGps() async {
    final instrumentHD = widget.task.horizontalDistance;
    
    // 保護 1: 無樹木 GPS 座標時，直接用儀器 HD
    if (widget.task.treeLatitude == 0 && widget.task.treeLongitude == 0) {
      debugPrint('[GPS] 樹木無 GPS 座標，使用儀器 HD=${instrumentHD}m');
      setState(() {
        _phoneToTreeDistance = instrumentHD;
        _distanceSource = 'instrument';
      });
      return;
    }
    
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));
      
      if (!mounted) return;
      
      _gpsAccuracyM = position.accuracy;
      
      // 保護 2: GPS 精度太差，改用儀器 HD
      if (position.accuracy > 20) {
        debugPrint('[GPS] 精度太差 (${position.accuracy.toStringAsFixed(0)}m)，使用儀器 HD');
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GPS 精度不足 (±${position.accuracy.toStringAsFixed(0)}m)，改用儀器距離 ${instrumentHD.toStringAsFixed(1)}m'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
      
      final gpsDist = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        widget.task.treeLatitude, widget.task.treeLongitude,
      );
      
      // 保護 3: GPS 與儀器 HD 嚴重不一致（差距 > 100%）
      final deviation = (gpsDist - instrumentHD).abs();
      final deviationPct = instrumentHD > 0 ? deviation / instrumentHD : double.infinity;
      
      if (deviationPct > 1.0) {
        debugPrint('[GPS] GPS(${gpsDist.toStringAsFixed(1)}m) 與儀器HD(${instrumentHD.toStringAsFixed(1)}m) 差距 ${(deviationPct * 100).toStringAsFixed(0)}%，優先用儀器 HD');
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GPS 距離 (${gpsDist.toStringAsFixed(0)}m) 與儀器 (${instrumentHD.toStringAsFixed(1)}m) 差異過大，採用儀器距離'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      
      // GPS 品質合格，使用 GPS 距離
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
      debugPrint('[GPS] 定位失敗: $e — fallback 到儀器 HD');
      if (mounted) {
        setState(() {
          _phoneToTreeDistance = instrumentHD;
          _distanceSource = 'instrument';
        });
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

  /// [Phase 1] AutoPilot 一鍵量測
  /// 同時觸發 DBH 測量和樹種辨識（並行），自動填入結果
  Future<void> _runAutoPilot(File image) async {
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
            : _dbhReady ? '樹種辨識需確認' 
            : _speciesReady ? 'DBH 需確認' 
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
          exifInfo['focalMm'] = r.denominator != 0 ? r.numerator.toDouble() / r.denominator.toDouble() : null;
        } else {
          exifInfo['focalMm'] = double.tryParse(focalTag.printable.replaceAll(' ', ''));
        }
      }

      final focal35Tag = exifData['EXIF FocalLengthIn35mmFilm'];
      if (focal35Tag != null) {
        exifInfo['focal35'] = double.tryParse(focal35Tag.printable.replaceAll(' ', ''));
      }

      final makeTag = exifData['Image Make'];
      if (makeTag != null) exifInfo['make'] = makeTag.printable.trim();

      final modelTag = exifData['Image Model'];
      if (modelTag != null) exifInfo['model'] = modelTag.printable.trim();

      debugPrint('[EXIF] ${exifInfo}');
    } catch (e) {
      debugPrint('[EXIF] Read failed: $e');
    }
    return exifInfo;
  }

  /// 自動 DBH 量測（附帶 EXIF 焦距提取）
  Future<void> _autoMeasureDbh(File image) async {
    try {
      setState(() => _autoPilotStatus = '測量 DBH 中...');
      
      final service = PureVisionDbhService();
      final available = await service.isServiceAvailable();
      if (!available) {
        debugPrint('[AutoPilot] ML Service 不可用，跳過自動 DBH');
        if (mounted) {
          setState(() => _autoPilotStatus = 'ML 服務無法連線');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('ML 量測服務無法連線，DBH 需手動輸入\n'
                  '請確認 ngrok 隧道與 ML Service 是否運行中'),
              duration: Duration(seconds: 5),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Extract EXIF for better focal length accuracy
      final exif = await _extractExif(image);

      final result = await service.autoMeasureDbh(
        imageFile: image,
        referenceDistanceM: _phoneToTreeDistance,
        instrumentDistanceM: widget.task.horizontalDistance,
        distanceSource: _distanceSource,
        focalLengthMm: exif['focalMm'] as double?,
        focalLength35mm: exif['focal35'] as double?,
        phoneMake: exif['make'] as String?,
        phoneModel: exif['model'] as String?,
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
    }
  }

  /// Multi-shot: take another photo and send all to fusion endpoint
  Future<void> _takeMultiShotPhoto() async {
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
      final result = await service.autoMeasureDbhMulti(
        imageFiles: _capturedImages,
        referenceDistanceM: _phoneToTreeDistance,
        instrumentDistanceM: widget.task.horizontalDistance,
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
          final speciesName = bestMatch['species']['scientificNameWithoutAuthor'];
          final commonNames = bestMatch['species']['commonNames'] as List?;
          final scoreNum = (bestMatch['score'] as num).toDouble();
          final score = (scoreNum * 100).toStringAsFixed(1);
          
          String displayName = speciesName;
          if (commonNames != null && commonNames.isNotEmpty) {
            displayName = commonNames.first;
          }

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
                  'scientific_name': localMatch['scientificName'] ?? speciesName,
                });
                _allSpecies.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));
              });
            }
          } else {
            try {
              final match = _allSpecies.firstWhere((s) {
                final dbName = (s['name'] ?? '').toString().toLowerCase();
                final dbSciName = (s['scientific_name'] ?? '').toString().toLowerCase();
                final synonyms = (s['synonyms'] as List?)?.map((e) => e.toString().toLowerCase()).toList() ?? [];
                final displayLower = displayName.toLowerCase();
                final sciLower = speciesName.toLowerCase();
                return dbName == displayLower || 
                       (dbSciName.isNotEmpty && dbSciName == sciLower) ||
                       synonyms.contains(displayLower);
              });
              matchedId = (match['id'] ?? match['樹種編號'])?.toString();
            } catch (_) {}
          }

          setState(() {
             _autoIdentifiedSpeciesName = displayName;
             _autoIdentifiedSpeciesId = matchedId;
             _aiPredictions = results.cast<Map<String, dynamic>>();
             _speciesConfidence = score;
          });

          // [Phase 1] 高信心度 (>=50%) 時自動套用，不需手動點「套用」
          final bool highConfidence = scoreNum >= 0.50;
          
          if (highConfidence && _speciesController.text.isEmpty) {
            setState(() {
              _speciesController.text = displayName;
              if (matchedId != null) {
                _speciesId = matchedId;
              }
              _speciesReady = true;
            });
            if (mounted && !_isAutoPilotRunning) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已自動套用: $displayName (信心度: $score%)'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            // 低信心度：提示使用者確認
            setState(() => _speciesReady = false);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('辨識結果: $displayName (信心度: $score%)'),
                  action: SnackBarAction(
                    label: '套用',
                    onPressed: () {
                      setState(() {
                        _speciesController.text = displayName;
                        if (matchedId != null) _speciesId = matchedId;
                        _speciesReady = true;
                      });
                    },
                  ),
                  duration: const Duration(seconds: 8),
                ),
              );
            }
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
    }
  }

  /// 手動進入 PureVisionDbhPage 量測（保留原有功能）
  Future<void> _startDBHMeasurement() async {
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (context) => PureVisionDbhPage(
          initialDbh: double.tryParse(_dbhController.text),
          speciesName: _speciesController.text,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _measuredDbh = result.diameterCm;
        _measurementConfidence = result.confidenceScore;
        _measurementMethod = result.method.name;
        _dbhController.text = result.diameterCm.toStringAsFixed(1);
        _dbhReady = true;
        
        if (result.notes != null && result.notes!.isNotEmpty) {
          if (_notesController.text.isNotEmpty) {
            _notesController.text += '\n${result.notes}';
          } else {
            _notesController.text = result.notes!;
          }
        }
      });

      if (_speciesController.text.isEmpty && result.capturedImagePath != null) {
        final imageFile = File(result.capturedImagePath!);
        if (await imageFile.exists()) {
          setState(() => _mainImage ??= imageFile);
          _identifySpecies(imageFile);
        }
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
      return name.contains(q) || id.contains(q) || sciName.contains(q) || synonyms.contains(q);
    }).toList();

    if (mounted) {
      setState(() {
        _speciesSearchResults = results;
      });
    }
  }

  // 顯示新增樹種對話框
  void _showAddSpeciesDialog(String prefilledName) {
    final nameController = TextEditingController(text: prefilledName);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增樹種'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '樹種名稱'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              const Text('樹種編號將由系統自動產生',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('新增'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  Navigator.of(context).pop();
                  await _addSpecies(nameController.text);
                }
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _addSpecies(String name) async {
    try {
      final response = await _speciesService.addSpecies(name);
      if (!mounted) return;

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增樹種成功: $name')),
        );

        // 更新列表並選中
        final newSpecies = {
          'id': response['id'],
          'name': response['name'],
        };
        
        setState(() {
          _allSpecies.add(newSpecies);
          _allSpecies.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
          
          _speciesController.text = name;
          _speciesId = response['id'].toString();
          _speciesSearchResults.clear();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增樹種失敗: ${response['message']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增樹種錯誤: $e')),
      );
    }
  }

  Future<void> _submitForm() async {
    if (_dbhController.text.isEmpty) {
      _showError('請輸入胸徑 (DBH)');
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

      // 1. 儲存照片 (如果有)
      if (_mainImage != null && widget.task.originalRecordId != null) {
        await _imageService.saveMeasurementImage(
          treeId: widget.task.originalRecordId!, // 使用原始記錄ID作為關聯
          image: _mainImage!,
          type: TreeImageType.trunk, // 假設為主樹幹照
          metadata: {
            'task_id': widget.task.id,
            'species_confidence': _speciesConfidence,
          },
        );
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
          userSelectedSpeciesId: _speciesId ?? 'unknown', // 使用者輸入的可能沒有 ID，除非是選單選的
          userSelectedSpeciesName: _speciesController.text,
          confidence: _speciesConfidence != null ? (double.tryParse(_speciesConfidence!) ?? 0) / 100.0 : null,
          topPredictions: _aiPredictions,
          imagePath: _mainImage?.path,
        );
      }

      // 2. 更新測量結果（含樹木狀態）
      final combinedNotes = [
        if (_selectedStatus != '正常') '樹況: $_selectedStatus',
        if (_notesController.text.isNotEmpty) _notesController.text,
      ].join(' | ');
      
      await _pendingService.updateMeasurement(
        id: widget.task.id!,
        dbhCm: dbh,
        confidence: _measurementConfidence ?? 1.0,
        method: _measurementMethod ?? 'manual_input',
        notes: combinedNotes.isEmpty ? _selectedStatus : combinedNotes,
        speciesName: _speciesController.text,
      );

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
      _mainImage != null || _measuredDbh != null || _dbhController.text.isNotEmpty;

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
        if (shouldLeave && mounted) {
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
            if (shouldLeave && mounted) {
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
                          onTap: _isAutoPilotRunning ? null : _takeMultiShotPhoto,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.add_a_photo, color: Colors.amber.shade800),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('再拍一張可提高精度',
                                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                                      Text('目前信心度 ${((_measurementConfidence ?? 0) * 100).toStringAsFixed(0)}%，多張照片融合可降低誤差',
                                          style: TextStyle(fontSize: 12, color: Colors.amber.shade700)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.amber.shade600),
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
                    onPressed: _submitForm,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('完成並提交'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
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
              color: _distanceSource == 'gps' ? Colors.green.shade50 : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _distanceSource == 'gps' ? Colors.green.shade300 : Colors.blue.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _distanceSource == 'gps' ? Icons.gps_fixed : Icons.straighten,
                  size: 16,
                  color: _distanceSource == 'gps' ? Colors.green.shade700 : Colors.blue.shade700,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _distanceSource == 'gps'
                        ? '距目標 ${_phoneToTreeDistance!.toStringAsFixed(1)}m (GPS${_gpsAccuracyM != null ? " ±${_gpsAccuracyM!.toStringAsFixed(0)}m" : ""})'
                        : '參考距離 ${_phoneToTreeDistance!.toStringAsFixed(1)}m (儀器 HD)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _distanceSource == 'gps' ? Colors.green.shade800 : Colors.blue.shade800,
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
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 48, color: Colors.teal.shade400),
                        const SizedBox(height: 8),
                        const Text('點擊拍照 — 一鍵自動量測',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        const Text(
                          '自動 DBH + 樹種辨識 + 填入表單',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
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
                                  const CircularProgressIndicator(color: Colors.white),
                                  const SizedBox(height: 8),
                                  Text(_autoPilotStatus,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: IconButton(
                            onPressed: _isAutoPilotRunning ? null : _takePhoto,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            tooltip: '重拍',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                        // AutoPilot 結果指標
                        if (!_isAutoPilotRunning && (_dbhReady || _speciesReady))
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Row(
                              children: [
                                if (_dbhReady)
                                  _buildBadge('DBH', Colors.green),
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
      ],
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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
            _buildInfoRow('樹高', '${widget.task.treeHeight.toStringAsFixed(1)} m'),
            _buildInfoRow('距離', '${widget.task.horizontalDistance.toStringAsFixed(1)} m'),
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
                onChanged: (value) => _searchSpecies(value),
              ),
            ),
            if (_speciesSearchResults.isEmpty && _speciesController.text.isNotEmpty && 
                !_allSpecies.any((s) => s['name'] == _speciesController.text || s['樹種名稱'] == _speciesController.text))
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                onPressed: () => _showAddSpeciesDialog(_speciesController.text),
                tooltip: '新增樹種',
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
                    color: matchType == 'synonym' ? Colors.orange : Colors.green,
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
                      _speciesController.text = species['name'] ?? species['樹種名稱'];
                      _speciesId = (species['id'] ?? species['樹種編號'])?.toString();
                      _speciesSearchResults.clear();
                    });
                  },
                );
              },
            ),
          ),

        const SizedBox(height: 16),
        
        // DBH 輸入 + AR 按鈕
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
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _startDBHMeasurement,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                side: BorderSide(color: Colors.teal.shade200),
              ),
              child: const Column(
                children: [
                  Icon(Icons.camera_alt),
                  SizedBox(height: 4),
                  Text('DBH 測量'),
                ],
              ),
            ),
          ],
        ),
        
        if (_measurementConfidence != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline, 
                  size: 14, 
                  color: _measurementConfidence! > 0.8 ? Colors.green : Colors.orange
                ),
                const SizedBox(width: 4),
                Text(
                  '測量信心度: ${(_measurementConfidence! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: _measurementConfidence! > 0.8 ? Colors.green : Colors.orange,
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
                    color: _selectedStatus == status ? Colors.teal.shade900 : Colors.black,
                    fontWeight: _selectedStatus == status ? FontWeight.bold : FontWeight.normal,
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
