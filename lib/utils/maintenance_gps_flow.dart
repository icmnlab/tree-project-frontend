import 'package:flutter/material.dart';

import 'field_gps_capture.dart';

/// 維護重測：SEND 後是否更新樹位 GPS 的決策（可單元測試）。
class MaintenanceGpsDecision {
  final bool updateTreeLocation;
  final FieldGpsCaptureResult? capturedGps;

  const MaintenanceGpsDecision._({
    required this.updateTreeLocation,
    this.capturedGps,
  });

  factory MaintenanceGpsDecision.keepExistingCoords() {
    return const MaintenanceGpsDecision._(updateTreeLocation: false);
  }

  factory MaintenanceGpsDecision.updateWithGps(FieldGpsCaptureResult gps) {
    return MaintenanceGpsDecision._(
      updateTreeLocation: true,
      capturedGps: gps,
    );
  }

  bool get cancelled => false;
}

/// 依決策解析 pending 用的 GPS 座標。
/// 不更新時沿用原樹座標；若原樹無座標則回傳 null（需改選更新 GPS）。
FieldGpsCaptureResult? resolveMaintenancePendingGps({
  required MaintenanceGpsDecision decision,
  required double? existingLat,
  required double? existingLon,
}) {
  if (decision.updateTreeLocation) {
    return decision.capturedGps;
  }
  if (existingLat == null ||
      existingLon == null ||
      existingLat == 0 ||
      existingLon == 0) {
    return null;
  }
  return FieldGpsCaptureResult(
    latitude: existingLat,
    longitude: existingLon,
    accuracyM: 0,
    sampleCount: 0,
    mode: 'existing',
  );
}

/// 維護重測 SEND 後：先問是否更新樹位；若要才開 GPS 定位。
Future<MaintenanceGpsDecision?> showMaintenanceRemeasureGpsFlow(
  BuildContext context, {
  String? treeLabel,
}) async {
  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('更新樹位 GPS？'),
      content: Text(
        treeLabel != null && treeLabel.isNotEmpty
            ? '重測 $treeLabel\n\n預設沿用原座標。僅在樹位明顯偏移或重植後才更新 GPS。'
            : '預設沿用原座標。僅在樹位明顯偏移或重植後才更新 GPS。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('不更新'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('更新 GPS'),
        ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return null;
  if (!choice) {
    return MaintenanceGpsDecision.keepExistingCoords();
  }
  final gps = await showFieldGpsCaptureDialog(
    context,
    mode: 'tree',
    title: '更新樹位 GPS',
  );
  if (gps == null || !context.mounted) return null;
  return MaintenanceGpsDecision.updateWithGps(gps);
}
