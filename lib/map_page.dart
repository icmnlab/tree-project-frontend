import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'services/api_service.dart';
import 'services/tree_service.dart';
import 'utils/location_helper.dart';
import 'services/project_service.dart';
import 'services/project_scope_store.dart';
import 'services/v3/project_boundary_service.dart';
import 'screens/v3/project_boundary_draw_page.dart';
import 'tree_survey_detail_page.dart';
import 'utils/marker_spread.dart';
import 'utils/tree_marker_cluster.dart';
import 'services/auth_service.dart'; // [T7] 角色權限
import 'services/locale_service.dart';
import 'services/location_service.dart';
import 'constants/colors.dart';
import 'config/global_keys.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with RouteAware {
  GoogleMapController? _controller;
  final Set<Marker> _markers = {};
  Set<Polygon> _polygons = {}; // V3: 專案邊界多邊形（每次重建 Set 以觸發地圖更新）
  bool _isLoading = false;
  String _selectedProject = '全部';
  String _selectedCity = '全部';
  List<String> _projects = ['全部'];
  List<String> _filteredProjects = ['全部'];
  List<String> _cities = ['全部'];
  bool _disposed = false;
  bool _hasLocationPermission = false;
  Position? _currentPosition;
  MapType _currentMapType = MapType.normal;
  bool _showMenu = true;
  bool _showBoundaries = true; // V3: 是否顯示邊界
  bool _hideRetired = false; // [生命週期] 是否隱藏已淘汰（枯死/倒塌/移除）的樹
  bool _canManageProjects = false; // [T7] 是否可繪製邊界

  // [優化] 快取樹木資料，避免重複呼叫 API
  List<dynamic> _cachedTreeData = [];
  Map<String, String> _projectNameToCode = {};
  int _totalTreeCount = 0;
  bool _fitBoundsOnNextMarkerUpdate = false;
  bool _mapLoadInFlight = false;
  DateTime? _lastBoundaryRefresh;
  bool _mapControllerReady = false;

  // [效能] Dart 端 marker 聚合：zoom < 門檻時聚合成「N 棵」圓點、點擊放大展開；
  // zoom ≥ 門檻一律顯示個別標記（保證放大後看得到定位點）。
  // 不用 plugin 原生 ClusterManager：7000+ 標記會觸發其 Android 端
  // RejectedExecutionException（每 addItem 觸發一次 re-cluster AsyncTask）。
  static const double _clusterZoomThreshold = 16.0;
  static const int _clusterMinCount = 200; // 低於此數直接畫個別點，不聚合
  static const int _maxIndividualMarkers = 2000; // 個別模式保險絲
  double _currentZoom = 7;
  LatLngBounds? _visibleBounds;
  bool _markerCapExceeded = false;
  final Map<String, BitmapDescriptor> _clusterIconCache = {};

  bool _inVisibleBounds(double lat, double lng) {
    final b = _visibleBounds;
    if (b == null) return true;
    final sw = b.southwest;
    final ne = b.northeast;
    final latOk = lat >= sw.latitude && lat <= ne.latitude;
    final lngOk = sw.longitude <= ne.longitude
        ? (lng >= sw.longitude && lng <= ne.longitude)
        : (lng >= sw.longitude || lng <= ne.longitude); // 跨 ±180 保險
    return latOk && lngOk;
  }

  Future<void> _onCameraIdle() async {
    final controller = _controller;
    if (controller == null || !_mapControllerReady) return;
    double zoom;
    try {
      zoom = await controller.getZoomLevel();
      _visibleBounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }
    // zoom 跨越聚合門檻或顯著改變時重建（避免每次輕微平移都重繪）
    final crossedThreshold =
        (zoom < _clusterZoomThreshold) != (_currentZoom < _clusterZoomThreshold);
    final zoomChanged = (zoom - _currentZoom).abs() >= 0.5;
    _currentZoom = zoom;
    if (crossedThreshold || zoomChanged || zoom >= _clusterZoomThreshold) {
      _updateMarkersFromCache();
    }
  }

  /// 產生「N 棵」聚合圓點圖示（畫布繪製 + 依標籤快取）
  Future<BitmapDescriptor> _clusterIcon(int count) async {
    final label = clusterLabel(count);
    final cached = _clusterIconCache[label];
    if (cached != null) return cached;

    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final logicalDiameter = clusterDiameter(count);
    final d = logicalDiameter * dpr;
    final r = d / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(Offset(r, r), r, Paint()..color = Colors.white);
    canvas.drawCircle(
        Offset(r, r), r - 2 * dpr, Paint()..color = const Color(0xFF2E7D32));
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: d * 0.30,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(r - tp.width / 2, r - tp.height / 2));

    final image = await recorder.endRecording().toImage(d.toInt(), d.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final icon = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: dpr,
    );
    _clusterIconCache[label] = icon;
    return icon;
  }
  
  void _mapLog(String message) {
    debugPrint('[MapPage] $message');
  }

  Future<void> _safeAnimateCamera(CameraUpdate update) async {
    if (_controller == null || !_mapControllerReady) {
      _mapLog('animateCamera skipped (controller not ready)');
      return;
    }
    try {
      await _controller!.animateCamera(update);
    } catch (e, st) {
      _mapLog('animateCamera failed: $e');
      debugPrint('$st');
    }
  }
  final ProjectBoundaryService _boundaryService = ProjectBoundaryService();
  final TreeService _treeService = TreeService();
  final LocationService _locationService = LocationService();
  List<ProjectBoundary> _projectBoundaries = [];

  // 台灣中心點作為預設位置
  static const LatLng _defaultLocation = LatLng(23.7, 121.0);

  @override
  void initState() {
    super.initState();
    ApiService.triggerCleanup();
    _loadMapMeta();
    _loadProjectBoundaries(forceRefresh: false); // V3: 載入專案邊界
    _loadPermissions(); // [T7] 載入角色權限
    // 延遲請求權限，確保 widget 已完全建立
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationPermission();
    });
  }

  // [T7] 載入使用者角色權限
  Future<void> _loadPermissions() async {
    final canManage = await AuthService.canManageProjects();
    if (mounted) setState(() => _canManageProjects = canManage);
  }

  // V3: 載入專案邊界
  Future<void> _loadProjectBoundaries({bool forceRefresh = false}) async {
    try {
      _projectBoundaries =
          await _boundaryService.getAllBoundaries(forceRefresh: forceRefresh);
      _updateBoundaryPolygons();
    } catch (e) {
      debugPrint('載入專案邊界錯誤: $e');
    }
  }

  /// 依目前縣市／專案篩選，從快取樹木解析專案代碼（優先符合縣市條件）。
  String? _resolveSelectedProjectCode() {
    if (_selectedProject == '全部') return null;

    String? fromCityScoped;
    String? fromAny;
    for (final tree in _cachedTreeData) {
      if (tree['專案名稱'] != _selectedProject) continue;
      final code = tree['專案代碼']?.toString().trim();
      if (code == null || code.isEmpty) continue;
      fromAny ??= code;
      if (_selectedCity != '全部' &&
          _cityMatches(tree['_city']?.toString(), _selectedCity)) {
        fromCityScoped ??= code;
      }
    }
    return fromCityScoped ?? fromAny;
  }

  bool _boundaryMatchesSelectedProject(ProjectBoundary boundary) {
    if (_selectedProject == '全部') return true;

    final selectedCode = _resolveSelectedProjectCode();
    final boundaryCode = boundary.projectCode?.toString().trim();
    if (selectedCode != null &&
        boundaryCode != null &&
        selectedCode == boundaryCode) {
      return true;
    }
    return _normalizeProjectLabel(boundary.projectName) ==
        _normalizeProjectLabel(_selectedProject);
  }

  /// 相容「植栽第1區」與「植栽1區」等命名差異（高雄港區常見）。
  String _normalizeProjectLabel(String name) {
    return name.trim().replaceAll('植栽第', '植栽');
  }

  /// 縣市篩選時，僅顯示該縣市樹木資料中出現過的專案邊界。
  bool _boundaryMatchesSelectedCity(ProjectBoundary boundary) {
    if (_selectedCity == '全部') return true;

    final code = boundary.projectCode?.toString().trim();
    for (final tree in _cachedTreeData) {
      if (!_cityMatches(tree['_city']?.toString(), _selectedCity)) continue;
      if (code != null && code.isNotEmpty) {
        if (tree['專案代碼']?.toString().trim() == code) return true;
      } else if (tree['專案名稱'] == boundary.projectName) {
        return true;
      }
    }
    return false;
  }

  bool _shouldShowBoundary(ProjectBoundary boundary) {
    if (!_showBoundaries) return false;
    if (!_boundaryMatchesSelectedCity(boundary)) return false;
    return _boundaryMatchesSelectedProject(boundary);
  }

  // V3: 更新邊界多邊形
  void _updateBoundaryPolygons() {
    if (!_showBoundaries) {
      _safeSetState(() => _polygons = {});
      return;
    }

    // 生成顏色
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];

    final nextPolygons = <Polygon>{};
    for (int i = 0; i < _projectBoundaries.length; i++) {
      final boundary = _projectBoundaries[i];
      if (!_shouldShowBoundary(boundary)) continue;

      final color = colors[i % colors.length];
      final points = boundary.coordinates
          .map((c) => LatLng(c[0], c[1]))
          .toList();

      if (points.length >= 3) {
        nextPolygons.add(Polygon(
          polygonId: PolygonId('boundary_${boundary.projectCode ?? boundary.projectName}'),
          points: points,
          strokeColor: color,
          strokeWidth: 2,
          fillColor: color.withValues(alpha: 0.15),
          consumeTapEvents: true,
          onTap: () => _showBoundaryInfo(boundary),
        ));
      }
    }

    _safeSetState(() => _polygons = nextPolygons);
  }

  // V3: 顯示邊界資訊
  void _showBoundaryInfo(ProjectBoundary boundary) {
    final area = _boundaryService.calculatePolygonArea(boundary.coordinates);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.crop_square, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(boundary.projectName, overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (boundary.projectCode != null)
              Text('區代碼：${boundary.projectCode}'),
            Text('頂點數量：${boundary.coordinates.length}'),
            Text('面積：${area.toStringAsFixed(2)} 公頃'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToBoundaryDrawPage(boundary.projectName);
            },
            child: const Text('編輯邊界'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  // V3: 導航到邊界繪製頁面
  void _navigateToBoundaryDrawPage([String? projectName]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectBoundaryDrawPage(
          projectName: projectName,
        ),
      ),
    );
    // 返回後重新載入邊界
    _loadProjectBoundaries();
  }

  // V3: 顯示邊界列表對話框
  void _showBoundaryListDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.crop_square, color: AppColors.primary),
            SizedBox(width: 8),
            Text('區邊界列表'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _projectBoundaries.length,
            itemBuilder: (context, index) {
              final boundary = _projectBoundaries[index];
              final area = _boundaryService.calculatePolygonArea(boundary.coordinates);
              
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: [
                    Colors.blue,
                    Colors.green,
                    Colors.orange,
                    Colors.purple,
                    Colors.teal,
                    Colors.pink,
                  ][index % 6].withValues(alpha: 0.2),
                  child: Icon(
                    Icons.crop_square,
                    color: [
                      Colors.blue,
                      Colors.green,
                      Colors.orange,
                      Colors.purple,
                      Colors.teal,
                      Colors.pink,
                    ][index % 6],
                  ),
                ),
                title: Text(
                  boundary.projectName,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${boundary.coordinates.length} 頂點 · ${area.toStringAsFixed(1)} 公頃'),
                trailing: IconButton(
                  icon: const Icon(Icons.center_focus_strong),
                  onPressed: () {
                    Navigator.pop(context);
                    _focusOnBoundary(boundary);
                  },
                  tooltip: '移動至此區域',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showBoundaryInfo(boundary);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  // V3: 聚焦到特定邊界
  void _focusOnBoundary(ProjectBoundary boundary) {
    final center = _boundaryService.calculatePolygonCenter(boundary.coordinates);
    _safeAnimateCamera(CameraUpdate.newLatLngZoom(
      LatLng(center['lat']!, center['lng']!),
      15,
    ));
  }

  Future<void> _checkLocationPermission() async {
    try {
      // iOS 建議使用 locationWhenInUse
      final status = await Permission.locationWhenInUse.status;
      
      if (status.isGranted) {
        _safeSetState(() {
          _hasLocationPermission = true;
        });
        _getCurrentLocation();
      } else if (status.isDenied) {
        // 尚未請求過，不主動請求，讓使用者點擊按鈕
        _safeSetState(() {
          _hasLocationPermission = false;
        });
      } else if (status.isPermanentlyDenied) {
        _safeSetState(() {
          _hasLocationPermission = false;
        });
      }
    } catch (e) {
      debugPrint('檢查權限錯誤: $e');
      _safeSetState(() {
        _hasLocationPermission = false;
      });
    }
  }

  Future<void> _requestLocationPermission() async {
    try {
      // 優先檢查狀態，避免重複請求導致無反應
      var status = await Permission.locationWhenInUse.status;
      
      if (status.isPermanentlyDenied) {
        if (mounted) {
          _showOpenSettingsDialog();
        }
        return;
      }

      // 請求權限
      status = await Permission.locationWhenInUse.request();
      
      if (status.isGranted) {
        _safeSetState(() {
          _hasLocationPermission = true;
        });
        _getCurrentLocation();
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          _showOpenSettingsDialog();
        }
      }
    } catch (e) {
      debugPrint('請求權限錯誤: $e');
    }
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要位置權限'),
        content: const Text('請在設定中開啟位置權限，以便在地圖上顯示您的位置並進行樹木定位。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍後再說'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('前往設定'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapControllerReady = false;
    _disposed = true;
    GlobalKeys.routeObserver.unsubscribe(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      GlobalKeys.routeObserver.subscribe(this, route);
    }
  }

  // 從子頁返回時僅輕量刷新邊界（避免整頁重載樹木造成閃爍／迴圈）
  @override
  void didPopNext() {
    final now = DateTime.now();
    if (_lastBoundaryRefresh != null &&
        now.difference(_lastBoundaryRefresh!) < const Duration(seconds: 45)) {
      return;
    }
    _lastBoundaryRefresh = now;
    debugPrint('[MapPage] didPopNext: 刷新邊界多邊形（不重整樹木）');
    _loadProjectBoundaries(forceRefresh: false);
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) {
      setState(fn);
    }
  }

  // 載入專案／縣市 meta（輕量），樹木標記依篩選再載入
  Future<void> _loadMapMeta() async {
    _safeSetState(() => _isLoading = true);
    final sw = Stopwatch()..start();
    try {
      _mapLog('meta load start');
      final meta = await _treeService.getMapMeta();
      final projResp = await ProjectService().getProjects(forceRefresh: true);
      final lastScope = await ProjectScopeStore().loadLast();
      if (meta['success'] == true) {
        final nameToCode = <String, String>{};
        final names = <String>{};
        for (final p in ProjectService.projectListFromResponse(projResp)) {
          if (p is! Map) continue;
          final name = p['name']?.toString();
          final code = (p['code'] ?? p['project_code'])?.toString();
          if (name != null && name.isNotEmpty) {
            names.add(name);
            if (code != null && code.isNotEmpty) nameToCode[name] = code;
          }
        }
        final cities = (meta['cities'] as List?)
                ?.map((c) => c.toString())
                .where((c) => c.isNotEmpty)
                .toList() ??
            [];
        final sortedNames = names.toList()..sort();
        String? preselectBlock;
        if (lastScope != null && lastScope.isComplete) {
          if (sortedNames.contains(lastScope.blockName)) {
            preselectBlock = lastScope.blockName;
          }
        }
        _safeSetState(() {
          _projectNameToCode = nameToCode;
          _projects = ['全部', ...sortedNames];
          _filteredProjects = _projects;
          if (preselectBlock != null) {
            _selectedProject = preselectBlock;
          } else {
            _sanitizeSelectedProject();
          }
          _cities = ['全部', ..._extractCitiesFromList(cities)];
          _totalTreeCount = (meta['totalTrees'] as num?)?.toInt() ?? 0;
        });
        if (preselectBlock != null) {
          _mapLog('ProjectScope preselect block=$preselectBlock');
        }
        _mapLog(
          'meta loaded projects=${names.length} cities=${cities.length} '
          'totalTrees=$_totalTreeCount elapsed=${sw.elapsedMilliseconds}ms',
        );
        await _loadMapData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入地圖 meta: $e')),
        );
      }
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  List<String> _extractCitiesFromList(List<String> fromMeta) {
    final cities = {...fromMeta};
    cities.addAll([
      '臺北市', '新北市', '桃園市', '臺中市', '臺南市', '高雄市',
      '基隆市', '新竹市', '新竹縣', '苗栗縣', '彰化縣', '南投縣',
      '雲林縣', '嘉義市', '嘉義縣', '屏東縣', '宜蘭縣', '花蓮縣',
      '臺東縣', '澎湖縣', '金門縣', '連江縣',
    ]);
    return cities.toList()..sort();
  }

  void _sanitizeSelectedProject() {
    if (_filteredProjects.contains(_selectedProject)) return;
    _selectedProject = '全部';
  }

  // 依縣市／專案一次載入標記（預設不用 bbox；拖曳不再自動重載）
  Future<void> _loadMapData() async {
    if (_mapLoadInFlight) return;
    _mapLoadInFlight = true;
    _safeSetState(() => _isLoading = true);
    final sw = Stopwatch()..start();

    try {
      final projectCode = _selectedProject == '全部'
          ? null
          : (_projectNameToCode[_selectedProject] ?? _resolveSelectedProjectCode());

      _mapLog(
        'load start city=$_selectedCity project=$_selectedProject '
        'code=$projectCode mode=filter-all',
      );

      final response = await _treeService.getMapTrees(
        projectCode: projectCode,
        city: _selectedCity == '全部' ? null : _selectedCity,
      );

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;
        _cachedTreeData = data;

        // 縣市載入（專案=全部）後，依快取在地端推導該縣市的專案下拉清單
        if (_selectedProject == '全部') {
          _deriveFilteredProjectsForCity();
        }

        _updateMarkersFromCache();
        if (data.length > 5000 && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '標記數量過多（${data.length} 筆），可能造成地圖當機；請選縣市或區縮小範圍',
              ),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        _mapLog(
          'load done markers=${_markers.length} cached=${data.length} '
          'elapsed=${sw.elapsedMilliseconds}ms',
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法載入資料')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $e')),
        );
      }
    } finally {
      _mapLoadInFlight = false;
      _safeSetState(() => _isLoading = false);
    }
  }

  void _onFilterChanged({bool fitBounds = true}) {
    _fitBoundsOnNextMarkerUpdate = fitBounds;
    _loadMapData();
  }

  /// 縣市比對（相容台/臺、市/縣尾綴）
  bool _cityMatches(String? detected, String selected) {
    if (selected == '全部') return true;
    if (detected == null || detected.isEmpty) return false;
    String norm(String s) => s.trim().replaceAll('台', '臺');
    final d = norm(detected);
    final candidates = <String>{norm(selected)};
    final base = selected.replaceAll(RegExp(r'[市縣]$'), '');
    if (base.isNotEmpty) {
      candidates.addAll([norm('${base}市'), norm('${base}縣')]);
    }
    return candidates.contains(d);
  }

  // 後端已依 city 參數篩選；前端再對專案／縣市做一次防禦性過濾（避免快取混用）
  Future<void> _updateMarkersFromCache() async {
    if (_cachedTreeData.isEmpty) {
      _safeSetState(() => _markers.clear());
      _updateBoundaryPolygons();
      return;
    }

    final trees = _cachedTreeData.where((tree) {
      if (_selectedProject != '全部' && tree['專案名稱'] != _selectedProject) {
        return false;
      }
      // [生命週期] 隱藏已淘汰（枯死/倒塌/移除）的樹（預設顯示，灰階區隔）
      if (_hideRetired && _isRetiredTree(tree)) {
        return false;
      }
      if (_selectedCity != '全部') {
        return _cityMatches(tree['_city']?.toString(), _selectedCity);
      }
      return true;
    }).toList();

    // 解析座標一次，後續聚合／個別模式共用
    final points = <({double lat, double lng, Map<String, dynamic> tree})>[];
    for (final tree in trees) {
      final y = double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
      final x = double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;
      if (y == 0.0 || x == 0.0) continue;
      points.add((lat: y, lng: x, tree: tree));
    }

    final useClusters =
        points.length > _clusterMinCount && _currentZoom < _clusterZoomThreshold;
    final markers = <Marker>{};
    bool capExceeded = false;

    if (useClusters) {
      final clusters = gridCluster<({double lat, double lng, Map<String, dynamic> tree})>(
        points,
        _currentZoom,
        latOf: (p) => p.lat,
        lngOf: (p) => p.lng,
      );
      for (final c in clusters) {
        if (c.isSingle) {
          markers.add(_buildTreeMarker(c.members.first.tree, c.lat, c.lng));
        } else {
          final icon = await _clusterIcon(c.count);
          if (!mounted) return;
          final target = LatLng(c.lat, c.lng);
          markers.add(Marker(
            markerId: MarkerId('cluster_${c.lat}_${c.lng}_${c.count}'),
            position: target,
            icon: icon,
            anchor: const Offset(0.5, 0.5),
            consumeTapEvents: true,
            onTap: () {
              final nextZoom =
                  min(_currentZoom + 2.5, _clusterZoomThreshold + 0.5);
              _safeAnimateCamera(CameraUpdate.newLatLngZoom(target, nextZoom));
            },
          ));
        }
      }
      _mapLog(
          'markers: cluster mode zoom=${_currentZoom.toStringAsFixed(1)} pts=${points.length} clusters=${clusters.length}');
    } else {
      // 個別模式：高縮放或少量點。視窗外的點不畫（高縮放時視窗必然小）。
      // [疊點展開] 同座標多棵樹時，自第 2 棵起以小圓環展開（否則只看得到最上層）。
      final seenCoords = <String, int>{};
      int rendered = 0;
      final cullByBounds =
          points.length > _maxIndividualMarkers && _visibleBounds != null;
      for (final p in points) {
        if (rendered >= _maxIndividualMarkers) {
          capExceeded = true;
          break;
        }
        if (cullByBounds && !_inVisibleBounds(p.lat, p.lng)) continue;
        final pos = nextSpreadPoint(seenCoords, p.lat, p.lng);
        markers.add(_buildTreeMarker(p.tree, pos.lat, pos.lng));
        rendered++;
      }
      _mapLog(
          'markers: individual mode zoom=${_currentZoom.toStringAsFixed(1)} pts=${points.length} rendered=$rendered');
    }

    _safeSetState(() {
      _markers.clear();
      _markers.addAll(markers);
      _markerCapExceeded = capExceeded;
    });

    _updateBoundaryPolygons();

    if (_fitBoundsOnNextMarkerUpdate &&
        points.isNotEmpty &&
        _controller != null &&
        mounted) {
      _fitBoundsOnNextMarkerUpdate = false;
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) _zoomToPoints(points);
      });
    }
  }

  Marker _buildTreeMarker(Map<String, dynamic> tree, double lat, double lng) {
    final projectName = tree['專案名稱'] ?? '未知區';
    final areaName = tree['專案區位'] ?? '未知專案';
    // [生命週期] 已淘汰（枯死/倒塌/移除）的樹以半透明灰紫標記區隔。
    final retired = _isRetiredTree(tree);
    final title = (tree['樹種名稱'] ?? '未知樹種').toString() +
        (retired ? '（已淘汰）' : '');
    return Marker(
      // 確保 MarkerId 唯一，避免覆蓋
      markerId: MarkerId('${tree['id']}_${lng}_$lat'),
      position: LatLng(lat, lng),
      alpha: retired ? 0.5 : 1.0,
      icon: retired
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet)
          : BitmapDescriptor.defaultMarker,
      infoWindow: InfoWindow(
        title: title,
        snippet: '區：$projectName\n專案：$areaName',
        onTap: () => _openTreeDetail(tree),
      ),
      onTap: () => _showTreeMarkerSheet(tree),
    );
  }

  /// 樹木是否已淘汰（lifecycle_status 非 active）。
  static bool _isRetiredTree(Map<String, dynamic> tree) {
    final lc = (tree['lifecycle_status'] ?? tree['生命週期'] ?? 'active')
        .toString()
        .trim();
    return lc.isNotEmpty && lc != 'active';
  }

  /// 點地圖標記後彈出摘要卡（下鑽閉環：地圖 → 摘要 → 詳情）。
  void _showTreeMarkerSheet(Map<String, dynamic> tree) {
    if (!mounted) return;
    final species = tree['樹種名稱']?.toString() ?? '未知樹種';
    final project = tree['專案名稱']?.toString() ?? '未知區';
    final area = tree['專案區位']?.toString() ?? '未知專案';
    final systemId = tree['系統樹木']?.toString() ?? tree['id']?.toString() ?? '—';
    final projectTreeId = tree['專案樹木']?.toString();

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.park, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      species,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _markerSheetRow(Icons.folder_outlined, '區', project),
              _markerSheetRow(Icons.place_outlined, '專案', area),
              _markerSheetRow(Icons.tag, '系統編號', systemId),
              if (projectTreeId != null && projectTreeId.isNotEmpty)
                _markerSheetRow(Icons.numbers, '區編號', projectTreeId),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('查看完整詳情'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openTreeDetail(tree);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _markerSheetRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Text('$label：', style: const TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _openTreeDetail(Map<String, dynamic> tree) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TreeSurveyDetailPage(treeData: tree),
      ),
    );
  }

  // 切換縣市時，先把專案重設為「全部」並重新載入該縣市的樹木；
  // 專案下拉清單改由 [_loadMapData] 在載入後，依「已按縣市過濾的快取樹木」
  // 在地端推導（_deriveFilteredProjectsForCity）。
  //
  // 之前是呼叫 `projects/by_area/<city>`，但該路由的 `:area` 是「區位名稱」
  // 而非「縣市」，把縣市當區位送進去永遠查不到 → 專案選單塌成只剩「全部」，
  // 也就是使用者回報的「專案選單不再配合縣市」。改用在地推導後不需後端配合。
  void _updateProjectsForCity(String city) {
    _safeSetState(() {
      if (city == '全部') {
        _filteredProjects = _projects;
      }
      _selectedProject = '全部';
    });
    _onFilterChanged();
  }

  /// 依目前 `_cachedTreeData`（已按所選縣市過濾）推導該縣市出現過的專案清單。
  /// 僅在「專案 = 全部」的載入後呼叫，避免被單一專案的結果塌縮。
  void _deriveFilteredProjectsForCity() {
    if (_selectedCity == '全部') {
      _safeSetState(() => _filteredProjects = _projects);
      return;
    }
    final names = <String>{};
    final nameToCode = <String, String>{..._projectNameToCode};
    for (final tree in _cachedTreeData) {
      final name = tree['專案名稱']?.toString();
      if (name == null || name.isEmpty) continue;
      names.add(name);
      final code = tree['專案代碼']?.toString().trim();
      if (code != null && code.isNotEmpty) nameToCode[name] = code;
    }
    final list = names.toList()..sort();
    _safeSetState(() {
      _filteredProjects = ['全部', ...list];
      _projectNameToCode = nameToCode;
      _sanitizeSelectedProject();
    });
  }

  // [Stage 1] 縣市下拉選單：列出資料中出現過的 _city + 完整台灣 22 縣市。
  // 之前需要自行解析區位名稱，現在直接讀伺服器標註的 _city 欄位即可。
  List<String> _extractCitiesFromData(List<dynamic> data) {
    final Set<String> cities = {};

    for (var tree in data) {
      final c = tree['_city'];
      if (c != null && c is String && c.isNotEmpty) {
        cities.add(c);
      }
    }

    cities.addAll([
      '臺北市', '新北市', '桃園市', '臺中市', '臺南市', '高雄市',
      '基隆市', '新竹市', '新竹縣', '苗栗縣', '彰化縣', '南投縣',
      '雲林縣', '嘉義市', '嘉義縣', '屏東縣', '宜蘭縣', '花蓮縣',
      '臺東縣', '澎湖縣', '金門縣', '連江縣',
    ]);

    return cities.toList()..sort();
  }

  // [Stage 1] _extractCityFromArea / _isCoordinateInCity 已移除
  // 縣市判斷統一在後端 utils/county.resolveAreaCity (座標優先 + areaName fallback)，
  // 透過 /tree_survey/map 回應的 _city 欄位帶到前端，不再有兩套不一致的邏輯。

  /// 以「全部資料點」為準調整視野（cluster 模式下 _markers 只是聚合圓點）
  void _zoomToPoints(
      List<({double lat, double lng, Map<String, dynamic> tree})> points) {
    if (points.isEmpty || _controller == null) return;
    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLng = points.first.lng, maxLng = points.first.lng;
    for (final p in points) {
      minLat = min(minLat, p.lat);
      maxLat = max(maxLat, p.lat);
      minLng = min(minLng, p.lng);
      maxLng = max(maxLng, p.lng);
    }
    _safeAnimateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      50,
    ));
  }

  void _zoomToMarkers() {
    // [UX] 原本空集合/未就緒時靜默 return，使用者會覺得「按了沒反應」——改給明確回饋
    if (_markers.isEmpty) {
      _mapLog('zoomToMarkers: no markers');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('目前沒有可顯示的樹木標記（請確認篩選條件）'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (_controller == null || !_mapControllerReady) {
      _mapLog('zoomToMarkers: controller not ready');
      return;
    }

    double minLat = _markers.first.position.latitude;
    double maxLat = _markers.first.position.latitude;
    double minLng = _markers.first.position.longitude;
    double maxLng = _markers.first.position.longitude;

    for (var marker in _markers) {
      minLat = min(minLat, marker.position.latitude);
      maxLat = max(maxLat, marker.position.latitude);
      minLng = min(minLng, marker.position.longitude);
      maxLng = max(maxLng, marker.position.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    _mapLog('zoomToMarkers: fit ${_markers.length} markers');
    _safeAnimateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    _mapControllerReady = true;
    _mapLog('map created');
  }

  Future<void> _getCurrentLocation() async {
    if (!_hasLocationPermission) return;
    
    try {
      final position = await getHighAccuracyPosition();
      if (position != null) {
        _safeSetState(() {
          _currentPosition = position;
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  String? _findCityOption(String shortOrFull) {
    if (shortOrFull.trim().isEmpty) return null;
    String norm(String s) => s.trim().replaceAll('台', '臺');
    final target = norm(shortOrFull);
    for (final city in _cities) {
      if (city == '全部') continue;
      if (_cityMatches(city, shortOrFull) || _cityMatches(shortOrFull, city)) {
        return city;
      }
      final base = city.replaceAll(RegExp(r'[市縣]$'), '');
      if (norm(base) == target) return city;
    }
    return null;
  }

  /// 依手機 GPS 定位並自動篩選所在縣市。
  Future<void> _useMyLocation() async {
    if (!_hasLocationPermission) {
      await _requestLocationPermission();
      if (!_hasLocationPermission) return;
    }

    _safeSetState(() => _isLoading = true);
    try {
      final position = await getHighAccuracyPosition();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法取得目前位置')),
          );
        }
        return;
      }

      _safeSetState(() => _currentPosition = position);

      if (_controller != null && _mapControllerReady) {
        await _safeAnimateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            14,
          ),
        );
      }

      final resp = await _locationService.suggestArea(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (resp['success'] == true) {
        final shortName = resp['suggestedArea']?.toString() ?? '';
        final matched = _findCityOption(shortName);
        if (matched != null) {
          _safeSetState(() {
            _selectedCity = matched;
            _selectedProject = '全部';
          });
          _onFilterChanged(fitBounds: false);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已依目前位置篩選：$matched')),
            );
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已定位至目前位置（$shortName）')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位失敗: $e')),
        );
      }
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.portBlue, Color(0xFF1565C0)],
            ),
          ),
        ),
        title: const Text(
          '樹木位置地圖',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // V3: 專案邊界控制
          PopupMenuButton<String>(
            icon: const Icon(Icons.crop_square),
            tooltip: '區邊界',
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'toggle',
                child: Row(
                  children: [
                    Icon(
                      _showBoundaries ? Icons.visibility : Icons.visibility_off,
                      color: _showBoundaries ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(_showBoundaries ? '隱藏邊界' : '顯示邊界'),
                  ],
                ),
              ),
              // [T7] 僅專案管理員以上顯示
              if (_canManageProjects)
                const PopupMenuItem(
                  value: 'draw',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('繪製邊界'),
                    ],
                  ),
                ),
              if (_projectBoundaries.isNotEmpty)
                PopupMenuItem(
                  value: 'list',
                  child: Row(
                    children: [
                      const Icon(Icons.list, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text('邊界列表 (${_projectBoundaries.length})'),
                    ],
                  ),
                ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'toggle':
                  setState(() {
                    _showBoundaries = !_showBoundaries;
                  });
                  _updateBoundaryPolygons();
                  break;
                case 'draw':
                  _navigateToBoundaryDrawPage();
                  break;
                case 'list':
                  _showBoundaryListDialog();
                  break;
              }
            },
          ),
          IconButton(
            icon: Icon(_showMenu ? Icons.filter_list_off : Icons.filter_list),
            onPressed: () {
              setState(() {
                _showMenu = !_showMenu;
              });
            },
            tooltip: _showMenu ? '隱藏篩選選單' : '顯示篩選選單',
          ),
          IconButton(
            icon: Icon(_hideRetired
                ? Icons.do_not_disturb_on
                : Icons.do_not_disturb_off_outlined),
            onPressed: () {
              setState(() => _hideRetired = !_hideRetired);
              _updateMarkersFromCache();
            },
            tooltip: _hideRetired ? '顯示已淘汰樹木' : '隱藏已淘汰樹木',
          ),
          IconButton(
            icon: const Icon(Icons.layers),
            onPressed: () {
              setState(() {
                _currentMapType = _currentMapType == MapType.normal
                    ? MapType.satellite
                    : MapType.normal;
              });
            },
            tooltip: '切換地圖類型',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _fitBoundsOnNextMarkerUpdate = true;
              _loadMapMeta();
              _loadProjectBoundaries(forceRefresh: true);
            },
            tooltip: '重新載入資料',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            onCameraIdle: _onCameraIdle,
            initialCameraPosition: CameraPosition(
              target: _currentPosition != null
                  ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                  : _defaultLocation,
              zoom: _currentPosition != null ? 15 : 7,
            ),
            markers: _markers,
            polygons: _polygons, // V3: 專案邊界多邊形
            // [N13 fix] 避免外層手勢變裝（如 BottomNavigation / TabBar袈動）拍走地圖的拖動手勢
            gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
            },
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false, // 移除 Android 預設縮放按鈕
            mapToolbarEnabled: true,
            compassEnabled: true,
            padding: EdgeInsets.only(
              top: _showMenu ? (_hasLocationPermission ? 140 : 220) : 0,
              bottom: 100,
              right: 60,
            ),
            mapType: _currentMapType,
          ),
          if (_markerCapExceeded)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.62),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '此視野標記過多，僅顯示部分；請放大地圖或用篩選縮小範圍',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          if (_showMenu) ...[
            if (!_hasLocationPermission)
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: Card(
                    elevation: 4,
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.shade300),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(Icons.location_off, color: Colors.amber.shade700, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '需要位置權限',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '開啟後可顯示您的位置',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.amber.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _requestLocationPermission,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            child: const Text('開啟'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: _hasLocationPermission ? 0 : 85,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_city, size: 16, color: Color(0xFF0D47A1)),
                              SizedBox(width: 4),
                              Text('縣市',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedCity,
                            // 面板為固定白底；釘住前景色避免暗色主題下白箭頭/白字看不到
                            iconEnabledColor: Colors.grey.shade700,
                            style: const TextStyle(color: Colors.black87, fontSize: 16),
                            dropdownColor: Colors.white,
                            underline: Container(height: 1, color: Colors.grey.shade300),
                            items: _cities.map((city) {
                              return DropdownMenuItem<String>(
                                value: city,
                                child: Text(city, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                _safeSetState(() {
                                  _selectedCity = value;
                                });
                                _updateProjectsForCity(value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _isLoading ? null : _useMyLocation,
                        icon: const Icon(Icons.my_location, size: 16),
                        label: Text(LocaleService.instance.t('map_use_my_location')),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF0D47A1),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BCD4).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.folder_outlined, size: 16, color: Color(0xFF00838F)),
                              SizedBox(width: 4),
                              Text('區',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00838F), fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _filteredProjects.contains(_selectedProject)
                                ? _selectedProject
                                : '全部',
                            // 面板為固定白底；釘住前景色避免暗色主題下白箭頭/白字看不到
                            iconEnabledColor: Colors.grey.shade700,
                            style: const TextStyle(color: Colors.black87, fontSize: 16),
                            dropdownColor: Colors.white,
                            underline: Container(height: 1, color: Colors.grey.shade300),
                            items: _filteredProjects.map((project) {
                              return DropdownMenuItem<String>(
                                value: project,
                                child: Text(project, overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                _safeSetState(() {
                                  _selectedProject = value;
                                });
                                _onFilterChanged();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0D47A1).withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.park, size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '顯示 ${_markers.length} 棵'
                                '${_totalTreeCount > 0 && _markers.length < _totalTreeCount ? ' / 共 $_totalTreeCount' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ],
          if (_isLoading)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
              child: Center(
                child: Card(
                  elevation: 12,
                  shadowColor: const Color(0xFF0D47A1).withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Colors.white, Color(0xFFF5F9FF)],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D47A1)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '載入地圖資料中...',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A237E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.park_outlined, size: 16, color: AppColors.leafGreen),
                            const SizedBox(width: 6),
                            Text(
                              '正在取得樹木位置',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _hasLocationPermission 
                    ? const Color(0xFF0D47A1).withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: FloatingActionButton(
              heroTag: 'locationButton',
              mini: true,
              backgroundColor: _hasLocationPermission 
                ? Colors.white 
                : Colors.grey.shade100,
              elevation: 0,
              onPressed: () async {
                if (!_hasLocationPermission) {
                  await _requestLocationPermission();
                  return;
                }
                if (_currentPosition != null) {
                  await _safeAnimateCamera(
                    CameraUpdate.newLatLng(
                      LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                    ),
                  );
                } else {
                  await _getCurrentLocation();
                  if (_currentPosition != null) {
                    await _safeAnimateCamera(
                      CameraUpdate.newLatLng(
                        LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                      ),
                    );
                  }
                }
              },
              child: Icon(
                _hasLocationPermission ? Icons.my_location : Icons.location_disabled,
                color: _hasLocationPermission ? const Color(0xFF0D47A1) : Colors.grey,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FloatingActionButton(
              heroTag: 'zoomButton',
              onPressed: _zoomToMarkers,
              tooltip: '顯示所有標記',
              backgroundColor: const Color(0xFF0D47A1),
              elevation: 0,
              child: const Icon(Icons.zoom_out_map, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
