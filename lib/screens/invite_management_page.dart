import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/invite_service.dart';
import '../services/project_service.dart';
import '../models/project.dart';

/// 邀請碼管理（業務管理員以上）
class InviteManagementPage extends StatefulWidget {
  const InviteManagementPage({super.key});

  @override
  State<InviteManagementPage> createState() => _InviteManagementPageState();
}

class _InviteManagementPageState extends State<InviteManagementPage> {
  final InviteService _inviteService = InviteService();
  final ProjectService _projectService = ProjectService();
  List<Map<String, dynamic>> _invites = [];
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _inviteService.listInvites(),
        _projectService.getProjects(forceRefresh: true),
      ]);
      if (!mounted) return;
      setState(() {
        _invites = results[0] as List<Map<String, dynamic>>;
        final projResp = results[1] as Map<String, dynamic>;
        final raw = projResp['projects'] as List? ?? [];
        _projects = raw
            .map((e) => Project.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showCreateDialog() async {
    String role = '調查管理員';
    int maxUses = 1;
    int days = 7;
    bool requiresApproval = true;
    final selectedCodes = <String>{};
    final locationsCtrl = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('建立邀請碼'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(role),
                  initialValue: role,
                  decoration: const InputDecoration(labelText: '內建角色'),
                  items: const [
                    '一般使用者',
                    '調查管理員',
                    '專案管理員',
                  ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setDialog(() => role = v ?? role),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: '1',
                  decoration: const InputDecoration(
                    labelText: '可用次數（建議 1 = 一次性）',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => maxUses = int.tryParse(v) ?? 1,
                ),
                TextFormField(
                  initialValue: '7',
                  decoration: const InputDecoration(labelText: '有效天數'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => days = int.tryParse(v) ?? 7,
                ),
                SwitchListTile(
                  title: const Text('註冊後需審核啟用'),
                  subtitle: const Text('帳號 is_active=false，管理員於使用者列表啟用'),
                  value: requiresApproval,
                  onChanged: (v) => setDialog(() => requiresApproval = v),
                ),
                const Text('綁定專案（可多選）', style: TextStyle(fontWeight: FontWeight.w600)),
                ..._projects.map((p) {
                  final code = p.code;
                  return CheckboxListTile(
                    dense: true,
                    title: Text('${p.name} ($code)'),
                    value: selectedCodes.contains(code),
                    onChanged: (checked) {
                      setDialog(() {
                        if (checked == true) {
                          selectedCodes.add(code);
                        } else {
                          selectedCodes.remove(code);
                        }
                      });
                    },
                  );
                }),
                TextField(
                  controller: locationsCtrl,
                  decoration: const InputDecoration(
                    labelText: '預設區位（逗號分隔，選填）',
                    hintText: '例如：A區, B區',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('建立'),
            ),
          ],
        ),
      ),
    );

    final locationText = locationsCtrl.text;
    locationsCtrl.dispose();
    if (created != true || !mounted) return;

    try {
      final locations = locationText
          .split(RegExp(r'[,，]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final invite = await _inviteService.createInvite(
        role: role,
        maxUses: maxUses.clamp(1, 100),
        expiresInDays: days.clamp(1, 90),
        projectCodes: selectedCodes.toList(),
        projectLocations: locations,
        requiresApproval: requiresApproval,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('邀請碼已建立'),
          content: SelectableText(invite['code']?.toString() ?? ''),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: invite['code']?.toString() ?? ''),
                );
                Navigator.pop(ctx);
              },
              child: const Text('複製'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
          ],
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('邀請碼管理'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('建立邀請碼'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _invites.isEmpty
              ? const Center(child: Text('尚無邀請碼'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _invites.length,
                  itemBuilder: (context, index) {
                    final inv = _invites[index];
                    final code = inv['code']?.toString() ?? '';
                    final active = inv['is_active'] == true;
                    final uses = '${inv['use_count'] ?? 0}/${inv['max_uses'] ?? 1}';
                    final codes = inv['project_codes'];
                    final proj = codes is List ? codes.join(', ') : '';
                    return Card(
                      child: ListTile(
                        title: Text(code, style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(
                          '角色：${inv['role']}\n'
                          '使用：$uses · 過期：${inv['expires_at'] ?? '—'}\n'
                          '${proj.isNotEmpty ? '專案：$proj\n' : ''}'
                          '${inv['requires_approval'] == true ? '需審核啟用 · ' : ''}'
                          '${active ? '有效' : '已停用'}',
                        ),
                        isThreeLine: true,
                        trailing: active
                            ? IconButton(
                                icon: const Icon(Icons.block),
                                tooltip: '停用',
                                onPressed: () async {
                                  final id = inv['invite_id'];
                                  if (id == null) return;
                                  await _inviteService.deactivateInvite(id as int);
                                  await _load();
                                },
                              )
                            : null,
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已複製邀請碼')),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
