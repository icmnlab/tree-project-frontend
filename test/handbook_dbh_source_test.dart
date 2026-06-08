import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sustainable_treeai/config/survey_settings.dart';
import 'package:sustainable_treeai/services/pending_measurement_service.dart';

/// 一筆帶「儀器遠端徑量（remote diameter）」的 BLE 記錄。
Map<String, dynamic> _bleRecordWithRemoteDia({double dbh = 18.5}) {
  return {
    'id': 'dbh-001',
    'type': 'DME',
    'lat': 23.8962222,
    'lon': 121.5481563,
    'hasGps': true,
    'height': 12.0,
    'dbh': dbh,
    'metadata': {
      'gps_source': 'tree',
      'horizontal_distance': 10.0,
      'slope_distance': 10.4,
      'azimuth': 90.0,
      'pitch': 0.0,
      'dbh_source': 'remote_diameter',
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const remoteDia = 18.5;

  group('手冊合規模式（handbookCompliantMode=true）', () {
    setUp(() async {
      // research=false → handbook=true：手冊不允許「儀器徑量」直接當 DBH。
      SharedPreferences.setMockInitialValues({
        'survey_research_mode_enabled': false,
      });
      await SurveySettings.instance.load();
    });

    test('儀器徑量不直接寫入 DBH，來源標 manual（待人工量測）', () {
      expect(SurveySettings.instance.handbookCompliantMode, isTrue);

      final pending = PendingMeasurementService()
          .createFromBleData(bleData: [_bleRecordWithRemoteDia(dbh: remoteDia)]);

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.dbhCm, isNull, reason: '手冊合規：不可把儀器徑量當成 DBH');
      expect(task.dbhSource, 'manual');
      // 但儀器值仍保留供溯源（不丟失原始量測）
      expect(task.instrumentDbhCm, closeTo(remoteDia, 0.0001));
    });
  });

  group('研究模式（handbookCompliantMode=false）', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'survey_research_mode_enabled': true,
      });
      await SurveySettings.instance.load();
    });

    test('儀器徑量作為 DBH，來源標 remote_diameter', () {
      expect(SurveySettings.instance.handbookCompliantMode, isFalse);

      final pending = PendingMeasurementService()
          .createFromBleData(bleData: [_bleRecordWithRemoteDia(dbh: remoteDia)]);

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.dbhCm, closeTo(remoteDia, 0.0001));
      expect(task.dbhSource, 'remote_diameter');
      expect(task.instrumentDbhCm, closeTo(remoteDia, 0.0001));
    });
  });
}
