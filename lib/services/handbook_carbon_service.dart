import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// 農業部《森林碳匯調查與監測手冊》第六章 — 單木碳儲量（與後端 handbookCarbonService 對齊）
class HandbookCarbonService {
  static Map<String, dynamic>? _volumeDoc;
  static bool _loadAttempted = false;

  static const double _co2PerC = 44 / 12;
  static const double _piOver4 = 0.79;

  static const Map<String, Map<String, double>> _table64 = {
    '天然針葉林': {'D': 0.41, 'BEF': 1.27, 'BCEF': 0.51, 'R': 0.22, 'CF': 0.4821},
    '天然針闊葉混淆林': {'D': 0.49, 'BEF': 1.34, 'BCEF': 0.72, 'R': 0.23, 'CF': 0.4756},
    '天然闊葉林': {'D': 0.56, 'BEF': 1.40, 'BCEF': 0.92, 'R': 0.24, 'CF': 0.4691},
    '人工針葉林': {'D': 0.41, 'BEF': 1.27, 'BCEF': 0.51, 'R': 0.22, 'CF': 0.4821},
    '人工針闊葉混淆林': {'D': 0.49, 'BEF': 1.34, 'BCEF': 0.72, 'R': 0.23, 'CF': 0.4756},
    '人工闊葉林': {'D': 0.56, 'BEF': 1.40, 'BCEF': 0.92, 'R': 0.24, 'CF': 0.4691},
    '木竹混淆林': {'D': 0.49, 'BEF': 1.34, 'BCEF': 0.72, 'R': 0.23, 'CF': 0.4756},
    '竹林': {'D': 0.62, 'BEF': 1.40, 'R': 0.46, 'CF': 0.4732},
  };

  static const String _defaultForestType = '天然闊葉林';

  /// 啟動時呼叫（main.dart），確保材積式表已載入
  static Future<void> preload() async {
    if (_volumeDoc != null) return;
    try {
      final raw = await rootBundle
          .loadString('assets/coa/coa_volume_equations.json');
      _volumeDoc = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _volumeDoc = {'entries': <dynamic>[]};
    }
    _loadAttempted = true;
  }

  static String _norm(String? s) =>
      (s ?? '').trim().replaceAll('臺', '台');

  static double calculateCarbonStorage(
    String species,
    double heightM,
    double dbhCm, {
    String? forestType,
    String? region,
    String? climateZone,
  }) {
    if (dbhCm <= 0 || heightM <= 0) return 0;
    final ft = forestType ?? _inferForestType(species);
    final coeffs = _table64[ft] ?? _table64[_defaultForestType]!;
    final vol = _estimateVolume(species, dbhCm, heightM,
        forestType: ft, region: region, climateZone: climateZone);
    if (vol <= 0) return 0;
    final agb = vol * coeffs['D']! * coeffs['BEF']!;
    final tb = agb * (1 + coeffs['R']!);
    final carbonT = tb * coeffs['CF']!;
    final co2eKg = carbonT * _co2PerC * 1000;
    return double.parse(co2eKg.toStringAsFixed(2));
  }

  static String _inferForestType(String species) {
    final n = _norm(species);
    const bamboo = ['桂竹', '孟宗竹', '綠竹', '毛竹'];
    for (final b in bamboo) {
      if (n.contains(b)) return '竹林';
    }
    if (n.contains('松') ||
        n.contains('柏') ||
        n.contains('杉') ||
        n.contains('檜') ||
        n.endsWith('松') ||
        n.endsWith('柏') ||
        n.endsWith('杉')) {
      return '天然針葉林';
    }
    final hints = (_volumeDoc?['conifer_species_hints'] as List?)?.cast<String>();
    if (hints != null) {
      for (final c in hints) {
        final cn = _norm(c);
        if (n == cn || n.contains(cn) || cn.contains(n)) return '天然針葉林';
      }
    }
    return _defaultForestType;
  }

  static double _estimateVolume(
    String species,
    double dbh,
    double h, {
    required String forestType,
    String? region,
    String? climateZone,
  }) {
    final ranked = _rankEntries(species, region: region, climateZone: climateZone);
    for (final entry in ranked) {
      final v = _evalEq(entry, dbh, h);
      if (v != null && v > 0) return v;
    }
    final isConifer = forestType.contains('針葉');
    final f = isConifer ? 0.5 : 0.45;
    return _piOver4 * dbh * dbh * h * f * 0.0001;
  }

  static List<Map<String, dynamic>> _rankEntries(
    String species, {
    String? region,
    String? climateZone,
  }) {
    if (!_loadAttempted) return [];
    final entries = (_volumeDoc?['entries'] as List?)?.cast<Map<String, dynamic>>();
    if (entries == null) return [];
    final sn = _norm(species);
    final scored = <MapEntry<Map<String, dynamic>, int>>[];
    for (final e in entries) {
      final labels = (e['species_labels'] as List?)?.cast<String>() ?? [];
      var labelScore = 999;
      for (final lbl in labels) {
        final ln = _norm(lbl);
        if (sn == ln) {
          labelScore = 0;
        } else if (sn.contains(ln) || ln.contains(sn)) {
          labelScore = math.min(labelScore, 10);
        }
      }
      if (labelScore >= 999) continue;
      final isOther = (e['species_labels'] as List?)?.any(
            (l) => _norm(l.toString()).contains('其他'),
          ) ??
          false;
      if (isOther && !sn.contains('其他')) labelScore += 22;
      var regionPenalty = 0;
      final er = (e['region'] as String?) ?? '全臺';
      if (region != null) {
        final wr = _norm(region);
        if (er != wr && er != '全臺') continue;
        if (er == '全臺') regionPenalty = 5;
      } else if (er != '全臺') {
        regionPenalty = 12;
      }
      final cz = e['climate_zone'] as String?;
      if (climateZone != null) {
        if (cz != null && cz != climateZone) continue;
      } else if (cz != null) {
        regionPenalty += 15;
      }
      final score = (e['priority'] as int? ?? 50) + labelScore + regionPenalty;
      scored.add(MapEntry(e, score));
    }
    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.map((e) => e.key).toList();
  }

  static double? _evalEq(Map<String, dynamic> eq, double d, double h) {
    final type = eq['type'] as String?;
    switch (type) {
      case 'power':
        return (eq['a'] as num).toDouble() *
            math.pow(d, (eq['b'] as num).toDouble()) *
            math.pow(h, (eq['c'] as num).toDouble());
      case 'quadratic':
        return (eq['a'] as num).toDouble() +
            (eq['b'] as num).toDouble() * d +
            (eq['c'] as num).toDouble() * d * d;
      case 'quadratic_dh':
        return (eq['a'] as num).toDouble() +
            (eq['b'] as num).toDouble() * d +
            (eq['c'] as num).toDouble() * d * d +
            ((eq['d'] as num?)?.toDouble() ?? 0) * d * h;
      case 'linear_dh':
        return (eq['a'] as num).toDouble() * d * h;
      case 'log_d_h':
        var inner = (eq['a'] as num).toDouble() +
            (eq['b'] as num).toDouble() * math.log(d) / math.ln10 +
            (eq['c'] as num).toDouble() * math.log(h) / math.ln10;
        var v = math.pow(10, inner).toDouble();
        if (eq['v_times_10'] == true) v /= 10;
        return v;
      case 'log_d':
        final inner = (eq['a'] as num).toDouble() +
            (eq['b'] as num).toDouble() * math.log(d) / math.ln10;
        return math.pow(10, inner).toDouble();
      case 'log_d2h':
        final inner = (eq['a'] as num).toDouble() +
            (eq['b'] as num).toDouble() * math.log(d * d * h) / math.ln10;
        return math.pow(10, inner).toDouble();
      case 'cubic_d':
        return (eq['a'] as num).toDouble() +
            ((eq['e'] as num?)?.toDouble() ?? 0) * math.pow(d, 3);
      case 'ln_d_h_d2':
        final inner = (eq['a'] as num).toDouble() +
            (eq['b'] as num).toDouble() * math.log(d) +
            (eq['c'] as num).toDouble() * math.log(h) +
            ((eq['d'] as num?)?.toDouble() ?? 0) * d * d;
        return math.exp(inner);
      default:
        return null;
    }
  }
}
