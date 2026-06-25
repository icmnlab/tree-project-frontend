# 交接摘要（給指導老師／行政，一頁）

> 技術細節見 [`HANDOFF.md`](HANDOFF.md)。最後更新：2026-06-19。

---

## 系統名稱與目的

**永續碳匯樹木管理系統（Sustainable TreeAI）** — 樹木現場調查、專案／區管理、碳匯估算與管理後台。目標使用單位：國立東華大學環境學院。

## 交付形態

| 項目 | 說明 |
|------|------|
| 程式 | 兩個獨立 GitHub repo：`tree-project-frontend`（Flutter）、`tree-project-backend`（Node.js + PostgreSQL） |
| 授權 | MIT；著作權與貢獻者見 `LICENSE`、`AUTHORS.md`、`CONTRIBUTION_RECORD.md` |
| 文件 | `frontend/docs/HANDOFF.md` 為單一入口；部署見 `LAB_DEPLOYMENT_GUIDE.md` |
| 接手入門 | [`DEVELOPER_ONBOARDING.md`](DEVELOPER_ONBOARDING.md)（從零裝機與接續開發順序） |

## 架構（三層）

```
Flutter App（Android 現場）→ HTTPS/JWT → Express API → PostgreSQL
                                      ↘ 選用 ML 服務（視覺 DBH）
```

## 核心現場流程（主推）

VLGEO2 **BLE 逐棵量測** → App 暫存 **pending** → 調查員補 DBH／樹種／照片 → **transfer** 寫入正式資料庫。手動新增／編輯見 [`MANUAL_DATA_ENTRY.md`](MANUAL_DATA_ENTRY.md)。

## 品質保證

| 項目 | 現況 |
|------|------|
| 後端整合測試 | `backend/tests/runner.js`（CI 約 80+ cases） |
| 前端單元測試 | `flutter test`（435 pass） |
| 部署後驗收 | `VERIFICATION_CHECKLIST.md` |

## 接手方責任

- 自建主機、資料庫、**全部 API 金鑰**（不接續使用交付方舊金鑰）
- 正式環境管理員以 `create_lab_admin.js` 建立（不使用開發種子帳 `admin/12345`）
- 維運與後續開發自交接日起由實驗室／接手方負責

## 已知文件範圍

- 現場 BLE：`FIELD_SURVEY_SOP.md`
- 手動新增／編輯：`MANUAL_DATA_ENTRY.md`（2026-06 補齊）
- AI／實驗功能：預設正式 APK 關閉（`HANDOFF.md` §12）
