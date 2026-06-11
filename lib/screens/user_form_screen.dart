import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/project_area_service.dart';
import '../services/project_service.dart';
import '../utils/password_validator.dart';

class UserFormScreen extends StatefulWidget {
  final Map<String, dynamic>? user;

  const UserFormScreen({Key? key, this.user}) : super(key: key);

  @override
  _UserFormScreenState createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _projectSearchController =
      TextEditingController();
  final _projectAreaService = ProjectAreaService();
  final _projectService = ProjectService();

  String _selectedRole = '一般使用者';
  List<String> _selectedProjects = [];
  List<Map<String, dynamic>> _allProjects = [];
  List<Map<String, dynamic>> _projectAreas = [];
  List<Map<String, dynamic>> _filteredProjects = [];
  String? _selectedArea;
  bool _isLoading = false;
  bool _loadingAreas = false;
  bool _loadingProjects = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    setState(() => _isLoading = true);

    if (widget.user != null) {
      _usernameController.text = widget.user!['username'] ?? '';
      _displayNameController.text = widget.user!['display_name'] ?? '';
      _selectedRole = widget.user!['role'] ?? '一般使用者';
    }

    await Future.wait([
      _loadProjects(),
      _loadProjectAreas(),
    ]);

    if (widget.user != null) {
      await _loadUserProjects();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadProjects() async {
    try {
      final response = await _projectService.getProjects(forceRefresh: true);
      if (response['success'] == true) {
        final list = ProjectService.projectListFromResponse(response);
        setState(() {
          _allProjects = List<Map<String, dynamic>>.from(list);
        });
      }
    } catch (e) {
      debugPrint('載入專案列表錯誤: $e');
    }
  }

  Future<void> _loadProjectAreas() async {
    setState(() => _loadingAreas = true);
    try {
      final areas = await _projectAreaService.getProjectAreas();
      if (mounted) {
        setState(() {
          _projectAreas = areas;
          _loadingAreas = false;
        });
      }
    } catch (e) {
      debugPrint('載入專案區位錯誤: $e');
      if (mounted) setState(() => _loadingAreas = false);
    }
  }

  Future<void> _loadProjectsForArea(String area) async {
    setState(() => _loadingProjects = true);
    try {
      final response = await _projectService.getProjectsByArea(area);
      final list = ProjectService.projectListFromResponse(response);
      if (mounted) {
        setState(() {
          _filteredProjects = List<Map<String, dynamic>>.from(list);
          _loadingProjects = false;
        });
      }
    } catch (e) {
      debugPrint('載入區內專案錯誤: $e');
      if (mounted) {
        setState(() {
          _filteredProjects = _allProjects
              .where((p) => (p['area'] ?? '').toString() == area)
              .toList();
          _loadingProjects = false;
        });
      }
    }
  }

  Future<void> _loadUserProjects() async {
    try {
      if (widget.user == null) return;
      final response =
          await ApiService.get('users/${widget.user!['user_id']}/projects');

      if (response['success'] == true && response['projects'] != null) {
        setState(() {
          _selectedProjects =
              List<Map<String, dynamic>>.from(response['projects'])
                  .map((project) => project['專案代碼'].toString())
                  .toList();
        });
      }
    } catch (e) {
      debugPrint('載入使用者專案錯誤: $e');
      if (widget.user?['associated_projects'] != null) {
        setState(() {
          _selectedProjects = widget.user!['associated_projects']
              .toString()
              .split(',')
              .where((project) => project.isNotEmpty)
              .toList();
        });
      }
    }
  }

  List<Map<String, dynamic>> get _visibleProjects {
    final q = _projectSearchController.text.trim().toLowerCase();
    if (q.isEmpty) return _filteredProjects;
    return _filteredProjects.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final code = (p['code'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  Future<void> _pickArea() async {
    final searchCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        List<Map<String, dynamic>> filtered = List.from(_projectAreas);
        return StatefulBuilder(
          builder: (ctx2, setDialog) {
            return AlertDialog(
              title: const Text('選擇專案'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: '搜尋專案名稱',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setDialog(() {
                          filtered = v.isEmpty
                              ? List.from(_projectAreas)
                              : _projectAreas
                                  .where((a) => (a['area_name'] ?? '')
                                      .toString()
                                      .toLowerCase()
                                      .contains(v.toLowerCase()))
                                  .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: (MediaQuery.of(ctx2).size.height * 0.35)
                            .clamp(120.0, 260.0),
                      ),
                      child: _loadingAreas
                          ? const Center(child: CircularProgressIndicator())
                          : filtered.isEmpty
                              ? const Center(child: Text('無符合的專案'))
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) {
                                    final name =
                                        filtered[i]['area_name']?.toString() ??
                                            '';
                                    return ListTile(
                                      title: Text(name),
                                      trailing: _selectedArea == name
                                          ? const Icon(Icons.check,
                                              color: Colors.teal)
                                          : null,
                                      onTap: () async {
                                        Navigator.pop(ctx2);
                                        setState(() {
                                          _selectedArea = name;
                                          _projectSearchController.clear();
                                        });
                                        await _loadProjectsForArea(name);
                                      },
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx2),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Map<String, dynamic>? _projectByCode(String code) {
    for (final p in _allProjects) {
      if ((p['code'] ?? '').toString() == code) return p;
    }
    return null;
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final Map<String, dynamic> userData = {
        'username': _usernameController.text,
        'display_name': _displayNameController.text,
        'role': _selectedRole,
      };

      if (_passwordController.text.isNotEmpty) {
        userData['password'] = _passwordController.text;
      }

      Map<String, dynamic> response;
      if (widget.user != null) {
        response =
            await ApiService.put('users/${widget.user!['user_id']}', userData);
      } else {
        response = await ApiService.post('users', userData);
      }

      if (!response['success']) {
        throw Exception('更新使用者資料失敗：${response['message']}');
      }

      if (widget.user != null) {
        final projectResponse = await ApiService.put(
            'users/${widget.user!['user_id']}/projects',
            {'projects': _selectedProjects});

        if (!projectResponse['success']) {
          throw Exception('更新區關聯失敗：${projectResponse['message']}');
        }
      } else if (response['userId'] != null) {
        final userId = response['userId'];
        final projectResponse = await ApiService.put(
            'users/$userId/projects', {'projects': _selectedProjects});

        if (!projectResponse['success']) {
          throw Exception('設定區關聯失敗：${projectResponse['message']}');
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('使用者資料更新成功'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('發生錯誤：$e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildProjectAssignmentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '關聯區',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '已選 ${_selectedProjects.length} 個區',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '先選「專案」，再勾選底下的「區」。與現場設定語意一致。',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loadingAreas ? null : _pickArea,
          icon: const Icon(Icons.folder_outlined),
          label: Text(
            _selectedArea == null || _selectedArea!.isEmpty
                ? '選擇專案'
                : '專案：$_selectedArea',
          ),
        ),
        if (_selectedProjects.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _selectedProjects.map((code) {
              final p = _projectByCode(code);
              final label = p != null
                  ? '${p['area'] ?? ''} · ${p['name']} ($code)'
                  : code;
              return InputChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                onDeleted: () {
                  setState(() => _selectedProjects.remove(code));
                },
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        if (_selectedArea == null || _selectedArea!.isEmpty)
          const Text('請先選擇專案，再勾選要授權的區。')
        else if (_loadingProjects)
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(),
          ))
        else if (_filteredProjects.isEmpty)
          Text('「$_selectedArea」下尚無可授權的區。')
        else ...[
          TextField(
            controller: _projectSearchController,
            decoration: const InputDecoration(
              labelText: '搜尋區名稱或代碼',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          ..._visibleProjects.map((project) {
            final projectCode = project['code']?.toString() ?? '';
            if (projectCode.isEmpty) return const SizedBox.shrink();
            return CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${project['name']} ($projectCode)'),
              subtitle: Text(_selectedArea ?? ''),
              value: _selectedProjects.contains(projectCode),
              onChanged: (bool? value) {
                setState(() {
                  if (value == true) {
                    if (!_selectedProjects.contains(projectCode)) {
                      _selectedProjects.add(projectCode);
                    }
                  } else {
                    _selectedProjects.remove(projectCode);
                  }
                });
              },
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user != null ? '編輯使用者' : '新增使用者'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '帳號',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '請輸入帳號';
                        }
                        return null;
                      },
                      enabled: widget.user == null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: widget.user != null ? '密碼（留空表示不修改）' : '密碼',
                        border: const OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (widget.user == null &&
                            (value == null || value.isEmpty)) {
                          return '請輸入密碼';
                        }
                        if (value != null && value.isNotEmpty) {
                          return validatePasswordStrength(value,
                              required: widget.user == null);
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: '顯示名稱',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        labelText: '角色',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '系統管理員', child: Text('系統管理員')),
                        DropdownMenuItem(value: '業務管理員', child: Text('業務管理員')),
                        DropdownMenuItem(value: '專案管理員', child: Text('專案管理員')),
                        DropdownMenuItem(value: '調查管理員', child: Text('調查管理員')),
                        DropdownMenuItem(value: '一般使用者', child: Text('一般使用者')),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() => _selectedRole = newValue);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildProjectAssignmentSection(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitForm,
                        child: Text(widget.user != null ? '更新' : '新增'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _projectSearchController.dispose();
    super.dispose();
  }
}
