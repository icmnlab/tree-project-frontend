import 'dart:math';

/// 產生防碰撞的測量批次 ID。
///
/// [稽核#4] 舊格式以 `millisecondsSinceEpoch % 100000` 當尾碼，兩台裝置同日
/// 可能撞號導致批次互相污染。改為「日期前綴（可讀）+ 96-bit 安全亂數」，
/// 碰撞機率可忽略，且長度（36 字元）符合 DB `VARCHAR(50)` 限制。
String generateUniqueSessionId({String prefix = 'MS'}) {
  final now = DateTime.now();
  final ymd = '${now.year}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final rng = Random.secure();
  final hex = List<int>.generate(12, (_) => rng.nextInt(256))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$prefix-$ymd-$hex';
}
