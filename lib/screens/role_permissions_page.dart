import 'package:flutter/material.dart';

import '../models/role_permissions.dart';
import '../services/auth_service.dart';

/// 管理後台：各角色權限對照表
class RolePermissionsPage extends StatefulWidget {
  const RolePermissionsPage({super.key});

  @override
  State<RolePermissionsPage> createState() => _RolePermissionsPageState();
}

class _RolePermissionsPageState extends State<RolePermissionsPage> {
  String? _currentRole;

  @override
  void initState() {
    super.initState();
    _loadCurrentRole();
  }

  Future<void> _loadCurrentRole() async {
    final role = await AuthService.getUserRole();
    if (mounted) setState(() => _currentRole = role);
  }

  Color _roleColor(String role) {
    switch (role) {
      case '系統管理員':
        return Colors.deepPurple;
      case '業務管理員':
        return Colors.indigo;
      case '專案管理員':
        return Colors.teal;
      case '調查管理員':
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('角色權限對照'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.blueGrey.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '階層式 RBAC',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '數字越大權限越高；後端 API 以「最低角色」檢查，'
                    '例如要求「專案管理員」時，專案管理員、業務管理員、系統管理員皆可通過。',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                  ),
                  if (_currentRole != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      '您目前的角色：$_currentRole'
                      '（Lv.${AuthService.getRoleLevel(_currentRole!)}）',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _roleColor(_currentRole!),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...RolePermissions.entries.map((entry) {
            final isCurrent = entry.role == _currentRole;
            final color = _roleColor(entry.role);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: isCurrent ? 4 : 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: isCurrent
                    ? BorderSide(color: color, width: 2)
                    : BorderSide.none,
              ),
              child: ExpansionTile(
                initiallyExpanded: isCurrent,
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    'L${entry.level}',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text(
                  entry.role,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(entry.summary),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('可執行',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        ...entry.capabilities.map(
                          (c) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.check_circle_outline,
                                    size: 18, color: Colors.green.shade700),
                                const SizedBox(width: 8),
                                Expanded(child: Text(c, style: const TextStyle(fontSize: 13))),
                              ],
                            ),
                          ),
                        ),
                        if (entry.restrictions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('限制',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          ...entry.restrictions.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.block,
                                      size: 18, color: Colors.red.shade400),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(r,
                                          style: const TextStyle(fontSize: 13))),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
