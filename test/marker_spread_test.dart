import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/utils/marker_spread.dart';

/// 兩點間距（公尺，平面近似，台灣緯度誤差可忽略）。
double distM(SpreadPoint a, SpreadPoint b) {
  final dLat = (a.lat - b.lat) * 111320.0;
  final dLng =
      (a.lng - b.lng) * 111320.0 * math.cos(a.lat * math.pi / 180.0);
  return math.sqrt(dLat * dLat + dLng * dLng);
}

void main() {
  const lat = 22.610492098; // 港區植栽5區實際疊點
  const lng = 120.29465604;

  group('spreadStackedPoint', () {
    test('第一棵（index 0）不位移', () {
      final p = spreadStackedPoint(lat, lng, 0);
      expect(p.lat, lat);
      expect(p.lng, lng);
    });

    test('負 index 視為不位移（防禦）', () {
      final p = spreadStackedPoint(lat, lng, -3);
      expect(p.lat, lat);
      expect(p.lng, lng);
    });

    test('第 2~9 棵展開在第一環（約 1.5m）', () {
      const origin = SpreadPoint(lat, lng);
      for (var i = 1; i <= 8; i++) {
        final p = spreadStackedPoint(lat, lng, i);
        final d = distM(origin, p);
        expect(d, greaterThan(1.0), reason: 'index $i 應該離開原點');
        expect(d, lessThan(2.0), reason: 'index $i 應在第一環 (~1.5m)');
      }
    });

    test('第 10 棵起進第二環（約 3m）', () {
      const origin = SpreadPoint(lat, lng);
      final p = spreadStackedPoint(lat, lng, 9);
      final d = distM(origin, p);
      expect(d, greaterThan(2.5));
      expect(d, lessThan(3.5));
    });

    test('同環 8 點彼此不重合（DB 實際最多 8 棵疊點全部可見）', () {
      final points = <SpreadPoint>[
        for (var i = 0; i < 8; i++) spreadStackedPoint(lat, lng, i),
      ];
      for (var i = 0; i < points.length; i++) {
        for (var j = i + 1; j < points.length; j++) {
          expect(distM(points[i], points[j]), greaterThan(0.5),
              reason: '點 $i 與 $j 應至少相距 0.5m');
        }
      }
    });

    test('確定性：同 index 永遠同位置（地圖重繪不漂移）', () {
      final a = spreadStackedPoint(lat, lng, 3);
      final b = spreadStackedPoint(lat, lng, 3);
      expect(a.lat, b.lat);
      expect(a.lng, b.lng);
    });

    test('位移幅度不影響縣市歸屬（<5m，遠小於行政邊界精度）', () {
      const origin = SpreadPoint(lat, lng);
      for (var i = 0; i <= 20; i++) {
        final p = spreadStackedPoint(lat, lng, i);
        expect(distM(origin, p), lessThan(5.0));
      }
    });
  });

  group('nextSpreadPoint（計數器整合）', () {
    test('同座標依序遞增展開、不同座標互不影響', () {
      final counter = <String, int>{};
      final p1 = nextSpreadPoint(counter, lat, lng);
      final p2 = nextSpreadPoint(counter, lat, lng);
      final p3 = nextSpreadPoint(counter, lat, lng);
      final other = nextSpreadPoint(counter, 24.0, 121.0);

      expect(p1.lat, lat); // 第一棵原地
      expect(distM(p1, p2), greaterThan(1.0)); // 第二棵展開
      expect(distM(p2, p3), greaterThan(0.5)); // 第三棵與第二棵不同位
      expect(other.lat, 24.0); // 不同座標的第一棵不位移
    });

    test('7066 棵不同座標展開計算 < 100ms（效能保險）', () {
      final counter = <String, int>{};
      final sw = Stopwatch()..start();
      for (var i = 0; i < 7066; i++) {
        nextSpreadPoint(counter, 22.0 + i * 0.0001, 120.0 + i * 0.0001);
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(100));
    });
  });
}
