import 'package:flutter/material.dart';
import 'dart:async';
import 'tree_survey_detail_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'services/tree_service.dart';
import 'services/admin_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart'; // 角色權限
import 'constants/colors.dart';
import 'services/locale_service.dart';
import 'services/project_service.dart';
import 'services/project_scope_store.dart';

/// [T6 cleanup] 中文表頭→V2 (English) DB 欄位映射
/// 用于 Excel 匯入 + 批次更新改走 createTreeV2 / updateTreeV2。
Map<String, dynamic> _zhToV2(Map<String, dynamic> src) {
  const zh2en = {
    '專案區位': 'project_area',
    '專案代碼': 'project_code',
    '專案名稱': 'project_name',
    '系統樹木': 'system_tree_id',
    '專案樹木': 'project_tree_id',
    '樹種編號': 'species_id',
    '樹種名稱': 'species_name',
    'X坐標': 'x_coord',
    'Y坐標': 'y_coord',
    '狀況': 'status',
    '註記': 'note',
    '樹木備註': 'tree_remark',
    '樹高（公尺）': 'tree_height_m',
    '胸徑（公分）': 'dbh_cm',
    '調查備註': 'survey_notes',
    '調查時間': 'survey_time',
    '碳儲存量': 'carbon_storage',
    '推估年碳吸存量': 'carbon_sequestration_per_year',
  };
  final out = <String, dynamic>{};
  src.forEach((k, v) {
    final ek = zh2en[k];
    if (ek != null && v != null && v.toString().isNotEmpty) out[ek] = v;
  });
  return out;
}

class TreeListPage extends StatefulWidget {
  const TreeListPage({Key? key}) : super(key: key);

  @override
  State<TreeListPage> createState() => _TreeListPageState();
}

class _TreeListPageState extends State<TreeListPage> {
  List<Map<String, dynamic>> _trees = [];
  List<Map<String, dynamic>> _filteredTrees = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _totalCount = 0;
  static const int _pageSize = 200;
  int _offset = 0;
  final ScrollController _scrollController = ScrollController();
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedProject = '全部';
  List<String> _projects = ['全部'];
  Map<String, String> _projectNameToCode = {};
  Timer? _searchDebounce;

  void _treeListLog(String message) {
    debugPrint('[TreeList] $message');
  }
  String _sortBy = '樹種名稱';
  bool _isAscending = true;
  final List<String> _sortOptions = [
    '樹種名稱',
    '專案名稱',
    '專案區位',
    '樹高（公尺）',
    '胸徑（公分）',
    '碳儲存量',
    '推估年碳吸存量'
  ];

  // 批次操作相關
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};

  // 匯入相關
  bool _isImporting = false;
  String _importStatus = '';
  
  // 匯出相關
  bool _isExportingExcel = false;
  bool _isExportingPdf = false;

  // 角色權限
  bool _canEdit = false;
  bool _canDelete = false;

  final TreeService _treeService = TreeService();

  @override
  void initState() {
    super.initState();
    // 觸發一次性的背景清理任務，不需要等待其完成
    ApiService.triggerCleanup();

    _fetchTrees(reset: true);
    _loadProjectOptions();
    _loadPermissions();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 400 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _fetchTrees(reset: false);
    }
  }

  Future<void> _loadPermissions() async {
    final canEdit = await AuthService.canEditTrees();
    final canDelete = await AuthService.canDeleteTrees();
    if (mounted) {
      setState(() {
        _canEdit = canEdit;
        _canDelete = canDelete;
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProjectOptions() async {
    try {
      final meta = await _treeService.getMapMeta();
      final projResp = await ProjectService().getProjects(forceRefresh: true);
      final lastScope = await ProjectScopeStore().loadLast();
      if (!mounted) return;
      final names = <String>{};
      final nameToCode = <String, String>{};
      for (final p in ProjectService.projectListFromResponse(projResp)) {
        if (p is! Map) continue;
        final name = p['name']?.toString();
        final code = (p['code'] ?? p['project_code'])?.toString();
        if (name != null && name.isNotEmpty) {
          names.add(name);
          if (code != null && code.isNotEmpty) nameToCode[name] = code;
        }
      }
      final sorted = names.toList()..sort();
      String? preselectBlock;
      if (lastScope != null && lastScope.isComplete) {
        if (sorted.contains(lastScope.blockName)) {
          preselectBlock = lastScope.blockName;
        }
      }
      setState(() {
        _projectNameToCode = nameToCode;
        _projects = ['全部', ...sorted];
        if (preselectBlock != null) {
          _selectedProject = preselectBlock;
        } else {
          _sanitizeSelectedProject();
        }
      });
      _treeListLog('projects loaded: ${sorted.length} (meta trees=${meta['totalTrees']})');
      if (preselectBlock != null) {
        _treeListLog('ProjectScope preselect block=$preselectBlock');
        _fetchTrees(reset: true);
      }
    } catch (e) {
      _treeListLog('load projects failed: $e');
    }
  }

  void _sanitizeSelectedProject() {
    if (_projects.contains(_selectedProject)) return;
    _selectedProject = '全部';
  }

  String? get _selectedProjectCode {
    if (_selectedProject == '全部') return null;
    return _projectNameToCode[_selectedProject];
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _treeListLog('search q="$value" project=$_selectedProject');
      _fetchTrees(reset: true);
    });
  }

  String? get _selectedProjectFilterName {
    if (_selectedProject == '全部') return null;
    if (_selectedProjectCode != null) return null;
    return _selectedProject;
  }

  Future<void> _fetchTrees({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _offset = 0;
        _hasMore = true;
        _trees = [];
      });
    } else {
      if (!_hasMore || _isLoadingMore) return;
      setState(() => _isLoadingMore = true);
    }

    try {
      final response = await _treeService.getAllTrees(
        limit: _pageSize,
        offset: _offset,
        projectCode: _selectedProjectCode,
        projectName: _selectedProjectFilterName,
        search: _searchController.text.trim(),
      );

      if (response['success'] == true && response['data'] is List) {
        final batch = (response['data'] as List<dynamic>)
            .map((t) => t as Map<String, dynamic>)
            .toList();
        final total = (response['totalCount'] as num?)?.toInt();

        setState(() {
          if (reset) {
            _trees = batch;
          } else {
            _trees.addAll(batch);
          }
          _offset = _trees.length;
          _totalCount = total ?? _trees.length;
          _hasMore = batch.length >= _pageSize && _trees.length < _totalCount;
          _filterAndSortTrees();
          _isLoading = false;
          _isLoadingMore = false;
        });
      } else {
        throw Exception('API 回應格式不正確或請求失敗');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _filterAndSortTrees() {
    var filtered = List<Map<String, dynamic>>.from(_trees);

    // 再排序
    filtered.sort((a, b) {
      var aValue = a[_sortBy];
      var bValue = b[_sortBy];

      // 處理數值型別
      if (_sortBy == '樹高（公尺）' ||
          _sortBy == '胸徑（公分）' ||
          _sortBy == '碳儲存量' ||
          _sortBy == '推估年碳吸存量') {
        aValue = double.tryParse(aValue?.toString() ?? '0') ?? 0;
        bValue = double.tryParse(bValue?.toString() ?? '0') ?? 0;
      } else {
        // 處理字串型別
        aValue = aValue?.toString() ?? '';
        bValue = bValue?.toString() ?? '';
      }

      int comparison = 0;
      if (aValue is num && bValue is num) {
        comparison = aValue.compareTo(bValue);
      } else {
        comparison = aValue.toString().compareTo(bValue.toString());
      }

      return _isAscending ? comparison : -comparison;
    });

    setState(() {
      _filteredTrees = filtered;
    });
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('tree_list_sort_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._sortOptions.map((option) => RadioListTile<String>(
                  title: Text(option),
                  value: option,
                  groupValue: _sortBy,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _sortBy = value;
                      });
                      _filterAndSortTrees();
                      Navigator.pop(context);
                    }
                  },
                )),
            const Divider(),
            SwitchListTile(
              title: Text(context.tr('tree_list_sort_asc')),
              value: _isAscending,
              onChanged: (value) {
                setState(() {
                  _isAscending = value;
                });
                _filterAndSortTrees();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedIndices.clear();
      }
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  /// 取得目前過濾後的專案代碼列表
  List<String> _getFilteredProjectCodes() {
    final codes = _filteredTrees
        .map((t) => t['專案代碼']?.toString() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    return codes;
  }

  Future<void> _exportToExcel() async {
    if (_isExportingExcel) return;
    
    setState(() => _isExportingExcel = true);
    try {
      final result = await ExportService.downloadExcel(_getFilteredProjectCodes());
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.warning ?? 'Excel 檔案已下載並開啟')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? '下載失敗')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出時發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingExcel = false);
      }
    }
  }

  Future<void> _exportToPDF() async {
    if (_isExportingPdf) return; // 防止重複點擊
    
    setState(() => _isExportingPdf = true);
    try {
      final result = await ExportService.downloadPdf(_getFilteredProjectCodes());
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.warning ?? 'PDF 檔案已下載並開啟')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? '下載失敗')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出時發生錯誤: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPdf = false);
      }
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇要刪除的項目')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: Text('確定要刪除選中的 ${_selectedIndices.length} 筆資料嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final List<int> treeIdsToDelete = _selectedIndices
            .map((index) => _filteredTrees[index]['id'] as int)
            .toList();

        for (final treeId in treeIdsToDelete) {
          await _treeService.deleteTree(treeId.toString());
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('批次刪除成功')),
          );
          _toggleSelectionMode();
          _fetchTrees();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('刪除時發生錯誤: $e')),
          );
        }
      }
    }
  }

  Future<void> _importFromExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        setState(() {
          _isImporting = true;
          _importStatus = '正在讀取檔案...';
        });

        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);

        setState(() {
          _importStatus = '正在解析資料...';
        });

        final sheet = excel.tables.keys.first;
        final rows = excel.tables[sheet]!.rows;

        // 跳過標題行
        final data = rows.skip(1).map((row) {
          return {
            '專案區位': row[0]?.value?.toString() ?? '',
            '專案代碼': row[1]?.value?.toString() ?? '',
            '專案名稱': row[2]?.value?.toString() ?? '',
            '系統樹木': row[3]?.value?.toString() ?? '',
            '專案樹木': row[4]?.value?.toString() ?? '',
            '樹種編號': row[5]?.value?.toString() ?? '',
            '樹種名稱': row[6]?.value?.toString() ?? '',
            'X坐標': double.tryParse(row[7]?.value?.toString() ?? '0') ?? 0,
            'Y坐標': double.tryParse(row[8]?.value?.toString() ?? '0') ?? 0,
            '狀況': row[9]?.value?.toString() ?? '',
            '註記': row[10]?.value?.toString() ?? '',
            '樹木備註': row[11]?.value?.toString() ?? '',
            '樹高（公尺）': double.tryParse(row[12]?.value?.toString() ?? '0') ?? 0,
            '胸徑（公分）': double.tryParse(row[13]?.value?.toString() ?? '0') ?? 0,
            '調查備註': row[14]?.value?.toString() ?? '',
            '調查時間':
                row[15]?.value?.toString() ?? DateTime.now().toIso8601String(),
            '碳儲存量': double.tryParse(row[16]?.value?.toString() ?? '0') ?? 0,
            '推估年碳吸存量': double.tryParse(row[17]?.value?.toString() ?? '0') ?? 0,
          };
        }).toList();

        setState(() {
          _importStatus = '正在上傳資料...';
        });

        // 批次上傳資料（T6 cleanup：走 V2 createTreeV2）
        for (var item in data) {
          final v2 = _zhToV2(item);
          if (v2.isNotEmpty) {
            await _treeService.createTreeV2(v2);
          }
        }

        setState(() {
          _isImporting = false;
          _importStatus = '';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('資料匯入成功')),
          );
          _fetchTrees();
        }
      }
    } catch (e) {
      setState(() {
        _isImporting = false;
        _importStatus = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯入失敗: $e')),
        );
      }
    }
  }

  Future<void> _batchUpdate() async {
    if (_selectedIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先選擇要更新的項目')),
      );
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('批次更新'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: '專案區位',
                  hintText: '留空表示不更新',
                ),
                onChanged: (value) => _batchUpdateData['專案區位'] = value,
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: '專案代碼',
                  hintText: '留空表示不更新',
                ),
                onChanged: (value) => _batchUpdateData['專案代碼'] = value,
              ),
              TextField(
                decoration: const InputDecoration(
                  labelText: '專案名稱',
                  hintText: '留空表示不更新',
                ),
                onChanged: (value) => _batchUpdateData['專案名稱'] = value,
              ),
              // 可以添加更多欄位
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _batchUpdateData),
            child: const Text('確定'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        final List<Map<String, dynamic>> treesToUpdate =
            _selectedIndices.map((index) => _filteredTrees[index]).toList();

        final updateData = Map<String, dynamic>.from(result);
        updateData.removeWhere(
            (key, value) => value == null || value.toString().isEmpty);

        if (updateData.isNotEmpty) {
          // [T6 cleanup] 走 V2：中文表頭譯成英文欄位。
          // 批次更新不帶 expected_updated_at → 其實是後寫贏（同 Phase 1 向後相容設計）。
          final v2Update = _zhToV2(updateData);
          if (v2Update.isNotEmpty) {
            for (final tree in treesToUpdate) {
              await _treeService.updateTreeV2(tree['id'].toString(), v2Update);
            }
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('批次更新成功')),
          );
          _toggleSelectionMode();
          _fetchTrees();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('更新時發生錯誤: $e')),
          );
        }
      }
    }
  }

  final Map<String, dynamic> _batchUpdateData = {};

  @override
  Widget build(BuildContext context) {
    // [B5] 暗/亮模式色彩輔助變數（AppBar 漸層、按鈕白字保持原樣，因為永遠在彩色背景上）
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final pageBg = isDark ? AppColors.darkBackground : AppColors.surfaceLight;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.neutral900;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.neutral600;
    final textTertiary = isDark ? AppColors.darkTextTertiary : AppColors.neutral500;

    return Scaffold(
      backgroundColor: pageBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.portBlue, AppColors.portBlue.withValues(alpha: 0.8)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.portBlue.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: Text(
          context.tr('tree_list_title'),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isSelectionMode) ...[
            if (_canEdit)
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                tooltip: context.tr('tree_list_batch_update'),
                onPressed: _batchUpdate,
              ),
            if (_canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: context.tr('tree_list_batch_delete'),
                onPressed: _batchDelete,
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: context.tr('tree_list_cancel_select'),
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              tooltip: context.tr('tree_list_sort'),
              onPressed: _showSortDialog,
            ),
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: context.tr('tree_list_batch_select'),
              onPressed: _toggleSelectionMode,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onSelected: (value) {
                switch (value) {
                  case 'excel':
                    _exportToExcel();
                    break;
                  case 'pdf':
                    _exportToPDF();
                    break;
                  case 'import':
                    _importFromExcel();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'excel',
                  enabled: !_isExportingExcel && !_isExportingPdf,
                  child: Row(
                    children: [
                      _isExportingExcel
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.table_chart_rounded, color: AppColors.forestGreen),
                      const SizedBox(width: 12),
                      Text(_isExportingExcel ? context.tr('tree_list_export_excel_loading') : context.tr('tree_list_export_excel')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'pdf',
                  enabled: !_isExportingExcel && !_isExportingPdf,
                  child: Row(
                    children: [
                      _isExportingPdf
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(Icons.picture_as_pdf_rounded, color: AppColors.tipcRed),
                      const SizedBox(width: 12),
                      Text(_isExportingPdf ? context.tr('tree_list_export_pdf_loading') : context.tr('tree_list_export_pdf')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file_rounded, color: AppColors.portBlue),
                      const SizedBox(width: 12),
                      Text(context.tr('tree_list_import_excel')),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [pageBg, cardBg],
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: context.tr('tree_list_search_hint'),
                              hintStyle: TextStyle(color: textTertiary, fontSize: 14),
                              prefixIcon: Icon(Icons.search_rounded, color: AppColors.portBlue),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: cardBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _projects.contains(_selectedProject)
                                ? _selectedProject
                                : '全部',
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.portBlue),
                            items: _projects.map((String project) {
                              return DropdownMenuItem<String>(
                                value: project,
                                child: Text(
                                  project.length > 8 ? '${project.substring(0, 8)}...' : project,
                                  style: TextStyle(fontSize: 14, color: textPrimary),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedProject = newValue;
                                });
                                _fetchTrees(reset: true);
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.portBlue.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort_rounded, size: 16, color: AppColors.portBlue),
                            const SizedBox(width: 8),
                            Text(
                              '$_sortBy (${_isAscending ? '↑' : '↓'})',
                              style: TextStyle(
                                color: AppColors.portBlue,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.forestGreen.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _trees.length < _totalCount
                              ? context.trParams('tree_list_total_partial', {
                                  'total': '$_totalCount',
                                  'loaded': '${_trees.length}',
                                })
                              : context.trParams('tree_list_total', {
                                  'n': '$_totalCount',
                                }),
                          style: TextStyle(
                            color: AppColors.forestGreen,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.portBlue.withValues(alpha: 0.1),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.portBlue),
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                context.tr('tree_list_loading'),
                                style: TextStyle(color: textSecondary, fontSize: 15),
                              ),
                            ],
                          ),
                        )
                      : _errorMessage.isNotEmpty
                          ? Center(
                              child: Container(
                                margin: const EdgeInsets.all(24),
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.error_outline_rounded,
                                        color: AppColors.error,
                                        size: 48,
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      _errorMessage,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: textSecondary, fontSize: 14),
                                    ),
                                    const SizedBox(height: 20),
                                    ElevatedButton(
                                      onPressed: _fetchTrees,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.portBlue,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                                        elevation: 0,
                                      ),
                                      child: const Text('重試', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _filteredTrees.isEmpty
                              ? Center(
                                  child: Container(
                                    margin: const EdgeInsets.all(24),
                                    padding: const EdgeInsets.all(40),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 20,
                                          spreadRadius: 5,
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: AppColors.forestGreen.withValues(alpha: 0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(Icons.park_outlined, size: 48, color: AppColors.forestGreen),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          '沒有符合條件的樹木資料',
                                          style: TextStyle(fontSize: 16, color: textPrimary, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: () => _fetchTrees(reset: true),
                                  color: AppColors.portBlue,
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                    itemCount: _filteredTrees.length +
                                        (_isLoadingMore ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      if (index >= _filteredTrees.length) {
                                        return const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        );
                                      }
                                      final tree = _filteredTrees[index];
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: cardBg,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.04),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(20),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(20),
                                            onTap: _isSelectionMode
                                                ? () => _toggleSelection(index)
                                                : () {
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (context) =>
                                                            TreeSurveyDetailPage(
                                                          treeData: tree,
                                                        ),
                                                      ),
                                                    ).then((_) => _fetchTrees());
                                                  },
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Row(
                                                children: [
                                                  // Leading
                                                  if (_isSelectionMode)
                                                    Checkbox(
                                                      value: _selectedIndices.contains(index),
                                                      onChanged: (value) => _toggleSelection(index),
                                                      activeColor: AppColors.portBlue,
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                    )
                                                  else
                                                    Container(
                                                      width: 52,
                                                      height: 52,
                                                      decoration: BoxDecoration(
                                                        gradient: LinearGradient(
                                                          colors: [AppColors.leafGreen, AppColors.forestGreen],
                                                          begin: Alignment.topLeft,
                                                          end: Alignment.bottomRight,
                                                        ),
                                                        borderRadius: BorderRadius.circular(14),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: AppColors.forestGreen.withValues(alpha: 0.3),
                                                            blurRadius: 8,
                                                            offset: const Offset(0, 3),
                                                          ),
                                                        ],
                                                      ),
                                                      child: const Icon(
                                                        Icons.park_rounded,
                                                        color: Colors.white,
                                                        size: 26,
                                                      ),
                                                    ),
                                                  const SizedBox(width: 16),
                                                  // Content
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          tree['樹種名稱'] ?? '未知樹種',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.w600,
                                                            fontSize: 16,
                                                            color: textPrimary,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 6),
                                                        Row(
                                                          children: [
                                                            Icon(Icons.folder_outlined, size: 14, color: textTertiary),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                tree['專案名稱'] ?? '未知專案',
                                                                style: TextStyle(color: textSecondary, fontSize: 13),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          children: [
                                                            Icon(Icons.location_on_rounded, size: 14, color: textTertiary),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                tree['專案區位'] ?? '未知區位',
                                                                style: TextStyle(color: textSecondary, fontSize: 13),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        if (_sortBy == '樹高（公尺）' || _sortBy == '胸徑（公分）' || _sortBy == '碳儲存量' || _sortBy == '推估年碳吸存量') ...[
                                                          const SizedBox(height: 6),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                            decoration: BoxDecoration(
                                                              color: AppColors.portBlue.withValues(alpha: 0.1),
                                                              borderRadius: BorderRadius.circular(8),
                                                            ),
                                                            child: Text(
                                                              _sortBy == '樹高（公尺）' ? '樹高: ${tree['樹高（公尺）']}m' :
                                                              _sortBy == '胸徑（公分）' ? '胸徑: ${tree['胸徑（公分）']}cm' :
                                                              _sortBy == '碳儲存量' ? '碳儲存量: ${tree['碳儲存量']}' :
                                                              '年碳吸存量: ${tree['推估年碳吸存量']}',
                                                              style: TextStyle(color: AppColors.portBlue, fontSize: 12, fontWeight: FontWeight.w500),
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                  // Trailing
                                                  if (!_isSelectionMode)
                                                    Container(
                                                      padding: const EdgeInsets.all(8),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.surfaceLight,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(
                                                        Icons.chevron_right_rounded,
                                                        color: AppColors.neutral500,
                                                        size: 20,
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                ),
              ],
            ),
          ),
          if (_isImporting)
            Container(
              color: Colors.black54,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_importStatus),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
