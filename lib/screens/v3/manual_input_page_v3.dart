import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/tree_service.dart';
import '../../services/project_service.dart';
import '../../services/species_service.dart';
import '../../services/species_identification_service.dart';
import '../../services/v3/project_boundary_service.dart';
import '../../services/v3/tree_image_service.dart';
import '../../services/v3/ml_data_collector.dart'; // ML Data Collector
import '../ar_dbh_measurement_page.dart'; // For AR Page
import '../../services/ar_measurement_service.dart'; // For MeasurementResult
import '../../services/project_area_service.dart'; // 新增專案區位服務

class ManualInputPageV3 extends StatefulWidget {
  const ManualInputPageV3({super.key});

  @override
  State<ManualInputPageV3> createState() => _ManualInputPageV3State();
}

class _ManualInputPageV3State extends State<ManualInputPageV3> {
  int _currentStep = 0;
  bool _isLoading = false;
  
  // Services
  final ProjectService _projectService = ProjectService();
  final TreeService _treeService = TreeService();
  final ProjectBoundaryService _boundaryService = ProjectBoundaryService();
  final TreeImageService _imageService = TreeImageService();
  final TreeSpeciesService _speciesService = TreeSpeciesService();
  final ProjectAreaService _projectAreaService = ProjectAreaService();

  // Step 1: Location & Project
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _projectCodeController = TextEditingController();
  final TextEditingController _areaController = TextEditingController();
  LatLng? _currentLocation;
  String? _selectedProjectName;
  List<String> _availableProjects = []; // 從 _filteredProjects 中獲取，用於自動匹配時的顯示
  bool _isLocationValid = false;
  String? _locationWarning;
  
  // V3: 專案區位和專案列表（類似 V2）
  List<Map<String, dynamic>> _projectAreas = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  bool _loadingAreas = false;
  bool _loadingFilteredProjects = false;
  
  // Cleanup Tracking - 追蹤本次 session 新增的專案區位和專案，以便在退出時清理
  final List<int> _createdAreaIds = [];
  final List<String> _createdProjectCodes = [];
  bool _hasSubmitted = false; // 是否已成功提交樹木資料

  // Step 2: Species
  final TextEditingController _speciesController = TextEditingController();
  String? _speciesId;
  bool _isIdentifying = false;
  List<Map<String, dynamic>> _allSpecies = []; // 所有樹種
  List<Map<String, dynamic>> _speciesSearchResults = [];
  // AI 辨識暫存 (ML Data Collection)
  String? _autoIdentifiedSpeciesName;
  String? _autoIdentifiedSpeciesId;
  List<Map<String, dynamic>>? _aiPredictions;
  String? _speciesConfidence;
  File? _identificationImage;

  // Step 3: Measurements
  final TextEditingController _dbhController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  double? _measuredDbh;
  double? _measurementConfidence;
  String? _measurementMethod;

  // Step 4: Status
  String _selectedStatus = '正常';
  final List<String> _statusOptions = ['正常', '枯死', '病蟲害', '傾斜', '斷梢', '空洞', '其他'];
  
  // Step 5: Photos & Notes
  final TextEditingController _notesController = TextEditingController();
  final List<File> _photos = [];
  
  @override
  void initState() {
    super.initState();
    _loadProjectAreas(); // V3: 載入專案區位列表
    _loadSpecies();
    _getCurrentLocation();
  }

  Future<void> _loadProjectAreas() async {
    setState(() => _loadingAreas = true);
    try {
      final areas = await _projectAreaService.getProjectAreas();
      if (mounted) {
        setState(() {
          _projectAreas = areas;
          _loadingAreas = false;
        });
      }
    } catch (e) {
      debugPrint('載入專案區位失敗: $e');
      if (mounted) {
        setState(() => _loadingAreas = false);
      }
    }
  }

  Future<void> _updateFilteredProjects(String area) async {
    setState(() => _loadingFilteredProjects = true);
    try {
      final response = await _projectService.getProjectsByArea(area);
      if (mounted) {
        setState(() {
          if (response['success'] == true && response['data'] != null) {
            _filteredProjects = List<Map<String, dynamic>>.from(response['data']);
            // 同時更新可用專案名稱列表（用於自動匹配）
            _availableProjects = _filteredProjects.map((p) => p['name'] as String).toList();
          } else {
            _filteredProjects = [];
            _availableProjects = [];
          }
          _loadingFilteredProjects = false;
        });
      }
    } catch (e) {
      debugPrint('載入專案失敗: $e');
      if (mounted) {
        setState(() {
          _filteredProjects = [];
          _availableProjects = [];
          _loadingFilteredProjects = false;
        });
      }
    }
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

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _isLoading = false;
      });
      
      // 自動匹配專案
      _autoMatchProject();
      
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar('無法獲取位置: $e');
    }
  }

  Future<void> _autoMatchProject() async {
    if (_currentLocation == null) return;
    
    // 確保邊界資料已載入
    await _boundaryService.getAllBoundaries();
    
    final match = _boundaryService.findProjectByCoordinate(
      lat: _currentLocation!.latitude,
      lng: _currentLocation!.longitude,
    );
    
    if (match.matched && match.projectName != null) {
      setState(() {
        _selectedProjectName = match.projectName;
        _projectController.text = match.projectName!;
        if (match.projectCode != null) {
          _projectCodeController.text = match.projectCode!;
        }
        // 自動載入該專案的區位資訊（如果有）
        _isLocationValid = true;
        _locationWarning = null;
      });
      _showSnackBar('已自動匹配專案: ${match.projectName}');
      
      // 嘗試載入該專案的區位資訊
      _updateFilteredProjects(_areaController.text);
    } else {
      // 雖然沒匹配到，但如果是選擇已有專案，需檢查是否在該專案邊界外
      if (_projectController.text.isNotEmpty) {
        _validateLocation();
      }
    }
  }

  void _validateLocation() {
    if (_currentLocation == null || _projectController.text.isEmpty) return;
    
    final validation = _boundaryService.validateCoordinateForProject(
      projectName: _projectController.text,
      lat: _currentLocation!.latitude,
      lng: _currentLocation!.longitude,
    );
    
    setState(() {
      _isLocationValid = validation.isValid;
      _locationWarning = validation.isValid ? null : validation.message;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // 專案區位對話框（類似 V2）
  void _showProjectAreaDialog() {
    final areaController = TextEditingController();
    List<Map<String, dynamic>> filteredAreas = List.from(_projectAreas);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('選擇專案區位'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: areaController,
                      decoration: const InputDecoration(
                        hintText: '搜尋或新增專案區位',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setState(() {
                          if (value.isEmpty) {
                            filteredAreas = List.from(_projectAreas);
                          } else {
                            filteredAreas = _projectAreas
                                .where((area) => (area['area_name'] ?? '')
                                    .toLowerCase()
                                    .contains(value.toLowerCase()))
                                .toList();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_loadingAreas)
                      const Center(child: CircularProgressIndicator())
                    else
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredAreas.length,
                          itemBuilder: (context, index) {
                            final area = filteredAreas[index];
                            return ListTile(
                              title: Text(area['area_name'] ?? ''),
                              onTap: () {
                                setState(() {
                                  _areaController.text = area['area_name'] ?? '';
                                  _projectController.text = '';
                                  _projectCodeController.text = '';
                                  _selectedProjectName = null;
                                });
                                _updateFilteredProjects(_areaController.text);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (areaController.text.isNotEmpty) {
                      _addProjectArea(areaController.text);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('新增區位'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addProjectArea(String areaName) async {
    try {
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
        if (position == null) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 3),
          );
        }
      } catch (e) {
        debugPrint('獲取位置失敗 (非致命): $e');
      }

      final requestData = {
        'area_name': areaName,
        'description': areaName + '專案區位',
        'isSubmit': true,
        if (position != null) 'xCoord': position.longitude,
        if (position != null) 'yCoord': position.latitude,
      };
      
      final response = await _projectAreaService.addProjectArea(requestData);
      
      if (response['success'] == true) {
        // 追蹤新增的專案區位 ID
        if (response['data'] != null && response['data']['id'] != null) {
          _createdAreaIds.add(response['data']['id'] as int);
        }
        
        await _loadProjectAreas();
        setState(() {
          _areaController.text = areaName;
          _projectController.text = '';
          _projectCodeController.text = '';
          _selectedProjectName = null;
        });
        await _updateFilteredProjects(areaName);
        
        if (mounted) {
          _showSnackBar('專案區位新增成功');
        }
      } else {
        if (mounted) {
          _showSnackBar(response['message'] ?? '新增失敗');
          if (response['message'] == '區位已存在') {
            setState(() => _areaController.text = areaName);
            await _updateFilteredProjects(areaName);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('新增失敗: $e');
      }
    }
  }

  void _showProjectDialog() {
    if (_areaController.text.isEmpty) {
      _showSnackBar('請先選擇或添加專案區位');
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('選擇專案', style: TextStyle(fontSize: 20)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddProjectDialog();
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 300,
                      child: _loadingFilteredProjects
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredProjects.isEmpty
                              ? const Center(child: Text('此區位下沒有專案，請新增專案'))
                              : ListView.builder(
                                  itemCount: _filteredProjects.length,
                                  itemBuilder: (context, index) {
                                    final project = _filteredProjects[index];
                                    return Card(
                                      child: ListTile(
                                        title: Text(project['name'] ?? '未知專案'),
                                        subtitle: Text('代碼: ${project['code'] ?? '未知'}'),
                                        onTap: () {
                                          setState(() {
                                            _projectController.text = project['name'] ?? '';
                                            _projectCodeController.text = project['code'] ?? '';
                                            _selectedProjectName = project['name'];
                                          });
                                          Navigator.pop(context);
                                          _validateLocation();
                                        },
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddProjectDialog() {
    final newProjectNameController = TextEditingController();
    final addFormKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新增專案'),
          content: Form(
            key: addFormKey,
            child: TextFormField(
              controller: newProjectNameController,
              decoration: const InputDecoration(labelText: '新專案名稱'),
              validator: (value) => value!.isEmpty ? '請輸入專案名稱' : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (addFormKey.currentState!.validate()) {
                  Navigator.pop(context);
                  await _addProject(newProjectNameController.text);
                }
              },
              child: const Text('新增'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addProject(String projectName) async {
    setState(() => _isLoading = true);
    try {
      final response = await _projectService.addProject(projectName, _areaController.text);
      if (response['success'] == true) {
        final newProject = response['project'];
        
        // 追蹤新增的專案 code
        if (newProject['code'] != null) {
          _createdProjectCodes.add(newProject['code'] as String);
        }
        
        setState(() {
          _projectController.text = newProject['name'];
          _projectCodeController.text = newProject['code'];
          _selectedProjectName = newProject['name'];
        });
        await _updateFilteredProjects(_areaController.text);
        _validateLocation();
        _showSnackBar('專案 "$projectName" 新增成功');
      }
    } catch (e) {
      _showSnackBar('新增專案時連線錯誤: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 清理臨時新增的專案區位和專案
  Future<void> _performCleanup() async {
    if (_createdAreaIds.isEmpty && _createdProjectCodes.isEmpty) return;
    
    debugPrint('[ManualInputPageV3] 執行清理工作...');
    
    // 清理新增的專案區位
    for (var id in _createdAreaIds) {
      try {
        await _projectAreaService.deleteProjectArea(id);
        debugPrint('[ManualInputPageV3] 已刪除專案區位 ID: $id');
      } catch (e) {
        debugPrint('[ManualInputPageV3] 刪除專案區位失敗 (ID: $id): $e');
      }
    }
    
    // 清理新增的專案
    for (var code in _createdProjectCodes) {
      try {
        await _projectService.deleteProject(code);
        debugPrint('[ManualInputPageV3] 已刪除專案 Code: $code');
      } catch (e) {
        debugPrint('[ManualInputPageV3] 刪除專案失敗 (Code: $code): $e');
      }
    }
    
    debugPrint('[ManualInputPageV3] 清理工作完成');
  }

  @override
  void dispose() {
    // 如果沒有提交且新增了專案區位/專案，執行清理
    if (!_hasSubmitted && (_createdAreaIds.isNotEmpty || _createdProjectCodes.isNotEmpty)) {
      _performCleanup();
    }
    
    _projectController.dispose();
    _projectCodeController.dispose();
    _areaController.dispose();
    _speciesController.dispose();
    _dbhController.dispose();
    _heightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 如果新增了專案區位/專案但還沒提交，詢問是否要清理
        if (!_hasSubmitted && (_createdAreaIds.isNotEmpty || _createdProjectCodes.isNotEmpty)) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('確定要離開嗎？'),
              content: const Text('尚未儲存的資料將會遺失，且本次新增的臨時專案/區位將被刪除。確定要放棄嗎？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('放棄並離開'),
                ),
              ],
            ),
          );
          
          if (shouldPop == true) {
            await _performCleanup();
            return true;
          }
          return false;
        }
        return true;
      },
      child: Scaffold(
      appBar: AppBar(
        title: const Text('新增樹木 (V3)'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Stepper(
        type: StepperType.horizontal,
        currentStep: _currentStep,
        onStepContinue: _handleStepContinue,
        onStepCancel: _handleStepCancel,
        controlsBuilder: _buildControls,
        steps: [
          Step(
            title: const Text('位置'),
            content: _buildLocationStep(),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.editing,
          ),
          Step(
            title: const Text('樹種'),
            content: _buildSpeciesStep(),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.editing,
          ),
          Step(
            title: const Text('測量'),
            content: _buildMeasurementStep(),
            isActive: _currentStep >= 2,
            state: _currentStep > 2 ? StepState.complete : StepState.editing,
          ),
          Step(
            title: const Text('完成'),
            content: _buildFinalizeStep(),
            isActive: _currentStep >= 3,
            state: _currentStep > 3 ? StepState.complete : StepState.editing,
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildControls(BuildContext context, ControlsDetails details) {
    final isLastStep = _currentStep == 3;
    return Padding(
      padding: const EdgeInsets.only(top: 24.0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : details.onStepContinue,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(isLastStep ? '提交' : '下一步'),
            ),
          ),
          if (_currentStep > 0) ...[
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: details.onStepCancel,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('上一步'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _handleStepContinue() {
    if (_currentStep == 0) {
      // 檢查專案區位和專案名稱是否都已選擇
      if (_areaController.text.isEmpty || _projectController.text.isEmpty) {
        _showSnackBar('請選擇專案區位和專案名稱');
        return;
      }
      
      // 如果有選擇專案名稱，驗證位置
      if (_projectController.text.isNotEmpty && !_isLocationValid) {
        // 警告但允許繼續 (V3 原則：Validation Warning)
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('位置警告'),
            content: Text(_locationWarning ?? '位置不在專案邊界內'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('返回')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() => _currentStep++);
                },
                child: const Text('仍然繼續'),
              ),
            ],
          ),
        );
        return;
      }
    } else if (_currentStep == 1) {
      if (_speciesController.text.isEmpty) {
        _showSnackBar('請輸入或選擇樹種');
        return;
      }
    } else if (_currentStep == 2) {
      if (_dbhController.text.isEmpty) {
        _showSnackBar('請輸入胸徑 (DBH)');
        return;
      }
    } else if (_currentStep == 3) {
      _submitForm();
      return;
    }

    setState(() {
      if (_currentStep < 3) _currentStep++;
    });
  }

  void _handleStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  // === Step 1: Location & Project ===
  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentLocation != null)
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _currentLocation!,
                  zoom: 16,
                ),
                markers: {
                  Marker(
                    markerId: const MarkerId('current'),
                    position: _currentLocation!,
                  ),
                },
                myLocationEnabled: true,
                onTap: (pos) {
                  setState(() {
                    _currentLocation = pos;
                    _validateLocation();
                  });
                },
              ),
            ),
          )
        else
          Container(
            height: 200,
            color: Colors.grey.shade100,
            child: const Center(child: CircularProgressIndicator()),
          ),
        
        const SizedBox(height: 16),
        
        // 專案區位選擇（類似 V2）
        TextFormField(
          controller: _areaController,
          decoration: InputDecoration(
            labelText: '專案區位 *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.map),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: _showProjectAreaDialog,
            ),
          ),
          readOnly: true,
          onTap: _showProjectAreaDialog,
        ),
        
        const SizedBox(height: 16),
        
        // 專案名稱選擇（類似 V2）
        TextFormField(
          controller: _projectController,
          decoration: InputDecoration(
            labelText: '專案名稱 *',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.folder),
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: _areaController.text.isNotEmpty ? _showProjectDialog : null,
            ),
          ),
          readOnly: true,
          onTap: _areaController.text.isNotEmpty ? _showProjectDialog : () {
            _showSnackBar('請先選擇專案區位');
          },
        ),
        
        if (_locationWarning != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_locationWarning!, style: const TextStyle(color: Colors.orange, fontSize: 12))),
              ],
            ),
          ),
      ],
    );
  }

  // === Step 2: Species ===
  Widget _buildSpeciesStep() {
    return Column(
      children: [
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
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _identifySpeciesWithCamera,
              icon: _isIdentifying 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.camera_enhance),
              tooltip: '拍照辨識',
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
                  title: Text(species['name'] ?? ''),
                  subtitle: Text(
                    matchType == 'synonym' && matchedVariant != null
                        ? '同義: $matchedVariant | ${species['scientific_name'] ?? ''}'
                        : species['scientific_name'] ?? '',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    setState(() {
                      _speciesController.text = species['name'];
                      _speciesId = species['id']?.toString();
                      _speciesSearchResults.clear();
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
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
        _showSnackBar('新增樹種成功: $name');

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
        _showSnackBar('新增樹種失敗: ${response['message']}');
      }
    } catch (e) {
      _showSnackBar('新增樹種錯誤: $e');
    }
  }

  Future<void> _identifySpeciesWithCamera() async {
    setState(() => _isIdentifying = true);
    try {
      final File? image = await _imageService.captureImage();
      if (image == null) {
        setState(() => _isIdentifying = false);
        return;
      }
      
      // 添加到照片列表
      _photos.add(image);
      
      final result = await SpeciesIdentificationService.identifyFromFile(image, lang: 'zh');
      
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
            if (wasAutoAdded) {
              _allSpecies.add({
                'id': localMatch['id'],
                'name': localMatch['name'] ?? displayName,
                'scientific_name': localMatch['scientificName'] ?? speciesName,
              });
            }
          } else {
            // Fallback: 在本地列表匹配
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
              matchedId = match['id']?.toString() ?? match['樹種編號']?.toString();
            } catch (_) {
              // No match found
            }
          }

          // 構建提示訊息
          String snackMsg = '辨識成功: $displayName (信心度 $score%)';
          if (wasAutoAdded) {
            snackMsg += ' [新樹種已自動建檔]';
          } else if (matchedId != null) {
            snackMsg += ' [已匹配]';
          }

          setState(() {
            _speciesController.text = displayName;
            if (matchedId != null) {
              _speciesId = matchedId;
            }
            
            // [ML Data Collection]
            _autoIdentifiedSpeciesName = displayName;
            _autoIdentifiedSpeciesId = matchedId;
            _aiPredictions = results.cast<Map<String, dynamic>>();
            _speciesConfidence = score;
            _identificationImage = image;
          });
          _showSnackBar(snackMsg);
        }
      } else {
        _showSnackBar('辨識失敗: ${result['error']}');
      }
    } catch (e) {
      _showSnackBar('錯誤: $e');
    } finally {
      if (mounted) setState(() => _isIdentifying = false);
    }
  }

  // === Step 3: Measurements ===
  Widget _buildMeasurementStep() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _dbhController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '胸徑 (DBH) cm',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.circle_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _startARMeasurement,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal,
              ),
              child: const Column(
                children: [
                  Icon(Icons.view_in_ar),
                  Text('AR 測量', style: TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _heightController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '樹高 (m)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.height),
          ),
        ),
      ],
    );
  }

  Future<void> _startARMeasurement() async {
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (context) => ARDBHMeasurementPage(
          initialDbh: double.tryParse(_dbhController.text),
          speciesName: _speciesController.text,
          targetLat: _currentLocation?.latitude,
          targetLon: _currentLocation?.longitude,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _measuredDbh = result.diameterCm;
        _measurementConfidence = result.confidenceScore;
        _measurementMethod = result.method.name;
        _dbhController.text = result.diameterCm.toStringAsFixed(1);
      });

      // 如果尚未辨識樹種且有拍攝影像，自動進行樹種辨識
      if (_speciesController.text.isEmpty && result.capturedImagePath != null) {
        final imageFile = File(result.capturedImagePath!);
        if (await imageFile.exists()) {
          _identifySpeciesFromImage(imageFile);
        }
      }
    }
  }

  /// 從已有影像辨識樹種（DBH 測量照片複用）
  Future<void> _identifySpeciesFromImage(File image) async {
    setState(() => _isIdentifying = true);
    try {
      final result = await SpeciesIdentificationService.identifyFromFile(image, lang: 'zh');
      if (result['success'] == true && mounted) {
        final results = result['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final bestMatch = results.first;
          final speciesName = bestMatch['species']['scientificNameWithoutAuthor'];
          final commonNames = bestMatch['species']['commonNames'] as List?;
          final score = (bestMatch['score'] * 100).toStringAsFixed(1);
          String displayName = speciesName;
          if (commonNames != null && commonNames.isNotEmpty) displayName = commonNames.first;

          // 優先使用後端回傳的 localMatch（含自動新增結果）
          String? matchedId;
          final localMatch = result['localMatch'] as Map<String, dynamic>?;
          final wasAutoAdded = result['autoAdded'] == true;
          
          if (localMatch != null && localMatch['id'] != null) {
            matchedId = localMatch['id'].toString();
            if (wasAutoAdded) {
              _allSpecies.add({
                'id': localMatch['id'],
                'name': localMatch['name'] ?? displayName,
                'scientific_name': localMatch['scientificName'] ?? speciesName,
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
              matchedId = match['id']?.toString() ?? match['樹種編號']?.toString();
            } catch (_) {}
          }

          String snackMsg = '從量測照片辨識: $displayName (信心度 $score%)';
          if (wasAutoAdded) {
            snackMsg += ' [新樹種已自動建檔]';
          } else if (matchedId != null) {
            snackMsg += ' [已匹配]';
          }

          setState(() {
            _speciesController.text = displayName;
            if (matchedId != null) _speciesId = matchedId;
            _autoIdentifiedSpeciesName = displayName;
            _autoIdentifiedSpeciesId = matchedId;
            _aiPredictions = results.cast<Map<String, dynamic>>();
            _speciesConfidence = score;
            _identificationImage = image;
          });
          _showSnackBar(snackMsg);
        }
      }
    } catch (e) {
      debugPrint('從量測照片辨識樹種錯誤: $e');
    } finally {
      if (mounted) setState(() => _isIdentifying = false);
    }
  }

  // === Step 4 & 5: Finalize (Status, Notes, Photos) ===
  Widget _buildFinalizeStep() {
    return Column(
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
                if (selected) setState(() => _selectedStatus = status);
              },
            );
          }).toList(),
        ),
        
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '備註',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.note),
          ),
        ),
        
        const SizedBox(height: 16),
        
        const Text('照片記錄', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: Row(
            children: [
              // 拍照按鈕
              InkWell(
                onTap: _takeAdditionalPhoto,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: const Icon(Icons.add_a_photo, color: Colors.grey),
                ),
              ),
              const SizedBox(width: 8),
              // 照片列表
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_photos[index], width: 80, height: 80, fit: BoxFit.cover),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _takeAdditionalPhoto() async {
    final image = await _imageService.captureImage();
    if (image != null) {
      setState(() => _photos.add(image));
    }
  }

  Future<void> _submitForm() async {
    setState(() => _isLoading = true);
    
    try {
      // 1. 準備提交數據 (相容 V2 API)
      final treeData = {
        "project_name": _projectController.text.isNotEmpty ? _projectController.text : _selectedProjectName,
        "project_code": _projectCodeController.text,
        "project_area": _areaController.text,
        
        "species_name": _speciesController.text,
        "species_id": _speciesId, // Optional
        
        "x_coord": _currentLocation?.longitude ?? 0,
        "y_coord": _currentLocation?.latitude ?? 0,
        
        "dbh_cm": double.tryParse(_dbhController.text) ?? 0,
        "tree_height_m": double.tryParse(_heightController.text) ?? 0,
        
        "status": _selectedStatus,
        "note": _notesController.text,
        
        "survey_time": DateTime.now().toIso8601String(),
        
        // V3 額外元數據 (如果 API 支援)
        "v3_metadata": {
          "measurement_method": _measurementMethod ?? "manual",
          "confidence": _measurementConfidence,
          "is_ar_measured": _measurementMethod != null,
        }
      };
      
      // 2. 呼叫 API 創建樹木
      final response = await _treeService.createTreeV2(treeData);
      
      if (response['success'] == true) {
        // 標記為已提交，這樣 dispose 時就不會清理新增的專案/區位
        _hasSubmitted = true;
        
        final treeId = response['id'].toString(); // 假設回傳 ID
        
        // 3. 儲存照片 (關聯到新創建的 treeId)
        for (var photo in _photos) {
          await _imageService.saveMeasurementImage(
            treeId: treeId,
            image: photo,
            type: TreeImageType.overview, // 或區分照片類型
          );
        }

        // [ML Data Collection] 收集訓練數據
        // 1. AR 測量修正記錄
        if (_measuredDbh != null) {
          await MLDataCollector.recordARMeasurementModification(
            treeId: treeId,
            referenceObjectType: 'unknown',
            referenceActualSizeCm: 0,
            autoMeasuredDbh: _measuredDbh!,
            userModifiedDbh: double.tryParse(_dbhController.text) ?? 0,
            confidence: _measurementConfidence,
            metadata: {'method': _measurementMethod},
          );
        }

        // 2. 樹種辨識修正記錄
        if (_autoIdentifiedSpeciesName != null) {
          await MLDataCollector.recordSpeciesModification(
            treeId: treeId,
            autoIdentifiedSpeciesId: _autoIdentifiedSpeciesId ?? 'unknown',
            autoIdentifiedSpeciesName: _autoIdentifiedSpeciesName!,
            userSelectedSpeciesId: _speciesId ?? 'unknown',
            userSelectedSpeciesName: _speciesController.text,
            confidence: _speciesConfidence != null ? double.tryParse(_speciesConfidence!)! / 100.0 : null,
            topPredictions: _aiPredictions,
            imagePath: _identificationImage?.path,
          );
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新增成功!')));
          Navigator.pop(context, true); // 返回成功
        }
      } else {
        throw Exception(response['message'] ?? '提交失敗');
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('錯誤: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
