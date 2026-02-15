import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/pending_tree_measurement.dart';
import '../../services/pending_measurement_service.dart';
import '../../services/species_identification_service.dart';
import '../../services/species_service.dart'; // Import SpeciesService
import '../../services/v3/tree_image_service.dart';
import '../../services/v3/ml_data_collector.dart'; // ML Data Collector
import '../../services/ar_measurement_service.dart'; // For MeasurementResult
import '../ar_dbh_measurement_page.dart';

/// V3 整合式樹木測量表單
/// 
/// 整合了：
/// 1. 照片拍攝與管理
/// 2. AR DBH 測量
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
  bool _isIdentifying = false;
  File? _mainImage;
  String? _speciesConfidence;
  
  // 樹種資料
  List<Map<String, dynamic>> _allSpecies = [];
  List<Map<String, dynamic>> _speciesSearchResults = [];
  String? _speciesId; // 記錄使用者選擇的樹種 ID (若有的話)
  
  // 測量結果暫存
  double? _measuredDbh;
  double? _measurementConfidence;
  String? _measurementMethod;
  
  // AI 辨識暫存
  String? _autoIdentifiedSpeciesName;
  String? _autoIdentifiedSpeciesId; // 目前 API 可能沒回傳 ID，視情況而定
  List<Map<String, dynamic>>? _aiPredictions;

  @override
  void initState() {
    super.initState();
    _initializeForm();
    _loadSpecies();
  }
  
  Future<void> _loadSpecies() async {
    try {
      // 優先載入增強版列表（含同義詞）
      final species = await _speciesService.getEnhancedSpecies();
      setState(() {
        _allSpecies = species;
      });
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
        });
        
        // 自動觸發樹種辨識
        _identifySpecies(image);
      }
    } catch (e) {
      _showError('拍照失敗: $e');
    }
  }

  Future<void> _identifySpecies(File image) async {
    setState(() => _isIdentifying = true);
    
    try {
      final result = await SpeciesIdentificationService.identifyFromFile(
        image,
        lang: 'zh', // 中文結果
      );
      
      if (result['success'] == true && mounted) {
        final results = result['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final bestMatch = results.first;
          final speciesName = bestMatch['species']['scientificNameWithoutAuthor'];
          final commonNames = bestMatch['species']['commonNames'] as List?;
          final score = (bestMatch['score'] * 100).toStringAsFixed(1);
          
          String displayName = speciesName;
          if (commonNames != null && commonNames.isNotEmpty) {
            displayName = commonNames.first;
          }

          // 優先使用後端回傳的 localMatch（含自動新增結果）
          String? matchedId;
          final localMatch = result['localMatch'] as Map<String, dynamic>?;
          final wasAutoAdded = result['autoAdded'] == true;
          
          if (localMatch != null && localMatch['id'] != null) {
            matchedId = localMatch['id'].toString();
            // 若是自動新增的樹種，動態加入本地列表
            if (wasAutoAdded) {
              _allSpecies.add({
                'id': localMatch['id'],
                'name': localMatch['name'] ?? displayName,
                'scientific_name': localMatch['scientificName'] ?? speciesName,
              });
            }
          } else {
            // Fallback: 在本地列表匹配（含同義詞）
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
              matchedId = match['id'] ?? match['樹種編號'];
            } catch (_) {
              // No match found
            }
          }
          
          // 構建 SnackBar 訊息
          String snackMsg = '辨識結果: $displayName (信心度: $score%)';
          if (wasAutoAdded) {
            snackMsg += ' [新樹種已自動建檔]';
          } else if (matchedId != null) {
            snackMsg += ' [已匹配]';
          }

          // [ML Data Collection] 暫存自動辨識結果
          setState(() {
             _autoIdentifiedSpeciesName = displayName;
             _autoIdentifiedSpeciesId = matchedId;
             _aiPredictions = results.cast<Map<String, dynamic>>();
             _speciesConfidence = score;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(snackMsg),
              action: SnackBarAction(
                label: '套用',
                onPressed: () {
                  setState(() {
                    _speciesController.text = displayName;
                    if (matchedId != null) {
                      _speciesId = matchedId;
                    }
                  });
                },
              ),
              duration: const Duration(seconds: 8),
            ),
          );
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
    } finally {
      if (mounted) {
        setState(() => _isIdentifying = false);
      }
    }
  }

  Future<void> _startARMeasurement() async {
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (context) => ARDBHMeasurementPage(
          initialDbh: double.tryParse(_dbhController.text),
          speciesName: _speciesController.text,
          knownDistance: widget.task.horizontalDistance,
          targetLat: widget.task.treeLatitude,
          targetLon: widget.task.treeLongitude,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _measuredDbh = result.diameterCm;
        _measurementConfidence = result.confidenceScore;
        _measurementMethod = result.method.name;
        _dbhController.text = result.diameterCm.toStringAsFixed(1);
        
        if (result.notes != null && result.notes!.isNotEmpty) {
          if (_notesController.text.isNotEmpty) {
            _notesController.text += '\n${result.notes}';
          } else {
            _notesController.text = result.notes!;
          }
        }
      });

      // 如果尚未辨識樹種且有拍攝影像，自動進行樹種辨識
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

    setState(() {
      _speciesSearchResults = results;
    });
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
      final dbh = double.parse(_dbhController.text);

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
          confidence: _speciesConfidence != null ? double.tryParse(_speciesConfidence!)! / 100.0 : null,
          topPredictions: _aiPredictions,
          imagePath: _mainImage?.path,
        );
      }

      // 2. 更新測量結果
      await _pendingService.updateMeasurement(
        id: widget.task.id!,
        dbhCm: dbh,
        confidence: _measurementConfidence ?? 1.0, // 如果是手動輸入，預設信心度 1.0 (或視為人工確認)
        method: _measurementMethod ?? 'manual_input',
        notes: _notesController.text,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('V3 樹木測量'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPhotoSection(),
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
    );
  }

  Widget _buildPhotoSection() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: GestureDetector(
        onTap: _takePhoto,
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
                    const Icon(Icons.add_a_photo, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    const Text('點擊拍攝樹木照片'),
                    const Text(
                      '(拍攝後將自動辨識樹種)',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                )
              : Stack(
                  children: [
                    if (_isIdentifying)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 8),
                              Text('正在辨識樹種...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: _takePhoto,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        tooltip: '重拍',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
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
              onPressed: _startARMeasurement,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                side: BorderSide(color: Colors.teal.shade200),
              ),
              child: const Column(
                children: [
                  Icon(Icons.view_in_ar),
                  SizedBox(height: 4),
                  Text('AR 測量'),
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
                  'AR 測量信心度: ${(_measurementConfidence! * 100).toStringAsFixed(0)}%',
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
