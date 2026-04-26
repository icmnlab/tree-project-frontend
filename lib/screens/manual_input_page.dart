import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../utils/location_helper.dart';
import '../services/project_area_service.dart';
import '../services/project_service.dart';
import '../services/species_service.dart';
import '../services/tree_service.dart';

/// @Deprecated('Use ManualInputPageV2 (manual_input_page_v2.dart) instead.')
///
/// This is the V1 manual input page.
/// It is kept for backward compatibility with older workflows,
/// but new development should focus on V2 or V3.
class ManualInputPage extends StatefulWidget {
  final List<Map<String, dynamic>> importedData;

  const ManualInputPage({super.key, required this.importedData});

  @override
  State<ManualInputPage> createState() => _ManualInputPageState();
}

class _ManualInputPageState extends State<ManualInputPage> {
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
  }

  void _deduplicateAndInitData() {
    // Group by ID
    Map<String, Map<String, dynamic>> uniqueMap = {};
    List<Map<String, dynamic>> noIdList = [];

    for (var item in widget.importedData) {
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
      print('載入初始數據失敗: $e');
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
      print('載入專案失敗: $e');
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
            content: const Text('尚未儲存的資料將會遺失，且本次新增的臨時專案/區位將被刪除。確定要放棄匯入嗎？'),
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
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4.0),
            child: LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: AppColors.surfaceLight,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
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
        print('刪除佔位樹木失敗: $e');
      }
    }
    for (var id in _createdAreaIds) {
      try {
        await _projectAreaService.deleteProjectArea(id);
        debugPrint('已刪除專案區位 ID: $id');
      } catch (e) {
        print('刪除專案區位失敗: $e');
      }
    }
  }

  String _getTitleForStep() {
    switch (_currentStep) {
      case 0:
        return '步驟 1/3: 預設專案設定';
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
            '請選擇「預設」的專案歸屬',
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
              labelText: '預設專案區位',
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
                    Text('+ 新增專案區位...', style: TextStyle(color: Colors.blue)),
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
              labelText: '預設專案名稱',
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
                      Text('+ 新增專案...', style: TextStyle(color: Colors.blue)),
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
                  color: isSelected ? AppColors.surfaceLight : null,
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
                          '專案: ${item['project_name']} (${item['project_area']})',
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
                    // [New] Project & Area Batch Edit
                    OutlinedButton.icon(
                      icon: const Icon(Icons.map, size: 16),
                      label: const Text('區位'),
                      onPressed: () => _showProjectAreaSelector(),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.folder, size: 16),
                      label: const Text('專案'),
                      onPressed: () => _showProjectSelector(),
                    ),
                    const SizedBox(width: 8),
                    const VerticalDivider(width: 20, thickness: 2),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.forest, size: 18),
                      label: const Text('樹種'),
                      onPressed: _showSpeciesSelector,
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
              content: Text('錯誤：尚有樹木未歸屬「專案」。'), backgroundColor: Colors.red),
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
          const Text('匯入統計：',
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
                            const Icon(Icons.folder_shared, color: Colors.blue),
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
                icon: const Icon(Icons.check),
                label: const Text('確認匯入'),
                onPressed: _submitAllData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
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
        title: const Text('選擇專案區位 (批量)'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            itemCount: _projectAreas.length + 1, // +1 for Add New
            itemBuilder: (context, index) {
              if (index == _projectAreas.length) {
                return ListTile(
                  leading: const Icon(Icons.add, color: Colors.blue),
                  title: const Text('新增專案區位...',
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
    // [FIX] 優先使用第一筆選取資料的區位作為預設值，而非全域預設值
    // 這樣使用者操作體驗更連貫：選了一批 A 區的樹，打開選單應該預設顯示 A 區
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
            title: const Text('設定歸屬專案'),
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
                      child: Text('+ 新增專案區位...',
                          style: TextStyle(color: Colors.blue)),
                    ),
                  ],
                  onChanged: (val) async {
                    if (val == '__NEW__') {
                      Navigator.pop(context);
                      _showAddProjectAreaDialog();
                    } else {
                      // 這裡透過 setStateDialog 更新 tempArea，這會觸發 FutureBuilder 重新執行
                      setStateDialog(() {
                        tempArea = val;
                      });
                    }
                  },
                  decoration: const InputDecoration(labelText: '區位'),
                ),
                const SizedBox(height: 16),
                if (tempArea != null)
                  SizedBox(
                    height: 200,
                    width: double.maxFinite,
                    // [FIX] 使用 FutureBuilder 處理列表載入，避免狀態不同步
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
                            // 如果載入完成但沒資料，顯示新增選項
                            return ListTile(
                              leading:
                                  const Icon(Icons.add, color: Colors.blue),
                              title: const Text('此區位尚無專案，點此新增...',
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
                                  title: const Text('新增專案...',
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
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: '胸徑 (cm)'),
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

  // [Logic] Updated to handle Project Object
  void _batchUpdateField(String field, dynamic value) {
    // [FIX] 允許選取 indices 為空時的特定操作 (如新增專案時強制賦值給所有未設定者)
    // 但為了安全，我們通常還是只對選取的操作。
    // 如果 _selectedIndices 為空，則不執行任何操作
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

  Future<void> _submitAllData() async {
    // Show Loading Dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('資料寫入中，請稍候...'),
          ],
        ),
      ),
    );

    try {
      final sysResp = await _treeService.getNextSystemTreeNumber();
      int nextSysId = sysResp['nextNumber'] ?? 1;
      Map<String, int> projectNextIds = {};
      int successCount = 0;

      for (var item in _editableData) {
        String pCode = item['project_code'] ?? '0';
        if (!projectNextIds.containsKey(pCode)) {
          final prjResp = await _treeService.getNextProjectTreeNumber(pCode);
          projectNextIds[pCode] = prjResp['nextNumber'] ?? 1;
        }
        int currentPrjId = projectNextIds[pCode]!;
        projectNextIds[pCode] = currentPrjId + 1;

        // [v13.1 NEW] 構建儀器測量參數的結構化備註
        String instrumentData = "";
        if (item['metadata'] != null) {
          final meta = item['metadata'];
          List<String> params = [];
          if (meta['horizontal_distance'] != null) {
            params.add("HD:${meta['horizontal_distance']}m");
          }
          if (meta['slope_distance'] != null) {
            params.add("SD:${meta['slope_distance']}m");
          }
          if (meta['pitch'] != null) {
            params.add("Pitch:${meta['pitch']}°");
          }
          if (meta['azimuth'] != null) {
            params.add("Az:${meta['azimuth']}°");
          }
          if (meta['altitude'] != null) {
            params.add("Alt:${meta['altitude']}m");
          }

          if (params.isNotEmpty) {
            instrumentData = "[VLGEO] ${params.join(', ')}";
          }
        }

        // 將使用者備註與儀器數據合併
        String finalSurveyRemark = item['survey_remark'] ?? "批量匯入";
        if (instrumentData.isNotEmpty) {
          finalSurveyRemark = "$instrumentData | $finalSurveyRemark";
        }

        // [T6 cleanup] V1 addTree 已移除，改走 createTreeV2（英文鍵名）
        final submitData = {
          "project_area": item['project_area'],
          "project_code": pCode,
          "project_name": item['project_name'],
          "system_tree_id": nextSysId++,
          "project_tree_id": currentPrjId,
          "species_id": item['species_id'] ?? '',
          "species_name": item['species_name'] ?? '',
          "x_coord": item['lon'] ?? 0.0,
          "y_coord": item['lat'] ?? 0.0,
          "status": item['status'] ?? "良好",
          "note": item['note'] ?? "無",
          "tree_remark": item['tree_remark'] ?? "無",
          "tree_height_m": item['height'] ?? 0.0,
          "dbh_cm": item['dbh'] ?? 0.0,
          "survey_notes": finalSurveyRemark,
          "survey_time": item['timestamp_iso'] ?? DateTime.now().toIso8601String(),
          "carbon_storage": 0,
          "carbon_sequestration_per_year": 0,
        };

        await _treeService.createTreeV2(submitData);
        successCount++;
      }

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('成功匯入 $successCount 筆資料')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      print('匯入失敗: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯入過程發生錯誤: $e')),
        );
      }
    }
  }

  Future<void> _showAddProjectAreaDialog() async {
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

        // [FIX] 針對 Step 2 批量新增區位後的自動套用
        if (_currentStep == 1) {
          // 即使沒有選取任何項目，我們也想提示使用者繼續
          // 但 _batchUpdateField 會檢查 _selectedIndices.isEmpty
          // 如果使用者是為了未來幾筆資料新增區位，此時可能還沒勾選。
          // 我們直接使用 _batchUpdateField 嘗試更新已選項目 (如果有)

          // 如果有選取項目，直接更新
          if (_selectedIndices.isNotEmpty) {
            _batchUpdateField('project_area', areaName);
            _batchUpdateField('project_name', null);
          }

          // 自動彈出新增專案對話框，引導使用者完成流程 (UX 優化)
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('區位新增成功。請繼續新增專案。')),
            );
            // 稍微延遲一下讓 SnackBar 顯示
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
        title: Text('在 $targetArea 新增專案'),
        content: TextField(
            controller: projectNameController,
            decoration: const InputDecoration(labelText: '新專案名稱')),
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

        // [FIX] 針對使用者反饋 "新增後不會自動套用"
        // 如果是在 Step 2 透過批量選擇器新增的，我們嘗試自動套用
        if (_currentStep == 1) {
          // 假設如果是在 Step 2 新增，使用者是想把選取的項目設為此新專案
          // 這裡直接呼叫 batch update，但前提是有選取項目
          if (_selectedIndices.isNotEmpty) {
            _batchUpdateField('project_obj', newProject);
            _batchUpdateField('project_area', area); // 確保區位也同步 (雖然通常已是該區位)
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('已新增並套用專案: ${newProject['name']}')),
              );
            }
          } else {
            // 如果沒選取，僅提示新增成功
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text('專案 ${newProject['name']} 新增成功。請選取資料以套用。')),
              );
            }
          }
        }

        // Only update default if we added to the default area
        if (area == _defaultArea) {
          setState(() {
            _defaultProject = newProject['name'];
            _defaultProjectCode = newProject['code'];
          });
        }

        if (mounted &&
            _currentStep == 0) // 只有在 Step 1 才顯示單純的新增成功提示，Step 2 已經顯示套用提示
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
