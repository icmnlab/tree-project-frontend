import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../services/api_service.dart';
import '../constants/colors.dart';

/// CSV 匯入頁面 — 自動適配手機/電腦螢幕
class CsvImportPage extends StatefulWidget {
  const CsvImportPage({super.key});

  @override
  State<CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends State<CsvImportPage> {
  bool _isUploading = false;
  bool _isImporting = false;
  String? _fileName;
  Map<String, dynamic>? _previewData;
  String? _errorMessage;
  Map<String, dynamic>? _importReport;
  bool _importFailed = false;

  // ===================== 上傳並預覽 =====================
  Future<void> _pickAndPreview() async {
    // 使用 FileType.any 避免 Android 上 CSV MIME type 不被辨識的問題
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    // 手動驗證副檔名
    final ext = file.name.split('.').last.toLowerCase();
    if (ext != 'csv') {
      setState(() => _errorMessage = '請選擇 CSV 檔案（目前選擇的是 .$ext）');
      return;
    }

    if (file.bytes == null) {
      setState(() => _errorMessage = '無法讀取檔案');
      return;
    }

    setState(() {
      _isUploading = true;
      _errorMessage = null;
      _previewData = null;
      _importReport = null;
      _importFailed = false;
      _fileName = file.name;
    });

    try {
      final uri = Uri.parse('${ApiService.baseUrl}/admin/import-csv/preview');
      final request = http.MultipartRequest('POST', uri);

      // 加入 JWT auth header
      final headers = ApiService.getAuthHeaders();
      request.headers.addAll(headers);

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('text', 'csv'),
      ));

      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode != 200) {
        // 嘗試解析 JSON 錯誤訊息
        try {
          final errData = jsonDecode(responseBody) as Map<String, dynamic>;
          setState(() => _errorMessage = errData['message'] ?? '伺服器錯誤 (${streamedResponse.statusCode})');
        } catch (_) {
          setState(() => _errorMessage = '伺服器錯誤 (${streamedResponse.statusCode}): $responseBody');
        }
        return;
      }

      final data = jsonDecode(responseBody) as Map<String, dynamic>;

      if (data['success'] == true) {
        setState(() => _previewData = data['preview']);
      } else {
        setState(() => _errorMessage = data['message'] ?? '預覽失敗');
      }
    } catch (e) {
      setState(() => _errorMessage = '上傳失敗: $e');
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ===================== 執行匯入 =====================
  Future<void> _executeImport() async {
    if (_previewData == null) return;

    setState(() {
      _isImporting = true;
      _errorMessage = null;
    });

    try {
      final response = await ApiService.post('admin/import-csv/execute', {
        'newRecords': _previewData!['newRecords'],
        'updatedRecords': _previewData!['updatedRecords'],
      });

      if (response['success'] == true) {
        setState(() {
          _importReport = response['report'];
          _importFailed = false;
          _previewData = null;
        });
      } else {
        final report = response['report'];
        setState(() {
          _errorMessage = response['message'] ?? '匯入失敗';
          _importFailed = true;
          if (report is Map<String, dynamic>) {
            _importReport = report;
          }
        });
      }
    } catch (e) {
      setState(() => _errorMessage = '匯入失敗: $e');
    } finally {
      setState(() => _isImporting = false);
    }
  }

  // ===================== 重置 =====================
  void _reset() {
    setState(() {
      _previewData = null;
      _importReport = null;
      _importFailed = false;
      _errorMessage = null;
      _fileName = null;
    });
  }

  // ===================== Build =====================
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildUploadSection(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                _buildErrorBanner(),
              ],
              if (_previewData != null) ...[
                const SizedBox(height: 16),
                _buildSummaryCards(isWide),
                const SizedBox(height: 16),
                if (isWide) _buildWidePreview() else _buildMobilePreview(),
                const SizedBox(height: 16),
                _buildConfirmButton(),
              ],
              if (_importReport != null) ...[
                const SizedBox(height: 16),
                _buildImportReport(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CSV 資料匯入',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          '上傳港務公司格式的 CSV 檔案，系統將自動偵測重複資料、極端值，並顯示匯入預覽。'
          '執行匯入時若任一笔失敗，整批會自動復原（不寫入資料庫）。',
          style: TextStyle(color: Colors.grey[600], fontSize: 14),
        ),
      ],
    );
  }

  Widget _buildUploadSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isUploading ? null : _pickAndPreview,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.blue.shade200,
              width: 2,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            children: [
              if (_isUploading)
                const CircularProgressIndicator()
              else
                Icon(Icons.cloud_upload_outlined,
                    size: 48, color: Colors.blue.shade400),
              const SizedBox(height: 12),
              Text(
                _fileName ?? '點擊選擇 CSV 檔案',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: _fileName != null ? Colors.green.shade700 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '支援 .csv 格式，上限 50MB',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(bool isWide) {
    final summary = _previewData!['summary'] as Map<String, dynamic>;
    final cards = [
      _summaryCard('總筆數', summary['total'], Colors.grey),
      _summaryCard('新增', summary['new'], Colors.green),
      _summaryCard('更新', summary['update'], Colors.blue),
      _summaryCard('重複', summary['duplicate'], Colors.orange),
      _summaryCard('異常', summary['outlier'], Colors.amber.shade700),
      _summaryCard('錯誤', summary['error'], Colors.red),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map((c) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: c)))
            .toList(),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cards.map((c) => SizedBox(width: 100, child: c)).toList(),
    );
  }

  Widget _summaryCard(String label, dynamic count, Color color) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Column(
          children: [
            Text(
              '${count ?? 0}',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }

  // ===================== 寬螢幕預覽 =====================
  Widget _buildWidePreview() {
    final newRecs = _previewData!['newRecords'] as List? ?? [];
    final updates = _previewData!['updatedRecords'] as List? ?? [];
    final dupes = _previewData!['duplicates'] as List? ?? [];
    final outliers = _previewData!['outliers'] as List? ?? [];
    final errors = _previewData!['errors'] as List? ?? [];

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: '新增'),
              Tab(text: '更新'),
              Tab(text: '重複'),
              Tab(text: '異常值'),
              Tab(text: '錯誤'),
            ],
          ),
          SizedBox(
            height: 400,
            child: TabBarView(
              children: [
                _buildRecordTable(newRecs, Colors.green.shade50),
                _buildRecordTable(updates, Colors.blue.shade50),
                _buildRecordTable(dupes, Colors.orange.shade50),
                _buildOutlierList(outliers),
                _buildErrorList(errors),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===================== 手機預覽 =====================
  Widget _buildMobilePreview() {
    final summary = _previewData!['summary'] as Map<String, dynamic>;
    final outliers = _previewData!['outliers'] as List? ?? [];
    final errors = _previewData!['errors'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (outliers.isNotEmpty) ...[
          const Text('異常值記錄', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...outliers.take(5).map((o) => _buildOutlierCard(o)),
          if (outliers.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('... 還有 ${outliers.length - 5} 筆',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
          const SizedBox(height: 16),
        ],
        if (errors.isNotEmpty) ...[
          const Text('錯誤記錄', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.red)),
          const SizedBox(height: 8),
          ...errors.take(5).map((e) => _buildErrorCard(e)),
          if (errors.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('... 還有 ${errors.length - 5} 筆',
                  style: TextStyle(color: Colors.grey.shade600)),
            ),
        ],
        if (outliers.isEmpty && errors.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '資料品質良好！共 ${summary['new']} 筆新增、${summary['update']} 筆更新。',
                    style: TextStyle(color: Colors.green.shade800),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildRecordTable(List records, Color bgColor) {
    if (records.isEmpty) {
      return const Center(child: Text('無記錄'));
    }

    return Container(
      color: bgColor,
      child: ListView.separated(
        itemCount: records.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, idx) {
          final rec = records[idx];
          final data = rec['data'] as Map<String, dynamic>? ?? rec;
          final row = rec['row'] ?? (idx + 1);
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade300,
              child: Text('$row', style: const TextStyle(fontSize: 11)),
            ),
            title: Text(
              '${data['project_name'] ?? ''} | ${data['species_name'] ?? ''}',
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              '代碼: ${data['project_code'] ?? ''} | 胸徑: ${data['dbh_cm'] ?? '-'} cm | 樹高: ${data['tree_height_m'] ?? '-'} m',
              style: const TextStyle(fontSize: 11),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOutlierList(List outliers) {
    if (outliers.isEmpty) return const Center(child: Text('無異常值'));
    return ListView.builder(
      itemCount: outliers.length,
      itemBuilder: (ctx, idx) => _buildOutlierCard(outliers[idx]),
    );
  }

  Widget _buildOutlierCard(dynamic outlier) {
    final row = outlier['row'];
    final items = outlier['outliers'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.amber.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('第 $row 列', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...items.map((o) => Text(
                  '${o['field']}: ${o['value']} (正常範圍 ${o['range']})',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorList(List errors) {
    if (errors.isEmpty) return const Center(child: Text('無錯誤'));
    return ListView.builder(
      itemCount: errors.length,
      itemBuilder: (ctx, idx) => _buildErrorCard(errors[idx]),
    );
  }

  Widget _buildErrorCard(dynamic error) {
    final row = error['row'];
    final errs = error['errors'] as List? ?? [];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('第 $row 列', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            ...errs.map((e) => Text(
                  e.toString(),
                  style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmButton() {
    final summary = _previewData!['summary'] as Map<String, dynamic>;
    final total = (summary['new'] ?? 0) + (summary['update'] ?? 0);

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.close),
            label: const Text('取消'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isImporting || total == 0 ? null : _executeImport,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle),
            label: Text(_isImporting ? '匯入中...' : '確認匯入 $total 筆'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.forestGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportReport() {
    final report = _importReport!;
    final errors = report['errors'] as List? ?? [];
    final failed = _importFailed;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle,
                  color: failed ? Colors.red.shade700 : Colors.green.shade700,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    failed ? '匯入已復原（未寫入）' : '匯入完成',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: failed
                          ? Colors.red.shade800
                          : Colors.green.shade800,
                    ),
                  ),
                ),
              ],
            ),
            if (failed) ...[
              const SizedBox(height: 8),
              Text(
                '有部分列無法寫入，系統已執行 ROLLBACK，資料庫維持匯入前狀態。請修正下列錯誤後再試。',
                style: TextStyle(fontSize: 13, color: Colors.red.shade900),
              ),
            ],
            const Divider(height: 24),
            if (!failed) ...[
              _reportRow('新增成功', report['inserted'], Colors.green),
              _reportRow('更新成功', report['updated'], Colors.blue),
              _reportRow('略過', report['skipped'], Colors.grey),
            ],
            if (errors.isNotEmpty) _reportRow('失敗', errors.length, Colors.red),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '錯誤明細',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: ListView.builder(
                  itemCount: errors.length,
                  itemBuilder: (ctx, idx) {
                    final err = errors[idx];
                    if (err is! Map) {
                      return ListTile(
                        dense: true,
                        title: Text(err.toString()),
                      );
                    }
                    final row = err['row'];
                    final msg = err['error'] ?? err['errors'];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      color: Colors.red.shade50,
                      child: ListTile(
                        dense: true,
                        title: Text('第 $row 列',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          msg is List ? msg.join('；') : msg?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.refresh),
                label: Text(failed ? '修正後重新匯入' : '匯入更多資料'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(String label, dynamic count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(
            '${count ?? 0} 筆',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}
