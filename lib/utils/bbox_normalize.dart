import 'dart:ui';

/// 將像素座標 bbox 正規化為 [left, top, right, bottom]（0–1，相對影像寬高）
List<double>? normalizeBbox(Rect? bbox, Size? imageSize) {
  if (bbox == null || imageSize == null) return null;
  final w = imageSize.width;
  final h = imageSize.height;
  if (w <= 0 || h <= 0) return null;
  return [
    (bbox.left / w).clamp(0.0, 1.0),
    (bbox.top / h).clamp(0.0, 1.0),
    (bbox.right / w).clamp(0.0, 1.0),
    (bbox.bottom / h).clamp(0.0, 1.0),
  ];
}

/// 正規化 bbox 轉回像素 Rect
Rect? denormalizeBbox(List<double>? normalized, Size imageSize) {
  if (normalized == null || normalized.length < 4) return null;
  return Rect.fromLTRB(
    normalized[0] * imageSize.width,
    normalized[1] * imageSize.height,
    normalized[2] * imageSize.width,
    normalized[3] * imageSize.height,
  );
}
