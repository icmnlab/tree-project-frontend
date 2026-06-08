import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sustainable_treeai/config/survey_settings.dart';
import 'package:sustainable_treeai/services/ble_live_packet_decoder.dart';
import 'package:sustainable_treeai/services/pending_measurement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // 「儀器 remote diameter → dbh」屬研究模式（非手冊合規）行為，
    // 故測試需把全域 SurveySettings 設為研究模式（handbook=false）。
    SharedPreferences.setMockInitialValues({
      'survey_research_mode_enabled': true,
    });
    await SurveySettings.instance.load();
  });

  group('BleLiveNmeaParser', () {
    test('解析使用者實測 PHGF 句（無 Remote Diameter）', () {
      const line =
          r'$PHGF,HVV,2.7,M,336.4,D,14.9,D,2.8,M,2.2,M,0.0,CM,*23';
      final m = BleLiveNmeaParser.tryParseLine(line);
      expect(m, isNotNull);
      expect(m!.horizontalDistanceM, 2.7);
      expect(m.azimuthDeg, 336.4);
      expect(m.pitchDeg, 14.9);
      expect(m.slopeDistanceM, 2.8);
      expect(m.heightM, 2.2);
      expect(m.trailingValue, 0.0);
      expect(m.trailingUnit, 'CM');
      expect(m.remoteDiameterCm, isNull);
      expect(m.checksum, '*23');
      expect(m.rawFields['parts_count'], 15);
    });

    test('解析有 Remote Diameter 的 PHGF 句', () {
      const line =
          r'$PHGF,HVV,2.9,M,353.1,D,16.2,D,3.0,M,2.3,M,3.8,CM,*21';
      final m = BleLiveNmeaParser.tryParseLine(line);
      expect(m, isNotNull);
      expect(m!.remoteDiameterCm, 3.8);
    });
  });

  group('BleLiveMeasurement.toBleRecordMap', () {
    test('Remote Diameter 對接待測量 dbh 欄位', () {
      const line =
          r'$PHGF,HVV,2.9,M,353.1,D,16.2,D,3.0,M,2.3,M,3.8,CM,*21';
      final m = BleLiveNmeaParser.tryParseLine(line)!;
      final record = m.toBleRecordMap(
        id: 'LIVE-1',
        lat: 23.89,
        lon: 121.54,
        hasGps: true,
        gpsSource: 'surveyor',
      );

      expect(record['dbh'], 3.8);
      final meta = record['metadata'] as Map<String, dynamic>;
      expect(meta['dbh_source'], 'remote_diameter');
      expect(meta['remote_diameter_cm'], 3.8);

      final pending = PendingMeasurementService()
          .createFromBleData(bleData: [record]);
      expect(pending, hasLength(1));
      expect(pending.single.instrumentDbhCm, 3.8);
      expect(pending.single.dbhSource, 'remote_diameter');
      expect(pending.single.hasInstrumentDbh, isTrue);
      expect(pending.single.needsDbhMeasurement, isFalse);
    });

    test('0.0 CM 不寫入 dbh', () {
      const line =
          r'$PHGF,HVV,2.5,M,348.3,D,19.3,D,2.7,M,2.4,M,0.0,CM,*21';
      final m = BleLiveNmeaParser.tryParseLine(line)!;
      final record = m.toBleRecordMap(
        id: 'LIVE-2',
        lat: 23.89,
        lon: 121.54,
        hasGps: true,
      );

      expect(record.containsKey('dbh'), isFalse);
      final pending = PendingMeasurementService()
          .createFromBleData(bleData: [record]);
      expect(pending.single.hasInstrumentDbh, isFalse);
      expect(pending.single.needsDbhMeasurement, isTrue);
    });
  });

  group('BleLiveNmeaAssembler', () {
    test('重組 20+20+15 分片', () {
      final asm = BleLiveNmeaAssembler();
      final p1 = r'$PHGF,HVV,2.7,M,336.'.codeUnits;
      final p2 = r'4,D,14.9,D,2.8,M,2.2'.codeUnits;
      final p3 = r',M,0.0,CM,*23' '\r\n'.codeUnits;

      expect(asm.feed(p1), isEmpty);
      expect(asm.feed(p2), isEmpty);
      final done = asm.feed(p3);
      expect(done, hasLength(1));
      expect(done.first.heightM, 2.2);
    });

    test('§9.3 前綴 + PHGF 無換行（第二棵 SEND 實機格式）', () {
      final asm = BleLiveNmeaAssembler();
      const chunk =
          r'22  22  14   62574$PHGF,HVV,2.2,M,261.4,D,1.8,D,2.2,M,1.5,M,9.3,CM,*14';
      final done = asm.feed(chunk.codeUnits);
      expect(done, hasLength(1));
      expect(done.first.horizontalDistanceM, 2.2);
      expect(done.first.heightM, 1.5);
      expect(done.first.remoteDiameterCm, 9.3);
    });

    test('連續兩棵 PHGF', () {
      final asm = BleLiveNmeaAssembler();
      final first = asm.feed(
        r'$PHGF,HVV,2.2,M,257.4,D,0.6,D,2.2,M,1.4,M,0.0,CM,*15'.codeUnits,
      );
      expect(first, hasLength(1));
      final second = asm.feed(
        r'22  22  15  182614$PHGF,HVV,2.2,M,261.4,D,1.8,D,2.2,M,1.5,M,9.3,CM,*14'
            .codeUnits,
      );
      expect(second, hasLength(1));
      expect(second.first.heightM, 1.5);
    });
  });
}
