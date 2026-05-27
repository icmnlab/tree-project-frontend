/// tree_survey 碳匯欄位 — 顯示名稱、單位與文獻說明（全系統一致）
///
/// 資料庫欄位（不可合併為單一數值）：
/// - [fieldStorage] 單木現況碳儲量（存量, stock）
/// - [fieldAnnual] 推估年固碳量（流量, flow）；客戶端不重算，僅讀 DB
class CarbonDisplay {
  CarbonDisplay._();

  static const String fieldStorage = 'carbon_storage';
  static const String fieldAnnual = 'carbon_sequestration_per_year';

  /// 詳情頁區塊標題（一張卡片內含兩列，非兩個獨立區塊）
  static const String sectionTitle = '碳匯（tree_survey）';

  static String rowLabelStorage() => '$fieldStorage（碳儲存量）';
  static String rowLabelAnnual() => '$fieldAnnual（推估年碳吸存量）';

  static String formLabelStorage() => '碳儲存量 $fieldStorage (kg CO₂e)';
  static String formLabelAnnual() =>
      '推估年碳吸存量 $fieldAnnual (kg CO₂e/年)';

  static String previewLabelStorage() =>
      '預估 $fieldStorage（手冊第六章）';

  static String formatStorage(double? kgCo2e) {
    if (kgCo2e == null || kgCo2e <= 0) return '—';
    return '${kgCo2e.toStringAsFixed(2)} kg CO₂e';
  }

  static String formatAnnual(double? kgCo2ePerYear) {
    if (kgCo2ePerYear == null || kgCo2ePerYear <= 0) {
      return '—（資料庫無值；客戶端不重算）';
    }
    return '${kgCo2ePerYear.toStringAsFixed(2)} kg CO₂e/年';
  }

  static const String methodologyStorage =
      '碳儲存量依農業部林業及自然保育署《森林碳匯調查與監測手冊》第六章：'
      '材積式（表 6-2／6-3）→ 地上生物量 → 總生物量（含根莖比 R）→ 碳量（CF）→ CO₂e（44/12）；'
      '係數見表 6-4。與環境部溫室氣體減量方法學 AR-TMS0001 造林植林專案一致。';

  static const String methodologyAnnual =
      '$fieldAnnual 為年度固碳流量（kg CO₂e/年），與 $fieldStorage（存量）不同。'
      '手冊第六章僅規範碳儲存量試算，年吸存量需生長量／樹齡或平台參數；'
      '本 App 僅顯示資料庫既有值（TIPC 匯入或 CSV），客端不重算。';

  /// 詳情頁「計算依據」列：年流量
  static String calculationBasisAnnual(double? dbAnnual) {
    if (dbAnnual != null && dbAnnual > 0) {
      return '資料庫欄位 $fieldAnnual（匯入或平台歷史值）';
    }
    return '無 $fieldAnnual；手冊第六章無 DBH+H 年流量公式，未試算';
  }

  /// 詳情頁「計算依據」列：存量
  static String calculationBasisStorage({required bool fromDb}) {
    if (fromDb) {
      return '資料庫欄位 $fieldStorage';
    }
    return '手冊第六章重算 → $fieldStorage';
  }

  static const List<String> literatureRefs = [
    '農業部林業及自然保育署 (2024). 森林碳匯調查與監測手冊.',
    '環境部 (2023). 溫室氣體減量方法學 AR-TMS0001 造林與植林碳匯專案活動 v01.0.',
  ];
}
