import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// [T8.2] IP 黑名單管理頁面（系統管理員專用）
///
/// 功能：
///  - 列出黑名單（active / permanent / expired）
///  - 顯示近 1 小時登入失敗 top 20 IP（提早預警）
///  - 手動加黑（指定原因 + 鎖多久 / 永久）
///  - 解除單筆封鎖
class IpBlacklistPage extends StatefulWidget {
  const IpBlacklistPage({super.key});

  @override
  State<IpBlacklistPage> createState() => _IpBlacklistPageState();
}

class _IpBlacklistPageState extends State<IpBlacklistPage> {
  bool _loading = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _stats = [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  // ===================== Network =====================

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        ApiService.get('admin/ip-blacklist'),
        ApiService.get('admin/ip-blacklist/stats'),
      ]);
      final listResp = results[0];
      final statsResp = results[1];

      if (listResp['success'] != true) {
        _errorMessage = listResp['message']?.toString() ?? '取得黑名單失敗';
      }

      final List<dynamic> list = (listResp['data'] as List?) ?? const [];
      final List<dynamic> stats = (statsResp['data'] as List?) ?? const [];

      if (!mounted) return;
      setState(() {
        _entries = list.cast<Map<String, dynamic>>();
        _stats = stats.cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '載入失敗: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _unblock(String ip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解除封鎖'),
        content: Text('確定要解除封鎖 IP「$ip」嗎？\n（將從黑名單刪除，但歷史保留在 audit log）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('確認解除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final resp = await ApiService.delete('admin/ip-blacklist/$ip');
    if (!mounted) return;
    final ok = resp['success'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(resp['message']?.toString() ?? (ok ? '已解除' : '解除失敗')),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );
    if (ok) await _refresh();
  }

  Future<void> _showAddDialog({String? presetIp}) async {
    final ipCtrl = TextEditingController(text: presetIp ?? '');
    final reasonCtrl = TextEditingController();
    int lockMinutes = 24 * 60; // 預設 24 小時
    bool permanent = false;

    const presets = <(String, int)>[
      ('5 分', 5),
      ('1 小時', 60),
      ('24 小時', 24 * 60),
      ('7 天', 7 * 24 * 60),
    ];

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('手動加入黑名單'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP 位址',
                    hintText: '例如 192.168.1.100',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '封鎖原因',
                    hintText: '例如 可疑爬蟲、暴力嘗試',
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('永久封鎖'),
                  value: permanent,
                  onChanged: (v) => setLocal(() => permanent = v ?? false),
                ),
                if (!permanent) ...[
                  const Text('鎖定時長：',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: presets.map((p) {
                      final selected = lockMinutes == p.$2;
                      return ChoiceChip(
                        label: Text(p.$1),
                        selected: selected,
                        onSelected: (_) => setLocal(() => lockMinutes = p.$2),
                      );
                    }).toList(),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('目前選擇：$lockMinutes 分鐘',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                final ip = ipCtrl.text.trim();
                final reason = reasonCtrl.text.trim();
                if (ip.isEmpty || reason.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('請輸入 IP 與原因')),
                  );
                  return;
                }
                final resp = await ApiService.post('admin/ip-blacklist', {
                  'ip': ip,
                  'reason': reason,
                  'lockMinutes': permanent ? null : lockMinutes,
                });
                if (!ctx.mounted) return;
                final ok = resp['success'] == true;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(resp['message']?.toString() ??
                        (ok ? '已加入黑名單' : '加入失敗')),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
                if (ok) Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('封鎖'),
            ),
          ],
        ),
      ),
    );

    if (added == true) await _refresh();
  }

  // ===================== Build =====================

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              _errorBanner(_errorMessage!),
            ],
            const SizedBox(height: 16),
            _buildBlacklistSection(),
            const SizedBox(height: 24),
            _buildStatsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'IP 黑名單管理',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 4),
              const Text(
                '管理被封鎖的 IP；自動入黑由 burstLimiter / 暴力登入偵測觸發。',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '重新整理',
          onPressed: _loading ? null : _refresh,
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('手動加黑'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _showAddDialog(),
        ),
      ],
    );
  }

  Widget _errorBanner(String msg) {
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
          Expanded(child: Text(msg, style: TextStyle(color: Colors.red.shade800))),
        ],
      ),
    );
  }

  Widget _buildBlacklistSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.shield, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  '黑名單（共 ${_entries.length} 筆）',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            if (_loading && _entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('目前沒有被封鎖的 IP', style: TextStyle(color: Colors.grey))),
              )
            else
              ..._entries.map(_buildEntryTile),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryTile(Map<String, dynamic> e) {
    final ip = e['ip']?.toString() ?? '';
    final status = e['status']?.toString() ?? 'unknown';
    final reason = e['reason']?.toString() ?? '';
    final offenseCount = e['offense_count'] ?? 0;
    final lockedUntil = e['locked_until']?.toString();
    final lastOffense = e['last_offense_at']?.toString() ?? '';

    final (Color color, String label) = switch (status) {
      'permanent' => (Colors.red.shade900, '永久封鎖'),
      'active' => (Colors.red, '封鎖中'),
      'expired' => (Colors.grey, '已過期'),
      _ => (Colors.grey, status),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: color, width: 4)),
        color: status == 'expired' ? Colors.grey.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SelectableText(
                      ip,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('累犯 $offenseCount 次',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('原因：$reason', style: const TextStyle(fontSize: 13)),
                if (lockedUntil != null && status != 'permanent')
                  Text('解除時間：${_formatTime(lockedUntil)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                Text('最近違規：${_formatTime(lastOffense)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            tooltip: '解除封鎖',
            icon: const Icon(Icons.lock_open, color: Colors.green),
            onPressed: () => _unblock(ip),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  '近 1 小時登入失敗 IP（top 20）',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(),
            if (_stats.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('過去 1 小時沒有登入失敗紀錄', style: TextStyle(color: Colors.grey)),
              )
            else
              Column(
                children: _stats.map((s) {
                  final ip = s['ip']?.toString() ?? '';
                  final cnt = s['failed_count'] ?? 0;
                  final last = s['last_attempt']?.toString() ?? '';
                  final danger = (cnt is int ? cnt : 0) >= 20;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      danger ? Icons.dangerous : Icons.error_outline,
                      color: danger ? Colors.red : Colors.orange,
                    ),
                    title: SelectableText(ip),
                    subtitle: Text('最後嘗試：${_formatTime(last)}',
                        style: const TextStyle(fontSize: 12)),
                    trailing: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('$cnt 次',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: danger ? Colors.red : Colors.orange,
                            )),
                        TextButton(
                          onPressed: () => _showAddDialog(presetIp: ip),
                          child: const Text('加黑'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)} '
          '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
    } catch (_) {
      return raw;
    }
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
