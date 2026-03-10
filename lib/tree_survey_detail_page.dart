import 'dart:io';
import 'package:flutter/material.dart';
import 'services/carbon_calculation_service.dart';
import '../services/api_service.dart';
import 'tree_edit_page_v2.dart';
import '../services/tree_service.dart';
import 'services/auth_service.dart';
import 'services/v3/tree_image_service.dart';
import 'constants/colors.dart';

class TreeSurveyDetailPage extends StatefulWidget {
  final dynamic treeData;

  const TreeSurveyDetailPage({super.key, required this.treeData});

  @override
  State<TreeSurveyDetailPage> createState() => _TreeSurveyDetailPageState();
}

class _TreeSurveyDetailPageState extends State<TreeSurveyDetailPage> {
  late Map<String, dynamic> _treeData;
  bool _canEdit = false;
  bool _canDelete = false;
  List<TreeImage> _treeImages = [];
  final TreeImageService _imageService = TreeImageService();

  /// Bilingual field accessor — tries English key first, then Chinese
  String _f(String enKey, String zhKey) {
    final v = _treeData[enKey] ?? _treeData[zhKey];
    return v?.toString() ?? '無';
  }

  @override
  void initState() {
    super.initState();
    ApiService.triggerCleanup();
    _treeData = Map<String, dynamic>.from(widget.treeData);
    _loadPermissions();
    _loadImages();
  }

  Future<void> _loadImages() async {
    final treeId = (_treeData['id'] ?? _treeData['系統樹木'])?.toString();
    if (treeId == null) return;
    try {
      final images = await _imageService.getTreeImages(treeId);
      if (mounted) setState(() => _treeImages = images);
    } catch (_) {}
  }

  Future<void> _loadPermissions() async {
    final canEdit = await AuthService.canEditTrees();
    final canDelete = await AuthService.canDeleteTrees();
    if (mounted) {
      setState(() {
        _canEdit = canEdit;
        _canDelete = canDelete;
      });
    }
  }

  void _editTree() async {
    _navigateToEditor(TreeEditPageV2(treeData: _treeData));
  }

  // [V2 NEW] Helper method to handle navigation and data refreshing.
  Future<void> _navigateToEditor(Widget editPage) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => editPage),
    );

    if (result == true) {
      _refreshTreeData();
    }
  }

  // [V2] 新增一個方法來從後端重新獲取最新的樹木資料
  Future<void> _refreshTreeData() async {
    final treeService = TreeService();
    try {
      final treeId = _treeData['id'].toString();
      final response = await treeService.getTreeById(treeId);
      if (response['success'] == true && response['data'] != null) {
        if (mounted) {
      setState(() {
            _treeData = response['data'];
      });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('無法重新整理資料')));
      }
    }
  }

  Future<void> _confirmAndDeleteTree() async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除這筆樹木資料嗎？\n此操作無法復原。'),
        actions: [
          TextButton(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: const Text('確定刪除'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      _deleteTree();
    }
  }

  Future<void> _deleteTree() async {
    final treeId = _treeData['id'];
    if (treeId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('無效的樹木 ID')));
      }
      return;
    }

    final response = await ApiService.delete('tree_survey/$treeId');

    if (mounted) {
      if (response['success'] == true) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('資料刪除成功')));
        // 刪除成功後，返回上一頁並觸發列表刷新
        Navigator.pop(context, true);
      } else {
        final errorMessage = response['message'] ?? '未知錯誤';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刪除失敗: $errorMessage')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String projectTreeId = _f('project_tree_id', '專案樹木');

    final species = _f('species_name', '樹種名稱');
    final height = double.tryParse(_f('tree_height_m', '樹高（公尺）')) ?? 5.0;
    final dbh = double.tryParse(_f('dbh_cm', '胸徑（公分）')) ?? 15.0;

    // 估算樹齡
    int estimatedAge = 10; // 預設值
    if (dbh > 30) {
      estimatedAge = 40;
    } else if (dbh > 20)
      estimatedAge = 25;
    else if (dbh > 10) estimatedAge = 15;

    // 使用新的服務計算碳數據
    final carbonStorage =
        CarbonCalculationService.calculateCarbonStorage(species, height, dbh);
    final annualSequestration =
        CarbonCalculationService.calculateAnnualCarbonSequestration(
            species, height, dbh, estimatedAge);

    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha:0.8)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.portBlue.withValues(alpha:0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: Text(
          '${species == '無' ? '未知樹種' : species} ($projectTreeId)',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            letterSpacing: 0.3,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_canEdit)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: '編輯',
              onPressed: _editTree,
            ),
          if (_canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: '刪除資料',
              onPressed: _confirmAndDeleteTree,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceLight, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 照片區塊
            if (_treeImages.isNotEmpty)
              _buildPhotoGallery(),
            if (_treeImages.isNotEmpty)
              const SizedBox(height: 16),
            
            _buildInfoCard('基本資訊', [
              _buildInfoRow('專案區位', _f('project_area', '專案區位')),
              _buildInfoRow('專案代碼', _f('project_code', '專案代碼')),
              _buildInfoRow('專案名稱', _f('project_name', '專案名稱')),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('樹木編號', [
              _buildInfoRow('系統樹木', _f('system_tree_id', '系統樹木')),
              _buildInfoRow('專案樹木', _f('project_tree_id', '專案樹木'),
                  isHighlighted: true),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('樹種資訊', [
              _buildInfoRow('樹種編號', _f('species_id', '樹種編號')),
              _buildInfoRow('樹種名稱', _f('species_name', '樹種名稱')),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('位置資訊', [
              _buildInfoRow('X坐標', _f('x_coord', 'X坐標')),
              _buildInfoRow('Y坐標', _f('y_coord', 'Y坐標')),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('生長資訊', [
              _buildInfoRow('樹高', '${_f('tree_height_m', '樹高（公尺）')} 公尺'),
              _buildInfoRow('胸徑', '${_f('dbh_cm', '胸徑（公分）')} 公分'),
              _buildInfoRow('狀況', _f('status', '狀況')),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('碳存量資訊', [
              _buildInfoRow('碳儲存量', '${_f('carbon_storage', '碳儲存量')} kg'),
              _buildInfoRow('推估年碳吸存量', '${_f('carbon_sequestration_per_year', '推估年碳吸存量')} kg/yr'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('碳吸收資訊', [
              _buildInfoRow('碳儲存量', '${carbonStorage.toStringAsFixed(2)} 公斤CO2e'),
              _buildInfoRow('年碳吸收量', '${annualSequestration.toStringAsFixed(2)} 公斤CO2e/年'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('備註資訊', [
              _buildInfoRow('註記', _f('note', '註記')),
              _buildInfoRow('樹木備註', _f('tree_remark', '樹木備註')),
              _buildInfoRow('調查備註', _f('survey_notes', '調查備註')),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('調查資訊', [
              _buildInfoRow('調查時間', _f('survey_time', '調查時間')),
            ]),
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    // 根據標題選擇圖標和顏色
    IconData cardIcon;
    Color cardColor;
    switch (title) {
      case '基本資訊':
        cardIcon = Icons.info_outline_rounded;
        cardColor = AppColors.portBlue;
        break;
      case '樹木編號':
        cardIcon = Icons.tag_rounded;
        cardColor = AppColors.warmOrange;
        break;
      case '樹種資訊':
        cardIcon = Icons.park_rounded;
        cardColor = AppColors.forestGreen;
        break;
      case '位置資訊':
        cardIcon = Icons.location_on_rounded;
        cardColor = AppColors.tipcRed;
        break;
      case '狀況資訊':
        cardIcon = Icons.health_and_safety_rounded;
        cardColor = AppColors.tipcTeal;
        break;
      case '測量數據':
        cardIcon = Icons.straighten_rounded;
        cardColor = AppColors.tipcPurple;
        break;
      case '碳數據':
        cardIcon = Icons.eco_rounded;
        cardColor = AppColors.forestGreen;
        break;
      case '調查資訊':
        cardIcon = Icons.assignment_rounded;
        cardColor = AppColors.info;
        break;
      case '生長資訊':
        cardIcon = Icons.trending_up_rounded;
        cardColor = AppColors.forestGreen;
        break;
      case '碳存量資訊':
        cardIcon = Icons.eco_rounded;
        cardColor = AppColors.forestGreen;
        break;
      case '碳吸收資訊':
        cardIcon = Icons.co2_rounded;
        cardColor = AppColors.leafGreen;
        break;
      case '備註資訊':
        cardIcon = Icons.notes_rounded;
        cardColor = AppColors.neutral600;
        break;
      default:
        cardIcon = Icons.article_rounded;
        cardColor = AppColors.neutral600;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: cardColor.withValues(alpha:0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cardColor.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(cardIcon, color: cardColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: AppColors.neutral900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cardColor.withValues(alpha:0.3), cardColor.withValues(alpha:0.05)],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGallery() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha:0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.forestGreen.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.photo_library_rounded, color: AppColors.forestGreen, size: 22),
                ),
                const SizedBox(width: 14),
                Text('樹木照片 (${_treeImages.length})',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.neutral900)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _treeImages.length,
                itemBuilder: (context, index) {
                  final img = _treeImages[index];
                  final file = File(img.localPath);
                  return Padding(
                    padding: EdgeInsets.only(right: index < _treeImages.length - 1 ? 8 : 0),
                    child: GestureDetector(
                      onTap: () => _showFullImage(file),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: file.existsSync()
                            ? Image.file(file, width: 120, height: 120, fit: BoxFit.cover)
                            : Container(
                                width: 120, height: 120,
                                color: Colors.grey.shade200,
                                child: const Icon(Icons.broken_image, color: Colors.grey),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(File imageFile) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: InteractiveViewer(
          child: Image.file(imageFile),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value,
      {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: AppColors.neutral500,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '無',
              style: TextStyle(
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
                color: isHighlighted ? AppColors.portBlue : AppColors.neutral900,
                fontSize: isHighlighted ? 15 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
