/// V3 專案邊界繪製頁面
/// 
/// 功能：
/// 1. 在地圖上手動繪製專案邊界多邊形
/// 2. 顯示現有的專案邊界
/// 3. 編輯/刪除專案邊界
/// 4. 驗證新邊界是否涵蓋所有現有樹木

import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/v3/project_boundary_service.dart';
import '../../services/v3/project_boundary_coordinator.dart';
import '../../services/api_service.dart';
import '../../services/download_service.dart';
import '../../widgets/conflict_resolution_dialog.dart';
import '../../utils/boundary_input.dart';
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

  // 目前頂點來源（draw|coords|kml|geojson|suggest），隨輸入方式更新，儲存時回報後端
  String _currentSource = 'draw';
  // 匯入解析中遮罩
  bool _isImporting = false;
  // 匯出 KML 中
  bool _isExporting = false;
  
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
  bool _isSuggesting = false;
  List<LatLng>? _suggestedPreviewPoints;
  String? _selectedProject;
  List<String> _availableProjects = [];
  final Map<String, String> _projectNameToCode = {};
  
  // 顏色
  static const Color _drawingColor = Colors.blue;
  static const Color _existingColor = Colors.green;
  static const Color _currentProjectColor = Colors.orange;
  static const Color _suggestedPreviewColor = Colors.deepPurple;

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
        _projectNameToCode.clear();
        final list = projectsResponse['data'] as List;
        _availableProjects = list
            .map((p) {
              final name = p['name']?.toString() ?? '';
              final code = p['project_code']?.toString() ?? '';
              if (name.isNotEmpty && code.isNotEmpty) {
                _projectNameToCode[name] = code;
              }
              return name;
            })
            .where((n) => n.isNotEmpty)
            .toList();
      }
      
      // 載入現有邊界
      _existingBoundaries = await _boundaryService.getAllBoundaries(forceRefresh: true);
      _refreshProjectOptions();

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

    // [B3 fix] 初次載入時自動把鏡頭拉到目前專案邊界中心 / 樹木重心
    _flyCameraToInitialView();
  }

  void _flyCameraToInitialView() {
    if (_controller == null) {
      // GoogleMap 還沒初始化完成 — 在 onMapCreated 內已自行處理初次 camera
      // 因此這裡 noop 即可（onMapCreated 會 retry）
      return;
    }
    if (_currentProjectBoundary != null) {
      final center = _boundaryService.calculatePolygonCenter(
          _currentProjectBoundary!.coordinates);
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(center['lat']!, center['lng']!),
        15,
      ));
    } else if (_existingTreeLocations.isNotEmpty) {
      double sumLat = 0, sumLng = 0;
      for (final loc in _existingTreeLocations) {
        sumLat += loc.latitude;
        sumLng += loc.longitude;
      }
      _controller!.animateCamera(CameraUpdate.newLatLngZoom(
        LatLng(
          sumLat / _existingTreeLocations.length,
          sumLng / _existingTreeLocations.length,
        ),
        15,
      ));
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
    if (!mounted) return;

    _polygons.clear();
    _markers.clear();
    _polylines.clear();
    
    // 添加現有邊界（其他專案）
    for (final boundary in _existingBoundaries) {
      if (boundary.projectName != _selectedProject) {
        _addBoundaryPolygon(boundary, _existingColor.withValues(alpha:0.3));
      }
    }
    
    // 添加當前專案的現有邊界
    if (_currentProjectBoundary != null) {
      _addBoundaryPolygon(_currentProjectBoundary!, _currentProjectColor.withValues(alpha:0.4));
    }
    
    // 添加繪製中的多邊形
    if (_drawingPoints.isNotEmpty) {
      _addDrawingPolygon();
    }

    // 建議邊界預覽（尚未儲存）
    if (_suggestedPreviewPoints != null &&
        _suggestedPreviewPoints!.length >= 3) {
      _polygons.add(Polygon(
        polygonId: const PolygonId('suggested_preview'),
        points: _suggestedPreviewPoints!,
        strokeColor: _suggestedPreviewColor,
        strokeWidth: 3,
        fillColor: _suggestedPreviewColor.withValues(alpha: 0.12),
      ));
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
    
    if (mounted) setState(() {});
  }

  void _addBoundaryPolygon(ProjectBoundary boundary, Color color) {
    final points = boundary.coordinates
        .map((c) => LatLng(c[0], c[1]))
        .toList();
    
    _polygons.add(Polygon(
      polygonId: PolygonId('boundary_${boundary.projectName}'),
      points: points,
      strokeColor: color.withValues(alpha:1),
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
        fillColor: _drawingColor.withValues(alpha:0.2),
      ));
    }
  }

  void _updateDrawingPoint(int index, LatLng newPosition) {
    // [B2 fix] 拖動頂點時只更新內部點 + polylines/preview polygon，
    // 不要重建 markers Set（重建會觸發 Marker 動畫漂移）。
    if (index < 0 || index >= _drawingPoints.length) return;
    _drawingPoints[index] = newPosition;

    // 移除舊的繪製預覽元素
    _polylines
        .removeWhere((p) => p.polylineId.value == 'drawing_line');
    _polygons
        .removeWhere((p) => p.polygonId.value == 'drawing_polygon');

    // 重新加入更新後的繪製預覽
    _addDrawingPolygon();

    // 注意：marker 本身已經在 onDragEnd 之後由 GoogleMaps 內建處理位置
    // 因此這裡不去清掉 _markers / 重新放 marker，避免漂移動畫
    setState(() {});
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
            Text('區代碼：${boundary.projectCode ?? "未設定"}'),
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
        content: Text('確定要刪除「${boundary.projectName}」的邊界嗎？\n刪除後，新增樹木到此區將不再有座標限制。'),
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
        const SnackBar(content: Text('請先選擇區')),
      );
      return;
    }

    setState(() {
      _isDrawing = true;
      _drawingPoints.clear();
      _suggestedPreviewPoints = null;
      _currentSource = 'draw';
    });
    _updateMapElements();
  }

  /// 從 tree_survey 主群集 GPS 產生建議邊界（outlier 排除，僅預覽）
  Future<void> _suggestBoundaryFromTrees() async {
    if (_selectedProject == null) return;
    if (_currentProjectBoundary != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此區已有邊界，請使用「重新繪製」')),
      );
      return;
    }
    if (_existingTreeLocations.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('至少需要 3 棵有 GPS 的樹木才能產生建議邊界')),
      );
      return;
    }

    setState(() => _isSuggesting = true);
    try {
      final result = await _boundaryService.suggestBoundaryFromTrees(
        projectName: _selectedProject!,
      );

      if (!mounted) return;

      if (!result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final stats = result.stats;
      final included = stats?['includedTrees'] ?? '?';
      final excluded = stats?['excludedTrees'] ?? 0;
      final spanKm = stats?['spanM'] != null
          ? ((stats!['spanM'] as num) / 1000).toStringAsFixed(2)
          : '?';

      final warnText = result.warnings.isNotEmpty
          ? '\n\n${result.warnings.join('\n')}'
          : '';

      final confirmed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('建議邊界預覽'),
          content: SingleChildScrollView(
            child: Text(
              '依主群集 $included 棵樹木產生凸包（+10m buffer）。\n'
              '主群集跨度約 $spanKm km。\n'
              '${excluded > 0 ? '已排除 $excluded 棵距主群集過遠的樹木。' : ''}'
              '$warnText\n\n'
              '此邊界僅供預覽，確認後可微調再儲存。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'load'),
              child: const Text('載入頂點'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'save'),
              child: const Text('直接儲存'),
            ),
          ],
        ),
      );

      if (confirmed == null || confirmed == 'cancel' || !mounted) return;

      final points = result.coordinates
          .map((c) => LatLng(c[0], c[1]))
          .toList();

      setState(() {
        _suggestedPreviewPoints = points;
        _drawingPoints
          ..clear()
          ..addAll(points);
        _isDrawing = true;
        _currentSource = 'suggest';
      });
      _updateMapElements();

      if (_controller != null && points.isNotEmpty) {
        final center = _boundaryService.calculatePolygonCenter(
          points.map((p) => [p.latitude, p.longitude]).toList(),
        );
        _controller!.animateCamera(CameraUpdate.newLatLngZoom(
          LatLng(center['lat']!, center['lng']!),
          15,
        ));
      }

      if (confirmed == 'save') {
        await _saveBoundary();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已載入建議邊界頂點，可微調後按「儲存邊界」'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSuggesting = false);
    }
  }

  /// 將預覽頂點載入繪製狀態（供貼座標 / 匯入檔案 / 建議共用）
  void _loadPreviewPoints(List<LatLng> points, String source) {
    setState(() {
      _drawingPoints
        ..clear()
        ..addAll(points);
      _isDrawing = true;
      _currentSource = source;
      _suggestedPreviewPoints = null;
    });
    _updateMapElements();
    if (_controller != null && points.isNotEmpty) {
      final center = _boundaryService.calculatePolygonCenter(
        points.map((p) => [p.latitude, p.longitude]).toList(),
      );
      _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(center['lat']!, center['lng']!), 15),
      );
    }
  }

  bool _ensureProjectSelected() {
    if (_selectedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇區')),
      );
      return false;
    }
    return true;
  }

  /// 方式 1：直接鍵入座標清單
  Future<void> _pasteCoordinates() async {
    if (!_ensureProjectSelected()) return;

    // 對話框抽成自有生命週期的 StatefulWidget（controller 於其 dispose 釋放），
    // 避免在 await 後立即 dispose 造成退場動畫重建時「used after disposed」連鎖錯誤。
    final parsed = await showDialog<BoundaryParseResult>(
      context: context,
      builder: (ctx) => const _PasteCoordinatesDialog(),
    );

    if (parsed == null || !mounted) return;

    if (!parsed.ok) {
      final msg = parsed.errors.isNotEmpty
          ? parsed.errors.join('\n')
          : '座標解析失敗';
      _showImportErrorDialog('座標解析失敗', msg);
      return;
    }

    await _confirmAndLoadParsed(
      coordinates: parsed.coordinates,
      source: 'coords',
      selfIntersecting: parsed.selfIntersecting,
      warnings: [...parsed.warnings, ...parsed.errors],
      detailLine:
          '共 ${parsed.coordinates.length} 個頂點'
          '${parsed.detectedOrder != null ? '，偵測順序：${parsed.detectedOrder == CoordOrder.lngLat ? '經,緯' : '緯,經'}' : ''}',
    );
  }

  /// 方式 3：匯入 KML / KMZ / GeoJSON
  Future<void> _importBoundaryFile() async {
    if (!_ensureProjectSelected()) return;

    FilePickerResult? picked;
    try {
      // 用 FileType.any 而非 custom：部分 Android 檔案選擇器在 custom + 少見副檔名
      //（.kml/.kmz/.geojson）下會把這些檔過濾掉，只剩圖片/音訊可選；改用 any 後
      // 由下方在 Dart 端驗證副檔名，確保使用者一定看得到並選得到這些檔。
      picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );
    } catch (e) {
      if (mounted) _showImportErrorDialog('選擇檔案失敗', '$e');
      return;
    }
    if (picked == null || picked.files.isEmpty || !mounted) return;

    final file = picked.files.first;
    const allowedExt = ['kml', 'kmz', 'geojson', 'json'];
    final ext = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : '';
    if (!allowedExt.contains(ext)) {
      _showImportErrorDialog(
        '檔案格式不支援',
        '請選擇 .kml / .kmz / .geojson 檔案（目前選到 ${ext.isEmpty ? '未知格式' : '.$ext'}）',
      );
      return;
    }
    final bytes = file.bytes;
    if (bytes == null) {
      _showImportErrorDialog('讀取失敗', '無法讀取檔案內容');
      return;
    }

    setState(() => _isImporting = true);
    final result = await _boundaryService.importBoundaryFile(
      bytes: bytes,
      filename: file.name,
    );
    if (!mounted) return;
    setState(() => _isImporting = false);

    if (!result.success) {
      _showImportErrorDialog('匯入失敗', result.message);
      return;
    }

    final stats = result.stats;
    final areaHa = stats?['areaHa'];
    final vertexCount = stats?['vertexCount'] ?? result.coordinates.length;
    final selfIntersecting = stats?['selfIntersecting'] == true;

    await _confirmAndLoadParsed(
      coordinates: result.coordinates,
      source: result.format == 'geojson' ? 'geojson' : 'kml',
      selfIntersecting: selfIntersecting,
      warnings: result.warnings,
      detailLine: '格式：${result.format ?? '?'}\n'
          '座標系統：${result.detectedCrs ?? '?'}\n'
          '頂點數：$vertexCount'
          '${areaHa is num ? '，面積約 ${(areaHa).toStringAsFixed(2)} 公頃' : ''}',
    );
  }

  /// 共用：顯示解析摘要 → 確認後載入頂點（可選依角度重排）
  Future<void> _confirmAndLoadParsed({
    required List<List<double>> coordinates,
    required String source,
    required bool selfIntersecting,
    required List<String> warnings,
    required String detailLine,
  }) async {
    final warnText = warnings.isNotEmpty ? '\n\n⚠️ ${warnings.join('\n⚠️ ')}' : '';
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('邊界預覽'),
        content: SingleChildScrollView(
          child: Text(
            '$detailLine$warnText\n\n載入後可在地圖上微調，再按「儲存邊界」。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          if (selfIntersecting)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reorder'),
              child: const Text('自動重排後載入'),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'load'),
            child: const Text('載入頂點'),
          ),
        ],
      ),
    );

    if (action == null || action == 'cancel' || !mounted) return;

    var coords = coordinates;
    if (action == 'reorder') {
      // 先角度重排（凸形）、仍自相交再試最近鄰（細長/凹形）
      final fixed = BoundaryInputParser.tryAutoReorder(coordinates);
      coords = fixed.coordinates;
      if (!fixed.resolved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('自動重排仍無法完全消除自相交（可能為複雜凹形），請載入後手動調整頂點順序'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
    final points = coords.map((c) => LatLng(c[0], c[1])).toList();
    _loadPreviewPoints(points, source);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已載入頂點，可微調後按「儲存邊界」')),
    );
  }

  void _showImportErrorDialog(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  /// 匯出目前選定區的已儲存邊界為 KML（沿用 DownloadService：含 JWT、TLS、開檔）。
  /// Android 會以 Google Earth（若已安裝）開啟，與「匯入 KML」形成雙向。
  Future<void> _exportKml() async {
    if (_selectedProject == null || _currentProjectBoundary == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('此區尚無已儲存的邊界可匯出')),
      );
      return;
    }
    final name = _selectedProject!;
    final base = ApiService.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url =
        '$base/project-boundaries/export.kml?project=${Uri.encodeComponent(name)}';

    setState(() => _isExporting = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('匯出 KML 中…')),
    );
    final result = await DownloadService.downloadAndOpen(
      url,
      suggestedFilename: '$name.kml',
    );
    if (!mounted) return;
    setState(() => _isExporting = false);
    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.warning ?? '已匯出 KML，可在 Google Earth 開啟')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'KML 匯出失敗'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _saveBoundary() async {
    if (_selectedProject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇區')),
      );
      return;
    }

    if (_drawingPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邊界至少需要 3 個頂點')),
      );
      return;
    }

    // 自相交防呆：手動點選/拖曳頂點也可能畫出交叉邊界（後端會以 turf.kinks 擋下）。
    // 在送出前先偵測，並提供「自動重排」（角度→最近鄰）以與貼座標/匯入流程一致。
    final drawCoords =
        _drawingPoints.map((p) => [p.latitude, p.longitude]).toList();
    if (BoundaryInputParser.isSelfIntersecting(drawCoords)) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠️ 邊界自相交'),
          content: const Text(
            '目前的頂點連線有交叉，地圖上會出現非預期範圍，後端也會拒絕儲存。\n\n'
            '可嘗試「自動重排」（凸形以角度、細長/凹形以最近鄰）；'
            '若是複雜凹形，請點「返回調整」手動修正頂點順序。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('返回調整'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'reorder'),
              child: const Text('自動重排'),
            ),
          ],
        ),
      );
      if (choice != 'reorder' || !mounted) return;

      final fixed = BoundaryInputParser.tryAutoReorder(drawCoords);
      setState(() {
        _drawingPoints
          ..clear()
          ..addAll(fixed.coordinates.map((c) => LatLng(c[0], c[1])));
      });
      if (!fixed.resolved) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('自動重排仍無法完全消除自相交，請手動調整頂點順序後再儲存'),
            duration: Duration(seconds: 4),
          ),
        );
        return; // 仍自相交，後端會拒絕，直接讓使用者調整
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已自動重排頂點，請確認後再次按儲存')),
      );
      return; // 重排後讓使用者確認形狀，再按一次儲存
    }

    // 驗證邊界是否涵蓋所有現有樹木
    bool allowTreesOutside = false;
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
              '儲存後這些樹木可能會被標記為不符合區範圍。\n\n'
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
        allowTreesOutside = true;
      }
    }

    setState(() => _isSaving = true);

    try {
      final resolvedCode = _projectNameToCode[_selectedProject!] ??
          widget.projectCode ??
          _currentProjectBoundary?.projectCode;

      final boundary = ProjectBoundary(
        projectName: _selectedProject!,
        projectCode: resolvedCode,
        coordinates: _drawingPoints.map((p) => [p.latitude, p.longitude]).toList(),
        source: _currentSource,
      );

      // [Phase 2c] 樂觀鎖：若是更新既有邊界，帶上 expectedUpdatedAt
      final payload = boundary.toJson();
      if (allowTreesOutside) {
        payload['allowTreesOutside'] = true;
      }
      if (_currentProjectBoundary?.updatedAt != null) {
        payload['expectedUpdatedAt'] =
            _currentProjectBoundary!.updatedAt!.toIso8601String();
      }

      var response = await ApiService.post('/project-boundaries', payload);

      // 處理 409 衝突
      if (response['success'] != true && response['code'] == 'CONFLICT') {
        if (!mounted) {
          setState(() => _isSaving = false);
          return;
        }
        final serverVersion = (response['serverVersion'] as Map?) ?? {};
        final action = await showConflictResolutionDialog(
          context,
          serverVersion: Map<String, dynamic>.from(serverVersion),
          myDraft: payload,
        );
        if (action == ConflictAction.keepMine) {
          // 強制覆寫：移除 expectedUpdatedAt 重送
          final retryPayload = Map<String, dynamic>.from(payload)
            ..remove('expectedUpdatedAt');
          response = await ApiService.post(
              '/project-boundaries', retryPayload);
        } else if (action == ConflictAction.useServer ||
            action == ConflictAction.manualMerge) {
          // 重新拉一次 server 版本後返回（讓使用者重新編輯）
          await _loadData();
          setState(() => _isSaving = false);
          return;
        } else {
          // 取消
          setState(() => _isSaving = false);
          return;
        }
      }

      if (response['success'] == true) {
        await ProjectBoundaryCoordinator.instance.afterBoundaryMutation(
          projectName: _selectedProject,
        );
        if (!mounted) return;
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

  /// 合併 API 專案與邊界紀錄中的專案名，去重並校正 Dropdown value。
  void _refreshProjectOptions() {
    final seen = <String>{};
    final names = <String>[];
    void add(String? raw) {
      final s = raw?.trim() ?? '';
      if (s.isEmpty || !seen.add(s)) return;
      names.add(s);
    }
    for (final n in _availableProjects) {
      add(n);
    }
    for (final b in _existingBoundaries) {
      add(b.projectName);
    }
    names.sort((a, b) => a.compareTo(b));
    _availableProjects = names;
    _sanitizeSelectedProject();
  }

  void _sanitizeSelectedProject() {
    final current = _selectedProject?.trim();
    if (current == null || current.isEmpty) {
      _selectedProject = null;
      return;
    }
    if (_availableProjects.contains(current)) return;
    _selectedProject =
        _availableProjects.isNotEmpty ? _availableProjects.first : null;
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
    if (!mounted) return;

    setState(() {
      _currentProjectBoundary = _existingBoundaries
          .where((b) => b.projectName == project)
          .firstOrNull;
    });

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
    // [新功能] 畫到一半離開時警告（已儲存或未開始繪製則直接放行）
    return PopScope(
      canPop: !(_isDrawing && _drawingPoints.isNotEmpty),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('未儲存的邊界'),
            content: Text(
              '你已畫了 ${_drawingPoints.length} 個點，但尚未儲存。\n離開後這些點會遺失，確定要離開嗎？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('繼續編輯'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('放棄並離開'),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          Navigator.of(context).pop();
        }
      },
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('區邊界繪製'),
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
          ] else if (_currentProjectBoundary != null)
            IconButton(
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.ios_share),
              tooltip: '匯出 KML（可在 Google Earth 開啟）',
              onPressed: _isExporting ? null : _exportKml,
            ),
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
                  onMapCreated: (controller) {
                    _controller = controller;
                    // [B3 fix] 地圖初始化完成後再嘗試一次 fly camera
                    _flyCameraToInitialView();
                  },
                  // [N13 fix] 避免外層拍走手勢造成地圖漂移
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                  onTap: _onMapTap,
                  polygons: _polygons,
                  markers: _markers,
                  polylines: _polylines,
                  mapType: MapType.hybrid,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                ),
                
                // 頂部控制面板
                // 注意: right 留 64px 給 GoogleMap 內建的「我的位置」定位按鈕 (右上角)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 64,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 專案選擇
                          Row(
                            children: [
                              const Text('區：', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButton<String>(
                                  value: _availableProjects.contains(_selectedProject)
                                      ? _selectedProject
                                      : null,
                                  hint: const Text('選擇區'),
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
                          _buildLegendItem('🟢', '其他區邊界'),
                          _buildLegendItem('🟠', '當前區邊界'),
                          _buildLegendItem('🟣', '建議邊界預覽'),
                          _buildLegendItem('🔵', '繪製中'),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // 載入中遮罩
                if (_isSaving || _isSuggesting || _isImporting)
                  Container(
                    color: Colors.black26,
                    child: Center(
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 16),
                              Text(_isImporting
                                  ? '解析邊界檔案中...'
                                  : _isSuggesting
                                      ? '產生建議邊界中...'
                                      : '儲存中...'),
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
                      if (_currentProjectBoundary == null &&
                          _existingTreeLocations.length >= 3)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isSuggesting ? null : _suggestBoundaryFromTrees,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('建議邊界'),
                          ),
                        ),
                      if (_currentProjectBoundary == null &&
                          _existingTreeLocations.length >= 3)
                        const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _startDrawing,
                          icon: const Icon(Icons.draw),
                          label: Text(_currentProjectBoundary != null ? '重新繪製' : '手動繪製'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 其他輸入方式：貼座標 / 匯入 KML·GeoJSON
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: '其他輸入方式',
                        onSelected: (value) {
                          switch (value) {
                            case 'coords':
                              _pasteCoordinates();
                              break;
                            case 'file':
                              _importBoundaryFile();
                              break;
                          }
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(
                            value: 'coords',
                            child: ListTile(
                              leading: Icon(Icons.edit_location_alt),
                              title: Text('貼上座標'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'file',
                            child: ListTile(
                              leading: Icon(Icons.upload_file),
                              title: Text('匯入 KML/GeoJSON'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
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

/// 「貼上邊界座標」對話框。
///
/// 獨立 StatefulWidget 的原因：TextEditingController 由本 State 持有並在
/// dispose() 釋放（路由完全移除後才執行），避免「await showDialog 後立即
/// controller.dispose()」在退場動畫重建子樹時觸發
/// `TextEditingController was used after being disposed` 及其連鎖錯誤
/// （_dependents.isEmpty / dirty widget wrong scope / Duplicate GlobalKeys）。
class _PasteCoordinatesDialog extends StatefulWidget {
  const _PasteCoordinatesDialog();

  @override
  State<_PasteCoordinatesDialog> createState() =>
      _PasteCoordinatesDialogState();
}

class _PasteCoordinatesDialogState extends State<_PasteCoordinatesDialog> {
  final TextEditingController _controller = TextEditingController();
  CoordOrder _assumedOrder = CoordOrder.lngLat;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('貼上邊界座標'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '每行一組座標，支援括號與逗號/空白分隔，例如：\n'
              '(120.1222905, 23.2637175)\n'
              '120.1233066, 23.2638557',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('無法判斷時順序：', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                // Expanded + isExpanded：避免在窄螢幕上 Row 溢出（RenderFlex overflow）
                Expanded(
                  child: DropdownButton<CoordOrder>(
                    value: _assumedOrder,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: CoordOrder.lngLat,
                        child: Text('經度, 緯度'),
                      ),
                      DropdownMenuItem(
                        value: CoordOrder.latLng,
                        child: Text('緯度, 經度'),
                      ),
                    ],
                    onChanged: (v) => setState(
                      () => _assumedOrder = v ?? CoordOrder.lngLat,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              maxLines: 8,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '在此貼上座標…',
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
            final r = BoundaryInputParser.parse(
              _controller.text,
              assumedOrder: _assumedOrder,
            );
            Navigator.pop(context, r);
          },
          child: const Text('解析'),
        ),
      ],
    );
  }
}
