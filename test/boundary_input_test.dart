import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/utils/boundary_input.dart';

void main() {
  group('BoundaryInputParser.parse', () {
    test('解析括號 (lng, lat) 格式並輸出 [lat, lng]', () {
      const text = '''
(120.1222905, 23.2637175)
(120.1233066, 23.2638557)
(120.1242669, 23.2584254)
(120.1219538, 23.2583754)
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, true);
      expect(r.coordinates.length, 4);
      // 第一點：lat≈23.26, lng≈120.12
      expect(r.coordinates.first[0], closeTo(23.2637175, 1e-6));
      expect(r.coordinates.first[1], closeTo(120.1222905, 1e-6));
      expect(r.detectedOrder, CoordOrder.lngLat);
    });

    test('解析 lat,lng 順序（緯度在前）', () {
      const text = '''
23.2637175, 120.1222905
23.2638557, 120.1233066
23.2584254, 120.1242669
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, true);
      expect(r.coordinates.first[0], closeTo(23.2637175, 1e-6));
      expect(r.coordinates.first[1], closeTo(120.1222905, 1e-6));
      expect(r.detectedOrder, CoordOrder.latLng);
    });

    test('移除首尾重複收尾點', () {
      const text = '''
120.10, 23.10
120.11, 23.10
120.11, 23.11
120.10, 23.10
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, true);
      expect(r.coordinates.length, 3);
    });

    test('忽略標頭文字、回報無法解析的行', () {
      const text = '''
經度, 緯度
120.10, 23.10
壞掉的行 only-one 120.11
120.11, 23.10
120.11, 23.11
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, true);
      expect(r.coordinates.length, 3);
      expect(r.errors.any((e) => e.contains('一個數值')), true);
    });

    test('頂點不足 3 個 → ok=false', () {
      const text = '120.10, 23.10\n120.11, 23.10';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, false);
    });

    test('學院圖一實際資料：缺小數點的座標被偵測並給出修正提示', () {
      // 取自環境學院「圖一」清單，其中第 3 筆 (1201240910,...) 掉了小數點
      const text = '''
(120.1222905, 23.2637175)
(120.1233066, 23.2638557)
(1201240910, 23.2619545)
(120.1242669, 23.2584254)
(120.1219538, 23.2583754)
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, true);
      // 壞掉那筆被略過，剩 4 個有效頂點
      expect(r.coordinates.length, 4);
      expect(r.detectedOrder, CoordOrder.lngLat);
      // 錯誤訊息應提示疑似缺少小數點，並建議 120.124091
      expect(r.errors.any((e) => e.contains('缺少小數點')), true);
      expect(r.errors.any((e) => e.contains('120.124091')), true);
    });

    test('座標超出範圍 → 略過並回報', () {
      const text = '''
120.10, 23.10
999, 999
120.11, 23.10
120.11, 23.11
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.errors.any((e) => e.contains('超出合理範圍')), true);
      expect(r.coordinates.length, 3);
    });

    test('學院魚塭 9 點（正確順序）為合法凹多邊形、不自相交', () {
      // 對應 docs/boundary_samples/coords_complex_pond.txt：證明系統可畫複雜（凹）形狀
      const text = '''
(120.1222905, 23.2637175)
(120.1233066, 23.2638557)
(120.1240910, 23.2619545)
(120.1242669, 23.2584254)
(120.1219538, 23.2583754)
(120.1218188, 23.2615941)
(120.1224000, 23.2619421)
(120.1224003, 23.2630480)
(120.1219813, 23.2632104)
''';
      final r = BoundaryInputParser.parse(text);
      expect(r.ok, true);
      expect(r.coordinates.length, 9);
      expect(r.selfIntersecting, false);
    });
  });

  group('自相交與重排', () {
    test('蝴蝶結偵測為自相交', () {
      final bowtie = [
        [0.0, 0.0],
        [2.0, 2.0],
        [0.0, 2.0],
        [2.0, 0.0],
      ];
      expect(BoundaryInputParser.isSelfIntersecting(bowtie), true);
    });

    test('正方形非自相交', () {
      final square = [
        [0.0, 0.0],
        [0.0, 2.0],
        [2.0, 2.0],
        [2.0, 0.0],
      ];
      expect(BoundaryInputParser.isSelfIntersecting(square), false);
    });

    test('依角度重排可修正亂序的凸多邊形', () {
      // 故意亂序（會自相交）
      final messy = [
        [0.0, 0.0],
        [2.0, 2.0],
        [0.0, 2.0],
        [2.0, 0.0],
      ];
      expect(BoundaryInputParser.isSelfIntersecting(messy), true);
      final fixed = BoundaryInputParser.reorderByAngle(messy);
      expect(BoundaryInputParser.isSelfIntersecting(fixed), false);
    });
  });

  group('自動重排（角度 + 最近鄰）', () {
    test('tryAutoReorder 修復凸形蝴蝶結並回 resolved=true', () {
      final bowtie = [
        [0.0, 0.0],
        [2.0, 2.0],
        [0.0, 2.0],
        [2.0, 0.0],
      ];
      final r = BoundaryInputParser.tryAutoReorder(bowtie);
      expect(r.resolved, true);
      expect(BoundaryInputParser.isSelfIntersecting(r.coordinates), false);
      expect(r.coordinates.length, 4);
    });

    test('reorderByNearestNeighbor 保留所有點且自最低點起', () {
      final pts = [
        [2.0, 2.0],
        [0.0, 0.0],
        [2.0, 0.0],
        [0.0, 2.0],
      ];
      final out = BoundaryInputParser.reorderByNearestNeighbor(pts);
      expect(out.length, 4);
      expect(out.first[0], 0.0); // lat 最小
      expect(out.first[1], 0.0); // 其次 lng 最小
    });

    test('tryAutoReorder 對已合法多邊形回 resolved=true', () {
      final square = [
        [0.0, 0.0],
        [0.0, 2.0],
        [2.0, 2.0],
        [2.0, 0.0],
      ];
      final r = BoundaryInputParser.tryAutoReorder(square);
      expect(r.resolved, true);
    });
  });
}
