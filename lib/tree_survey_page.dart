import 'package:flutter/material.dart';
import 'screens/ai_chat_page.dart';
import 'tree_survey_detail_page.dart';
import 'services/tree_service.dart'; // 引入 TreeService
import 'widgets/add_tree_dialog.dart'; // 引入 AddTreeSelectionDialog
import 'services/auth_service.dart'; // 角色權限
import 'constants/colors.dart';

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
  final TreeService _treeService = TreeService();
  bool _canEdit = false;

  // 記錄日誌用的輔助函數
  void _logDebug(String message) {
    debugPrint('TreeSurveyPage: $message');
  }

  @override
  void initState() {
    super.initState();
    _fetchTrees();
    _cleanupUnusedData();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final canEdit = await AuthService.canEditTrees();
    if (mounted) {
      setState(() => _canEdit = canEdit);
    }
  }

  Future<void> _fetchTrees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      Map<String, dynamic> response;

      if (widget.projectName != null) {
        // 如果有專案名稱，則按專案名稱過濾
        _logDebug('按專案名稱過濾: ${widget.projectName}');
        response = await _treeService.getTreesByProjectName(widget.projectName!);
      } else if (widget.areaName != null) {
        // 如果有區位名稱，則按區位名稱過濾
        _logDebug('按區位名稱過濾: ${widget.areaName}');
        response = await _treeService.getTreesByArea(widget.areaName!);
      } else {
        // 否則獲取所有樹木
        _logDebug('獲取所有樹木');
        response = await _treeService.getAllTrees();
      }

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
      await _treeService.cleanupTemporaryData();
      _logDebug('清理請求已發送');
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

    // 否則返回原始 ID
    return id;
  }

  void _showAiAssistant() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AIChatPage(
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
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha: 0.8)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.portBlue.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '重新整理',
            onPressed: () {
              _cleanupUnusedData().then((_) => _fetchTrees());
            },
          ),
          IconButton(
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'AI 小助手',
            onPressed: _showAiAssistant,
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
        child: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.portBlue.withValues(alpha: 0.1),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.portBlue),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '載入樹木資料中...',
                    style: TextStyle(
                      color: AppColors.neutral600,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.error_outline_rounded,
                            size: 48,
                            color: AppColors.error,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '載入失敗',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.neutral900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          style: TextStyle(color: AppColors.neutral600, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          label: const Text('重新整理', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          onPressed: () {
                            _cleanupUnusedData().then((_) => _fetchTrees());
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.portBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _trees.isEmpty
                  ? Center(
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [AppColors.forestGreen.withValues(alpha: 0.1), AppColors.leafGreen.withValues(alpha: 0.1)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.park_outlined, size: 56, color: AppColors.forestGreen),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '尚無樹木資料',
                              style: TextStyle(
                                fontSize: 20,
                                color: AppColors.neutral900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '點擊下方按鈕開始新增第一筆資料',
                              style: TextStyle(fontSize: 14, color: AppColors.neutral500),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                        children: [
                          // 樹木數量標籤
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.forestGreen.withValues(alpha: 0.1),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: AppColors.forestGreen.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.park_rounded, size: 18, color: AppColors.forestGreen),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        '共 ${_trees.length} 棵樹木',
                                        style: const TextStyle(
                                          color: AppColors.forestGreen,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _trees.length,
                      itemBuilder: (context, index) {
                        final tree = _trees[index];
                        final systemTreeId = tree['系統樹木'] ?? '未知';
                        final projectTreeId = tree['專案樹木'] ?? '未知';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
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
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    // Leading icon
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [AppColors.leafGreen, AppColors.forestGreen],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppColors.forestGreen.withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          _getLastPartOfId(systemTreeId),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    // Content
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  tree['樹種名稱'] ?? '未知樹種',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                    color: AppColors.neutral900,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: AppColors.portBlue.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  systemTreeId.toString(),
                                                  style: TextStyle(
                                                    color: AppColors.portBlue,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(Icons.location_on_rounded, size: 14, color: AppColors.neutral500),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  '${tree['專案區位']} · ${tree['專案名稱']}',
                                                  style: TextStyle(color: AppColors.neutral600, fontSize: 13),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              _buildInfoChip(
                                                Icons.height_rounded,
                                                '${(tree['樹高（公尺）'] ?? 0).toString()}m',
                                                AppColors.forestGreen,
                                              ),
                                              const SizedBox(width: 8),
                                              _buildInfoChip(
                                                Icons.circle_outlined,
                                                '${(tree['胸徑（公分）'] ?? 0).toString()}cm',
                                                AppColors.warmOrange,
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: AppColors.accentSurface,
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  '專案: ${_getLastPartOfId(projectTreeId)}',
                                                  style: TextStyle(
                                                    color: AppColors.forestGreen,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Trailing
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceLight,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.chevron_right_rounded, color: AppColors.neutral500, size: 20),
                                    ),
                                  ],
                                ),
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
      floatingActionButton: _canEdit
          ? Padding(
              padding: EdgeInsets.only(
                  bottom: Navigator.canPop(context)
                      ? 16
                      : 80), // 如果是 push 進來的(獨立頁面)則不需太高，如果是 Tab 則需避開底部導航
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha: 0.85)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.portBlue.withValues(alpha: 0.4),
                      blurRadius: 16,
                      spreadRadius: 0,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: FloatingActionButton(
                  onPressed: () {
                    AddTreeSelectionDialog.show(
                      context,
                      initialData: widget.projectName != null
                          ? {'project_name': widget.projectName}
                          : widget.areaName != null
                              ? {'project_location': widget.areaName}
                              : {},
                      onDataChanged: () {
                        _cleanupUnusedData().then((_) => _fetchTrees());
                      },
                    );
                  },
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  tooltip: '新增樹木資料',
                  child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
