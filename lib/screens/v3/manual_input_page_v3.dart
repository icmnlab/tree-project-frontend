import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../utils/location_helper.dart';
import '../../services/tree_service.dart';
import '../../services/project_service.dart';
import '../../services/species_service.dart';
import '../../services/species_identification_service.dart';
import '../../services/v3/project_boundary_service.dart';
import '../../services/v3/tree_image_service.dart';
import '../../services/v3/ml_data_collector.dart'; // ML Data Collector
import '../scanner_page.dart'; // For DBH measurement
import '../../services/ar_measurement_service.dart'; // For MeasurementResult
import '../../services/project_area_service.dart'; // 新增專案區位服務
import 'project_boundary_draw_page.dart'; // [N新功能] 新增專案 → 引導畫邊界

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
  bool _isLocationValid = false;
  String? _locationWarning;
  ProjectBoundaryStatus? _boundaryStatus;

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
  final List<String> _statusOptions = [
    '正常',
    '枯死',
    '病蟲害',
    '傾斜',
    '斷梢',
    '空洞',
    '其他'
  ];

  // Step 5: Photos & Notes
  final TextEditingController _notesController = TextEditingController();
  final List<File> _photos = [];

  // Bug #23: 搜尋防抖
  Timer? _speciesSearchDebounce;

  // [N12 fix] V3 輸入頁地圖要顯示既有專案邊界，方便使用者一眼看到目前位置
  // 是否落在某個專案的邊界內
  final Set<Polygon> _boundaryPolygons = {};

  @override
  void initState() {
    super.initState();
    _loadProjectAreas(); // V3: 載入專案區位列表
    _loadSpecies();
    _getCurrentLocation();
    _loadBoundariesForMap(); // [N12 fix] 載入並渲染專案邊界
  }

  // [N12 fix] 載入專案邊界並轉成 Polygon Set 供地圖顯示
  Future<void> _loadBoundariesForMap() async {
    try {
      final boundaries = await _boundaryService.getAllBoundaries();
      if (!mounted) return;
      const palette = <Color>[
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.purple,
        Colors.teal,
        Colors.pink,
        Colors.indigo,
        Colors.amber,
      ];
      final polys = <Polygon>{};
      for (var i = 0; i < boundaries.length; i++) {
        final b = boundaries[i];
        final pts = b.coordinates.map((c) => LatLng(c[0], c[1])).toList();
        if (pts.length < 3) continue;
        final color = palette[i % palette.length];
        polys.add(Polygon(
          polygonId: PolygonId('mi_boundary_${b.projectName}'),
          points: pts,
          strokeColor: color,
          strokeWidth: 2,
          fillColor: color.withValues(alpha: 0.12),
        ));
      }
      setState(() {
        _boundaryPolygons
          ..clear()
          ..addAll(polys);
      });
    } catch (e) {
      debugPrint('[ManualInputPageV3] 載入邊界失敗: $e');
    }
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
            _filteredProjects =
                List<Map<String, dynamic>>.from(response['data']);
          } else {
            _filteredProjects = [];
          }
          _loadingFilteredProjects = false;
        });
      }
    } catch (e) {
      debugPrint('載入專案失敗: $e');
      if (mounted) {
        setState(() {
          _filteredProjects = [];
          _loadingFilteredProjects = false;
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

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final position = await getHighAccuracyPosition();

      if (position != null && mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });

        // 自動匹配專案
        _autoMatchProject();
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar('無法獲取位置: $e');
      }
    }
  }

  Future<void> _autoMatchProject() async {
    if (_currentLocation == null) return;

    // 確保邊界資料已載入
    await _boundaryService.getAllBoundaries();

    if (!mounted) return;

    final match = _boundaryService.findProjectByCoordinate(
      lat: _currentLocation!.latitude,
      lng: _currentLocation!.longitude,
    );

    if (match.matched && match.projectName != null) {
      // [N2 fix] 區位以「專案名稱反查 projects 表」為權威來源。
      // 邊界 row 的 project_area 只是儲存邊界當下的快取（很多舊邊界沒帶
      // projectCode → 後端 resolve 不到 → 該欄位是 NULL），不可信任。
      String? resolvedArea;
      try {
        final res = await _projectService.getProjectByName(match.projectName!);
        if (res['success'] == true && res['data'] != null) {
          final a = res['data']['area'];
          if (a is String && a.isNotEmpty) resolvedArea = a;
        }
      } catch (_) {}
      // 完全查不到才退回看邊界 row 有沒有附帶（極少數情況）
      resolvedArea ??=
          (match.projectArea?.isNotEmpty == true) ? match.projectArea : null;

      if (mounted) {
        setState(() {
          _selectedProjectName = match.projectName;
          _projectController.text = match.projectName!;
          if (match.projectCode != null) {
            _projectCodeController.text = match.projectCode!;
          }
          if (resolvedArea != null && resolvedArea.isNotEmpty) {
            _areaController.text = resolvedArea;
          }
          _isLocationValid = true;
          _locationWarning = null;
        });
        _showSnackBar('已自動匹配專案: ${match.projectName}'
            '${resolvedArea != null ? ' (區位: $resolvedArea)' : ''}');
      }

      // 嘗試載入該專案的區位資訊
      if (_areaController.text.isNotEmpty) {
        _updateFilteredProjects(_areaController.text);
      }
    } else {
      // 雖然沒匹配到，但如果是選擇已有專案，需檢查是否在該專案邊界外
      if (_projectController.text.isNotEmpty) {
        _validateLocation();
      }
    }
  }

  Future<void> _refreshProjectBoundaryStatus() async {
    final name = _projectController.text.trim();
    if (name.isEmpty) {
      if (mounted) setState(() => _boundaryStatus = null);
      return;
    }
    await _boundaryService.getAllBoundaries();
    final status = await _boundaryService.getProjectBoundaryStatus(name);
    if (mounted) setState(() => _boundaryStatus = status);
  }

  void _validateLocation() async {
    if (_currentLocation == null || _projectController.text.isEmpty) return;

    await _refreshProjectBoundaryStatus();

    final validation = await _boundaryService.validateCoordinateForProjectFresh(
      projectName: _projectController.text.trim(),
      lat: _currentLocation!.latitude,
      lng: _currentLocation!.longitude,
    );

    if (!mounted) return;

    setState(() {
      if (!validation.hasBoundary) {
        // 專案存在但尚未畫邊界 → 手動模式，不阻擋提交
        _isLocationValid = true;
        _locationWarning = null;
        return;
      }
      _isLocationValid = validation.isValid;
      _locationWarning = validation.isValid ? null : validation.message;
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // 專案區位對話框（類似 V2）
  void _showProjectAreaDialog() {
    final areaController = TextEditingController();
    List<Map<String, dynamic>> filteredAreas = List.from(_projectAreas);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
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
                        setDialogState(() {
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
                                // 修改 parent state — 使用 controller (跨 widget 安全)
                                _areaController.text = area['area_name'] ?? '';
                                _projectController.text = '';
                                _projectCodeController.text = '';
                                _selectedProjectName = null;
                                _updateFilteredProjects(_areaController.text);
                                Navigator.pop(context);
                                // 觸發 parent rebuild
                                if (mounted) setState(() {});
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
        position ??=
            await getHighAccuracyPosition(timeout: const Duration(seconds: 3));
      } catch (e) {
        debugPrint('獲取位置失敗 (非致命): $e');
      }

      final requestData = {
        'area_name': areaName,
        'description': '$areaName專案區位',
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
                                        onTap: () {
                                          setState(() {
                                            _projectController.text =
                                                project['name'] ?? '';
                                            _projectCodeController.text =
                                                project['code'] ?? '';
                                            _selectedProjectName =
                                                project['name'];
                                          });
                                          Navigator.pop(context);
                                          _validateLocation();
                                          _refreshProjectBoundaryStatus();
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
                if (addFormKey.currentState?.validate() == true) {
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
      final response =
          await _projectService.addProject(projectName, _areaController.text);
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
        await _refreshProjectBoundaryStatus();
        _validateLocation();
        _showSnackBar('專案 "$projectName" 新增成功');

        // [新功能] 引導使用者立刻畫邊界（可跳過，不影響專案已建立的事實）
        await _promptDrawBoundaryAfterCreate(
          projectName: newProject['name'] as String,
          projectCode: newProject['code'] as String?,
        );
      }
    } catch (e) {
      _showSnackBar('新增專案時連線錯誤: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// [新功能] 新增專案成功後詢問是否立即繪製邊界。
  /// 設計原則：專案 row 已建立，邊界是「可選後續步驟」，
  /// 不論使用者跳過、半途離開、或網路失敗，都不影響專案已存的事實。
  Future<void> _promptDrawBoundaryAfterCreate({
    required String projectName,
    String? projectCode,
  }) async {
    if (!mounted) return;
    final shouldDraw = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('要繪製專案邊界嗎？'),
        content: const Text(
          '建議現在就在地圖上畫出專案範圍，'
          '這樣之後使用智慧模式新增樹木時可以自動匹配到此專案。\n\n'
          '可以稍後在地圖頁手動補畫，不影響專案已建立的事實。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍後再說'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.draw),
            label: const Text('立刻繪製'),
          ),
        ],
      ),
    );

    if (shouldDraw != true || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectBoundaryDrawPage(
          projectName: projectName,
          projectCode: projectCode,
        ),
      ),
    );
    // 回來後重新整理一下邊界快取（讓自動匹配馬上生效）
    try {
      await _boundaryService.getAllBoundaries(forceRefresh: true);
    } catch (_) {}
  }

  // 清理臨時新增的專案區位和專案
  Future<void> _performCleanup() async {
    if (_createdAreaIds.isEmpty && _createdProjectCodes.isEmpty) return;

    debugPrint('[ManualInputPageV3] 執行清理工作...');

    // 清理新增的專案
    for (var code in _createdProjectCodes) {
      try {
        await _projectService.deleteProject(code);
        debugPrint('[ManualInputPageV3] 已刪除專案 Code: $code');
      } catch (e) {
        debugPrint('[ManualInputPageV3] 刪除專案失敗 (Code: $code): $e');
      }
    }

    // 清理新增的專案區位。必須放在專案清理之後，避免先刪區位導致
    // projects.area_id 被資料庫設為 NULL，但 project_boundaries 仍保留。
    for (var id in _createdAreaIds) {
      try {
        await _projectAreaService.deleteProjectArea(id);
        debugPrint('[ManualInputPageV3] 已刪除專案區位 ID: $id');
      } catch (e) {
        debugPrint('[ManualInputPageV3] 刪除專案區位失敗 (ID: $id): $e');
      }
    }

    debugPrint('[ManualInputPageV3] 清理工作完成');
  }

  @override
  void dispose() {
    // 如果沒有提交且新增了專案區位/專案，執行清理（fire-and-forget，最佳努力）
    if (!_hasSubmitted &&
        (_createdAreaIds.isNotEmpty || _createdProjectCodes.isNotEmpty)) {
      _performCleanup(); // async but intentional fire-and-forget
    }

    // Bug #20: 清理暫存照片
    for (final photo in _photos) {
      try {
        if (photo.existsSync()) photo.deleteSync();
      } catch (_) {}
    }
    _photos.clear();

    _speciesSearchDebounce?.cancel();
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // 如果新增了專案區位/專案但還沒提交，詢問是否要清理
        if (!_hasSubmitted &&
            (_createdAreaIds.isNotEmpty || _createdProjectCodes.isNotEmpty)) {
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
            if (context.mounted) Navigator.of(context).pop();
          }
        } else {
          if (context.mounted) Navigator.of(context).pop();
        }
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

      // 如果有選擇專案名稱，驗證位置（僅在有邊界時才警告邊界外）
      if (_projectController.text.isNotEmpty &&
          _boundaryStatus?.hasBoundary == true &&
          !_isLocationValid) {
        // 警告但允許繼續 (V3 原則：Validation Warning)
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('位置警告'),
            content: Text(_locationWarning ?? '位置不在專案邊界內'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('返回')),
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
      final dbhVal = double.tryParse(_dbhController.text);
      if (dbhVal == null || dbhVal <= 0) {
        _showSnackBar('請輸入有效的胸徑數值 (> 0)');
        return;
      }
      // Bug #22: 高度選填但如填寫需驗證
      if (_heightController.text.isNotEmpty) {
        final heightVal = double.tryParse(_heightController.text);
        if (heightVal == null || heightVal < 0) {
          _showSnackBar('請輸入有效的樹高 (≥ 0)');
          return;
        }
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
  Widget _buildBoundaryStatusChip() {
    final status = _boundaryStatus!;
    if (status.hasBoundary) {
      return Chip(
        avatar: const Icon(Icons.check_circle, color: Colors.green, size: 18),
        label: Text(
          '專案已有邊界${_isLocationValid ? '' : '（目前位置在邊界外）'}',
          style: const TextStyle(fontSize: 12),
        ),
        backgroundColor: Colors.green.shade50,
      );
    }
    return Chip(
      avatar: const Icon(Icons.info_outline, color: Colors.orange, size: 18),
      label: Text(
        '尚未畫邊界（手動模式，GPS 不限制；${status.treeCountWithGps} 棵有 GPS）',
        style: const TextStyle(fontSize: 12),
      ),
      backgroundColor: Colors.orange.shade50,
    );
  }

  Widget _buildLocationStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_currentLocation != null)
          Container(
            // [N8 RWD] 高度依螢幕比例，小螢幕不再硬塞 200px；範圍 160-260。
            height:
                (MediaQuery.of(context).size.height * 0.25).clamp(160.0, 260.0),
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
                polygons: _boundaryPolygons, // [N12 fix] 顯示既有專案邊界
                myLocationEnabled: true,
                // [N6 fix] GoogleMap 在 Stepper 的可滾動容器內，預設 ScrollGesture 會被外層搶走，
                // 造成「單指拖地圖→放手後地圖回彈到反方向」(實際是 Stepper 在滑)。
                // 用 EagerGestureRecognizer 讓地圖立刻認領垂直拖動，外層就不會搶。
                gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                  Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer()),
                },
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
            height:
                (MediaQuery.of(context).size.height * 0.25).clamp(160.0, 260.0),
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
              onPressed:
                  _areaController.text.isNotEmpty ? _showProjectDialog : null,
            ),
          ),
          readOnly: true,
          onTap: _areaController.text.isNotEmpty
              ? _showProjectDialog
              : () {
                  _showSnackBar('請先選擇專案區位');
                },
        ),

        if (_projectController.text.isNotEmpty && _boundaryStatus != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: _buildBoundaryStatusChip(),
          ),

        if (_locationWarning != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_locationWarning!,
                        style: const TextStyle(
                            color: Colors.orange, fontSize: 12))),
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
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _identifySpeciesWithCamera,
              icon: _isIdentifying
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
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
                    color:
                        matchType == 'synonym' ? Colors.orange : Colors.green,
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
                      _speciesController.text = species['name'] ?? '';
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
  /// 3) 否則呼叫 POST /tree_species 自動建檔。後端在 transaction 內以 LOWER(name) 互斥，
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
        if (!_allSpecies.any((s) => s['id']?.toString() == _speciesId)) {
          _allSpecies.add({
            'id': r['id'],
            'name': r['name'] ?? name,
            'scientific_name': r['scientific_name'],
          });
        }
        return true;
      }
      _showSnackBar('樹種建檔失敗: ${r['message'] ?? '未知錯誤'}');
      return false;
    } catch (e) {
      if (mounted) _showSnackBar('樹種建檔錯誤: $e');
      return false;
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

      final result = await SpeciesIdentificationService.identifyFromFile(image,
          lang: 'zh');

      if (result['success'] == true && mounted) {
        final results = result['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final bestMatch = results.first;
          // [N1 fix] PlantNet 可能沒回 scientificNameWithoutAuthor，防 null cast
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
          final rawScore = bestMatch['score'];
          final score = rawScore != null
              ? ((rawScore as num).toDouble() * 100).toStringAsFixed(1)
              : '0.0';

          // [Policy] 學名優先；若無則退回完整學名/俗名，總之要把名字填進去
          final String? commonHint =
              (commonNames != null && commonNames.isNotEmpty)
                  ? commonNames.first?.toString()
                  : null;
          String displayName = (sciNoAuthor ?? '').trim();
          if (displayName.isEmpty) displayName = (sciFull ?? '').trim();
          if (displayName.isEmpty && commonHint != null) {
            displayName = commonHint.trim();
          }
          if (displayName.isEmpty) {
            _showSnackBar('辨識結果不完整，請手動輸入樹種');
            return;
          }
          // 對外仍以 scientificNameWithoutAuthor 命名變數，方便後續匹配 (fallback 已併入 displayName)
          final String? speciesName = sciNoAuthor ?? sciFull;

          // 優先使用後端回傳的 localMatch（含自動新增結果）
          String? matchedId;
          final localMatch = result['localMatch'] as Map<String, dynamic>?;
          final wasAutoAdded = result['autoAdded'] == true;

          if (localMatch != null && localMatch['id'] != null) {
            matchedId = localMatch['id'].toString();
          } else {
            // Fallback: 在本地列表匹配
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
              matchedId = match['id']?.toString() ?? match['樹種編號']?.toString();
            } catch (_) {
              // No match found
            }
          }

          // 構建提示訊息
          final hint = commonHint != null ? ' / $commonHint' : '';
          String snackMsg = '辨識成功: $displayName$hint (信心度 $score%)';
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

            // 將自動新增的樹種加入列表（在 setState 內，修復 Bug #18）
            if (wasAutoAdded && localMatch != null) {
              _allSpecies.add({
                'id': localMatch['id'],
                'name': localMatch['name'] ?? displayName,
                'scientific_name': localMatch['scientificName'] ?? speciesName,
              });
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
              onPressed: _startDBHMeasurement,
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                backgroundColor: Colors.teal.shade50,
                foregroundColor: Colors.teal,
              ),
              child: const Column(
                children: [
                  Icon(Icons.camera_alt),
                  Text('DBH 測量', style: TextStyle(fontSize: 10)),
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

  Future<void> _startDBHMeasurement() async {
    final result = await Navigator.of(context).push<MeasurementResult>(
      MaterialPageRoute(
        builder: (context) => ScannerPage(
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
      final result = await SpeciesIdentificationService.identifyFromFile(image,
          lang: 'zh');
      if (result['success'] == true && mounted) {
        final results = result['results'] as List? ?? [];
        if (results.isNotEmpty) {
          final bestMatch = results.first;
          // [N1 fix] 同上，null-safe
          final String? speciesName = bestMatch['species'] != null
              ? bestMatch['species']['scientificNameWithoutAuthor'] as String?
              : bestMatch['scientificNameWithoutAuthor'] as String?;
          final commonNames = bestMatch['species'] != null
              ? bestMatch['species']['commonNames'] as List?
              : bestMatch['commonNames'] as List?;
          final rawScore = bestMatch['score'];
          final score = rawScore != null
              ? ((rawScore as num).toDouble() * 100).toStringAsFixed(1)
              : '0.0';
          String displayName = speciesName ?? '';
          if (commonNames != null && commonNames.isNotEmpty) {
            displayName = commonNames.first?.toString() ?? displayName;
          }
          if (displayName.isEmpty) return;

          // 優先使用後端回傳的 localMatch（含自動新增結果）
          String? matchedId;
          final localMatch = result['localMatch'] as Map<String, dynamic>?;
          final wasAutoAdded = result['autoAdded'] == true;

          if (localMatch != null && localMatch['id'] != null) {
            matchedId = localMatch['id'].toString();
            // Bug #19 fix: 將 _allSpecies.add 移入下方 setState
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
            // Bug #19 fix: 將自動新增的樹種加入列表（在 setState 內）
            if (wasAutoAdded && localMatch != null) {
              _allSpecies.add({
                'id': localMatch['id'],
                'name': localMatch['name'] ?? displayName,
                'scientific_name': localMatch['scientificName'] ?? speciesName,
              });
            }
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
                        child: Image.file(_photos[index],
                            width: 80, height: 80, fit: BoxFit.cover),
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
    if (_isLoading) return; // 防止重複提交

    // 驗證必要欄位
    if (_currentLocation == null) {
      _showSnackBar('尚未取得 GPS 定位，無法提交');
      return;
    }

    final dbhValue = double.tryParse(_dbhController.text);
    if (dbhValue == null || dbhValue <= 0) {
      _showSnackBar('請輸入有效的胸徑 (DBH > 0)');
      return;
    }

    final heightValue = double.tryParse(_heightController.text);
    // 樹高為選填但不可為負
    if (_heightController.text.isNotEmpty &&
        (heightValue == null || heightValue < 0)) {
      _showSnackBar('請輸入有效的樹高');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // [Auto-Add] 提交前確保樹種已建檔（取代舊的「新增樹種」按鈕；多人並發安全）
      final speciesOk = await _ensureSpeciesId();
      if (!speciesOk) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 1. 準備提交數據 (相容 V2 API)
      final treeData = {
        "project_name": _projectController.text.isNotEmpty
            ? _projectController.text
            : _selectedProjectName,
        "project_code": _projectCodeController.text,
        "project_area": _areaController.text,

        "species_name": _speciesController.text,
        "species_id": _speciesId, // Optional

        "x_coord": _currentLocation!.longitude,
        "y_coord": _currentLocation!.latitude,

        "dbh_cm": dbhValue,
        "tree_height_m": heightValue ?? 0,

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

        final treeId =
            (response['id'] ?? response['data']?['id'] ?? 'unknown').toString();

        // 3. 儲存照片 (關聯到新創建的 treeId)
        for (var photo in _photos) {
          final savedImage = await _imageService.saveMeasurementImage(
            treeId: treeId,
            image: photo,
            type: TreeImageType.overview, // 或區分照片類型
            metadata: {
              'source': 'survey',
              'project_code': _projectCodeController.text,
              'project_name': _projectController.text.isNotEmpty
                  ? _projectController.text
                  : _selectedProjectName,
            },
          );
          if (savedImage != null) {
            unawaited(_imageService.syncImage(savedImage).then((ok) {
              debugPrint('[Photo] 同步到後端: ${ok ? "成功" : "失敗/稍後重試"}');
            }).catchError((e) {
              debugPrint('[Photo] 同步異常（將在下次批次時重試）: $e');
            }));
          }
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
            confidence: _speciesConfidence != null
                ? (double.tryParse(_speciesConfidence!) ?? 0) / 100.0
                : null,
            topPredictions: _aiPredictions,
            imagePath: _identificationImage?.path,
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('新增成功!')));
          Navigator.pop(context, true); // 返回成功
        }
      } else {
        throw Exception(response['message'] ?? '提交失敗');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('錯誤: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
