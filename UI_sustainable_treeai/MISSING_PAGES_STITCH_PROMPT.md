# Stitch Prompt — Forest Intelligence 缺漏頁面設計

> 用途：把以下內容貼到 Google **Stitch**（stitch.withgoogle.com），讓它**沿用既有 Forest Intelligence 設計系統**，補齊目前 14 張 mockup 尚未涵蓋的頁面。
>
> 已完成的 14 張（請勿重做）：登入/首頁、量測表單、Admin Portal、區邊界繪製×2、樹木詳情、樹木清單、統計分析、維護測量、註冊、樹種辨識資料庫、同步狀態、BLE 連線。
>
> 使用建議：先貼「Global design system」一次設定基調，再**逐頁**貼「Screen」段落產生（Stitch 一次處理單一畫面效果最佳）。所有 UI 文字使用**繁體中文（zh-TW）**。

---

## Global design system (paste first)

Design a mobile app called **Forest Intelligence** — a field tool for professional foresters and carbon auditors. Platform: Android handset (also tablet landscape). All UI text must be in **Traditional Chinese (zh-TW)**. Aesthetic: "Industrial Minimalism" + Material 3, authoritative yet approachable, optimized for high-glare outdoor use (high contrast, spacious, large touch targets).

Use these design tokens exactly:

- **Font:** Plus Jakarta Sans. Body text large (18px) for arm's-length readability; bold headlines; data-entry labels use medium/bold weight with wider letter-spacing.
- **Colors:** Primary Ocean Blue `#004E8B` (nav, primary actions); Secondary Forest Green `#1B6D24` (carbon/growth/success); Tertiary Deep Purple `#781B9F` (AI / LIDAR / species ID); Stats Deep Cyan `#006A6A` (charts/dashboard); Error/Alert Red `#BA1A1A` (Bluetooth/sensor/sync failures). Background cool off-white `#FCF8FF`; text deep navy `#1A1A2E`; outline `#717782`.
- **Shape:** buttons/inputs/chips radius 8px; cards/list items radius 16px; floating bottom nav + FAB radius 24px.
- **Layout:** 20px screen margins; 16px grid gutter; min 48×48dp touch targets (usable with field gloves).
- **Navigation:** signature **floating bottom navigation bar** — pill-shaped island inset 12px from edges, active item shown as a primary-colored pill behind the icon.
- **Elevation:** white cards with soft 12% shadow (8px blur); floating nav/modals 18% shadow (16px blur), 24px radius.
- **Components:** outlined input fields with always-visible labels and 2px focus border; primary buttons solid `#0066B3` white text; secondary buttons outlined green; chips rounded 16px high-contrast; a persistent top status chip ("離線" navy / "已連線/同步中" green).

---

## Screen 1 — 地圖總覽（Map）★ 高優先

A full-screen interactive map showing surveyed trees as pins across a project area. Requirements:
- Map fills the screen; floating top bar with a project/area filter dropdown ("專案 / 區位") and a city/county filter chip.
- Tree pins color-coded by status: green = 正常/活立木, amber = 傾斜/病蟲害, grey semi-transparent = 已淘汰（枯死/倒塌/移除）. A small legend.
- A toggle chip "隱藏已淘汰" to hide retired trees.
- Tapping a pin opens a bottom sheet card: tree photo thumbnail, 樹木編號, 樹種, 胸徑(DBH), 狀況, and a "查看詳情" button.
- A FAB "＋ 新增樹木" (Ocean Blue, 24px radius). Top-right buttons: "繪製邊界"、"匯出 KML".
- Offline status chip at top.

## Screen 2 — AI 智能助理對話（AI Assistant Chat）★ 高優先

A ChatGPT-style assistant scoped to forestry/carbon data. Use the **Deep Purple** AI accent. Requirements:
- Collapsible left sidebar listing chat sessions (歷史對話) with "＋ 新對話".
- Top bar showing the active model/agent badge and a model selector.
- Empty state: greeting "您好，我能協助您查詢碳匯資料" + a grid of suggestion chips (e.g. "本專案總碳匯量"、"哪些樹木已淘汰"、"產生永續報告草稿"、"近一個月新增樹木").
- Message thread with user bubbles and assistant bubbles; assistant messages can include small data tables and chart cards (Deep Cyan).
- Bottom input bar with text field, attach button, and a send FAB (Deep Purple).

## Screen 3 — 相機 / 視覺 DBH 掃描（AI Camera Measure）★ 高優先

A live camera screen for measuring tree DBH (diameter at breast height) by photo. Use **Deep Purple AI mode** styling. Requirements:
- Full-screen camera viewfinder with a translucent purple scanning frame and soft glow signalling the experimental AI tool.
- An auto-detected trunk bounding box overlay; a hint "對準樹幹拍照，AI 自動辨識並量測" (auto mode) / "拍照後手動框選樹幹範圍" (manual mode).
- A mode toggle (自動 / 手動框選).
- Bottom: large round shutter button, plus secondary controls (切換閃光、改用人工量測).
- A results panel state: detected 樹種 (with confidence %), 胸徑像素寬度, estimated DBH, a warning row "樹幹可能超出畫面，建議重拍" when coverage is high, and "確認並填入表單" / "重拍" buttons.

## Screen 4 — BLE 即時連續量測（Live Vertex Session）

A live measuring session paired with a Haglöf Vertex Laser Geo2 over Bluetooth. Requirements:
- Top: persistent connection status chip (已連線 green / 連線中 / 已中斷 red) with device name, plus battery/signal.
- A large live readout of the latest received measurement (e.g. 胸徑 / 樹高), with the running sequence number "第 N 棵".
- A scrollable list of captured measurements this session (序號、數值、時間、GPS 狀態), each editable/deletable.
- A prompt card for "樹旁 GPS 取得中…" and, for maintenance re-measure, a question "是否更新樹木座標？沿用原座標／更新 GPS".
- Bottom actions: "結束量測"、"暫停/重連". Use Alert Red for disconnect banners.

## Screen 5 — 待測量任務（Pending Measurement Tasks）

A two-stage workflow task list of trees awaiting field measurement. Requirements:
- List grouped by 專案 / 區位; each row: 樹木編號, 預定樹種, 建立時間, a status badge (待測量 / 進行中).
- Search and filter bar.
- Swipe or tap a row to "開始量測" (opens measurement form) or "標記跳過".
- Header summary: 待測 N 筆 / 已完成 M 筆 with a thin progress bar (Forest Green).

## Screen 6 — Admin 後台子頁通用樣板（Admin Sub-pages）

One consistent admin template that covers several back-office pages (generate variants if helpful): **稽核紀錄 (Audit Log)、角色權限 (Role Permissions)、IP 黑名單、系統設定、CSV 匯入、研究資料集**. Requirements:
- Left/collapsible admin nav with sections; main area as a data table or settings form.
- Audit Log variant: filterable table (時間、使用者、動作、目標、詳情) with pagination.
- Role Permissions variant: a role × permission matrix with toggles (角色：系統管理員/業務管理員/調查管理員/調查員).
- System Settings variant: grouped setting cards with switches and inputs.
- CSV Import variant: drag-and-drop upload zone, column-mapping preview table, and an import-result summary.
- Keep Ocean Blue primary; destructive actions in Alert Red with confirm dialogs.

## Screen 7 — 帳號邊角頁（Auth edge pages）

Two minimal screens matching the existing 登入/註冊 style: **忘記密碼（輸入 email 申請重設）** and **重設密碼待審核/完成** confirmation. Centered card, single primary action, clear success/pending states.

---

### 交付後對接 Flutter

- 色彩/字體/圓角/間距已封裝於 `frontend/lib/themes/forest_intelligence_theme.dart`（`ForestIntelligenceTheme`）。實作時於 `main.dart` 切換 `theme: ForestIntelligenceTheme.lightTheme` 即可全域生效。
- 對應的現有程式頁面：`map_page.dart`、`screens/ai_chat_page.dart`、`screens/scanner_page.dart`、`screens/ble_live_session_page.dart`、`screens/pending_measurement_task_page.dart`、`screens/{audit_log,role_permissions,ip_blacklist,system_settings,csv_import}_page.dart`、`admin_research_dataset_page.dart`、`screens/forgot_password_page.dart`。
