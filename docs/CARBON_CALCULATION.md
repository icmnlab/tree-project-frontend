# 碳匯計算 — 欄位、公式與文獻

## tree_survey 欄位（請勿合併為單一數值）

| 欄位 | 中文 | 單位 | 意義 |
|------|------|------|------|
| `carbon_storage` | 碳儲存量 | kg CO₂e | 單木**現況**碳儲量（存量） |
| `carbon_sequestration_per_year` | 推估年碳吸存量 | kg CO₂e/年 | **每年**固碳量（流量） |

UI 上合併為**一張卡片、兩列資料**即可；數值上不能只留下其中一個，否則統計頁「總年碳吸存量」與論文敘述會失真。

## 客戶端可重算項目

依 **農業部《森林碳匯調查與監測手冊》第六章**（與後端 `handbookCarbonService.js` 一致）：

1. 材積 V：表 6-2 / 6-3（`assets/coa/coa_volume_equations.json`）
2. 地上生物量：V × D × BEF（表 6-4）
3. 總生物量：× (1 + R)
4. 碳量：× CF
5. CO₂e：× (44/12) × 1000 → **kg CO₂e** 寫入 `carbon_storage`

程式入口：

- 前端：`HandbookCarbonService` / `CarbonCalculationService`
- 後端：`services/handbookCarbonService.js`（預設）、`CARBON_CALC_LEGACY_TIPC=1` 時 TIPC 相容式

## 推估年碳吸存量（手冊與系統現況）

**《森林碳匯調查與監測手冊》第六章**主軸是**單木碳儲存量（存量）**：材積 → 生物量 → 碳量 → CO₂e，對應本系統 `carbon_storage`。

**年碳吸存量（流量）**在手冊中通常屬**生長量／增量**或專案方法學的**年度排碳量估算**，需樹齡、生長率或平台專用參數；**第六章未提供與 `carbon_storage` 同一條、可直接由 DBH+H 一步算出的年流量公式**。實務上常見來源：

| 來源 | 說明 |
|------|------|
| 歷史 TIPC 平台匯入 | 7044 筆等既有資料帶入 `carbon_sequestration_per_year` |
| 外部生長模型／專案方法學 | 需額外輸入樹齡或年度增量，未納入 App 客端重算 |
| 統計加總 | `SUM(carbon_sequestration_per_year)` 僅對**已有欄位值**的列有效 |

因此：**App／後端 `handbookCarbonService` 只重算 `carbon_storage`，不重算年流量**；新建或轉移樹木若無匯入值，年欄位為 NULL，UI 顯示「—」。

## 客戶端不重算項目

- **`carbon_sequestration_per_year`**：手冊第六章無公開之 DBH+H 年流量公式；TIPC 平台樹齡相關公式未公開。編輯表單僅顯示／提交 DB 既有值。

## 文獻（論文與口試請引用）

1. 農業部林業及自然保育署 (2024). *森林碳匯調查與監測手冊*.
2. 環境部 (2023). *溫室氣體減量方法學 AR-TMS0001 造林與植林碳匯專案活動* v01.0.
3. 後端 `carbonCalculationService.js` 註解：TIPC 逆向驗證與針闊葉常數簡化說明（論文需揭露偏差）。

## 顯示規範

全系統標籤與單位見 `lib/utils/carbon_display.dart`。
