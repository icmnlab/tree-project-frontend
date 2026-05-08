import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';

/// 建立 GPS 位置串流設定。
///
/// 導航 / 測站對準等需要即時回饋之情境，建議使用 [distanceFilter] = 1、
/// [intervalMs] = 250(走路 ~1 m/s 約每 250 ms 更新一次，雷達不卡頓)。
/// 一般情境（地圖瀏覽 / 紀錄 GPS）保留預設 3 m / 500 ms 較省電。
LocationSettings buildLocationSettings({
  int distanceFilter = 3,
  int intervalMs = 500,
}) {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      forceLocationManager: false,
      intervalDuration: Duration(milliseconds: intervalMs),
    );
  } else if (Platform.isIOS) {
    return AppleSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      activityType: ActivityType.fitness,
      showBackgroundLocationIndicator: false,
    );
  }
  return LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: distanceFilter,
  );
}

Future<Position?> getHighAccuracyPosition({
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.deniedForever) return null;
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }
    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(timeout);
  } catch (e) {
    return null;
  }
}
