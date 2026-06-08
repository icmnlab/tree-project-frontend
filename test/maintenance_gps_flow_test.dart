import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/utils/field_gps_capture.dart';
import 'package:sustainable_treeai/utils/maintenance_gps_flow.dart';

void main() {
  group('Maintenance GPS flow', () {
    test('keepExisting uses tree coordinates when available', () {
      final gps = resolveMaintenancePendingGps(
        decision: MaintenanceGpsDecision.keepExistingCoords(),
        existingLat: 23.888,
        existingLon: 121.548,
      );
      expect(gps, isNotNull);
      expect(gps!.latitude, closeTo(23.888, 0.0001));
      expect(gps.longitude, closeTo(121.548, 0.0001));
      expect(gps.mode, 'existing');
    });

    test('keepExisting returns null when tree has no coords', () {
      final gps = resolveMaintenancePendingGps(
        decision: MaintenanceGpsDecision.keepExistingCoords(),
        existingLat: null,
        existingLon: null,
      );
      expect(gps, isNull);
    });

    test('updateWithGps uses captured phone GPS', () {
      const captured = FieldGpsCaptureResult(
        latitude: 23.8879974,
        longitude: 121.5479363,
        accuracyM: 16.5,
        sampleCount: 1,
        mode: 'tree',
      );
      final gps = resolveMaintenancePendingGps(
        decision: MaintenanceGpsDecision.updateWithGps(captured),
        existingLat: 23.888,
        existingLon: 121.548,
      );
      expect(gps, same(captured));
    });

    test('update decision sets updateTreeLocation flag', () {
      const captured = FieldGpsCaptureResult(
        latitude: 1,
        longitude: 2,
        accuracyM: 5,
        sampleCount: 1,
        mode: 'tree',
      );
      final d = MaintenanceGpsDecision.updateWithGps(captured);
      expect(d.updateTreeLocation, isTrue);
      expect(d.capturedGps, captured);
    });
  });
}
