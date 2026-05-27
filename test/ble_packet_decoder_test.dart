import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/services/ble_live_packet_decoder.dart';
import 'package:sustainable_treeai/services/ble_packet_decoder.dart';

void main() {
  group('BlePacketDecoder (批次 CSV 串流)', () {
    test('20-byte 正常封包原樣保留', () {
      final input = List<int>.generate(20, (i) => 0x30 + (i % 10));
      expect(BlePacketDecoder.decodePacket(input), input);
    });

    test('44 0x0F 00 標記封包跳過前 3 bytes（實作僅辨識第二 byte ≤ 0x0F）', () {
      final input = [0x44, 0x05, 0x00, ...List.filled(17, 0x41)];
      final out = BlePacketDecoder.decodePacket(input);
      expect(out.length, 17);
      expect(out.every((b) => b == 0x41), isTrue);
    });

    test('5-byte 殘留封包只保留前 3 bytes', () {
      final input = [0x31, 0x32, 0x33, 0xFF, 0xFE];
      expect(BlePacketDecoder.decodePacket(input), [0x31, 0x32, 0x33]);
    });
  });

  group('BleLivePacketDecoder (即時 §9.3)', () {
    test('解析標準 20-byte 量測', () {
      // HD=10.2m SD=10.4m H=21.6m pitch=38.4° az=2.3°（各欄 4 字元，值×10）
      const raw = '01020104021603840023';
      final bytes = raw.codeUnits;
      expect(bytes.length, 20);

      final m = BleLivePacketDecoder.tryParse(bytes);
      expect(m, isNotNull);
      expect(m!.horizontalDistanceM, closeTo(10.2, 0.01));
      expect(m.slopeDistanceM, closeTo(10.4, 0.01));
      expect(m.heightM, closeTo(21.6, 0.01));
      expect(m.pitchDeg, closeTo(38.4, 0.01));
      expect(m.azimuthDeg, closeTo(2.3, 0.01));
    });

    test('拒絕 CSV 片段', () {
      final csvChunk = '\$;1;3P;;;;10001'.padRight(20).codeUnits;
      expect(BleLivePacketDecoder.tryParse(csvChunk), isNull);
    });
  });
}
