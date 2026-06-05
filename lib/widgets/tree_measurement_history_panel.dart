import 'package:flutter/material.dart';
import '../services/tree_measurement_history_service.dart';

/// 歷次量測時間序列（最新在上）
class TreeMeasurementHistoryPanel extends StatefulWidget {
  final int treeId;
  final int limit;

  const TreeMeasurementHistoryPanel({
    super.key,
    required this.treeId,
    this.limit = 15,
  });

  @override
  State<TreeMeasurementHistoryPanel> createState() =>
      _TreeMeasurementHistoryPanelState();
}

class _TreeMeasurementHistoryPanelState
    extends State<TreeMeasurementHistoryPanel> {
  final _service = TreeMeasurementHistoryService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

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
      final rows =
          await _service.fetchByTreeId(widget.treeId, limit: widget.limit);
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  String _fmtTime(dynamic v) {
    if (v == null) return '—';
    final s = v.toString();
    final dt = DateTime.tryParse(s);
    if (dt == null) return s.length > 16 ? s.substring(0, 16) : s;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_error != null) {
      return ListTile(
        title: Text('無法載入歷史紀錄', style: TextStyle(color: Colors.red.shade700)),
        subtitle: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      );
    }
    if (_rows.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('尚無歷次量測紀錄', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._rows.map((r) {
          final mode = r['survey_mode']?.toString() ?? 'new';
          final isMaint = mode == 'maintenance';
          return ListTile(
            dense: true,
            leading: Icon(
              isMaint ? Icons.build_circle_outlined : Icons.forest_outlined,
              color: isMaint ? Colors.orange.shade700 : Colors.teal,
            ),
            title: Text(
              '${_fmtTime(r['survey_time'])} · '
              'H ${r['tree_height_m'] ?? '—'} m · '
              'DBH ${r['dbh_cm'] ?? '—'} cm',
            ),
            subtitle: Text(
              [
                if (r['species_name'] != null) r['species_name'].toString(),
                if (isMaint) '維護重測' else '初測',
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }),
        if (_rows.length >= widget.limit)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              '僅顯示最近 ${widget.limit} 筆',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
      ],
    );
  }
}
