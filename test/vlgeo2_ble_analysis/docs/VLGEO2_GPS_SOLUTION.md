# VLGEO2 儀器 GPS 整合方案（2026-05-31 實測結論）

> 依 Haglöf 硬體手冊 Rev.1；以 Mac + VLGEO2_3190 電腦驗證為準。

## 實測結論

| 通道 | 量測 PHGF | 儀器 GPS (GGA/RMC) | 備註 |
|------|-----------|-------------------|------|
| **BLE NUS**（MEMORY 關，逐棵 SEND） | ✅ 12/12 棵 | ❌ 0 句 | `gps_verify_20260531_013536` |
| **USB DATA.CSV**（歷史存檔） | CSV 列 | ✅ LAT/LON 有值 | `/Volumes/VL_GEO2/DATA/DATA.CSV` |
| **BLE PHGF 封包本身** | HD/AZ/H/SD | ❌ 無座標欄 | 手冊 §9.2 一致 |

**結論：不是 APP 解析問題；BLE 逐棵通道目前不送 GPS NMEA。**

## 可行方案（優先順序）

### 方案 A — Classic 藍牙 GPS + BLE 量測（推薦，符合手冊 §4.6.2）

手冊 §4.5：Classic 名稱 `VLGEO2_XXXXX_COM`，PIN `1234`，NMEA 含 §10 GGA/RMC。  
手冊 §4.6.2：USE GPS 開、EXTERN.GPS 關 → 連線後送 GPS 給外部裝置。

```
┌─────────────┐     Classic SPP      ┌──────┐
│  VLGEO2     │ ── GGA/RMC 串流 ───→ │ APP  │  儀器 GPS 快取
│             │     BLE NUS          │      │
│             │ ── PHGF 每棵 SEND ─→ │      │  觸發：配對最新 GGA + HD/AZ
└─────────────┘                      └──────┘
```

**電腦驗證：**

```bash
# 1. Mac 藍牙配對 VLGEO2_3190_COM（PIN 1234）
pip install pyserial   # 已在 .venv 可略
python verify_vlgeo2_classic_gps.py --duration 120
```

**APP 實作要點：**

- Android：Classic SPP（`flutter_bluetooth_serial` 等）+ BLE NUS 並行
- iOS：Classic SPP 受限，需實機測是否可雙連；不行則方案 B/C
- 收到 PHGF 時取 `lastInstrumentGga`，再依 SOP 決定：
  - **樹位 = 儀器 GPS**（調查員站樹旁），或
  - **樹位 = 儀器 GPS + HD/AZ 反算**（`StationService`）

### 方案 B — MEMORY 開 + 場次匯出 CSV（有 GPS，非逐棵即時）

手冊 §4.4.12：MEMORY 開時每筆可存 **5 位 ID + GPS** 至 SSD。  
手冊 §4.5：**MEMORY 開時無法 Bluetooth/IR 即時 SEND**（與逐棵 PHGF 衝突，需實機再確認韌體）。

流程：場次結束 → MEMORY → SEND FILES → 解析 CSV 33 欄（含 LAT/LON）。  
適合批次，不適合會議要求的「逐棵即填即提交」。

**電腦驗證 MEMORY 是否寫入 GPS：**

```bash
python verify_vlgeo2_gps_usb_watch.py
# 儀器 ENABLE MEM=ON，量測 + SEND，看終端是否 [新增] ✅ GPS
```

### 方案 C — 向 Haglof / Amit 確認韌體

問題範本：

> VLGEO2_3190 STD V3.7：MEMORY 關 + BLE NUS 逐棵 SEND 僅收到 `$PHGF,HVV`，無 `$GNGGA`。  
> §4.6.2 外部 GPS 是否必須走 Classic COM？BLE 是否有指令可開 GPS notify？

### 不建議

- **僅用手機 GPS**：環境學院已要求儀器 GPS
- **逆向韌體 .VL7/.VLB**：授權與維護成本極高，且 USB 已有 GPS 存檔證明硬體正常

## 下一步

1. Mac 配對 **Classic COM**，跑 `verify_vlgeo2_classic_gps.py`
2. 若 Classic 有 GGA → APP 開發方案 A
3. 若 Classic 也無 GGA → 跑 `verify_vlgeo2_gps_usb_watch.py`（MEMORY 開）+ 聯繫 Haglof
4. 逐棵 PHGF 解析器修復（§9.3 前綴）已合併至 `ble_live_packet_decoder.dart`
