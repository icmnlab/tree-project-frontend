import 'dart:math' as math;

/// 同座標標記展開（簡化 spiderfy）。
///
/// 背景：DB 中存在多棵樹座標完全相同（例：同一點 8 棵），Google Map 的
/// marker 完全重疊時只看得到／點得到最上層那個，使用者會以為「樹不見了」。
/// 做法：同一座標的第 2 棵起，以小圓環（每環 8 個、半徑約 1.5m 起跳）
/// 確定性展開，讓每棵樹都可見、可點；第 1 棵維持原座標。
///
/// 純函式、不依賴地圖套件，便於單元測試。
class SpreadPoint {
  final double lat;
  final double lng;
  const SpreadPoint(this.lat, this.lng);
}

/// 每環放幾個點。
const int _pointsPerRing = 8;

/// 基礎展開半徑（公尺）。
const double _baseRadiusM = 1.5;

/// [duplicateIndex]：此座標的第幾個重複（0 = 第一棵，不位移）。
SpreadPoint spreadStackedPoint(double lat, double lng, int duplicateIndex) {
  if (duplicateIndex <= 0) return SpreadPoint(lat, lng);

  final int ring = ((duplicateIndex - 1) ~/ _pointsPerRing) + 1; // 1,2,3…
  final int posInRing = (duplicateIndex - 1) % _pointsPerRing;
  final double radiusM = _baseRadiusM * ring;
  // 每環起始角錯開半格，避免不同環的點排成直線。
  final double angle = (2 * math.pi / _pointsPerRing) * posInRing +
      (ring.isEven ? math.pi / _pointsPerRing : 0);

  // 公尺 → 經緯度（緯度 1 度 ≈ 111,320 m；經度依緯度收縮）。
  final double dLat = radiusM * math.cos(angle) / 111320.0;
  final double cosLat = math.cos(lat * math.pi / 180.0);
  // 極端緯度保險（台灣用不到，但避免除以 0）。
  final double lngScale = cosLat.abs() < 1e-6 ? 1e-6 : cosLat;
  final double dLng = radiusM * math.sin(angle) / (111320.0 * lngScale);

  return SpreadPoint(lat + dLat, lng + dLng);
}

/// 將「座標 → 已出現次數」的計數器套用到一個點，回傳展開後座標並遞增計數。
/// key 用原始座標字串，確保同座標的樹拿到遞增的 duplicateIndex。
SpreadPoint nextSpreadPoint(
  Map<String, int> seenCounter,
  double lat,
  double lng,
) {
  final key = '$lat,$lng';
  final index = seenCounter[key] ?? 0;
  seenCounter[key] = index + 1;
  return spreadStackedPoint(lat, lng, index);
}
