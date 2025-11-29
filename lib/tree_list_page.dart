import 'package:flutter/material.dart';
import 'tree_survey_detail_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'services/tree_service.dart';
import 'services/admin_service.dart';
import 'services/api_service.dart';

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

  final TreeService _treeService = TreeService();

  @override
  void initState() {
    super.initState();
    // 觸發一次性的背景清理任務，不需要等待其完成
    ApiService.triggerCleanup();

    _fetchTrees();
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
  /*
  Future<void> _fetchTrees() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/tree_survey'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _trees = List<Map<String, dynamic>>.from(data);
          _projects = [
            '全部',
            ..._trees.map((t) => t['專案名稱'] as String).toSet().toList()
          ];
          _filterAndSortTrees();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = '無法載入資料 (狀態碼: ${response.statusCode})';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '發生錯誤: $e';
        _isLoading = false;
      });
    }
  }
  */

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

  Future<void> _exportToExcel() async {
    final url = ExportService.getExcelExportUrl(
        []); // Empty list for all projects for now
    try {
      await ExportService.launchExportUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel 檔案下載已啟動')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出時發生錯誤: $e')),
        );
      }
    }
  }
  /*
  Future<void> _exportToExcel() async {
    try {
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/export/excel'),
      );

      if (response.statusCode == 200) {
        // 在實際應用中，這裡需要處理檔案下載
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Excel 檔案已準備好下載')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('匯出失敗')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出時發生錯誤: $e')),
        );
      }
    }
  }
  */

  Future<void> _exportToPDF() async {
    final url = ExportService.getPdfExportUrl(
        []); // Empty list for all projects for now
    try {
      await ExportService.launchExportUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 檔案下載已啟動')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出時發生錯誤: $e')),
        );
      }
    }
  }
  /*
  Future<void> _exportToPDF() async {
    try {
      final response = await http.get(
        Uri.parse('http://172.20.10.4:3000/api/export/pdf'),
      );

      if (response.statusCode == 200) {
        // 在實際應用中，這裡需要處理檔案下載
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF 檔案已準備好下載')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('匯出失敗')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('匯出時發生錯誤: $e')),
        );
      }
    }
  }
  */

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
  /*
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
        for (final index in _selectedIndices) {
          final tree = _filteredTrees[index];
          final response = await http.delete(
            Uri.parse('${ApiService.baseUrl}/tree_survey/${tree['id']}'),
          );

          if (response.statusCode != 200) {
            throw Exception('刪除失敗: ${response.statusCode}');
          }
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
  */

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
  /*
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
          final response = await http.post(
            Uri.parse('${ApiService.baseUrl}/tree_survey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(item),
          );

          if (response.statusCode != 200) {
            throw Exception('上傳失敗: ${response.statusCode}');
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
  */

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
  /*
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
        for (final index in _selectedIndices) {
          final tree = _filteredTrees[index];
          final updateData = Map<String, dynamic>.from(result);
          updateData.removeWhere(
              (key, value) => value == null || value.toString().isEmpty);

          final response = await http.put(
            Uri.parse('${ApiService.baseUrl}/tree_survey/${tree['id']}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(updateData),
          );

          if (response.statusCode != 200) {
            throw Exception('更新失敗: ${response.statusCode}');
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
  */

  final Map<String, dynamic> _batchUpdateData = {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('樹木列表'),
        backgroundColor: Colors.green.shade100,
        elevation: 0,
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: '批次更新',
              onPressed: _batchUpdate,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: '批次刪除',
              onPressed: _batchDelete,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消選擇',
              onPressed: _toggleSelectionMode,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.sort),
              tooltip: '排序',
              onPressed: _showSortDialog,
            ),
            IconButton(
              icon: const Icon(Icons.select_all),
              tooltip: '批次選擇',
              onPressed: _toggleSelectionMode,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
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
                const PopupMenuItem(
                  value: 'excel',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart),
                      SizedBox(width: 8),
                      Text('匯出 Excel'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf),
                      SizedBox(width: 8),
                      Text('匯出 PDF'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file),
                      SizedBox(width: 8),
                      Text('匯入 Excel'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.green.shade50, Colors.white],
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜尋樹種、專案或區位',
                            prefixIcon: const Icon(Icons.search),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onChanged: (value) => _filterAndSortTrees(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<String>(
                        value: _selectedProject,
                        items: _projects.map((String project) {
                          return DropdownMenuItem<String>(
                            value: project,
                            child: Text(project),
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
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Text(
                        '排序方式: $_sortBy (${_isAscending ? '升序' : '降序'})',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _errorMessage.isNotEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 60,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _errorMessage,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _fetchTrees,
                                    child: const Text('重試'),
                                  ),
                                ],
                              ),
                            )
                          : _filteredTrees.isEmpty
                              ? const Center(
                                  child: Text(
                                    '沒有符合條件的樹木資料',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _fetchTrees,
                                  child: ListView.builder(
                                    itemCount: _filteredTrees.length,
                                    itemBuilder: (context, index) {
                                      final tree = _filteredTrees[index];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 8.0,
                                          vertical: 4.0,
                                        ),
                                        child: ListTile(
                                          leading: _isSelectionMode
                                              ? Checkbox(
                                                  value: _selectedIndices
                                                      .contains(index),
                                                  onChanged: (value) =>
                                                      _toggleSelection(index),
                                                )
                                              : const Icon(
                                                  Icons.park,
                                                  color: Colors.green,
                                                  size: 40,
                                                ),
                                          title: Text(
                                            tree['樹種名稱'] ?? '未知樹種',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  '專案: ${tree['專案名稱'] ?? '未知專案'}'),
                                              Text(
                                                  '區位: ${tree['專案區位'] ?? '未知區位'}'),
                                              if (_sortBy == '樹高（公尺）')
                                                Text(
                                                    '樹高: ${tree['樹高（公尺）']} 公尺'),
                                              if (_sortBy == '胸徑（公分）')
                                                Text(
                                                    '胸徑: ${tree['胸徑（公分）']} 公分'),
                                              if (_sortBy == '碳儲存量')
                                                Text('碳儲存量: ${tree['碳儲存量']}'),
                                              if (_sortBy == '推估年碳吸存量')
                                                Text(
                                                    '年碳吸存量: ${tree['推估年碳吸存量']}'),
                                            ],
                                          ),
                                          trailing: _isSelectionMode
                                              ? null
                                              : const Icon(Icons.chevron_right),
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
