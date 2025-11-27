import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:math';
import 'dart:convert';

// Import services
import 'services/tree_service.dart';
import 'services/project_service.dart';
import 'services/project_area_service.dart';
import 'services/location_service.dart';
import 'services/species_service.dart';

// A new, dedicated page for editing tree data in V2 style.
// This avoids mixing create/edit logic and resolves state issues.

void logDebug(String message) {
  assert(() {
    debugPrint('TreeAppEditV2: $message');
    return true;
  }());
}

// Carbon calculation functions can be shared or moved to a utility file
double calculateCarbonStorage(double dbh) {
  if (dbh <= 0) return 0;
  double aboveGroundBiomass = exp(-2.48 + 2.4835 * log(dbh));
  double totalBiomass = 1.24 * aboveGroundBiomass;
  double carbonContent = 0.50 * totalBiomass;
  return carbonContent * 3.67;
}

double calculateCarbonSequestration(
    double carbonStorage, double? growthFactor) {
  return carbonStorage * (growthFactor ?? 0.03);
}

class TreeEditPageV2 extends StatefulWidget {
  final Map<String, dynamic> treeData;

  const TreeEditPageV2({super.key, required this.treeData});

  @override
  State<TreeEditPageV2> createState() => _TreeEditPageV2State();
}

class _TreeEditPageV2State extends State<TreeEditPageV2> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _locationError = '';
  bool _autoCalculateEnabled = true;

  // Services
  final TreeService _treeService = TreeService();
  final ProjectService _projectService = ProjectService();
  final ProjectAreaService _projectAreaService = ProjectAreaService();
  final LocationService _locationService = LocationService();
  final TreeSpeciesService _speciesService = TreeSpeciesService();

  // Data Lists
  List<Map<String, dynamic>> _speciesList = [];
  bool _loadingSpecies = false;
  List<Map<String, dynamic>> _projectAreas = [];
  bool _loadingAreas = false;
  List<Map<String, dynamic>> _filteredProjects = [];
  bool _loadingFilteredProjects = false;

  // Controllers
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

  final List<String> _commonStatuses = [
    '正常',
    '枯死',
    '病蟲害',
    '傾斜',
    '斷梢',
    '空洞',
    '其他'
  ];

  // Tree ID is final in edit mode
  late final String _treeId;

  @override
  void initState() {
    super.initState();

    _treeId = widget.treeData['id'].toString();

    _loadSpeciesList();
    _loadProjectAreas();

    _populateFormWithData(widget.treeData);

    projectCodeController.addListener(_onProjectCodeChanged);

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

    // After populating, load projects for the current area
    if (projectAreaController.text.isNotEmpty) {
      _updateFilteredProjects(projectAreaController.text);
    }
  }

  void _onProjectCodeChanged() {
    // 當專案代碼變更，且不為空時，自動生成新的專案樹木編號
    if (projectCodeController.text.isNotEmpty) {
      // 避免與初始值相同時重複觸發（雖然這裡邏輯上是允許移動到同專案並獲取新編號，但通常是換專案）
      // 這裡我們簡單地每次變更都去抓取最新的可用編號，確保無衝突
      _generateProjectTreeNumber();
    }
  }

  Future<void> _generateProjectTreeNumber() async {
    try {
      final projectCode = projectCodeController.text;
      logDebug('專案代碼變更: $projectCode，正在生成新的專案樹木編號');

      final response = await _treeService.getNextProjectTreeNumber(projectCode);
      if (!mounted) return;

      if (response['success'] == true) {
        logDebug('API 返回的下一個專案樹木編號: ${response['nextNumber']}');
        setState(() {
          projectTreeController.text = 'PT-${response['nextNumber']}';
        });

        // 提示用戶編號已更新
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('專案已變更，自動分配新編號: PT-${response['nextNumber']}'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      logDebug('生成專案樹木編號時發生錯誤: $e');
    }
  }

  void _updateCarbonCalculations() {
    if (!_autoCalculateEnabled) return;
    try {
      double dbh = double.tryParse(dbhController.text) ?? 0.0;
      if (dbh > 0) {
        double carbonStorage = calculateCarbonStorage(dbh);
        double annualCarbon = calculateCarbonSequestration(carbonStorage, null);
        carbonstorageController.text = carbonStorage.toStringAsFixed(2);
        annualcarbonController.text = annualCarbon.toStringAsFixed(2);
      }
    } catch (e) {
      logDebug('Carbon calculation error: $e');
    }
  }

  @override
  void dispose() {
    // Dispose all controllers
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

  Future<void> submitUpdateData() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請檢查表單填寫是否完整')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final treeData = {
        "project_area": projectAreaController.text,
        "project_code": projectCodeController.text,
        "project_name": projectNameController.text,
        "project_tree_id": projectTreeController.text,
        "species_id": treeIdController.text,
        "species_name": treeNameController.text,
        "x_coord": double.tryParse(xCoordController.text) ?? 0,
        "y_coord": double.tryParse(yCoordController.text) ?? 0,
        "status": statusController.text,
        "note": noteController.text.isEmpty ? null : noteController.text,
        "tree_remark": treeRemarkController.text.isEmpty
            ? null
            : treeRemarkController.text,
        "tree_height_m": double.tryParse(treeHeightController.text) ?? 0,
        "dbh_cm": double.tryParse(dbhController.text) ?? 0,
        "survey_notes": surveyRemarkController.text,
        "survey_time": surveyTime.toIso8601String(),
        "carbon_storage": double.tryParse(carbonstorageController.text) ?? 0,
        "carbon_sequestration_per_year":
            double.tryParse(annualcarbonController.text) ?? 0,
      };

      logDebug(
          'Submitting V2 update for tree ID $_treeId: ${jsonEncode(treeData)}');

      final response = await _treeService.updateTreeV2(_treeId, treeData);

      if (!mounted) return;

      if (response['success'] == true) {
        logDebug('Update successful, response: $response');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('更新成功 (V2)!')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        String errorMsg = response['message'] ?? '伺服器錯誤';
        logDebug('Update failed: $errorMsg');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(errorMsg)));
      }
    } catch (e) {
      logDebug('An error occurred during update: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('連線錯誤: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // All other helper methods (_getCurrentLocation, _buildTextField, dialogs, etc.)
  // are copied from TreeInputPageV2 and adapted for the edit context.
  // For brevity, only the core logic is shown here. Assume they exist and are functional.
  // ...

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('編輯樹木 (V2)'),
        backgroundColor: Colors.teal.shade100,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                // Using ListView instead of Stepper for a simpler layout
                padding: const EdgeInsets.all(16.0),
                children: [
                  const Text('基本資訊',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                  const Divider(),
                  _buildReadOnlyTextField(systemTreeController, '系統樹木編號'),
                  _buildReadOnlyTextField(projectTreeController, '專案樹木編號'),
                  _buildProjectAreaField(),
                  _buildProjectNameField(),
                  _buildReadOnlyTextField(projectCodeController, '專案代碼'),
                  const SizedBox(height: 24),
                  const Text('樹木資訊',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                  const Divider(),
                  _buildTreeSpeciesSelector(),
                  const SizedBox(height: 24),
                  const Text('位置與狀態',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                          child: _buildTextField(
                              xCoordController, 'X坐標 (經度)', null,
                              keyboardType: TextInputType.number)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _buildTextField(
                              yCoordController, 'Y坐標 (緯度)', null,
                              keyboardType: TextInputType.number)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildStatusField(),
                  const SizedBox(height: 24),
                  const Text('測量與備註',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                  const Divider(),
                  _buildTextField(treeHeightController, '樹高 (m)', null,
                      keyboardType: TextInputType.number),
                  _buildTextField(dbhController, '胸徑 (cm)', null,
                      keyboardType: TextInputType.number),
                  _buildTextField(noteController, '註記', null),
                  _buildTextField(treeRemarkController, '樹木備註', null),
                  _buildTextField(surveyRemarkController, '調查備註', null),
                  const SizedBox(height: 24),
                  const Text('碳計算',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal)),
                  const Divider(),
                  _buildCarbonFields(),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('儲存變更'),
                    onPressed: submitUpdateData,
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

  // Helper for read-only fields
  Widget _buildReadOnlyTextField(
      TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.grey[200],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // All other build helpers are assumed to be copied and adapted from TreeInputPageV2
  // For example:
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
          ),
          onChanged: (value) {
            setState(() {});
          },
          validator: (value) => (value?.isEmpty ?? true) ? '請輸入狀況' : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTreeSpeciesSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('選擇樹種',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _showEnhancedSpeciesDialog(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
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
        const SizedBox(height: 16),
        _buildReadOnlyTextField(treeIdController, '樹種編號'),
      ],
    );
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
                      ),
                      onChanged: filterSpecies,
                    ),
                    const SizedBox(height: 16),
                    if (_loadingSpecies)
                      const Center(child: CircularProgressIndicator())
                    else if (showNoResults)
                      Center(child: Text('沒有找到 "${searchController.text}"'))
                    else
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
            );
          },
        );
      },
    );
  }

  void _onSpeciesSelected(Map<String, dynamic> species) {
    setState(() {
      treeIdController.text = species['id'].toString();
      treeNameController.text = species['name'].toString();
    });
  }

  Future<void> _loadSpeciesList() async {
    setState(() => _loadingSpecies = true);
    try {
      _speciesList = await _speciesService.getSpecies();
    } catch (e) {
      logDebug('Failed to load species list: $e');
    } finally {
      if (mounted) setState(() => _loadingSpecies = false);
    }
  }

  Future<void> _loadProjectAreas() async {
    setState(() => _loadingAreas = true);
    try {
      _projectAreas = await _projectAreaService.getProjectAreas();
    } catch (e) {
      logDebug('Failed to load project areas: $e');
    } finally {
      if (mounted) setState(() => _loadingAreas = false);
    }
  }

  Future<void> _updateFilteredProjects(String area) async {
    setState(() => _loadingFilteredProjects = true);
    try {
      final response = await _projectService.getProjectsByArea(area);
      if (response['success'] == true && response['data'] != null) {
        if (mounted) {
          setState(() {
            _filteredProjects =
                List<Map<String, dynamic>>.from(response['data']);
          });
        }
      }
    } catch (e) {
      logDebug('Failed to load projects for area $area: $e');
    } finally {
      if (mounted) setState(() => _loadingFilteredProjects = false);
    }
  }

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

  void _showProjectAreaDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('選擇專案區位'),
          content: SizedBox(
            width: double.maxFinite,
            child: _loadingAreas
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _projectAreas.length + 1, // +1 for Add option
                    itemBuilder: (context, index) {
                      if (index == _projectAreas.length) {
                        return ListTile(
                          leading: const Icon(Icons.add, color: Colors.teal),
                          title: const Text('新增專案區位...',
                              style: TextStyle(color: Colors.teal)),
                          onTap: () {
                            Navigator.pop(context);
                            _showAddProjectAreaDialog();
                          },
                        );
                      }
                      final area = _projectAreas[index];
                      return ListTile(
                        title: Text(area['area_name'] ?? ''),
                        onTap: () {
                          setState(() {
                            projectAreaController.text =
                                area['area_name'] ?? '';
                            projectNameController.clear();
                            projectCodeController.clear();
                          });
                          _updateFilteredProjects(area['area_name'] ?? '');
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        );
      },
    );
  }

  void _showAddProjectAreaDialog() {
    final areaNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增專案區位'),
        content: TextField(
            controller: areaNameController,
            decoration: const InputDecoration(labelText: '專案區位名稱')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (areaNameController.text.isNotEmpty) {
                Navigator.pop(context);
                await _addProjectArea(areaNameController.text);
              }
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProjectArea(String areaName) async {
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
      } catch (e) {
        // Ignore
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
        await _loadProjectAreas();
        projectAreaController.text = areaName;
        // Reset project info as area changed
        projectNameController.clear();
        projectCodeController.clear();
        _updateFilteredProjects(areaName);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('專案區位新增成功')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('新增失敗: $e')),
      );
    }
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

  void _showProjectDialog() {
    if (projectAreaController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇專案區位')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('選擇專案'),
          content: SizedBox(
            width: double.maxFinite,
            child: _loadingFilteredProjects
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount:
                        _filteredProjects.length + 1, // +1 for Add option
                    itemBuilder: (context, index) {
                      if (index == _filteredProjects.length) {
                        return ListTile(
                          leading: const Icon(Icons.add, color: Colors.teal),
                          title: const Text('新增專案...',
                              style: TextStyle(color: Colors.teal)),
                          onTap: () {
                            Navigator.pop(context);
                            _showAddProjectDialog();
                          },
                        );
                      }
                      final project = _filteredProjects[index];
                      return ListTile(
                        title: Text(project['name'] ?? '未知專案'),
                        subtitle: Text('代碼: ${project['code'] ?? '未知'}'),
                        onTap: () {
                          setState(() {
                            projectNameController.text = project['name'] ?? '';
                            projectCodeController.text = project['code'] ?? '';
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
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
        setState(() {
          projectNameController.text = newProject['name'];
          projectCodeController.text = newProject['code'];
        });
        await _updateFilteredProjects(projectAreaController.text);

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
                  if (value) _updateCarbonCalculations();
                });
              },
              activeColor: Colors.teal[700],
            ),
            Text(_autoCalculateEnabled ? '自動' : '手動'),
          ],
        ),
        const SizedBox(height: 8),
        _buildTextField(
          carbonstorageController,
          '碳儲存量 (kg)',
          (value) => value?.isEmpty ?? true ? '請輸入碳儲存量' : null,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        _buildTextField(
          annualcarbonController,
          '推估年碳吸存量 (kg)',
          (value) => value?.isEmpty ?? true ? '請輸入推估年碳吸存量' : null,
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}
