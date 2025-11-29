import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'services/api_service.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? _controller;
  final Set<Marker> _markers = {};
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

  // [優化] 快取樹木資料，避免重複呼叫 API
  List<dynamic> _cachedTreeData = [];

  // 台灣中心點作為預設位置
  static const LatLng _defaultLocation = LatLng(23.7, 121.0);

  @override
  void initState() {
    super.initState();
    ApiService.triggerCleanup();
    _loadMapData();
    // 延遲請求權限，確保 widget 已完全建立
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLocationPermission();
    });
  }

  Future<void> _checkLocationPermission() async {
    try {
      final status = await Permission.location.status;
      
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
      final status = await Permission.location.request();
      
      if (status.isGranted) {
        _safeSetState(() {
          _hasLocationPermission = true;
        });
        _getCurrentLocation();
      } else if (status.isPermanentlyDenied) {
        // 使用者永久拒絕，引導到設定頁面
        if (mounted) {
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
      }
    } catch (e) {
      debugPrint('請求權限錯誤: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _controller?.dispose();
    super.dispose();
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
          _filteredProjects = ['全部', ...projects];
          _cities = ['全部', ...cities];
        });

        _updateMarkersFromCache();
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
  void _updateMarkersFromCache() {
    if (_cachedTreeData.isEmpty) return;

    final trees = _cachedTreeData.where((tree) {
      if (_selectedProject != '全部' && tree['專案名稱'] != _selectedProject) {
        return false;
      }

      if (_selectedCity != '全部') {
        final y = double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
        final x = double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;

        if (x != 0.0 && y != 0.0) {
          if (_isCoordinateInCity(x, y, _selectedCity)) {
            return true;
          }
        }

        if (tree['專案區位'] != null) {
          final area = tree['專案區位'].toString();
          String? extractedCity = _extractCityFromArea(area);
          if (extractedCity == _selectedCity) {
            return true;
          }
        }
        return false;
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
        return Marker(
          markerId: MarkerId(tree['id'].toString()),
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

    if (_markers.isNotEmpty && _controller != null && mounted) {
      _zoomToMarkers();
    }
  }

  void _updateProjectsForCity(String city) {
    if (city == '全部') {
      _safeSetState(() {
        _filteredProjects = _projects;
        _selectedProject = '全部';
      });
      _updateMarkersFromCache();
      return;
    }

    final filteredTrees = _cachedTreeData.where((tree) {
      final y = double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
      final x = double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;

      bool matchesAreaName = false;
      if (tree['專案區位'] != null) {
        final area = tree['專案區位'].toString();
        String? extractedCity = _extractCityFromArea(area);
        matchesAreaName = (extractedCity == city);
      }

      bool matchesCoordinate = false;
      if (x != 0.0 && y != 0.0) {
        matchesCoordinate = _isCoordinateInCity(x, y, city);
      }

      return matchesAreaName || matchesCoordinate;
    });

    final cityProjects = filteredTrees
        .map((tree) => tree['專案名稱'] as String?)
        .where((name) => name != null && name.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    _safeSetState(() {
      _filteredProjects = ['全部', ...cityProjects];
      _selectedProject = '全部';
    });

    _updateMarkersFromCache();
  }

  List<String> _extractCitiesFromData(List<dynamic> data) {
    final Set<String> cities = {};

    for (var tree in data) {
      if (tree['專案區位'] != null) {
        final area = tree['專案區位'].toString();
        String? extractedCity = _extractCityFromArea(area);
        if (extractedCity != null) {
          cities.add(extractedCity);
        }
      }
    }

    cities.addAll([
      '台北市', '新北市', '桃園市', '台中市', '台南市', '高雄市',
      '基隆市', '新竹市', '新竹縣', '苗栗縣', '彰化縣', '南投縣',
      '雲林縣', '嘉義市', '嘉義縣', '屏東縣', '宜蘭縣', '花蓮縣',
      '台東縣', '澎湖縣', '金門縣', '連江縣',
    ]);

    return cities.toList()..sort();
  }

  String? _extractCityFromArea(String area) {
    final Map<String, List<String>> cityKeywords = {
      '台北市': ['台北', '臺北', '北市'],
      '新北市': ['新北'],
      '桃園市': ['桃園'],
      '台中市': ['台中', '臺中', '中市'],
      '台南市': ['台南', '臺南', '南市'],
      '高雄市': ['高雄', '高市'],
      '基隆市': ['基隆'],
      '新竹市': ['新竹市', '竹市'],
      '新竹縣': ['新竹縣', '竹縣'],
      '苗栗縣': ['苗栗'],
      '彰化縣': ['彰化'],
      '南投縣': ['南投'],
      '雲林縣': ['雲林'],
      '嘉義市': ['嘉義市', '嘉市'],
      '嘉義縣': ['嘉義縣', '嘉縣'],
      '屏東縣': ['屏東'],
      '宜蘭縣': ['宜蘭', '蘭陽', '羅東', '冬山', '礁溪'],
      '花蓮縣': ['花蓮'],
      '台東縣': ['台東', '臺東'],
      '澎湖縣': ['澎湖'],
      '金門縣': ['金門'],
      '連江縣': ['連江', '馬祖'],
    };

    for (var city in cityKeywords.keys) {
      if (cityKeywords[city]!.any((keyword) => area.contains(keyword))) {
        return city;
      }
    }

    if (area.contains('蘭') && !area.contains('花蘭')) {
      return '宜蘭縣';
    }

    return null;
  }

  bool _isCoordinateInCity(double x, double y, String city) {
    if (city == '全部') return true;

    String simplifiedCity = city.replaceAll('市', '').replaceAll('縣', '');

    Map<String, Map<String, double>> cityBounds = {
      '台北': {'minLat': 25.01, 'maxLat': 25.22, 'minLng': 121.45, 'maxLng': 121.65},
      '新北': {'minLat': 24.70, 'maxLat': 25.30, 'minLng': 121.28, 'maxLng': 122.05},
      '桃園': {'minLat': 24.80, 'maxLat': 25.10, 'minLng': 121.10, 'maxLng': 121.45},
      '台中': {'minLat': 24.05, 'maxLat': 24.40, 'minLng': 120.55, 'maxLng': 121.05},
      '台南': {'minLat': 22.90, 'maxLat': 23.40, 'minLng': 120.10, 'maxLng': 120.50},
      '高雄': {'minLat': 22.40, 'maxLat': 23.00, 'minLng': 120.15, 'maxLng': 120.50},
      '基隆': {'minLat': 25.05, 'maxLat': 25.20, 'minLng': 121.65, 'maxLng': 121.85},
      '新竹': {'minLat': 24.70, 'maxLat': 24.85, 'minLng': 120.90, 'maxLng': 121.05},
      '嘉義': {'minLat': 23.45, 'maxLat': 23.55, 'minLng': 120.40, 'maxLng': 120.50},
      '宜蘭': {'minLat': 24.50, 'maxLat': 24.90, 'minLng': 121.65, 'maxLng': 121.95},
      '花蓮': {'minLat': 23.30, 'maxLat': 24.40, 'minLng': 121.30, 'maxLng': 121.65},
      '台東': {'minLat': 22.50, 'maxLat': 23.40, 'minLng': 120.90, 'maxLng': 121.20},
      '澎湖': {'minLat': 23.45, 'maxLat': 23.70, 'minLng': 119.40, 'maxLng': 119.70},
      '金門': {'minLat': 24.40, 'maxLat': 24.55, 'minLng': 118.25, 'maxLng': 118.45},
      '連江': {'minLat': 25.95, 'maxLat': 26.30, 'minLng': 119.90, 'maxLng': 120.20},
      '苗栗': {'minLat': 24.25, 'maxLat': 24.70, 'minLng': 120.65, 'maxLng': 121.10},
      '彰化': {'minLat': 23.85, 'maxLat': 24.15, 'minLng': 120.35, 'maxLng': 120.60},
      '南投': {'minLat': 23.60, 'maxLat': 24.10, 'minLng': 120.75, 'maxLng': 121.15},
      '雲林': {'minLat': 23.55, 'maxLat': 23.80, 'minLng': 120.15, 'maxLng': 120.50},
      '屏東': {'minLat': 22.10, 'maxLat': 22.80, 'minLng': 120.40, 'maxLng': 120.80},
    };

    if (!cityBounds.containsKey(simplifiedCity)) return false;

    var bounds = cityBounds[simplifiedCity]!;
    return y >= bounds['minLat']! && y <= bounds['maxLat']! &&
        x >= bounds['minLng']! && x <= bounds['maxLng']!;
  }

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
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _safeSetState(() {
        _currentPosition = position;
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('樹木位置地圖'),
        actions: [
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
            onPressed: _loadMapData,
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
            myLocationEnabled: _hasLocationPermission,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: true,
            compassEnabled: true,
            padding: EdgeInsets.only(
              top: _hasLocationPermission ? 140 : 220,
              bottom: 100,
              right: 60,
            ),
            mapType: _currentMapType,
          ),
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
                      color: Colors.black.withOpacity(0.1),
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
                          color: const Color(0xFF0D47A1).withOpacity(0.1),
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
                          color: const Color(0xFF00BCD4).withOpacity(0.1),
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
                          color: const Color(0xFF0D47A1).withOpacity(0.3),
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
                            color: Colors.white.withOpacity(0.2),
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
          if (_isLoading)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.5),
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
              child: Center(
                child: Card(
                  elevation: 12,
                  shadowColor: const Color(0xFF0D47A1).withOpacity(0.4),
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
                            color: const Color(0xFF0D47A1).withOpacity(0.1),
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
                            Icon(Icons.park_outlined, size: 16, color: Colors.green.shade400),
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
                    ? const Color(0xFF0D47A1).withOpacity(0.3)
                    : Colors.grey.withOpacity(0.3),
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
                  color: const Color(0xFF0D47A1).withOpacity(0.4),
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
