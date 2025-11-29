import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'tree_input_page.dart';
import 'tree_input_page_v2.dart'; // 引入 V2 頁面
import 'tree_survey_page.dart';
import 'ai_assistant_page.dart';
import '../services/api_service.dart'; // 引入 ApiService
import '../services/project_service.dart'; // 引入 ProjectService
import '../services/tree_service.dart'; // 引入 TreeService
import 'widgets/add_tree_dialog.dart'; // 引入 AddTreeSelectionDialog

class ProjectTreesPage extends StatefulWidget {
  final String projectName;

  const ProjectTreesPage({Key? key, required this.projectName})
      : super(key: key);

  @override
  State<ProjectTreesPage> createState() => _ProjectTreesPageState();
}

class _ProjectTreesPageState extends State<ProjectTreesPage> {
  Map<String, dynamic>? _projectInfo;
  List<Map<String, dynamic>> _trees = [];
  bool _isLoading = true;
  String _errorMessage = '';

  // [REFACTOR] 移除日誌輔助函數，改為使用標準日誌庫 (如有需要)
  // void _logDebug(String message) {
  //   debugPrint('ProjectTreesPage: $message');
  // }

  @override
  void initState() {
    super.initState();
    // 觸發一次性的背景清理任務
    // ApiService.triggerCleanup(); // 根據新架構，此類呼叫應由更上層的邏輯處理，此處移除
    _fetchProjectData();
  }

  final ProjectService _projectService = ProjectService();
  final TreeService _treeService = TreeService();

  // [REFACTOR] 將 _fetchProjectInfo 拆分為 _fetchProjectData 和 _fetchTrees
  Future<void> _fetchProjectData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 使用 ProjectService 獲取專案資訊
      final projectResult =
          await _projectService.getProjectByName(widget.projectName);

      if (projectResult['success']) {
        final projectData = projectResult['data'];
        final projectCode = projectData['code']?.toString();

        if (projectCode != null) {
          setState(() {
            _projectInfo = projectData;
          });
          // 成功獲取專案資訊後，接著獲取樹木列表
          await _fetchTrees(projectCode);
        } else {
          throw Exception('專案代碼遺失');
        }
      } else {
        // 如果按名稱找不到，嘗試按代碼獲取 (假設 projectName 可能也是 code)
        final projectResultByCode =
            await _projectService.getProjectByCode(widget.projectName);
        if (projectResultByCode['success']) {
          final projectData = projectResultByCode['data'];
          setState(() {
            _projectInfo = projectData;
          });
          await _fetchTrees(widget.projectName);
        } else {
          throw Exception(projectResult['message'] ?? '找不到專案');
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = '載入專案資料失敗: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchTrees(String projectCode) async {
    try {
      // 使用 TreeService 獲取樹木列表
      final treesResult = await _treeService.getTreesByProjectCode(projectCode);

      if (treesResult['success']) {
        final List<dynamic> treeData = treesResult['data'];
        setState(() {
          _trees = List<Map<String, dynamic>>.from(treeData);
          // 排序邏輯保持不變
          _trees.sort((a, b) {
            final aNum = int.tryParse(a['專案樹木']?.toString() ?? '0') ?? 0;
            final bNum = int.tryParse(b['專案樹木']?.toString() ?? '0') ?? 0;
            return aNum.compareTo(bNum);
          });
        });
      } else {
        throw Exception(treesResult['message'] ?? '無法載入樹木列表');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '載入樹木資料時發生錯誤: $e';
        });
      }
    }
  }

  // [REFACTOR] 移除舊的 _fetchProjectInfo 和 _fetchTreesByProjectId
  /*
  Future<void> _fetchProjectInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 首先嘗試使用專案名稱獲取專案信息
      _logDebug('使用專案名稱獲取資料: ${widget.projectName}');

      // 確保URL正確編碼
      final String encodedName = Uri.encodeComponent(widget.projectName);
      final Uri uri = Uri.parse(
          'http://172.20.10.4:3000/api/projects/by_name/$encodedName');

      _logDebug('API請求URL: ${uri.toString()}');
      final response = await http.get(uri);
      _logDebug('API響應狀態碼: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _logDebug('成功獲取專案信息');

        setState(() {
          _projectInfo = data;
          _isLoading = false;
        });

        // 如果專案信息存在，使用專案ID獲取樹木
        if (_projectInfo != null && _projectInfo!['id'] != null) {
          _fetchTreesByProjectId(_projectInfo!['id'].toString());
        }
      } else if (response.statusCode == 404) {
        _logDebug('未找到專案，嘗試使用專案代碼獲取');

        // 如果名稱不存在，嘗試使用專案代碼
        final String projectCode = widget.projectName.replaceAll(' ', '_');
        final Uri codeUri = Uri.parse(
            'http://172.20.10.4:3000/api/projects/by_code/$projectCode');

        _logDebug('嘗試使用代碼API請求URL: ${codeUri.toString()}');
        final codeResponse = await http.get(codeUri);
        _logDebug('代碼API響應狀態碼: ${codeResponse.statusCode}');

        if (codeResponse.statusCode == 200) {
          final data = jsonDecode(codeResponse.body);
          _logDebug('成功使用專案代碼獲取資料');

          setState(() {
            _projectInfo = data;
            _isLoading = false;
          });

          // 如果專案信息存在，使用專案ID獲取樹木
          if (_projectInfo != null && _projectInfo!['id'] != null) {
            _fetchTreesByProjectId(_projectInfo!['id'].toString());
          }
        } else {
          _logDebug('使用專案代碼獲取失敗: ${codeResponse.statusCode}');
          setState(() {
            _errorMessage = '無法找到專案資料 (錯誤: ${codeResponse.statusCode})';
            _isLoading = false;
          });
        }
      } else {
        _logDebug('API請求失敗: ${response.statusCode}');
        setState(() {
          _errorMessage = '無法載入專案資料 (錯誤: ${response.statusCode})';
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

  // 使用專案ID獲取樹木
  Future<void> _fetchTreesByProjectId(String projectId) async {
    try {
      _logDebug('使用專案ID獲取樹木: $projectId');
      // 修改 API 路徑，使用專案名稱而非 ID
      final Uri treesUri = Uri.parse(
          'http://172.20.10.4:3000/api/tree_survey/by_project/${Uri.encodeComponent(widget.projectName)}');

      _logDebug('樹木API請求URL: ${treesUri.toString()}');
      final treesResponse = await http.get(treesUri);
      _logDebug('樹木API響應狀態碼: ${treesResponse.statusCode}');

      if (treesResponse.statusCode == 200) {
        final List<dynamic> treeData = jsonDecode(treesResponse.body);
        _logDebug('成功獲取 ${treeData.length} 棵樹');

        setState(() {
          _trees = List<Map<String, dynamic>>.from(treeData);

          // 按照專案樹木編號排序 (project_tree_number)
          _trees.sort((a, b) {
            // 首先檢查是否存在project_tree_number
            if (a['project_tree_number'] == null &&
                b['project_tree_number'] == null) {
              return 0;
            }
            if (a['project_tree_number'] == null) {
              return 1;
            }
            if (b['project_tree_number'] == null) {
              return -1;
            }

            // 確保數字比較（避免字串比較）
            final aNum = int.tryParse('${a['project_tree_number']}') ?? 0;
            final bNum = int.tryParse('${b['project_tree_number']}') ?? 0;
            return aNum.compareTo(bNum);
          });
        });
      } else {
        _logDebug('獲取樹木失敗: ${treesResponse.statusCode}');
      }
    } catch (e) {
      _logDebug('獲取樹木時發生錯誤: $e');
    }
  }
  */

  void _navigateToAddTree() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            TreeInputPage(treeData: {'專案名稱': widget.projectName}),
      ),
    ).then((_) {
      _fetchProjectData(); // 刷新頁面
    });
  }

  // [REFACTOR] 使用 Dialog 選擇 V1/V2
  void _showAddDialog() {
    AddTreeSelectionDialog.show(
      context,
      initialData: {'project_name': widget.projectName}, // 這裡使用 project_name
      onDataChanged: () {
        _fetchProjectData(); // 刷新頁面
      },
    );
  }

  void _navigateToViewAllTrees() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TreeSurveyPage(projectName: widget.projectName),
      ),
    );
  }

  void _showAiAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIAssistantPage(
          userId: 'user-${DateTime.now().millisecondsSinceEpoch}',
          selectedProjectAreas: [widget.projectName],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.projectName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProjectData,
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
                        onPressed: _fetchProjectData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ),
                )
              : _projectInfo == null
                  ? const Center(child: Text('找不到專案資料'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              widget.projectName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall!
                                  .copyWith(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.visibility),
                                  label: const Text('查看所有樹木'),
                                  onPressed: _navigateToViewAllTrees,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    padding: const EdgeInsets.all(12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.add),
                                  label: const Text('新增樹木'),
                                  onPressed: _navigateToAddTree,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    padding: const EdgeInsets.all(12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_trees.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.green.shade50, Colors.green.shade100],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.forest, color: Colors.green.shade700),
                                  const SizedBox(width: 8),
                                  Text(
                                    '最近添加的樹木',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge!
                                        .copyWith(
                                          color: Colors.green.shade700,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._trees.take(5).map((tree) => Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  elevation: 3,
                                  shadowColor: Colors.green.withOpacity(0.3),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: LinearGradient(
                                        colors: [Colors.white, Colors.green.shade50],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                        child: const Icon(Icons.nature, color: Colors.white),
                                      ),
                                      title: Text(
                                        tree['樹種名稱'] ?? '未知樹種',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 4),
                                          Text(
                                              '編號: ${tree['系統樹木'] ?? '未知'} (專案: ${tree['專案樹木'] ?? '未知'})'),
                                          Text(
                                              '樹高: ${(tree['樹高（公尺）'] ?? 0).toString()} 公尺, 胸徑: ${(tree['胸徑（公分）'] ?? 0).toString()} 公分'),
                                        ],
                                      ),
                                      isThreeLine: true,
                                    ),
                                  ),
                                )),
                          ],
                        ],
                      ),
                    ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.green.shade400, Colors.green.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _showAddDialog,
          backgroundColor: Colors.transparent,
          elevation: 0,
          tooltip: '新增樹木資料',
          child: const Icon(Icons.add, size: 28),
        ),
      ),
    );
  }
}
