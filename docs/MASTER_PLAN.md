# 🌲 TreeAI 總體開發計畫 (Master Plan)

> 📅 建立日期：2025-12-13
> 🎯 目標：實現全自動化、高可信度、安全的智慧樹木管理系統
> 🔗 關聯文件：`V3_DEVELOPMENT_PLAN.md`, `WORKFLOW_RULES.md`, `ACADEMIC_REFERENCES.md`

本計畫整合了使用者需求、學術規範與 V3 架構設計，分為四個階段進行。

---

## 🔴 Phase 1: 基礎修復與架構優化 (Immediate Fixes & Foundation)
**目標**：解決現有 Bug，提升 APP 穩定性與速度，統一 API 架構。

### 1.1 嚴重 Bug 修復
- [x] **修復新增專案名稱錯誤**：解決使用者回報的錯誤（已優化 GPS 獲取邏輯）。
- [x] **驗證樹木編號邏輯**：確保新專案樹木從 1 開始編號（已確認後端邏輯排除佔位記錄）。
- [x] **修復專案刪除殘留**：刪除最後一筆樹木後，專案應能被正確清理或保留（已實作專案刪除功能）。

### 1.2 效能與 UX 優化
- [x] **優化輸入頁面速度**：
    - 解決「新增專案區位/名稱」速度過慢問題（GPS Timeout 機制）。
    - 實作 `ProjectService` 本地快取機制，減少重複 API 請求。
    - 優化定位功能回應速度。
- [x] **UI 調整**：將 `TreeSurveyPage` 的「新增樹木」按鈕下移，避免遮擋內容（動態 FAB 位置）。

### 1.3 架構重構 (API Unification)
- [x] **統一 API 呼叫點**：
    - 檢查並重構 `TreeSurveyPage`，移除直接 `ApiService.get` 呼叫，改用 `TreeService`。
    - 檢查並重構其他頁面，確保 UI 層完全不觸碰 HTTP 邏輯。

---

## 🟡 Phase 2: V3 核心 - 自動化與科學測量 (Automation & Science)
**目標**：透過 AR 與演算法提升測量效率與可信度（學術背書）。

### 2.1 專案邊界系統 (Project Boundaries)
- [x] **後端支援**：擴充 `projects` 表，支援 PostGIS/GeoJSON 多邊形儲存（已建立 `project_boundaries` 表）。
- [x] **前端繪製**：實作地圖繪製介面，讓管理者劃定專案範圍（`ProjectBoundaryDrawPage`）。
- [x] **自動匹配**：新增樹木/BLE 匯入時，根據座標自動填入專案名稱與區位（`ProjectBoundaryService` 實作）。

### 2.2 測站位置推算 (The "iPhone Ruler" Concept)
- [x] **演算法實作**：
    - 實作「已知樹木座標 + 距離 + 方位角 → 推算測站座標」公式（`StationService`）。
    - 實作「已知測站座標 + 距離 + 方位角 → 推算樹木座標」公式。
- [x] **AR 測量整合**：
    - 在 AR 測量 DBH 時，同時記錄手機 GPS 與方位角（`IntegratedTreeFormPage`）。
    - 引導測量員站在正確位置（如 DBH 1.3m 處的水平距離）。

### 2.3 整合式輸入流程 (Integrated Workflow)
- [x] **合併新增/編輯頁面**：建立 `TreeFormV3`，統一處理手動與自動輸入（`ManualInputPageV3`）。
- [x] **一鍵測量**：實作「拍照 -> AI 辨識樹種 -> AR 測量 DBH」的連續流程（`IntegratedTreeFormPage`）。

---

## 🟢 Phase 3: 資料完整性與影像管理 (Data Integrity)
**目標**：確保資料符合 2NF，影像與數據緊密關聯。

### 3.1 影像資料庫 (Image Database)
- [x] **資料庫設計**：建立 `tree_images` 表，分離影像 Metadata 與 Blob（已建立 migration）。
- [x] **儲存策略**：
    - 本地：SQLite 記錄 + App Documents 儲存（`TreeImageService`）。
    - 雲端：背景上傳機制 (WiFi Only 選項)（後端 `tree_images.js` API 已就緒）。
    - 關聯：確保每張照片都能追溯到特定的 `tree_id` 與測量事件。

### 3.2 機器學習數據收集 (ML Data Collection)
- [x] **MLDataCollector 服務**：
    - 已實作完整的數據收集類別 (`services/v3/ml_data_collector.dart`)
    - 支援：碳計算修改、AR 測量修改、樹種辨識修改、座標修正、欄位修改、衝突解決、測站位置計算
- [x] **MLDataSyncService 同步服務**：
    - WiFi 優先背景同步 (`services/v3/ml_data_sync_service.dart`)
    - 批次上傳、失敗重試機制
- [x] **後端 API**：
    - `POST /api/ml-training/batch` - 批次上傳
    - `GET /api/ml-training/statistics` - 統計資訊
    - `GET /api/ml-training/export` - 導出訓練數據
    - `GET /api/ml-training/analysis` - 分析報告
- [x] **前端整合**：
    - `tree_edit_page_v2.dart` - 碳計算修正記錄
    - `integrated_tree_form_page.dart` - AR 測量、樹種辨識修正記錄
    - `manual_input_page_v3.dart` - AR 測量、樹種辨識修正記錄

### 3.3 樹種辨識優化
- [x] **辨識流程**：已整合 `SpeciesIdentificationService` 到 V3 輸入流程。
    - `manual_input_page_v3.dart` - 拍照辨識樹種
    - `integrated_tree_form_page.dart` - 整合式辨識
- [x] **自動對應 species_id**：辨識結果會自動在 `_allSpecies` 中尋找匹配的 ID。
- [ ] **新增樹種提示**：若資料庫無此樹種，詢問使用者是否新增（待實作）。

---

## 🔵 Phase 4: 安全性與管理 (Security & Management)
**目標**：完善權限控管與資安防護。

### 4.1 JWT 認證與 Legacy 模式
- [x] **JWT 認證中間件**：實作 `jwtAuth.js`，支援 Bearer Token 驗證。
- [x] **50 天過渡期**：實作 Legacy Mode，允許舊 APK 在過渡期內繼續使用。
- [x] **持久化過渡截止日**：建立 `system_settings` 表，確保 Render 重新部署不會重置截止日。
- [x] **前端 401 處理**：實作全域 401 Unauthorized 處理，自動登出並導向登入頁。

### 4.2 權限架構 (RBAC)
- [x] **後端權限**：`users` 表已有 `role` 欄位（系統管理員、業務管理員、專案管理員、調查管理員、一般使用者）。
- [x] **專案權限**：已實作 `projectAuth` 中間件，限制非專案成員的編輯權限。
    - 系統管理員/業務管理員：全部專案權限
    - 其他角色：只能存取 `associated_projects` 中的專案
    - 已整合到：樹木 CRUD、批量匯入等 API

### 4.3 資安加強
- [x] **敏感資料保護**：前端 JWT Token 使用 `SharedPreferences` 安全儲存，不硬編碼。
- [x] **密碼雜湊**：後端使用者密碼採用 `bcrypt` 加密（`routes/users.js`）。
- [x] **API Rate Limit**：已實作 `loginLimiter` 針對登入 API。
- [x] **AI API Rate Limit**：已實作 `aiLimiter` (50次/30分鐘) 於 `routes/ai.js`。

### 4.4 審計日誌 (Audit Logs)
- [x] **資料庫設計**：建立 `audit_logs` 表，記錄 user_id、action、resource、details、IP、UserAgent。
- [x] **AuditLogService**：建立統一的審計日誌服務 (`services/auditLogService.js`)。
- [x] **操作記錄整合**：
    - 登入成功/失敗 (`LOGIN`, `LOGIN_FAILED`)
    - 使用者管理 (`CREATE_USER`, `UPDATE_USER`, `DELETE_USER`, `UPDATE_USER_STATUS`, `UPDATE_USER_PROJECTS`)
    - 樹木新增 (`CREATE_TREE`, `CREATE_TREE_LEGACY`, `BATCH_IMPORT_TREES`)
    - 樹木更新 (`UPDATE_TREE`, `UPDATE_TREE_LEGACY`)
    - 樹木刪除 (`DELETE_TREE`)
- [ ] **異常監控**：登入失敗達 N 次的警示機制（待實作）。

---

## 🏗️ 架構說明 (Architecture Notes)

### Service Layer 設計
```
┌─────────────────────────────────────────────────────────┐
│                      UI Layer                            │
│  (Pages: TreeSurveyPage, ManualInputPageV3, etc.)       │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│              Domain Services (業務邏輯層)                │
│  TreeService, ProjectService, CarbonSinkService, etc.   │
│  - 封裝業務邏輯                                          │
│  - 資料轉換與驗證                                        │
│  - 本地快取管理                                          │
└─────────────────────────┬───────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────┐
│                  ApiService (HTTP 層)                    │
│  - 統一的 HTTP 請求封裝                                   │
│  - JWT Token 管理                                        │
│  - 401 自動登出處理                                      │
│  - 錯誤處理標準化                                        │
└─────────────────────────────────────────────────────────┘
```

**為何分離 TreeService 和 ApiService？**
- **關注點分離**：ApiService 只處理 HTTP 通訊，TreeService 處理樹木相關業務邏輯
- **可測試性**：可以 mock ApiService 來單獨測試 TreeService
- **維護性**：修改 API endpoint 只需改 TreeService，不影響 UI
- **一致性**：所有樹木相關操作都經過 TreeService，確保邏輯統一

---

## 📅 執行策略 (Execution Strategy)

1.  **優先執行 Phase 1**，解決目前影響使用的痛點。
2.  每個功能開發前，必先閱讀 `WORKFLOW_RULES.md` 與相關學術文件。
3.  每完成一個小項目，即進行測試與 Git Commit。
4.  隨時更新本計畫文件的進度狀態。

### 🔴 剩餘待完成項目 (Remaining Tasks)
**所有核心功能已完成！** 🎉

以下為可選的增強功能：
| 優先級 | 項目 | 說明 |
|--------|------|------|
| 極低 | 前端新增樹種對話框 | 前端 UI 詢問是否新增未知樹種（後端 API 已完成） |
| 極低 | 管理員異常登入儀表板 | 視覺化顯示異常登入統計（後端功能已完成） |

### ✅ 已完成重大功能
- JWT 認證 + 50 天 Legacy 過渡期
- 審計日誌系統 (所有關鍵操作)
- ML 數據收集與同步
- 樹種辨識整合 (Pl@ntNet + GBIF + iNaturalist)
- AI Chat Rate Limiting
- 前端 401 自動登出
- **專案權限控管** (RBAC - 限制非專案成員編輯)
- **自動化回歸測試** (可取代手機測試)
- **V3 功能路由整合** (ManualInputPageV3, IntegratedTreeFormPage, ProjectBoundaryDrawPage)
- **Phase 3.3 新增樹種 API** (辨識到未知樹種時可新增)
- **Phase 4.4 登入失敗監控** (5次失敗鎖定30分鐘，自動解鎖)

---

## 🧪 自動化測試 (Automated Testing)

### 執行方式
```bash
cd tree-project-backend

# 完整回歸測試 (推薦 - 取代手機測試)
npm run test:regression

# 本地測試
npm run test:regression:local

# 只測試特定模組
node tests/regression.test.js --section=auth      # 認證
node tests/regression.test.js --section=tree      # 樹木 CRUD
node tests/regression.test.js --section=batch     # 批量匯入
node tests/regression.test.js --section=user      # 使用者管理
node tests/regression.test.js --section=security  # 安全性
```

### 測試涵蓋範圍 (32+ 項)
| 模組 | 測試內容 |
|------|---------|
| 認證 | 登入 (admin/survey)、JWT 驗證、錯誤密碼、401 處理 |
| 樹木 | 新增/編輯/刪除 (V2 + Legacy API) |
| 批量 | BLE 匯入、ID 連續性驗證 |
| 使用者 | CRUD、停用、專案關聯 |
| 安全 | SQL 注入、XSS、Rate Limit |
| 審計 | 日誌記錄驗證 |

### 測試通過標準
- ✅ **全部通過**: 可放心部署/燒錄 APK
- ❌ **有失敗**: 檢查失敗項目，修復後重測
