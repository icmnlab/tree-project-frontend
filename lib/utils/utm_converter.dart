import 'dart:math';

/// UTM → WGS84 座標轉換工具
///
/// 用於 VLGEO2 儀器無 GPS 但有 UTM 座標的記錄補救
/// WGS84 橢球體參數，標準 UTM 投影反算
class UtmConverter {
  // WGS84 橢球體常數
  static const double _a = 6378137.0; // 半長軸 (m)
  static const double _f = 1 / 298.257223563; // 扁率
  static const double _k0 = 0.9996; // UTM 比例因子
  static const double _e2 = 2 * _f - _f * _f; // 第一偏心率平方
  static const double _ep2 = _e2 / (1 - _e2); // 第二偏心率平方

  /// UTM → WGS84 (lat, lon) 轉換
  ///
  /// [easting] - UTM X 座標 (m)
  /// [northing] - UTM Y 座標 (m)
  /// [zoneNumber] - UTM 區號 (1-60)
  /// [isNorthern] - 是否在北半球
  ///
  /// 回傳 (latitude, longitude) in degrees
  static ({double lat, double lon}) toLatLon({
    required double easting,
    required double northing,
    required int zoneNumber,
    required bool isNorthern,
  }) {
    // 移除偏移量
    final x = easting - 500000.0; // 去除 false easting
    final y = isNorthern ? northing : northing - 10000000.0; // 南半球去除 false northing

    // 計算 footprint latitude
    final m = y / _k0;

    final mu = m /
        (_a *
            (1 - _e2 / 4 - 3 * _e2 * _e2 / 64 - 5 * _e2 * _e2 * _e2 / 256));

    // 計算 e1
    final e1 = (1 - sqrt(1 - _e2)) / (1 + sqrt(1 - _e2));

    // Footprint latitude (φ₁) 級數展開
    final phi1 = mu +
        (3 * e1 / 2 - 27 * e1 * e1 * e1 / 32) * sin(2 * mu) +
        (21 * e1 * e1 / 16 - 55 * e1 * e1 * e1 * e1 / 32) * sin(4 * mu) +
        (151 * e1 * e1 * e1 / 96) * sin(6 * mu) +
        (1097 * e1 * e1 * e1 * e1 / 512) * sin(8 * mu);

    // 輔助量
    final sinPhi1 = sin(phi1);
    final cosPhi1 = cos(phi1);
    final tanPhi1 = tan(phi1);
    final n1 = _a / sqrt(1 - _e2 * sinPhi1 * sinPhi1); // 卯酉圈曲率半徑
    final t1 = tanPhi1 * tanPhi1;
    final c1 = _ep2 * cosPhi1 * cosPhi1;
    final r1 = _a *
        (1 - _e2) /
        pow(1 - _e2 * sinPhi1 * sinPhi1, 1.5); // 子午圈曲率半徑
    final d = x / (n1 * _k0);

    // 計算緯度
    final lat = phi1 -
        (n1 * tanPhi1 / r1) *
            (d * d / 2 -
                (5 + 3 * t1 + 10 * c1 - 4 * c1 * c1 - 9 * _ep2) *
                    d *
                    d *
                    d *
                    d /
                    24 +
                (61 +
                        90 * t1 +
                        298 * c1 +
                        45 * t1 * t1 -
                        252 * _ep2 -
                        3 * c1 * c1) *
                    d *
                    d *
                    d *
                    d *
                    d *
                    d /
                    720);

    // 計算經度
    final lon0 = ((zoneNumber - 1) * 6 - 180 + 3) * pi / 180; // 中央經線 (rad)
    final lon = lon0 +
        (d -
                (1 + 2 * t1 + c1) * d * d * d / 6 +
                (5 - 2 * c1 + 28 * t1 - 3 * c1 * c1 + 8 * _ep2 + 24 * t1 * t1) *
                    d *
                    d *
                    d *
                    d *
                    d /
                    120) /
            cosPhi1;

    return (lat: lat * 180 / pi, lon: lon * 180 / pi);
  }

  /// 從 UTM zone 字串解析區號和半球
  ///
  /// [utmZone] - 如 "51Q", "51R", "48N" 等
  /// 回傳 (zoneNumber, isNorthern)
  /// zone letter >= 'N' 表示北半球
  static ({int zoneNumber, bool isNorthern})? parseUtmZone(String utmZone) {
    utmZone = utmZone.trim().toUpperCase();
    if (utmZone.isEmpty) return null;

    // 嘗試提取數字和字母
    final match = RegExp(r'^(\d{1,2})([A-Z])$').firstMatch(utmZone);
    if (match == null) return null;

    final zoneNumber = int.tryParse(match.group(1)!);
    final zoneLetter = match.group(2)!;

    if (zoneNumber == null || zoneNumber < 1 || zoneNumber > 60) return null;

    // UTM zone letter: C-M = 南半球, N-X = 北半球
    final isNorthern = zoneLetter.codeUnitAt(0) >= 'N'.codeUnitAt(0);

    return (zoneNumber: zoneNumber, isNorthern: isNorthern);
  }

  /// 便捷方法：直接從 VLGEO2 metadata 轉換
  ///
  /// [utmX] - metadata['utm_x'] (Easting)
  /// [utmY] - metadata['utm_y'] (Northing)
  /// [utmZone] - metadata['utm_zone'] (如 "51Q")
  static ({double lat, double lon})? fromVlgeo2Metadata({
    double? utmX,
    double? utmY,
    String? utmZone,
  }) {
    if (utmX == null || utmY == null || utmZone == null) return null;
    if (utmX == 0 && utmY == 0) return null;

    final zone = parseUtmZone(utmZone);
    if (zone == null) return null;

    return toLatLon(
      easting: utmX,
      northing: utmY,
      zoneNumber: zone.zoneNumber,
      isNorthern: zone.isNorthern,
    );
  }
}
