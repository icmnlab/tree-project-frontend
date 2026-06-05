import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// GoogleMap 平台通道在 onMapCreated 後可能尚未就緒；統一延遲 + try/catch。
class SafeMapCamera {
  SafeMapCamera({this.logTag = 'Map'});

  final String logTag;
  GoogleMapController? controller;
  bool ready = false;

  void attach(GoogleMapController ctrl) {
    controller = ctrl;
    ready = false;
  }

  void detach() {
    controller = null;
    ready = false;
  }

  /// onMapCreated 後呼叫，待平台通道穩定再標記 ready。
  Future<void> markReadyAfterPlatformInit() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    ready = true;
  }

  Future<void> animate(CameraUpdate update) async {
    final ctrl = controller;
    if (!ready || ctrl == null) return;
    try {
      await ctrl.animateCamera(update);
    } catch (e, st) {
      debugPrint('[$logTag] animateCamera: $e');
      if (kDebugMode) debugPrint('$st');
    }
  }

  Future<void> fitMarkers(Set<Marker> markers, {double padding = 56}) async {
    if (markers.isEmpty) return;
    if (markers.length == 1) {
      await animate(CameraUpdate.newLatLngZoom(markers.first.position, 17));
      return;
    }
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final m in markers) {
      final p = m.position;
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    // 單點或共線時 newLatLngBounds 可能失敗，補最小跨度
    const eps = 0.00015;
    if ((maxLat - minLat).abs() < eps) {
      minLat -= eps;
      maxLat += eps;
    }
    if ((maxLng - minLng).abs() < eps) {
      minLng -= eps;
      maxLng += eps;
    }
    await animate(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        padding,
      ),
    );
  }
}
