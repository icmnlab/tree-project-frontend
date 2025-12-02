import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ar_measurement_service.dart';

/// AR DBH 測量頁面
/// 
/// 提供多種測量方法的視覺化介面：
/// 1. 雙點測量法 - 點擊標記樹幹邊緣
/// 2. 參照物比例法 - 使用已知尺寸物體
/// 3. 環繞拍攝法 - 多角度測量取平均
class ARDBHMeasurementPage extends StatefulWidget {
  /// 初始 DBH 值（如有）
  final double? initialDbh;
  
  /// 樹種名稱（用於顯示參考範圍）
  final String? speciesName;

  const ARDBHMeasurementPage({
    super.key,
    this.initialDbh,
    this.speciesName,
  });

  @override
  State<ARDBHMeasurementPage> createState() => _ARDBHMeasurementPageState();
}

class _ARDBHMeasurementPageState extends State<ARDBHMeasurementPage>
    with SingleTickerProviderStateMixin {
  final ARMeasurementService _measurementService = ARMeasurementService();
  final ImagePicker _imagePicker = ImagePicker();

  // 狀態
  late TabController _tabController;
  DeviceCapabilities? _deviceCapabilities;
  bool _isLoading = true;
  
  // 測量結果
  MeasurementResult? _currentResult;
  final List<MeasurementResult> _multiAngleResults = [];
  
  // 雙點測量狀態
  File? _twoPointImage;
  MeasurementPoint? _point1;
  MeasurementPoint? _point2;
  double _estimatedDistance = 1.5; // 預設距離 1.5m
  
  // 參照物測量狀態
  File? _referenceImage;
  ReferenceObject? _selectedReference;
  double _referencePixelWidth = 0;
  double _treePixelWidth = 0;
  int _referenceStep = 0; // 0: 選擇參照物, 1: 標記參照物, 2: 標記樹幹
  
  // 環繞測量狀態
  final List<File> _multiAngleImages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      final capabilities = await _measurementService.detectDeviceCapabilities();
      if (mounted) {
        setState(() {
          _deviceCapabilities = capabilities;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('初始化測量服務失敗: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DBH 智慧測量'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.touch_app), text: '雙點測量'),
            Tab(icon: Icon(Icons.straighten), text: '參照物'),
            Tab(icon: Icon(Icons.threesixty), text: '環繞測量'),
          ],
        ),
        actions: [
          if (_currentResult != null)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: '確認使用此測量結果',
              onPressed: _confirmResult,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 設備能力提示
                if (_deviceCapabilities != null)
                  _buildCapabilitiesBar(),
                
                // 測量結果顯示
                if (_currentResult != null)
                  _buildResultCard(),
                
                // 分頁內容
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTwoPointTab(),
                      _buildReferenceTab(),
                      _buildMultiAngleTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// 設備能力提示欄
  Widget _buildCapabilitiesBar() {
    final caps = _deviceCapabilities!;
    final recommended = caps.recommendedMethod;
    
    String recommendedText;
    IconData recommendedIcon;
    
    switch (recommended) {
      case MeasurementMethod.arDepth:
        recommendedText = caps.hasLiDAR ? 'LiDAR 深度測量 (最精確)' : 'AR 深度測量';
        recommendedIcon = Icons.view_in_ar;
        break;
      case MeasurementMethod.twoPoint:
        recommendedText = '雙點測量法';
        recommendedIcon = Icons.touch_app;
        break;
      case MeasurementMethod.reference:
        recommendedText = '參照物比例法';
        recommendedIcon = Icons.straighten;
        break;
      default:
        recommendedText = '標準測量';
        recommendedIcon = Icons.camera_alt;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.teal.shade50,
      child: Row(
        children: [
          Icon(recommendedIcon, color: Colors.teal, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '推薦方法: $recommendedText',
              style: TextStyle(
                color: Colors.teal.shade700,
                fontSize: 13,
              ),
            ),
          ),
          if (caps.hasLiDAR)
            Chip(
              label: const Text('LiDAR'),
              backgroundColor: Colors.green.shade100,
              labelStyle: TextStyle(
                color: Colors.green.shade700,
                fontSize: 11,
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
        ],
      ),
    );
  }

  /// 測量結果卡片
  Widget _buildResultCard() {
    final result = _currentResult!;
    final isValid = _measurementService.validateMeasurement(result);
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isValid ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isValid ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isValid ? Icons.check_circle : Icons.warning,
                color: isValid ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(
                '測量結果',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isValid ? Colors.green.shade700 : Colors.orange.shade700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getConfidenceColor(result.confidenceScore),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '信心度: ${result.confidenceLevel}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildResultMetric(
                '直徑 (DBH)',
                '${result.diameterCm.toStringAsFixed(1)} cm',
                Icons.circle_outlined,
              ),
              _buildResultMetric(
                '圓周',
                '${result.circumferenceCm.toStringAsFixed(1)} cm',
                Icons.panorama_fish_eye,
              ),
              _buildResultMetric(
                '誤差範圍',
                '±${result.estimatedErrorCm.toStringAsFixed(1)} cm',
                Icons.error_outline,
              ),
            ],
          ),
          if (result.notes != null) ...[
            const SizedBox(height: 8),
            Text(
              result.notes!,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultMetric(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.teal, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Color _getConfidenceColor(double score) {
    if (score >= 0.8) return Colors.green;
    if (score >= 0.6) return Colors.teal;
    if (score >= 0.4) return Colors.orange;
    return Colors.red;
  }

  /// 雙點測量分頁
  Widget _buildTwoPointTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 提示卡片
          _buildTipsCard(MeasurementMethod.twoPoint),
          
          const SizedBox(height: 16),
          
          // 拍照按鈕
          if (_twoPointImage == null)
            _buildPhotoButton(
              onPressed: () => _takePhoto(MeasurementMethod.twoPoint),
              label: '拍攝樹幹照片',
              icon: Icons.camera_alt,
            )
          else ...[
            // 顯示照片並允許點擊標記
            _buildInteractiveImage(
              image: _twoPointImage!,
              onTap: _onTwoPointTap,
              points: [_point1, _point2].whereType<MeasurementPoint>().toList(),
            ),
            
            const SizedBox(height: 16),
            
            // 距離輸入
            Row(
              children: [
                Expanded(
                  child: Text(
                    '您與樹幹的距離: ${_estimatedDistance.toStringAsFixed(1)} 公尺',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            Slider(
              value: _estimatedDistance,
              min: 0.5,
              max: 5.0,
              divisions: 45,
              label: '${_estimatedDistance.toStringAsFixed(1)}m',
              onChanged: (value) {
                setState(() => _estimatedDistance = value);
                _recalculateTwoPoint();
              },
            ),
            
            const SizedBox(height: 8),
            
            // 狀態指示
            _buildPointStatus(),
            
            const SizedBox(height: 16),
            
            // 操作按鈕
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _resetTwoPoint,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新測量'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _point1 != null && _point2 != null
                        ? _calculateTwoPoint
                        : null,
                    icon: const Icon(Icons.calculate),
                    label: const Text('計算直徑'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPointStatus() {
    return Row(
      children: [
        _buildPointIndicator(1, _point1 != null),
        const SizedBox(width: 8),
        const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        _buildPointIndicator(2, _point2 != null),
        const Spacer(),
        Text(
          _point1 == null
              ? '請點擊樹幹左側邊緣'
              : _point2 == null
                  ? '請點擊樹幹右側邊緣'
                  : '標記完成',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildPointIndicator(int number, bool isSet) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isSet ? Colors.teal : Colors.grey.shade300,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: isSet ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// 參照物測量分頁
  Widget _buildReferenceTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 提示卡片
          _buildTipsCard(MeasurementMethod.reference),
          
          const SizedBox(height: 16),
          
          // 步驟指示
          _buildStepIndicator(),
          
          const SizedBox(height: 16),
          
          // 步驟內容
          if (_referenceStep == 0)
            _buildReferenceSelection()
          else if (_referenceImage == null)
            _buildPhotoButton(
              onPressed: () => _takePhoto(MeasurementMethod.reference),
              label: '拍攝照片（包含參照物和樹幹）',
              icon: Icons.camera_alt,
            )
          else
            _buildReferenceMarkingUI(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStepChip(0, '選擇參照物'),
        const Expanded(child: Divider()),
        _buildStepChip(1, '拍攝照片'),
        const Expanded(child: Divider()),
        _buildStepChip(2, '標記測量'),
      ],
    );
  }

  Widget _buildStepChip(int step, String label) {
    final isActive = _referenceStep >= step;
    final isCurrent = _referenceStep == step;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isCurrent
            ? Colors.teal
            : isActive
                ? Colors.teal.shade100
                : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isCurrent
              ? Colors.white
              : isActive
                  ? Colors.teal.shade700
                  : Colors.grey.shade600,
          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildReferenceSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '選擇您手邊的參照物:',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        ...ReferenceObject.commonObjects.map((ref) => _buildReferenceItem(ref)),
      ],
    );
  }

  Widget _buildReferenceItem(ReferenceObject ref) {
    final isSelected = _selectedReference?.name == ref.name;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected ? Colors.teal.shade50 : null,
      child: ListTile(
        leading: Icon(
          _getIconData(ref.iconName),
          color: isSelected ? Colors.teal : Colors.grey,
        ),
        title: Text(ref.nameZh),
        subtitle: Text('${ref.widthCm} × ${ref.heightCm} cm'),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Colors.teal)
            : null,
        onTap: () {
          setState(() {
            _selectedReference = ref;
            _referenceStep = 1;
          });
        },
      ),
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'credit_card':
        return Icons.credit_card;
      case 'description':
        return Icons.description;
      case 'smartphone':
        return Icons.smartphone;
      case 'straighten':
        return Icons.straighten;
      case 'square_foot':
        return Icons.square_foot;
      default:
        return Icons.help_outline;
    }
  }

  Widget _buildReferenceMarkingUI() {
    return Column(
      children: [
        // 顯示照片
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            _referenceImage!,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 參照物寬度輸入
        Row(
          children: [
            const Text('參照物像素寬度:'),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '測量或估計',
                  suffixText: 'px',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
                onChanged: (v) => _referencePixelWidth = double.tryParse(v) ?? 0,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 12),
        
        // 樹幹寬度輸入
        Row(
          children: [
            const Text('樹幹像素寬度:'),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '測量或估計',
                  suffixText: 'px',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                ),
                onChanged: (v) => _treePixelWidth = double.tryParse(v) ?? 0,
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        // 計算按鈕
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _resetReference,
                icon: const Icon(Icons.refresh),
                label: const Text('重新開始'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _referencePixelWidth > 0 && _treePixelWidth > 0
                    ? _calculateReference
                    : null,
                icon: const Icon(Icons.calculate),
                label: const Text('計算直徑'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 環繞測量分頁
  Widget _buildMultiAngleTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 提示卡片
          _buildTipsCard(MeasurementMethod.multiAngle),
          
          const SizedBox(height: 16),
          
          // 已拍攝照片列表
          if (_multiAngleImages.isNotEmpty) ...[
            Text(
              '已拍攝 ${_multiAngleImages.length} 張照片',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _multiAngleImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _multiAngleImages[index],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeMultiAngleImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // 已計算的結果列表
          if (_multiAngleResults.isNotEmpty) ...[
            Text(
              '各角度測量結果:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            ...List.generate(_multiAngleResults.length, (index) {
              final r = _multiAngleResults[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    child: Text('${index + 1}'),
                  ),
                  title: Text('${r.diameterCm.toStringAsFixed(1)} cm'),
                  subtitle: Text('信心度: ${r.confidenceLevel}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeMultiAngleResult(index),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
          ],
          
          // 按鈕區
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _takePhoto(MeasurementMethod.multiAngle),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('添加照片'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _multiAngleResults.length >= 2
                      ? _calculateMultiAngle
                      : null,
                  icon: const Icon(Icons.calculate),
                  label: const Text('計算平均'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          
          if (_multiAngleResults.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '至少需要 2 個角度的測量結果',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  /// 提示卡片
  Widget _buildTipsCard(MeasurementMethod method) {
    final tips = _measurementService.getMeasurementTips(method);
    
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, color: Colors.blue.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                tips,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.blue.shade900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 拍照按鈕
  Widget _buildPhotoButton({
    required VoidCallback onPressed,
    required String label,
    required IconData icon,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 48),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 32),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  /// 可互動的圖片（用於雙點標記）
  Widget _buildInteractiveImage({
    required File image,
    required Function(Offset) onTap,
    required List<MeasurementPoint> points,
  }) {
    return GestureDetector(
      onTapDown: (details) {
        final RenderBox box = context.findRenderObject() as RenderBox;
        final localOffset = box.globalToLocal(details.globalPosition);
        onTap(localOffset);
      },
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              image,
              width: double.infinity,
              fit: BoxFit.contain,
            ),
          ),
          // 標記點
          ...points.asMap().entries.map((entry) {
            final index = entry.key;
            final point = entry.value;
            return Positioned(
              left: point.x - 12,
              top: point.y - 12,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: index == 0 ? Colors.red : Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }),
          // 連接線
          if (points.length == 2)
            CustomPaint(
              painter: LinePainter(
                point1: Offset(points[0].x, points[0].y),
                point2: Offset(points[1].x, points[1].y),
              ),
            ),
        ],
      ),
    );
  }

  // === 事件處理 ===

  Future<void> _takePhoto(MeasurementMethod method) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      
      if (image != null) {
        setState(() {
          switch (method) {
            case MeasurementMethod.twoPoint:
              _twoPointImage = File(image.path);
              _point1 = null;
              _point2 = null;
              break;
            case MeasurementMethod.reference:
              _referenceImage = File(image.path);
              _referenceStep = 2;
              break;
            case MeasurementMethod.multiAngle:
              _multiAngleImages.add(File(image.path));
              break;
            default:
              break;
          }
        });
      }
    } catch (e) {
      _showError('拍照失敗: $e');
    }
  }

  void _onTwoPointTap(Offset position) {
    setState(() {
      if (_point1 == null) {
        _point1 = MeasurementPoint(x: position.dx, y: position.dy);
      } else if (_point2 == null) {
        _point2 = MeasurementPoint(x: position.dx, y: position.dy);
        _calculateTwoPoint();
      }
    });
  }

  void _recalculateTwoPoint() {
    if (_point1 != null && _point2 != null) {
      _calculateTwoPoint();
    }
  }

  void _calculateTwoPoint() {
    if (_point1 == null || _point2 == null) return;
    
    final screenSize = MediaQuery.of(context).size;
    
    try {
      final result = _measurementService.calculateFromTwoPoints(
        point1: _point1!,
        point2: _point2!,
        screenWidth: screenSize.width,
        screenHeight: screenSize.height,
        distance: _estimatedDistance,
      );
      
      setState(() => _currentResult = result);
    } catch (e) {
      _showError('計算失敗: $e');
    }
  }

  void _resetTwoPoint() {
    setState(() {
      _twoPointImage = null;
      _point1 = null;
      _point2 = null;
      _currentResult = null;
    });
  }

  void _calculateReference() {
    if (_selectedReference == null) return;
    if (_referencePixelWidth <= 0 || _treePixelWidth <= 0) return;
    
    try {
      final result = _measurementService.calculateFromReference(
        reference: _selectedReference!,
        referencePixelWidth: _referencePixelWidth,
        treePixelWidth: _treePixelWidth,
      );
      
      setState(() => _currentResult = result);
    } catch (e) {
      _showError('計算失敗: $e');
    }
  }

  void _resetReference() {
    setState(() {
      _referenceImage = null;
      _selectedReference = null;
      _referenceStep = 0;
      _referencePixelWidth = 0;
      _treePixelWidth = 0;
      _currentResult = null;
    });
  }

  void _removeMultiAngleImage(int index) {
    setState(() {
      _multiAngleImages.removeAt(index);
    });
  }

  void _removeMultiAngleResult(int index) {
    setState(() {
      _multiAngleResults.removeAt(index);
      if (_multiAngleResults.isEmpty) {
        _currentResult = null;
      }
    });
  }

  void _calculateMultiAngle() {
    if (_multiAngleResults.length < 2) return;
    
    try {
      final result = _measurementService.calculateFromMultiAngle(
        measurements: _multiAngleResults,
      );
      
      setState(() => _currentResult = result);
    } catch (e) {
      _showError('計算失敗: $e');
    }
  }

  void _confirmResult() {
    if (_currentResult == null) return;
    
    // 返回測量結果
    Navigator.of(context).pop(_currentResult);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}

/// 連接線繪製器
class LinePainter extends CustomPainter {
  final Offset point1;
  final Offset point2;
  
  LinePainter({required this.point1, required this.point2});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.yellow
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    
    canvas.drawLine(point1, point2, paint);
    
    // 繪製虛線
    final dashedPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    
    final path = Path()..moveTo(point1.dx, point1.dy)..lineTo(point2.dx, point2.dy);
    canvas.drawPath(path, dashedPaint);
  }
  
  @override
  bool shouldRepaint(covariant LinePainter oldDelegate) {
    return point1 != oldDelegate.point1 || point2 != oldDelegate.point2;
  }
}
