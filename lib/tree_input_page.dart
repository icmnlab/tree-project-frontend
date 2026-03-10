import 'package:flutter/material.dart';
import 'constants/colors.dart';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:file_picker/file_picker.dart';
import 'utils/location_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:math';
import 'dart:async';

// Import services
import 'services/tree_service.dart';
import 'services/project_service.dart';
import 'services/project_area_service.dart';
import 'services/location_service.dart';
import 'services/species_service.dart';

/// 生成安全的備用 ID（用時間戳避免碰撞，比隨機數安全）
int _generateSafeFallbackId() {
  final now = DateTime.now();
  // 用時分秒毫秒組成 6 位數字，比 4 位隨機數碰撞機率低很多
  return (now.hour * 100000) + (now.minute * 1000) + (now.second * 10) + (now.millisecond ~/ 100) + 100000;
}

// 定義日誌函數，方便後續替換 print
void logDebug(String message) {
  // 在生產環境下可以禁用，或使用正式的日誌庫
  assert(() {
    debugPrint('TreeApp: $message');
    return true;
  }());
}

// 比較可信的碳計算公式：
// 步驟一：計算地上部生物量（AGB）：AGB = e^(−2.48+2.4835×ln(DBH))
// 步驟二：計算總生物量（TB）：TB = 1.24 × AGB
// 步驟三：計算碳儲存量（kgC）：碳儲存量 = 0.50 × TB
// 步驟四：轉換為 CO₂ 當量：碳儲存量(kgCO2−eq) = 碳儲存量(kgC) × 3.67
// 步驟五：計算年碳吸存量（kg CO₂-eq/yr）：年碳吸存量 = 碳儲存量(kgCO2−eq) × 生長率因子

// 創建碳儲存量計算函數 (kg CO2-eq)
double calculateCarbonStorage(double dbh) {
  // 步驟一：計算地上部生物量
  double aboveGroundBiomass = exp(-2.48 + 2.4835 * log(dbh));

  // 步驟二：計算總生物量
  double totalBiomass = 1.24 * aboveGroundBiomass;

  // 步驟三：計算碳含量：C = 0.50 × TB
  double carbonContent = 0.50 * totalBiomass;

  // 步驟四：轉換為 CO₂ 當量
  return carbonContent * 3.67; // 碳儲存量 (kg CO2-eq)
}

// 創建年碳吸存量計算函數 (kg CO2-eq/yr)
double calculateCarbonSequestration(
    double carbonStorage, double? growthFactor) {
  // 根據樹種生長速度選擇生長率因子：
  // 快速成長樹種：4%
  // 一般生長速度樹種：2%
  // 緩慢生長樹種：1%
  // 預設值為3% (0.03)
  return carbonStorage * (growthFactor ?? 0.03);
}

class TreeInputPage extends StatefulWidget {
  final Map<String, dynamic>? treeData;
  final bool isEdit;

  const TreeInputPage({super.key, this.treeData, this.isEdit = false});

  @override
  State<TreeInputPage> createState() => _TreeInputPageState();
}

class _TreeInputPageState extends State<TreeInputPage> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;
  bool _isLoading = false;
  String _locationError = '';
  bool _autoCalculateEnabled = true;

  // New state variables to manage editing state
  bool _isEditing = false;
  Map<String, dynamic>? _currentTreeData;

  // Services
  final TreeService _treeService = TreeService();
  final ProjectService _projectService = ProjectService();
  final ProjectAreaService _projectAreaService = ProjectAreaService();
  final LocationService _locationService = LocationService();
  final TreeSpeciesService _speciesService = TreeSpeciesService();

  // 樹種列表
  List<Map<String, dynamic>> _speciesList = [];
  bool _loadingSpecies = false;

  // 專案列表
  List<Map<String, dynamic>> _projectList = [];

  // 新增專案區位列表
  List<Map<String, dynamic>> _projectAreas = [];
  bool _loadingAreas = false;

  // 新增專案列表（根據選擇的區位過濾）
  List<Map<String, dynamic>> _filteredProjects = [];
  bool _loadingFilteredProjects = false;

  // 專案常見樹種
  List<Map<String, dynamic>> _commonSpecies = [];
  bool _loadingCommonSpecies = false;

  // 控制器
  final projectAreaController = TextEditingController();
  final projectCodeController = TextEditingController();
  final projectNameController = TextEditingController();
  final systemTreeController = TextEditingController();
  final projectTreeController = TextEditingController();
  final treeIdController = TextEditingController();
  final treeNameController = TextEditingController();
  final xCoordController = TextEditingController();
  final yCoordController = TextEditingController();
  final statusController = TextEditingController();
  final noteController = TextEditingController();
  final treeRemarkController = TextEditingController();
  final treeHeightController = TextEditingController();
  final dbhController = TextEditingController();
  final surveyRemarkController = TextEditingController();
  DateTime surveyTime = DateTime.now();
  final carbonstorageController = TextEditingController();
  final annualcarbonController = TextEditingController();

  // 在 _TreeInputPageState 類別中新增一個變數來儲存當前位置
  // Map<String, double>? _currentLocation; // Linter warning: The value of the field '_currentLocation' isn't used.

  @override
  void initState() {
    super.initState();

    // Initialize new state variables
    _isEditing = widget.isEdit;
    _currentTreeData = widget.treeData;

    _loadSpeciesList();
    _loadProjectList();
    _loadProjectAreas();

    // 如果是新增模式，設置編號
    if (!_isEditing) {
      _generateTreeNumbers();
    }

    // 添加專案代碼變更監聽器，自動更新專案樹木編號
    projectCodeController.addListener(_onProjectCodeChanged);

    if (_isEditing && _currentTreeData != null) {
      _populateFormWithData(_currentTreeData!);
    }

    // 添加監聽器以自動計算碳儲存量
    treeHeightController.addListener(_updateCarbonCalculations);
    dbhController.addListener(_updateCarbonCalculations);
  }

  // Helper function to populate form fields from a data map
  void _populateFormWithData(Map<String, dynamic> data) {
    // This map handles the key difference between backend (snake_case) and frontend (Chinese)
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
      'id': 'id' // Also map id
    };

    // Helper to safely get value regardless of key type
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
    statusController.text = getValue('status')?.toString() ?? '';
    noteController.text = getValue('note')?.toString() ?? '';
    treeRemarkController.text = getValue('tree_remark')?.toString() ?? '';
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

  // 專案代碼變更時更新專案樹木編號和常見樹種
  void _onProjectCodeChanged() {
    if (!_isEditing && projectCodeController.text.isNotEmpty) {
      _generateProjectTreeNumber();
      _loadCommonSpecies();
    }
  }

  // 只生成專案樹木編號
  Future<void> _generateProjectTreeNumber() async {
    try {
      final projectCode = projectCodeController.text;
      logDebug('專案代碼變更: $projectCode，正在生成新的專案樹木編號');

      // Refactored to use TreeService
      final response = await _treeService.getNextProjectTreeNumber(projectCode);
      if (response['success'] == true) {
        logDebug('API 返回的下一個專案樹木編號: ${response['nextNumber']}');
        if (mounted) {
          setState(() {
            projectTreeController.text = 'PT-${response['nextNumber']}';
          });
        }
      } else {
        logDebug('專案樹木編號 API 返回失敗，未更新編號');
      }
    } catch (e) {
      logDebug('生成專案樹木編號時發生錯誤: $e');
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

        // 更新控制器值（避免觸發循環更新）
        carbonstorageController.text = carbonStorage.toStringAsFixed(2);
        annualcarbonController.text = annualCarbon.toStringAsFixed(2);
      }
    } catch (e) {
      logDebug('碳計算錯誤: $e');
    }
  }

  @override
  void dispose() {
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

  // 在送出樹木資料前自動同步 project_areas - 保留作為備用功能
  // ignore: unused_element
  Future<void> _syncProjectAreaIfNeeded() async {
    final areaName = projectAreaController.text.trim();
    if (areaName.isEmpty) return;
    try {
      // 1. 先查詢 project_areas 是否已存在該區位
      // Refactored to use ProjectAreaService
      final areas = await _projectAreaService.getProjectAreas();
      final exists = areas.any((a) => a['area_name'] == areaName);
      debugPrint('[DEBUG] 檢查區位 $areaName 是否已存在: $exists');
      if (!exists) {
        // 2. 若不存在，則自動新增
        final x = double.tryParse(xCoordController.text) ?? 0;
        final y = double.tryParse(yCoordController.text) ?? 0;
        final desc = areaName; // 或直接給空字串 ''
        final areaData = {
          'area_name': areaName,
          'description': desc,
          'xCoord': x,
          'yCoord': y,
          'isSubmit': true
        };
        final resp = await _projectAreaService.addProjectArea(areaData);
        debugPrint('[DEBUG] 自動新增區位 $areaName，API 回應: ${resp}');
      }
    } catch (e) {
      debugPrint('[DEBUG] 區位同步發生錯誤: $e');
    }
  }

  // 在送出樹木資料前呼叫 _syncProjectAreaIfNeeded
  // Future<void> _submitTreeData() async { // Linter warning: The declaration '_submitTreeData' isn't referenced.
  //   await _syncProjectAreaIfNeeded();
  //   // ...原本送出樹木資料的程式碼...
  // }

  void submitData() async {
    if (!_formKey.currentState!.validate()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請檢查表單填寫是否完整')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 確保樹木編號不是0或空的
    if (!_isEditing &&
        (systemTreeController.text == '0' ||
            systemTreeController.text.isEmpty ||
            !systemTreeController.text.startsWith('ST-'))) {
      // 嘗試通過API獲取下一個系統樹木編號
      try {
        // Refactored to use TreeService
        final response = await _treeService.getNextSystemTreeNumber();
        if (response['success'] == true) {
          systemTreeController.text = 'ST-${response['nextNumber']}';
        } else {
          final randomNumber = _generateSafeFallbackId();
          systemTreeController.text = 'ST-$randomNumber';
        }
      } catch (e) {
        // 如果發生錯誤，使用隨機編號
        final randomNumber = _generateSafeFallbackId();
        systemTreeController.text = 'ST-$randomNumber';
      }
    }

    if (!_isEditing &&
        (projectTreeController.text == '0' ||
            projectTreeController.text.isEmpty ||
            !projectTreeController.text.startsWith('PT-'))) {
      // 嘗試通過API獲取專案樹木編號
      if (projectCodeController.text.isNotEmpty) {
        try {
          // Refactored to use TreeService
          final response = await _treeService
              .getNextProjectTreeNumber(projectCodeController.text);
          if (response['success'] == true) {
            projectTreeController.text = 'PT-${response['nextNumber']}';
          } else {
            final randomNumber = _generateSafeFallbackId();
            projectTreeController.text = 'PT-$randomNumber';
          }
        } catch (e) {
          final randomNumber = _generateSafeFallbackId();
          projectTreeController.text = 'PT-$randomNumber';
        }
      } else {
        // 如果沒有專案代碼，使用隨機編號
        final randomNumber = _generateSafeFallbackId();
        projectTreeController.text = 'PT-$randomNumber';
      }
    }


    try {
      final data = {
        "專案區位": projectAreaController.text,
        "專案代碼":
            (int.tryParse(projectCodeController.text.replaceAll('PRJ-', '')) ??
                    0)
                .toString(), // 轉為字串以避免型別錯誤
        "專案名稱": projectNameController.text,
        "系統樹木":
            (int.tryParse(systemTreeController.text.replaceAll('ST-', '')) ?? 0)
                .toString(), // 轉為字串
        "專案樹木":
            (int.tryParse(projectTreeController.text.replaceAll('PT-', '')) ??
                    0)
                .toString(), // 轉為字串
        "樹種編號": treeIdController.text,
        "樹種名稱": treeNameController.text,
        "X坐標": double.tryParse(xCoordController.text) ?? 0,
        "Y坐標": double.tryParse(yCoordController.text) ?? 0,
        "狀況": statusController.text,
        "註記": noteController.text.isEmpty ? '無' : noteController.text,
        "樹木備註":
            treeRemarkController.text.isEmpty ? '無' : treeRemarkController.text,
        "樹高（公尺）": double.tryParse(treeHeightController.text) ?? 0,
        "胸徑（公分）": double.tryParse(dbhController.text) ?? 0,
        "調查備註": surveyRemarkController.text,
        "調查時間": surveyTime.toIso8601String(),
        "碳儲存量": double.tryParse(carbonstorageController.text) ?? 0,
        "推估年碳吸存量": double.tryParse(annualcarbonController.text) ?? 0,
      };

      // 顯示正在提交的數據到日誌（方便調試）
      logDebug('提交的數據: ${jsonEncode(data)}');

      // Refactored to use TreeService
      Map<String, dynamic> response;
      if (_isEditing) {
        response = await _treeService.updateTree(
            _currentTreeData!['id'].toString(), data);
      } else {
        response = await _treeService.addTree(data);
      }

      // 確保在回調前檢查 widget 是否仍然掛載
      if (!mounted) return;

      if (response['success'] == true) {
        logDebug('請求成功，返回數據: $response');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? '更新成功!' : '提交成功!')),
        );

        // [FIX] 將完整的資料回傳給前一個頁面
        final Map<String, dynamic> returnedData =
            Map<String, dynamic>.from(data);
        if (_isEditing) {
          returnedData['id'] = _currentTreeData!['id'];
          // [V2 COMPATIBILITY] In edit mode, return true on success to trigger refresh.
          Navigator.pop(context, true);
        } else {
          returnedData['id'] = response['id'];
        Navigator.pop(context, returnedData);
        }
      } else {
        String errorMsg = response['message'] ?? '伺服器錯誤';
        logDebug('請求失敗: $errorMsg，響應體: $response');
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
    setState(() {
      _isLoading = true;
      _locationError = '';
    });

    try {
      // 檢查位置權限
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

      // 獲取當前位置
      final position = await getHighAccuracyPosition();
      if (position == null) {
        setState(() {
          _isLoading = false;
          _locationError = '無法獲取位置';
        });
        return;
      }

      // 確保在更新狀態前檢查 widget 是否仍掛載
      if (!mounted) return;

      // 如果有選擇專案區位，驗證位置
      if (projectAreaController.text.isNotEmpty) {
        // Refactored to use LocationService
        final response = await _locationService.validateLocation(
            area: projectAreaController.text,
            latitude: position.latitude,
            longitude: position.longitude);

        if (response['isValid'] == false) {
          // 獲取建議的區位
          final suggestResponse = await _locationService.suggestArea(
              latitude: position.latitude, longitude: position.longitude);
          String suggestedArea = '';
          if (suggestResponse['success'] == true) {
            suggestedArea = suggestResponse['suggestedArea'];
          }
          // 顯示警告對話框
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
      // 確保在更新狀態前檢查 widget 是否仍掛載
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

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String? Function(String?)? validator, {
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.forestGreen),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.forestGreen, width: 2),
          ),
          filled: true,
          fillColor: AppColors.surfaceLight,
        ),
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Widget _buildCarbonFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '碳儲存計算',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
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
              activeColor: Colors.green[700],
            ),
            Text(
              _autoCalculateEnabled ? '自動' : '手動',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.blue),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('碳儲存量計算說明'),
                    content: const Text('碳儲存量計算採用5個步驟：\n\n'
                        '1. 計算地上部生物量：AGB = e^(-2.48 + 2.4835 × ln(DBH))\n'
                        '2. 計算總生物量：TB = 1.24 × AGB\n'
                        '3. 計算碳含量：C = 0.50 × TB\n'
                        '4. 轉換為CO₂當量：CO₂-eq = C × 3.67\n'
                        '5. 計算年碳吸存量：\n   年吸存量 = CO₂-eq × 生長率因子\n\n'
                        '生長率因子依樹種而異：\n'
                        '· 快速生長樹種：4%\n'
                        '· 一般生長樹種：2%\n'
                        '· 緩慢生長樹種：1%\n'
                        '預設使用3%作為保守估計值。'),
                    actions: [
                      TextButton(
                        child: const Text('了解'),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                );
              },
            ),
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

  Widget _buildTreeSpeciesSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '選擇樹種',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (_loadingCommonSpecies)
          const Center(child: CircularProgressIndicator())
        else if (_commonSpecies.isNotEmpty) ...[
          const Text(
            '專案常見樹種',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.forestGreen.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _commonSpecies.length,
              itemBuilder: (context, index) {
                final species = _commonSpecies[index];
                return ListTile(
                  title: Text(species['樹種名稱']),
                  subtitle:
                      Text('編號: ${species['樹種編號']} (${species['count']}棵)'),
                  onTap: () => _onSpeciesSelected(species),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        // 樹種名稱欄位 - 點擊後彈出搜尋/選擇視窗
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '樹種名稱',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _showEnhancedSpeciesDialog(),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.forestGreen.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.surfaceLight,
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
                    Icon(Icons.search, color: AppColors.forestGreen),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // 樹種編號欄位 - 自動填入或生成
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '樹種編號',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: treeIdController,
              readOnly: true,
              decoration: InputDecoration(
                hintText: '選擇樹種後自動填入',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.green),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: AppColors.forestGreen, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 增強版樹種搜尋/選擇對話框
  void _showEnhancedSpeciesDialog() {
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController searchController = TextEditingController();
        List<Map<String, dynamic>> filteredList = List.from(_speciesList);
        bool showNoResults = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // 過濾函數 - 基於名稱搜尋（包含關鍵字和相似音）
            void filterSpecies(String query) {
              setDialogState(() {
                if (query.isEmpty) {
                  filteredList = List.from(_speciesList);
                  showNoResults = false;
                } else {
                  // 簡單的相似音處理（例如：將 "臺" 和 "台" 視為相同）
                  String normalizedQuery = query
                      .toLowerCase()
                      .replaceAll('臺', '台')
                      .replaceAll('羅', '罗')
                      .replaceAll('樹', '树');

                  filteredList = _speciesList.where((species) {
                    String name = species['name']
                        .toString()
                        .toLowerCase()
                        .replaceAll('臺', '台')
                        .replaceAll('羅', '罗')
                        .replaceAll('樹', '树');

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
                height: MediaQuery.of(context).size.height * 0.6, // 固定高度
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
                          child: Text(
                            '沒有找到符合的樹種',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: Text('新增樹種: ${searchController.text}'),
                        onPressed: () {
                          Navigator.pop(context);
                          _showAddSpeciesDialog(searchController.text);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                      ),
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
                if (searchController.text.isNotEmpty && !showNoResults)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('新增樹種: ${searchController.text}'),
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddSpeciesDialog(searchController.text);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // 簡化版的新增樹種對話框（不需要輸入編號）
  void _showAddSpeciesDialog([String prefilledName = '']) {
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
                decoration: const InputDecoration(
                  labelText: '樹種名稱',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              const Text(
                '樹種編號將由系統自動產生',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('新增'),
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  // 關閉對話框
                  Navigator.of(context).pop();

                  // 使用獨立方法處理網絡請求和狀態更新
                  await _addSpecies(nameController.text);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('請填寫樹種名稱')),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  // 載入樹種列表
  Future<void> _loadSpeciesList() async {
    setState(() {
      _loadingSpecies = true;
    });

    try {
      // Refactored to use TreeSpeciesService
      _speciesList = await _speciesService.getSpecies();
    } catch (e) {
      logDebug('載入樹種列表錯誤: $e');
    } finally {
      setState(() {
        _loadingSpecies = false;
      });
    }
  }

  // 選擇樹種處理函數
  void _onSpeciesSelected(Map<String, dynamic> species) {
    setState(() {
      // 檢查是否為常見樹種（來自 _commonSpecies）
      if (species.containsKey('樹種編號')) {
        treeIdController.text = species['樹種編號'].toString();
        treeNameController.text = species['樹種名稱'].toString();
      } else {
        // 原始樹種列表的處理方式
        treeIdController.text = species['id'].toString();
        treeNameController.text = species['name'].toString();
      }
    });
  }

  // 添加載入專案列表的方法
  Future<void> _loadProjectList() async {
    setState(() {
      // _loadingProjects = true; // 改為直接使用 false
    });

    try {
      // Refactored to use ProjectService and ensure correct type casting
      final response = await _projectService.getProjects();
      if (response['success'] == true && response['data'] != null) {
        _projectList = List<Map<String, dynamic>>.from(response['data']);
      } else {
        _projectList = [];
      }
      logDebug('載入的專案列表: $_projectList');
    } catch (e) {
      logDebug('載入專案列表錯誤: $e');
    } finally {
      setState(() {
        // _loadingProjects = false; // 直接移除
      });
    }
  }

  // 載入專案區位列表
  Future<void> _loadProjectAreas() async {
    setState(() {
      _loadingAreas = true;
      _projectAreas = []; // 清空現有列表
    });

    try {
      logDebug('開始載入專案區位列表...');

      // Refactored to use ProjectAreaService
      _projectAreas = await _projectAreaService.getProjectAreas();
      logDebug('載入的專案區位: $_projectAreas');
    } catch (e) {
      logDebug('載入專案區位列表錯誤: $e');

      // 添加測試資料，確保用戶體驗不中斷
      if (mounted) {
        setState(() {
          _projectAreas = [
            {'area_name': '測試區位', 'area_code': 'AREA-TEST', 'description': '測試區位'}
          ];
          logDebug('發生異常，添加測試數據: $_projectAreas');
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入專案區位列表時發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingAreas = false;
        });
      }
    }
  }

  // 更新專案列表（根據區位過濾）
  Future<void> _updateFilteredProjects(String area) async {
    setState(() {
      _loadingFilteredProjects = true;
      _filteredProjects = []; // 清空先前的列表
    });

    try {
      // 修正 API 路徑，使用正確的格式
      // Refactored to use ProjectService
      final response = await _projectService.getProjectsByArea(area);
      if (response['success'] == true && response['data'] != null) {
        _filteredProjects = List<Map<String, dynamic>>.from(response['data']);
      } else {
        _filteredProjects = [];
      }
      logDebug('過濾後的專案列表: $_filteredProjects');
    } catch (e) {
      logDebug('載入專案列表錯誤: $e');

      // 顯示錯誤提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入專案列表錯誤: $e')),
        );
      }
    } finally {
      // 改善 finally 中的控制流，避免使用 return
      if (mounted) {
        setState(() {
          _loadingFilteredProjects = false;
        });
      }
    }
  }

  // 添加新樹種
  Future<void> _addSpecies(String name) async {
    try {
      // Refactored to use TreeSpeciesService
      final response = await _speciesService.addSpecies(name);

      // 檢查 widget 是否仍然掛載
      if (!mounted) return;

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增樹種成功: $name')),
        );
        // 重新載入樹種列表
        _loadSpeciesList();
        // 設置剛剛添加的樹種
        setState(() {
          // 如果 API 返回了編號則使用，否則保持空白等待系統生成
          treeIdController.text = response['id']?.toString() ?? '';
          treeNameController.text = name;
        });
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

  // 顯示專案區位選擇對話框
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
                    else if (_projectAreas.isEmpty)
                      const Center(
                        child: Text(
                          '目前沒有專案區位資料',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredAreas.length,
                          itemBuilder: (context, index) {
                            final area = filteredAreas[index];
                            return ListTile(
                              title: Text(area['area_name'] ?? ''),
                              subtitle: area['area_code'] != null
                                  ? Text('代碼: ${area['area_code']}')
                                  : null,
                              onTap: () {
                                projectAreaController.text =
                                    area['area_name'] ?? '';
                                // 清空和重設專案資訊
                                projectNameController.text = '';
                                projectCodeController.text = '';
                                // 主要修正：使用更新後的區位來加載專案列表
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
                if (areaController.text.isNotEmpty &&
                    !_projectAreas
                        .any((a) => a['area_name'] == areaController.text))
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

  // 新增專案區位
  Future<void> _addProjectArea(String areaName) async {
    try {
      logDebug('嘗試新增專案區位: $areaName');

      // 獲取當前位置
      final position = await getHighAccuracyPosition();
      if (position != null) {
        logDebug('獲取到當前位置: ${position.latitude}, ${position.longitude}');
      } else {
        logDebug('獲取位置失敗');
      }

      // 準備請求資料
      final requestData = {
        'area_name': areaName,
        'description': areaName + '專案區位',
        'isSubmit': true, // 標記為正式提交
      };

      // 如果有位置資訊，加入座標
      if (position != null) {
        requestData['xCoord'] = position.longitude;
        requestData['yCoord'] = position.latitude;
        logDebug('加入座標資訊: ${position.longitude}, ${position.latitude}');
      }

      // Refactored to use ProjectAreaService
      final response = await _projectAreaService.addProjectArea(requestData);

      logDebug('新增專案區位 API 回應: $response');

      if (!mounted) return;

      if (response['success'] == true) {
        await _loadProjectAreas();
        projectAreaController.text = areaName;

        // 顯示成功訊息，包含縣市資訊
        final city = response['data']?['city'] ?? '未知縣市';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('專案區位新增成功 (縣市: $city)')),
        );
      } else {
        logDebug('新增專案區位失敗: ${response['message']}');
        // 顯示錯誤訊息
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? '新增專案區位失敗')),
        );
      }
    } catch (e) {
      logDebug('新增專案區位錯誤: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增專案區位時發生錯誤: $e')),
      );
    }
  }

  // 修改專案區位輸入欄位
  Widget _buildProjectAreaField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '專案區位',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.green),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.forestGreen, width: 2),
            ),
            filled: true,
            fillColor: AppColors.surfaceLight,
          ),
          validator: (value) => value?.isEmpty ?? true ? '請選擇專案區位' : null,
        ),
      ],
    );
  }

  // 修改專案名稱輸入欄位
  Widget _buildProjectNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '專案名稱',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
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
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.green),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.forestGreen, width: 2),
            ),
            filled: true,
            fillColor: AppColors.surfaceLight,
          ),
          validator: (value) => value?.isEmpty ?? true ? '請選擇專案名稱' : null,
        ),
      ],
    );
  }

  // 修改專案代碼輸入欄位
  Widget _buildProjectCodeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '專案代碼',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: projectCodeController,
          readOnly: true,
          decoration: InputDecoration(
            hintText: '系統自動產生',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.green),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.forestGreen, width: 2),
            ),
            filled: true,
            fillColor: Colors.grey.shade100,
          ),
        ),
      ],
    );
  }

  // 展示專案選擇對話框
  void _showProjectDialog() {
    if (projectAreaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇或添加專案區位')),
      );
      return;
    }

    logDebug('顯示專案選擇對話框，當前專案區位: ${projectAreaController.text}');

    // 確保專案列表已根據當前選擇的區位進行了更新
    // 注意: _updateFilteredProjects 現在會在區位選擇時觸發，這裡可能不需要再次呼叫
    // if (_filteredProjects.isEmpty) {
    //   _updateFilteredProjects(projectAreaController.text);
    // }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // Renamed setState to setStateDialog for clarity
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('選擇專案', style: TextStyle(fontSize: 20)),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.green),
                    tooltip: '新增專案',
                    onPressed: () {
                      Navigator.pop(
                          context); // Close the selection dialog first
                      _showAddProjectDialog(); // Open the add project dialog
                    },
                  ),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: TextEditingController(
                          text: projectAreaController.text),
                      decoration: const InputDecoration(
                        labelText: '專案區位',
                        border: OutlineInputBorder(),
                      ),
                      readOnly: true,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 300,
                      child: _loadingFilteredProjects
                          ? const Center(child: CircularProgressIndicator())
                          : _filteredProjects.isEmpty
                              ? const Center(
                                  child: Text('此區位下沒有專案，請新增專案'),
                                )
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
                                          logDebug(
                                              '選擇專案: ${project['name']} (${project['code']})');

                                          // 設置專案名稱和代碼
                                          // Use the main page's setState
                                          setState(() {
                                            projectNameController.text =
                                                project['name'] ?? '';
                                            projectCodeController.text =
                                                project['code'] ?? '';
                                          });

                                          Navigator.pop(
                                              context); // Close the dialog

                                          // Fetch project tree number after selection
                                          if (projectCodeController
                                              .text.isNotEmpty) {
                                            await _generateProjectTreeNumber();
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
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // 新增：顯示新增專案對話框
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('專案區位: ${projectAreaController.text}'),
                const SizedBox(height: 16),
                TextFormField(
                  controller: newProjectNameController,
                  decoration: const InputDecoration(
                    labelText: '新專案名稱',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '請輸入專案名稱';
                    }
                    return null;
                  },
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
              onPressed: () async {
                if (addFormKey.currentState!.validate()) {
                  Navigator.pop(context); // Close the add dialog
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

  // 新增：處理新增專案邏輯
  Future<void> _addProject(String projectName) async {
    setState(() {
      _isLoading = true; // Show loading indicator
    });

    try {
      // Refactored to use ProjectService
      final response = await _projectService.addProject(
          projectName, projectAreaController.text);

      if (!mounted) return;

      if (response['success'] == true) {
        final newProject = response['project'];
        final placeholderTree =
            response['placeholderTree']; // Get placeholder data
        logDebug('專案新增成功: ${newProject['name']} (${newProject['code']})');

        if (placeholderTree != null) {
          // This is the main fix: transition from 'add' to 'edit' state
          setState(() {
            _isEditing = true;
            _currentTreeData = Map<String, dynamic>.from(placeholderTree);
            _populateFormWithData(_currentTreeData!);

            // Also update project fields which are not part of tree_survey table
            projectNameController.text = newProject['name'];
            projectCodeController.text = newProject['code'];
            projectAreaController.text = newProject['area'];
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('專案已建立，請填寫第一筆樹木資料。')),
          );
        } else {
          // Fallback for safety, though should not happen with new backend
          setState(() {
            projectNameController.text = newProject['name'];
            projectCodeController.text = newProject['code'];
          });
          await _updateFilteredProjects(projectAreaController.text);
          await _generateProjectTreeNumber();
          await _loadCommonSpecies();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('專案 "$projectName" 新增成功')),
          );
        }
      } else {
        logDebug('新增專案失敗: ${response['message']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增專案失敗: ${response['message'] ?? '未知錯誤'}')),
        );
      }
    } catch (e) {
      logDebug('新增專案時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增專案時連線錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 生成樹木編號
  Future<void> _generateTreeNumbers() async {
    try {
      // 系統樹木編號生成
      logDebug('正在生成系統樹木編號');
      // Refactored to use TreeService
      final response = await _treeService.getNextSystemTreeNumber();
      if (response['success'] == true) {
        logDebug('API 返回的下一個系統樹木編號: ${response['nextNumber']}');
        setState(() {
          systemTreeController.text = 'ST-${response['nextNumber']}';
        });
      } else {
        logDebug('API 返回失敗，使用隨機編號');
        // 生成隨機編號作為備用
        final randomNumber = _generateSafeFallbackId();
        setState(() {
          systemTreeController.text = 'ST-$randomNumber';
        });
      }

      // 如果已有專案代碼，則同時生成專案樹木編號
      if (projectCodeController.text.isNotEmpty) {
        await _generateProjectTreeNumber();
      } else {
        // 如果沒有專案代碼，使用隨機編號
        final randomNumber = _generateSafeFallbackId();
        setState(() {
          projectTreeController.text = 'PT-$randomNumber';
        });
      }
    } catch (e) {
      logDebug('生成樹木編號時發生錯誤: $e');
      final randomNumber = _generateSafeFallbackId();
      if (mounted) {
        setState(() {
          systemTreeController.text = 'ST-$randomNumber';
          projectTreeController.text = 'PT-$randomNumber';
        });
      }
    }
  }

  // 載入專案常見樹種
  Future<void> _loadCommonSpecies() async {
    if (projectCodeController.text.isEmpty) return;

    setState(() {
      _loadingCommonSpecies = true;
    });

    try {
      // Refactored to use TreeService
      final response =
          await _treeService.getCommonSpecies(projectCodeController.text);
      setState(() {
        _commonSpecies = response;
      });
    } catch (e) {
      logDebug('載入專案常見樹種錯誤: $e');
    } finally {
      setState(() {
        _loadingCommonSpecies = false;
      });
    }
  }

  List<Step> getSteps() {
    return [
      Step(
        title: const Text('基本資訊'),
        content: Container(
          margin: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              _buildProjectAreaField(),
              _buildProjectNameField(),
              _buildProjectCodeField(),
              // 系統樹木輸入欄位
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '系統樹木編號 (自動生成)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: systemTreeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: '系統自動生成',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.green),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: AppColors.forestGreen, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ],
                ),
              ),
              // 專案樹木輸入欄位
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '專案樹木編號 (自動生成)',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: projectTreeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        hintText: '系統自動生成',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.green),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.forestGreen.withValues(alpha: 0.3)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: AppColors.forestGreen, width: 2),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        isActive: _currentStep >= 0,
        state: _currentStep > 0 ? StepState.complete : StepState.indexed,
      ),
      Step(
        title: const Text('樹木基本資訊'),
        content: Material(
          child: Column(
            children: [
              _buildTreeSpeciesSelector(),
              const SizedBox(height: 16),
              _buildTextField(
                treeIdController,
                '樹種編號',
                (value) => value?.isEmpty ?? true ? '請輸入樹種編號' : null,
              ),
              _buildTextField(
                treeNameController,
                '樹種名稱',
                (value) => value?.isEmpty ?? true ? '請輸入樹種名稱' : null,
              ),
            ],
          ),
        ),
        isActive: _currentStep >= 1,
      ),
      Step(
        title: const Text('位置資訊'),
        content: Material(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: xCoordController,
                      decoration: const InputDecoration(labelText: 'X坐標（經度）'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: yCoordController,
                      decoration: const InputDecoration(labelText: 'Y坐標（緯度）'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _getCurrentLocation,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.my_location),
                label: Text(_isLoading ? '獲取位置中...' : '使用目前位置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
              if (_locationError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _locationError,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
        isActive: _currentStep >= 2,
      ),
      Step(
        title: const Text('狀態資訊'),
        content: Material(
          child: Column(
            children: [
              _buildTextField(
                statusController,
                '狀況',
                (value) => value?.isEmpty ?? true ? '請輸入狀況' : null,
              ),
              _buildTextField(noteController, '註記', null),
              _buildTextField(treeRemarkController, '樹木備註', null),
            ],
          ),
        ),
        isActive: _currentStep >= 3,
      ),
      Step(
        title: const Text('測量資訊'),
        content: Material(
          child: Column(
            children: [
              _buildTextField(
                treeHeightController,
                '樹高（公尺）',
                (value) => value?.isEmpty ?? true ? '請輸入樹高' : null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              _buildTextField(
                dbhController,
                '胸徑（公分）',
                (value) => value?.isEmpty ?? true ? '請輸入胸徑' : null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
        isActive: _currentStep >= 4,
      ),
      Step(
        title: const Text('碳計算資訊'),
        content: Material(
          child: _buildCarbonFields(),
        ),
        isActive: _currentStep >= 5,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // [REVISED] Concurrency-safe cleanup logic
        // Only try to clean up if we are in a state of editing a placeholder
        if (_isEditing &&
            _currentTreeData != null &&
            _currentTreeData!['species_name'] == '預設樹種') {
          final placeholderId = _currentTreeData!['id'];
          if (placeholderId != null) {
            try {
              debugPrint(
                  "Attempting to delete specific placeholder with ID: $placeholderId");
              await _treeService.deletePlaceholderTree(placeholderId);
              debugPrint("Specific placeholder cleanup successful.");
            } catch (e) {
              debugPrint("Error deleting specific placeholder: $e");
              // Fallback to general cleanup if specific fails for some reason
              await _treeService.cleanupTemporaryData();
            }
          }
        } else {
          // For other cases (like navigating back from a normal 'add' page without creating a project),
          // a general cleanup might still be relevant.
          await _treeService.cleanupTemporaryData();
        }
        return true; // Allow pop
      },
      child: Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha: 0.8)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.portBlue.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          title: Text(
            _isEditing ? '編輯樹木資料' : '新增樹木資料',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
              letterSpacing: 0.5,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.surfaceLight, Colors.white],
            ),
          ),
          child: Scrollbar(
            thickness: 8, // 滑動軸的寬度
            radius: const Radius.circular(4), // 滑動軸的圓角
            thumbVisibility: true, // 始終顯示滑動軸
            interactive: true, // 允許直接拖動滑動軸
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Form(
                      key: _formKey,
                      child: Stepper(
                        type: StepperType.vertical,
                        currentStep: _currentStep,
                        onStepContinue: () {
                          if (_currentStep < getSteps().length - 1) {
                            setState(() {
                              _currentStep++;
                            });
                          } else {
                            submitData();
                          }
                        },
                        onStepCancel: () {
                          if (_currentStep > 0) {
                            setState(() {
                              _currentStep--;
                            });
                          }
                        },
                        steps: getSteps(),
                        controlsBuilder: (context, details) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 20.0),
                            child: Row(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha: 0.85)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.portBlue.withValues(alpha: 0.3),
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
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 28, vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    child: Text(
                                        _currentStep == getSteps().length - 1
                                            ? '提交'
                                            : '下一步',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                ),
                                if (_currentStep > 0) ...[
                                  const SizedBox(width: 12),
                                  TextButton(
                                    onPressed: details.onStepCancel,
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.neutral600,
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    ),
                                    child: const Text('上一步', style: TextStyle(fontWeight: FontWeight.w500)),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    TreeBatchUploadWidget(
                      onUploadComplete: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('批量上傳完成！資料已更新。'),
                            backgroundColor: Colors.green,
                          ),
                        );
                        Navigator.pop(context, true);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TreeBatchUploadWidget extends StatefulWidget {
  final Function onUploadComplete;

  const TreeBatchUploadWidget({
    Key? key,
    required this.onUploadComplete,
  }) : super(key: key);

  @override
  State<TreeBatchUploadWidget> createState() => _TreeBatchUploadWidgetState();
}

class _TreeBatchUploadWidgetState extends State<TreeBatchUploadWidget> {
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _statusMessage = '';
  final TreeService _treeService = TreeService(); // Add service instance

  Future<void> _pickAndUploadFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
      );

      if (result != null) {
        setState(() {
          _isUploading = true;
          _statusMessage = '準備上傳檔案...';
        });

        File file = File(result.files.single.path!);

        // Refactored to use TreeService
        try {
          final response = await _treeService.importTrees(file, (progress) {
            if (mounted) {
              setState(() {
                _uploadProgress = progress;
                _statusMessage =
                    '上傳中... ${(_uploadProgress * 100).toStringAsFixed(0)}%';
              });
            }
          });
          if (mounted) {
            setState(() {
              _statusMessage = '上傳成功：${response['message']}';
            });
            widget.onUploadComplete();
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _statusMessage = '上傳失敗：$e';
            });
          }
        }

      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = '錯誤：$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _downloadTemplate() async {
    try {
      // Refactored to use TreeService
      final url = _treeService.getTemplateDownloadUrl();
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        setState(() {
          _statusMessage = '無法下載模板，請檢查網絡連接';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '下載模板時出錯：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.portBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.upload_file_rounded, color: AppColors.portBlue, size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    '批量上傳樹木資料',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '使用 Excel 或 CSV 檔案批量導入樹木資料，請確保格式正確。',
              style: TextStyle(
                color: AppColors.neutral600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('下載模板'),
                    onPressed: _downloadTemplate,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.portBlue,
                      side: BorderSide(color: AppColors.portBlue.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha: 0.85)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.portBlue.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_rounded),
                      label: const Text('選擇並上傳'),
                      onPressed: _isUploading ? null : _pickAndUploadFile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isUploading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: AppColors.neutral200,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.portBlue),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            if (_statusMessage.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('錯誤') || _statusMessage.contains('失敗')
                      ? AppColors.error.withValues(alpha: 0.1)
                      : AppColors.forestGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _statusMessage.contains('錯誤') || _statusMessage.contains('失敗')
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      color: _statusMessage.contains('錯誤') || _statusMessage.contains('失敗')
                          ? AppColors.error
                          : AppColors.forestGreen,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains('錯誤') || _statusMessage.contains('失敗')
                              ? AppColors.error
                              : AppColors.forestGreen,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
