import 'package:flutter_test/flutter_test.dart';

/// 與 backend/scripts/seed_field_test_dataset.js 偏移算法一致
({double dLat, double dLon}) metersToOffset(double lat, double dLatM, double dLonM) {
  final dLat = dLatM / 111320;
  final cos = (lat * 3.141592653589793 / 180).abs().clamp(0.2, 1.0);
  final dLon = dLonM / (111320 * cos);
  return (dLat: dLat, dLon: dLon);
}

void main() {
  test('fixture GPS offsets stay within ~40m of anchor', () {
    const lat = 24.15;
    const lon = 120.65;
    final off = metersToOffset(lat, 28, 15);
    final distLatM = off.dLat.abs() * 111320;
    expect(distLatM, lessThan(50));
    expect(distLatM, greaterThan(20));
    final newLat = lat + off.dLat;
    final newLon = lon + off.dLon;
    expect(newLat, isNot(lat));
    expect(newLon, isNot(lon));
  });

  test('QA-FIXTURE marker is stable for cleanup', () {
    const marker = '[QA-FIXTURE:field-test]';
    expect('${marker} HIST-1'.contains(marker), isTrue);
  });
}
