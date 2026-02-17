import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'constants/colors.dart';
// import 'package:provider/provider.dart'; // Unused
import 'screens/api_key_management_screen.dart';
import 'screens/user_form_screen.dart';
import 'services/user_service.dart';
import 'services/project_service.dart';
import 'services/admin_service.dart';
import 'models/project.dart';
import 'config/app_config.dart'; // Import AppConfig
import 'screens/v3/project_boundary_draw_page.dart'; // V3 專案邊界繪製
import 'screens/csv_import_page.dart'; // [Phase C] CSV 匯入頁面
import '../services/api_service.dart';
import '../services/auth_service.dart';

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

  List<Project> _projectsForExport = [];
  List<String> _selectedProjectCodesForMultiExport = []; // 用於儲存多選的專案代碼
  bool _isLoadingProjects = false;
  bool _isExportingExcel = false;
  bool _isExportingPdf = false;
  final TextEditingController _tokenController =
      TextEditingController(); // Create controller as a state variable

  // Services
  final UserService _userService = UserService();
  final ProjectService _projectService = ProjectService();
  final AdminService _adminService = AdminService();

  @override
  void dispose() {
    _tokenController.dispose(); // Dispose of the controller
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchProjectsForExport();
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

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final users = await _userService.fetchUsers();
      setState(() {
        _users = users.map((user) {
          // [FIX] Backend now guarantees boolean, but keeping robust parsing logic just in case
          // Handle various types: bool, int (0/1), or string ("true"/"false")
          bool isActive = true;
          if (user['is_active'] is bool) {
            isActive = user['is_active'];
          } else if (user['is_active'] is int) {
            isActive = user['is_active'] == 1;
          } else if (user['is_active'] is String) {
            isActive = user['is_active'].toString().toLowerCase() == 'true';
          }
          return {...user, 'is_active': isActive};
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('無法載入使用者資料: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchProjectsForExport() async {
    setState(() {
      _isLoadingProjects = true;
      _selectedProjectCodesForMultiExport.clear(); // 清空已選
    });
    try {
      final projectsResponse = await _projectService.getProjects();
      if (projectsResponse['success'] == true &&
          projectsResponse['data'] != null) {
        setState(() {
          _projectsForExport = (projectsResponse['data'] as List)
              .map((json) => Project.fromJson(json))
              .toList();
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(projectsResponse['message'] ?? '無法載入專案列表')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入專案列表發生錯誤: $e')),
        );
      }
    } finally {
      setState(() {
        _isLoadingProjects = false;
      });
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

  Future<void> _backupDatabase() async {
    try {
      final response = await _adminService.backupDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? '資料庫備份成功')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $e')),
        );
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
      shadowColor: roleColor.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14.0),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, roleColor.withOpacity(0.05)],
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [roleColor.withOpacity(0.8), roleColor],
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
            style: TextStyle(fontWeight: FontWeight.w600, color: roleColor.withOpacity(0.9)),
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

  Widget _buildBackupOptions() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '資料備份與還原',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        const Text(
          '備份功能會將資料庫中的所有資料匯出為 SQL 檔案，\n'
          '還原功能可以從備份檔案中恢復資料。\n'
          '請定期備份您的資料以防資料遺失。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          icon: const Icon(Icons.backup),
          label: const Text('備份資料庫'),
          onPressed: _backupDatabase,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.restore),
          label: const Text('還原資料庫'),
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('還原資料庫'),
                content: const Text(
                  '還原功能將會覆蓋現有資料庫內容，此操作無法復原。\n\n'
                  '目前此功能需要在伺服器端手動操作（透過管理員 API），'
                  '請聯繫系統管理員進行還原。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('了解'),
                  ),
                ],
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildApiKeyOptions() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'API 密鑰管理',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          const Text(
            'API 密鑰用於授權第三方應用程式訪問系統 API。\n'
            '您可以創建、查看和刪除 API 密鑰。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.key),
            label: const Text('管理 API 密鑰'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ApiKeyManagementScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemSettings() {
    final appConfig = AppConfig();
    bool isStaging = appConfig.environment == Environment.staging;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '系統開發設定',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  title: const Text('啟用測試環境 (Staging)'),
                  subtitle: Text(
                      '當前 API 環境: ${isStaging ? "測試 (Staging)" : "正式 (Production)"}\n${appConfig.baseUrl}'),
                  value: isStaging,
                  onChanged: (bool value) {
                    // The toggle function now handles the dialog and restart
                    appConfig.toggleEnvironment(context);
                  },
                  secondary: Icon(
                    isStaging ? Icons.developer_mode : Icons.public,
                    color: isStaging ? Colors.orange : Colors.green,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '切換環境後，應用程式將會提示您重新啟動以載入新的伺服器設定。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
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

            // Admin Token 輸入框
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _tokenController,
                  decoration: const InputDecoration(
                    labelText: 'Admin API Token (執行腳本所需)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key),
                    helperText: '為了安全，所有維運操作都需要驗證管理員 Token。',
                    helperMaxLines: 2, // 確保提示文字不會被截斷
                  ),
                  obscureText: true,
                ),
              ),
            ),
            const SizedBox(height: 24),

            _buildSectionTitle('知識庫工程 (Knowledge Engineering)'),
            const SizedBox(height: 16),
            // 強制垂直排列，每個腳本一張卡片，佔滿寬度
            Column(
              children: [
                _buildScriptCard(
                  title: '更新調查數據知識庫',
                  description: '將最新的「實地樹木調查記錄」同步至 AI 知識庫，讓 AI 能回答關於特定樹木的問題。',
                  icon: Icons.sync,
                  color: Colors.blue,
                  scriptName: 'populate_knowledge_from_survey',
                  tokenController: _tokenController,
                ),
                const SizedBox(height: 16),
                _buildScriptCard(
                  title: '更新樹種科學數據庫',
                  description: '將硬性科學指標（如碳吸存量、耐旱性）轉化為 AI 可理解的知識片段。',
                  icon: Icons.science,
                  color: Colors.teal,
                  scriptName: 'generateEmbeddings',
                  tokenController: _tokenController,
                ),
              ],
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('AI 內容生成 (Content Generation)'),
            const SizedBox(height: 16),
            Column(
              children: [
                _buildScriptCard(
                  title: 'AI 撰寫樹種深度文章',
                  description: '使用 LLM 為每個樹種自動撰寫詳細的百科全書式介紹文章。(僅針對新樹種生成，耗時較長)',
                  icon: Icons.auto_awesome,
                  color: Colors.purple,
                  scriptName: 'generate_species_knowledge',
                  tokenController: _tokenController,
                ),
                const SizedBox(height: 16),
                _buildScriptCard(
                  title: '擴充樹種同義詞索引',
                  description: '自動補充樹種的學名、別名與多語言名稱，提升搜尋準確度。',
                  icon: Icons.translate,
                  color: Colors.indigo,
                  scriptName: 'enrich_species_synonyms',
                  tokenController: _tokenController,
                ),
              ],
            ),

            const SizedBox(height: 32),
            _buildSectionTitle('系統計算 (System Calculation)'),
            const SizedBox(height: 16),
            Column(
              children: [
                _buildScriptCard(
                  title: '重算樹種區域評分',
                  description: '根據樹種特性，重新計算所有樹種在台灣各區域的適植性評分。',
                  icon: Icons.calculate,
                  color: Colors.orange,
                  scriptName: 'populateSpeciesRegionScore',
                  tokenController: _tokenController,
                ),
              ],
            ),
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
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '專案管理',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
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
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.red),
                              onPressed: () => _confirmDeleteProject(project),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteProject(Project project) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除專案'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('您確定要刪除專案 "${project.name}" (代碼: ${project.code}) 嗎？'),
            const SizedBox(height: 12),
            const Text(
              '此操作將會刪除該專案下所有的樹木資料！',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('請輸入專案代碼以確認刪除：'),
            const SizedBox(height: 8),
            // Note: In a real app, we might add a text field here for double confirmation
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認刪除'),
          ),
        ],
      ),
    );

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

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 24,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          // 使用 Expanded 防止標題過長溢出
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScriptCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required String scriptName,
    required TextEditingController tokenController,
    // width 參數已移除
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _runBackendScript(scriptName, tokenController.text),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 28),
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
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _runBackendScript(scriptName, tokenController.text),
                        icon: Icon(Icons.play_circle_outline,
                            size: 18, color: color),
                        label: Text('執行腳本', style: TextStyle(color: color)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: color.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runBackendScript(String scriptName, String token) async {
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請輸入 Admin API Token')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/admin/run-script'),
        headers: {
          'Content-Type': 'application/json',
          'x-admin-token': token,
        },
        body: jsonEncode({'scriptName': scriptName}),
      );

      final data = jsonDecode(response.body);
      if (mounted) {
        if (data['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('腳本執行成功: ${data['message']}')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('腳本執行失敗: ${data['message']}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Try to show the raw body if json decode fails, truncated
        String errorMessage = e.toString();
        if (e is FormatException) {
          errorMessage = "伺服器回應格式錯誤 (非 JSON)";
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('發生錯誤: $errorMessage')),
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
              NavigationRail(
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
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.people),
                    label: Text('使用者管理'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.file_download),
                    label: Text('資料匯出'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.backup),
                    label: Text('資料備份'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.key),
                    label: Text('API 密鑰'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('系統設定'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.build),
                    label: Text('管理員專區'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.folder_delete),
                    label: Text('專案管理'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.map),
                    label: Text('專案邊界'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.upload_file),
                    label: Text('CSV 匯入'),
                  ),
                ],
              ),
            if (_isSidebarVisible)
              const VerticalDivider(thickness: 1, width: 1),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _selectedIndex == 0
                    ? _buildUserList()
                    : _selectedIndex == 1
                        ? _buildExportOptions()
                        : _selectedIndex == 2
                            ? _buildBackupOptions()
                            : _selectedIndex == 3
                                ? _buildApiKeyOptions()
                                : _selectedIndex == 4
                                    ? _buildSystemSettings()
                                    : _selectedIndex == 5
                                        ? _buildAdminZone()
                                        : _selectedIndex == 6
                                            ? _buildProjectManagement()
                                            : _selectedIndex == 7
                                                ? const ProjectBoundaryDrawPage()
                                                : const CsvImportPage(),
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
