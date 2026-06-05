# 交接機密與本機設定清單

> GitHub **只放程式碼與文件**；下列項目須**手動備份**（G:\ 或加密隨身碟），交付時另行交給接手者。

## 必備（沒有就無法建 APK / 連後端）

| 項目 | 路徑 | 說明 |
|------|------|------|
| Android 簽章 | `android/key.properties` + `*.jks` | 見 `key.properties.example` |
| Google Maps Key | `key.properties` 內 `GOOGLE_MAPS_API_KEY` | 須綁 package + SHA-1 |
| 後端環境變數 | `backend/.env` | DB、JWT secret、ML proxy key |
| 後端 baseUrl | `lib/config/app_config.dart` | 部署後改為圖資中心網址 |

## 建議備份

| 項目 | 說明 |
|------|------|
| Tailscale / VPN 設定 | 自架後端連線用 |
| 圖資中心 SSH / 部署腳本 | PM2、nginx、webhook |
| VLGEO2 韌體備份 | `test/vlgeo2_ble_analysis/firmware_backup/`（已在 Git） |
| 管理員帳號與邀請碼清單 | 後台交付文件，勿進 Git |

## 自動備份腳本

```powershell
cd frontend
powershell -ExecutionPolicy Bypass -File scripts\handoff_backup.ps1
```

預設輸出：`G:\TreeAI-Handoff\yyyyMMdd_HHmm\`（含 frontend + backend 原始碼，排除 build 與機密檔）。
