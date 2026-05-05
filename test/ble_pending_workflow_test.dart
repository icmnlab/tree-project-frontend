import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/models/pending_tree_measurement.dart';
import 'package:sustainable_treeai/services/pending_measurement_service.dart';
import 'package:sustainable_treeai/services/v3/data_filter_service.dart';

Map<String, dynamic> _bleRecord({
  required String id,
  double lat = 23.8962222,
  double lon = 121.5481563,
  bool hasGps = true,
  String gpsSource = 'surveyor',
  double horizontalDistance = 10,
  double slopeDistance = 10.4,
  double azimuth = 90,
  double pitch = 0,
  double height = 12,
  double? dbh,
  Map<String, dynamic>? extraMetadata,
  Map<String, dynamic>? extraTopLevel,
}) {
  return {
    'id': id,
    'type': '1P',
    'lat': lat,
    'lon': lon,
    'hasGps': hasGps,
    'height': height,
    if (dbh != null) 'dbh': dbh,
    'metadata': {
      'gps_source': gpsSource,
      'horizontal_distance': horizontalDistance,
      'slope_distance': slopeDistance,
      'azimuth': azimuth,
      'pitch': pitch,
      ...?extraMetadata,
    },
    ...?extraTopLevel,
  };
}

void main() {
  group('BLE pending workflow invariants', () {
    test('surveyor GPS keeps raw station and derives tree position', () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(id: 'station-001', gpsSource: 'surveyor'),
      ];

      final pending = service.createFromBleData(bleData: records);

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.gpsSource, 'surveyor');
      expect(task.stationLatitude, closeTo(23.8962222, 0.0000001));
      expect(task.stationLongitude, closeTo(121.5481563, 0.0000001));
      expect(task.distanceToTree(23.8962222, 121.5481563), closeTo(10, 0.05));
      expect(
        task.rawDataSnapshot?['tree_position_source'],
        'derived_from_station_gps_hd_az',
      );
      expect(task.rawDataSnapshot?['station_position_source'], 'gps_receiver');
      expect(task.rawDataSnapshot?['lat'], 23.8962222);
      expect(task.rawDataSnapshot?['lon'], 121.5481563);
    });

    test(
        'tree GPS keeps raw tree position and derives station for traceability',
        () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(id: 'tree-001', gpsSource: 'tree'),
      ];

      final pending = service.createFromBleData(bleData: records);

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.gpsSource, 'tree');
      expect(task.treeLatitude, closeTo(23.8962222, 0.0000001));
      expect(task.treeLongitude, closeTo(121.5481563, 0.0000001));
      expect(
          task.distanceToStation(23.8962222, 121.5481563), closeTo(10, 0.05));
      expect(task.distanceToNavigationTarget(23.8962222, 121.5481563),
          closeTo(0, 0.01));
      expect(task.rawDataSnapshot?['tree_position_source'], 'gps_receiver');
      expect(
        task.rawDataSnapshot?['station_position_source'],
        'derived_from_tree_gps_hd_az',
      );
    });

    test('missing GPS can be retained only when requiresGpsFix is explicit',
        () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(
          id: 'missing-gps-001',
          lat: 0,
          lon: 0,
          hasGps: false,
          extraMetadata: {'requires_gps_fix': true},
        ),
      ];

      final pending = service.createFromBleData(bleData: records);

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.requiresGpsFix, isTrue);
      expect(task.hasTreeGps, isFalse);
      expect(task.hasStationGps, isFalse);
      expect(task.treeLatitude, 0);
      expect(task.treeLongitude, 0);
    });

    test(
        'mixed pending GPS rows are skipped until per-record source is resolved',
        () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(id: 'mixed-001', gpsSource: 'mixed_pending'),
      ];

      final pending = service.createFromBleData(bleData: records);

      expect(pending, isEmpty);
    });

    test('maintenance metadata is preserved for backend transfer', () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(
          id: 'maint-001',
          extraTopLevel: {
            '_survey_mode': 'maintenance',
            '_target_tree_id': 123,
            '_match_status': 'matched_nearby_tree',
          },
        ),
      ];

      final pending = service.createFromBleData(bleData: records);

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.normalizedSurveyMode, 'maintenance');
      expect(task.isMaintenanceTask, isTrue);
      expect(task.targetTreeId, 123);
      expect(task.matchStatus, 'matched_nearby_tree');

      final json = task.toJson();
      expect(json['survey_mode'], 'maintenance');
      expect(json['target_tree_id'], 123);
      expect(json['match_status'], 'matched_nearby_tree');
    });

    test('same station can produce multiple tree records without dedupe loss',
        () {
      final records = [
        _bleRecord(id: 'same-station-001'),
        _bleRecord(id: 'same-station-002', height: 13, azimuth: 120),
      ];

      final result = DataFilterService.filterBleData(records);

      expect(result.validRecords, hasLength(2));
      expect(result.duplicateRecords, isEmpty);
      expect(result.stats.duplicateCount, 0);
      expect(result.stats.validCount, 2);
    });

    test('mixed BLE batch keeps resolved rows and skips unresolved GPS source',
        () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(id: 'surveyor-001', gpsSource: 'surveyor'),
        _bleRecord(id: 'tree-001', gpsSource: 'tree', azimuth: 270),
        _bleRecord(id: 'mixed-001', gpsSource: 'mixed_pending'),
        _bleRecord(
          id: 'missing-gps-001',
          lat: 0,
          lon: 0,
          hasGps: false,
          extraMetadata: {'requires_gps_fix': true},
        ),
      ];

      final pending = service.createFromBleData(
        bleData: records,
        projectArea: '全域區位',
        projectCode: 'GLOBAL',
        projectName: '全域專案',
      );

      expect(pending.map((task) => task.originalRecordId), [
        'surveyor-001',
        'tree-001',
        'missing-gps-001',
      ]);
      expect(pending.every((task) => task.projectCode == 'GLOBAL'), isTrue);

      final surveyorTask = pending[0];
      expect(surveyorTask.gpsSource, 'surveyor');
      expect(surveyorTask.rawDataSnapshot?['tree_position_source'],
          'derived_from_station_gps_hd_az');

      final treeTask = pending[1];
      expect(treeTask.gpsSource, 'tree');
      expect(treeTask.rawDataSnapshot?['tree_position_source'], 'gps_receiver');

      final missingGpsTask = pending[2];
      expect(missingGpsTask.requiresGpsFix, isTrue);
      expect(missingGpsTask.hasStationGps, isFalse);
      expect(missingGpsTask.hasTreeGps, isFalse);
    });

    test('per-record project assignment overrides global project fallback', () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(id: 'global-project-001'),
        _bleRecord(
          id: 'override-project-001',
          extraTopLevel: {
            '_assigned_project_area': '逐筆區位',
            '_assigned_project_code': 'PER-ROW',
            '_assigned_project_name': '逐筆專案',
          },
        ),
      ];

      final pending = service.createFromBleData(
        bleData: records,
        projectArea: '全域區位',
        projectCode: 'GLOBAL',
        projectName: '全域專案',
      );

      expect(pending, hasLength(2));
      expect(pending[0].projectArea, '全域區位');
      expect(pending[0].projectCode, 'GLOBAL');
      expect(pending[0].projectName, '全域專案');
      expect(pending[1].projectArea, '逐筆區位');
      expect(pending[1].projectCode, 'PER-ROW');
      expect(pending[1].projectName, '逐筆專案');
    });

    test('AutoPilot smoke-style record follows BLE surveyor semantics', () {
      final service = PendingMeasurementService();
      final records = [
        _bleRecord(
          id: 'SMOKE-AUTOPILOT-001',
          horizontalDistance: 2,
          slopeDistance: 2,
          azimuth: 90,
          height: 10,
          extraMetadata: {
            'is_smoke_test': true,
            'smoke_test_type': 'autopilot_phone_flow',
          },
        ),
      ];

      final pending = service.createFromBleData(
        bleData: records,
        projectArea: '測試區',
        projectCode: 'TEST-SMOKE',
        projectName: 'AutoPilot 測試',
      );

      expect(pending, hasLength(1));
      final task = pending.single;
      expect(task.measurementType, '1P');
      expect(task.projectCode, 'TEST-SMOKE');
      expect(task.gpsSource, 'surveyor');
      expect(task.distanceToTree(23.8962222, 121.5481563), closeTo(2, 0.05));
      expect(task.rawDataSnapshot?['is_smoke_test'], isTrue);
      expect(task.rawDataSnapshot?['tree_position_source'],
          'derived_from_station_gps_hd_az');
    });
  });

  group('PendingTreeMeasurement JSON bridge', () {
    test('survey mode and target tree fields survive fromJson/toJson', () {
      final task = PendingTreeMeasurement.fromJson({
        'id': 9,
        'session_id': 'MS-test',
        'tree_height': 10.5,
        'tree_latitude': 23.1,
        'tree_longitude': 121.1,
        'station_latitude': 23.0,
        'station_longitude': 121.0,
        'horizontal_distance': 15,
        'slope_distance': 15.2,
        'azimuth': 30,
        'pitch': 2,
        'status': 'pending',
        'created_at': '2026-05-05T00:00:00Z',
        'survey_mode': 'maintenance',
        'target_tree_id': '456',
        'match_status': 'matched_nearby_tree',
        'raw_data_snapshot': {
          'gps_source': 'tree',
        },
      });

      expect(task.isTreeGpsSource, isTrue);
      expect(task.isMaintenanceTask, isTrue);
      expect(task.targetTreeId, 456);
      expect(task.toJson()['target_tree_id'], 456);
    });
  });
}
