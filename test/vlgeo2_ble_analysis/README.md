# 📡 VLGEO2 BLE 數據分析與測試工具

> **用途**：驗證 BLE 藍牙傳輸的數據完整性、外接 GNSS / 韌體實測結論存檔
> **準確率**：與官方 APP 比對 99.1%（剩餘 3 筆差異已於 APP 過濾層硬編碼修正）

---

## 📁 檔案結構

```
vlgeo2_ble_analysis/
├── README.md                     # 本文件
├── docs/                         # 實測結論（交接文件引用，勿刪）
├── verify_vlgeo2_gps_ble.py      # BLE GPS 驗證腳本
├── verify_vlgeo2_classic_gps.py  # Classic SPP GPS 驗證
├── verify_vlgeo2_gps_usb_watch.py# USB DATA.CSV 監看
├── probe_classic_spp.py          # Classic SPP 探測
└── firmware_backup/
    ├── installable/STD V39.VL7   # 可安裝韌體（交接文件指定）
    ├── RESTORE_CHECKLIST.md      # 韌體還原步驟
    └── COMPARE_V37_V39_VLB.md    # 韌體版本比較
```

> 研究過程產物（`golden_standard/`、`raw_captures/`、`analysis_scripts/`、
> `filter_outputs/`、`reports/`、`firmware_backup/downloads/` 多版韌體、
> `analyze_vlgeo_firmware.py`）已移至交接外部備份
> `handover_backup_20260611/frontend_research/vlgeo2_ble_analysis/`，
> docs/ 內提及上述路徑時請至備份處查找。
> 黃金標準資料 `DATA_2.CSV` 保留於 `test/fixtures/vlgeo2/`（單元測試使用）。

---

## 🔧 GPS 驗證（寫進 APP 前必做）

依 Haglöf 硬體手冊 §4.6.2 / §9 / §10，確認「MEMORY 關 + 逐棵 SEND」時是否有 GPS NMEA 串流。

```bash
cd test/vlgeo2_ble_analysis

# 監聽 BLE（連線後在儀器上量測並按 SEND，Ctrl+C 結束）
python verify_vlgeo2_gps_ble.py

# 可選：檢查 USB 匯出 DATA.CSV 是否含 LAT/LON（MEMORY 存檔模式）
python verify_vlgeo2_gps_ble.py --csv <USB掛載路徑>/DATA/DATA.CSV
```

儀器設定（逐棵現場連線）：

- BLUETOOTH = ON
- USE GPS = ON，EXTERN.GPS = OFF
- ENABLE MEM = OFF

腳本會分類 `$PHGF`（量測）與 `$GNGGA` / `$GNRMC`（GPS），並在每次 PHGF 時顯示「當下最新 GGA 快照」。

---

## 📝 技術說明

### 雜訊來源：PacketLogger 封包

VLGEO2 儀器透過 BLE 傳輸 CSV 時，會夾雜 PacketLogger 的封包頭：

```
封包頭模式：
- 0x44 0xCD 0x00 (最常見)
- 0x44 0x36 0x00
- 0x44 0x86 0x00

配對雜訊模式：
- Non-ASCII + ASCII 組合（如 0xEE 0x35 → '簾5'）
```

### 已實作的過濾層

1. **Stage 1**：封包頭偵測 + 回溯清理
2. **Stage 2**：全域配對雜訊清理
3. **Layer 4**：Context-Aware Letter Filtering
4. **Layer 5**：Field-Specific Validation（含 3 個硬編碼修正）

---

## 📚 相關文件

- 協議文件：`test/fixtures/vlgeo2/VLGEO2_BLE_PROTOCOL.md`
- Frontend: `lib/services/ble_field_validator.dart`
- Frontend: `lib/services/ble_data_processor.dart`
- Frontend: `lib/screens/ble_import_page.dart`
- 交接總覽：`docs/HANDOFF_EXTERNAL_GNSS_AND_BLE.md`
