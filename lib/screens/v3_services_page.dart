import 'dart:io';
import 'package:flutter/material.dart';
import '../services/v3/tree_image_service.dart';
import '../services/v3/conflict_resolution_service.dart';
import '../services/v3/ar_measurement_integration_service.dart';
import '../services/v3/ml_data_sync_service.dart';

/// V3 進階服務管理頁面
/// 
/// 功能：
/// 1. 樹木影像管理 - 查看、同步照片
/// 2. 衝突解決 - 查看待處理的衝突
/// 3. DBH 測量校準 - 校準測量設定
/// 4. ML 數據同步 - 管理訓練數據同步
class V3ServicesPage extends StatefulWidget {
  const V3ServicesPage({super.key});

  @override
  State<V3ServicesPage> createState() => _V3ServicesPageState();
}

class _V3ServicesPageState extends State<V3ServicesPage> {
  final TreeImageService _imageService = TreeImageService();
  final ConflictResolutionService _conflictService = ConflictResolutionService();
  final ARMeasurementIntegrationService _arService = ARMeasurementIntegrationService();
  final MLDataSyncService _mlSyncService = MLDataSyncService();
  
  // 服務狀態
  bool _isLoading = true;
  int _pendingImageCount = 0;
  int _pendingConflictCount = 0;
  int _pendingMlDataCount = 0;
  CalibrationData? _currentCalibration;
  
  @override
  void initState() {
    super.initState();
    _loadServiceStatus();
  }
  
  Future<void> _loadServiceStatus() async {
    setState(() => _isLoading = true);
    
    try {
      // 加載各服務狀態
      final unsyncedImages = await _imageService.getUnsyncedImages();
      final pendingOps = _conflictService.pendingOperations;
      _currentCalibration = _arService.currentCalibration ?? CalibrationData.standard;
      
      // 獲取 ML 數據同步狀態
      final mlStatus = await _mlSyncService.getStatus();
      
      setState(() {
        _pendingImageCount = unsyncedImages.length;
        _pendingConflictCount = pendingOps.length;
        _pendingMlDataCount = mlStatus.pendingRecords;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('載入服務狀態失敗: $e');
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('進階服務管理'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadServiceStatus,
            tooltip: '重新整理',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadServiceStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildServiceCard(
                    title: '樹木影像管理',
                    subtitle: '$_pendingImageCount 張照片待同步',
                    icon: Icons.photo_library,
                    color: Colors.blue,
                    badge: _pendingImageCount > 0 ? _pendingImageCount : null,
                    onTap: () => _showImageManager(),
                  ),
                  const SizedBox(height: 12),
                  _buildServiceCard(
                    title: '資料衝突處理',
                    subtitle: '$_pendingConflictCount 筆待處理',
                    icon: Icons.sync_problem,
                    color: _pendingConflictCount > 0 ? Colors.orange : Colors.green,
                    badge: _pendingConflictCount > 0 ? _pendingConflictCount : null,
                    onTap: () => _showConflictResolver(),
                  ),
                  const SizedBox(height: 12),
                  _buildServiceCard(
                    title: 'DBH 測量校準',
                    subtitle: '目前使用: ${_currentCalibration != null ? "自訂校準" : "標準設定"}',
                    icon: Icons.straighten,
                    color: Colors.teal,
                    onTap: () => _showARCalibration(),
                  ),
                  const SizedBox(height: 12),
                  _buildServiceCard(
                    title: 'ML 數據同步',
                    subtitle: '$_pendingMlDataCount 筆待上傳',
                    icon: Icons.psychology,
                    color: Colors.purple,
                    badge: _pendingMlDataCount > 0 ? _pendingMlDataCount : null,
                    onTap: () => _showMLDataSync(),
                  ),
                  const SizedBox(height: 24),
                  _buildInfoSection(),
                ],
              ),
            ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.deepPurple.withValues(alpha:0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha:0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.settings_suggest, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'V3 進階服務',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '管理進階功能與資料同步',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildStatusChip('照片', _pendingImageCount, Colors.blue),
              const SizedBox(width: 8),
              _buildStatusChip('衝突', _pendingConflictCount, Colors.orange),
              const SizedBox(width: 8),
              _buildStatusChip('ML數據', _pendingMlDataCount, Colors.purple),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha:0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: count > 0 ? color : Colors.green,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildServiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    int? badge,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  if (badge != null && badge > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          badge > 99 ? '99+' : badge.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 8),
              Text(
                '關於 V3 服務',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'V3 進階服務提供離線資料管理、衝突解決、'
            'DBH 測量校準等功能。所有資料會在有網路時自動同步。',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
  
  // === 功能頁面 ===
  
  void _showImageManager() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const _TreeImageManagerPage(),
      ),
    ).then((_) => _loadServiceStatus());
  }
  
  void _showConflictResolver() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ConflictResolverPage(service: _conflictService),
      ),
    ).then((_) => _loadServiceStatus());
  }
  
  void _showARCalibration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ARCalibrationPage(service: _arService),
      ),
    ).then((_) => _loadServiceStatus());
  }
  
  void _showMLDataSync() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology, color: Colors.purple),
            SizedBox(width: 8),
            Text('ML 數據同步'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('待上傳數據: $_pendingMlDataCount 筆'),
            const SizedBox(height: 12),
            const Text(
              'ML 數據會在有網路連線時自動上傳，'
              '用於改善測量精度和碳計算模型。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              await _mlSyncService.sync(force: true);
              _loadServiceStatus();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('同步已啟動')),
                );
              }
            },
            icon: const Icon(Icons.sync),
            label: const Text('立即同步'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ),
        ],
      ),
    );
  }
}

// === 子頁面：樹木影像管理 ===

class _TreeImageManagerPage extends StatefulWidget {
  const _TreeImageManagerPage();

  @override
  State<_TreeImageManagerPage> createState() => _TreeImageManagerPageState();
}

class _TreeImageManagerPageState extends State<_TreeImageManagerPage> {
  final TreeImageService _imageService = TreeImageService();
  List<TreeImage> _images = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<void> _loadImages() async {
    setState(() => _isLoading = true);
    try {
      final images = await _imageService.getAllImages();
      setState(() {
        _images = images;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入失敗: $e')),
        );
      }
    }
  }

  Future<void> _syncAll() async {
    setState(() => _isSyncing = true);
    try {
      final result = await _imageService.syncAllImages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('同步完成: ${result['synced']} 成功, ${result['failed']} 失敗'),
          ),
        );
      }
      _loadImages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失敗: $e')),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final unsyncedCount = _images.where((img) => !img.isSynced).length;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('樹木影像管理'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          if (unsyncedCount > 0)
            Badge(
              label: Text(unsyncedCount.toString()),
              child: IconButton(
                icon: _isSyncing 
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload),
                onPressed: _isSyncing ? null : _syncAll,
                tooltip: '同步所有照片',
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _images.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.photo_library, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        '尚無樹木照片',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _images.length,
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    return _buildImageTile(image);
                  },
                ),
    );
  }

  Widget _buildImageTile(TreeImage image) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(image.thumbnailPath ?? image.localPath),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade200,
              child: const Icon(Icons.broken_image),
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: image.isSynced ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
            child: Icon(
              image.isSynced ? Icons.cloud_done : Icons.cloud_off,
              size: 12,
              color: Colors.white,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
              ),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Text(
              image.type.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }
}

// === 子頁面：衝突解決 ===

class _ConflictResolverPage extends StatefulWidget {
  final ConflictResolutionService service;
  
  const _ConflictResolverPage({required this.service});

  @override
  State<_ConflictResolverPage> createState() => _ConflictResolverPageState();
}

class _ConflictResolverPageState extends State<_ConflictResolverPage> {
  List<PendingOperation> _pendingOps = [];
  
  @override
  void initState() {
    super.initState();
    _loadPendingOps();
  }
  
  void _loadPendingOps() {
    setState(() {
      _pendingOps = widget.service.pendingOperations;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('資料衝突處理'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: _pendingOps.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, size: 64, color: Colors.green.shade300),
                  const SizedBox(height: 16),
                  const Text('沒有待處理的衝突'),
                  Text(
                    '所有資料都已同步',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _pendingOps.length,
              itemBuilder: (context, index) {
                return _buildConflictCard(_pendingOps[index]);
              },
            ),
    );
  }

  Widget _buildConflictCard(PendingOperation op) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getOperationIcon(op.operationType),
                  color: _getConflictColor(op.lastConflict),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${op.entityType} - ${op.entityId}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '操作: ${op.operationType}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            if (op.lastConflict != null)
              Text(
                '衝突類型: ${op.lastConflict!.name}',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 13),
              ),
            Text(
              '重試次數: ${op.retryCount}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _abandonOperation(op),
                  child: const Text('放棄'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => _retryOperation(op),
                  child: const Text('重試'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getOperationIcon(String operationType) {
    switch (operationType) {
      case 'create':
        return Icons.add_circle;
      case 'update':
        return Icons.edit;
      case 'delete':
        return Icons.delete;
      default:
        return Icons.help;
    }
  }

  Color _getConflictColor(ConflictType? type) {
    if (type == null) return Colors.blue;
    switch (type) {
      case ConflictType.versionConflict:
        return Colors.orange;
      case ConflictType.dataDeleted:
        return Colors.red;
      case ConflictType.networkError:
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  Future<void> _retryOperation(PendingOperation op) async {
    try {
      await widget.service.retryOperation(op.id);
      _loadPendingOps();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重試已啟動')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重試失敗: $e')),
        );
      }
    }
  }

  Future<void> _abandonOperation(PendingOperation op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認放棄？'),
        content: const Text('這將刪除此待處理操作，本地修改將會遺失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('放棄'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      await widget.service.abandonOperation(op.id);
      _loadPendingOps();
    }
  }
}

// === 子頁面：AR 校準 ===

class _ARCalibrationPage extends StatefulWidget {
  final ARMeasurementIntegrationService service;
  
  const _ARCalibrationPage({required this.service});

  @override
  State<_ARCalibrationPage> createState() => _ARCalibrationPageState();
}

class _ARCalibrationPageState extends State<_ARCalibrationPage> {
  late double _distance;
  late double _cameraHeight;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final cal = widget.service.currentCalibration ?? CalibrationData.standard;
    _distance = cal.deviceToTreeDistance;
    _cameraHeight = cal.cameraHeight;
  }

  Future<void> _saveCalibration() async {
    setState(() => _isSaving = true);
    try {
      await widget.service.setCalibration(CalibrationData(
        deviceToTreeDistance: _distance,
        cameraHeight: _cameraHeight,
        sensorSize: CalibrationData.standard.sensorSize,
        focalLength: CalibrationData.standard.focalLength,
      ));
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('校準已保存')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失敗: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DBH 測量校準'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '測量距離',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '手機到樹幹的距離: ${_distance.toStringAsFixed(1)} m',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  Slider(
                    value: _distance,
                    min: 0.5,
                    max: 5.0,
                    divisions: 45,
                    label: '${_distance.toStringAsFixed(1)} m',
                    onChanged: (v) => setState(() => _distance = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '相機高度',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '相機離地高度: ${_cameraHeight.toStringAsFixed(2)} m',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  Text(
                    '(DBH 標準高度為 1.3m)',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                  Slider(
                    value: _cameraHeight,
                    min: 0.5,
                    max: 2.0,
                    divisions: 30,
                    label: '${_cameraHeight.toStringAsFixed(2)} m',
                    onChanged: (v) => setState(() => _cameraHeight = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _distance = CalibrationData.standard.deviceToTreeDistance;
                      _cameraHeight = CalibrationData.standard.cameraHeight;
                    });
                  },
                  child: const Text('重設為預設值'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveCalibration,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存校準'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '校準提示',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• 測量距離會影響精度，建議保持 1-2 公尺\n'
                  '• 相機高度應對準 DBH 測量位置 (1.3m)\n'
                  '• 定期校準可提升測量準確度',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.blue.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
