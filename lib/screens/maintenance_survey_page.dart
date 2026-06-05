import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/maintenance_target.dart';
import '../services/tree_service.dart';
import '../utils/tree_id_display.dart';
import '../widgets/ble/ble_device_scanner.dart';
import '../widgets/field/field_session_setup.dart';
import 'ble_live_session_page.dart';
import '../services/locale_service.dart';

/// 維護量測：選區 → 樹清單 → 選樹重測或新增樹木
class MaintenanceSurveyPage extends StatefulWidget {
  const MaintenanceSurveyPage({super.key});

  @override
  State<MaintenanceSurveyPage> createState() => _MaintenanceSurveyPageState();
}

class _MaintenanceSurveyPageState extends State<MaintenanceSurveyPage> {
  final _treeService = TreeService();
  FieldSessionSetup? _setup;
  MaintenanceTarget? _targetTree;
  BluetoothDevice? _selectedDevice;

  bool _loadingTrees = false;
  String? _loadError;
  List<Map<String, dynamic>> _trees = [];
  String _search = '';
  int _step = 0; // 0=list 1=ble

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSetup());
  }

  Future<void> _ensureSetup() async {
    if (_setup != null) {
      await _loadTrees();
      return;
    }
    final setup = await showFieldSessionSetupDialog(context);
    if (!mounted) return;
    if (setup == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _setup = setup);
    await _loadTrees();
  }

  Future<void> _loadTrees() async {
    final setup = _setup;
    if (setup == null) return;
    setState(() {
      _loadingTrees = true;
      _loadError = null;
    });
    try {
      final res = await _treeService.getAllTrees(
        projectCode: setup.projectCode,
        search: _search.trim().isEmpty ? null : _search.trim(),
        limit: 500,
      );
      if (!mounted) return;
      final raw = res['data'] ?? res['trees'] ?? res;
      List<Map<String, dynamic>> list = [];
      if (raw is List) {
        list = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      final area = setup.projectArea.trim();
      if (area.isNotEmpty) {
        list = list.where((t) {
          final loc = (t['project_location'] ?? t['專案區位'] ?? '')
              .toString()
              .trim();
          return loc == area || loc.contains(area) || area.contains(loc);
        }).toList();
      }
      setState(() {
        _trees = list;
        _loadingTrees = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingTrees = false;
      });
    }
  }

  void _startBle({MaintenanceTarget? target}) {
    setState(() {
      _targetTree = target;
      _selectedDevice = null;
      _step = 1;
    });
  }

  Future<void> _openLiveSession() async {
    if (_selectedDevice == null || _setup == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BleLiveSessionPage(
          initialDevice: _selectedDevice,
          initialSessionSetup: _setup,
          maintenanceTarget: _targetTree,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _step = 0);
    await _loadTrees();
  }

  int? _treeId(Map<String, dynamic> t) {
    final v = t['id'] ?? t['ID'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('maintain_title')),
        backgroundColor: Colors.orange.shade800,
        foregroundColor: Colors.white,
      ),
      body: _step == 0 ? _buildListStep() : _buildBleStep(),
    );
  }

  Widget _buildListStep() {
    final setup = _setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (setup != null)
          Material(
            color: Colors.orange.shade50,
            child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text('${setup.projectName} · ${setup.projectArea}'),
              subtitle: Text(setup.projectCode),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () async {
                  final s = await showFieldSessionSetupDialog(
                    context,
                    initial: setup,
                  );
                  if (s != null && mounted) {
                    setState(() => _setup = s);
                    await _loadTrees();
                  }
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            decoration: InputDecoration(
              hintText: context.tr('maintain_search_hint'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (v) {
              _search = v;
              _loadTrees();
            },
          ),
        ),
        Expanded(
          child: _loadingTrees
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(child: Text(_loadError!))
                  : _trees.isEmpty
                      ? Center(child: Text(context.tr('maintain_empty')))
                      : RefreshIndicator(
                          onRefresh: _loadTrees,
                          child: ListView.builder(
                            itemCount: _trees.length,
                            itemBuilder: (ctx, i) {
                              final t = _trees[i];
                              final id = _treeId(t);
                              final pt = (t['project_tree_id'] ??
                                      t['專案樹木'])
                                  ?.toString();
                              final st = (t['system_tree_id'] ??
                                      t['系統樹木'])
                                  ?.toString();
                              final species = (t['species_name'] ??
                                      t['樹種名稱'] ??
                                      '—')
                                  .toString();
                              final h = t['tree_height_m'] ??
                                  t['樹高（公尺）'];
                              final dbh =
                                  t['dbh_cm'] ?? t['胸徑（公分）'];
                              return ListTile(
                                title: Text(
                                  TreeIdDisplay.fieldListLabel(
                                    projectTreeId: pt,
                                    systemTreeId: st,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 18,
                                  ),
                                ),
                                subtitle: Text(
                                  '$species · H $h m · DBH $dbh cm',
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: id == null
                                    ? null
                                    : () => _startBle(
                                          target: MaintenanceTarget(
                                            treeSurveyId: id,
                                            projectTreeId: pt,
                                            systemTreeId: st,
                                            speciesName: species != '—'
                                                ? species
                                                : null,
                                          ),
                                        ),
                              );
                            },
                          ),
                        ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: setup == null ? null : () => _startBle(),
              icon: const Icon(Icons.add),
              label: Text(context.tr('maintain_add_tree')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.teal,
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBleStep() {
    final isMaint = _targetTree != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            isMaint
                ? context.tr('maintain_ble_remeasure').replaceAll(
                    '{id}',
                    TreeIdDisplay.projectTreeDigits(
                      _targetTree!.projectTreeId,
                    ),
                  )
                : context.tr('maintain_ble_new'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: BleDeviceScanner(
            onDeviceSelected: (d) {
              setState(() => _selectedDevice = d);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _step = 0),
                child: Text(context.tr('maintain_back_list')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      _selectedDevice == null ? null : _openLiveSession,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(context.tr('ble_start')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
