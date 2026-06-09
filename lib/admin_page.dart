import 'package:flutter/material.dart';
import 'constants/colors.dart';
// import 'package:provider/provider.dart'; // Unused
import 'screens/user_form_screen.dart';
import 'services/user_service.dart';
import 'services/project_service.dart';
import 'services/project_area_service.dart';
import 'services/admin_service.dart'; // ExportService 來自此檔
import 'models/project.dart';
import 'screens/v3/project_boundary_draw_page.dart'; // V3 專案邊界繪製
import 'screens/project_areas_admin_page.dart'; // 專案區位 CRUD 管理
import 'screens/system_settings_page.dart'; // 系統狀態與維運
import 'screens/csv_import_page.dart'; // [Phase C] CSV 匯入頁面
import 'screens/ip_blacklist_page.dart'; // [T8.2] IP 黑名單管理
import 'admin_research_dataset_page.dart'; // [Research] DBH 校準資料蒐集
import 'screens/invite_management_page.dart';
import 'screens/audit_log_page.dart';
import 'screens/pending_password_resets_page.dart';
import 'screens/role_permissions_page.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import 'config/survey_settings.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  int _selectedIndex = 0;
  bool _isSidebarVisible = true; // 控制側邊欄是否顯示
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String _selectedRole = '全部';
  // [T7] 角色權限
  bool _canManageProjects = false; // 專案邊界 tab
  bool _canImportCsv = false;       // CSV 匯入 tab
  bool _canManageIpBlacklist = false; // [T8.2] IP 黑名單 tab
  bool _canManageInvites = false; // 邀請碼／使用者管理（業務管理員以上）
  bool _isSystemAdmin = false; // 系統管理員：系統維運分頁、研究資料集

  List<Project> _projectsForExport = [];
  List<String> _selectedProjectCodesForMultiExport = []; // 用於儲存多選的專案代碼
  bool _isLoadingProjects = false;
  bool _isExportingExcel = false;
  bool _isExportingPdf = false;
  bool _researchMode = false;

  // Services
  final UserService _userService = UserService();
  final ProjectService _projectService = ProjectService();
  final ProjectAreaService _projectAreaService = ProjectAreaService();

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchProjectsForExport();
    _loadPermissions();
    _researchMode = SurveySettings.instance.researchModeEnabled;
  }

  // [T7] 載入角色權限 -> 控制 tab 顯示
  Future<void> _loadPermissions() async {
    final canManage = await AuthService.canManageProjects();
    final canCsv = await AuthService.canImportCsv();
    final canIp = await AuthService.canManageIpBlacklist();
    final canInvites = await AuthService.canManageUsers();
    final isSysAdmin = await AuthService.hasMinimumRole('系統管理員');
    if (mounted) {
      setState(() {
        _canManageProjects = canManage;
        _canImportCsv = canCsv;
        _canManageIpBlacklist = canIp;
        _canManageInvites = canInvites;
        _isSystemAdmin = isSysAdmin;
      });
    }
  }

  // [T7] 4 個固定 tab + 3 個可選 tab；依角色展開對應的頁面
  Widget _buildBodyForIndex() {
    final pages = <Widget>[
      _buildUserList(),
      _buildPendingApprovalUsers(),
      _buildExportOptions(),
      _buildAdminZone(),
      _buildProjectManagement(),
      if (_canManageProjects) const ProjectBoundaryDrawPage(),
      if (_canManageProjects) const ProjectAreasAdminPage(),
      if (_canImportCsv) const CsvImportPage(),
      if (_canManageIpBlacklist) const IpBlacklistPage(),
      if (_isSystemAdmin) const SystemSettingsPage(),
    ];
    final idx = _selectedIndex.clamp(0, pages.length - 1);
    return pages[idx];
  }

  List<Map<String, dynamic>> get _filteredUsers {
    return _users.where((user) {
      final matchesSearch = user['username']
              .toString()
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          (user['display_name']
                  ?.toString()
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ??
              false);

      final matchesRole =
          _selectedRole == '全部' || user['role'] == _selectedRole;

      return matchesSearch && matchesRole;
    }).toList();
  }

  List<Map<String, dynamic>> get _pendingApprovalUsers {
    final pending = _users
        .where((user) =>
            user['pending_approval'] == true && user['is_active'] != true)
        .toList();
    pending.sort((a, b) {
      final ta = a['created_at']?.toString() ?? '';
      final tb = b['created_at']?.toString() ?? '';
      return tb.compareTo(ta);
    });
    return pending;
  }

  int get _pendingApprovalCount => _pendingApprovalUsers.length;

  String _formatUserTime(dynamic value) {
    if (value == null) return '—';
    return value.toString().replaceFirst('T', ' ').split('.').first;
  }

  Widget _railIcon(IconData icon, {int badge = 0}) {
    if (badge <= 0) return Icon(icon);
    return Badge(
      label: Text('$badge'),
      child: Icon(icon),
    );
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final users = await _userService.fetchUsers();
      if (!mounted) return;
      setState(() {
        _users = users.map((user) {
          bool parseBool(dynamic v, {required bool defaultValue}) {
            if (v is bool) return v;
            if (v is int) return v == 1;
            if (v is String) {
              return v.toLowerCase() == 'true';
            }
            return defaultValue;
          }

          return {
            ...user,
            'is_active': parseBool(user['is_active'], defaultValue: true),
            'pending_approval':
                parseBool(user['pending_approval'], defaultValue: false),
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入使用者資料: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchProjectsForExport() async {
    setState(() {
      _isLoadingProjects = true;
      _selectedProjectCodesForMultiExport.clear(); // 清空已選
    });
    try {
      final projectsResponse = await _projectService.getProjects();
      if (!mounted) return;
      if (projectsResponse['success'] == true &&
          projectsResponse['data'] != null) {
        setState(() {
          _projectsForExport = (projectsResponse['data'] as List)
              .map((json) => Project.fromJson(json))
              .toList();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(projectsResponse['message'] ?? '無法載入專案列表')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入專案列表發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProjects = false;
        });
      }
    }
  }

  // 新增方法：顯示專案多選對話框
  Future<void> _showProjectMultiSelectDialog() async {
    final List<String> tempSelectedCodes =
        List.from(_selectedProjectCodesForMultiExport);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateDialog) {
            return AlertDialog(
              title: const Text('選擇要匯出的專案'),
              contentPadding: const EdgeInsets.only(
                  top: 12.0, left: 0.0, right: 0.0, bottom: 0.0),
              content: SizedBox(
                width: double.maxFinite,
                child: _isLoadingProjects // 在對話框內部也處理載入狀態
                    ? const Center(
                        child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator()))
                    : _projectsForExport.isEmpty
                        ? const Center(
                            child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('沒有可供選擇的專案。')))
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: _projectsForExport.length,
                            itemBuilder: (BuildContext context, int index) {
                              final project = _projectsForExport[index];
                              final bool isSelected =
                                  tempSelectedCodes.contains(project.code);
                              return CheckboxListTile(
                                title: Text('${project.name} (${project.code})',
                                    style: const TextStyle(fontSize: 14)),
                                subtitle: project.area != null &&
                                        project.area!.isNotEmpty
                                    ? Text(project.area!,
                                        style: const TextStyle(
                                            fontSize: 12, color: Colors.grey))
                                    : null,
                                value: isSelected,
                                onChanged: (bool? value) {
                                  setStateDialog(() {
                                    if (value == true) {
                                      if (!tempSelectedCodes
                                          .contains(project.code)) {
                                        tempSelectedCodes.add(project.code);
                                      }
                                    } else {
                                      tempSelectedCodes.remove(project.code);
                                    }
                                  });
                                },
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16.0, vertical: 0),
                              );
                            },
                          ),
              ),
              actionsAlignment: MainAxisAlignment.spaceBetween,
              actions: <Widget>[
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  child: const Text('清除全部'),
                  onPressed: _projectsForExport.isEmpty // 如果沒有專案，禁用此按鈕
                      ? null
                      : () {
                          setStateDialog(() {
                            tempSelectedCodes.clear();
                          });
                        },
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      child: const Text('取消'),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                    ElevatedButton(
                      child: const Text('確認選擇'),
                      onPressed: () {
                        setState(() {
                          _selectedProjectCodesForMultiExport =
                              List.from(tempSelectedCodes);
                        });
                        Navigator.of(dialogContext).pop();
                      },
                    ),
                  ],
                )
              ],
            );
          },
        );
      },
    );
    // 主頁面UI將由按鈕文字和已選代碼的 Text Widget 更新，無需在此處額外 setState
  }

  Future<void> _exportExcel() async {
    if (_isExportingExcel) return; // 防止重複點擊
    
    setState(() => _isExportingExcel = true);
    try {
      final result = await ExportService.downloadExcel(_selectedProjectCodesForMultiExport);
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.warning ?? 'Excel 檔案已下載並開啟')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? '下載失敗')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下載 Excel 檔案時發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingExcel = false);
      }
    }
  }

  Future<void> _exportPDF() async {
    if (_isExportingPdf) return; // 防止重複點擊
    
    setState(() => _isExportingPdf = true);
    try {
      final result = await ExportService.downloadPdf(_selectedProjectCodesForMultiExport);
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.warning ?? 'PDF 檔案已下載並開啟')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? '下載失敗')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下載 PDF 檔案時發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    // 顯示確認對話框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text(
            '確定要刪除使用者 "${user['display_name'] ?? user['username']}" 嗎？\n此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('刪除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final response =
          await _userService.deleteUser(user['user_id'].toString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? '使用者刪除成功'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchUsers(); // 重新載入使用者列表
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刪除失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final bool currentStatus = user['is_active'] as bool;
    final bool newStatus = !currentStatus;
    final String actionText = newStatus ? '啟用' : '禁用';

    // 顯示確認對話框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('確認$actionText帳號'),
        content: Text(
            '確定要$actionText使用者 "${user['display_name'] ?? user['username']}" 的帳號嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: newStatus ? Colors.green : Colors.red,
            ),
            child: Text(actionText),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true; // 可以考慮為單個項目設置載入狀態，而非整個列表
    });

    try {
      final response = await _userService.toggleUserStatus(
          user['user_id'].toString(), newStatus);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message'] ?? '使用者帳號已$actionText'),
          backgroundColor: Colors.green,
        ),
      );
      _fetchUsers(); // 重新載入使用者列表以更新狀態
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToAddUser() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserFormScreen(),
      ),
    ).then((result) {
      if (result == true) {
        _fetchUsers();
      }
    });
  }

  void _navigateToEditUser(Map<String, dynamic> user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserFormScreen(
          user: user,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _fetchUsers();
      }
    });
  }

  Widget _buildUserListItem(Map<String, dynamic> user) {
    final displayName = user['display_name'] as String?;
    final role = user['role'] as String?;
    final username = user['username'] as String?;
    final bool isActive = user['is_active'] as bool? ?? true; // 預設為 true，以防資料缺失
    final roleColor = _getRoleColor(role ?? '');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 4.0,
      shadowColor: roleColor.withValues(alpha:0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.0),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, roleColor.withValues(alpha:0.05)],
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [roleColor.withValues(alpha:0.8), roleColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                (role != null && role.isNotEmpty)
                    ? role[0].toUpperCase()
                    : 'U',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
          title: Text(
            username ?? '未知用戶名',
            style: TextStyle(fontWeight: FontWeight.w600, color: roleColor.withValues(alpha:0.9)),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (displayName != null && displayName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2.0, bottom: 2.0),
                  child: Text(displayName),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 2.0, bottom: 2.0),
                  child: Text('未設定顯示名稱',
                      style: TextStyle(fontStyle: FontStyle.italic)),
                ),
              Text(role ?? '未指定角色'),
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  isActive ? '狀態：啟用' : '狀態：禁用',
                  style: TextStyle(
                    color: isActive ? AppColors.forestGreen : Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (String value) {
              if (value == 'edit') {
                _navigateToEditUser(user);
              } else if (value == 'toggle_status') {
                _toggleUserStatus(user);
              } else if (value == 'delete') {
                _deleteUser(user); // 假設您已有 _deleteUser 方法
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_note),
                  title: Text('編輯使用者'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'toggle_status',
                child: ListTile(
                  leading: Icon(isActive
                      ? Icons.toggle_off_outlined
                      : Icons.toggle_on_outlined),
                  title: Text(isActive ? '禁用帳號' : '啟用帳號'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline, color: Colors.red),
                  title: Text('刪除使用者', style: TextStyle(color: Colors.red)),
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
            tooltip: '更多操作',
          ),
          isThreeLine: (displayName != null && displayName.isNotEmpty),
        ),
      ),
    );
  }

  Widget _buildUserList() {
    if (_isLoading && _users.isEmpty) {
      // Show loader only if users are not yet loaded
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.admin_panel_settings_outlined),
                label: const Text('角色權限對照'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RolePermissionsPage(),
                    ),
                  );
                },
              ),
              if (_canManageInvites)
                OutlinedButton.icon(
                  icon: const Icon(Icons.vpn_key_outlined),
                  label: const Text('邀請碼管理'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const InviteManagementPage(),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        // 搜尋和篩選區域
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜尋使用者...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              DropdownButton<String>(
                value: _selectedRole,
                items: [
                  '全部',
                  '系統管理員',
                  '業務管理員',
                  '專案管理員',
                  '調查管理員',
                  '一般使用者',
                ].map((String role) {
                  return DropdownMenuItem<String>(
                    value: role,
                    child: Text(role),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      _selectedRole = newValue;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        // 新增使用者按鈕
        // 將其移至 Scaffold 的 floatingActionButton
        // 使用者列表
        Expanded(
          child: _isLoading &&
                  _users
                      .isEmpty // Show loader in the center if still loading and no users yet
              ? const Center(child: CircularProgressIndicator())
              : _filteredUsers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          '沒有找到符合條件的使用者。\n請嘗試修改搜尋關鍵字或篩選條件。',
                          style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                              height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      // Changed from ListView.separated
                      padding: const EdgeInsets.only(
                          top: 8.0,
                          bottom: 80.0), // Add padding and space for FAB
                      itemCount: _filteredUsers.length,
                      itemBuilder: (context, index) {
                        return _buildUserListItem(_filteredUsers[index]);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildPendingApprovalUsers() {
    if (_isLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final pending = _pendingApprovalUsers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '待審核使用者',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '透過「註冊後需審核啟用」邀請碼註冊的帳號會顯示於此，啟用後方可登入。',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '重新整理',
                onPressed: _fetchUsers,
              ),
            ],
          ),
        ),
        Expanded(
          child: pending.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      '目前沒有待審核的使用者。',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 12, bottom: 24),
                  itemCount: pending.length,
                  itemBuilder: (context, index) {
                    final user = pending[index];
                    final displayName =
                        user['display_name']?.toString() ?? user['username'];
                    final username = user['username']?.toString() ?? '';
                    final role = user['role']?.toString() ?? '';
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.hourglass_top),
                        ),
                        title: Text(displayName),
                        subtitle: Text(
                          '帳號：$username\n角色：$role\n註冊時間：${_formatUserTime(user['created_at'])}',
                        ),
                        isThreeLine: true,
                        trailing: FilledButton.icon(
                          onPressed: () => _toggleUserStatus(user),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('啟用'),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case '系統管理員':
        return Colors.red;
      case '業務管理員':
        return Colors.orange;
      case '專案管理員':
        return Colors.blue;
      case '調查管理員':
        return Colors.green;
      case '一般使用者':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _buildExportOptions() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '資料匯出選項',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.list_alt),
                  label: Text(_selectedProjectCodesForMultiExport.isEmpty
                      ? '選擇專案 (預設全部)'
                      : '已選擇 ${_selectedProjectCodesForMultiExport.length} 個專案'),
                  onPressed:
                      _isLoadingProjects ? null : _showProjectMultiSelectDialog,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                if (_selectedProjectCodesForMultiExport.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                        '已選: ${_selectedProjectCodesForMultiExport.join(", ")}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey[700])),
                  ),
              ],
            )),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ElevatedButton.icon(
            icon: _isExportingExcel
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.file_download),
            label: Text(_isExportingExcel ? '匯出中...' : '匯出 Excel'),
            onPressed: (_isLoadingProjects && _projectsForExport.isEmpty) || _isExportingExcel
                ? null
                : _exportExcel,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ElevatedButton.icon(
            icon: _isExportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.picture_as_pdf),
            label: Text(_isExportingPdf ? '匯出中...' : '匯出 PDF'),
            onPressed: (_isLoadingProjects && _projectsForExport.isEmpty) || _isExportingPdf
                ? null
                : _exportPDF,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminZone() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '後端維運工具箱',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            const Text(
              '這裡提供了一系列自動化腳本，用於維護資料庫一致性、生成 AI 知識庫以及優化系統效能。請根據需求選擇執行。',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 24),

            // [T2] Admin Token 輸入框已移除：腳本執行改走 JWT（需系統管理員）

            // [Stage 0.2] 已移除「知識庫工程」「AI 內容生成」段：
            //   knowledge embeddings RAG 在 2025.11 已被 Text-to-SQL 取代，
            //   後端 routes/knowledge.js + tree_knowledge_embeddings_v2 表 (295 MB)
            //   均已刪除，本 UI 區塊隨之失效，故移除。
            // [Stage 0.3] 已移除「系統計算」段：
            //   populateSpeciesRegionScore 依賴已刪除的 tree_carbon_data 表，
            //   不再適用。

            Card(
              elevation: 2,
              child: SwitchListTile(
                secondary: Icon(
                  _researchMode ? Icons.science : Icons.fact_check,
                  color: _researchMode ? Colors.orange : Colors.teal,
                ),
                title: Text(context.tr('settings_research_mode')),
                subtitle: Text(
                  _researchMode
                      ? context.tr('settings_research_mode_on')
                      : context.tr('settings_research_mode_off'),
                ),
                value: _researchMode,
                onChanged: (v) async {
                  await SurveySettings.instance.setResearchModeEnabled(v);
                  if (!mounted) return;
                  setState(() => _researchMode = v);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        v
                            ? context.tr('settings_research_mode_enabled')
                            : context.tr('settings_research_mode_disabled'),
                      ),
                    ),
                  );
                },
              ),
            ),
            // [Research] DBH 校準資料蒐集（給研究/論文 §結果用的乾淨資料集）
            // 後端 research dataset 端點需「系統管理員」，入口同步只給系統管理員。
            if (_isSystemAdmin) ...[
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('研究資料蒐集（DBH 校準）'),
                  subtitle: const Text('現場捲尺實測周長 + 拍攝距離 + 1~3 張手機照'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AdminResearchDatasetPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
            if (_canManageInvites) ...[
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined),
                  title: const Text('待審核使用者'),
                  subtitle: Text(
                    _pendingApprovalCount > 0
                        ? '目前有 $_pendingApprovalCount 位使用者等待啟用'
                        : '審核需啟用的邀請碼註冊帳號',
                  ),
                  trailing: _pendingApprovalCount > 0
                      ? Badge(label: Text('$_pendingApprovalCount'))
                      : const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    setState(() => _selectedIndex = 1);
                  },
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.history_edu_outlined),
                  title: Text(context.tr('admin_audit_log')),
                  subtitle: Text(context.tr('admin_audit_log_sub')),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AuditLogPage(),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.password_outlined),
                  title: Text(context.tr('admin_pwd_resets')),
                  subtitle: Text(context.tr('admin_pwd_resets_sub')),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PendingPasswordResetsPage(),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectManagement() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 窄螢幕時讓標題縮排避免 RenderFlex overflow
            Expanded(
              child: Text(
                '專案管理',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            if (_canManageInvites)
              ElevatedButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('建立專案'),
                onPressed: _showCreateProjectDialog,
              ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchProjectsForExport,
              tooltip: '重新整理列表',
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '警告：刪除專案將會永久刪除該專案下的所有樹木調查資料，此操作無法復原。',
          style: TextStyle(color: Colors.red, fontSize: 14),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoadingProjects
              ? const Center(child: CircularProgressIndicator())
              : _projectsForExport.isEmpty
                  ? const Center(child: Text('目前沒有專案'))
                  : ListView.builder(
                      itemCount: _projectsForExport.length,
                      itemBuilder: (context, index) {
                        final project = _projectsForExport[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 2,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primaryContainer,
                              child: Text(project.code),
                            ),
                            title: Text(project.name),
                            subtitle: Text('區域: ${project.area ?? "無"}'),
                            trailing: _canManageInvites
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                    onPressed: () =>
                                        _confirmDeleteProject(project),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _showCreateProjectDialog() async {
    // 後端 POST /projects/add 需 area 對應到既有 project_areas.area_name。
    List<Map<String, dynamic>> areas = [];
    try {
      areas = await _projectAreaService.getProjectAreas();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入區位清單失敗：$e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (!mounted) return;
    if (areas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('尚無任何區位，請先到「專案區位」建立區位後再建立專案。')),
      );
      return;
    }

    final nameController = TextEditingController();
    String? selectedArea = areas.first['area_name']?.toString();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final nameEmpty = nameController.text.trim().isEmpty;
            return AlertDialog(
              title: const Text('建立專案'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: '專案名稱 *',
                        border: const OutlineInputBorder(),
                        errorText: nameEmpty ? '專案名稱不能為空' : null,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedArea,
                      decoration: const InputDecoration(
                        labelText: '所屬區位 *',
                        border: OutlineInputBorder(),
                      ),
                      items: areas
                          .map((a) => a['area_name']?.toString() ?? '')
                          .where((n) => n.isNotEmpty)
                          .map((n) => DropdownMenuItem<String>(
                                value: n,
                                child: Text(n),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => selectedArea = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: (nameEmpty || selectedArea == null)
                      ? null
                      : () => Navigator.pop(dialogContext, {
                            'name': nameController.text.trim(),
                            'area': selectedArea!,
                          }),
                  child: const Text('建立'),
                ),
              ],
            );
          },
        );
      },
    );
    nameController.dispose();

    if (result == null) return;
    setState(() => _isLoadingProjects = true);
    try {
      final resp =
          await _projectService.addProject(result['name']!, result['area']!);
      if (mounted) {
        if (resp['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(resp['message']?.toString() ?? '專案已建立'),
                backgroundColor: Colors.green),
          );
          _fetchProjectsForExport();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(resp['message']?.toString() ?? '建立失敗'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('建立發生錯誤：$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingProjects = false);
    }
  }

  Future<void> _confirmDeleteProject(Project project) async {
    final codeController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final codeMatches =
                codeController.text.trim() == project.code.trim();
            return AlertDialog(
              title: const Text('確認刪除專案'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '您確定要刪除專案 "${project.name}" (代碼: ${project.code}) 嗎？',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '此操作將會刪除該專案下所有的樹木資料，且無法復原。',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('請輸入專案代碼「${project.code}」以確認刪除：'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: codeController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: project.code,
                        border: const OutlineInputBorder(),
                        errorText: codeController.text.isEmpty
                            ? null
                            : codeMatches
                                ? null
                                : '代碼不符',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: codeMatches
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: const Text('確認刪除'),
                ),
              ],
            );
          },
        );
      },
    );
    codeController.dispose();

    if (confirmed == true) {
      await _deleteProject(project.code);
    }
  }

  Future<void> _deleteProject(String projectCode) async {
    setState(() => _isLoadingProjects = true);
    try {
      final response = await _projectService.deleteProject(projectCode);
      if (mounted) {
        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(response['message'] ?? '專案已刪除'),
                backgroundColor: Colors.green),
          );
          _fetchProjectsForExport(); // Refresh list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(response['message'] ?? '刪除失敗'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('刪除錯誤: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingProjects = false);
      }
    }
  }

  // [Stage 0.3] 已移除 _buildSectionTitle / _buildScriptCard / _runBackendScript：
  //   原本只服務「系統計算 (populateSpeciesRegionScore)」卡片，該卡片已移除。
  //   /api/admin/run-script 後端端點目前無前端入口，保留待未來新增腳本時再接。

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // 新增側邊欄控制按鈕
        leading: IconButton(
          icon: Icon(_isSidebarVisible ? Icons.menu_open : Icons.menu),
          color: Colors.white,
          tooltip: _isSidebarVisible ? '隱藏選單' : '顯示選單',
          onPressed: () {
            setState(() {
              _isSidebarVisible = !_isSidebarVisible;
            });
          },
        ),
        title: const Text(
          '管理後臺',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor:
            Theme.of(context).colorScheme.primary, // Ensure high contrast
        elevation: 1, // Subtle elevation
        // automaticallyImplyLeading: false, // Removed to allow custom leading
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              AuthService.logout(context);
            },
            tooltip: '登出',
          ),
        ],
      ),
      body: Container(
        child: Row(
          children: [
            // 只有當 _isSidebarVisible 為 true 時才顯示 NavigationRail
            if (_isSidebarVisible)
              // 矮螢幕時讓側欄可捲動，避免 NavigationRail 直向 overflow
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                selectedIndex: _selectedIndex,
                // extended: true, // 始終保持展開狀態，只控制整體顯示/隱藏
                minWidth: 72, // 標準寬度
                minExtendedWidth: 180, // 展開寬度
                // 這裡我們不需要 extended 屬性來控制變小，因為我們要的是整欄消失
                // 但為了美觀，我們可以讓它始終顯示文字 (extended: true) 或者維持預設
                // 根據使用者需求 "原本那樣我就覺得足夠了"，假設原本是 extended: false (只顯示 icon)
                // 還是 extended: true?
                // 使用者說 "我要的不是展開左邊的選單和變小的差別... 而是讓我沒有要選取時讓它消失"
                // 所以 NavigationRail 本身的樣式保持不變 (有 icon 和 label)
                // 我們使用 visibility 來控制
                extended: false, // 保持預設 (只有 icon，或者點擊變大? 預設 NavigationRail 行為)
                // 等等，NavigationRail 如果 extended: false，labelType 必須是 all 或 selected
                labelType: NavigationRailLabelType.all,
                onDestinationSelected: (int index) {
                  setState(() {
                    _selectedIndex = index;
                  });
                },
                backgroundColor:
                    Theme.of(context).colorScheme.surface, // Use theme color
                indicatorColor: Theme.of(context)
                    .colorScheme
                    .primaryContainer, // Use theme color
                selectedIconTheme:
                    IconThemeData(color: Theme.of(context).colorScheme.primary),
                unselectedIconTheme: IconThemeData(color: Colors.grey[600]),
                selectedLabelTextStyle:
                    TextStyle(color: Theme.of(context).colorScheme.primary),
                destinations: [
                  const NavigationRailDestination(
                    icon: Icon(Icons.people),
                    label: Text('使用者管理'),
                  ),
                  NavigationRailDestination(
                    icon: _railIcon(Icons.person_add_alt_1,
                        badge: _pendingApprovalCount),
                    label: const Text('待審核'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.file_download),
                    label: Text('資料匯出'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.build),
                    label: Text('管理員專區'),
                  ),
                  const NavigationRailDestination(
                    icon: Icon(Icons.folder_delete),
                    label: Text('專案管理'),
                  ),
                  // [T7] 專案邊界 — 專案管理員以上
                  if (_canManageProjects)
                    const NavigationRailDestination(
                      icon: Icon(Icons.map),
                      label: Text('專案邊界'),
                    ),
                  // 專案區位管理 — 專案管理員以上
                  if (_canManageProjects)
                    const NavigationRailDestination(
                      icon: Icon(Icons.location_city),
                      label: Text('專案區位'),
                    ),
                  // [T7] CSV 匯入 — 業務管理員以上
                  if (_canImportCsv)
                    const NavigationRailDestination(
                      icon: Icon(Icons.upload_file),
                      label: Text('CSV 匯入'),
                    ),
                  // [T8.2] IP 黑名單 — 系統管理員
                  if (_canManageIpBlacklist)
                    const NavigationRailDestination(
                      icon: Icon(Icons.shield),
                      label: Text('IP 黑名單'),
                    ),
                  // 系統狀態與維運 — 系統管理員
                  if (_isSystemAdmin)
                    const NavigationRailDestination(
                      icon: Icon(Icons.settings_suggest),
                      label: Text('系統'),
                    ),
                ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_isSidebarVisible)
              const VerticalDivider(thickness: 1, width: 1),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildBodyForIndex(),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton:
          _selectedIndex == 0 // Show FAB only on User Management tab
              ? FloatingActionButton.extended(
                  onPressed: _navigateToAddUser,
                  icon: const Icon(Icons.add),
                  label: const Text('新增使用者'),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                )
              : null,
    );
  }
}
