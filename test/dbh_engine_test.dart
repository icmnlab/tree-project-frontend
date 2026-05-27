import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/services/dbh_measurement_engine.dart';

void main() {
  group('DbhEngineResolver', () {
    const noLidar = DbhHardwareCapabilities(
      reportsLidarHardware: false,
      platform: 'android',
      deviceModel: 'SM-S9080',
    );

    const proLidar = DbhHardwareCapabilities(
      reportsLidarHardware: true,
      platform: 'ios',
      deviceModel: 'iPhone15,2',
    );

    test('Android 無 LiDAR → visionMono', () {
      final r = DbhEngineResolver.resolveForAutoMeasure(hardware: noLidar);
      expect(r.apiEngine, DbhEngine.visionMono);
      expect(r.engine, DbhEngine.visionMono);
    });

    test('iPhone Pro 但 Xiang API 未開 → vision fallback', () {
      DbhCapabilityService.xiangApiEnabled = false;
      final r = DbhEngineResolver.resolveForAutoMeasure(hardware: proLidar);
      expect(r.engine, DbhEngine.xiangLidar);
      expect(r.apiEngine, DbhEngine.visionMono);
      expect(r.reason, contains('not enabled'));
    });

    test('Xiang 就緒且有 depth frame → xiangLidar', () {
      DbhCapabilityService.xiangApiEnabled = true;
      final r = DbhEngineResolver.resolveForAutoMeasure(
        hardware: proLidar,
        hasLidarDepthFrame: true,
        xiangPreflightOk: true,
      );
      expect(r.apiEngine, DbhEngine.xiangLidar);
      DbhCapabilityService.xiangApiEnabled = false;
    });

    test('fromFormSource 對應', () {
      expect(
        DbhEngineResolver.fromFormSource('remote_diameter'),
        DbhEngine.instrumentRemote,
      );
      expect(DbhEngineResolver.fromFormSource('vision'), DbhEngine.visionMono);
    });
  });
}
