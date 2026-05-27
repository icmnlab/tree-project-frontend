import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../screens/v3/project_boundary_draw_page.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/project_area_service.dart';
import '../../services/project_service.dart';
import '../../services/v3/project_boundary_coordinator.dart';
import '../../utils/location_helper.dart';

/// 現場場次共用：專案／區位／GPS 語意／場次名稱
class FieldSessionSetup {
  final String batchName;
  final String projectName;
  final String projectCode;
  final String projectArea;
  final String gpsSource; // 'surveyor' | 'tree'

  const FieldSessionSetup({
    required this.batchName,
    required this.projectName,
    required this.projectCode,
    required this.projectArea,
    required this.gpsSource,
  });
}

/// 第一棵樹（或進入現場連線）前必填；回傳 null 表示使用者取消
Future<FieldSessionSetup?> showFieldSessionSetupDialog(
  BuildContext context, {
  FieldSessionSetup? initial,
}) async {
  if (!context.mounted) return null;

  return showDialog<FieldSessionSetup>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _FieldSessionSetupDialog(initial: initial),
  );
}

class _FieldSessionSetupDialog extends StatefulWidget {
  final FieldSessionSetup? initial;

  const _FieldSessionSetupDialog({this.initial});

  @override
  State<_FieldSessionSetupDialog> createState() =>
      _FieldSessionSetupDialogState();
}

class _FieldSessionSetupDialogState extends State<_FieldSessionSetupDialog> {
  final _batchCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _projectNameCtrl = TextEditingController();
  final _projectService = ProjectService();
  final _projectAreaService = ProjectAreaService();

  String? _projectCode;
  String _gpsSource = 'surveyor';
  bool _loadingAreas = true;
  bool _loadingProjects = false;
  bool _canAddProject = false;
  List<Map<String, dynamic>> _projectAreas = [];
  List<Map<String, dynamic>> _filteredProjects = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _batchCtrl.text = initial?.batchName ??
        '現場-${DateTime.now().month}/${DateTime.now().day}';
    _areaCtrl.text = initial?.projectArea ?? '';
    _projectNameCtrl.text = initial?.projectName ?? '';
    _projectCode = initial?.projectCode;
    _gpsSource = initial?.gpsSource ?? 'surveyor';
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _canAddProject = await AuthService.canImportCsv();
    await _loadProjectAreas();
    if (_areaCtrl.text.trim().isNotEmpty) {
      await _loadProjectsForArea(_areaCtrl.text.trim());
    }
  }

  @override
  void dispose() {
    _batchCtrl.dispose();
    _areaCtrl.dispose();
    _projectNameCtrl.dispose();
    super.dispose();
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
    } catch (_) {
      if (mounted) setState(() => _loadingAreas = false);
    }
  }

  Future<void> _loadProjectsForArea(String area) async {
    setState(() => _loadingProjects = true);
    try {
      final resp = await _projectService.getProjectsByArea(area);
      final list = <Map<String, dynamic>>[];
      if (resp['success'] == true) {
        final raw = resp['data'] ?? resp['projects'];
        if (raw is List) {
          for (final p in raw) {
            if (p is Map) list.add(Map<String, dynamic>.from(p));
          }
        }
      }
      if (mounted) {
        setState(() {
          _filteredProjects = list;
          _loadingProjects = false;
          if (_projectCode != null) {
            final stillExists = list.any(
              (p) =>
                  p['code']?.toString() == _projectCode ||
                  p['name']?.toString() == _projectCode,
            );
            if (!stillExists) {
              _projectCode = null;
              _projectNameCtrl.clear();
            }
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  void _showProjectAreaDialog() {
    final searchCtrl = TextEditingController();
    var filtered = List<Map<String, dynamic>>.from(_projectAreas);

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialog) {
          return AlertDialog(
            title: Text(ctx2.tr('field_setup_area')),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜尋或新增專案區位',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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
                  SizedBox(
                    height: 260,
                    child: _loadingAreas
                        ? const Center(child: CircularProgressIndicator())
                        : filtered.isEmpty
                            ? const Center(child: Text('尚無專案區位'))
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (_, i) {
                                  final name =
                                      filtered[i]['area_name']?.toString() ?? '';
                                  return ListTile(
                                    title: Text(name),
                                    onTap: () async {
                                      _areaCtrl.text = name;
                                      _projectNameCtrl.clear();
                                      _projectCode = null;
                                      Navigator.pop(ctx2);
                                      await _loadProjectsForArea(name);
                                      setState(() {});
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
                child: Text(ctx2.tr('cancel')),
              ),
              ElevatedButton(
                onPressed: () async {
                  final name = searchCtrl.text.trim();
                  if (name.isEmpty) return;
                  Navigator.pop(ctx2);
                  await _addProjectArea(name);
                },
                child: const Text('新增區位'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addProjectArea(String areaName) async {
    try {
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
        position ??= await getHighAccuracyPosition(
          timeout: const Duration(seconds: 3),
        );
      } catch (_) {}

      final response = await _projectAreaService.addProjectArea({
        'area_name': areaName,
        'description': '$areaName專案區位',
        'isSubmit': true,
        if (position != null) 'xCoord': position.longitude,
        if (position != null) 'yCoord': position.latitude,
      });

      if (response['success'] == true) {
        await _loadProjectAreas();
        _areaCtrl.text = areaName;
        _projectNameCtrl.clear();
        _projectCode = null;
        setState(() => _filteredProjects = []);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('專案區位新增成功')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message']?.toString() ?? '新增失敗')),
        );
        if (response['message'] == '區位已存在') {
          _areaCtrl.text = areaName;
          await _loadProjectsForArea(areaName);
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增區位失敗: $e')),
        );
      }
    }
  }

  void _showProjectDialog() {
    if (_areaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇或新增專案區位')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(ctx.tr('field_setup_project')),
            if (_canAddProject)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, color: Colors.teal),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddProjectDialog();
                },
              ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 280,
          child: _loadingProjects
              ? const Center(child: CircularProgressIndicator())
              : _filteredProjects.isEmpty
                  ? Center(
                      child: Text(
                        _canAddProject
                            ? '此區位下沒有專案，請新增專案'
                            : '此區位下沒有專案，請聯絡管理員建立',
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredProjects.length,
                      itemBuilder: (_, i) {
                        final p = _filteredProjects[i];
                        return ListTile(
                          title: Text(p['name']?.toString() ?? ''),
                          subtitle: Text('代碼: ${p['code'] ?? ''}'),
                          onTap: () {
                            _projectNameCtrl.text = p['name']?.toString() ?? '';
                            _projectCode = p['code']?.toString();
                            Navigator.pop(ctx);
                            setState(() {});
                          },
                        );
                      },
                    ),
        ),
      ),
    );
  }

  void _showAddProjectDialog() {
    if (!_canAddProject) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('新增專案需要「業務管理員」以上權限，請聯絡管理員'),
        ),
      );
      return;
    }
    if (_areaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇專案區位')),
      );
      return;
    }

    final nameCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('field_setup_add_project')),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: ctx.tr('field_setup_project_name'),
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await _addProject(name);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProject(String projectName) async {
    try {
      final response = await _projectService.addProject(
        projectName,
        _areaCtrl.text.trim(),
      );
      if (response['success'] == true && response['project'] != null) {
        final p = response['project'] as Map<String, dynamic>;
        _projectNameCtrl.text = p['name']?.toString() ?? projectName;
        _projectCode = p['code']?.toString();
        await _loadProjectsForArea(_areaCtrl.text.trim());
        await ProjectBoundaryCoordinator.instance.afterBoundaryMutation(
          projectName: _projectNameCtrl.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('專案 "$projectName" 新增成功')),
          );
          setState(() {});
          await _promptDrawBoundaryAfterCreate(
            projectName: _projectNameCtrl.text,
            projectCode: _projectCode,
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response['message']?.toString() ?? '新增專案失敗'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('新增專案錯誤: $e')),
        );
      }
    }
  }

  Future<void> _promptDrawBoundaryAfterCreate({
    required String projectName,
    String? projectCode,
  }) async {
    if (!mounted) return;
    final shouldDraw = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('要繪製專案邊界嗎？'),
        content: const Text(
          '建議現在就在地圖上畫出專案範圍，'
          '之後使用智慧模式新增樹木時可以自動匹配到此專案。\n\n'
          '可以稍後在地圖頁手動補畫，不影響專案已建立的事實。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍後再說'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.draw),
            label: const Text('立刻繪製'),
          ),
        ],
      ),
    );
    if (shouldDraw != true || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectBoundaryDrawPage(
          projectName: projectName,
          projectCode: projectCode,
        ),
      ),
    );
    await ProjectBoundaryCoordinator.instance.afterBoundaryMutation(
      projectName: projectName,
    );
  }

  bool get _canConfirm =>
      _projectCode != null &&
      _batchCtrl.text.trim().isNotEmpty &&
      _areaCtrl.text.trim().isNotEmpty &&
      _projectNameCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('field_setup_title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.tr('field_setup_hint'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _batchCtrl,
              decoration: InputDecoration(
                labelText: context.tr('field_setup_batch'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _areaCtrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: context.tr('field_setup_area'),
                hintText: '請選擇專案區位',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: _showProjectAreaDialog,
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.teal.shade50,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _projectNameCtrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: context.tr('field_setup_project'),
                hintText: '請選擇專案',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down),
                  onPressed: _showProjectDialog,
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.teal.shade50,
              ),
            ),
            if (_canAddProject)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _showAddProjectDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.tr('field_setup_add_project')),
                ),
              ),
            const SizedBox(height: 16),
            Text(context.tr('field_setup_gps_title'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(context.tr('field_setup_gps_hint'),
                style: const TextStyle(fontSize: 12)),
            RadioListTile<String>(
              dense: true,
              title: Text(context.tr('field_setup_gps_surveyor')),
              value: 'surveyor',
              groupValue: _gpsSource,
              onChanged: (v) => setState(() => _gpsSource = v!),
            ),
            RadioListTile<String>(
              dense: true,
              title: Text(context.tr('field_setup_gps_tree')),
              value: 'tree',
              groupValue: _gpsSource,
              onChanged: (v) => setState(() => _gpsSource = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: _canConfirm
              ? () {
                  Navigator.pop(
                    context,
                    FieldSessionSetup(
                      batchName: _batchCtrl.text.trim(),
                      projectName: _projectNameCtrl.text.trim(),
                      projectCode: _projectCode!,
                      projectArea: _areaCtrl.text.trim(),
                      gpsSource: _gpsSource,
                    ),
                  );
                }
              : null,
          child: Text(context.tr('field_setup_confirm')),
        ),
      ],
    );
  }
}
