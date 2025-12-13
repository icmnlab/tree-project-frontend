import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

/// V3 測站位置計算服務
///
/// 功能：
/// 1. 根據樹木座標、距離、方位角，反推測站（測量員）位置
/// 2. 計算兩點間距離與方位角（驗證用）
///
/// 數學原理：
/// 使用大圓距離公式 (Haversine / Spherical Law of Cosines) 計算目標點座標。
///
/// 情境：
/// VLGEO2 設備測量時，會記錄：
/// - 樹木位置 (Tree GPS) - 已知
/// - 水平距離 (Horizontal Distance)
/// - 方位角 (Azimuth, Station -> Tree)
///
/// 我們需要計算 Station (測量員) 的位置。
class StationService {
  static final StationService _instance = StationService._internal();
  factory StationService() => _instance;
  StationService._internal();

  // 地球半徑 (公尺)
  static const double earthRadius = 6371000.0;
  static const Distance _distanceCalculator = Distance();

  /// 計算測站位置
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
    // 1. 計算反向方位角 (樹木 -> 測站)
    // 如果測站看樹木是 Azimuth，那樹木看測站就是 (Azimuth + 180) % 360
    final double reverseAzimuth = (azimuthDegrees + 180) % 360;

    // 2. 使用 latlong2 的 offset 功能計算目標點
    // 從樹木位置，沿著反向方位角，移動指定距離
    final Distance distance = const Distance();
    
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
  /// 參考 V3_DEVELOPMENT_PLAN.md 中的公式
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
