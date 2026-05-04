import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'services/api_service.dart';
import 'utils/location_helper.dart';
import 'services/v3/project_boundary_service.dart';
import 'screens/v3/project_boundary_draw_page.dart';
import 'services/auth_service.dart'; // [T7] 角色權限
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
  final Set<Polygon> _polygons = {}; // V3: 專案邊界多邊形
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
  bool _canManageProjects = false; // [T7] 是否可繪製邊界

  // [優化] 快取樹木資料，避免重複呼叫 API
  List<dynamic> _cachedTreeData = [];
  
  // V3: 專案邊界服務
  final ProjectBoundaryService _boundaryService = ProjectBoundaryService();
  List<ProjectBoundary> _projectBoundaries = [];

  // 台灣中心點作為預設位置
  static const LatLng _defaultLocation = LatLng(23.7, 121.0);

  @override
  void initState() {
    super.initState();
    ApiService.triggerCleanup();
    _loadMapData();
    _loadProjectBoundaries(); // V3: 載入專案邊界
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
  Future<void> _loadProjectBoundaries() async {
    try {
      _projectBoundaries = await _boundaryService.getAllBoundaries(forceRefresh: true);
      _updateBoundaryPolygons();
    } catch (e) {
      debugPrint('載入專案邊界錯誤: $e');
    }
  }

  // V3: 更新邊界多邊形
  void _updateBoundaryPolygons() {
    _polygons.clear();
    
    if (!_showBoundaries) {
      _safeSetState(() {});
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

    for (int i = 0; i < _projectBoundaries.length; i++) {
      final boundary = _projectBoundaries[i];
      final color = colors[i % colors.length];
      
      // 如果選擇了特定專案，只顯示該專案的邊界
      if (_selectedProject != '全部' && boundary.projectName != _selectedProject) {
        continue;
      }

      final points = boundary.coordinates
          .map((c) => LatLng(c[0], c[1]))
          .toList();

      if (points.length >= 3) {
        _polygons.add(Polygon(
          polygonId: PolygonId('boundary_${boundary.projectName}'),
          points: points,
          strokeColor: color,
          strokeWidth: 2,
          fillColor: color.withValues(alpha: 0.15),
          consumeTapEvents: true,
          onTap: () => _showBoundaryInfo(boundary),
        ));
      }
    }

    _safeSetState(() {});
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
              Text('專案代碼：${boundary.projectCode}'),
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
            Text('專案邊界列表'),
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
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(
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

  // [Bug B 修復] 從別頁返回 MapPage 時強制刷新邊界與樹木資料，避免顯示快取
  @override
  void didPopNext() {
    debugPrint('[MapPage] didPopNext: 強制刷新邊界與樹木資料');
    _loadMapData();
    _loadProjectBoundaries();
  }

  void _safeSetState(VoidCallback fn) {
    if (!_disposed && mounted) {
      setState(fn);
    }
  }

  // [優化] 一次性載入所有地圖資料
  Future<void> _loadMapData() async {
    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // [優化] 使用精簡版 API
      final response = await ApiService.get('tree_survey/map');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;
        _cachedTreeData = data;

        final projects = data
            .map((tree) => tree['專案名稱'] as String?)
            .where((name) => name != null && name.isNotEmpty)
            .cast<String>()
            .toSet()
            .toList();

        final cities = _extractCitiesFromData(data);

        _safeSetState(() {
          _projects = ['全部', ...projects];
          _cities = ['全部', ...cities];
        });

        // 不直接設 _filteredProjects：交給 _updateProjectsForCity 依當前 _selectedCity
        // 重算，變 Reload【選了花蓮縣 → 切走別頁 → didPopNext 重載】時不會被全部專案覆寫。
        _updateProjectsForCity(_selectedCity);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法載入資料')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $e')),
        );
      }
    } finally {
      _safeSetState(() {
        _isLoading = false;
      });
    }
  }

  // [優化] 從快取資料更新地圖標記
  // [Stage 1] city 過濾改用伺服器權威 _city 欄位（utils/county.resolveAreaCity 解析）
  void _updateMarkersFromCache() {
    if (_cachedTreeData.isEmpty) return;

    final trees = _cachedTreeData.where((tree) {
      if (_selectedProject != '全部' && tree['專案名稱'] != _selectedProject) {
        return false;
      }
      if (_selectedCity != '全部') {
        return tree['_city'] == _selectedCity;
      }
      return true;
    }).toList();

    final markers = trees.map((tree) {
      try {
        final y = double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
        final x = double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;
        if (y == 0.0 || x == 0.0) return null;

        final projectName = tree['專案名稱'] ?? '未知專案';
        final areaName = tree['專案區位'] ?? '未知區位';
        // 確保 MarkerId 唯一，避免覆蓋
        final markerId = '${tree['id']}_${x}_$y';
        
        return Marker(
          markerId: MarkerId(markerId),
          position: LatLng(y, x),
          infoWindow: InfoWindow(
            title: tree['樹種名稱'] ?? '未知樹種',
            snippet: '專案：$projectName\n區位：$areaName',
          ),
        );
      } catch (e) {
        return null;
      }
    }).where((marker) => marker != null).cast<Marker>().toSet();

    _safeSetState(() {
      _markers.clear();
      _markers.addAll(markers);
    });

    // V3: 同時更新邊界多邊形
    _updateBoundaryPolygons();

    if (_markers.isNotEmpty && _controller != null && mounted) {
      _zoomToMarkers();
    }
  }

  void _updateProjectsForCity(String city) {
    if (city == '全部') {
      // 縣市=全部 → 列出所有專案；若使用者已選的專案還在就保留，不在就回 '全部'
      final keepSelected = _projects.contains(_selectedProject);
      _safeSetState(() {
        _filteredProjects = _projects;
        if (!keepSelected) _selectedProject = '全部';
      });
      _updateMarkersFromCache();
      return;
    }

    // [Stage 1] 使用伺服器權威 _city 欄位，不再自行解析名稱/座標
    final filteredTrees = _cachedTreeData.where((tree) => tree['_city'] == city);

    final cityProjects = filteredTrees
        .map((tree) => tree['專案名稱'] as String?)
        .where((name) => name != null && name.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    final newList = ['全部', ...cityProjects];
    final keepSelected = newList.contains(_selectedProject);

    _safeSetState(() {
      _filteredProjects = newList;
      if (!keepSelected) _selectedProject = '全部';
    });

    _updateMarkersFromCache();
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

  void _zoomToMarkers() {
    if (_markers.isEmpty || _controller == null) return;

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

    _controller!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;
    if (_markers.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _zoomToMarkers();
      });
    }
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
            tooltip: '專案邊界',
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
              _loadMapData();
              _loadProjectBoundaries();
            },
            tooltip: '重新載入資料',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
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
                              Text('專案',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00838F), fontSize: 13)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedProject,
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
                                _updateMarkersFromCache();
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
                            '共有 ${_markers.length} 棵樹',
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
                if (_currentPosition != null && _controller != null) {
                  await _controller!.animateCamera(
                    CameraUpdate.newLatLng(
                      LatLng(
                        _currentPosition!.latitude,
                        _currentPosition!.longitude,
                      ),
                    ),
                  );
                } else {
                  await _getCurrentLocation();
                  if (_currentPosition != null && _controller != null) {
                    await _controller!.animateCamera(
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
