# 文件索引

本目錄為 **Sustainable TreeAI** 的長期文件庫。根目錄 [`README.md`](../README.md) 只放快速入門；詳細內容依職責分檔，方便移交至老師的 GitHub 組織後由接手者查閱。

## 建議閱讀順序（接手開發）

1. [`SYSTEM_HANDOFF_MANUAL.md`](SYSTEM_HANDOFF_MANUAL.md) — 部署、BLE 協議、併發、migration
2. [`UBUNTU_SSH_ACCESS.md`](UBUNTU_SSH_ACCESS.md) — Tailscale SSH、部署確認
3. [`HANDOFF_SECRETS_CHECKLIST.md`](HANDOFF_SECRETS_CHECKLIST.md) — 哪些不能進 Git、要怎麼備份
4. [`DEVELOPMENT_BACKLOG.md`](DEVELOPMENT_BACKLOG.md) — 已完成與暫緩項目
5. [`FIELD_SURVEY_SOP.md`](FIELD_SURVEY_SOP.md) — 給現場調查員（非技術）
6. [`MEETING_MINUTES_20260528.md`](MEETING_MINUTES_20260528.md) — 需求與決議來源

## 文件分類（業界常見做法）

| 類型 | 目的 | 本專案範例 |
|------|------|------------|
| **README（根目錄）** | 30 秒懂專案、clone、build、連結 | `../README.md` |
| **Tutorial** | 從零跑起來 | `BUILD_GUIDE.md`、`LAB_DEPLOYMENT_GUIDE.md` |
| **How-to** | 解決單一任務 | `FIELD_SURVEY_SOP.md`、`VERIFICATION_CHECKLIST.md` |
| **Reference** | API、schema、協議 | `SYSTEM_HANDOFF_MANUAL.md`、`DATABASE_NORMALIZATION.md` |
| **Explanation** | 為什麼這樣設計 | `MEETING_MINUTES_20260528.md`、`BOUNDARY_SYSTEM_DESIGN.md` |

> 業界慣例：**不要把整本手冊塞進 README**。README 維持精簡；`docs/` 用索引（本檔）串起各專題。大型開源專案另可加 `CONTRIBUTING.md`、`ARCHITECTURE.md`；本專案以 `SYSTEM_HANDOFF_MANUAL.md` 兼任架構與維運說明。

## 依角色

| 角色 | 文件 |
|------|------|
| 現場調查員 | `FIELD_SURVEY_SOP.md` |
| 後端 / DevOps | `SYSTEM_HANDOFF_MANUAL.md`、`LAB_DEPLOYMENT_GUIDE.md`、`HANDOFF_SECRETS_CHECKLIST.md` |
| Flutter 開發 | `SYSTEM_HANDOFF_MANUAL.md` §7、`DEVELOPMENT_BACKLOG.md`、`VLGEO2_STD_APPLICATION_GUIDE.md` |
| 教授 / 簡報 | `PROJECT_OVERVIEW_FOR_MEETING.md` |
| BLE / 儀器研究 | `test/vlgeo2_ble_analysis/docs/` |

## 歷史與暫緩方案

外接 GNSS、批次藍牙擴充等已決議暫緩／取消的說明，保留於 `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` 等檔，避免誤以為仍為現行方案。
