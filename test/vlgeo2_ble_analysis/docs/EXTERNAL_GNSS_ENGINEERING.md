# 外接 GNSS 工程方案（對照 VLGEO2 內建 GPS）

> 現場量測仍用 **STD + 1P/3P + SEND**；座標可來自內建或外接。  
> 手冊 Rev.1 §4.6、§10；產品頁 [Vertex Laser Geo 2](https://haglofsweden.com/project/vertex-laser-geo-2/)。

---

## 1. VLGEO2 內建 GPS 能力清單（手冊 §10）

### 衛星系統（主機可解）

| 類別 | 系統 |
|------|------|
| **GNSS 星座** | GPS（美）、GLONASS（俄）、Galileo（歐）、QZSS（日） |
| **SBAS 增強** | WAAS（美）、EGNOS（歐）、MSAS（日）、GAGAN（印） |
| **未列於手冊** | **BeiDou（北斗）** — 規格表未寫，勿假設有 |

### 性能（開闊地、內建）

| 項目 | 規格 |
|------|------|
| 通道 | 33 tracking / 99 acquisition |
| 更新率 | **1 Hz** |
| 精度（SBAS、自動） | **約 2.5 m CEP**（50% 圓概率） |
| 座標系 | **WGS84** |
| 輸出協定 | NMEA（GGA、RMC、GSA、GSV…）— 走 Classic `_COM`（你們 Mac 實測 0 byte） |
| 存檔 | MEMORY ON → **`DATA.CSV` 第 12/14 欄 LAT/LON** |
| 冷啟動 | 28 s～15 min（視環境）；手冊建議 **GPS 開後等 ~10 min** 再存座標 |
| 工作溫度 | −40 ℃～+85 ℃（模組規格） |

### 現場「有連到衛星」怎麼看（儀器上）

1. **SETTINGS → GPS → USE GPS = ON**  
2. 等 **fix**（螢幕 **3D FIX**、衛星數、N/E 座標）  
3. **MEMORY ON** 量測 → **SEND** → `DATA SAVED`  
4. 收工 **USB** 或 **SEND FILES** 看 CSV 的 LAT/LON 是否有值  

**沒有**在儀器 UI 列出「每顆衛星 PRN 清單」；細部需 Classic NMEA **GSV**（你們目前收不到）或外接接收機原廠 app。

---

## 2. 工程目標對照

| 需求 | 內建 GPS | 僅手機 GPS | 外接 GNSS（推薦方向） |
|------|----------|------------|------------------------|
| 維持 STD 現場量樹 | ✅ | ✅ | ✅ |
| 座標進「儀器存檔」 | ✅ MEMORY | ❌ 環境學院不要 | ✅ **EXTERN.GPS** |
| 比 2.5 m 更準 | ❌ | 視手機 | ✅ 可 sub‑m～cm（看設備） |
| 與手冊同星座 | GPS/GLO/GAL/QZSS | 視手機 | 選 **≥ 四星座 + SBAS** |
| 森林 canopy | 一般 | 一般 | 選 **多頻 / 高靈敏** 機種 |

---

## 3. 推薦架構（量測不變 + 座標升級）

### 方案 A — **外接 BT GPS → 儀器 EXTERN.GPS**（最符合「儀器座標」）

手冊 §4.6.1 步驟 5：**EXTERN.GPS ON** → 配對外接藍牙 GPS（例：Geode、Trimble R1）。

```
[外接 GNSS 接收機] ──Bluetooth──→ VLGEO2（EXTERN.GPS）
                                      │
                    現場：STD 量樹 → SEND（MEM ON）
                                      │
                              DATA.CSV 的 LAT/LON = 外接機座標
                                      │
                    手機：BLE SEND FILES → APP 取最新一列
```

- **量測流程不變**（仍 1P/3P + SEND）  
- **座標來自外接機，但寫進儀器 CSV** — 可與老師確認是否算「儀器 GPS 資料流」  
- **不需** Classic COM 在 Mac 上通  
- 外接機需 **Bluetooth 可被 Geo2 配對**（查各產品是否 SPP / 被 Haglöf 列為相容）

### 方案 B — **外接 GNSS → 手機 + VLGEO2 BLE PHGF 合併**

- MEM OFF → BLE 收 PHGF；外接機连手机收 NMEA，**時間戳配對**  
- 環境學院若堅持「非手機 GPS」，需事先確認 **外接接收機是否接受**

### 方案 C — **維持內建 GPS + MEMORY + BLE 同步**（零硬體）

- 精度 **~2.5 m**，但流程已驗證、無 license、無外掛  

---

## 4. 外接設備選型（要比內建更好）

手冊明示範例：[Geode](https://juniper-sys.com/products/geode/)、[Trimble R1](https://geospatial.trimble.com/en/products-and-solutions/gnss-handhelds/trimble-r1)（精度 <1 m 級，需查型錄）。

選購時對照內建，至少滿足：

| 項目 | 內建 Geo2 | 外接建議 |
|------|-----------|----------|
| GPS + GLONASS + Galileo + QZSS | ✅ | ✅ 四星座 |
| SBAS | ✅ | ✅ |
| BeiDou | ❓ 未列 | 台灣野外建議 **有 BDS** |
| 更新率 | 1 Hz | ≥ 1 Hz（量樹夠用） |
| 精度 | ~2.5 m CEP | **sub‑meter** 起跳；預算夠才 RTK cm |
| 藍牙 | Geo2 當 host 配對外接 | 確認 **與 Geo2 EXTERN.GPS 可配對** |
| 野外 | IP67 儀器 | 接收機 + 天線 **防摔防雨**、長续航 |

**不建議** 為此專案先買 **RTK 基站+ rover（cm 级）** — 成本高、森林不一定需要，除非老師明確要求。

**實務下一步：** 向租賃/經銷商借 **Trimble R1 或 Juniper Geode** 一天，在 Geo2 上 **EXTERN.GPS ON** 配對 → MEM ON 量 2 棵 → 看 CSV LAT/LON 是否來自外接機且優於內建。

---

## 5. 與已失敗方案的關係

| 方案 | 狀態 |
|------|------|
| Classic `_COM` 收 GGA | Mac 0 byte，暫停 |
| USB 邊量邊讀 CSV | **不可**（量測會離開 USB mode） |
| BLE 逐棵 PHGF + 內建 GPS | **無 GPS 欄** |
| **MEMORY + BLE SEND FILES** | ✅ 內建 GPS，工程主線 |
| **EXTERN.GPS + 同上** | ✅ 精度升級主線 |

---

## 6. 建議執行順序

1. 用 **`installable/STD V39`** 與 **MEMORY + BLE SEND FILES** 跑通 APP（內建 GPS）  
2. 與環境學院確認：**EXTERN.GPS 寫入 CSV 的座標是否可接受**  
3. 借測 **R1 / Geode** → EXTERN.GPS 實機驗證  
4. 再決定是否採購外接機（預算、樹位精度需求）
