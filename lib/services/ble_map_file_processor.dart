import 'ble_data_processor.dart';

/// MAP TARGET / MAP TRAIL 整檔（`MAPxxx.CSV`）。
///
/// 韌體仍使用 33 欄 `$;…` 格式；與 DATA.CSV 欄位索引相同，但語意為製圖目標點。
class BleMapFileProcessor {
  BleMapFileProcessor._();

  static final _mapFilePattern = RegExp(r'MAP\d{0,5}\.CSV', caseSensitive: false);

  static bool looksLikeMapTransfer(String buffer) {
    final upper = buffer.toUpperCase();
    if (_mapFilePattern.hasMatch(upper)) return true;
    if (upper.contains('MAP TARGET') || upper.contains('MAP TRAIL')) {
      return true;
    }
    return false;
  }

  /// 解析 MAP 檔內容；回傳帶 [file_kind]=map 的記錄。
  static List<Map<String, dynamic>> parseMapCsv(String csvData) {
    final parsed = BleDataProcessor.parseCsvData(csvData);
    return parsed.map((record) {
      final copy = Map<String, dynamic>.from(record);
      final meta = Map<String, dynamic>.from(
        copy['metadata'] as Map<String, dynamic>? ?? {},
      );
      meta['file_kind'] = 'map';
      meta['map_kind'] = _inferMapKind(record);
      copy['metadata'] = meta;
      copy['file_kind'] = 'map';
      return copy;
    }).toList();
  }

  static String _inferMapKind(Map<String, dynamic> record) {
    final type = (record['type']?.toString() ?? '').toUpperCase();
    if (type.contains('TRAIL')) return 'trail';
    return 'target';
  }

  static String summarize(List<Map<String, dynamic>> records) {
    if (records.isEmpty) return '無 MAP 量測點';
    final ids = records
        .map((r) => r['id']?.toString())
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();
    return '${records.length} 點 · ${ids.length} 個 Target ID';
  }
}
