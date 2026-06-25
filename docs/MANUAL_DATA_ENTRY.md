# 手動新增與編輯（調查員／開發對照）

> 補充 [`FIELD_SURVEY_SOP.md`](FIELD_SURVEY_SOP.md)（該 SOP 以 **BLE 現場逐棵** 為主）。  
> 完整 API 與歷次語意見 [`HANDOFF.md`](HANDOFF.md) §8.1、[`SURVEY_HISTORY.md`](SURVEY_HISTORY.md)。

---

## 路徑總表

| 模式 | APP 入口 | 畫面 | API | 寫歷次 |
|------|----------|------|-----|--------|
| **現場 BLE** | 首頁「VLGEO2 現場連線」 | `BleLiveSessionPage` → `IntegratedTreeFormPage` | `POST .../transfer` | ✅ |
| **藍牙批次／待測量** | 「藍牙匯入」→「待測量任務」 | `BleImportPage` / `PendingMeasurementTaskPage` | 同上 `transfer` | ✅ |
| **智慧模式** | 樹木調查 → 新增 → **智慧** | `ManualInputPageV3` | `POST /api/tree_survey/create_v2` | ✅ |
| **快速模式** | 樹木調查 → 新增 → **快速** | `TreeInputPageV2` | `POST /api/tree_survey/create_v2` | ✅ |
| **編輯** | 樹木詳情 → 編輯 | `TreeEditPageV2` | `PUT /api/tree_survey/update_v2/:id` | ❌ 刻意不寫 |

---

## 智慧 vs 快速（調查員）

| 項目 | 智慧模式 | 快速模式 |
|------|----------|----------|
| 適合 | 需引導、自動帶入區位等 | 熟練調查員快速鍵入 |
| 畫面 | 步驟較完整（V3） | 欄位較精簡（V2） |
| API | 相同 `create_v2` | 相同 `create_v2` |
| 差異 | 較快速模式少送部分備註分欄 | 含 `tree_remark`／`survey_notes` 等 |

DBH、樹種、座標、碳儲量等核心欄位四路一致；細節見 `HANDOFF.md` §8.1。

---

## 編輯（調查員）

- 入口：樹木列表或詳情 → **編輯**
- 更新主檔 `tree_survey`；**不新增**歷次量測列（維護重測請走 BLE／待測量，會寫歷次）
- 後端：`routes/treeSurvey.js` 的 `update_v2`

---

## 開發者 trace 起點

| 模式 | 建議先開 |
|------|----------|
| 智慧 | `lib/screens/v3/manual_input_page_v3.dart` |
| 快速 | `lib/tree_input_page_v2.dart` |
| 編輯 | `lib/tree_edit_page_v2.dart` |
| 共用 API | `lib/services/api_service.dart`（或 tree survey 相關 service）、`backend/routes/treeSurvey.js` |

---

## 與 BLE 現場的差異（一句話）

- **BLE／待測量**：儀器資料先進 **pending**，完成表單後 **transfer** 進正式庫。  
- **智慧／快速**：跳過 pending，直接 **create_v2** 寫入 `tree_survey`（並寫首筆歷次）。
