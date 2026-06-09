import 'dart:math' as math;

/// Dart 端網格聚合（grid clustering）。
///
/// 為什麼不用 google_maps_flutter 原生 ClusterManager：
/// 該 plugin 的 ClusterManagersController 每 addItem 一次就觸發一次原生
/// re-cluster AsyncTask，7000+ 標記會塞爆 Android ThreadPoolExecutor 的
/// 128 佇列 → RejectedExecutionException（實機已重現）。
/// Dart 端先聚合再下發少量 marker，行為完全可控：
/// - zoom < 門檻：依螢幕約 80px 的網格聚合成「N 棵」圓點
/// - zoom ≥ 門檻：一律顯示個別標記（不會出現「放大了還是數字」）
class TreeCluster<T> {
  final double lat;
  final double lng;
  final List<T> members;

  const TreeCluster({
    required this.lat,
    required this.lng,
    required this.members,
  });

  int get count => members.length;
  bool get isSingle => members.length == 1;
}

/// 依 zoom 計算網格邊長（度）。約等於螢幕 [cellPx] 像素（Web Mercator 估算）。
double clusterCellSizeDeg(double zoom, {double cellPx = 80}) {
  return cellPx * 360.0 / (256.0 * math.pow(2.0, zoom));
}

/// 將點位聚合成網格 cluster。
///
/// [latOf]/[lngOf] 從元素取座標；回傳的 cluster 座標為成員質心。
List<TreeCluster<T>> gridCluster<T>(
  List<T> items,
  double zoom, {
  required double Function(T) latOf,
  required double Function(T) lngOf,
  double cellPx = 80,
}) {
  if (items.isEmpty) return const [];
  final cell = clusterCellSizeDeg(zoom, cellPx: cellPx);
  final buckets = <String, List<T>>{};

  for (final item in items) {
    final lat = latOf(item);
    final lng = lngOf(item);
    final key = '${(lat / cell).floor()}_${(lng / cell).floor()}';
    buckets.putIfAbsent(key, () => []).add(item);
  }

  final clusters = <TreeCluster<T>>[];
  for (final members in buckets.values) {
    double sumLat = 0, sumLng = 0;
    for (final m in members) {
      sumLat += latOf(m);
      sumLng += lngOf(m);
    }
    clusters.add(TreeCluster<T>(
      lat: sumLat / members.length,
      lng: sumLng / members.length,
      members: members,
    ));
  }
  return clusters;
}

/// 聚合圓點上的數字標籤（>999 顯示 k）。
String clusterLabel(int count) {
  if (count < 1000) return '$count';
  final k = count / 1000.0;
  return k >= 10 ? '${k.round()}k' : '${k.toStringAsFixed(1)}k';
}

/// 依數量決定圓點直徑（px，再乘 devicePixelRatio）。
double clusterDiameter(int count) {
  if (count < 10) return 40;
  if (count < 100) return 48;
  if (count < 1000) return 56;
  return 64;
}
