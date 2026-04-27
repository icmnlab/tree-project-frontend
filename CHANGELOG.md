# Changelog

所有主要版本變更記錄。

---

## v18.5.1 (2026-04-28) — V3 species refactor + docs cleanup

### V3 樹種辨識
- `lib/screens/v3/integrated_tree_form_page.dart` · `lib/screens/v3/manual_input_page_v3.dart`
  - 顯示名稱改用學名 (`scientificNameWithoutAuthor`)；中文俗名只在 snackbar 提示
  - 移除手動「新增樹種」按鈕；改在提交時用 `_ensureSpeciesId()` 自動建檔（先 server-side searchSpecies → 找不到才 POST /tree_species）
  - TextFormField onChanged 編輯時自動清掉舊 _speciesId，避免誤套到別的樹

### AI Chat
- `lib/screens/ai_chat_page.dart`：修掉之前的 chat-leak

### 公開文件清理
- README 加完整架構圖（Flutter ↔ backend ↔ ml_service 雙路徑），已升級為 Mermaid
- 移除 README/CHANGELOG 內所有硬寫的 Tailscale hostname/IP

---

## v18.5.0 (2026-03-10) - Self-Hosted Server Support

### 自架伺服器支援
- 新增 `Environment.selfHosted` → 自架伺服器（預設；實際主機由 `lib/config/app_config.dart` 決定，不在 repo 中以明碼公開）
- Admin UI 改為 3 環境切換按鈕（selfHosted / prod / staging）
- 各環境獨立圖示與顏色標識

### 變更檔案
| 類型 | 檔案 | 說明 |
|------|------|------|
| feat | `lib/config/app_config.dart` | 新增 selfHosted 環境 |
| feat | `lib/admin_page.dart` | 3 環境切換 UI |

---

## v18.4.0 (2026-02-22) - App Stabilization & ML Precision Upgrade

### 測量與精準度
- EXIF 焦距提取與 GPS 保護機制
- 多相片融合 UI (Multi-shot fusion)
- Stakeout 導航 + 拍照指南 (Photo Guide)

### UX 優化
- Dashboard UX 翻新：三區塊分類 + 拖曳排序
- BLE 測量 pipeline：race conditions 修復 + Fused Location
- Type Cast Safety 強化
- 中英雙語 Key 支援

---

## v18.3.2 (2025-12-14) - 專案管理邏輯修正

- V2/V3 退出時自動清理未提交的專案區位、專案名稱、樹種
- 追蹤 `_createdAreaIds`、`_createdProjectCodes`、`_createdSpeciesIds`
- WillPopScope 詢問清理

---

## v18.3.1 (2025-12-14) - UX 改進與程式碼清理

- 匯出按鈕 Loading 動畫（Admin、列表、永續報告）
- V3 手動輸入提交按鈕 Loading
- 移除 6 個未使用 imports、修復 linter warnings

---

## v18.3.0 (2025-12-14) - 編譯修復

- 修復 IntegratedTreeFormPage 路由編譯錯誤
- 修復 download_service.dart 正則表達式
- 修復 main.dart import 路徑

---

## v18.2.0 (2025-12-14) - AR 測量優化與安全改進

- AR 測量 GPS 距離模式（Haversine 公式）
- 虛擬 1.3m DBH 測量線
- Google Maps API Key 移至 gradle.properties（安全）
- 新增 `geolocator`、`camera` 套件

---

## v18.1.0 (2025-01-14) - V3 進階服務 UI 整合

- V3 進階服務管理頁面（影像、衝突、AR 校準、ML 同步）
- 首頁「進階服務」入口

---

## v18.0.0 (2025-12-03) - V3 測試套件與 ML 同步

- ML 數據同步服務（WiFi 優先、批次上傳、自動重試）
- V3 測試套件：251 個測試案例 (8,258 行)

---

## v17.1.0 (2025-12-04) - V3 進階服務層

- 影像記錄系統（本地優先 + 雲端同步）
- 衝突解決機制（Optimistic Lock）
- AR 測量整合服務（校準 + 信心度）
- BLE 模擬測試服務

---

## v17.0.0 (2025-12-03) - 專案邊界與智慧匹配

- 地圖手動繪製專案邊界多邊形
- 座標驗證（Ray Casting 演算法）
- BLE 批次匯入自動匹配專案

---

## v16.0.0 (2025-12-02) - 極簡現代化介面重構

- TIPC 港務風格 + 生態綠色主題
- 全新配色系統 + Material 3 + Google Fonts
- 首頁、統計、登入、列表、地圖全面翻新

---

## v15.0.0 (2025-12-02) - 樹種辨識 + AI 聊天

- Pl@ntNet + GBIF + iNaturalist 三合一樹種辨識
- 全新 AI 聊天頁面
- BLE 解碼器優化
