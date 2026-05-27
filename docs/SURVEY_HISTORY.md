# 同一棵樹的多次調查（歷次資料）

## 目前機制（已存在）

| 層級 | 行為 |
|------|------|
| **tree_survey** | 每棵樹一筆「目前快照」：`survey_time`、`dbh_cm`、`tree_height_m` 等會在最新一次寫入時更新 |
| **tree_measurement_raw** | 轉移待測量或匯入時，儀器原始量測（距離、方位、GPS、raw snapshot、`measured_at`）會掛在 `tree_id` 上，可累積多筆 |
| **待測量 survey_mode** | `new`：新建 tree_survey；`maintenance`：更新既有 `target_tree_id`（複查／維護） |
| **照片 tree_images** | `owner_type=survey`，轉移時由 pending 改掛正式樹 id |

因此：**同一棵樹再次調查**時，若走「維護／對應既有樹木」流程，正式表會更新最新調查結果，儀器細節留在 `tree_measurement_raw` 供研究追溯。

## 尚未完整建置（研究用長期願景）

- 獨立的 **`tree_survey_events`**（或類似）表：每次調查一列，不覆寫歷史 DBH／樹高
- 前端「調查時間軸」：同一 system_tree_id 列出歷次事件
- 碳匯年流量依歷次調查差分計算（需與手冊／TIPC 欄位對齊後再實作）

## 實務建議

1. 複查既有樹：BLE／待測量請設 `survey_mode=maintenance` 並帶 `target_tree_id`（或事後在樹木清單編輯對應）。
2. 新植／新點：維持 `new`，轉移後產生新 `system_tree_id`。
3. 研究匯出：現階段可從 `tree_measurement_raw` + `tree_survey.survey_time` 做初步分析；完整歷次快照待 events 表上線。
