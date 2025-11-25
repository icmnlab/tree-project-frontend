import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'tree_input_page.dart';
import 'services/carbon_calculation_service.dart';
import '../services/api_service.dart'; // 引入 ApiService

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
    _treeData = widget.treeData;
  }

  void _editTree() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TreeInputPage(
          treeData: _treeData,
          isEdit: true,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _treeData = result;
      });
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
      body: SingleChildScrollView(
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
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            const Divider(),
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
