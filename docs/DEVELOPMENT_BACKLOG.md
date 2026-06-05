# 開發待辦清單（持續更新）

> 與 `SYSTEM_HANDOFF_MANUAL.md` 互補：本檔追蹤**尚未完成**的補強與下一階段功能。  
> 完成項請打 `[x]`，並簡述 commit 或 PR。

---

## 進行中（開發優先）

- [x] **歷次量測 schema** — `tree_survey_measurements` 表 + migration `15_*`
- [x] **transfer 寫入歷次** — 初測 `new`、維護 `maintenance` 皆 INSERT 歷次，維護仍 UPDATE 最新快照
- [x] **歷次查詢 API** — `GET /tree-survey/by_id/:id/measurements`
- [ ] **維護量測入口** — 區 → 樹清單/地圖 → 選樹 → BLE 逐棵重測 + 新增樹木
- [ ] **歷史紀錄 UI** — 整合表單頁 + 樹詳情頁時間序列（日期/樹高/DBH）

---

## P2 — 現場逐棵流程可選補強

| 狀態 | 項目 | 說明 |
|------|------|------|
| [ ] | 場中換專案/區 | 目前需退出連線重設場次；加場中切換 UI |
| [ ] | 斷線自動重連 | 目前只顯示「連線已中斷」 |
| [ ] | GPS 失敗重測按鈕 | 橘色提示外，加明確「重測此棵」流程 |
| [ ] | ID 對齊 | 會議尚未定案；SOP 註明現階段假設與限制 |

---

## 中優先 — 多人同時使用 / 資料完整性

| 狀態 | 項目 | 風險 | 位置 |
|------|------|------|------|
| [x] | transfer 併發重複樹木 | 重複 INSERT | `pending_measurements.js` — `6f087b5` |
| [x] | 樹木 ID advisory lock 不統一 | 撞號 | `csvImportController.js` — `d5f045c` |
| [x] | update_v2 漏 ROLLBACK | 連線池耗盡 | `treeSurveyUpdateController.js` — `d5f045c` |
| [x] | system_tree_id 唯一約束 | 靜默重複 | migration `14_tree_survey_unique_ids` — `d5f045c` |
| [ ] | CSV 匯入部分失敗仍 COMMIT | 資料不一致 | `csvImportController.js` |
| [ ] | tree_images 缺專案權限 | 跨專案掛圖/讀圖 | `routes/tree_images.js` |
| [ ] | management 缺專案權限 | 跨專案建議 | `routes/management.js` |
| [ ] | 部分 reports 缺 projectAuth | 跨專案統計 | `routes/reports.js` |
| [ ] | 舊版 XLSX `/import` 無鎖 | 併發撞號 | `routes/treeSurvey.js` |
| [ ] | pending PATCH 樂觀鎖 | UPDATE 未帶 `updated_at` | `pending_measurements.js` |

---

## 驗證備註 — 第二棵 SEND

- 程式與單元測試已覆蓋 §9.3 前綴 + 連續兩棵 PHGF（`test/ble_live_nmea_test.dart`）。
- **不確定時**：手邊有儀器可在電腦先跑  
  `test/vlgeo2_ble_analysis/verify_vlgeo2_gps_ble.py`（nRF Connect 或腳本連 BLE），  
  或 `flutter test test/ble_live_nmea_test.dart` 回歸解碼邏輯。
- 實機異常請保留 BLE log（`ble_live_session_page` 畫面下方）再對照。

---

## 暫緩 / 取消

- **暫緩**：批次藍牙匯入擴充
- **取消**：外接 GNSS（LG290P）模組
