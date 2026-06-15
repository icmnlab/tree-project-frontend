import 'package:flutter/material.dart';

/// BLE 連線就緒面板（等待儀器送出量測的畫面）。
///
/// 為什麼是獨立 widget：卡片內為固定高內容（圖示 52 + 標題 + 三步驟 +
/// 等待提示），在矮螢幕或上方狀態列較高時，外層 `Expanded` 配到的高度可能
/// 小於內容，造成 `RenderFlex overflowed ... on the bottom`。
/// 這裡用 `LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight)
/// + IntrinsicHeight`：空間足時 `Spacer` 仍把按鈕推到底；空間不足時改為可捲動，
/// 永不溢出。文案以參數傳入（避免相依 localization），便於 widget test 在
/// 極窄/極矮尺寸直接驗證不溢位。
class BleReadyPanel extends StatelessWidget {
  /// 是否已收到至少一筆量測（影響圖示與是否顯示等待提示）。
  final bool hasData;

  final String title;
  final String step1;
  final String step2;
  final String step3;

  /// 尚未收到資料時的等待提示。
  final String waitingText;

  /// 「掃描其他裝置」按鈕文案。
  final String scanOtherLabel;

  /// 是否顯示「掃描其他裝置」按鈕（處理中時隱藏）。
  final bool showScanOther;

  final VoidCallback onScanOther;

  const BleReadyPanel({
    super.key,
    required this.hasData,
    required this.title,
    required this.step1,
    required this.step2,
    required this.step3,
    required this.waitingText,
    required this.scanOtherLabel,
    required this.showScanOther,
    required this.onScanOther,
  });

  Widget _readyStep(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.arrow_right, size: 20, color: Colors.green.shade700),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    Card(
                      elevation: 0,
                      color: Colors.green.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              hasData ? Icons.check_circle : Icons.touch_app,
                              size: 52,
                              color: Colors.green.shade700,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            _readyStep(step1),
                            _readyStep(step2),
                            _readyStep(step3),
                            if (!hasData) ...[
                              const SizedBox(height: 16),
                              Text(
                                waitingText,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (showScanOther)
                      TextButton.icon(
                        onPressed: onScanOther,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: Text(scanOtherLabel),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
