import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sustainable_treeai/widgets/ble/ble_ready_panel.dart';

/// 回歸測試：BLE 連線就緒面板在矮螢幕不得 RenderFlex 溢位（曾見「11px on the
/// bottom」）。現用 LayoutBuilder + SingleChildScrollView，空間不足時可捲動。
/// 本測試在極矮高度 pump 真實 widget，並以 `tester.takeException()` 斷言無溢位。
void main() {
  Widget buildPanel({
    required bool hasData,
    required bool showScanOther,
  }) {
    return BleReadyPanel(
      hasData: hasData,
      title: '儀器已連線，等待量測資料',
      step1: '在儀器上完成一次測高量測',
      step2: '按 SEND 將資料藍牙送出到手機',
      step3: 'App 收到後會自動帶入本棵樹的表單',
      waitingText: '尚未收到量測資料，請在儀器上按 SEND…',
      scanOtherLabel: '掃描其他裝置',
      showScanOther: showScanOther,
      onScanOther: () {},
    );
  }

  Future<void> pumpAtSize(
    WidgetTester tester,
    Size size,
    Widget child,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('矮高度 (120px) 等待中不溢位（改為可捲動）', (tester) async {
    await pumpAtSize(
      tester,
      const Size(360, 120),
      buildPanel(hasData: false, showScanOther: true),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(BleReadyPanel), findsOneWidget);
    // 內容超過視窗 → 應為可捲動
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('極矮高度 (80px) 仍不溢位', (tester) async {
    await pumpAtSize(
      tester,
      const Size(320, 80),
      buildPanel(hasData: true, showScanOther: false),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('高度充足 (800px) 顯示掃描其他裝置按鈕、不溢位', (tester) async {
    await pumpAtSize(
      tester,
      const Size(400, 800),
      buildPanel(hasData: false, showScanOther: true),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('掃描其他裝置'), findsOneWidget);
  });
}
