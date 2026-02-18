import 'package:flutter/material.dart';
import 'tree_survey_detail_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'services/tree_service.dart';
import 'services/admin_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart'; // 角色權限
import 'constants/colors.dart';

class TreeListPage extends StatefulWidget {
  const TreeListPage({Key? key}) : super(key: key);

  @override
  State<TreeListPage> createState() => _TreeListPageState();
}

class _TreeListPageState extends State<TreeListPage> {
  List<Map<String, dynamic>> _trees = [];
  List<Map<String, dynamic>> _filteredTrees = [];
  bool _isLoading = true;
  String _errorMessage = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedProject = '全部';
  List<String> _projects = ['全部'];

  // 排序相關
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

    _fetchTrees();
    _loadPermissions();
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTrees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // 使用 TreeService 並正確處理回應格式
      final response = await _treeService.getAllTrees();

      // TreeService 現在回傳一個 Map，我們需要從 'data' 鍵中提取列表
      if (response['success'] == true && response['data'] is List) {
        final trees = response['data'] as List<dynamic>;

        setState(() {
          _trees = trees.map((t) => t as Map<String, dynamic>).toList();
          _projects = [
            '全部',
            ..._trees.map((t) => t['專案名稱'].toString()).toSet().toList()
          ];
          _filterAndSortTrees();
          _isLoading = false;
        });
      } else {
        throw Exception('API 回應格式不正確或請求失敗');
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
      });
    }
  }

  void _filterAndSortTrees() {
    final searchText = _searchController.text.toLowerCase();

    // 先過濾
    var filtered = _trees.where((tree) {
      final matchesSearch = searchText.isEmpty ||
          (tree['樹種名稱']?.toString().toLowerCase().contains(searchText) ??
              false) ||
          (tree['專案名稱']?.toString().toLowerCase().contains(searchText) ??
              false) ||
          (tree['專案區位']?.toString().toLowerCase().contains(searchText) ??
              false);

      final matchesProject =
          _selectedProject == '全部' || tree['專案名稱'] == _selectedProject;

      return matchesSearch && matchesProject;
    }).toList();

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
        title: const Text('排序選項'),
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
              title: const Text('升序排列'),
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

        // 批次上傳資料
        for (var item in data) {
          await _treeService.addTree(item);
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
          for (final tree in treesToUpdate) {
            await _treeService.updateTree(tree['id'].toString(), updateData);
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
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.portBlue, AppColors.portBlue.withOpacity(0.8)],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.portBlue.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        ),
        title: const Text(
          '樹木列表',
          style: TextStyle(
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
                tooltip: '批次更新',
                onPressed: _batchUpdate,
              ),
            if (_canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: '批次刪除',
                onPressed: _batchDelete,
              ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: '取消選擇',
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.sort_rounded),
              tooltip: '排序',
              onPressed: _showSortDialog,
            ),
            IconButton(
              icon: const Icon(Icons.checklist_rounded),
              tooltip: '批次選擇',
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
                      Text(_isExportingExcel ? '匯出 Excel 中...' : '匯出 Excel'),
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
                      Text(_isExportingPdf ? '匯出 PDF 中...' : '匯出 PDF'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file_rounded, color: AppColors.portBlue),
                      const SizedBox(width: 12),
                      const Text('匯入 Excel'),
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
                colors: [AppColors.surfaceLight, Colors.white],
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: '搜尋樹種、專案或區位',
                              hintStyle: TextStyle(color: AppColors.neutral400, fontSize: 14),
                              prefixIcon: Icon(Icons.search_rounded, color: AppColors.portBlue),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            ),
                            onChanged: (value) => _filterAndSortTrees(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedProject,
                            icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.portBlue),
                            items: _projects.map((String project) {
                              return DropdownMenuItem<String>(
                                value: project,
                                child: Text(
                                  project.length > 8 ? '${project.substring(0, 8)}...' : project,
                                  style: TextStyle(fontSize: 14, color: AppColors.neutral900),
                                ),
                              );
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) {
                                setState(() {
                                  _selectedProject = newValue;
                                  _filterAndSortTrees();
                                });
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.portBlue.withOpacity(0.08),
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
                          color: AppColors.forestGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '共 ${_filteredTrees.length} 棵',
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.portBlue.withOpacity(0.1),
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
                                '載入樹木資料中...',
                                style: TextStyle(color: AppColors.neutral600, fontSize: 15),
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
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
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
                                        color: AppColors.error.withOpacity(0.1),
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
                                      style: TextStyle(color: AppColors.neutral600, fontSize: 14),
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
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
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
                                            color: AppColors.forestGreen.withOpacity(0.1),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(Icons.park_outlined, size: 48, color: AppColors.forestGreen),
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          '沒有符合條件的樹木資料',
                                          style: TextStyle(fontSize: 16, color: AppColors.neutral700, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _fetchTrees,
                                  color: AppColors.portBlue,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                                    itemCount: _filteredTrees.length,
                                    itemBuilder: (context, index) {
                                      final tree = _filteredTrees[index];
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.04),
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
                                                            color: AppColors.forestGreen.withOpacity(0.3),
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
                                                            color: AppColors.neutral900,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 6),
                                                        Row(
                                                          children: [
                                                            Icon(Icons.folder_outlined, size: 14, color: AppColors.neutral500),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                tree['專案名稱'] ?? '未知專案',
                                                                style: TextStyle(color: AppColors.neutral600, fontSize: 13),
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Row(
                                                          children: [
                                                            Icon(Icons.location_on_rounded, size: 14, color: AppColors.neutral500),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                              child: Text(
                                                                tree['專案區位'] ?? '未知區位',
                                                                style: TextStyle(color: AppColors.neutral600, fontSize: 13),
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
                                                              color: AppColors.portBlue.withOpacity(0.1),
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
