import 'package:flutter/material.dart';
import '../services/audit_log_service.dart';
import '../services/locale_service.dart';

/// 稽核日誌（業務管理員以上）
class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  final AuditLogService _service = AuditLogService();
  final ScrollController _scroll = ScrollController();
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 &&
          !_loadingMore &&
          _hasMore) {
        _load(reset: false);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _offset = 0;
        _hasMore = true;
        _logs = [];
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final res = await _service.fetchLogs(limit: _pageSize, offset: _offset);
      if (res['success'] == true) {
        final batch = List<Map<String, dynamic>>.from(res['logs'] as List? ?? []);
        setState(() {
          if (reset) {
            _logs = batch;
          } else {
            _logs.addAll(batch);
          }
          _offset = _logs.length;
          _hasMore = batch.length >= _pageSize;
          _loading = false;
          _loadingMore = false;
        });
      } else {
        throw Exception(res['message'] ?? 'load failed');
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _t(String key) => LocaleService.instance.t(key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('audit_log_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(reset: true)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? Center(child: Text(_t('audit_log_empty')))
              : RefreshIndicator(
                  onRefresh: () => _load(reset: true),
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _logs.length + (_loadingMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i >= _logs.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final log = _logs[i];
                      return Card(
                        child: ListTile(
                          title: Text(
                            '${log['action'] ?? '—'} · ${log['username'] ?? '—'}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${log['created_at'] ?? ''}\n'
                            '${log['resource_type'] ?? ''} ${log['resource_id'] ?? ''}\n'
                            '${log['details'] ?? ''}',
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
