import 'package:flutter/material.dart';

/// 新增樹木流程 Step 1 的「區邊界狀態」橫幅。
///
/// 為什麼是獨立 widget：原本用 `Chip` 包長字串（如
/// 「尚未畫邊界（手動模式，GPS 不限制；N 棵有 GPS）」），`Chip` 不會折行，
/// 在窄螢幕（如 Mi A1）會撐爆其內部 `Row` 造成 `RenderFlex overflow`。
/// 改為可換行容器（圖示 + `Expanded(Text)`），文字自動折行；抽成獨立 widget
/// 以便用 widget test 在窄寬度直接驗證不再溢位。
class BoundaryStatusBanner extends StatelessWidget {
  final bool hasBoundary;

  /// 目前 GPS 位置是否落在邊界內（僅 [hasBoundary] 為 true 時影響文案）。
  final bool isLocationValid;

  /// 該區目前有 GPS 座標的樹木數（無邊界時提示用）。
  final int treeCountWithGps;

  const BoundaryStatusBanner({
    super.key,
    required this.hasBoundary,
    required this.isLocationValid,
    required this.treeCountWithGps,
  });

  @override
  Widget build(BuildContext context) {
    final icon = hasBoundary
        ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
        : const Icon(Icons.info_outline, color: Colors.orange, size: 18);
    final text = hasBoundary
        ? '區已有邊界${isLocationValid ? '' : '（目前位置在邊界外）'}'
        : '尚未畫邊界（手動模式，GPS 不限制；$treeCountWithGps 棵有 GPS）';
    final bg = hasBoundary ? Colors.green.shade50 : Colors.orange.shade50;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
