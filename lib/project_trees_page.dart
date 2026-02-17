import 'package:flutter/material.dart';
import 'tree_input_page.dart';
import 'tree_survey_page.dart';
import 'screens/ai_chat_page.dart';
import '../services/project_service.dart'; // 引入 ProjectService
import '../services/tree_service.dart'; // 引入 TreeService
import 'widgets/add_tree_dialog.dart'; // 引入 AddTreeSelectionDialog
import 'services/auth_service.dart'; // 角色權限
import 'constants/colors.dart';

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
  bool _canEdit = false;

  // [REFACTOR] 移除日誌輔助函數，改為使用標準日誌庫 (如有需要)
  // void _logDebug(String message) {
  //   debugPrint('ProjectTreesPage: $message');
  // }

  @override
  void initState() {
    super.initState();
    _fetchProjectData();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final authService = AuthService();
    final canEdit = await authService.canEditTrees();
    if (mounted) {
      setState(() => _canEdit = canEdit);
    }
  }

  final ProjectService _projectService = ProjectService();
  final TreeService _treeService = TreeService();

  Future<void> _fetchProjectData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final projectResult =
          await _projectService.getProjectByName(widget.projectName);

      if (projectResult['success']) {
        final projectData = projectResult['data'];
        final projectCode = projectData['code']?.toString();

        if (projectCode != null) {
          if (mounted) {
            setState(() {
              _projectInfo = projectData;
            });
          }
          await _fetchTrees(projectCode);
        } else {
          throw Exception('專案代碼遺失');
        }
      } else {
        final projectResultByCode =
            await _projectService.getProjectByCode(widget.projectName);
        if (projectResultByCode['success']) {
          final projectData = projectResultByCode['data'];
          if (mounted) {
            setState(() {
              _projectInfo = projectData;
            });
          }
          await _fetchTrees(widget.projectName);
        } else {
          throw Exception(projectResult['message'] ?? '找不到專案');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '載入專案資料失敗: $e';
        });
      }
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
        if (mounted) {
          setState(() {
            _trees = List<Map<String, dynamic>>.from(treeData);
            _trees.sort((a, b) {
              final aNum = int.tryParse(a['專案樹木']?.toString() ?? '0') ?? 0;
              final bNum = int.tryParse(b['專案樹木']?.toString() ?? '0') ?? 0;
              return aNum.compareTo(bNum);
            });
          });
        }
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
        builder: (context) => AIChatPage(
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
                              if (_canEdit) ...[
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
                            ],
                          ),
                          const SizedBox(height: 20),
                          if (_trees.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.surfaceLight, AppColors.surfaceLight],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.forest, color: AppColors.forestGreen),
                                  const SizedBox(width: 8),
                                  Text(
                                    '最近添加的樹木',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge!
                                        .copyWith(
                                          color: AppColors.forestGreen,
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
                                        colors: [Colors.white, AppColors.surfaceLight],
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
                                            colors: [AppColors.leafGreen, AppColors.forestGreen],
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
                                          color: AppColors.darkGreen,
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
      floatingActionButton: _canEdit
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.leafGreen, AppColors.forestGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.forestGreen.withOpacity(0.4),
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
            )
          : null,
    );
  }
}
