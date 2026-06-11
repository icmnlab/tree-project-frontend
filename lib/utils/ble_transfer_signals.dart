/// VLGEO2 BLE 整檔傳輸（SEND FILES）共用常數。
class BleTransferSignals {
  BleTransferSignals._();

  /// 實機 DATA.CSV 常見 EOT（serial capture DATA_2）
  static const batchEotPrimary = [0x5A, 0xBF, 0xFB];

  /// 手冊／部分韌體變體（test/fixtures/vlgeo2/VLGEO2_BLE_PROTOCOL.md §6）
  static bool isBatchFileEot(List<int> data) {
    if (data.length != 3) return false;
    if (data[0] == batchEotPrimary[0] &&
        data[1] == batchEotPrimary[1] &&
        data[2] == batchEotPrimary[2]) {
      return true;
    }
    if (data[0] == 0x04 && data[1] == 0x7C) return true;
    return false;
  }

  /// 韌體在串流開頭可能送出的檔名（例：`DATA.CSV` + 長度）
  static String stripFileNamePreamble(String buffer) {
    final upper = buffer.toUpperCase();
    for (final name in ['DATA.CSV', 'MAP']) {
      final idx = upper.indexOf(name);
      if (idx >= 0 && idx < 32) {
        // 保留第一個 `$;` 或 `#;` 起的內容
        final dollar = buffer.indexOf('\$;', idx);
        final hash = buffer.indexOf('#;', idx);
        int start = -1;
        if (dollar >= 0) start = dollar;
        if (hash >= 0 && (start < 0 || hash < start)) start = hash;
        if (start > 0) return buffer.substring(start);
      }
    }
    return buffer;
  }
}
