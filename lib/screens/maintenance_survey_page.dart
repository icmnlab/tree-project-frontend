import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';

import '../models/maintenance_target.dart';
import '../services/maintenance_lock_service.dart';
import '../services/tree_service.dart';
import '../utils/location_helper.dart';
import '../utils/maintenance_session.dart';
import '../utils/tree_id_display.dart';
import '../widgets/ble/ble_device_scanner.dart';
import '../widgets/field/field_session_setup.dart';
import '../widgets/maintenance/maintenance_tree_map.dart';
import '../widgets/tree_measurement_history_panel.dart';
import 'ble_live_session_page.dart';
import '../services/locale_service.dart';

enum _MaintainView { list, map }

/// 維護量測：選區 → 開始場次 → 重測（本場已完成者自清單／地圖移除）→ 使用者按「完成維護」結束
class MaintenanceSurveyPage extends StatefulWidget {
  const MaintenanceSurveyPage({super.key});

  @override
  State<MaintenanceSurveyPage> createState() => _MaintenanceSurveyPageState();
}

class _MaintenanceSurveyPageState extends State<MaintenanceSurveyPage> {
  final _treeService = TreeService();
  final _lockService = MaintenanceLockService();
  FieldSessionSetup? _setup;
  MaintenanceTarget? _targetTree;
  BluetoothDevice? _selectedDevice;

  bool _loadingTrees = false;
  String? _loadError;

  /// [稽核#8] 樹木清單達查詢上限（500），可能不完整
  bool _listTruncated = false;
  List<Map<String, dynamic>> _trees = [];
  String _search = '';
  int _step = 0; // 0=list 1=ble
  _MaintainView _view = _MaintainView.list;

  /// 本場次已成功重測的 tree_survey.id（自待辦清單／地圖隱藏）
  final Set<int> _completedThisSession = {};
  /// 本場次「新增樹木」入庫的 id（非待重測，自待辦清單／地圖隱藏）
  final Set<int> _addedThisSession = {};
  int _sessionInitialCount = 0;
  bool _allDoneDialogShown = false;

  double? _userLat;
  double? _userLon;
  Map<int, MaintenanceLockInfo> _locksByTreeId = {};
  int? _heldLockTreeId;

  @override
  void dispose() {
    final held = _heldLockTreeId;
    if (held != null) {
      _lockService.releaseLock(held);
    }
    super.dispose();
  }
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
    if (!mounted) return;
    setState(() => _sessionInitialCount = _trees.length);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('maintain_session_started')),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _loadLocks() async {
    final code = _setup?.projectCode;
    if (code == null || code.isEmpty) return;
    final locks = await _lockService.fetchLocks(code);
    if (!mounted) return;
    setState(() => _locksByTreeId = locks);
  }

  String? _lockLabelForTree(int treeId) {
    final lock = _locksByTreeId[treeId];
    if (lock == null) return null;
    final name = lock.displayName ?? '?';
    return context.tr('maintain_locked_by').replaceAll('{name}', name);
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
      final pos = await Geolocator.getLastKnownPosition() ??
          await getHighAccuracyPosition(timeout: const Duration(seconds: 5));
      if (pos != null) {
        _userLat = pos.latitude;
        _userLon = pos.longitude;
      } else {
        _userLat = null;
        _userLon = null;
      }
      _sortTreesByDistance(list);
      setState(() {
        _trees = list;
        // [稽核#8] 達到查詢上限代表清單可能被截斷，需提示使用者用搜尋縮小範圍
        _listTruncated = list.length >= 500;
        _loadingTrees = false;
      });
      await _loadLocks();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loadingTrees = false;
      });
    }
  }

  void _sortTreesByDistance(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final da = _distanceToTreeM(a) ?? double.infinity;
      final db = _distanceToTreeM(b) ?? double.infinity;
      return da.compareTo(db);
    });
  }

  int? _treeId(Map<String, dynamic> t) => maintenanceTreeIdOf(t);

  bool _isPendingInSession(Map<String, dynamic> t) => isMaintenanceSessionPending(
        treeId: _treeId(t),
        completedThisSession: _completedThisSession,
        addedThisSession: _addedThisSession,
      );

  int get _pendingCount =>
      _trees.where(_isPendingInSession).length;

  int get _doneCount => _completedThisSession.length;

  List<Map<String, dynamic>> get _displayTrees {
    final q = _search.trim().toLowerCase();
    return _trees.where((t) {
      if (!_isPendingInSession(t)) return false;
      if (q.isEmpty) return true;
      final pt = (t['project_tree_id'] ?? t['專案樹木'] ?? '').toString();
      final st = (t['system_tree_id'] ?? t['系統樹木'] ?? '').toString();
      final species =
          (t['species_name'] ?? t['樹種名稱'] ?? '').toString().toLowerCase();
      final digits = TreeIdDisplay.projectTreeDigits(pt);
      return digits.contains(q) ||
          pt.toLowerCase().contains(q) ||
          st.toLowerCase().contains(q) ||
          species.contains(q);
    }).toList();
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
    final target = _targetTree;
    int? lockTreeId;
    if (target != null) {
      final acquire = await _lockService.acquireLock(
        target.treeSurveyId,
        sessionHint: _setup!.batchName,
      );
      if (!mounted) return;
      if (!acquire.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              acquire.message ?? context.tr('maintain_lock_blocked'),
            ),
            backgroundColor: Colors.orange,
          ),
        );
        await _loadLocks();
        return;
      }
      lockTreeId = target.treeSurveyId;
      _heldLockTreeId = lockTreeId;
    }
    MaintenanceSessionResult? result;
    try {
      result = await Navigator.of(context).push<MaintenanceSessionResult>(
        MaterialPageRoute(
          builder: (_) => BleLiveSessionPage(
            initialDevice: _selectedDevice,
            initialSessionSetup: _setup,
            maintenanceTarget: target,
            maintenanceSessionContext: true,
          ),
        ),
      );
    } finally {
      if (lockTreeId != null) {
        await _lockService.releaseLock(lockTreeId);
        if (_heldLockTreeId == lockTreeId) {
          _heldLockTreeId = null;
        }
        if (mounted) await _loadLocks();
      }
    }
    if (!mounted) return;
    setState(() {
      _step = 0;
      _targetTree = null;
    });
    if (result?.success != true) return;
    final successResult = result!;
    if (successResult.isNewTree) {
      if (successResult.treeSurveyId != null) {
        setState(() {
          _addedThisSession.add(successResult.treeSurveyId!);
        });
      }
      await _loadTrees();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('maintain_new_tree_done')),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: context.tr('maintain_add_another'),
            onPressed: () => _startBle(),
          ),
        ),
      );
      return;
    }
    if (successResult.treeSurveyId != null) {
      setState(() {
        _completedThisSession.add(successResult.treeSurveyId!);
        _allDoneDialogShown = false;
      });
      await _loadTrees();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('maintain_done_pick_next')),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
      _maybeShowAllTreesDoneDialog();
    }
  }

  void _maybeShowAllTreesDoneDialog() {
    if (_allDoneDialogShown) return;
    if (_sessionInitialCount <= 0) return;
    if (_pendingCount > 0) return;
    if (_completedThisSession.isEmpty) return;
    _allDoneDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showAllTreesDoneDialog();
    });
  }

  Future<void> _showAllTreesDoneDialog() async {
    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('maintain_all_done_title')),
        content: Text(
          context
              .tr('maintain_all_done_body')
              .replaceAll('{done}', '$_doneCount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'add'),
            child: Text(context.tr('maintain_all_done_add')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'finish'),
            child: Text(context.tr('maintain_finish')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'add') {
      _startBle();
    } else if (action == 'finish') {
      await _finishMaintenanceSession();
    } else {
      _allDoneDialogShown = false;
    }
  }

  Future<bool> _confirmFinishSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('maintain_finish_confirm_title')),
        content: Text(
          context
              .tr('maintain_finish_confirm_body')
              .replaceAll('{done}', '$_doneCount')
              .replaceAll('{remaining}', '$_pendingCount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('maintain_finish')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _finishMaintenanceSession() async {
    if (!await _confirmFinishSession()) return;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  double? _treeCoord(Map<String, dynamic> t, String en, String zh) {
    final v = t[en] ?? t[zh];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '');
  }

  double? _distanceToTreeM(Map<String, dynamic> t) {
    if (_userLat == null || _userLon == null) return null;
    final lat = _treeCoord(t, 'y_coord', 'Y坐標');
    final lon = _treeCoord(t, 'x_coord', 'X坐標');
    if (lat == null || lon == null || lat == 0 || lon == 0) return null;
    return Geolocator.distanceBetween(_userLat!, _userLon!, lat, lon);
  }

  String? _distanceLabel(Map<String, dynamic> t) {
    final m = _distanceToTreeM(t);
    if (m == null) return null;
    if (m >= 1000) return '約 ${(m / 1000).toStringAsFixed(1)} km';
    return context.tr('maintain_distance_m').replaceAll('{n}', '${m.round()}');
  }

  MaintenanceTarget? _targetFromTree(Map<String, dynamic> t) {
    final id = _treeId(t);
    if (id == null) return null;
    final pt = (t['project_tree_id'] ?? t['專案樹木'])?.toString();
    final st = (t['system_tree_id'] ?? t['系統樹木'])?.toString();
    final species =
        (t['species_name'] ?? t['樹種名稱'] ?? '—').toString();
    final lat = _treeCoord(t, 'y_coord', 'Y坐標');
    final lon = _treeCoord(t, 'x_coord', 'X坐標');
    return MaintenanceTarget(
      treeSurveyId: id,
      projectTreeId: pt,
      systemTreeId: st,
      speciesName: species != '—' ? species : null,
      treeLatitude: lat,
      treeLongitude: lon,
    );
  }

  void _confirmTreeSelection(Map<String, dynamic> t) {
    final target = _targetFromTree(t);
    if (target == null) return;
    final pt = (t['project_tree_id'] ?? t['專案樹木'])?.toString();
    final species =
        (t['species_name'] ?? t['樹種名稱'] ?? '—').toString();
    final h = t['tree_height_m'] ?? t['樹高（公尺）'];
    final dbh = t['dbh_cm'] ?? t['胸徑（公分）'];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                TreeIdDisplay.fieldListLabel(
                  projectTreeId: pt,
                  systemTreeId: target.systemTreeId,
                ),
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text('$species · H $h m · DBH $dbh cm'),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.tr('history_title'),
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              TreeMeasurementHistoryPanel(
                treeId: target.treeSurveyId,
                initialLimit: 5,
                compact: true,
              ),
              if (_lockLabelForTree(target.treeSurveyId) != null) ...[
                const SizedBox(height: 8),
                Text(
                  _lockLabelForTree(target.treeSurveyId)!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _locksByTreeId.containsKey(target.treeSurveyId)
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _startBle(target: target);
                      },
                icon: const Icon(Icons.sensors),
                label: Text(context.tr('maintain_map_remeasure')),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.tr('maintain_map_cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _completedThisSession.isEmpty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('maintain_leave_title')),
            content: Text(
              context
                  .tr('maintain_leave_body')
                  .replaceAll('{done}', '$_doneCount'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(context.tr('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(context.tr('maintain_leave_confirm')),
              ),
            ],
          ),
        );
        if (leave != true) return;
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('maintain_title')),
          backgroundColor: Colors.orange.shade800,
          foregroundColor: Colors.white,
          actions: [
            if (_setup != null && _step == 0)
              TextButton(
                onPressed: _finishMaintenanceSession,
                child: Text(
                  context.tr('maintain_finish'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
        body: _step == 0 ? _buildListStep() : _buildBleStep(),
      ),
    );
  }

  Widget _buildListStep() {
    final setup = _setup;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: Column(
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
                        tooltip: context.tr('field_setup_title'),
                        onPressed: () async {
                          if (_completedThisSession.isNotEmpty) {
                            final reset = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title:
                                    Text(context.tr('maintain_scope_change_title')),
                                content: Text(
                                    context.tr('maintain_scope_change_body')),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: Text(context.tr('cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(context.tr('field_setup_confirm')),
                                  ),
                                ],
                              ),
                            );
                            if (reset != true || !mounted) return;
                          }
                          final s = await showFieldSessionSetupDialog(
                            context,
                            initial: setup,
                          );
                          if (s != null && mounted) {
                            setState(() {
                              _setup = s;
                              _completedThisSession.clear();
                              _addedThisSession.clear();
                              _allDoneDialogShown = false;
                            });
                            await _loadTrees();
                            if (mounted) {
                              setState(() => _sessionInitialCount = _trees.length);
                            }
                          }
                        },
                      ),
                    ),
                  ),
                if (_setup != null)
                  Material(
                    color: Colors.orange.shade100,
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.playlist_add_check,
                          color: Colors.orange.shade900),
                      title: Text(
                        context
                            .tr('maintain_session_progress')
                            .replaceAll('{remaining}', '$_pendingCount')
                            .replaceAll('{done}', '$_doneCount')
                            .replaceAll('{total}', '$_sessionInitialCount'),
                      ),
                      subtitle: Text(context.tr('maintain_session_hint')),
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
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() => _search = '');
                                _loadTrees();
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) => setState(() => _search = v),
                    onSubmitted: (_) => _loadTrees(),
                  ),
                ),
                if (_userLat != null && _pendingCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      context.tr('maintain_sorted_nearby'),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: SegmentedButton<_MaintainView>(
                    segments: [
                      ButtonSegment(
                        value: _MaintainView.list,
                        label: Text(
                          context
                              .tr('maintain_tab_list')
                              .replaceAll('{n}', '${_displayTrees.length}'),
                        ),
                        icon: const Icon(Icons.list, size: 18),
                      ),
                      ButtonSegment(
                        value: _MaintainView.map,
                        label: Text(context.tr('maintain_tab_map')),
                        icon: const Icon(Icons.map_outlined, size: 18),
                      ),
                    ],
                    selected: {_view},
                    onSelectionChanged: (s) {
                      setState(() => _view = s.first);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // [稽核#8] 清單可能被截斷時的明確提示（取代靜默截斷）
        if (_listTruncated && !_loadingTrees)
          Container(
            width: double.infinity,
            color: Colors.orange.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 16, color: Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '清單僅顯示前 500 筆，可能不完整；請用搜尋縮小範圍',
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade900),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loadingTrees
              ? const Center(child: CircularProgressIndicator())
              : _loadError != null
                  ? Center(child: Text(_loadError!))
                  : _displayTrees.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _trees.isEmpty
                                  ? context.tr('maintain_empty')
                                  : _pendingCount == 0 &&
                                          _sessionInitialCount > 0
                                      ? context.tr('maintain_pending_empty')
                                      : context.tr('maintain_search_empty'),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : _view == _MaintainView.map
                          ? MaintenanceTreeMap(
                              trees: _displayTrees,
                              onTreeTap: _confirmTreeSelection,
                              gpsCoverageHint:
                                  context.tr('maintain_map_gps_coverage'),
                              emptyMessage:
                                  context.tr('maintain_map_no_gps'),
                              tapHint: context.tr('maintain_map_tap_hint'),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadTrees,
                              child: ListView.builder(
                                itemCount: _displayTrees.length,
                                itemBuilder: (ctx, i) {
                                  final t = _displayTrees[i];
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
                                  final dist = _distanceLabel(t);
                                  final tid = _treeId(t);
                                  final lockLabel =
                                      tid != null ? _lockLabelForTree(tid) : null;
                                  var sub = dist == null
                                      ? '$species · H $h m · DBH $dbh cm'
                                      : '$species · H $h m · DBH $dbh cm · $dist';
                                  if (lockLabel != null) {
                                    sub = '$sub · $lockLabel';
                                  }
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
                                    subtitle: Text(sub),
                                    trailing:
                                        const Icon(Icons.chevron_right),
                                    onTap: () => _confirmTreeSelection(t),
                                  );
                                },
                              ),
                            ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        setup == null ? null : _finishMaintenanceSession,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(context.tr('maintain_finish')),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
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
              ],
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
