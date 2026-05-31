# 交接：外接 GNSS + 現場 BLE 量測（2026-05）

> 給換電腦後接手的開發者。儀器實測結論見 `test/vlgeo2_ble_analysis/docs/`。

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

## 規劃中的硬體（產品尚未買）

### 建議架構（量測與定位分步）

```
[VLGEO2] BLE PHGF ──────────────→ 手機 APP（樹高/距離/方位）
[外掛 GNSS] BLE NMEA/自訂 GATT ─→ 手機 APP（3D fix、衛星數、HDOP、座標）
```

- **不要**指望 Geo2 mini-USB **對外供電**：該孔為 **Device 口**（充電 + 接電腦傳檔），**不是 Host**，不能當外掛電源。  
- 外掛用 **自有 LiPo / 18650** 或獨立 USB 充電。  
- 機械：**1/4"-20 母牙**（手冊 monopod mount）→ 3D 列印支架 + 短螺柱；GNSS 天線朝上、少遮擋。

### 採購方向（依精度預算）

| 等級 | 產品例 | 精度 | 與 APP |
|------|--------|------|--------|
| 入門 multi-GNSS | Bad Elf Flex / Garmin GLO 2 | ~2–3 m | 手機 BT SPP 收 NMEA → 需 Android SPP 或原廠 SDK |
| 專業 sub-meter | **Trimble R1**、Juniper **Geode GNS3** | sub-m | BT NMEA；可選 **EXTERN.GPS 接 Geo2** 寫 CSV |
| 高精度 | Emlid Reach RS2+（RTK） | cm | 成本高；需 NTRIP/基站；APP 需接 Reach SDK 或 NMEA |

**自研外掛（長期）**：u-blox **ZED-F9P**（多頻 GPS+GLO+GAL+BDS）+ **ESP32** BLE NUS 轉發 GGA/GSA/GSV（1–5 Hz），天線 **ANN-MB1** 級。

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
