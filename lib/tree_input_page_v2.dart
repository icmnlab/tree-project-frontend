import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:convert';
import 'utils/location_helper.dart';

// Import services
import 'services/tree_service.dart';
import 'services/project_service.dart';
import 'services/project_area_service.dart';
import 'services/location_service.dart';
import 'services/species_service.dart';
import 'services/v3/project_boundary_service.dart'; // V3: 專案邊界驗證

// 定義日誌函數
void logDebug(String message) {
  assert(() {
    debugPrint('TreeAppV2: $message');
    return true;
  }());
}

// 創建碳儲存量計算函數 (kg CO2-eq)
double calculateCarbonStorage(double dbh) {
  if (dbh <= 0) return 0;
  double aboveGroundBiomass = exp(-2.48 + 2.4835 * log(dbh));
  double totalBiomass = 1.24 * aboveGroundBiomass;
  double carbonContent = 0.50 * totalBiomass;
  return carbonContent * 3.67; // 碳儲存量 (kg CO2-eq)
}

// 創建年碳吸存量計算函數 (kg CO2-eq/yr)
double calculateCarbonSequestration(
    double carbonStorage, double? growthFactor) {
  return carbonStorage * (growthFactor ?? 0.03);
}

class TreeInputPageV2 extends StatefulWidget {
  final Map<String, dynamic>? treeData;
  final bool isEdit;

  const TreeInputPageV2({super.key, this.treeData, this.isEdit = false});

  @override
  State<TreeInputPageV2> createState() => _TreeInputPageV2State();
}

class _TreeInputPageV2State extends State<TreeInputPageV2> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isLoading = false;
  // ignore: unused_field
  String _locationError = ''; // Reserved for future location error handling
  bool _autoCalculateEnabled = true;

  bool _isEditing = false;
  Map<String, dynamic>? _currentTreeData;
  
  // Cleanup Tracking - 追蹤本次 session 新增的專案區位、專案和樹種，以便在退出時清理
  final List<int> _createdAreaIds = [];
  final List<String> _createdProjectCodes = [];
  final List<String> _createdSpeciesIds = []; // 追蹤新增的樹種 ID
  bool _hasSubmitted = false; // 是否已成功提交樹木資料

  // Services
  final TreeService _treeService = TreeService();
  final ProjectService _projectService = ProjectService();
  final ProjectAreaService _projectAreaService = ProjectAreaService();
  final LocationService _locationService = LocationService();
  final TreeSpeciesService _speciesService = TreeSpeciesService();

  // Data Lists
  List<Map<String, dynamic>> _speciesList = [];
  bool _loadingSpecies = false;
  // ignore: unused_field
  List<Map<String, dynamic>> _projectList = []; // Reserved for project list caching
  List<Map<String, dynamic>> _projectAreas = [];
  bool _loadingAreas = false;
  List<Map<String, dynamic>> _filteredProjects = [];
  bool _loadingFilteredProjects = false;
  List<Map<String, dynamic>> _commonSpecies = [];
  bool _loadingCommonSpecies = false;

  // Controllers
  final projectAreaController = TextEditingController();
  final projectCodeController = TextEditingController();
  final projectNameController = TextEditingController();
  // V2: ID 由後端生成，這裡只作顯示用
  final systemTreeController = TextEditingController(text: '提交後自動生成');
  final projectTreeController = TextEditingController(text: '提交後自動生成');
  final treeIdController = TextEditingController();
  final treeNameController = TextEditingController();
  final xCoordController = TextEditingController();
  final yCoordController = TextEditingController();
  final statusController = TextEditingController(text: '正常'); // Default status
  final noteController = TextEditingController(text: '無');
  final treeRemarkController = TextEditingController(text: '無');
  final treeHeightController = TextEditingController();
  final dbhController = TextEditingController();
  final surveyRemarkController = TextEditingController();
  DateTime surveyTime = DateTime.now();
  final carbonstorageController = TextEditingController();
  final annualcarbonController = TextEditingController();

  // 常見狀態列表 (增強功能)
  final List<String> _commonStatuses = [
    '正常',
    '枯死',
    '病蟲害',
    '傾斜',
    '斷梢',
    '空洞',
    '其他'
  ];

  @override
  void initState() {
    super.initState();

    _isEditing = widget.isEdit;
    _currentTreeData = widget.treeData;

    _loadSpeciesList();
    _loadProjectList();
    _loadProjectAreas();

    projectCodeController.addListener(_onProjectCodeChanged);

    if (_isEditing && _currentTreeData != null) {
      _populateFormWithData(_currentTreeData!);
    }

    treeHeightController.addListener(_updateCarbonCalculations);
    dbhController.addListener(_updateCarbonCalculations);
  }

  void _populateFormWithData(Map<String, dynamic> data) {
    Map<String, String> keyMapping = {
      'project_location': '專案區位',
      'project_code': '專案代碼',
      'project_name': '專案名稱',
      'system_tree_id': '系統樹木',
      'project_tree_id': '專案樹木',
      'species_id': '樹種編號',
      'species_name': '樹種名稱',
      'x_coord': 'X坐標',
      'y_coord': 'Y坐標',
      'status': '狀況',
      'note': '註記',
      'tree_remark': '樹木備註',
      'tree_height_m': '樹高（公尺）',
      'dbh_cm': '胸徑（公分）',
      'survey_remark': '調查備註',
      'survey_time': '調查時間',
      'carbon_storage': '碳儲存量',
      'carbon_sequestration_per_year': '推估年碳吸存量',
      'id': 'id'
    };

    dynamic getValue(String backendKey) {
      return data[backendKey] ?? data[keyMapping[backendKey]];
    }

    projectAreaController.text = getValue('project_location')?.toString() ?? '';
    projectCodeController.text = getValue('project_code')?.toString() ?? '';
    projectNameController.text = getValue('project_name')?.toString() ?? '';
    systemTreeController.text = getValue('system_tree_id')?.toString() ?? '';
    projectTreeController.text = getValue('project_tree_id')?.toString() ?? '';
    treeIdController.text = getValue('species_id')?.toString() ?? '';
    treeNameController.text = getValue('species_name')?.toString() ?? '';
    xCoordController.text = getValue('x_coord')?.toString() ?? '0';
    yCoordController.text = getValue('y_coord')?.toString() ?? '0';
    statusController.text = getValue('status')?.toString() ?? '正常';
    noteController.text = getValue('note')?.toString() ?? '無';
    treeRemarkController.text = getValue('tree_remark')?.toString() ?? '無';
    treeHeightController.text = getValue('tree_height_m')?.toString() ?? '0';
    dbhController.text = getValue('dbh_cm')?.toString() ?? '0';
    surveyRemarkController.text = getValue('survey_remark')?.toString() ?? '';
    carbonstorageController.text =
        getValue('carbon_storage')?.toString() ?? '0';
    annualcarbonController.text =
        getValue('carbon_sequestration_per_year')?.toString() ?? '0';

    final surveyTimeString = getValue('survey_time');
    if (surveyTimeString != null) {
      try {
        surveyTime = DateTime.parse(surveyTimeString.toString());
      } catch (e) {
        surveyTime = DateTime.now();
      }
    }
  }

  void _onProjectCodeChanged() {
    if (!_isEditing && projectCodeController.text.isNotEmpty) {
      _loadCommonSpecies();
    }
  }

  void _updateCarbonCalculations() {
    if (!_autoCalculateEnabled) return;

    try {
      double height = double.tryParse(treeHeightController.text) ?? 0.0;
      double dbh = double.tryParse(dbhController.text) ?? 0.0;

      if (height > 0 && dbh > 0) {
        double carbonStorage = calculateCarbonStorage(dbh);
        double annualCarbon = calculateCarbonSequestration(carbonStorage, null);

        carbonstorageController.text = carbonStorage.toStringAsFixed(2);
        annualcarbonController.text = annualCarbon.toStringAsFixed(2);
      }
    } catch (e) {
      logDebug('碳計算錯誤: $e');
    }
  }

  bool _cleanupPerformed = false;
  
  // 清理臨時新增的專案區位、專案和樹種
  Future<void> _performCleanup() async {
    if (_cleanupPerformed) return;
    if (_createdAreaIds.isEmpty && _createdProjectCodes.isEmpty && _createdSpeciesIds.isEmpty) return;
    _cleanupPerformed = true;
    
    debugPrint('[TreeInputPageV2] 執行清理工作...');
    
    for (var id in _createdAreaIds) {
      try {
        await _projectAreaService.deleteProjectArea(id);
        debugPrint('[TreeInputPageV2] 已刪除專案區位 ID: $id');
      } catch (e) {
        debugPrint('[TreeInputPageV2] 刪除專案區位失敗 (ID: $id): $e');
      }
    }
    
    for (var code in _createdProjectCodes) {
      try {
        await _projectService.deleteProject(code);
        debugPrint('[TreeInputPageV2] 已刪除專案 Code: $code');
      } catch (e) {
        debugPrint('[TreeInputPageV2] 刪除專案失敗 (Code: $code): $e');
      }
    }
    
    if (_createdSpeciesIds.isNotEmpty) {
      try {
        await _treeService.cleanupTemporaryData();
        debugPrint('[TreeInputPageV2] 已觸發清理未使用的樹種');
      } catch (e) {
        debugPrint('[TreeInputPageV2] 清理樹種失敗: $e');
      }
    }
    
    _createdAreaIds.clear();
    _createdProjectCodes.clear();
    _createdSpeciesIds.clear();
    debugPrint('[TreeInputPageV2] 清理工作完成');
  }

  @override
  void dispose() {
    // 如果沒有提交且新增了專案區位/專案/樹種，執行清理
    if (!_hasSubmitted && (_createdAreaIds.isNotEmpty || _createdProjectCodes.isNotEmpty || _createdSpeciesIds.isNotEmpty)) {
      _performCleanup();
    }
    
    treeHeightController.removeListener(_updateCarbonCalculations);
    dbhController.removeListener(_updateCarbonCalculations);
    projectCodeController.removeListener(_onProjectCodeChanged);
    projectAreaController.dispose();
    projectCodeController.dispose();
    projectNameController.dispose();
    systemTreeController.dispose();
    projectTreeController.dispose();
    treeIdController.dispose();
    treeNameController.dispose();
    xCoordController.dispose();
    yCoordController.dispose();
    statusController.dispose();
    noteController.dispose();
    treeRemarkController.dispose();
    treeHeightController.dispose();
    dbhController.dispose();
    surveyRemarkController.dispose();
    carbonstorageController.dispose();
    annualcarbonController.dispose();
    super.dispose();
  }

  Future<void> submitData() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請檢查表單填寫是否完整')),
        );
      }
      return;
    }

    // V3: 驗證座標是否在專案邊界內
    final projectName = projectNameController.text;
    final lat = double.tryParse(yCoordController.text);
    final lng = double.tryParse(xCoordController.text);
    
    if (projectName.isNotEmpty && lat != null && lng != null && lat != 0 && lng != 0) {
      final boundaryService = ProjectBoundaryService();
      // 確保已載入邊界資料
      await boundaryService.getAllBoundaries();
      
      final validation = boundaryService.validateCoordinateForProject(
        projectName: projectName,
        lat: lat,
        lng: lng,
      );
      
      if (!validation.isValid) {
        if (mounted) {
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('座標驗證警告'),
                ],
              ),
              content: Text(
                '${validation.message}\n\n'
                '您仍然可以選擇繼續提交，但這棵樹的位置可能需要重新確認。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('返回修改'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: const Text('仍然提交'),
                ),
              ],
            ),
          );
          
          if (shouldContinue != true) {
            return;
          }
        }
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 準備 V2 提交數據
      // 編輯模式：project_code 直接傳（不做 int parse 避免破壞關聯）
      // 新增模式：沿用原邏輯（後端 create controller 會處理）
      final rawProjectCode = projectCodeController.text;
      final projectCode = _isEditing
          ? rawProjectCode
          : (int.tryParse(rawProjectCode.replaceAll('PRJ-', '')) ?? 0).toString();
      
      final treeData = {
        "project_area": projectAreaController.text,
        "project_code": projectCode,
        "project_name": projectNameController.text,

        "species_id": treeIdController.text,
        "species_name": treeNameController.text,
        "x_coord": double.tryParse(xCoordController.text) ?? 0,
        "y_coord": double.tryParse(yCoordController.text) ?? 0,

        "status": statusController.text,
        "note": noteController.text.isEmpty ? null : noteController.text,
        "tree_remark":
            treeRemarkController.text.isEmpty ? null : treeRemarkController.text,

        "tree_height_m": double.tryParse(treeHeightController.text) ?? 0,
        "dbh_cm": double.tryParse(dbhController.text) ?? 0,

        "survey_notes": surveyRemarkController.text,

        "survey_time": surveyTime.toIso8601String(),

        "carbon_storage": double.tryParse(carbonstorageController.text) ?? 0,
        "carbon_sequestration_per_year":
            double.tryParse(annualcarbonController.text) ?? 0,
      };

      logDebug('提交 V2 單筆數據: ${jsonEncode(treeData)}');

      Map<String, dynamic> response;
      if (_isEditing) {
        // 編輯模式：使用 V2 Update API
        response = await _treeService.updateTreeV2(
            _currentTreeData!['id'].toString(), treeData);
      } else {
        // 新增模式：呼叫 V2 Create API
        response = await _treeService.createTreeV2(treeData);
      }

      if (!mounted) return;

      if (response['success'] == true) {
        logDebug('請求成功，返回數據: $response');
        
        // 標記為已提交，這樣 dispose 時就不會清理新增的專案/區位
        _hasSubmitted = true;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? '更新成功!' : '新增成功 (V2)!')),
        );

        // 回傳資料給上層頁面更新列表
        // 這裡補上後端回傳的生成 ID
        if (!_isEditing) {
          treeData['id'] = response['id'];
          treeData['system_tree_id'] = response['system_tree_id'];
          treeData['project_tree_id'] = response['project_tree_id'];
        }
        Navigator.pop(context, treeData);
      } else {
        String errorMsg = response['message'] ?? '伺服器錯誤';
        logDebug('請求失敗: $errorMsg');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      logDebug('請求過程中發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('連線錯誤: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    // ... (Location logic same as V1)
    setState(() {
      _isLoading = true;
      _locationError = '';
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _isLoading = false;
            _locationError = '需要位置權限才能獲取當前位置';
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _isLoading = false;
          _locationError = '位置權限被永久拒絕，請在設定中開啟';
        });
        return;
      }

      final position = await getHighAccuracyPosition();
      if (position == null) {
        setState(() {
          _isLoading = false;
          _locationError = '無法獲取位置';
        });
        return;
      }

      if (!mounted) return;

      if (projectAreaController.text.isNotEmpty) {
        final response = await _locationService.validateLocation(
            area: projectAreaController.text,
            latitude: position.latitude,
            longitude: position.longitude);

        if (response['isValid'] == false) {
          final suggestResponse = await _locationService.suggestArea(
              latitude: position.latitude, longitude: position.longitude);
          String suggestedArea = '';
          if (suggestResponse['success'] == true) {
            suggestedArea = suggestResponse['suggestedArea'];
          }
          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('位置警告'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '您的位置（${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}）'
                      '不在${projectAreaController.text}的合理範圍內。',
                    ),
                    if (suggestedArea.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '建議的專案區位：$suggestedArea',
                        style: const TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text('是否仍要使用此位置？'),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _isLoading = false;
                        _locationError = '請選擇正確的專案區位或重新定位';
                      });
                    },
                    child: const Text('取消'),
                  ),
                  if (suggestedArea.isNotEmpty)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          projectAreaController.text = suggestedArea;
                          _updateFilteredProjects(suggestedArea);
                          _isLoading = false;
                        });
                      },
                      child: const Text('使用建議區位'),
                    ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        xCoordController.text = position.longitude.toString();
                        yCoordController.text = position.latitude.toString();
                        _isLoading = false;
                      });
                    },
                    child: const Text('使用此位置'),
                  ),
                ],
              ),
            );
          }
          return;
        }
      }

      setState(() {
        xCoordController.text = position.longitude.toString();
        yCoordController.text = position.latitude.toString();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _locationError = e.toString();
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('無法獲取位置：$e')),
      );
    }
  }

  // UI Helpers with Teal Theme (V2)
  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String? Function(String?)? validator, {
    TextInputType? keyboardType,
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.teal),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.teal.shade600, width: 2),
          ),
          filled: true,
          fillColor: readOnly ? Colors.grey.shade200 : Colors.teal.shade50,
        ),
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  // V2: 增強版狀態選擇器
  Widget _buildStatusField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '狀況',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _commonStatuses.map((status) {
              final isSelected = statusController.text == status;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(status),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        statusController.text = status;
                        if (status == '其他') {
                          statusController.clear();
                        }
                      }
                    });
                  },
                  selectedColor: Colors.teal.shade100,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.teal.shade900 : Colors.black,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: statusController,
          decoration: InputDecoration(
            labelText: '狀況描述',
            hintText: '選擇上方標籤或手動輸入',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.teal),
            ),
            filled: true,
            fillColor: Colors.teal.shade50,
            suffixIcon: statusController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        statusController.clear();
                      });
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {}); // Trigger rebuild for chip selection state
          },
          validator: (value) => (value?.isEmpty ?? true) ? '請輸入狀況' : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // Reuse logic for Carbon, Species, Project... (Using V2 Theme)
  // ... (Due to token limits, I'll implement the essential structure and reuse V1 logic concept)

  // Species Selector (V2: Teal Theme)
  Widget _buildTreeSpeciesSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('選擇樹種',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_loadingCommonSpecies)
          const Center(child: CircularProgressIndicator())
        else if (_commonSpecies.isNotEmpty) ...[
          const Text('專案常見樹種',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            children: _commonSpecies.map((species) {
              return ActionChip(
                label: Text(species['樹種名稱']),
                onPressed: () => _onSpeciesSelected(species),
                backgroundColor: Colors.teal.shade50,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('樹種名稱',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showEnhancedSpeciesDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.teal.shade200),
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.teal.shade50,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        treeNameController.text.isEmpty
                            ? '點擊選擇或搜尋樹種'
                            : treeNameController.text,
                        style: TextStyle(
                          color: treeNameController.text.isEmpty
                              ? Colors.grey
                              : Colors.black,
                        ),
                      ),
                    ),
                    const Icon(Icons.search, color: Colors.teal),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _loadSpeciesList() async {
    setState(() => _loadingSpecies = true);
    try {
      _speciesList = await _speciesService.getSpecies();
    } catch (e) {
      logDebug('載入樹種列表錯誤: $e');
    } finally {
      setState(() => _loadingSpecies = false);
    }
  }

  Future<void> _loadProjectList() async {
    // ...
  }

  Future<void> _loadProjectAreas() async {
    setState(() => _loadingAreas = true);
    try {
      _projectAreas = await _projectAreaService.getProjectAreas();
    } catch (e) {
      logDebug('載入專案區位列表錯誤: $e');
    } finally {
      setState(() => _loadingAreas = false);
    }
  }

  void _onSpeciesSelected(Map<String, dynamic> species) {
    setState(() {
      if (species.containsKey('樹種編號')) {
        treeIdController.text = species['樹種編號'].toString();
        treeNameController.text = species['樹種名稱'].toString();
      } else {
        treeIdController.text = species['id'].toString();
        treeNameController.text = species['name'].toString();
      }
    });
  }

  Future<void> _updateFilteredProjects(String area) async {
    setState(() {
      _loadingFilteredProjects = true;
      _filteredProjects = [];
    });
    try {
      final response = await _projectService.getProjectsByArea(area);
      if (response['success'] == true && response['data'] != null) {
        _filteredProjects = List<Map<String, dynamic>>.from(response['data']);
      } else {
        _filteredProjects = [];
      }
    } catch (e) {
      logDebug('載入專案列表錯誤: $e');
    } finally {
      setState(() => _loadingFilteredProjects = false);
    }
  }

  Future<void> _loadCommonSpecies() async {
    if (projectCodeController.text.isEmpty) return;
    setState(() => _loadingCommonSpecies = true);
    try {
      final response =
          await _treeService.getCommonSpecies(projectCodeController.text);
      setState(() => _commonSpecies = response);
    } catch (e) {
      logDebug('載入專案常見樹種錯誤: $e');
    } finally {
      setState(() => _loadingCommonSpecies = false);
    }
  }

  // [V2 NEW] 新增樹種的邏輯
  Future<void> _addSpecies(String name) async {
    try {
      final response = await _speciesService.addSpecies(name);
      if (!mounted) return;

      if (response['success'] == true) {
        // 追蹤新增的樹種 ID，以便退出時清理
        if (response['id'] != null) {
          _createdSpeciesIds.add(response['id'] as String);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增樹種成功: $name')),
        );

        // 創建新的樹種 Map
        final newSpecies = {
          'id': response['id'],
          'name': response['name'],
        };

        // 更新本地樹種列表緩存並選中它
        setState(() {
          _speciesList.add(newSpecies);
          _speciesList.sort((a, b) => a['name'].compareTo(b['name']));
        });
        _onSpeciesSelected(newSpecies);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增樹種失敗: ${response['message']}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增樹種錯誤: $e')),
      );
    }
  }

  // [V2 NEW] 顯示新增樹種的對話框
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
                  Navigator.of(context).pop(); // Close the add dialog
                  await _addSpecies(nameController.text);
                }
              },
            ),
          ],
        );
      },
    );
  }

  // Dialogs (Project Area, Project, Species) - reusing logic but with V2 theme
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
                                projectAreaController.text =
                                    area['area_name'] ?? '';
                                projectNameController.text = '';
                                projectCodeController.text = '';
                                _updateFilteredProjects(
                                    area['area_name'] ?? '');
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
                    _addProjectArea(areaController.text);
                    Navigator.pop(context);
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
        // 優化：先嘗試獲取最後已知位置，避免等待
        position = await Geolocator.getLastKnownPosition();
        
        // 如果沒有最後位置，則嘗試獲取當前位置，但設定超時
        if (position == null) {
          position = await getHighAccuracyPosition(timeout: const Duration(seconds: 3));
        }
      } catch (e) {
        logDebug('獲取位置失敗 (非致命): $e');
        // 位置獲取失敗不應阻止新增區位
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
        // 追蹤新增的專案區位 ID，以便退出時清理
        if (response['data'] != null && response['data']['id'] != null) {
          _createdAreaIds.add(response['data']['id'] as int);
        }
        
        await _loadProjectAreas();
        projectAreaController.text = areaName;
        // 清空相關欄位
        projectNameController.text = '';
        projectCodeController.text = '';
        _filteredProjects = [];
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('專案區位新增成功')),
          );
        }
      } else {
        // 處理後端返回的業務錯誤 (例如區位已存在)
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response['message'] ?? '新增失敗')),
          );
          
          // 如果區位已存在，或許我們應該直接選中它？
          if (response['message'] == '區位已存在') {
             projectAreaController.text = areaName;
             // 重新載入該區位的專案
             _updateFilteredProjects(areaName);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增失敗: $e')),
        );
      }
    }
  }

  void _showProjectDialog() {
    if (projectAreaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇或添加專案區位')),
      );
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
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.teal),
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
                                        subtitle: Text(
                                            '代碼: ${project['code'] ?? '未知'}'),
                                        onTap: () async {
                                          setState(() {
                                            projectNameController.text =
                                                project['name'] ?? '';
                                            projectCodeController.text =
                                                project['code'] ?? '';
                                          });
                                          Navigator.pop(context);
                                          if (projectCodeController
                                              .text.isNotEmpty) {
                                            await _loadCommonSpecies();
                                          }
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
                child: const Text('取消')),
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
      final response = await _projectService.addProject(
          projectName, projectAreaController.text);
      if (response['success'] == true) {
        final newProject = response['project'];
        
        // 追蹤新增的專案 code，以便退出時清理
        if (newProject['code'] != null) {
          _createdProjectCodes.add(newProject['code'] as String);
        }
        
        setState(() {
          projectNameController.text = newProject['name'];
          projectCodeController.text = newProject['code'];
        });
        await _updateFilteredProjects(projectAreaController.text);
        await _loadCommonSpecies();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('專案 "$projectName" 新增成功')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增專案時連線錯誤: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showEnhancedSpeciesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController searchController = TextEditingController();
        List<Map<String, dynamic>> filteredList = List.from(_speciesList);
        bool showNoResults = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void filterSpecies(String query) {
              setDialogState(() {
                if (query.isEmpty) {
                  filteredList = List.from(_speciesList);
                  showNoResults = false;
                } else {
                  String normalizedQuery = query.toLowerCase();
                  filteredList = _speciesList.where((species) {
                    String name = species['name'].toString().toLowerCase();
                    return name.contains(normalizedQuery);
                  }).toList();
                  showNoResults = filteredList.isEmpty;
                }
              });
            }

            return AlertDialog(
              title: const Text('選擇或搜尋樹種'),
              content: SizedBox(
                width: double.maxFinite,
                height: MediaQuery.of(context).size.height * 0.6,
                child: Column(
                  children: [
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: '輸入樹種名稱關鍵字',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  searchController.clear();
                                  filterSpecies('');
                                },
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: filterSpecies,
                    ),
                    const SizedBox(height: 16),
                    if (_loadingSpecies)
                      const Center(child: CircularProgressIndicator())
                    else if (showNoResults) ...[
                      const Expanded(
                        child: Center(
                          child: Text('沒有找到符合的樹種',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text('新增樹種: ${searchController.text}'),
                        onPressed: () {
                          Navigator.pop(context); // Close search dialog
                          _showAddSpeciesDialog(searchController.text);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16), // Add some spacing
                    ] else
                      Expanded(
                        child: ListView.builder(
                          itemCount: filteredList.length,
                          itemBuilder: (context, index) {
                            final species = filteredList[index];
                            return ListTile(
                              title: Text(species['name']),
                              subtitle: Text('編號: ${species['id']}'),
                              onTap: () {
                                _onSpeciesSelected(species);
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
              ],
            );
          },
        );
      },
    );
  }

  // Build Methods
  Widget _buildProjectAreaField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('專案區位',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: projectAreaController,
          readOnly: true,
          decoration: InputDecoration(
            hintText: '請選擇專案區位',
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: _showProjectAreaDialog,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.teal.shade50,
          ),
          validator: (value) => value?.isEmpty ?? true ? '請選擇專案區位' : null,
        ),
      ],
    );
  }

  Widget _buildProjectNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('專案名稱',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: projectNameController,
          readOnly: true,
          decoration: InputDecoration(
            hintText: '請選擇專案名稱',
            suffixIcon: IconButton(
              icon: const Icon(Icons.arrow_drop_down),
              onPressed: _showProjectDialog,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.teal.shade50,
          ),
          validator: (value) => value?.isEmpty ?? true ? '請選擇專案名稱' : null,
        ),
      ],
    );
  }

  Widget _buildCarbonFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('碳儲存計算',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Switch(
              value: _autoCalculateEnabled,
              onChanged: (value) {
                setState(() {
                  _autoCalculateEnabled = value;
                  if (value) {
                    _updateCarbonCalculations();
                  }
                });
              },
              activeColor: Colors.teal[700],
            ),
            Text(_autoCalculateEnabled ? '自動' : '手動',
                style: TextStyle(color: Colors.grey[700])),
          ],
        ),
        const SizedBox(height: 8),
        _buildTextField(
          carbonstorageController,
          '碳儲存量 (kg)',
          (value) => value?.isEmpty ?? true ? '請輸入碳儲存量' : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),
        _buildTextField(
          annualcarbonController,
          '推估年碳吸存量 (kg)',
          (value) => value?.isEmpty ?? true ? '請輸入推估年碳吸存量' : null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }

  List<Step> getSteps() {
    return [
      Step(
        title: const Text('基本資訊'),
        content: Column(
          children: [
            _buildProjectAreaField(),
            const SizedBox(height: 16),
            _buildProjectNameField(),
            const SizedBox(height: 16),
            _buildTextField(projectCodeController, '專案代碼', null,
                readOnly: true),
            const SizedBox(height: 16),
            const Text(
              '編號將由系統在提交時自動生成',
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: const Text('樹木資訊'),
        content: Column(
          children: [
            _buildTreeSpeciesSelector(),
            const SizedBox(height: 16),
            _buildTextField(treeIdController, '樹種編號', null),
            _buildTextField(treeNameController, '樹種名稱',
                (v) => v!.isEmpty ? '請輸入樹種名稱' : null),
          ],
        ),
        isActive: _currentStep >= 1,
      ),
      Step(
        title: const Text('位置資訊'),
        content: Column(
          children: [
            Row(
              children: [
                Expanded(
                    child: _buildTextField(xCoordController, 'X坐標 (經度)', null,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true))),
                const SizedBox(width: 8),
                Expanded(
                    child: _buildTextField(yCoordController, 'Y坐標 (緯度)', null,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true))),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _getCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('使用目前位置'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, foregroundColor: Colors.white),
            ),
          ],
        ),
        isActive: _currentStep >= 2,
      ),
      Step(
        title: const Text('狀態與測量'),
        content: Column(
          children: [
            _buildStatusField(),
            _buildTextField(treeHeightController, '樹高 (m)', null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _buildTextField(dbhController, '胸徑 (cm)', null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            _buildTextField(noteController, '註記', null),
            _buildTextField(treeRemarkController, '樹木備註', null),
            _buildTextField(surveyRemarkController, '調查備註', null),
          ],
        ),
        isActive: _currentStep >= 3,
      ),
      Step(
        title: const Text('碳計算'),
        content: _buildCarbonFields(),
        isActive: _currentStep >= 4,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 如果新增了專案區位/專案/樹種但還沒提交，詢問是否要清理
        if (!_hasSubmitted && (_createdAreaIds.isNotEmpty || _createdProjectCodes.isNotEmpty || _createdSpeciesIds.isNotEmpty)) {
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
        title: Text(_isEditing ? '編輯樹木 (V2)' : '新增樹木 (V2)'),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal.shade600, Colors.teal.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 4,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade50, Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
                    ),
                    const SizedBox(height: 16),
                    Text('載入中...', style: TextStyle(color: Colors.teal.shade700)),
                  ],
                ),
              )
          : Form(
              key: _formKey,
              child: Stepper(
                type: StepperType.vertical,
                currentStep: _currentStep,
                onStepContinue: () {
                  if (_currentStep < getSteps().length - 1) {
                    setState(() => _currentStep++);
                  } else {
                    submitData();
                  }
                },
                onStepCancel: () {
                  if (_currentStep > 0) {
                    setState(() => _currentStep--);
                  }
                },
                controlsBuilder: (context, details) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.teal.shade400, Colors.teal.shade600],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.teal.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: details.onStepContinue,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: Text(_currentStep == getSteps().length - 1
                                ? '提交 (V2)'
                                : '下一步'),
                          ),
                        ),
                        if (_currentStep > 0) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: details.onStepCancel,
                            child: const Text('上一步'),
                          ),
                        ],
                      ],
                    ),
                  );
                },
                steps: getSteps(),
              ),
            ),
        ),
      ),
    );
  }
}
