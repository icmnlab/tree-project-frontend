# Ubuntu 後端主機 — Tailscale SSH 與部署確認

> 主機為自架後端（非 Render）。App 目前連線：  
> `https://<TAILSCALE_HOST>/api`

---

## 1. 前置：加入 Tailscale

1. 電腦與手機安裝 [Tailscale](https://tailscale.com/download) 並登入**與後端相同的 tailnet**（目前為 `<GITHUB_OWNER>@`）。
2. 本機確認看得到 Ubuntu：

```powershell
tailscale status
```

應出現類似：

| Tailscale IP | 主機名 | OS |
|--------------|--------|-----|
| `<TAILSCALE_SERVER_IP>` | `<TAILSCALE_HOST_SHORT>` | linux |

---

## 2. SSH 連線（建議）

### 2a. 已驗證可用（2026-06-08）

本機需有已加入伺服器 `authorized_keys` 的金鑰（例如 `~/.ssh/id_ed25519`）：

```powershell
ssh -i $env:USERPROFILE\.ssh\id_ed25519 kyleliu@100.118.203.75
```

| 項目 | 值 |
|------|-----|
| Linux 使用者 | `kyleliu` |
| Tailscale IP | `100.118.203.75` |
| 主機名 | `richardhualienserver` |
| 後端目錄 | `/opt/tree-app/backend` |
| 部署日誌 | `/opt/tree-app/logs/deploy.log` |

連線後常用指令：

```bash
cd /opt/tree-app/backend && git log -1 --oneline
tail -30 /opt/tree-app/logs/deploy.log
pm2 list
pm2 logs tree-backend --lines 50 --nostream
curl -s http://127.0.0.1:3000/health
```

### 2b. Tailscale SSH（若 host key 已公告）

```powershell
tailscale ssh richardhualienserver
```

首次連線若出現 host key 提示，輸入 `yes` 接受。若出現 `No ED25519 host key is known`，請改用 **§2a** 傳統 SSH。

### 常見錯誤與處理

| 現象 | 原因 | 建議 |
|------|------|------|
| `No ED25519 host key is known for <TAILSCALE_HOST_SHORT>...` | Ubuntu 尚未在 Tailscale 上公告 SSH host key，或 Tailscale SSH 未完整啟用 | 在**本機互動式終端**執行 `tailscale ssh <TAILSCALE_HOST_SHORT>`；若仍失敗，請伺服器管理員在 Ubuntu 啟用 Tailscale SSH（`tailscale set --ssh`）並確認 ACL |
| `Permission denied (publickey)`（`ssh user@<TAILSCALE_SERVER_IP>`） | 伺服器**僅允許公鑰**，不接受密碼；或本機金鑰未加入 `authorized_keys` | 使用已加入伺服器的本機金鑰（例如 `~/.ssh/id_ed25519`）連線；或改用 `tailscale ssh <TAILSCALE_HOST_SHORT>` |
| `Permission denied (publickey,password)` | 同上：密碼登入已停用 | 勿用密碼；確認 `ssh -i ~/.ssh/id_ed25519 <SERVER_USER>@<TAILSCALE_SERVER_IP>` 可用 |
| `connectex ... port 22 ... failed` | 主機未對 tailnet 開放 22，或僅允許 Tailscale SSH 通道 | 同上，用 `tailscale ssh`；必要時由管理員檢查 `ufw` / `sshd` |
| `curl /health` 回 `OK` 但不知是否最新版 | health 只代表程序在跑 | SSH 後 `git log -1`，或帶 token 查 `GET /webhook/status` |

傳統 SSH（需知道 Linux 使用者名，且金鑰已加入伺服器；**非預設路徑**）：

```powershell
ssh <使用者>@<TAILSCALE_SERVER_IP>
# 或
ssh <使用者>@<TAILSCALE_HOST_SHORT>
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

# 手動部署（webhook 失敗時；需用 bash 執行）
bash /opt/tree-app/scripts/deploy.sh
```

### 部署卡住／未更新到最新 commit

若 `deploy.log` 有 `Deploy started` 但 `git log -1` 仍為舊版，常見原因：

| 現象 | 處理 |
|------|------|
| `untracked working tree files would be overwritten by merge`（例如 `scripts/list_users.js`） | `mv scripts/list_users.js scripts/list_users.js.bak` 後再 `git pull origin main` |
| `git pull` 已成功但 PM2 uptime 仍為數天 | 手動 pull 會讓 `deploy.sh` 判定「Already up to date」而跳過重啟；需執行 `npm install --production`、`node scripts/migrate.js`、`pm2 reload tree-backend` |
| `Permission denied` 執行 deploy.sh | 腳本為 symlink，請用 `bash /opt/tree-app/scripts/deploy.sh` |


---

## 4. 從 Windows 確認（不 SSH）

```powershell
curl.exe -sk https://<TAILSCALE_HOST>/health
```

回 `OK` 表示服務在線；**不代表**已拉到最新 commit，仍須 SSH 看 `git log` 或 `deploy.log`。

部署狀態 API（需正式機 `ADMIN_API_TOKEN`）：

```powershell
curl.exe -sk -H "X-Admin-Token: <token>" https://<TAILSCALE_HOST>/webhook/status
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
