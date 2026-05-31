# 韌體比對：V37 vs V39 vs BIOS V3.5

## 檔案
- `STD V37.VL7`: 97114 bytes, SHA256 `8b52cbcc1ced24cb1035328f6ed152c98e922fd2d9feffebefd163c682541294`
- `STD V39.VL7`: 99146 bytes, SHA256 `dbef30d6306e69dec8d7d1d433f7226a5f05938a0c3e9b99967ab96a60f86812`
- `VLGEO2_V3.5.VLB`: 293066 bytes, SHA256 `493432349f1705331d38d7affb4e8d1583ad1e9e952a59553d1e11ee2e495e48`

## STD V37 → V39（GPS/BLE 相關字串 diff）

### 僅 V39 新增 (1)
- `BRUK GPS`

### 僅 V37 有、V39 移除 (0)

### 兩版共同：GGA/RMC/NUS UUID 搜尋
- **V37**: GNGGA=無, NUS TX UUID=無
- **V39**: GNGGA=無, NUS TX UUID=無
- **VLB**: GNGGA=無, NUS TX UUID=無

## BIOS VLGEO2_V3.5.VLB

### 二進位關鍵字位置（前 5 個 offset）
- `GGA`: [67432]
- `RMC`: [67288]
- `VLGEO2_`: [2212]

### GPS/BLE 相關字串 (49)
- `ASENNUSRUTI.`
- `BLE    V%d`
- `BLE..`
- `BLUETOOTH`
- `BLUETOOTH `
- `BLUETOOTH  `
- `BOTOES DME/SEND`
- `BT122_BGAPI.BIN`
- `Bluetooth`
- `Bluetooth `
- `CAL.COMP. `
- `CAL.COMPASS`
- `CAL.COMPASS `
- `COMMENCER`
- `COMPASS`
- `COMPASS   `
- `Comece a`
- `Command`
- `DME/SEND`
- `DME/SEND EIN`
- `EINGABE GPS`
- `ENABLE MEM `
- `ENTRAR GPS`
- `ERR COMPASS`
- `EXTERN.GPS`
- `FAIBLE `
- `GPS `
- `GPS INIT...`
- `GPS PIN`
- `INFO COMP.`
- `MED DME/SEND`
- `NO GPS`
- `NUSTATYMAI  `
- `No gps data!`
- `POM.DME/SEND`
- `Reading gps`
- `SELECT BLE`
- `Send     `
- `Send      `
- `Sende    `
- `Senden   `
- `Sending... `
- `TLA.DME/SEND`
- `USE GPS`
- `VISTA COM OS`
- `VLOZ GPS`
- `YOUR GPS`
- `ZADNE GPS`
- `_COM`

## 結論

1. **STD 3.9 vs 3.7**：GPS/BLE 相關 diff 主要是翻譯/介面（如 `BRUK GPS`），**未出現 GGA/RMC 或 BLE GPS notify 新字串**。
2. **PHGF 格式字串兩版相同**：`$PHGF,HVV,...` 仍無 LAT/LON。
3. **BIOS V3.5** 含 `USE GPS`、`EXTERN.GPS`、`Reading gps`、`No gps data!` → **GPS 串流邏輯在 BIOS 層**。
4. **VLB 亦無 `$GNGGA` 明文**（可能執行時組句，或壓縮在 code 段）；Classic SPP / GATT UUID 需進一步反組譯，非 strings 可解。
5. **升級到 V3.5 + STD 3.9 不太可能新增「BLE 逐棵 GPS」**；若要做 Classic GPS，應從 VLB 的 `Reading gps` / Bluetooth stack 查 SPP 為何 Mac 0-byte。

> 副本位置：`firmware_backup/downloads/`。請勿刷回儀器，除非環境學院自行決定。
