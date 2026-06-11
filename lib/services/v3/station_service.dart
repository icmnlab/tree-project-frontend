import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// V3 測站位置計算服務
///
/// 功能：
/// 1. 根據測站座標、距離、方位角，正向推算樹木位置
/// 2. 根據樹木座標、距離、方位角，反推測站位置（保留向後相容）
/// 3. 計算兩點間距離與方位角（驗證用）
///
/// 重要修正 (2026-02):
/// VLGEO2 CSV 的 LAT/LON 是「操作員（儀器）的 GPS 位置」，不是樹木位置。
/// SD/HD/AZ/PITCH 是「從儀器指向目標」的向量。
/// 因此需要「正向推算」：測站(GPS) + HD + AZ -> 樹木位置
class StationService {
  static final StationService _instance = StationService._internal();
  factory StationService() => _instance;
  StationService._internal();

  // 地球半徑 (公尺)
  static const double earthRadius = 6371000.0;
  static const Distance _distanceCalculator = Distance();

  /// 正向推算樹木位置（主要方法）
  ///
  /// VLGEO2 的 GPS 座標是操作員位置，HD/AZ 是從操作員指向樹木的向量。
  /// 因此：樹木位置 = 操作員位置 + offset(HD, AZ)
  ///
  /// [stationLat] 測站（操作員/儀器）緯度 = VLGEO2 GPS LAT
  /// [stationLng] 測站（操作員/儀器）經度 = VLGEO2 GPS LON
  /// [distanceMeters] 水平距離 HD (公尺)
  /// [azimuthDegrees] 方位角 AZ (度, 0-360, 測站指向樹木)
  ///
  /// 返回：樹木位置 LatLng
  LatLng calculateTreePosition({
    required double stationLat,
    required double stationLng,
    required double distanceMeters,
    required double azimuthDegrees,
  }) {
    const Distance distance = Distance();
    return distance.offset(
      LatLng(stationLat, stationLng),
      distanceMeters,
      azimuthDegrees,
    );
  }

  /// 反推測站位置（保留向後相容）
  ///
  /// [treeLat] 樹木緯度
  /// [treeLng] 樹木經度
  /// [distanceMeters] 水平距離 (公尺)
  /// [azimuthDegrees] 方位角 (度, 0-360, 測站指向樹木)
  ///
  /// 返回：測站位置 LatLng
  LatLng calculateStationPosition({
    required double treeLat,
    required double treeLng,
    required double distanceMeters,
    required double azimuthDegrees,
  }) {
    final double reverseAzimuth = (azimuthDegrees + 180) % 360;
    const Distance distance = Distance();
    return distance.offset(
      LatLng(treeLat, treeLng),
      distanceMeters,
      reverseAzimuth,
    );
  }

  /// 計算兩點間距離 (公尺)
  double getDistance({
    required double lat1,
    required double lon1,
    required double lat2,
    required double lon2,
  }) {
    return _distanceCalculator.as(
      LengthUnit.Meter,
      LatLng(lat1, lon1),
      LatLng(lat2, lon2),
    );
  }

  /// 驗證計算結果 (對稱性測試)
  ///
  /// 輸入測站與樹木位置，驗證距離與方位角是否吻合
  Map<String, dynamic> verifyCalculation({
    required LatLng stationPos,
    required LatLng treePos,
    required double originalDistance,
    required double originalAzimuth,
  }) {
    // 計算實際距離
    final double calculatedDistance = _distanceCalculator.as(
      LengthUnit.Meter,
      stationPos,
      treePos,
    );

    // 計算實際方位角 (Station -> Tree)
    final double calculatedAzimuth = _distanceCalculator.bearing(
      stationPos,
      treePos,
    );
    
    // 正規化方位角 (0-360)
    double normalizedAzimuth = calculatedAzimuth;
    if (normalizedAzimuth < 0) {
      normalizedAzimuth += 360;
    }

    return {
      'distanceDiff': (calculatedDistance - originalDistance).abs(),
      'azimuthDiff': (normalizedAzimuth - originalAzimuth).abs(),
      'isAccurate': (calculatedDistance - originalDistance).abs() < 0.5 && // 誤差小於 50cm
                    (normalizedAzimuth - originalAzimuth).abs() < 1.0,     // 誤差小於 1度
      'calculatedDistance': calculatedDistance,
      'calculatedAzimuth': normalizedAzimuth,
    };
  }

  /// 手動實現的公式計算 (用於雙重驗證或無套件時)
  ///
  /// 公式：球面三角學的目的地點計算（given 起點、方位角、距離）
  LatLng calculateStationPositionManual({
    required double treeLat,
    required double treeLng,
    required double distanceMeters,
    required double azimuthDegrees,
  }) {
    // 將角度轉為弧度
    const double deg2rad = math.pi / 180.0;
    const double rad2deg = 180.0 / math.pi;

    final double reverseAzimuth = (azimuthDegrees + 180) % 360;
    final double brng = reverseAzimuth * deg2rad;
    final double d = distanceMeters / earthRadius; // 角距離

    final double lat1 = treeLat * deg2rad;
    final double lon1 = treeLng * deg2rad;

    final double lat2 = math.asin(
      math.sin(lat1) * math.cos(d) + 
      math.cos(lat1) * math.sin(d) * math.cos(brng)
    );

    final double lon2 = lon1 + math.atan2(
      math.sin(brng) * math.sin(d) * math.cos(lat1),
      math.cos(d) - math.sin(lat1) * math.sin(lat2)
    );

    return LatLng(lat2 * rad2deg, lon2 * rad2deg);
  }
}
