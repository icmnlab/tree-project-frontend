import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'tree_input_page.dart';
import 'services/carbon_calculation_service.dart';
import '../services/api_service.dart'; // 引入 ApiService
import 'tree_edit_page_v2.dart'; // [V2] 引入新的編輯頁面
import '../services/tree_service.dart'; // [V2] 引入 TreeService

class TreeSurveyDetailPage extends StatefulWidget {
  final dynamic treeData;

  const TreeSurveyDetailPage({super.key, required this.treeData});

  @override
  State<TreeSurveyDetailPage> createState() => _TreeSurveyDetailPageState();
}

class _TreeSurveyDetailPageState extends State<TreeSurveyDetailPage> {
  late Map<String, dynamic> _treeData;

  @override
  void initState() {
    super.initState();
    // 觸發一次性的背景清理任務
    ApiService.triggerCleanup();
    _treeData = Map<String, dynamic>.from(widget.treeData);
  }

  void _editTree() async {
    // [V2 REVISED] Always show a dialog to let the user choose the edit mode.
    // This allows using the V2 editor for V1 data, facilitating migration.
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('選擇編輯模式'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.article, color: Colors.green),
                title: const Text('標準編輯器 (V1)'),
                subtitle: const Text('使用舊版介面修改'),
                onTap: () {
                  Navigator.pop(dialogContext); // Close dialog
                  _navigateToEditor(TreeInputPage(
                    treeData: _treeData,
                    isEdit: true,
                  ));
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.brush, color: Colors.teal),
                title: const Text('新版編輯器 (V2)'),
                subtitle: const Text('使用新版介面修改 (推薦)'),
                onTap: () {
                  Navigator.pop(dialogContext); // Close dialog
                  _navigateToEditor(TreeEditPageV2(treeData: _treeData));
                },
              ),
            ],
          ),
        );
      },
    );
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
    // 獲取專案樹木編號
    String projectTreeId = _treeData['專案樹木']?.toString() ?? '未知';

    // 獲取樹木數據
    final species = _treeData['樹種名稱'] ?? '其他';
    final height = double.tryParse(_treeData['樹高（公尺）'].toString()) ?? 5.0;
    final dbh = double.tryParse(_treeData['胸徑（公分）'].toString()) ?? 15.0;

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
      appBar: AppBar(
        title:
            Text('${_treeData['樹種名稱']?.toString() ?? '未知樹種'} ($projectTreeId)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _editTree,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: '刪除資料',
            onPressed: _confirmAndDeleteTree,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.green.shade50, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            _buildInfoCard('基本資訊', [
              _buildInfoRow('專案區位', _treeData['專案區位']?.toString() ?? '無'),
              _buildInfoRow('專案代碼', _treeData['專案代碼']?.toString() ?? '無'),
              _buildInfoRow('專案名稱', _treeData['專案名稱']?.toString() ?? '無'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('樹木編號', [
              _buildInfoRow('系統樹木', _treeData['系統樹木']?.toString() ?? '無'),
              _buildInfoRow('專案樹木', _treeData['專案樹木']?.toString() ?? '無',
                  isHighlighted: true),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('樹種資訊', [
              _buildInfoRow('樹種編號', _treeData['樹種編號']?.toString() ?? '無'),
              _buildInfoRow('樹種名稱', _treeData['樹種名稱']?.toString() ?? '無'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('位置資訊', [
              _buildInfoRow('X坐標', _treeData['X坐標']?.toString() ?? '無'),
              _buildInfoRow('Y坐標', _treeData['Y坐標']?.toString() ?? '無'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('生長資訊', [
              _buildInfoRow(
                  '樹高', '${_treeData['樹高（公尺）']?.toString() ?? '無'} 公尺'),
              _buildInfoRow(
                  '胸徑', '${_treeData['胸徑（公分）']?.toString() ?? '無'} 公分'),
              _buildInfoRow('狀況', _treeData['狀況']?.toString() ?? '無'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('碳存量資訊', [
              _buildInfoRow(
                  '碳儲存量', '${_treeData['碳儲存量']?.toString() ?? '無'} kg'),
              _buildInfoRow('推估年碳吸存量',
                  '${_treeData['推估年碳吸存量']?.toString() ?? '無'} kg/yr'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('碳吸收資訊', [
              _buildInfoRow(
                  '碳儲存量', '${carbonStorage.toStringAsFixed(2)} 公斤CO₂e'),
              _buildInfoRow('年碳吸收量',
                  '${annualSequestration.toStringAsFixed(2)} 公斤CO₂e/年'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('備註資訊', [
              _buildInfoRow('註記', _treeData['註記']?.toString() ?? '無'),
              _buildInfoRow('樹木備註', _treeData['樹木備註']?.toString() ?? '無'),
              _buildInfoRow('調查備註', _treeData['調查備註']?.toString() ?? '無'),
            ]),
            const SizedBox(height: 16),
            _buildInfoCard('調查資訊', [
              _buildInfoRow('調查時間', _treeData['調查時間']?.toString() ?? '無'),
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
        cardIcon = Icons.info_outline;
        cardColor = Colors.blue;
        break;
      case '樹木編號':
        cardIcon = Icons.tag;
        cardColor = Colors.orange;
        break;
      case '樹種資訊':
        cardIcon = Icons.park;
        cardColor = Colors.green;
        break;
      case '位置資訊':
        cardIcon = Icons.location_on;
        cardColor = Colors.red;
        break;
      case '狀況資訊':
        cardIcon = Icons.health_and_safety;
        cardColor = Colors.teal;
        break;
      case '測量數據':
        cardIcon = Icons.straighten;
        cardColor = Colors.purple;
        break;
      case '碳數據':
        cardIcon = Icons.eco;
        cardColor = Colors.green.shade700;
        break;
      case '調查資訊':
        cardIcon = Icons.assignment;
        cardColor = Colors.indigo;
        break;
      default:
        cardIcon = Icons.article;
        cardColor = Colors.grey;
    }

    return Card(
      elevation: 4,
      shadowColor: cardColor.withOpacity(0.3),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              cardColor.withOpacity(0.05),
            ],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(cardIcon, color: cardColor, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cardColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: cardColor.withOpacity(0.2)),
            const SizedBox(height: 4),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value,
      {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label：',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '無',
              style: TextStyle(
                fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                color: isHighlighted ? Colors.green.shade700 : Colors.black,
                fontSize: isHighlighted ? 16 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
