import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/utils/tree_marker_cluster.dart';

typedef Pt = ({double lat, double lng});

List<TreeCluster<Pt>> cluster(List<Pt> pts, double zoom) => gridCluster<Pt>(
      pts,
      zoom,
      latOf: (p) => p.lat,
      lngOf: (p) => p.lng,
    );

void main() {
  group('gridCluster', () {
    test('空清單回傳空', () {
      expect(cluster([], 10), isEmpty);
    });

    test('低縮放時鄰近點聚成一個 cluster', () {
      // 同一公園內 ~100m 內的 5 個點，zoom 10 的網格遠大於 100m
      final pts = List.generate(
          5, (i) => (lat: 23.9000 + i * 0.0002, lng: 121.5400 + i * 0.0002));
      final result = cluster(pts, 10);
      expect(result.length, 1);
      expect(result.first.count, 5);
      expect(result.first.isSingle, isFalse);
    });

    test('高縮放時同樣的點各自獨立', () {
      final pts = List.generate(
          5, (i) => (lat: 23.9000 + i * 0.01, lng: 121.5400 + i * 0.01));
      final result = cluster(pts, 18);
      expect(result.length, 5);
      expect(result.every((c) => c.isSingle), isTrue);
    });

    test('cluster 座標為成員質心', () {
      final pts = [
        (lat: 23.0, lng: 121.0),
        (lat: 23.0002, lng: 121.0002),
      ];
      final result = cluster(pts, 8);
      expect(result.length, 1);
      expect(result.first.lat, closeTo(23.0001, 1e-9));
      expect(result.first.lng, closeTo(121.0001, 1e-9));
    });

    test('成員總數守恆（不丟點）', () {
      final pts = List.generate(
          500,
          (i) => (
                lat: 21.9 + (i % 50) * 0.05,
                lng: 120.0 + (i ~/ 50) * 0.05,
              ));
      for (final zoom in [5.0, 8.0, 11.0, 14.0, 17.0]) {
        final total =
            cluster(pts, zoom).fold<int>(0, (sum, c) => sum + c.count);
        expect(total, 500, reason: 'zoom=$zoom 不可丟點');
      }
    });

    test('7000 點聚合在 100ms 內完成（效能保險）', () {
      final pts = List.generate(
          7000,
          (i) => (
                lat: 21.9 + (i % 300) * 0.01,
                lng: 120.0 + (i ~/ 300) * 0.01,
              ));
      final sw = Stopwatch()..start();
      cluster(pts, 9);
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(100));
    });
  });

  group('clusterCellSizeDeg', () {
    test('zoom 越大網格越小', () {
      expect(clusterCellSizeDeg(12), lessThan(clusterCellSizeDeg(8)));
    });
  });

  group('clusterLabel', () {
    test('一般數字直接顯示', () {
      expect(clusterLabel(7), '7');
      expect(clusterLabel(999), '999');
    });
    test('千以上以 k 表示', () {
      expect(clusterLabel(1234), '1.2k');
      expect(clusterLabel(12000), '12k');
    });
  });

  group('clusterDiameter', () {
    test('數量越大圓點越大且有上限', () {
      expect(clusterDiameter(5), lessThan(clusterDiameter(50)));
      expect(clusterDiameter(50), lessThan(clusterDiameter(500)));
      expect(clusterDiameter(99999), 64);
    });
  });
}
