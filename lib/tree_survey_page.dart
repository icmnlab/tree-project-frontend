import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tree_input_page.dart';
import 'tree_input_page_v2.dart'; // 引入 V2 頁面
import 'ai_assistant_page.dart';
import 'tree_survey_detail_page.dart';
import 'services/api_service.dart'; // 引入 ApiService
import 'widgets/add_tree_dialog.dart'; // 引入 AddTreeSelectionDialog

class TreeSurveyPage extends StatefulWidget {
  final String? projectName;
  final String? areaName;

  const TreeSurveyPage({Key? key, this.projectName, this.areaName})
      : super(key: key);

  @override
  State<TreeSurveyPage> createState() => _TreeSurveyPageState();
}

class _TreeSurveyPageState extends State<TreeSurveyPage> {
  List<Map<String, dynamic>> _trees = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // 記錄日誌用的輔助函數
  void _logDebug(String message) {
    debugPrint('TreeSurveyPage: $message');
  }

  @override
  void initState() {
    super.initState();
    _fetchTrees();
    _cleanupUnusedData();
  }

  Future<void> _fetchTrees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final String endpoint;

      if (widget.projectName != null) {
        // 如果有專案名稱，則按專案名稱過濾
        _logDebug('按專案名稱過濾: ${widget.projectName}');
        endpoint =
            'tree_survey/by_project/${Uri.encodeComponent(widget.projectName!)}';
      } else if (widget.areaName != null) {
        // 如果有區位名稱，則按區位名稱過濾
        _logDebug('按區位名稱過濾: ${widget.areaName}');
        endpoint =
            'tree_survey/by_area/${Uri.encodeComponent(widget.areaName!)}';
      } else {
        // 否則獲取所有樹木
        _logDebug('獲取所有樹木');
        endpoint = 'tree_survey';
      }

      // 使用 ApiService 並處理標準回應格式
      final response = await ApiService.get(endpoint);
      _logDebug('API 響應成功');

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as List;
        _logDebug('獲取到 ${data.length} 棵樹');

        setState(() {
          _trees = List<Map<String, dynamic>>.from(data);

          // 根據專案名稱決定排序方式
          if (widget.projectName != null) {
            // 如果有專案名稱參數，根據專案樹木編號進行排序
            _trees.sort((a, b) {
              // 獲取專案樹木編號，如果不存在則使用空字串
              final String aId = a['專案樹木']?.toString() ?? '';
              final String bId = b['專案樹木']?.toString() ?? '';

              // 嘗試提取編號部分
              int aNum = _extractNumberFromId(aId);
              int bNum = _extractNumberFromId(bId);

              // 如果兩個都能提取數字部分，則按數字比較
              if (aNum != -1 && bNum != -1) {
                return aNum.compareTo(bNum);
              }

              // 否則按字串比較
              return aId.compareTo(bId);
            });
            _logDebug('按專案樹木編號排序');
          } else {
            // 否則按系統樹木編號排序
            _trees.sort((a, b) {
              // 獲取系統樹木編號，如果不存在則使用空字串
              final String aId = a['系統樹木']?.toString() ?? '';
              final String bId = b['系統樹木']?.toString() ?? '';

              // 嘗試提取編號部分
              int aNum = _extractNumberFromId(aId);
              int bNum = _extractNumberFromId(bId);

              // 如果兩個都能提取數字部分，則按數字比較
              if (aNum != -1 && bNum != -1) {
                return aNum.compareTo(bNum);
              }

              // 否則按字串比較
              return aId.compareTo(bId);
            });
            _logDebug('按系統樹木編號排序');
          }

          _isLoading = false;
        });
      } else {
        _logDebug('API 請求失敗: ${response['message']}');
        setState(() {
          _errorMessage = '無法載入資料 (${response['message'] ?? '未知錯誤'})';
          _isLoading = false;
        });
      }
    } catch (e) {
      _logDebug('發生錯誤: $e');
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
      });
    }
  }

  // 清理未使用的數據（樹種和專案區位）
  Future<void> _cleanupUnusedData() async {
    try {
      _logDebug('開始清理未使用的數據...');
      // 使用 ApiService 發送 POST 請求
      final response = await ApiService.post('project_areas/cleanup', {});

      if (response['success'] == true) {
        _logDebug('清理完成，影響行數: ${response['affectedRows']}');
      } else {
        _logDebug('清理API返回錯誤: ${response['message']}');
      }
    } catch (e) {
      _logDebug('清理過程發生錯誤: $e');
      // 不阻止正常流程，所以這裡只記錄錯誤
    }
  }

  // 從ID字串中提取數字部分
  int _extractNumberFromId(String id) {
    // 嘗試從形如 "ST-123" 或 "PT-123" 的字串中提取數字部分
    final RegExp regex = RegExp(r'[A-Za-z]+-(\d+)');
    final match = regex.firstMatch(id);

    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1) ?? '-1') ?? -1;
    }

    // 嘗試從純數字字串中提取
    if (RegExp(r'^\d+$').hasMatch(id)) {
      return int.tryParse(id) ?? -1;
    }

    return -1;
  }

  // 安全地獲取ID的最後部分
  String _getLastPartOfId(dynamic projectTreeId) {
    if (projectTreeId == null) return '?';

    final String id = projectTreeId.toString();

    // 如果格式是 XX-123，返回123部分
    final parts = id.split('-');
    if (parts.length > 1) {
      return parts.last;
    }

    // 否則返回原始ID
    return id;
  }

  void _navigateToAddProject() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TreeInputPage(
          treeData: widget.projectName != null
              ? {'專案名稱': widget.projectName}
              : widget.areaName != null
                  ? {'專案區位': widget.areaName}
                  : {},
        ),
      ),
    ).then((_) {
      setState(() {
        // 返回頁面時，先清理，再獲取最新樹木數據
        _cleanupUnusedData().then((_) => _fetchTrees());
      });
    });
  }

  // V2 導航邏輯
  void _navigateToAddProjectV2() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('進入 V2 新增模式 (後端生成 ID)'),
        backgroundColor: Colors.teal,
        duration: Duration(seconds: 1),
      ),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TreeInputPageV2(
          treeData: widget.projectName != null
              ? {
                  'project_name': widget.projectName
                } // 注意：V2 可能使用不同的鍵名，但在 populate 時會映射
              : widget.areaName != null
                  ? {'project_location': widget.areaName}
                  : {},
        ),
      ),
    ).then((_) {
      setState(() {
        _cleanupUnusedData().then((_) => _fetchTrees());
      });
    });
  }

  void _showAiAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIAssistantPage(
          userId: 'user-${DateTime.now().millisecondsSinceEpoch}',
          selectedProjectAreas: [widget.projectName ?? ''],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.projectName ?? widget.areaName ?? '樹木調查資料';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // 刷新時，先清理，再獲取最新樹木數據
              _cleanupUnusedData().then((_) => _fetchTrees());
            },
          ),
          IconButton(
            icon: const Icon(Icons.support_agent),
            tooltip: 'AI 小助手',
            onPressed: _showAiAssistant,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 60,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新整理'),
                        onPressed: () {
                          // 刷新時，先清理，再獲取最新樹木數據
                          _cleanupUnusedData().then((_) => _fetchTrees());
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ),
                )
              : _trees.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.park_outlined, size: 80, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text(
                            '沒有樹木資料',
                            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '點擊右下角按鈕新增第一筆資料',
                            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.green.shade50, Colors.white],
                        ),
                      ),
                      child: ListView.builder(
                      itemCount: _trees.length,
                      itemBuilder: (context, index) {
                        final tree = _trees[index];
                        final systemTreeId = tree['系統樹木'] ?? '未知';
                        final projectTreeId = tree['專案樹木'] ?? '未知';

                        return Card(
                          elevation: 3,
                          shadowColor: Colors.green.withOpacity(0.2),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.green.shade400, Colors.green.shade600],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  _getLastPartOfId(systemTreeId),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tree['樹種名稱'] ?? '未知樹種',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    systemTreeId.toString(),
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '${tree['專案區位']} - ${tree['專案名稱']}',
                                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.health_and_safety_outlined, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Text('狀況: ${tree['狀況'] ?? '未知'}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.straighten, size: 14, color: Colors.grey.shade600),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        '樹高: ${(tree['樹高（公尺）'] ?? 0).toString()}m, 胸徑: ${(tree['胸徑（公分）'] ?? 0).toString()}cm',
                                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '專案: ${_getLastPartOfId(projectTreeId)}',
                                        style: TextStyle(
                                          color: Colors.orange.shade700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.chevron_right, color: Colors.green.shade600),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TreeSurveyDetailPage(
                                    treeData: tree,
                                  ),
                                ),
                              ).then((_) => _fetchTrees());
                            },
                          ),
                        );
                      },
                    ),
                    ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.4),
              blurRadius: 12,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: () {
            // V2: 呼叫選擇對話框，而不是直接導航
            AddTreeSelectionDialog.show(
              context,
              initialData: widget.projectName != null
                  ? {'project_name': widget.projectName}
                  : widget.areaName != null
                      ? {'project_location': widget.areaName}
                      : {},
              onDataChanged: () {
                // 返回頁面時，先清理，再獲取最新樹木數據
                _cleanupUnusedData().then((_) => _fetchTrees());
              },
            );
          },
          backgroundColor: Colors.green,
          elevation: 0,
          tooltip: '新增樹木資料',
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }
}
