# Ubuntu 後端主機 — Tailscale SSH 與部署確認

> 主機為自架後端（非 Render）。App 目前連線：  
> `https://richardhualienserver.tail124a1b.ts.net/api`

---

## 1. 前置：加入 Tailscale

1. 電腦與手機安裝 [Tailscale](https://tailscale.com/download) 並登入**與後端相同的 tailnet**（目前為 `KyleliuNDHU@`）。
2. 本機確認看得到 Ubuntu：

```powershell
tailscale status
```

應出現類似：

| Tailscale IP | 主機名 | OS |
|--------------|--------|-----|
| `100.118.203.75` | `richardhualienserver` | linux |

---

## 2. SSH 連線（建議）

```powershell
tailscale ssh richardhualienserver
```

首次連線若出現 host key 提示，輸入 `yes` 接受。

傳統 SSH（需知道 Linux 使用者名，常見為部署帳號）：

```powershell
ssh <使用者>@100.118.203.75
# 或
ssh <使用者>@richardhualienserver
```

---

## 3. 部署目錄與常用指令

| 路徑 | 說明 |
|------|------|
| `/opt/tree-app/backend` | Node 後端原始碼 |
| `/opt/tree-app/logs/deploy.log` | GitHub webhook 自動部署日誌 |
| `/opt/tree-app/scripts/deploy.sh` | 手動部署腳本 |

```bash
# 確認是否已拉到最新 main
cd /opt/tree-app/backend && git log -1 --oneline

# 部署日誌
tail -30 /opt/tree-app/logs/deploy.log

# 健康檢查（機器本機）
curl -s http://127.0.0.1:3000/health

# PM2
pm2 list
pm2 logs tree-backend --lines 30

# 手動部署（webhook 失敗時）
/opt/tree-app/scripts/deploy.sh
```

---

## 4. 從 Windows 確認（不 SSH）

```powershell
curl.exe -sk https://richardhualienserver.tail124a1b.ts.net/health
```

回 `OK` 表示服務在線；**不代表**已拉到最新 commit，仍須 SSH 看 `git log` 或 `deploy.log`。

部署狀態 API（需正式機 `ADMIN_API_TOKEN`）：

```powershell
curl.exe -sk -H "X-Admin-Token: <token>" https://richardhualienserver.tail124a1b.ts.net/webhook/status
```

---

## 5. GitHub 自動部署流程

`push` 到 `tree-project-backend` 的 `main` → webhook  
`POST :8443/webhook/deploy` → 執行 `deploy.sh` → `git pull` → `npm install` → migration → `pm2 reload`。

詳見 repo `backend/README.md` §8。

---

## 6. 圖資中心遷移後

簡老師協調的圖資中心主機就緒後，需更新：

- Ubuntu SSH 位址與帳號
- `app_config.dart` 的 `baseUrl`
- Tailscale / 防火牆 Port

並同步更新本檔。
