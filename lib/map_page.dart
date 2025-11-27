import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'services/api_service.dart'; // 引入 ApiService

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
  late CameraPosition _initialPosition;
  Position? _currentPosition;
  MapType _currentMapType = MapType.normal;

  @override
  void initState() {
    super.initState();
    // 觸發一次性的背景清理任務
    ApiService.triggerCleanup();
    _requestLocationPermission();
    _fetchCitiesAndProjects();
    _initialPosition = const CameraPosition(
      target: LatLng(23.7, 121.0), // 台灣中心位置
      zoom: 7,
    );
    _getCurrentLocation();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    setState(() {
      _hasLocationPermission = status.isGranted;
    });
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

  // 同時獲取縣市和專案列表
  Future<void> _fetchCitiesAndProjects() async {
    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // 使用 ApiService 獲取資料並處理標準回應格式
      final response = await ApiService.get('tree_survey');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;

        // 獲取所有不重複的專案名稱
        final projects = data
            .map((tree) => tree['專案名稱'] as String)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList();

        // 嘗試從資料中提取縣市
        final cities = _extractCitiesFromData(data);

        _safeSetState(() {
          _projects = ['全部', ...projects];
          _filteredProjects = ['全部', ...projects];
          _cities = ['全部', ...cities];
        });

        _fetchTrees();
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

  // 更新專案列表以僅顯示特定縣市的專案
  void _updateProjectsForCity(String city) {
    if (city == '全部') {
      _safeSetState(() {
        _filteredProjects = _projects;
        _selectedProject = '全部'; // 重置專案選擇
      });
      _fetchTrees();
      return;
    }

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // 先重置專案選擇
      _selectedProject = '全部';

      // 然後獲取所有樹木數據
      ApiService.get('tree_survey').then((response) {
        if (response != null &&
            response['success'] == true &&
            response['data'] != null) {
          final data = response['data'] as List;
          // 過濾在選定縣市中的樹木
          final filteredTrees = data.where((tree) {
            // 獲取坐標
            final y = double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
            final x = double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;

            // 檢查區位名稱
            bool matchesAreaName = false;
            if (tree['專案區位'] != null) {
              final area = tree['專案區位'].toString();
              String? extractedCity = _extractCityFromArea(area);
              matchesAreaName = (extractedCity == city);
            }

            // 檢查坐標
            bool matchesCoordinate = false;
            if (x != 0.0 && y != 0.0) {
              matchesCoordinate = _isCoordinateInCity(x, y, city);
            }

            return matchesAreaName || matchesCoordinate;
          });

          // 從過濾後的樹木提取專案名稱
          final cityProjects = filteredTrees
              .map((tree) => tree['專案名稱'] as String)
              .where((name) => name != null && name.isNotEmpty)
              .toSet()
              .toList();

          _safeSetState(() {
            // 即使沒有專案，也至少顯示'全部'選項
            _filteredProjects = ['全部', ...cityProjects];
            _isLoading = false;
          });

          // 獲取樹木
          _fetchTrees();
        } else {
          _safeSetState(() {
            _isLoading = false;
            _filteredProjects = ['全部'];
          });
        }
      }).catchError((e) {
        _safeSetState(() {
          _isLoading = false;
          _filteredProjects = ['全部'];
        });
      });
    } catch (e) {
      _safeSetState(() {
        _isLoading = false;
        _filteredProjects = ['全部'];
      });
    }
  }

  // 從資料中提取縣市資訊
  List<String> _extractCitiesFromData(List<dynamic> data) {
    final Set<String> cities = {};

    // 嘗試從專案區位欄位提取縣市
    for (var tree in data) {
      if (tree['專案區位'] != null) {
        final area = tree['專案區位'].toString();
        String? extractedCity = _extractCityFromArea(area);
        if (extractedCity != null) {
          cities.add(extractedCity);
        }
      }
    }

    // 確保添加所有標準縣市，即使資料中沒有出現
    cities.addAll([
      '台北市',
      '新北市',
      '桃園市',
      '台中市',
      '台南市',
      '高雄市',
      '基隆市',
      '新竹市',
      '新竹縣',
      '苗栗縣',
      '彰化縣',
      '南投縣',
      '雲林縣',
      '嘉義市',
      '嘉義縣',
      '屏東縣',
      '宜蘭縣',
      '花蓮縣',
      '台東縣',
      '澎湖縣',
      '金門縣',
      '連江縣',
    ]);

    return cities.toList()..sort();
  }

  // 從區位名稱中提取城市名稱
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

    // 如果沒有找到明確匹配，嘗試進一步分析
    if (area.contains('蘭') && !area.contains('花蘭')) {
      return '宜蘭縣';
    }

    return null;
  }

  // 判斷坐標是否在指定縣市範圍內
  bool _isCoordinateInCity(double x, double y, String city) {
    if (city == '全部') return true;

    // 簡化縣市名稱，去除「市」和「縣」
    String simplifiedCity = city.replaceAll('市', '').replaceAll('縣', '');

    // 定義各縣市的大致坐標範圍
    Map<String, Map<String, double>> cityBounds = {
      '台北': {
        'minLat': 25.01,
        'maxLat': 25.22,
        'minLng': 121.45,
        'maxLng': 121.65
      },
      '新北': {
        'minLat': 24.70,
        'maxLat': 25.30,
        'minLng': 121.28,
        'maxLng': 122.05
      },
      '桃園': {
        'minLat': 24.80,
        'maxLat': 25.10,
        'minLng': 121.10,
        'maxLng': 121.45
      },
      '台中': {
        'minLat': 24.05,
        'maxLat': 24.40,
        'minLng': 120.55,
        'maxLng': 121.05
      },
      '台南': {
        'minLat': 22.90,
        'maxLat': 23.40,
        'minLng': 120.10,
        'maxLng': 120.50
      },
      '高雄': {
        'minLat': 22.40,
        'maxLat': 23.00,
        'minLng': 120.15,
        'maxLng': 120.50
      },
      '基隆': {
        'minLat': 25.05,
        'maxLat': 25.20,
        'minLng': 121.65,
        'maxLng': 121.85
      },
      '新竹': {
        'minLat': 24.70,
        'maxLat': 24.85,
        'minLng': 120.90,
        'maxLng': 121.05
      },
      '嘉義': {
        'minLat': 23.45,
        'maxLat': 23.55,
        'minLng': 120.40,
        'maxLng': 120.50
      },
      '宜蘭': {
        'minLat': 24.50,
        'maxLat': 24.90,
        'minLng': 121.65,
        'maxLng': 121.95
      },
      '花蓮': {
        'minLat': 23.30,
        'maxLat': 24.40,
        'minLng': 121.30,
        'maxLng': 121.65
      },
      '台東': {
        'minLat': 22.50,
        'maxLat': 23.40,
        'minLng': 120.90,
        'maxLng': 121.20
      },
      '澎湖': {
        'minLat': 23.45,
        'maxLat': 23.70,
        'minLng': 119.40,
        'maxLng': 119.70
      },
      '金門': {
        'minLat': 24.40,
        'maxLat': 24.55,
        'minLng': 118.25,
        'maxLng': 118.45
      },
      '連江': {
        'minLat': 25.95,
        'maxLat': 26.30,
        'minLng': 119.90,
        'maxLng': 120.20
      },
      '苗栗': {
        'minLat': 24.25,
        'maxLat': 24.70,
        'minLng': 120.65,
        'maxLng': 121.10
      },
      '彰化': {
        'minLat': 23.85,
        'maxLat': 24.15,
        'minLng': 120.35,
        'maxLng': 120.60
      },
      '南投': {
        'minLat': 23.60,
        'maxLat': 24.10,
        'minLng': 120.75,
        'maxLng': 121.15
      },
      '雲林': {
        'minLat': 23.55,
        'maxLat': 23.80,
        'minLng': 120.15,
        'maxLng': 120.50
      },
      '屏東': {
        'minLat': 22.10,
        'maxLat': 22.80,
        'minLng': 120.40,
        'maxLng': 120.80
      },
    };

    // 檢查該城市是否有定義坐標範圍
    if (!cityBounds.containsKey(simplifiedCity)) {
      return false;
    }

    var bounds = cityBounds[simplifiedCity]!;

    // 檢查坐標是否在該縣市範圍內
    return y >= bounds['minLat']! &&
        y <= bounds['maxLat']! &&
        x >= bounds['minLng']! &&
        x <= bounds['maxLng']!;
  }

  Future<void> _fetchTrees() async {
    if (!mounted) return;

    _safeSetState(() {
      _isLoading = true;
    });

    try {
      // 使用 ApiService 獲取資料並處理標準回應格式
      final response = await ApiService.get('tree_survey');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;
        final trees = data.where((tree) {
          // 先篩選專案
          if (_selectedProject != '全部' && tree['專案名稱'] != _selectedProject) {
            return false;
          }

          // 再篩選縣市
          if (_selectedCity != '全部') {
            // 嘗試從坐標判斷所在縣市
            final y = double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
            final x = double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;

            if (x != 0.0 && y != 0.0) {
              // 使用坐標檢查
              if (_isCoordinateInCity(x, y, _selectedCity)) {
                return true;
              }
            }

            // 如果坐標不可用或不在範圍內，嘗試從區位名稱判斷
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

        final markers = trees
            .map((tree) {
              try {
                // 確保坐標是有效的數字
                final y =
                    double.tryParse(tree['Y坐標']?.toString() ?? '0') ?? 0.0;
                final x =
                    double.tryParse(tree['X坐標']?.toString() ?? '0') ?? 0.0;

                // 檢查坐標是否在有效範圍內
                if (y == 0.0 || x == 0.0) {
                  print('無效的坐標: ${tree['樹種名稱']} - X: $x, Y: $y');
                  return null;
                }

                return Marker(
                  markerId: MarkerId(tree['id'].toString()),
                  position: LatLng(y, x),
                  infoWindow: InfoWindow(
                    title: tree['樹種名稱'] ?? '未知樹種',
                    snippet:
                        '專案：${tree['專案名稱'] ?? '未知專案'}\n區位：${tree['專案區位'] ?? '未知區位'}',
                  ),
                );
              } catch (e) {
                print('處理標記時發生錯誤: $e');
                return null;
              }
            })
            .where((marker) => marker != null)
            .cast<Marker>()
            .toSet();

        _safeSetState(() {
          _markers.clear();
          _markers.addAll(markers);
        });

        if (_markers.isNotEmpty && _controller != null && mounted) {
          _zoomToMarkers();
        } else {
          print('沒有有效的標記或地圖控制器未初始化');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法載入樹木資料')),
          );
        }
      }
    } catch (e) {
      print('獲取樹木資料時發生錯誤: $e');
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

  // 將地圖縮放到顯示所有標記
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

    _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 50),
    );
  }

  void _onMapCreated(GoogleMapController controller) {
    _controller = controller;

    // 地圖完成加載後，如果有標記，縮放地圖以顯示所有標記
    if (_markers.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        _zoomToMarkers();
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
      });
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('樹木位置地圖'),
        backgroundColor: Colors.green.shade100,
        elevation: 0,
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
        ],
      ),
      body: Stack(
        children: [
          _currentPosition == null
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                  onMapCreated: _onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _currentPosition!.latitude,
                      _currentPosition!.longitude,
                    ),
                    zoom: 15,
                  ),
                  markers: _markers,
                  myLocationEnabled: _hasLocationPermission,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  mapToolbarEnabled: true,
                  compassEnabled: true,
                  padding: const EdgeInsets.only(bottom: 120, right: 10),
                  mapType: _currentMapType,
                ),
          if (!_hasLocationPermission)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('需要位置權限才能顯示您的位置'),
                      ElevatedButton(
                        onPressed: _requestLocationPermission,
                        child: const Text('授予權限'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // 自訂定位按鈕
          if (_hasLocationPermission)
            Positioned(
              left: 10,
              bottom: 80, // 調整為更高的位置
              child: FloatingActionButton(
                heroTag: 'locationButton',
                mini: true,
                backgroundColor: Colors.white,
                onPressed: () async {
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
                  }
                },
                child: Icon(Icons.my_location, color: Colors.grey[600]),
              ),
            ),
          // 篩選面板
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white.withOpacity(0.9),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('縣市: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedCity,
                          items: _cities.map((city) {
                            return DropdownMenuItem<String>(
                              value: city,
                              child:
                                  Text(city, overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _safeSetState(() {
                                _selectedCity = value;
                              });
                              // 更新專案列表後再獲取樹木
                              _updateProjectsForCity(value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('專案: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _selectedProject,
                          items: _filteredProjects.map((project) {
                            return DropdownMenuItem<String>(
                              value: project,
                              child: Text(project,
                                  overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              _safeSetState(() {
                                _selectedProject = value;
                              });
                              _fetchTrees();
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  Text('共有 ${_markers.length} 棵樹'),
                ],
              ),
            ),
          ),
          // 載入指示器
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _zoomToMarkers,
        backgroundColor: Colors.green,
        tooltip: '顯示所有標記',
        child: const Icon(Icons.zoom_out_map),
      ),
    );
  }
}
