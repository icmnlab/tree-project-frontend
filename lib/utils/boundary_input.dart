/// boundary_input.dart — 邊界「直接鍵入座標」的解析與健檢工具（純函式、可單元測試）
///
/// 對應環境學院需求方式 1：使用者貼上座標清單。
/// 統一輸出 [[lat, lng], ...]（與 project_boundaries 儲存格式一致）。
///
/// 設計重點：
/// 1. 容錯解析：支援每行一組、含括號 (lng, lat)、空白/逗號/Tab 分隔；忽略標頭。
/// 2. 順序偵測：台灣經度約 120（絕對值 > 90），緯度約 23（<= 90），可穩健判斷
///    每組是 (lng,lat) 或 (lat,lng)；無法判斷時採用 assumedOrder。
/// 3. 明確回報無法解析的行（含行號），不靜默吞掉（學院範例曾出現格式異常列）。
/// 4. 自相交偵測 + 依極角重排，協助修正非四方形時的非預期範圍。

import 'dart:math' as math;

/// 使用者宣告/假設的座標順序（用於無法由數值判斷時）
enum CoordOrder { lngLat, latLng }

class BoundaryParseResult {
  final bool ok;
  final List<List<double>> coordinates; // [[lat, lng], ...]
  final CoordOrder? detectedOrder;
  final bool mixedOrder;
  final bool selfIntersecting;
  final List<String> warnings;
  final List<String> errors;

  const BoundaryParseResult({
    required this.ok,
    this.coordinates = const [],
    this.detectedOrder,
    this.mixedOrder = false,
    this.selfIntersecting = false,
    this.warnings = const [],
    this.errors = const [],
  });
}

class BoundaryInputParser {
  static final RegExp _numberRe = RegExp(r'-?\d+(?:\.\d+)?');

  /// 解析使用者貼上的座標文字。
  /// [assumedOrder]：當某組座標兩值皆無法由範圍判斷時採用（預設 lng,lat，符合學院範例）。
  static BoundaryParseResult parse(
    String text, {
    CoordOrder assumedOrder = CoordOrder.lngLat,
  }) {
    final warnings = <String>[];
    final errors = <String>[];
    final coords = <List<double>>[];
    final detectedOrders = <CoordOrder>{};

    final lines = text.split(RegExp(r'[\r\n]+'));
    var lineNo = 0;
    for (final rawLine in lines) {
      lineNo++;
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final matches = _numberRe.allMatches(line).map((m) => m.group(0)!).toList();
      if (matches.isEmpty) {
        // 可能是標頭/說明文字，略過但不報錯
        continue;
      }
      if (matches.length < 2) {
        errors.add('第 $lineNo 行只找到一個數值，已略過：「$line」');
        continue;
      }
      // 取前兩個數值（第三個視為高度忽略）
      final a = double.tryParse(matches[0]);
      final b = double.tryParse(matches[1]);
      if (a == null || b == null) {
        errors.add('第 $lineNo 行數值無法解析，已略過：「$line」');
        continue;
      }

      double lat;
      double lng;
      final aAbs = a.abs();
      final bAbs = b.abs();
      if (aAbs > 90 && bAbs <= 90) {
        lng = a;
        lat = b;
        detectedOrders.add(CoordOrder.lngLat);
      } else if (bAbs > 90 && aAbs <= 90) {
        lat = a;
        lng = b;
        detectedOrders.add(CoordOrder.latLng);
      } else {
        // 兩值皆 <=90（或皆 >90）→ 無法判斷，採用 assumedOrder
        if (assumedOrder == CoordOrder.lngLat) {
          lng = a;
          lat = b;
        } else {
          lat = a;
          lng = b;
        }
      }

      if (lat.abs() > 90 || lng.abs() > 180) {
        final hint = _decimalRepairHint(matches[0]) + _decimalRepairHint(matches[1]);
        errors.add('第 $lineNo 行座標超出合理範圍（lat=$lat, lng=$lng），已略過$hint');
        continue;
      }
      coords.add([lat, lng]);
    }

    // 去除重複收尾點（首尾相同 → 開放環）
    if (coords.length >= 2) {
      final first = coords.first;
      final last = coords.last;
      if ((first[0] - last[0]).abs() < 1e-9 && (first[1] - last[1]).abs() < 1e-9) {
        coords.removeLast();
      }
    }

    if (coords.length < 3) {
      return BoundaryParseResult(
        ok: false,
        coordinates: coords,
        errors: [...errors, '有效頂點不足 3 個（目前 ${coords.length} 個），無法構成邊界'],
        warnings: warnings,
      );
    }

    final mixed = detectedOrders.length > 1;
    if (mixed) {
      warnings.add('偵測到座標順序不一致（同時出現 lng,lat 與 lat,lng），請確認來源格式。');
    }

    final selfIntersect = isSelfIntersecting(coords);
    if (selfIntersect) {
      warnings.add('座標連線自相交，地圖上可能出現非預期範圍，建議使用「依角度重排」或調整順序。');
    }

    return BoundaryParseResult(
      ok: true,
      coordinates: coords,
      detectedOrder: detectedOrders.length == 1 ? detectedOrders.first : null,
      mixedOrder: mixed,
      selfIntersecting: selfIntersect,
      warnings: warnings,
      errors: errors,
    );
  }

  /// 防呆提示：偵測「缺少小數點」的數值（例如 1201240910 應為 120.1240910）。
  /// 僅回傳提示字串供使用者確認，不自動竄改資料（避免影響正常邏輯）。
  static String _decimalRepairHint(String token) {
    if (token.contains('.')) return '';
    final neg = token.startsWith('-');
    final digits = token.replaceAll('-', '');
    if (digits.length < 4) return '';
    // 台灣經度 119–122（整數 3 位）、緯度 21–26（整數 2 位）
    for (final intLen in [3, 2]) {
      if (digits.length > intLen) {
        final cand = double.tryParse(
          '${neg ? '-' : ''}${digits.substring(0, intLen)}.${digits.substring(intLen)}',
        );
        if (cand != null && cand.abs() <= 180) {
          return '（疑似缺少小數點，應為 $cand？請確認後修正）';
        }
      }
    }
    return '';
  }

  /// 依相對中心點的極角重排（適合凸多邊形/順序錯亂的點集）。
  /// 回傳新的 [[lat,lng], ...]。
  static List<List<double>> reorderByAngle(List<List<double>> coords) {
    if (coords.length < 3) return coords;
    double cy = 0;
    double cx = 0;
    for (final c in coords) {
      cy += c[0];
      cx += c[1];
    }
    cy /= coords.length;
    cx /= coords.length;
    final sorted = [...coords];
    sorted.sort((p, q) {
      final ap = math.atan2(p[0] - cy, p[1] - cx);
      final aq = math.atan2(q[0] - cy, q[1] - cx);
      return ap.compareTo(aq);
    });
    return sorted;
  }

  /// 自相交偵測：檢查多邊形（閉合）是否有不相鄰邊相交。
  static bool isSelfIntersecting(List<List<double>> coords) {
    final n = coords.length;
    if (n < 4) return false;
    // 邊 i: coords[i] → coords[(i+1)%n]
    for (int i = 0; i < n; i++) {
      final a1 = coords[i];
      final a2 = coords[(i + 1) % n];
      for (int j = i + 1; j < n; j++) {
        // 跳過相鄰邊與共端點邊
        if (j == i) continue;
        if ((j + 1) % n == i) continue;
        if (i == (j + 1) % n) continue;
        if (j == (i + 1) % n) continue;
        final b1 = coords[j];
        final b2 = coords[(j + 1) % n];
        if (_segmentsIntersect(a1, a2, b1, b2)) return true;
      }
    }
    return false;
  }

  static double _cross(List<double> o, List<double> a, List<double> b) {
    // 以 (lng=x, lat=y)
    return (a[1] - o[1]) * (b[0] - o[0]) - (a[0] - o[0]) * (b[1] - o[1]);
  }

  static bool _onSegment(List<double> p, List<double> q, List<double> r) {
    return q[1] <= math.max(p[1], r[1]) &&
        q[1] >= math.min(p[1], r[1]) &&
        q[0] <= math.max(p[0], r[0]) &&
        q[0] >= math.min(p[0], r[0]);
  }

  static bool _segmentsIntersect(
      List<double> p1, List<double> p2, List<double> p3, List<double> p4) {
    final d1 = _cross(p3, p4, p1);
    final d2 = _cross(p3, p4, p2);
    final d3 = _cross(p1, p2, p3);
    final d4 = _cross(p1, p2, p4);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    if (d1 == 0 && _onSegment(p3, p1, p4)) return true;
    if (d2 == 0 && _onSegment(p3, p2, p4)) return true;
    if (d3 == 0 && _onSegment(p1, p3, p2)) return true;
    if (d4 == 0 && _onSegment(p1, p4, p2)) return true;
    return false;
  }
}
