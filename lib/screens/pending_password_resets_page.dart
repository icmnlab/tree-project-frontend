import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/password_reset_service.dart';
import '../services/locale_service.dart';
import '../constants/colors.dart';

class PendingPasswordResetsPage extends StatefulWidget {
  const PendingPasswordResetsPage({super.key});

  @override
  State<PendingPasswordResetsPage> createState() =>
      _PendingPasswordResetsPageState();
}

class _PendingPasswordResetsPageState extends State<PendingPasswordResetsPage> {
  final _service = PasswordResetService();
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.listPending();
      if (!mounted) return;
      setState(() {
        _pending = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('pwd_code_copied'))),
    );
  }

  String _formatTime(dynamic v) {
    if (v == null) return '';
    return v.toString().replaceFirst('T', ' ').split('.').first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('pwd_pending_title')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _load,
                        child: Text(context.tr('retry')),
                      ),
                    ],
                  ),
                )
              : _pending.isEmpty
                  ? Center(child: Text(context.tr('pwd_pending_empty')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _pending.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final row = _pending[i];
                          final code =
                              row['reset_code']?.toString() ?? '—';
                          return Card(
                            child: ListTile(
                              title: Text(row['username']?.toString() ?? ''),
                              subtitle: Text(
                                '${row['display_name'] ?? ''}\n'
                                '${context.tr('pwd_expires')}: ${_formatTime(row['expires_at'])}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    code,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                      color: AppColors.portBlue,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy),
                                    tooltip: context.tr('pwd_copy_code'),
                                    onPressed: code == '—'
                                        ? null
                                        : () => _copyCode(code),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
