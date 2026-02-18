import 'dart:io' show Platform;
import 'package:geolocator/geolocator.dart';

LocationSettings buildLocationSettings({int distanceFilter = 3}) {
  if (Platform.isAndroid) {
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
      forceLocationManager: false,
      intervalDuration: const Duration(milliseconds: 500),
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
