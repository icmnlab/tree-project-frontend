import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../services/tree_measurement_history_service.dart';

/// 歷次量測時間軸（最新在上）
class TreeMeasurementHistoryPanel extends StatefulWidget {
  final int treeId;
  final int initialLimit;
  final bool compact;

  const TreeMeasurementHistoryPanel({
    super.key,
    required this.treeId,
    this.initialLimit = 15,
    this.compact = false,
  });

  @override
  State<TreeMeasurementHistoryPanel> createState() =>
      _TreeMeasurementHistoryPanelState();
}

class _TreeMeasurementHistoryPanelState
    extends State<TreeMeasurementHistoryPanel> {
  final _service = TreeMeasurementHistoryService();
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  int _limit = 15;

  @override
  void initState() {
    super.initState();
    _limit = widget.initialLimit;
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final result = await _service.fetchByTreeId(
        widget.treeId,
        limit: _limit,
        offset: reset ? 0 : _rows.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _rows = result.rows;
        } else {
          _rows = [..._rows, ...result.rows];
        }
        _total = result.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _loadingMore = false;
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

  String? _delta(num? current, num? previous, String unit) {
    if (current == null || previous == null) return null;
    final d = current - previous;
    if (d.abs() < 0.05) return null;
    final sign = d > 0 ? '+' : '';
    return '$sign${d.toStringAsFixed(1)} $unit';
  }

  String _modeLabel(String mode) {
    switch (mode) {
      case 'maintenance':
        return context.tr('history_mode_maint');
      case 'snapshot':
        return context.tr('history_mode_snapshot');
      case 'new':
      default:
        return context.tr('history_mode_new');
    }
  }

  Color _modeColor(String mode) {
    switch (mode) {
      case 'maintenance':
        return Colors.orange.shade700;
      case 'snapshot':
        return Colors.blueGrey;
      default:
        return Colors.teal;
    }
  }

  Widget _modeChip(String mode) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _modeColor(mode).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _modeColor(mode).withValues(alpha: 0.4)),
      ),
      child: Text(
        _modeLabel(mode),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _modeColor(mode),
        ),
      ),
    );
  }

  Widget _buildRow(int index) {
    final r = _rows[index];
    final mode = r['survey_mode']?.toString() ?? 'new';
    final prev = index + 1 < _rows.length ? _rows[index + 1] : null;
    final h = r['tree_height_m'];
    final dbh = r['dbh_cm'];
    final hPrev = prev?['tree_height_m'];
    final dbhPrev = prev?['dbh_cm'];
    final hDelta = _delta(
      h is num ? h : double.tryParse(h?.toString() ?? ''),
      hPrev is num ? hPrev : double.tryParse(hPrev?.toString() ?? ''),
      'm',
    );
    final dbhDelta = _delta(
      dbh is num ? dbh : double.tryParse(dbh?.toString() ?? ''),
      dbhPrev is num ? dbhPrev : double.tryParse(dbhPrev?.toString() ?? ''),
      'cm',
    );

    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            _modeChip(mode),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_fmtTime(r['survey_time'])} · H $h · DBH $dbh',
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // 外層卡片帶底色/陰影，這裡補一層透明 Material，讓 ExpansionTile 標題列的
    // 水波紋/底色有正確的 Material 祖先（否則會被外層 DecoratedBox 蓋住而觸發警告）。
    return Material(
      color: Colors.transparent,
      child: ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            mode == 'maintenance'
                ? Icons.build_circle_outlined
                : Icons.forest_outlined,
            color: _modeColor(mode),
            size: 22,
          ),
        ],
      ),
      title: Text(
        _fmtTime(r['survey_time']),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(
            'H ${h ?? '—'} m · DBH ${dbh ?? '—'} cm',
            style: const TextStyle(fontSize: 13),
          ),
          if (hDelta != null || dbhDelta != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                if (hDelta != null)
                  Chip(
                    label: Text('H $hDelta', style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                if (dbhDelta != null)
                  Chip(
                    label:
                        Text('DBH $dbhDelta', style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ],
        ],
      ),
      trailing: _modeChip(mode),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r['species_name'] != null)
                Text('${context.tr('history_species')}: ${r['species_name']}'),
              if (r['status'] != null && r['status'].toString().isNotEmpty)
                Text('${context.tr('history_status')}: ${r['status']}'),
              if (r['carbon_storage'] != null)
                Text(
                  '${context.tr('history_carbon')}: ${r['carbon_storage']}',
                ),
              if (r['x_coord'] != null && r['y_coord'] != null)
                Text(
                  '${context.tr('history_coords')}: '
                  '${r['y_coord']}, ${r['x_coord']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              if (r['survey_notes'] != null &&
                  r['survey_notes'].toString().trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    r['survey_notes'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade800,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: widget.compact ? 8 : 12),
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
        dense: widget.compact,
        title: Text(
          context.tr('history_load_error'),
          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
        ),
        subtitle: Text(_error!, maxLines: 2, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => _load(reset: true),
        ),
      );
    }
    if (_rows.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(widget.compact ? 8 : 12),
        child: Text(
          context.tr('history_empty'),
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.compact && _total > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 4),
            child: Text(
              context
                  .tr('history_count')
                  .replaceAll('{n}', '$_total'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ...List.generate(
          widget.compact ? _rows.length.clamp(0, 3) : _rows.length,
          _buildRow,
        ),
        if (!widget.compact && _rows.length < _total)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _loadingMore
                ? const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton.icon(
                    onPressed: () => _load(reset: false),
                    icon: const Icon(Icons.expand_more),
                    label: Text(
                      context
                          .tr('history_load_more')
                          .replaceAll('{left}', '${_total - _rows.length}'),
                    ),
                  ),
          ),
      ],
    );
  }
}
