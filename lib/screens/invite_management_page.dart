import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/invite_service.dart';
import '../services/project_service.dart';
import '../services/project_area_service.dart';
import '../services/v3/project_boundary_coordinator.dart';
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
  final ProjectAreaService _projectAreaService = ProjectAreaService();
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
    final selectedAreas = <String>{};
    String projectQuery = '';

    Set<String> areasForSelection() {
      final areas = <String>{};
      for (final p in _projects) {
        if (!selectedCodes.contains(p.code)) continue;
        final a = p.area?.trim();
        if (a != null && a.isNotEmpty) areas.add(a);
      }
      return areas;
    }

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
                  subtitle: const Text('帳號待審核，管理員於「待審核」專區啟用'),
                  value: requiresApproval,
                  onChanged: (v) => setDialog(() => requiresApproval = v),
                ),
                Text(
                  '綁定專案（可多選）${selectedCodes.isNotEmpty ? '：已選 ${selectedCodes.length} 個' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final createdProj = await _quickCreateProject(ctx);
                      if (createdProj != null) {
                        setDialog(() {
                          _projects.add(createdProj);
                          selectedCodes.add(createdProj.code);
                          final a = createdProj.area?.trim();
                          if (a != null && a.isNotEmpty) selectedAreas.add(a);
                        });
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('新增專案'),
                  ),
                ),
                // [UX] 專案多時可搜尋，清單限高可捲動（原本 40+ 專案攤平整個對話框）
                TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: '搜尋專案名稱或代碼',
                  ),
                  onChanged: (v) => setDialog(() => projectQuery = v.trim()),
                ),
                const SizedBox(height: 4),
                Builder(builder: (_) {
                  final q = projectQuery.toLowerCase();
                  final filtered = q.isEmpty
                      ? _projects
                      : _projects
                          .where((p) =>
                              p.name.toLowerCase().contains(q) ||
                              p.code.toLowerCase().contains(q))
                          .toList();
                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('沒有符合的專案',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final p = filtered[i];
                        final code = p.code;
                        return CheckboxListTile(
                          dense: true,
                          title: Text('${p.name} ($code)'),
                          subtitle: p.area != null && p.area!.isNotEmpty
                              ? Text('預設區位：${p.area}')
                              : null,
                          value: selectedCodes.contains(code),
                          onChanged: (checked) {
                            setDialog(() {
                              if (checked == true) {
                                selectedCodes.add(code);
                                final a = p.area?.trim();
                                if (a != null && a.isNotEmpty) {
                                  selectedAreas.add(a);
                                }
                              } else {
                                selectedCodes.remove(code);
                                final a = p.area?.trim();
                                if (a != null) selectedAreas.remove(a);
                              }
                            });
                          },
                        );
                      },
                    ),
                  );
                }),
                // [UX] 區位由勾選的專案自動帶出，僅作管理紀錄用標籤；
                // 原本另有一個「逗號分隔」文字欄與 chips 雙向同步，混淆且易誤觸，已移除。
                if (areasForSelection().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('專案區位（自動帶出，僅供管理紀錄）',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Text(
                    '註冊權限以上方「綁定專案」為準；區位僅記錄供管理員對照。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 0,
                    children: areasForSelection().map((area) {
                      final picked = selectedAreas.contains(area);
                      return FilterChip(
                        label: Text(area),
                        selected: picked,
                        onSelected: (v) {
                          setDialog(() {
                            if (v) {
                              selectedAreas.add(area);
                            } else {
                              selectedAreas.remove(area);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
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

    if (created != true || !mounted) return;

    try {
      final locations = selectedAreas.toList();
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

  Future<Project?> _quickCreateProject(BuildContext context) async {
    final nameCtrl = TextEditingController();
    List<Map<String, dynamic>> areas = [];
    String? selectedArea;
    bool loadingAreas = true;

    Future<void> loadAreas(StateSetter setDialog) async {
      setDialog(() => loadingAreas = true);
      try {
        areas = await _projectAreaService.getProjectAreas();
      } catch (_) {
        areas = [];
      }
      if (selectedArea == null && areas.isNotEmpty) {
        selectedArea = areas.first['area_name']?.toString();
      }
      setDialog(() => loadingAreas = false);
    }

    Future<void> addNewArea(StateSetter setDialog) async {
      final areaCtrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('新增專案區位'),
          content: TextField(
            controller: areaCtrl,
            decoration: const InputDecoration(
              labelText: '區位名稱',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('建立'),
            ),
          ],
        ),
      );
      if (ok != true || areaCtrl.text.trim().isEmpty) return;
      final areaName = areaCtrl.text.trim();
      try {
        final res = await _projectAreaService.addProjectArea({
          'area_name': areaName,
          'description': '$areaName專案區位',
        });
        if (res['success'] == true) {
          await loadAreas(setDialog);
          setDialog(() => selectedArea = areaName);
        }
      } catch (_) {}
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          if (loadingAreas && areas.isEmpty) {
            loadAreas(setDialog);
          }
          return AlertDialog(
            title: const Text('新增專案'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '專案名稱',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '專案區位',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => addNewArea(setDialog),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('新增區位'),
                      ),
                    ],
                  ),
                  if (loadingAreas)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (areas.isEmpty)
                    const Text('尚無區位，請先新增區位')
                  else
                    DropdownButtonFormField<String>(
                      value: selectedArea,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: '選擇既有區位',
                      ),
                      items: areas
                          .map((a) => a['area_name']?.toString() ?? '')
                          .where((n) => n.isNotEmpty)
                          .map(
                            (n) => DropdownMenuItem(value: n, child: Text(n)),
                          )
                          .toList(),
                      onChanged: (v) => setDialog(() => selectedArea = v),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty ||
                      selectedArea == null ||
                      selectedArea!.trim().isEmpty) {
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('建立'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true ||
        nameCtrl.text.trim().isEmpty ||
        selectedArea == null ||
        selectedArea!.trim().isEmpty) {
      return null;
    }

    try {
      final res = await _projectService.addProject(
        nameCtrl.text.trim(),
        selectedArea!.trim(),
      );
      if (res['success'] == true && res['project'] != null) {
        final p = Project.fromJson(
          Map<String, dynamic>.from(res['project'] as Map),
        );
        await ProjectBoundaryCoordinator.instance.afterBoundaryMutation(
          projectName: p.name,
        );
        return p;
      }
    } catch (_) {}
    return null;
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
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('停用邀請碼'),
                                      content: Text('確定停用 $code？已發出的碼將無法再註冊。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text('取消'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text('停用'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (ok != true || !mounted) return;
                                  try {
                                    final inviteId = id is int
                                        ? id
                                        : (id as num).toInt();
                                    await _inviteService
                                        .deactivateInvite(inviteId);
                                    await _load();
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('停用失敗: $e'),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                  }
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
