import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/widgets/boundary_status_banner.dart';

/// 回歸測試：新增樹木 Step 1 的「區邊界狀態」橫幅在窄螢幕不得 RenderFlex 溢位。
///
/// 舊版用 `Chip` 包長字串，在窄寬度會撐爆內部 Row（曾見「78px on the right」）。
/// 現用 `BoundaryStatusBanner`（Expanded 文字自動折行）。本測試在極窄寬度
/// pump 真實 widget，並以 `tester.takeException()` 斷言沒有溢位例外。
void main() {
  Future<void> pumpAtWidth(
    WidgetTester tester,
    double width,
    Widget child,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('窄寬度 (180px) 無邊界長字串不溢位', (tester) async {
    await pumpAtWidth(
      tester,
      180,
      const BoundaryStatusBanner(
        hasBoundary: false,
        isLocationValid: false,
        treeCountWithGps: 123,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BoundaryStatusBanner), findsOneWidget);
  });

  testWidgets('極窄寬度 (120px) 有邊界 + 界外提示不溢位', (tester) async {
    await pumpAtWidth(
      tester,
      120,
      const BoundaryStatusBanner(
        hasBoundary: true,
        isLocationValid: false,
        treeCountWithGps: 0,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('一般寬度 (360px) 顯示有邊界文案', (tester) async {
    await pumpAtWidth(
      tester,
      360,
      const BoundaryStatusBanner(
        hasBoundary: true,
        isLocationValid: true,
        treeCountWithGps: 5,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('區已有邊界'), findsOneWidget);
  });
}
