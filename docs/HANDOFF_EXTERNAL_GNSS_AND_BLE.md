# 交接：外接 GNSS + 現場 BLE 量測（2026-05，外接 GNSS 已取消）

> ⚠️ **狀態（2026-05-28 專案決議）：外接 GNSS 不採購、不續做**。
> 現場 GPS 一律使用**手機定位（樹旁取樣）**，現行流程見 `FIELD_SURVEY_SOP.md`。
> 本文件保留作為**技術存檔**：若日後重啟外接 GNSS，按此文件繼續即可。
> 文中「下一步程式」皆為**未實作的歷史規劃**（`external_gnss_service.dart` 不存在）。
>
> **交接總覽**：[`HANDOFF.md`](HANDOFF.md)；儀器實測結論見 `test/vlgeo2_ble_analysis/docs/`。

## 現狀（APP）

| 檔案 | 職責 |
|------|------|
| `lib/screens/ble_live_session_page.dart` | 現場連線：BLE 收 PHGF → 取 GPS → 建任務 → 開表單 |
| `lib/services/ble_live_packet_decoder.dart` | `$PHGF` 分片重組（**已修第二棵 §9.3 前綴 bug**） |
| `lib/utils/field_gps_capture.dart` | **目前 GPS 來源 = 手機 Geolocator**（多點取樣） |
| `lib/widgets/field/field_session_setup.dart` | `gpsSource`: `surveyor` \| `tree` |

### 收到 PHGF 後的流程

```
_onPacket → BleLiveNmeaAssembler.feed
         → _processLiveMeasurement
         → _resolveGpsForLiveMeasurement  ← 這裡要接外接 GNSS
         → createAndUploadFromBle → IntegratedTreeFormPage
```

### 下一步程式（外接 GNSS）

1. 新增 `lib/services/external_gnss_service.dart`（或 `instrument_gnss_cache.dart`）  
   - BLE 連外掛（NUS 或 SPP platform channel）  
   - 解析 `$GNGGA` / `$GNGSA` / `$GPGSV`  
   - 暴露：`fixType`（2D/3D）、`satellitesUsed`、`satellitesInView`、`hdop`、`latitude`、`longitude`、`accuracyM`  
   - UI：類似儀器「衛星數跳動」→ `Stream<GnssFixStatus>`

2. 擴充 `FieldSessionSetup.gpsSource`：  
   - `external_gnss` | `instrument_csv` | 保留 `surveyor`/`tree`

3. 改 `_resolveGpsForLiveMeasurement`：  
   - `external_gnss` → 讀 `ExternalGnssService.latestFix`（或量測前一步「定位」按鈕強制更新）  
   - metadata 寫入：`gps_source`, `fix_3d`, `sat_count`, `hdop`, `receiver_model`

4. 可選第二路線：`instrument_csv` = MEMORY ON + BLE SEND FILES，解析 `DATA.CSV` 最後一列（見 `verify_vlgeo2_gps_usb_watch.py`）

## 硬體（已下單 2026-05）

| 品項 | 狀態 |
|------|------|
| LG290P GNSS RTK Module | 已買；**不帶 RTC 電池**版（RTK/standalone 能力同電池版） |
| ESP32-C3 | 已買 ¥20.79；**待確認是否帶排針 -M** |
| ML1220 | 未附；可選後補 |
| 5V 電源 / 線 | 自備 |

## 硬體架構

### 建議架構（量測與定位分步）

```
[VLGEO2] BLE PHGF ──────────────→ 手機 APP（樹高/距離/方位）
[外掛 GNSS] BLE NMEA/自訂 GATT ─→ 手機 APP（3D fix、衛星數、HDOP、座標）
```

- **不要**指望 Geo2 mini-USB **對外供電**：該孔為 **Device 口**（充電 + 接電腦傳檔），**不是 Host**，不能當外掛電源。  
- 外掛用 **自有行動電源（5V）**；見下方採購清單。  
- 機械：**1/4"-20 母牙**（手冊 monopod mount）→ 3D 列印支架 + 短螺柱；GNSS 天線朝上、少遮擋。

---

## VLGEO2 內建 GPS 是哪一種？（不是方案 1 也不是方案 2）

手冊 §10（見 `test/vlgeo2_ble_analysis/docs/EXTERNAL_GNSS_ENGINEERING.md`）：

| 項目 | **VLGEO2 內建** | 方案 2 LC29H(DA) | 方案 1 LG290P |
|------|-----------------|------------------|---------------|
| 晶片世代 | 儀器整合 **單頻** GNSS | 移遠 **雙頻 L1+L5** RTK SoC | 移遠 **四頻 L1+L2+L5+E6** RTK SoC |
| 星座 | GPS / GLONASS / Galileo / QZSS + SBAS | 上列 + **北斗 B1/B2a** | 上列 + **北斗全頻** + NavIC |
| **RTK** | **❌ 無** | ✅（需 NTRIP 才 cm） | ✅ |
| Standalone 精度 | **~2.5 m CEP**（SBAS） | **~1.0 m CEP** | **~0.7 m CEP** |
| 更新率 | **1 Hz** | 最高 10 Hz | 最高 20 Hz |
| 輸出 | NMEA（Classic `_COM`；你們 Mac 實測 0 byte） | UART NMEA | UART NMEA |

**結論**：Geo2 是 **「舊式單頻 multi-GNSS + SBAS、無 RTK」** 的儀器級 GPS，**技術類型上比方案 1、2 都舊**；精度上 **方案 1、2 的 standalone 規格都明確優於 Geo2**。  
硬要比「像誰」：比較接近 **沒有 RTK 功能的入門外接 GPS**，**不像** 方案 1/2 這種現代雙頻/四頻 RTK 模組。

### 方案 1 vs 方案 2 差別（為何推薦方案 1）

| | **方案 1 LG290P** | **方案 2 LC29H(DA)** |
|--|-------------------|----------------------|
| 精度（standalone） | **0.7 m**（更好） | 1.0 m（仍優於 Geo2） |
| 頻段 | L1+L2+L5+**E6** 四頻 | L1+L5 雙頻 |
| 體積 | 33×33 mm 小模組 | 65×30 mm HAT（不必買 Pi） |
| 台灣/亞洲 | 北斗 + SBAS 較完整 | 有北斗，頻段較少 |
| 價格（微雪） | **約 ¥500** | **約 ¥350** |
| UART 預設波特率 | **460800** | **115200** |
| 套件 | Type-C + **含天線** + SH1.0 線 | Micro-USB + **含天線** |

**確定採用：方案 1**（精度最好、價差僅約 ¥150，仍遠低於 Trimble 路線）。

---

## 採購清單（2026-05｜**方案 1 定案**｜僅信官方/旗艦店）

> **基準**：VLGEO2 ≈ **2.5 m CEP**。LG290P standalone **0.7 m CEP**。  
> **勿買**：¥45–90「F9P」、無品牌裸板。

### 必買（僅 2 項；線材 / 行動電源用既有即可）

| # | 品名 | 數量 | 參考價 | 購買連結 |
|---|------|------|--------|----------|
| 1 | **LG290P GNSS RTK Module**（含天線、SH1.0 線、排針） | 1 | **¥499.95** | https://www.waveshare.net/shop/LG290P-GNSS-RTK-Module.htm |
| 2 | **ESP32-C3-Zero-M**（帶排針，燒 TreeGNSS 韌體） | 1 | **約 ¥35–55** | https://www.waveshare.net/shop/ESP32-C3-Zero-M.htm |

**微雪淘寶同一貨源**（可合併下單減運費）：https://world.taobao.com/dianpu/442244005.htm  

**接線 Wiki（LG290P ↔ ESP32）**：https://www.waveshare.net/wiki/LG290P_GNSS_RTK_Module

**自備**：任意 **5V ≥2A** 行動電源 + USB 線（LG290P Type-C、ESP32-C3 依板子接口）。合計約 **220 mA**，一場調查足夠。

### 選配

| # | 品名 | 用途 |
|---|------|------|
| 3 | **ML1220 3V 鈕扣電池** | LG290P JST 熱啟動；**五金行可買**，非必須 |
| 4 | 1/4"-20 公牙 + 3D 列印盒 | 固定於 Geo2 monopod 接口；天線垂直朝天 |

### 電源與信號（方案 1）

```
[既有 5V 行動電源]
   ├─ USB ──→ LG290P（~100 mA）
   └─ USB ──→ ESP32-C3-Zero（~120 mA）

LG290P TXD3（NMEA，460800）──→ ESP32 RX
GND 共地
```

**Geo2 不給外掛供電**；手機另連 VLGEO2 BLE + TreeGNSS BLE。

### 現場架設（勿綁大行動電源在握把）

- **推薦**：1/4"-20 短桿 + 3D 列印盒（LG290P + ESP32 + 小電池），天線**垂直朝天**；Geo2 只管瞄準。  
- **勿**：量樹時讓 GNSS 剛性隨 Geo2 大幅傾斜（精度變差）。  
- 詳見 [`HANDOFF_外接GNSS現場量測.md`](HANDOFF_外接GNSS現場量測.md) §二。

### 方案 2（更省約 ¥150）：仍優於 Geo2 — 約 **¥450 ≈ NT$2,000**

| # | 買什麼 | 規格 | 連結 | 參考價 |
|---|--------|------|------|--------|
| 1 | **LC29H(DA) GPS/RTK HAT** | 移遠 LC29H；**PVT ~1 m CEP**；RTK cm；**含 GPS External Antenna (D)** | [微雪 LC29H(DA)](https://www.waveshare.net/shop/LC29H-DA-GPS-RTK-HAT.htm) | 約 **¥349** |
| 2 | ESP32-C3-Zero | 同上 | 同上 | 約 **¥35–55** |
| 3–5 | 電源 + 線 + ML1220 | 同上 | — | 約 **¥100** |

**注意**：LC29H 為 40pin HAT 外形，**不必買樹莓派**；5V + UART 跳線帽切到「外接 MCU UART」（見 LC29H Wiki），再接 ESP32。

### 方案 3（F9P 雙頻 L1+L2，林下略穩）— 約 **¥750–950 ≈ NT$3,400–4,300**

| # | 買什麼 | 連結 | 參考價 |
|---|--------|------|--------|
| 1 | **ZED-F9P GPS-RTK HAT**（含多頻天線） | [微雪 ZED-F9P HAT](https://www.waveshare.net/shop/ZED-F9P-GPS-RTK-HAT.htm) | 約 **¥900+**（官網變動） |
| 2 | ESP32-C3-Zero + 電源 | 同上 | 約 **¥150** |

**北天原廠（僅當微雪缺貨）**：[北天旗艦店](https://www.taobao.com/list/dianpu/332390975.htm) · 型號 **BT-F9PK3**（含天線）；到貨用 **u-center** 讀晶片應為 u-blox ZED-F9P。

### 不要買的清單

| 商品 | 原因 |
|------|------|
| NEO-6M / ATGM336 / ¥45「F9P」 | 精度 **≤ 或差於** Geo2 2.5 m |
| 無天線裸 F9P 模組 | 無 L1/L2 天線則精度崩盤 |
| 無店鋪評分 / 「其他品牌」超低價 F9P | 假晶片高發；見下方驗收 |

---

## 外接電源（已納入上表）

```
[5V 行動電源 雙口]
   ├─ USB-C ──→ LG290P / LC29H（5V，<120 mA）
   └─ USB-C ──→ ESP32-C3-Zero（5V，~120 mA BLE 廣播時）

[信號線] LG290P TXD3（NMEA）──→ ESP32 RX（如 GPIO4）
         GND ──────────────────→ ESP32 GND
（只讀 NMEA 時可不接 GNSS RX）
```

- Geo2 **不能**給外掛供電；外掛與 Geo2 **分電**。  
- 現場：**手機** 同時 BLE 連 `VLGEO2_3190` + `TreeGNSS`（ESP32 廣播名，見下）。  
- 天線用隨板 **IPEX→SMA 短線** 接有源天線，**天線面朝天**，盡量高於冠層。

---

## APP 整合規格（與現有 VLGEO2 BLE 並存）

### 為何不會白花錢（整合保證）

| 依據 | 說明 |
|------|------|
| **標準 NMEA** | LG290P 輸出 `$GNGGA` / `$GNGSA`；全球通用，非廠商私有 |
| **標準 BLE NUS** | 與 Geo2 相同 Service/Notify UUID（見 `lib/utils/ble_uart_discovery.dart`） |
| **APP 已有 BLE 堆疊** | `flutter_blue_plus` 已連 Geo2；第二設備連 `TreeGNSS` 為同庫擴展 |
| **明確接點** | `_resolveGpsForLiveMeasurement`（L399）現用 Geolocator → 改讀 `ExternalGnssService` |
| **備選路線** | 若外掛不可用：MEMORY + CSV GPS（零硬體，精度 2.5 m） |
| **微雪官方 ESP32 範例** | LG290P Wiki 含 ESP32 UART 接線；韌體僅多一層 BLE 轉發 |

**剩餘工作**：ESP32 韌體 + `external_gnss_service.dart` + `gpsSource` 列舉（見 [`HANDOFF_外接GNSS現場量測.md`](HANDOFF_外接GNSS現場量測.md) §六）。

與 `ble_live_session_page.dart` 相同 **Nordic UART Service**，第二路 BLE 設備：

| 項目 | 值 |
|------|-----|
| 設備廣播名 | `TreeGNSS`（勿與 Geo2 混淆） |
| Service UUID | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| Notify（手機收 NMEA） | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |
| 載荷 | ASCII NMEA 行，建議 **1–5 Hz**：`$GNGGA` / `$GNGSA` / `$GPGSV` 或 `$GNGSV` |
| UART 速率 | LG290P 預設 **460800**；LC29H **115200**；ESP32 須一致 |
| APP | `gpsSource: external_gnss` → `ExternalGnssService` 解析 → `_resolveGpsForLiveMeasurement` |

ESP32 韌體：讀 UART → 按行分包 BLE notify（可參考 [ArduSimple BLE Bridge](https://www.ardusimple.com/product/ble-bridge/) 思路；UUID 用上表即可對接 Flutter）。

---

## 到貨驗收（防假貨）

1. **LG290P / LC29H**：電腦 USB 接板，[QGNSS](https://www.waveshare.net/wiki/LG290P_GNSS_RTK_Module) 或移遠工具讀模組型號。  
2. **ZED-F9P**：Windows **u-center** 讀應為 **ZED-F9P**，非 NEO-M8N。  
3. **開闊地測試**：standalone 水平誤差應 **明顯 < 2.5 m**（通常 0.7–1.5 m）；若長期 > 5 m，檢查天線與假模組。  
4. **BLE 測試**：手機 nRF Connect 連 `TreeGNSS`，notify 應持續出現 `$GNGGA`。

### 精度對照（datasheet，standalone PVT）

| 產品 | PVT CEP | vs Geo2 2.5 m |
|------|---------|-----------------|
| LG290P | **0.7 m** | ✅ 約好 3.5× |
| LC29H(DA) | **1.0 m** | ✅ 約好 2.5× |
| ZED-F9P | **1.5 m**（開闊常更好） | ✅ |
| VLGEO2 內建 | **2.5 m** | 基準 |

**cm 級**需另配 **NTRIP**（如台灣 e-GNSS **NT$300/日/組** + 註冊）；硬體同上，非再買 Trimble。

### 台灣 GNSS / RTK 說明

| 模式 | 台灣可用 | 費用 | 說明 |
|------|----------|------|------|
| **Standalone PVT** | ✅ | 無 | 本專案現階段；~0.7 m，優於 Geo2 |
| **RTK cm** | ✅ | e-GNSS 等付費 | 需 NTRIP + 手機網路 + 韌體灌 RTCM；千尋（大陸）非台灣主方案 |
| **RTC 電池 ML1220** | ✅ 可後補 | 約幾十台幣 | 僅縮短斷電後再定位等待，**不影響精度** |

- 國土地圖 **e-GNSS**：https://egnss.nlsc.gov.tw/（法人註冊 + 按日計費）  
- **冷啟動**：斷電久再開，無電池時可能多等 ~20–30 s 才有 fix，非手動改時間。

---

### 其他採購方向（非 DIY）

| 等級 | 產品例 | 精度 | 與 APP |
|------|--------|------|--------|
| 入門 multi-GNSS | Bad Elf Flex / Garmin GLO 2 | ~2–3 m | 手機 BT SPP 收 NMEA → 需 Android SPP 或原廠 SDK |
| 專業 sub-meter | **Trimble R1**、Juniper **Geode GNS3** | sub-m | BT NMEA；可選 **EXTERN.GPS 接 Geo2** 寫 CSV |
| 高精度 | Emlid Reach RS2+（RTK） | cm | 成本高；需 NTRIP/基站；APP 需接 Reach SDK 或 NMEA |
| 成品免焊 | **Columbus P-70 Ultra** | standalone ~30 cm | [GPSWebShop ~USD299](https://gpswebshop.com/products/columbus-p-70-ultra-precise-usb-and-bluetooth-gnss-receiver) · 內建 BT，免 ESP32 |

### 與環境學院

- 外接 **survey-grade** 接收機經 BLE 進 APP ≠ 手機內建 GPS，需老師確認是否接受。  
- **EXTERN.GPS → Geo2 CSV** 則座標在儀器檔內，另需 MEMORY + SEND FILES 同步。

## 儀器韌體（repo）

- 可安裝：`test/vlgeo2_ble_analysis/firmware_backup/installable/STD V39.VL7`  
- 勿裝未購 license：`BAF V14`、`Pile V25`（見 `downloads/README_LICENSED.md`）

## 驗證腳本

```bash
# Classic GPS（Mac 目前 0 byte，保留排查）
python test/vlgeo2_ble_analysis/verify_vlgeo2_classic_gps.py --diag

# MEMORY + USB 監看 CSV
python test/vlgeo2_ble_analysis/verify_vlgeo2_gps_usb_watch.py
```
