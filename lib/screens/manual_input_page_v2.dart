import 'package:flutter/material.dart';
import '../services/ble_data_processor.dart';
import '../services/project_area_service.dart';
import '../utils/location_helper.dart';
import '../services/project_service.dart';
import '../services/species_service.dart';
import '../services/tree_service.dart';
import '../services/v3/project_boundary_service.dart'; // V3: 專案邊界自動匹配
import 'scanner_page.dart';
import '../services/ar_measurement_service.dart'; // For MeasurementResult

/// ManualInputPageV2
///
/// 這是第二版的手動輸入頁面，用於配合後端全新的 `/batch_import` API。
/// 特性：
/// 1. 移除前端 ID 生成邏輯，改由後端統一處理。
/// 2. 支援完整的儀器 metadata 上傳。
/// 3. 採用一次性批量提交，而非迴圈提交。
class ManualInputPageV2 extends StatefulWidget {
  final List<Map<String, dynamic>> importedData;

  const ManualInputPageV2({super.key, required this.importedData});

  @override
  State<ManualInputPageV2> createState() => _ManualInputPageV2State();
}

class _ManualInputPageV2State extends State<ManualInputPageV2> {
  final _projectAreaService = ProjectAreaService();
  final _projectService = ProjectService();
  final _speciesService = TreeSpeciesService();
  final _treeService = TreeService();

  // Wizard State
  int _currentStep = 0; // 0: Setup, 1: Edit, 2: Confirm

  // Data
  bool _isLoading = false;
  List<Map<String, dynamic>> _projectAreas = [];
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _speciesList = [];

  // Step 1: Setup - Selected Values (Acts as Default)
  String? _defaultArea;
  String? _defaultProject;
  String? _defaultProjectCode;

  // Step 2: Edit - Editable Data
  late List<Map<String, dynamic>> _editableData;
  Set<int> _selectedIndices = {};

  // Drag Selection State
  bool _isDragSelecting = false;
  final Map<int, GlobalKey> _itemKeys = {};
  bool _dragSelectValue = true;

  // Cleanup Tracking
  final List<int> _createdAreaIds = [];
  final List<int> _createdPlaceholderIds = [];

  @override
  void initState() {
    super.initState();
    _deduplicateAndInitData();
    _loadInitialData();
    _autoMatchProjects(); // V3: 自動匹配專案
  }

  // V3: 根據座標自動匹配專案
  Future<void> _autoMatchProjects() async {
    final boundaryService = ProjectBoundaryService();
    
    // 載入所有專案邊界
    await boundaryService.getAllBoundaries(forceRefresh: true);
    
    if (!boundaryService.hasCache) return;
    
    int matchedCount = 0;
    
    for (int i = 0; i < _editableData.length; i++) {
      final item = _editableData[i];
      final lat = item['lat'] as double?;
      final lon = item['lon'] as double?;
      
      if (lat == null || lon == null || lat == 0 || lon == 0) continue;
      
      final matchResult = boundaryService.findProjectByCoordinate(
        lat: lat,
        lng: lon,
      );
      
      if (matchResult.matched && matchResult.projectName != null) {
        _editableData[i]['project_name'] = matchResult.projectName;
        _editableData[i]['project_code'] = matchResult.projectCode;
        if (matchResult.projectArea != null && matchResult.projectArea!.isNotEmpty) {
          _editableData[i]['project_area'] = matchResult.projectArea;
        }
        _editableData[i]['_auto_matched'] = true; // 標記為自動匹配
        matchedCount++;
      }
    }
    
    if (mounted && matchedCount > 0) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('V3: 已根據座標自動匹配 $matchedCount 筆區名稱'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _deduplicateAndInitData() {
    var merged = BleDataProcessor.mergeMultiSeqRecords(
      List<Map<String, dynamic>>.from(widget.importedData),
    );

    // Group by ID to remove duplicates if any
    Map<String, Map<String, dynamic>> uniqueMap = {};
    List<Map<String, dynamic>> noIdList = [];

    for (var item in merged) {
      if (item['id'] != null && item['id'].toString().isNotEmpty) {
        uniqueMap[item['id'].toString()] = item;
      } else {
        noIdList.add(item);
      }
    }

    // 合併
    List<Map<String, dynamic>> mergedList = [...uniqueMap.values, ...noIdList];

    // 複製並添加預設欄位
    _editableData = List.from(mergedList.map((item) {
      return {
        ...item,
        'status': '良好',
        'note': '無',
        'tree_remark': '無',
        'survey_remark': '批量匯入',
        // [New] Per-row Project Info
        'project_area': null,
        'project_name': null,
        'project_code': null,
      };
    }));

    // 預設全選
    _selectedIndices =
        Set.from(List.generate(_editableData.length, (index) => index));
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await _loadProjectAreas();
      final species = await _speciesService.getSpecies();
      if (mounted) {
        setState(() {
          _speciesList = species;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('載入初始數據失敗: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProjectAreas() async {
    final areas = await _projectAreaService.getProjectAreas();
    if (mounted) {
      setState(() {
        _projectAreas = areas;
      });
    }
  }

  Future<void> _loadProjects(String area) async {
    setState(() => _isLoading = true);
    try {
      final response = await _projectService.getProjectsByArea(area);
      if (mounted) {
        setState(() {
          if (response['success'] == true && response['data'] != null) {
            _projects = List<Map<String, dynamic>>.from(response['data']);
          } else {
            _projects = [];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('載入專案失敗: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('確定要離開嗎？'),
            content: const Text('尚未儲存的資料將會遺失，且本次新增的臨時區/專案將被刪除。確定要放棄匯入嗎？'),
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
          _performCleanup();
        }
        return shouldPop ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_getTitleForStep()),
          backgroundColor: Colors.teal.shade100, // V2 區別色
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4.0),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: Colors.teal.shade100,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.teal),
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildCurrentStep(),
      ),
    );
  }

  // 清理臨時數據
  Future<void> _performCleanup() async {
    debugPrint('執行清理工作...');
    for (var id in _createdPlaceholderIds) {
      try {
        await _treeService.deletePlaceholderTree(id.toString());
        debugPrint('已刪除佔位樹木 ID: $id');
      } catch (e) {
        debugPrint('刪除佔位樹木失敗: $e');
      }
    }
    for (var id in _createdAreaIds) {
      try {
        await _projectAreaService.deleteProjectArea(id);
        debugPrint('已刪除專案區位 ID: $id');
      } catch (e) {
        debugPrint('刪除專案區位失敗: $e');
      }
    }
  }

  String _getTitleForStep() {
    switch (_currentStep) {
      case 0:
        return '步驟 1/3: 預設區設定 (V2)';
      case 1:
        return '步驟 2/3: 數據預覽與清洗';
      case 2:
        return '步驟 3/3: 最終確認';
      default:
        return '匯入數據';
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1Setup();
      case 1:
        return _buildStep2Cleaning();
      case 2:
        return _buildStep3Confirm();
      default:
        return const SizedBox.shrink();
    }
  }

  // --- Step 1: Setup (Set Defaults) ---

  Widget _buildStep1Setup() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '請選擇「預設」的區歸屬',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            '您可以在下一步針對特定資料進行修改',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _defaultArea,
            decoration: const InputDecoration(
              labelText: '預設專案',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.map),
            ),
            items: [
              ..._projectAreas.map((area) {
                return DropdownMenuItem(
                  value: area['area_name'] as String,
                  child: Text(area['area_name'] as String),
                );
              }).toList(),
              const DropdownMenuItem(
                value: '__NEW__',
                child:
                    Text('+ 新增專案...', style: TextStyle(color: Colors.blue)),
              ),
            ],
            onChanged: (value) {
              if (value == '__NEW__') {
                setState(() {});
                _showAddProjectAreaDialog();
              } else {
                setState(() {
                  _defaultArea = value;
                  _defaultProject = null;
                  _projects = [];
                });
                if (value != null) _loadProjects(value);
              }
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _defaultProject,
            decoration: const InputDecoration(
              labelText: '預設區名稱',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.folder),
            ),
            items: [
              ..._projects.map((proj) {
                return DropdownMenuItem(
                  value: proj['name'] as String,
                  child: Text('${proj['name']} (${proj['code']})'),
                );
              }).toList(),
              if (_defaultArea != null)
                const DropdownMenuItem(
                  value: '__NEW__',
                  child:
                      Text('+ 新增區...', style: TextStyle(color: Colors.blue)),
                ),
            ],
            onChanged: (value) {
              if (value == '__NEW__') {
                setState(() {});
                _showAddProjectDialog();
              } else {
                final proj = _projects.firstWhere((p) => p['name'] == value);
                setState(() {
                  _defaultProject = value;
                  _defaultProjectCode = proj['code']?.toString();
                });
              }
            },
          ),
          const Spacer(),
          ElevatedButton(
            onPressed: (_defaultArea != null && _defaultProject != null)
                ? () {
                    // Apply defaults to all rows initially
                    for (var item in _editableData) {
                      if (item['project_area'] == null)
                        item['project_area'] = _defaultArea;
                      if (item['project_name'] == null) {
                        item['project_name'] = _defaultProject;
                        item['project_code'] = _defaultProjectCode;
                      }
                    }
                    setState(() => _currentStep = 1);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('下一步 (套用預設值)'),
          ),
        ],
      ),
    );
  }

  // --- Step 2: Cleaning (Batch Edit) ---

  Widget _buildStep2Cleaning() {
    return Column(
      children: [
        // Toolbar
        Container(
          color: Colors.grey[100],
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              TextButton.icon(
                icon: Icon(
                  _selectedIndices.length == _editableData.length
                      ? Icons.deselect
                      : Icons.select_all,
                ),
                label: Text(_selectedIndices.length == _editableData.length
                    ? '取消全選'
                    : '全選'),
                onPressed: () {
                  setState(() {
                    if (_selectedIndices.length == _editableData.length) {
                      _selectedIndices.clear();
                    } else {
                      _selectedIndices = Set.from(
                          List.generate(_editableData.length, (i) => i));
                    }
                  });
                },
              ),
              const Spacer(),
              const Text(
                '滑動勾選框可連選',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // List Content
        Expanded(
          child: Listener(
            onPointerMove: (event) {
              _handleGlobalDrag(event.position);
            },
            onPointerUp: (_) => _isDragSelecting = false,
            child: ListView.builder(
              itemCount: _editableData.length,
              itemBuilder: (context, index) {
                final item = _editableData[index];
                final bool isSelected = _selectedIndices.contains(index);
                if (!_itemKeys.containsKey(index)) {
                  _itemKeys[index] = GlobalKey();
                }

                return Container(
                  key: _itemKeys[index],
                  color: isSelected ? Colors.teal.shade50 : null,
                  child: ListTile(
                    leading: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) {
                        setState(() {
                          _isDragSelecting = true;
                          _dragSelectValue = !isSelected;
                          _updateSelection(index);
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Checkbox(
                          value: isSelected,
                          activeColor: Colors.teal,
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedIndices.add(index);
                              } else {
                                _selectedIndices.remove(index);
                              }
                            });
                          },
                        ),
                      ),
                    ),
                    title: Text(
                        'ID: ${item['id']} | H: ${item['height']}m | D: ${item['dbh'] ?? 0}cm',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${item['species_name'] ?? '未選樹種'} | 狀: ${item['status']}'),
                        Text(
                          '區: ${item['project_name']} (${item['project_area']})',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blueGrey[700]),
                        ),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedIndices.remove(index);
                        } else {
                          _selectedIndices.add(index);
                        }
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),

        // Batch Actions
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: const Offset(0, -2))
            ],
          ),
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('專案'),
                      onPressed: () => _showProjectAreaSelector(),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder, size: 16),
                      label: const Text('區'),
                      onPressed: () => _showProjectSelector(),
                    ),
                    const SizedBox(width: 8),
                    const VerticalDivider(width: 20, thickness: 2),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.forest, size: 18),
                      label: const Text('樹種'),
                      onPressed: _showSpeciesSelector,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      child: const Text('胸徑'),
                      onPressed: () => _showDBHSelector(),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      child: const Text('狀況'),
                      onPressed: () => _showTextInputDialog('status', '狀況'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      child: const Text('備註'),
                      onPressed: () =>
                          _showTextInputDialog('tree_remark', '樹木備註'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 0),
                    child: const Text('重設預設值'),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      if (_validateData()) {
                        setState(() => _currentStep = 2);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('下一步：確認'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _validateData() {
    for (var item in _editableData) {
      if (item['species_name'] == null || item['species_name'].isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('錯誤：尚有樹木未設定「樹種」。'), backgroundColor: Colors.red),
        );
        return false;
      }
      if (item['project_name'] == null || item['project_name'].isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('錯誤：尚有樹木未歸屬「區」。'), backgroundColor: Colors.red),
        );
        return false;
      }
    }
    return true;
  }

  void _handleGlobalDrag(Offset position) {
    if (!_isDragSelecting) return;
    for (var entry in _itemKeys.entries) {
      final index = entry.key;
      final key = entry.value;
      final RenderBox? box =
          key.currentContext?.findRenderObject() as RenderBox?;

      if (box != null) {
        final itemPosition = box.localToGlobal(Offset.zero);
        final itemSize = box.size;
        if (position.dy >= itemPosition.dy &&
            position.dy <= itemPosition.dy + itemSize.height) {
          if (_selectedIndices.contains(index) != _dragSelectValue) {
            _updateSelection(index);
          }
          break;
        }
      }
    }
  }

  void _updateSelection(int index) {
    setState(() {
      if (_dragSelectValue) {
        _selectedIndices.add(index);
      } else {
        _selectedIndices.remove(index);
      }
    });
  }

  // --- Step 3: Confirmation ---

  Widget _buildStep3Confirm() {
    Map<String, int> projectCounts = {};
    for (var item in _editableData) {
      String key = '${item['project_name']} (${item['project_area']})';
      projectCounts[key] = (projectCounts[key] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('匯入統計 (V2)：',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('數據歸屬分佈：',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: projectCounts.entries
                  .map((e) => ListTile(
                        dense: true,
                        leading:
                            const Icon(Icons.folder_shared, color: Colors.teal),
                        title: Text(e.key),
                        trailing: Text('${e.value} 筆',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ))
                  .toList(),
            ),
          ),
          const Divider(),
          _buildInfoRow('總筆數', '${_editableData.length} 棵'),
          const SizedBox(height: 24),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _currentStep = 1),
                child: const Text('返回修改'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('確認並批量上傳'),
                onPressed: _submitBatchDataV2,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // --- Selectors ---

  void _showProjectAreaSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('選擇專案 (批量)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _projectAreas.length + 1, // +1 for Add New
            itemBuilder: (context, index) {
              if (index == _projectAreas.length) {
                return ListTile(
                  leading: const Icon(Icons.add, color: Colors.blue),
                  title: const Text('新增專案...',
                      style: TextStyle(color: Colors.blue)),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddProjectAreaDialog();
                  },
                );
              }
              final area = _projectAreas[index];
              return ListTile(
                title: Text(area['area_name']),
                onTap: () {
                  _batchUpdateField('project_area', area['area_name']);
                  _batchUpdateField('project_name', null);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _showProjectSelector() {
    String? tempArea = _defaultArea;

    if (_selectedIndices.isNotEmpty) {
      final firstIndex = _selectedIndices.first;
      final firstItemArea = _editableData[firstIndex]['project_area'];
      if (firstItemArea != null) {
        tempArea = firstItemArea;
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('設定歸屬區'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: tempArea,
                  items: [
                    ..._projectAreas
                        .map((area) => DropdownMenuItem(
                              value: area['area_name'] as String,
                              child: Text(area['area_name']),
                            ))
                        .toList(),
                    const DropdownMenuItem(
                      value: '__NEW__',
                      child: Text('+ 新增專案...',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                  onChanged: (val) async {
                    if (val == '__NEW__') {
                      Navigator.pop(context);
                      _showAddProjectAreaDialog();
                    } else {
                      setStateDialog(() {
                        tempArea = val;
                      });
                    }
                  },
                  decoration: const InputDecoration(labelText: '專案'),
                ),
                const SizedBox(height: 16),
                if (tempArea != null)
                  SizedBox(
                    height: 200,
                    width: double.maxFinite,
                    child: FutureBuilder<Map<String, dynamic>>(
                        future: _projectService.getProjectsByArea(tempArea!),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          List<Map<String, dynamic>> displayList = [];
                          if (snapshot.hasData &&
                              snapshot.data!['success'] == true &&
                              snapshot.data!['data'] != null) {
                            displayList = List<Map<String, dynamic>>.from(
                                snapshot.data!['data']);
                          }

                          if (displayList.isEmpty &&
                              snapshot.connectionState ==
                                  ConnectionState.done) {
                            return ListTile(
                              leading:
                                  const Icon(Icons.add, color: Colors.blue),
                              title: const Text('此專案尚無區，點此新增...',
                                  style: TextStyle(color: Colors.blue)),
                              onTap: () {
                                Navigator.pop(context);
                                _showAddProjectDialog(overrideArea: tempArea);
                              },
                            );
                          }

                          return ListView.builder(
                            itemCount: displayList.length + 1,
                            itemBuilder: (context, index) {
                              if (index == displayList.length) {
                                return ListTile(
                                  leading:
                                      const Icon(Icons.add, color: Colors.blue),
                                  title: const Text('新增區...',
                                      style: TextStyle(color: Colors.blue)),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _showAddProjectDialog(
                                        overrideArea: tempArea);
                                  },
                                );
                              }
                              final p = displayList[index];
                              return ListTile(
                                title: Text(p['name']),
                                subtitle: Text(p['code']),
                                onTap: () {
                                  _batchUpdateField('project_area', tempArea);
                                  _batchUpdateField('project_obj', p);
                                  Navigator.pop(context);
                                },
                              );
                            },
                          );
                        }),
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  void _showSpeciesSelector() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('選擇樹種'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _speciesList.length,
            itemBuilder: (context, index) {
              final s = _speciesList[index];
              return ListTile(
                title: Text(s['name']),
                onTap: () {
                  _batchUpdateField('species', s);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showAddSpeciesDialog();
              },
              child: const Text('新增樹種')),
        ],
      ),
    );
  }

  void _showAddSpeciesDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增樹種'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: '樹種名稱'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                Navigator.pop(context);
                await _addNewSpecies(nameController.text);
              }
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNewSpecies(String name) async {
    setState(() => _isLoading = true);
    try {
      final response = await _speciesService.addSpecies(name);
      if (response['success'] == true) {
        final species = await _speciesService.getSpecies();
        if (mounted) setState(() => _speciesList = species);
        final newSpecies =
            _speciesList.firstWhere((s) => s['name'] == name, orElse: () => {});
        if (newSpecies.isNotEmpty) _batchUpdateField('species', newSpecies);
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('樹種新增成功')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('新增失敗: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTextInputDialog(String field, String title) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title (將套用至選取項目)'),
        content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: title)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              _batchUpdateField(field, controller.text);
              Navigator.pop(context);
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _showDBHSelector() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('設定胸徑 (DBH)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 影像測量按鈕
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('影像測量胸徑'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade100,
                  foregroundColor: Colors.teal.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  final result = await Navigator.of(context).push<MeasurementResult>(
                    MaterialPageRoute(
                      builder: (_) => const ScannerPage(),
                    ),
                  );
                  if (result != null) {
                    _batchUpdateField('dbh', result.diameterCm);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('測量完成：胸徑 ${result.diameterCm.toStringAsFixed(1)} cm'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
            ),
            const Divider(),
            const SizedBox(height: 8),
            const Text('或手動輸入：', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '胸徑 (cm)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                _batchUpdateField('dbh', val);
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('請輸入有效數字')));
              }
            },
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _batchUpdateField(String field, dynamic value) {
    if (_selectedIndices.isEmpty) return;

    setState(() {
      for (int index in _selectedIndices) {
        switch (field) {
          case 'species':
            _editableData[index]['species_id'] = value['id'];
            _editableData[index]['species_name'] = value['name'];
            break;
          case 'status':
            _editableData[index]['status'] = value;
            break;
          case 'note':
            _editableData[index]['note'] = value;
            break;
          case 'tree_remark':
            _editableData[index]['tree_remark'] = value;
            break;
          case 'project_area':
            _editableData[index]['project_area'] = value;
            break;
          case 'project_name':
            _editableData[index]['project_name'] = value;
            break;
          case 'project_obj':
            _editableData[index]['project_name'] = value['name'];
            _editableData[index]['project_code'] = value['code']?.toString();
            break;
          case 'dbh':
            _editableData[index]['dbh'] = value;
            break;
        }
      }
    });
  }

  // [CRITICAL UPDATE] 批量提交邏輯 (V2)
  Future<void> _submitBatchDataV2() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在使用 V2 API 批量上傳...'),
          ],
        ),
      ),
    );

    try {
      // 分組處理：將資料按「專案」分組 (因為 Batch API 一次處理一個專案比較乾淨)
      // 雖然 API 支援單一 ProjectCode，但前端可能混雜了多個專案的資料
      // 這裡先簡單處理：假設使用者會先篩選或統一處理
      // 實際上我們可以把整包丟給後端，讓後端處理?
      // 不，後端 Batch Controller 目前設計是接收單一 project_code 的 context
      // 所以我們需要在這裡分組

      Map<String, List<Map<String, dynamic>>> groupedData = {};

      for (var item in _editableData) {
        String pCode = item['project_code'] ?? 'UNKNOWN';
        if (!groupedData.containsKey(pCode)) {
          groupedData[pCode] = [];
        }
        groupedData[pCode]!.add(item);
      }

      int totalSuccess = 0;

      for (var pCode in groupedData.keys) {
        List<Map<String, dynamic>> group = groupedData[pCode]!;

        // 準備 Payload
        // 取第一筆資料的專案資訊作為 Header
        var first = group.first;

        Map<String, dynamic> payload = {
          "project_area": first['project_area'],
          "project_code": pCode == 'UNKNOWN' ? null : pCode,
          "project_name": first['project_name'],
          "trees": group.map((item) {
            // 構建 tree object
            return {
              "species_id": item['species_id'],
              "species_name": item['species_name'],
              "height": item['height'],
              "dbh": item['dbh'],
              "lat": item['lat'], // Y
              "lon": item['lon'], // X
              "status": item['status'],
              "note": item['note'],
              "tree_remark": item['tree_remark'],
              "survey_remark": item['survey_remark'],
              "survey_time":
                  item['timestamp_iso'] ?? DateTime.now().toIso8601String(),
              "carbon_storage": 0,
              "carbon_sequestration": 0,
              // [New] 完整傳遞 metadata
              "metadata": item['metadata'] // 這裡直接傳遞 Map，後端會解析
            };
          }).toList()
        };

        // 呼叫 V2 API
        final result = await _treeService.batchImportTreesV2(payload);

        if (result['success'] == true) {
          totalSuccess += (result['data']['count'] as int);
        } else {
          throw Exception('區 $pCode 匯入失敗: ${result['message']}');
        }
      }

      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('V2 批量上傳成功！共 $totalSuccess 筆'),
            backgroundColor: Colors.teal,
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      debugPrint('V2 匯入失敗: $e');
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('上傳失敗'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _showAddProjectAreaDialog() async {
    final areaNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增專案'),
        content: TextField(
            controller: areaNameController,
            decoration: const InputDecoration(labelText: '專案名稱')),
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
    setState(() => _isLoading = true);
    try {
      final position = await getHighAccuracyPosition();

      final requestData = {
        'area_name': areaName,
        'description': areaName + '專案區位',
        'isSubmit': true,
        if (position != null) 'xCoord': position.longitude,
        if (position != null) 'yCoord': position.latitude,
      };
      final response = await _projectAreaService.addProjectArea(requestData);
      if (response['success'] == true) {
        if (response['data'] != null && response['data']['id'] != null) {
          _createdAreaIds.add(response['data']['id']);
        }
        await _loadProjectAreas();

        if (_currentStep == 1) {
          if (_selectedIndices.isNotEmpty) {
            _batchUpdateField('project_area', areaName);
            _batchUpdateField('project_name', null);
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('專案新增成功。請繼續新增區。')),
            );
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) _showAddProjectDialog(overrideArea: areaName);
            });
          }
        }

        if (_currentStep == 0) {
          setState(() {
            _defaultArea = areaName;
            _defaultProject = null;
            _projects = [];
          });
          await _loadProjects(areaName);
          if (mounted)
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('新增成功')));
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('失敗: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddProjectDialog({String? overrideArea}) async {
    final targetArea = overrideArea ?? _defaultArea;
    if (targetArea == null) return;
    final projectNameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('在 $targetArea 新增區'),
        content: TextField(
            controller: projectNameController,
            decoration: const InputDecoration(labelText: '新區名稱')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (projectNameController.text.isNotEmpty) {
                Navigator.pop(context);
                await _addProject(projectNameController.text, targetArea);
              }
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProject(String projectName, String area) async {
    setState(() => _isLoading = true);
    try {
      final response = await _projectService.addProject(projectName, area);
      if (response['success'] == true) {
        if (response['placeholderTree'] != null &&
            response['placeholderTree']['id'] != null) {
          _createdPlaceholderIds.add(response['placeholderTree']['id']);
        }
        final newProject = response['project'];
        await _loadProjects(
            area); // Reload projects for the area we just added to

        if (_currentStep == 1) {
          if (_selectedIndices.isNotEmpty) {
            _batchUpdateField('project_obj', newProject);
            _batchUpdateField('project_area', area);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已新增並套用區: ${newProject['name']}')),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('區 ${newProject['name']} 新增成功。請選取資料以套用。')),
              );
            }
          }
        }

        if (area == _defaultArea) {
          setState(() {
            _defaultProject = newProject['name'];
            _defaultProjectCode = newProject['code'];
          });
        }

        if (mounted && _currentStep == 0)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('新增成功')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('失敗: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
