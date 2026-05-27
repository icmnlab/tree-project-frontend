import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../services/project_service.dart';
import '../../services/v3/project_boundary_coordinator.dart';

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
  final projectsResp = await ProjectService().getProjects(forceRefresh: true);
  final projects = <Map<String, dynamic>>[];
  if (projectsResp['success'] == true) {
    final raw = projectsResp['data'] ?? projectsResp['projects'];
    if (raw is List) {
      for (final p in raw) {
        if (p is Map) projects.add(Map<String, dynamic>.from(p));
      }
    }
  }

  final batchCtrl = TextEditingController(
    text: initial?.batchName ??
        '現場-${DateTime.now().month}/${DateTime.now().day}',
  );
  final areaCtrl = TextEditingController(text: initial?.projectArea ?? '');
  String? selectedCode = initial?.projectCode;
  String gpsSource = initial?.gpsSource ?? 'surveyor';

  if (!context.mounted) return null;

  return showDialog<FieldSessionSetup>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx2, setDialog) {
        Map<String, dynamic>? picked;
        if (selectedCode != null) {
          for (final p in projects) {
            final code = p['code']?.toString() ?? '';
            if (code == selectedCode || p['name']?.toString() == selectedCode) {
              picked = p;
              break;
            }
          }
        }

        return AlertDialog(
          title: Text(ctx.tr('field_setup_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  ctx.tr('field_setup_hint'),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: batchCtrl,
                  decoration: InputDecoration(
                    labelText: ctx.tr('field_setup_batch'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                if (projects.isEmpty)
                  Text(
                    ctx.tr('field_setup_no_projects'),
                    style: TextStyle(color: Colors.orange.shade800),
                  )
                else
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: ctx.tr('field_setup_project'),
                      border: const OutlineInputBorder(),
                    ),
                    value: selectedCode,
                    items: projects.map((p) {
                      final code = p['code']?.toString() ?? '';
                      final name = p['name']?.toString() ?? code;
                      return DropdownMenuItem(
                        value: code.isEmpty ? name : code,
                        child: Text(name),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setDialog(() {
                        selectedCode = v;
                        for (final p in projects) {
                          if (p['code']?.toString() == v ||
                              p['name']?.toString() == v) {
                            final a = p['area']?.toString();
                            if (a != null &&
                                a.isNotEmpty &&
                                areaCtrl.text.trim().isEmpty) {
                              areaCtrl.text = a;
                            }
                            break;
                          }
                        }
                      });
                    },
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final created = await _createProjectQuick(ctx2);
                      if (created != null) {
                        projects.add(created);
                        setDialog(() {
                          selectedCode =
                              created['code']?.toString() ?? created['name'];
                          final a = created['area']?.toString();
                          if (a != null && a.isNotEmpty) areaCtrl.text = a;
                        });
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(ctx.tr('field_setup_add_project')),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: areaCtrl,
                  decoration: InputDecoration(
                    labelText: ctx.tr('field_setup_area'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(ctx.tr('field_setup_gps_title'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(ctx.tr('field_setup_gps_hint'),
                    style: const TextStyle(fontSize: 12)),
                RadioListTile<String>(
                  dense: true,
                  title: Text(ctx.tr('field_setup_gps_surveyor')),
                  value: 'surveyor',
                  groupValue: gpsSource,
                  onChanged: (v) => setDialog(() => gpsSource = v!),
                ),
                RadioListTile<String>(
                  dense: true,
                  title: Text(ctx.tr('field_setup_gps_tree')),
                  value: 'tree',
                  groupValue: gpsSource,
                  onChanged: (v) => setDialog(() => gpsSource = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: Text(ctx.tr('cancel')),
            ),
            ElevatedButton(
              onPressed: selectedCode == null ||
                      batchCtrl.text.trim().isEmpty ||
                      areaCtrl.text.trim().isEmpty
                  ? null
                  : () {
                      final name = picked?['name']?.toString() ??
                          selectedCode!;
                      Navigator.pop(
                        ctx2,
                        FieldSessionSetup(
                          batchName: batchCtrl.text.trim(),
                          projectName: name,
                          projectCode:
                              picked?['code']?.toString() ?? selectedCode!,
                          projectArea: areaCtrl.text.trim(),
                          gpsSource: gpsSource,
                        ),
                      );
                    },
              child: Text(ctx.tr('field_setup_confirm')),
            ),
          ],
        );
      },
    ),
  );
}

Future<Map<String, dynamic>?> _createProjectQuick(BuildContext context) async {
  final nameCtrl = TextEditingController();
  final areaCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.tr('field_setup_add_project')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: ctx.tr('field_setup_project_name'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: areaCtrl,
            decoration: InputDecoration(
              labelText: ctx.tr('field_setup_area'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(ctx.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ctx.tr('field_setup_confirm')),
        ),
      ],
    ),
  );
  if (ok != true || nameCtrl.text.trim().isEmpty) return null;
  final area = areaCtrl.text.trim();
  try {
    final res = await ProjectService().addProject(
      nameCtrl.text.trim(),
      area.isEmpty ? '未分類' : area,
    );
    if (res['success'] == true && res['project'] != null) {
      final p = res['project'] as Map<String, dynamic>;
      await ProjectBoundaryCoordinator.instance.afterBoundaryMutation(
        projectName: p['name']?.toString(),
      );
      return {
        'name': p['name']?.toString(),
        'code': p['code']?.toString(),
        'area': p['area']?.toString() ?? (area.isEmpty ? '未分類' : area),
      };
    }
  } catch (_) {}
  return null;
}
