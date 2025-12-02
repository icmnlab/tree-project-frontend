/// V3 專案邊界繪製頁面
/// 
/// 功能：
/// 1. 在地圖上手動繪製專案邊界多邊形
/// 2. 顯示現有的專案邊界
/// 3. 編輯/刪除專案邊界
/// 4. 驗證新邊界是否涵蓋所有現有樹木

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../services/v3/project_boundary_service.dart';
import '../../services/api_service.dart';
import '../../constants/colors.dart';

class ProjectBoundaryDrawPage extends StatefulWidget {
  final String? projectName;
  final String? projectCode;
  
  const ProjectBoundaryDrawPage({
    super.key,
    this.projectName,
    this.projectCode,
  });

  @override
  State<ProjectBoundaryDrawPage> createState() => _ProjectBoundaryDrawPageState();
}

class _ProjectBoundaryDrawPageState extends State<ProjectBoundaryDrawPage> {
  GoogleMapController? _controller;
  final ProjectBoundaryService _boundaryService = ProjectBoundaryService();
  
  // 繪製模式
  bool _isDrawing = false;
  final List<LatLng> _drawingPoints = [];
  
  // 現有邊界
  List<ProjectBoundary> _existingBoundaries = [];
  ProjectBoundary? _currentProjectBoundary;
  
  // 地圖元素
  final Set<Polygon> _polygons = {};
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  
  // 現有樹木位置（用於驗證邊界）
  List<LatLng> _existingTreeLocations = [];
  
  // UI 狀態
  bool _isLoading = true;
  bool _isSaving = false;
  String? _selectedProject;
  List<String> _availableProjects = [];
  
  // 顏色
  static const Color _drawingColor = Colors.blue;
  static const Color _existingColor = Colors.green;
  static const Color _currentProjectColor = Colors.orange;
  // _treeMarkerColor 用於標記現有樹木，使用 BitmapDescriptor.hueRed 代替

  @override
  void initState() {
    super.initState();
    _selectedProject = widget.projectName;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // 載入專案列表
      final projectsResponse = await ApiService.get('/projects');
      if (projectsResponse['success'] == true) {
        _availableProjects = (projectsResponse['data'] as List)
            .map((p) => p['name'] as String)
            .toList();
      }
      
      // 載入現有邊界
      _existingBoundaries = await _boundaryService.getAllBoundaries(forceRefresh: true);
      
      // 如果有選定專案，載入該專案的樹木位置
      if (_selectedProject != null) {
        final project = _selectedProject!;
        await _loadProjectTrees(project);
        
        // 檢查是否已有邊界
        _currentProjectBoundary = _existingBoundaries
            .where((b) => b.projectName == project)
            .firstOrNull;
      }
      
      _updateMapElements();
      
    } catch (e) {
      debugPrint('[ProjectBoundaryDrawPage] 載入資料錯誤: $e');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadProjectTrees(String projectName) async {
    try {
      // 使用 URL 編碼的專案名稱
      final encodedName = Uri.encodeComponent(projectName);
      final response = await ApiService.get('/tree_survey?project_name=$encodedName');
      
      if (response['success'] == true && response['data'] != null) {
        _existingTreeLocations = (response['data'] as List)
            .where((t) => t['x_coord'] != null && t['y_coord'] != null)
            .map((t) => LatLng(
              (t['y_coord'] as num).toDouble(),
              (t['x_coord'] as num).toDouble(),
            ))
            .toList();
      }
    } catch (e) {
      debugPrint('[ProjectBoundaryDrawPage] 載入樹木資料錯誤: $e');
    }
  }

  void _updateMapElements() {
    _polygons.clear();
    _markers.clear();
    _polylines.clear();
    
    // 添加現有邊界（其他專案）
    for (final boundary in _existingBoundaries) {
      if (boundary.projectName != _selectedProject) {
        _addBoundaryPolygon(boundary, _existingColor.withOpacity(0.3));
      }
    }
    
    // 添加當前專案的現有邊界
    if (_currentProjectBoundary != null) {
      _addBoundaryPolygon(_currentProjectBoundary!, _currentProjectColor.withOpacity(0.4));
    }
    
    // 添加繪製中的多邊形
    if (_drawingPoints.isNotEmpty) {
      _addDrawingPolygon();
    }
    
    // 添加現有樹木標記
    for (int i = 0; i < _existingTreeLocations.length; i++) {
      _markers.add(Marker(
        markerId: MarkerId('tree_$i'),
        position: _existingTreeLocations[i],
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: '樹木 ${i + 1}'),
      ));
    }
    
    // 添加繪製點標記
    for (int i = 0; i < _drawingPoints.length; i++) {
      _markers.add(Marker(
        markerId: MarkerId('draw_$i'),
        position: _drawingPoints[i],
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        draggable: true,
        onDragEnd: (newPosition) => _updateDrawingPoint(i, newPosition),
        infoWindow: InfoWindow(title: '頂點 ${i + 1}'),
      ));
    }
    
    setState(() {});
  }

  void _addBoundaryPolygon(ProjectBoundary boundary, Color color) {
    final points = boundary.coordinates
        .map((c) => LatLng(c[0], c[1]))
        .toList();
    
    _polygons.add(Polygon(
      polygonId: PolygonId('boundary_${boundary.projectName}'),
      points: points,
      strokeColor: color.withOpacity(1),
      strokeWidth: 2,
      fillColor: color,
      consumeTapEvents: true,
      onTap: () => _showBoundaryInfo(boundary),
    ));
  }

  void _addDrawingPolygon() {
    // 繪製已連接的線段
    if (_drawingPoints.length >= 2) {
      final allPoints = List<LatLng>.from(_drawingPoints);
      if (_drawingPoints.length >= 3) {
        allPoints.add(_drawingPoints[0]); // 閉合
      }
      
      _polylines.add(Polyline(
        polylineId: const PolylineId('drawing_line'),
        points: allPoints,
        color: _drawingColor,
        width: 3,
      ));
    }
    
    // 繪製填充的多邊形（預覽）
    if (_drawingPoints.length >= 3) {
      _polygons.add(Polygon(
        polygonId: const PolygonId('drawing_polygon'),
        points: _drawingPoints,
        strokeColor: _drawingColor,
        strokeWidth: 2,
        fillColor: _drawingColor.withOpacity(0.2),
      ));
    }
  }

  void _updateDrawingPoint(int index, LatLng newPosition) {
    _drawingPoints[index] = newPosition;
    _updateMapElements();
  }

  void _showBoundaryInfo(ProjectBoundary boundary) {
    final area = _boundaryService.calculatePolygonArea(boundary.coordinates);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(boundary.projectName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('專案代碼：${boundary.projectCode ?? "未設定"}'),
            Text('頂點數量：${boundary.coordinates.length}'),
            Text('面積：${area.toStringAsFixed(2)} 公頃'),
            if (boundary.updatedAt != null)
              Text('更新時間：${_formatDate(boundary.updatedAt!)}'),
          ],
        ),
        actions: [
          if (boundary.projectName == _selectedProject) ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _editExistingBoundary(boundary);
              },
              child: const Text('編輯'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _confirmDeleteBoundary(boundary);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('刪除'),
            ),
          ],
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  void _editExistingBoundary(ProjectBoundary boundary) {
    setState(() {
      _drawingPoints.clear();
      _drawingPoints.addAll(
        boundary.coordinates.map((c) => LatLng(c[0], c[1])),
      );
      _isDrawing = true;
    });
    _updateMapElements();
  }

  Future<void> _confirmDeleteBoundary(ProjectBoundary boundary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除「${boundary.projectName}」的邊界嗎？\n刪除後，新增樹木到此專案將不再有座標限制。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isSaving = true);
      
      final success = await _boundaryService.deleteBoundary(boundary.projectName);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('邊界已刪除')),
        );
        _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('刪除失敗')),
        );
      }
      
      setState(() => _isSaving = false);
    }
  }

  void _onMapTap(LatLng position) {
    if (!_isDrawing) return;
    
    setState(() {
      _drawingPoints.add(position);
    });
    _updateMapElements();
  }

  void _undoLastPoint() {
    if (_drawingPoints.isEmpty) return;
    
    setState(() {
      _drawingPoints.removeLast();
    });
    _updateMapElements();
  }

  void _clearDrawing() {
    setState(() {
      _drawingPoints.clear();
      _isDrawing = false;
    });
    _updateMapElements();
  }

  void _startDrawing() {
    if (_selectedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇專案')),
      );
      return;
    }
    
    setState(() {
      _isDrawing = true;
      _drawingPoints.clear();
    });
    _updateMapElements();
  }

  Future<void> _saveBoundary() async {
    if (_selectedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇專案')),
      );
      return;
    }

    if (_drawingPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邊界至少需要 3 個頂點')),
      );
      return;
    }

    // 驗證邊界是否涵蓋所有現有樹木
    if (_existingTreeLocations.isNotEmpty) {
      final treesOutside = <LatLng>[];
      for (final tree in _existingTreeLocations) {
        if (!_isPointInDrawingPolygon(tree)) {
          treesOutside.add(tree);
        }
      }
      
      if (treesOutside.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ 驗證警告'),
            content: Text(
              '有 ${treesOutside.length} 棵現有樹木不在新邊界內。\n'
              '儲存後這些樹木可能會被標記為不符合專案區域。\n\n'
              '確定要繼續嗎？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
                child: const Text('仍然儲存'),
              ),
            ],
          ),
        );
        
        if (confirmed != true) return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final boundary = ProjectBoundary(
        projectName: _selectedProject!,
        projectCode: widget.projectCode,
        coordinates: _drawingPoints.map((p) => [p.latitude, p.longitude]).toList(),
      );

      final response = await ApiService.post('/project-boundaries', boundary.toJson());

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('邊界已儲存')),
        );
        
        setState(() {
          _isDrawing = false;
          _drawingPoints.clear();
        });
        
        await _loadData();
      } else {
        final message = response['message'] ?? '儲存失敗';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
        
        // 如果有樹木在邊界外的詳細資訊
        if (response['treesOutside'] != null) {
          _highlightTreesOutside(response['treesOutside']);
        }
      }
    } catch (e) {
      debugPrint('[ProjectBoundaryDrawPage] 儲存邊界錯誤: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗: $e')),
      );
    }

    setState(() => _isSaving = false);
  }

  void _highlightTreesOutside(List<dynamic> treesOutside) {
    // 在地圖上標記邊界外的樹木
    for (int i = 0; i < treesOutside.length; i++) {
      final tree = treesOutside[i];
      _markers.add(Marker(
        markerId: MarkerId('outside_$i'),
        position: LatLng(
          (tree['lat'] as num).toDouble(),
          (tree['lng'] as num).toDouble(),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
        infoWindow: const InfoWindow(title: '邊界外的樹木'),
      ));
    }
    setState(() {});
  }

  bool _isPointInDrawingPolygon(LatLng point) {
    if (_drawingPoints.length < 3) return false;

    int intersections = 0;
    final n = _drawingPoints.length;

    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      
      final y1 = _drawingPoints[i].latitude;
      final x1 = _drawingPoints[i].longitude;
      final y2 = _drawingPoints[j].latitude;
      final x2 = _drawingPoints[j].longitude;

      if (((y1 > point.latitude) != (y2 > point.latitude)) &&
          (point.longitude < (x2 - x1) * (point.latitude - y1) / (y2 - y1) + x1)) {
        intersections++;
      }
    }

    return intersections % 2 == 1;
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
           '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  void _onProjectChanged(String? project) async {
    if (project == null || project == _selectedProject) return;
    
    setState(() {
      _selectedProject = project;
      _isDrawing = false;
      _drawingPoints.clear();
      _existingTreeLocations.clear();
    });
    
    await _loadProjectTrees(project);
    
    _currentProjectBoundary = _existingBoundaries
        .where((b) => b.projectName == project)
        .firstOrNull;
    
    _updateMapElements();
    
    // 移動到專案區域
    if (_currentProjectBoundary != null) {
      final center = _boundaryService.calculatePolygonCenter(_currentProjectBoundary!.coordinates);
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(center['lat']!, center['lng']!),
        15,
      ));
    } else if (_existingTreeLocations.isNotEmpty) {
      // 移動到樹木中心
      double sumLat = 0, sumLng = 0;
      for (final loc in _existingTreeLocations) {
        sumLat += loc.latitude;
        sumLng += loc.longitude;
      }
      _controller?.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(sumLat / _existingTreeLocations.length, sumLng / _existingTreeLocations.length),
        15,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('專案邊界繪製'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isDrawing) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: '撤銷',
              onPressed: _drawingPoints.isEmpty ? null : _undoLastPoint,
            ),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: '清除',
              onPressed: _clearDrawing,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // 地圖
                GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(23.7, 121.0),
                    zoom: 7,
                  ),
                  onMapCreated: (controller) => _controller = controller,
                  onTap: _onMapTap,
                  polygons: _polygons,
                  markers: _markers,
                  polylines: _polylines,
                  mapType: MapType.hybrid,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                
                // 頂部控制面板
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 專案選擇
                          Row(
                            children: [
                              const Text('專案：', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: _selectedProject,
                                  hint: const Text('選擇專案'),
                                  isExpanded: true,
                                  items: _availableProjects.map((p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p, overflow: TextOverflow.ellipsis),
                                  )).toList(),
                                  onChanged: _onProjectChanged,
                                ),
                              ),
                            ],
                          ),
                          
                          // 狀態資訊
                          if (_selectedProject != null) ...[
                            const Divider(),
                            Row(
                              children: [
                                Icon(
                                  _currentProjectBoundary != null ? Icons.check_circle : Icons.warning,
                                  color: _currentProjectBoundary != null ? Colors.green : Colors.orange,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _currentProjectBoundary != null 
                                      ? '已設定邊界 (${_currentProjectBoundary!.coordinates.length} 頂點)'
                                      : '尚未設定邊界',
                                  style: TextStyle(
                                    color: _currentProjectBoundary != null ? Colors.green : Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            if (_existingTreeLocations.isNotEmpty)
                              Text('現有樹木：${_existingTreeLocations.length} 棵'),
                          ],
                          
                          // 繪製模式資訊
                          if (_isDrawing) ...[
                            const Divider(),
                            Text(
                              '📍 已繪製 ${_drawingPoints.length} 個頂點 (點擊地圖新增頂點)',
                              style: const TextStyle(color: Colors.blue),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                
                // 圖例
                Positioned(
                  bottom: 100,
                  left: 16,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('圖例', style: TextStyle(fontWeight: FontWeight.bold)),
                          _buildLegendItem('🔴', '現有樹木'),
                          _buildLegendItem('🟢', '其他專案邊界'),
                          _buildLegendItem('🟠', '當前專案邊界'),
                          _buildLegendItem('🔵', '繪製中'),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // 載入中遮罩
                if (_isSaving)
                  Container(
                    color: Colors.black26,
                    child: const Center(
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('儲存中...'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      
      // 底部按鈕
      bottomNavigationBar: _selectedProject == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    if (!_isDrawing) ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _startDrawing,
                          icon: const Icon(Icons.draw),
                          label: Text(_currentProjectBoundary != null ? '重新繪製' : '開始繪製'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearDrawing,
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _drawingPoints.length >= 3 ? _saveBoundary : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('儲存邊界'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLegendItem(String icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
