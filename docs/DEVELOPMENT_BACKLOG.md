# 開發待辦清單（持續更新）

> 與 `SYSTEM_HANDOFF_MANUAL.md` 互補：本檔追蹤**尚未完成**的補強與下一階段功能。  
> 完成項請打 `[x]`，並簡述 commit 或 PR。

---

## 進行中（開發優先）

- [x] **歷次量測 schema** — `tree_survey_measurements` 表 + migration `15_*`
- [x] **transfer 寫入歷次** — 初測 `new`、維護 `maintenance` 皆 INSERT 歷次，維護仍 UPDATE 最新快照
- [x] **歷次查詢 API** — `GET /tree-survey/by_id/:id/measurements`
- [x] **維護量測入口** — `MaintenanceSurveyPage`：區 → 樹清單 → 重測/新增 → BLE
- [x] **歷史紀錄 UI** — 整合表單（維護任務）+ 樹詳情頁 `TreeMeasurementHistoryPanel`
- [x] **物種辨識填入** — 整合表單改中文俗名優先（學名對照）
- [x] **ID 顯示慣例** — `TreeIdDisplay`：現場純數字、系統 ST- 完整

---

## P2 — 現場逐棵流程可選補強

| 狀態 | 項目 | 說明 |
|------|------|------|
| [x] | 場中換專案/區 | AppBar 切換 + 已完成樹木警示 |
| [x] | 斷線自動重連 | 重連面板、表單中暫停、手動重連、NUS 優先 |
| [x] | GPS 失敗重測按鈕 | 保留 PHGF + 橫幅/SnackBar「重測 GPS」 |
| [x] | ID 對齊 SOP | 見下方「ID 顯示慣例」 |
| [x] | 維護量測地圖入口 | 分段切換、底部確認、即時搜尋過濾 |

### ID 顯示慣例（現場 SOP）

| 情境 | 顯示 | DB 儲存 |
|------|------|---------|
| 現場列表／地圖 | 專案樹號 **純數字**（`PT-123` → `123`） | 完整 `PT-123` |
| 系統對照 | 小字 `ST-xxx`（`TreeIdDisplay.fieldListLabel`） | 完整 `ST-xxx` |
| 管理後台／詳情 | 可顯示完整前綴 | 不變 |

實作：`lib/utils/tree_id_display.dart`。新 UI 請沿用，勿在現場再造另一套編號格式。

---

## 中優先 — 多人同時使用 / 資料完整性

| 狀態 | 項目 | 風險 | 位置 |
|------|------|------|------|
| [x] | transfer 併發重複樹木 | 重複 INSERT | `pending_measurements.js` — `6f087b5` |
| [x] | 樹木 ID advisory lock 不統一 | 撞號 | `csvImportController.js` — `d5f045c` |
| [x] | update_v2 漏 ROLLBACK | 連線池耗盡 | `treeSurveyUpdateController.js` — `d5f045c` |
| [x] | system_tree_id 唯一約束 | 靜默重複 | migration `14_tree_survey_unique_ids` — `d5f045c` |
| [x] | CSV 匯入部分失敗仍 COMMIT | 資料不一致 | `csvImportController.js` — 有錯 ROLLBACK |
| [x] | tree_images 缺專案權限 | 跨專案掛圖/讀圖 | `routes/tree_images.js` |
| [x] | management 缺專案權限 | 跨專案建議 | `routes/management.js` + controller |
| [x] | 部分 reports 缺 projectAuth | 跨專案統計 | `routes/reports.js` + `reportController.js` |
| [x] | 舊版 XLSX `/import` 無鎖 | 併發撞號 | `routes/treeSurvey.js` — advisory lock + 專案權限 |
| [x] | pending PATCH 樂觀鎖 | UPDATE 未帶 `updated_at` | `pending_measurements.js` |

---

## 驗證備註 — BLE / GPS（2026-06 電腦實測）

- [x] 第二棵 SEND §9.3 前綴黏接 — 12 棵連續 SEND 通過（`verify_vlgeo2_gps_ble.py`）
- [x] 儀器 BLE 逐棵 SEND **不送 GPS NMEA** — 現場用手機 GPS 定案
- PHGF 實際從 **NUS TX** 進來；Haglof TX 僅 §9.3 前綴（APP 訂閱邏輯待觀察）
- 單元測試：`flutter test test/ble_live_nmea_test.dart`

---

## 資料庫 / 歷史紀錄（2026-06）

- [x] **2NF 邊界 code 回填** — migration `16_project_boundaries_backfill.pg.sql`
- [x] **歷次 baseline 回填** — migration `17_*`（無歷次之既有樹 → `snapshot` 一筆）
- [x] **歷次 API 分頁** — `GET measurements?limit&offset` + `total`
- [x] **歷史 UI 深化** — 時間軸、展開詳情、H/DBH 變化、載入更多、維護選樹預覽

---

## 文件 / 管理工具

- [x] **系統交接手冊更新** — `SYSTEM_HANDOFF_MANUAL.md`（2026-06-05 同步現況）
- [x] **CSV 匯入失敗 UX** — 全批 ROLLBACK 時顯示錯誤明細與復原說明
- [x] **一般使用者操作手冊**（非技術 SOP）— `FIELD_SURVEY_SOP.md`
- [x] **2026-05-28 會議紀錄** — `MEETING_MINUTES_20260528.md`
- [x] **文件索引與交接清單** — `docs/README.md`、`HANDOFF_SECRETS_CHECKLIST.md`
- [x] **Release 現場日誌** — `FieldLog` + BLE 頁複製日誌 + `ENABLE_FIELD_LOGS`
- [ ] **整理資料夾結構** — 待下一階段
- [ ] **註解重寫**（對齊程式碼、去除 AI 口吻）— 待下一階段

---

## 暫緩 / 取消

- **暫緩**：批次藍牙匯入擴充
- **取消**：外接 GNSS（LG290P）模組
