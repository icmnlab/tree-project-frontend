import 'dart:io';
import 'package:flutter/material.dart';
import 'services/carbon_calculation_service.dart';
import 'utils/carbon_display.dart';
import '../services/api_service.dart';
import 'tree_edit_page_v2.dart';
import '../services/tree_service.dart';
import 'services/auth_service.dart';
import 'services/v3/tree_image_service.dart';
import 'constants/colors.dart';
import 'utils/tree_id_display.dart';
import 'widgets/tree_measurement_history_panel.dart';
import 'services/locale_service.dart';

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

  /// 雲端最新照片（跨裝置可見；本地索引被清理後仍可顯示）
  String? _latestRemotePhotoUrl;

  String get _lifecycleStatus =>
      (_treeData['lifecycle_status'] ?? _treeData['生命週期'] ?? 'active')
          .toString()
          .trim();
  bool get _isRetired =>
      _lifecycleStatus.isNotEmpty && _lifecycleStatus != 'active';
  String get _lifecycleLabel {
    switch (_lifecycleStatus) {
      case 'dead':
        return '枯死';
      case 'fallen':
        return '倒塌';
      case 'removed':
        return '已移除';
      default:
        return '存活';
    }
  }

  int? _numericTreeId() {
    final v = _treeData['id'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

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
    await _loadLatestRemotePhoto();
  }

  /// 取雲端最新一張照片（依 captured_at）。本地索引被清理或換裝置時，仍能顯示最新照片。
  Future<void> _loadLatestRemotePhoto() async {
    final id = _numericTreeId();
    if (id == null) return;
    try {
      final res =
          await ApiService.get('tree-images/tree/$id?source=survey&latest=1');
      if (res['success'] == true && res['data'] is List && (res['data'] as List).isNotEmpty) {
        final row = (res['data'] as List).first as Map<String, dynamic>;
        final url = (row['url'] ?? row['cloud_url'] ?? row['thumbnail_url'])?.toString();
        if (mounted && url != null && url.startsWith('http')) {
          setState(() => _latestRemotePhotoUrl = url);
        }
      }
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

  Future<void> _retireTree() async {
    final id = _numericTreeId();
    if (id == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('標記為已淘汰'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '此樹將不再列入維護待辦、不計入活立木碳匯，地圖以灰階顯示。歷史與照片仍保留，可隨時復原。',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'dead'),
            child: const Text('枯死'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'fallen'),
            child: const Text('倒塌'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'removed'),
            child: const Text('移除 / 砍除'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    final res = await ApiService.post('tree_survey/$id/retire', {
      'lifecycle_status': reason,
    });
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? '已標記為淘汰')),
      );
      await _refreshTreeData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失敗：${res['message'] ?? '未知錯誤'}')),
      );
    }
  }

  Future<void> _restoreTree() async {
    final id = _numericTreeId();
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('復原樹木'),
        content: const Text('確定要將此樹復原為「存活」狀態嗎？\n復原後將重新計入活立木碳匯與維護待辦。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('復原')),
        ],
      ),
    );
    if (ok != true) return;
    final res = await ApiService.post('tree_survey/$id/restore', {});
    if (!mounted) return;
    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? '已復原')),
      );
      await _refreshTreeData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失敗：${res['message'] ?? '未知錯誤'}')),
      );
    }
  }

  Widget _buildLifecycleCard() {
    final retired = _isRetired;
    final color = retired ? Colors.orange : Colors.green;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(retired ? Icons.warning_amber_rounded : Icons.eco,
              color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  retired ? '已淘汰：$_lifecycleLabel' : '存活中',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: color.withValues(alpha: 0.95)),
                ),
                if (retired)
                  Text(
                    _f('retired_reason', '淘汰原因') == '無'
                        ? '不計入活立木碳匯、不列維護待辦'
                        : '原因：${_f('retired_reason', '淘汰原因')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
          if (_canEdit)
            retired
                ? OutlinedButton.icon(
                    onPressed: _restoreTree,
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('復原'),
                  )
                : OutlinedButton.icon(
                    onPressed: _retireTree,
                    icon: const Icon(Icons.do_not_disturb_on_outlined, size: 18),
                    label: const Text('淘汰'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange.shade800),
                  ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawProjectTreeId = _f('project_tree_id', '專案樹木');
    final displayProjectTreeId =
        TreeIdDisplay.projectTreeDigits(rawProjectTreeId == '無' ? null : rawProjectTreeId);

    final species = _f('species_name', '樹種名稱');
    final height = double.tryParse(_f('tree_height_m', '樹高（公尺）')) ?? 0.0;
    final dbh = double.tryParse(_f('dbh_cm', '胸徑（公分）')) ?? 0.0;

    // Storage: prefer DB-stored TIPC value; fall back to TIPC K_sp recompute when absent
    final dbStorage =
        double.tryParse(_f('carbon_storage', '碳儲存量'));
    final carbonStorage = dbStorage ??
        CarbonCalculationService.calculateCarbonStorage(species, height, dbh);

    // Annual: TIPC platform's internal formula uses tree age and is not public;
    // we display the DB-stored value only. 0 代表 “—” (unavailable).
    // Backend SQL aliases the column as '推估年碳吸存量'.
    final annualSequestration = double.tryParse(
            _f('carbon_sequestration_per_year', '推估年碳吸存量')) ??
        0.0;

    // [B5] 暗/亮模式輔助
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final pageBg = isDark ? AppColors.darkBackground : AppColors.surfaceLight;

    return Scaffold(
      backgroundColor: pageBg,
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
          '${species == '無' ? '未知樹種' : species} ($displayProjectTreeId)',
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
            colors: [pageBg, cardBg],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // 生命週期狀態卡（淘汰/復原）
            _buildLifecycleCard(),

            // 最新照片（優先雲端，跨裝置可見）
            if (_latestRemotePhotoUrl != null) ...[
              _buildLatestPhotoHero(),
              const SizedBox(height: 16),
            ],

            // 照片區塊（本地相簿）
            if (_treeImages.isNotEmpty)
              _buildPhotoGallery(),
            if (_treeImages.isNotEmpty)
              const SizedBox(height: 16),
            
            _buildInfoCard('基本資訊', [
              _buildInfoRow('專案', _f('project_area', '專案區位')),
              _buildInfoRow('區代碼', _f('project_code', '專案代碼')),
              _buildInfoRow('區名稱', _f('project_name', '專案名稱')),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('樹木編號', [
              _buildInfoRow('系統樹木', _f('system_tree_id', '系統樹木')),
              _buildInfoRow('區樹木（現場）', displayProjectTreeId,
                  isHighlighted: true),
              if (rawProjectTreeId != displayProjectTreeId &&
                  rawProjectTreeId != '無')
                _buildInfoRow('完整編號', rawProjectTreeId),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard(context.tr('history_title'), [
              if (_numericTreeId() != null)
                TreeMeasurementHistoryPanel(
                  treeId: _numericTreeId()!,
                  initialLimit: 20,
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('無法載入歷史（缺少樹木 ID）',
                      style: TextStyle(color: Colors.grey)),
                ),
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
              _buildInfoRow('生命週期', _isRetired ? '已淘汰（$_lifecycleLabel）' : '存活'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard(CarbonDisplay.sectionTitle, [
              _buildInfoRow(
                CarbonDisplay.rowLabelStorage(),
                CarbonDisplay.formatStorage(
                  dbStorage ?? (carbonStorage > 0 ? carbonStorage : null),
                ),
              ),
              _buildInfoRow(
                CarbonDisplay.rowLabelAnnual(),
                CarbonDisplay.formatAnnual(
                  annualSequestration > 0 ? annualSequestration : null,
                ),
              ),
              _buildInfoRow(
                '計算依據（存量）',
                CarbonDisplay.calculationBasisStorage(
                  fromDb: dbStorage != null,
                ),
              ),
              _buildInfoRow(
                '計算依據（年吸存）',
                CarbonDisplay.calculationBasisAnnual(
                  annualSequestration > 0 ? annualSequestration : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  CarbonDisplay.methodologyAnnual,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  CarbonDisplay.methodologyStorage,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ),
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
      case '碳匯（tree_survey）':
        cardIcon = Icons.eco_rounded;
        cardColor = AppColors.forestGreen;
        break;
      case '備註資訊':
        cardIcon = Icons.notes_rounded;
        cardColor = AppColors.neutral600;
        break;
      default:
        cardIcon = Icons.article_rounded;
        cardColor = AppColors.neutral600;
    }

    // [B5] helper 讀 Theme
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.neutral900;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
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
                      color: textPrimary,
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

  Widget _buildLatestPhotoHero() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.neutral900;
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.forestGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_camera, color: AppColors.forestGreen),
                const SizedBox(width: 8),
                Text('最新照片',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textPrimary)),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _latestRemotePhotoUrl!,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                errorBuilder: (ctx, e, st) => const SizedBox(
                  height: 220,
                  child: Center(child: Icon(Icons.broken_image, size: 48)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoGallery() {
    // [B5]
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.neutral900;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
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
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.forestGreen, size: 22),
                ),
                const SizedBox(width: 14),
                Text('樹木照片 (${_treeImages.length})',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary)),
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
    // [B5]
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.neutral900;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.neutral500;
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
                color: textTertiary,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '無',
              style: TextStyle(
                fontWeight: isHighlighted ? FontWeight.w600 : FontWeight.w500,
                color: isHighlighted ? AppColors.portBlue : textPrimary,
                fontSize: isHighlighted ? 15 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
