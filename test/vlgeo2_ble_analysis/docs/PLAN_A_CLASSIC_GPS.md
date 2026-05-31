# 方案 1：Classic GPS + BLE 逐棵量測

> 目標：SEND 每一棵時，座標來自 **VLGEO2 內建 GPS**，量測來自 **BLE PHGF**。  
> **不刷韌體、不逆向刷機**；只改 Mac 驗證 + 之後 APP。

## 架構

```
┌──────────────┐  Classic SPP (VLGEO2_3190_COM)   ┌─────┐
│   VLGEO2     │ ── GGA/RMC 背景串流 ────────────→ │ APP │ lastGga
│              │  BLE NUS (VLGEO2_3190)            │     │
│              │ ── PHGF（每棵 SEND）────────────→ │     │ PHGF + lastGga → 表單
└──────────────┘                                   └─────┘
```

現場 SOP **不變**：量樹 → SEND → 填 DBH → 提交。

## 研究階段

### 階段 1 — Classic COM 必須先有資料（Mac，零風險）

| 步驟 | 動作 | 成功判準 |
|------|------|----------|
| 1.1 | 手機斷 BLE；Mac 只配對 `_COM` | `/dev/cu.VLGEO2_*_COM` 存在 |
| 1.2 | 儀器 SETTINGS 照檢查表 | USE GPS ON, EXTERN OFF, MEM OFF |
| 1.3 | 跑診斷腳本 | 見下方命令 |
| 1.4 | 若 0 byte | 重配 _COM、重開機、白天有 fix 再測 |
| 1.5 | 若有 GGA | 進階段 2 |

```bash
cd tree-project-frontend/test/vlgeo2_ble_analysis

# 完整排查（DTR/RTS、probe、baud、cu/tty）
/Users/kyle/project_code/.venv/bin/python verify_vlgeo2_classic_gps.py \
  --port /dev/cu.VLGEO2_3190_COM --diag -v --duration 30

# 僅長時間監聽
/Users/kyle/project_code/.venv/bin/python verify_vlgeo2_classic_gps.py \
  --port /dev/cu.VLGEO2_3190_COM --duration 120 -v
```

Log：`raw_captures/classic_gps_*.log`

**解讀：**

- `bytes=0` 全程 → SPP 鏈路問題（不是 APP、不是沒衛星）
- `bytes>0` 無 GGA → 協定/格式問題，查 log 內 `$` 開頭行
- `GPS>=1` → 方案 1 通道成立，可寫 APP

### 階段 2 — APP POC（Classic 有 GGA 後）

1. Android：`flutter_bluetooth_serial` 或 platform channel 收 SPP GGA
2. 並行：`flutter_blue_plus` 訂閱 NUS TX PHGF
3. `BleLiveSessionPage`：收到 PHGF 時讀 `InstrumentGpsCache.lastGga`
4. iOS：實測 Classic SPP 是否可用；不行再評估

### 階段 3 — 若 Classic 仍 0 byte

1. 離線分析 `firmware_backup/downloads/VLGEO2_V3.5.VLB`（`_COM`、`Reading gps`）
2. **不刷**自改 VLB
3. 再考慮方案 2（BLE 全 GATT 掃描）

## 與批次匯入的差別

| | 方案 1 雙通道 | 批次匯入 |
|--|----------------|----------|
| 連線 | _COM + BLE 同時 | 通常僅 BLE |
| 觸發 | 每棵 SEND | SEND FILES |
| 資料 | 即時 GGA + PHGF | 整檔 DATA.CSV |

## 實測紀錄

| 日期 | 設定 | bytes | GGA | 備註 |
|------|------|-------|-----|------|
| 2026-05-31 | COM 配對、設定 ON | 0 | 0 | 初測 120s |
| 2026-05-31 | 同上 | 0 | 0 | 25s 複測 |
| 2026-05-31 | `--diag` 全項 | 0 | 0 | DTR/RTS、probe、5 baud、cu/tty 皆 0；log `classic_gps_20260531_024438.log` |
