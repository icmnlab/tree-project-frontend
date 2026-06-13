import 'package:flutter/material.dart';
import '../services/project_area_service.dart';

/// 專案區位（project_areas）後台管理：列表 + 新增 / 編輯 / 刪除。
/// 後端 CRUD 端點皆需「專案管理員」以上權限。
/// 以 body widget 形式嵌入 AdminPage 的內容區（不自帶 Scaffold）。
class ProjectAreasAdminPage extends StatefulWidget {
  const ProjectAreasAdminPage({super.key});

  @override
  State<ProjectAreasAdminPage> createState() => _ProjectAreasAdminPageState();
}

class _ProjectAreasAdminPageState extends State<ProjectAreasAdminPage> {
  final ProjectAreaService _service = ProjectAreaService();

  bool _isLoading = false;
  String? _error;
  List<Map<String, dynamic>> _areas = [];

  @override
  void initState() {
    super.initState();
    _fetchAreas();
  }

  Future<void> _fetchAreas() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final areas = await _service.getProjectAreas();
      if (!mounted) return;
      setState(() => _areas = areas);
    } catch (e) {
      if (mounted) setState(() => _error = '載入專案失敗：$e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _openCreateDialog() async {
    final result = await _showAreaForm();
    if (result == null) return;
    try {
      final resp = await _service.addProjectArea({
        'area_name': result['area_name'],
        'description': result['description'],
      });
      if (resp['success'] == true) {
        _showSnack('專案「${result['area_name']}」已新增');
        _fetchAreas();
      } else {
        _showSnack(resp['message']?.toString() ?? '新增失敗', error: true);
      }
    } catch (e) {
      _showSnack('新增發生錯誤：$e', error: true);
    }
  }

  Future<void> _openEditDialog(Map<String, dynamic> area) async {
    final result = await _showAreaForm(existing: area);
    if (result == null) return;
    final id = area['id'];
    if (id == null) {
      _showSnack('此專案缺少 id，無法更新', error: true);
      return;
    }
    try {
      final resp = await _service.updateProjectArea(
        id is int ? id : int.parse(id.toString()),
        {
          'area_name': result['area_name'],
          // 後端 PUT 需 area_code，沿用原本代碼。
          'area_code': area['area_code'],
          'description': result['description'],
        },
      );
      if (resp['success'] == true) {
        _showSnack('專案已更新');
        _fetchAreas();
      } else {
        _showSnack(resp['message']?.toString() ?? '更新失敗', error: true);
      }
    } catch (e) {
      _showSnack('更新發生錯誤：$e', error: true);
    }
  }

  /// 顯示新增/編輯表單，回傳 {area_name, description} 或 null（取消）。
  Future<Map<String, String>?> _showAreaForm({Map<String, dynamic>? existing}) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => _AreaFormDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> area) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除專案'),
        content: Text(
            '確定要刪除專案「${area['area_name']}」嗎？\n若仍有區使用此專案，刪除會被拒絕。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final id = area['id'];
    if (id == null) {
      _showSnack('此專案缺少 id，無法刪除', error: true);
      return;
    }
    try {
      final resp = await _service
          .deleteProjectArea(id is int ? id : int.parse(id.toString()));
      if (resp['success'] == true) {
        _showSnack('專案已刪除');
        _fetchAreas();
      } else {
        // 後端 409：仍被專案引用
        final refs = (resp['data'] is Map) ? resp['data']['references'] : null;
        final extra = (refs is List && refs.isNotEmpty)
            ? '（仍有 ${refs.length} 筆引用）'
            : '';
        _showSnack(
            '${resp['message']?.toString() ?? '刪除失敗'}$extra',
            error: true);
      }
    } catch (e) {
      _showSnack('刪除發生錯誤：$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Expanded + ellipsis：避免標題與右側按鈕在窄螢幕擠壓造成 RenderFlex overflow
            Expanded(
              child: Text(
                '專案管理',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新整理',
                  onPressed: _fetchAreas,
                ),
                const SizedBox(width: 4),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('新增專案'),
                  onPressed: _openCreateDialog,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '專案（縣市/地區）是區的上層分類。刪除前須先移除其下所有區。',
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!,
                              style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchAreas,
                            child: const Text('重試'),
                          ),
                        ],
                      ),
                    )
                  : _areas.isEmpty
                      ? const Center(child: Text('目前沒有專案，請按「新增專案」建立。'))
                      : ListView.builder(
                          itemCount: _areas.length,
                          itemBuilder: (context, index) {
                            final area = _areas[index];
                            final name = area['area_name']?.toString() ?? '—';
                            final code = area['area_code']?.toString() ?? '—';
                            final city = area['city']?.toString();
                            final desc = area['description']?.toString();
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              elevation: 2,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Text(code,
                                      style: const TextStyle(fontSize: 12)),
                                ),
                                title: Text(name),
                                subtitle: Text([
                                  if (city != null && city.isNotEmpty) '縣市：$city',
                                  if (desc != null && desc.isNotEmpty) desc,
                                ].join('\n').trim().isEmpty
                                    ? '（無描述）'
                                    : [
                                        if (city != null && city.isNotEmpty)
                                          '縣市：$city',
                                        if (desc != null && desc.isNotEmpty) desc,
                                      ].join('\n')),
                                isThreeLine:
                                    (desc != null && desc.isNotEmpty),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: '編輯',
                                      onPressed: () => _openEditDialog(area),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      tooltip: '刪除',
                                      onPressed: () => _confirmDelete(area),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

/// 新增/編輯專案（區位）表單對話框。
///
/// 獨立 StatefulWidget：TextEditingController 由本 State 在 dispose() 釋放
/// （路由完全移除後才執行），避免原本 `showDialog().whenComplete(dispose)`
/// 在對話框退場動畫重建子樹時觸發
/// `TextEditingController was used after being disposed` 及連鎖錯誤
/// （_dependents.isEmpty / dirty widget wrong scope）。
class _AreaFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _AreaFormDialog({this.existing});

  @override
  State<_AreaFormDialog> createState() => _AreaFormDialogState();
}

class _AreaFormDialogState extends State<_AreaFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descController;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
        text: widget.existing?['area_name']?.toString() ?? '');
    _descController = TextEditingController(
        text: widget.existing?['description']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    final isEdit = _isEdit;
    final nameEmpty = _nameController.text.trim().isEmpty;
    return AlertDialog(
      title: Text(isEdit ? '編輯專案' : '新增專案'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isEdit && existing!['area_code'] != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('專案代碼：${existing['area_code']}',
                    style: const TextStyle(color: Colors.grey)),
              ),
            TextField(
              controller: _nameController,
              autofocus: !isEdit,
              // 編輯時不允許改名：area_name 被 tree_survey / project_boundaries
              // 等以名稱反規格化儲存，後端 PUT 不會連動更名，改名會造成既有資料
              // 指向舊名稱不一致。改名請改用「新增區位 + 搬移專案」流程。
              readOnly: isEdit,
              decoration: InputDecoration(
                labelText: isEdit ? '專案名稱（不可修改）' : '專案名稱 *',
                border: const OutlineInputBorder(),
                helperText: isEdit ? '名稱建立後不可變更，僅能編輯描述' : null,
                errorText: (!isEdit && nameEmpty) ? '專案名稱不能為空' : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: '描述（選填）',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: nameEmpty
              ? null
              : () => Navigator.pop(context, {
                    'area_name': _nameController.text.trim(),
                    'description': _descController.text.trim(),
                  }),
          child: Text(isEdit ? '儲存' : '新增'),
        ),
      ],
    );
  }
}
