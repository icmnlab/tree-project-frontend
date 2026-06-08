import 'package:flutter/material.dart';
// dart:convert, provider, auth_service imports removed - unused
import '../services/api_service.dart';
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
  String _selectedRole = '一般使用者';
  List<String> _selectedProjects = [];
  List<Map<String, dynamic>> _availableProjects = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  Future<void> _initializeUserData() async {
    setState(() {
      _isLoading = true;
    });

    // 設置基本使用者資料
    if (widget.user != null) {
      _usernameController.text = widget.user!['username'] ?? '';
      _displayNameController.text = widget.user!['display_name'] ?? '';
      _selectedRole = widget.user!['role'] ?? '一般使用者';
    }

    // 載入所有可用專案
    await _loadProjects();

    // 如果是編輯模式，載入使用者的關聯專案
    if (widget.user != null) {
      await _loadUserProjects();
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadProjects() async {
    try {
      final response = await ApiService.get('projects');

      if (response['success'] == true && response['data'] != null) {
        setState(() {
          _availableProjects =
              List<Map<String, dynamic>>.from(response['data']);
        });
      }
    } catch (e) {
      print('載入專案列表錯誤: $e');
    }
  }

  Future<void> _loadUserProjects() async {
    try {
      if (widget.user != null) {
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
      }
    } catch (e) {
      print('載入使用者專案錯誤: $e');
      // 如果 API 呼叫失敗，嘗試從 user 物件中取得關聯專案
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

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. 首先更新使用者基本資料
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

      // 2. 然後更新專案關聯
      if (widget.user != null) {
        final projectResponse = await ApiService.put(
            'users/${widget.user!['user_id']}/projects',
            {'projects': _selectedProjects});

        if (!projectResponse['success']) {
          throw Exception('更新專案關聯失敗：${projectResponse['message']}');
        }
      }

      // 3. 如果是新增使用者，需要在創建後立即更新專案關聯
      else if (response['userId'] != null) {
        final userId = response['userId'];
        final projectResponse = await ApiService.put(
            'users/$userId/projects', {'projects': _selectedProjects});

        if (!projectResponse['success']) {
          throw Exception('設定專案關聯失敗：${projectResponse['message']}');
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
                          setState(() {
                            _selectedRole = newValue;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text('關聯專案：'),
                    const SizedBox(height: 8),
                    if (_availableProjects.isEmpty)
                      const Text('無可用專案')
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _availableProjects.length,
                        itemBuilder: (context, index) {
                          final project = _availableProjects[index];
                          final projectCode = project['code']?.toString() ?? '';
                          return CheckboxListTile(
                            title:
                                Text('${project['name']} (${project['code']})'),
                            subtitle: Text(project['area']?.toString() ?? ''),
                            value: _selectedProjects.contains(projectCode),
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  _selectedProjects.add(projectCode);
                                } else {
                                  _selectedProjects.remove(projectCode);
                                }
                              });
                            },
                          );
                        },
                      ),
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
    super.dispose();
  }
}
