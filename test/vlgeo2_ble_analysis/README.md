# 📡 VLGEO2 BLE 數據分析與測試工具

> **用途**：驗證 BLE 藍牙傳輸的數據完整性  
> **目標**：達到與官方 APP 100% 一致  
> **目前狀態**：99.1% 準確率（3 筆待修正）

---

## 📁 檔案結構

```
vlgeo2_ble_analysis/
├── README.md                     # 本文件
├── golden_standard/              # 官方黃金標準數據
│   └── DATA_2.CSV                # 官方 APP 匯出的 336 筆完整記錄
├── raw_captures/                 # 原始 BLE 封包捕獲
│   └── serial_20251125_200547.txt # Android BLE 原始日誌
├── analysis_scripts/             # Python 分析腳本
│   ├── compare_with_official.py  # 與官方數據比對
│   ├── trace_hex_pattern.py      # 追蹤 Hex 雜訊模式
│   └── test_filter_versions.py   # 測試各版本過濾器
├── filter_outputs/               # 各版本過濾器輸出
│   ├── PC_RECEIVED_V133.CSV
│   ├── PC_RECEIVED_V134.CSV
│   ├── PC_RECEIVED_V135.CSV
│   └── PC_RECEIVED_V135_PLUS.CSV
└── reports/                      # 分析報告
    └── remaining_3_errors.md     # 剩餘 3 筆差異分析
```

---

## 📊 剩餘 3 筆差異（待修正）

| ID | 欄位 | 官方值 | 我們的值 | 原因分析 |
|----|------|--------|----------|----------|
| 10071 | HD [24] | `4.5` | `42.5` | 封包邊界 '2' 字元被插入 |
| 10087 | UTC [19] | `85508` | `855089` | 末尾重複的 '9' |
| 10092 | 經度 [14] | `120.5366472` | `120.53664472` | 小數位重複的 '4' |

---

## 🔧 使用方式

### 1. 比對官方數據

```bash
cd vlgeo2_ble_analysis
python analysis_scripts/compare_with_official.py
```

### 3. 電腦端 GPS 驗證（寫進 APP 前必做）

依 Haglöf 硬體手冊 §4.6.2 / §9 / §10，確認「MEMORY 關 + 逐棵 SEND」時是否有 GPS NMEA 串流。

```bash
cd tree-project-frontend/test/vlgeo2_ble_analysis

# 監聽 BLE（連線後在儀器上量測并按 SEND，Ctrl+C 結束）
/Users/kyle/project_code/.venv/bin/python verify_vlgeo2_gps_ble.py

# 可選：檢查 USB 匯出 DATA.CSV 是否含 LAT/LON（MEMORY 存檔模式）
/Users/kyle/project_code/.venv/bin/python verify_vlgeo2_gps_ble.py --csv /Volumes/VL_GEO2/DATA/DATA.CSV
```

儀器設定（逐棵現場連線）：

- BLUETOOTH = ON
- USE GPS = ON，EXTERN.GPS = OFF
- ENABLE MEM = OFF

腳本會分類 `$PHGF`（量測）與 `$GNGGA` / `$GNRMC`（GPS），並在每次 PHGF 時顯示「當下最新 GGA 快照」。  
log 輸出：`raw_captures/gps_verify_YYYYMMDD_HHMMSS.log`

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

- Frontend: `lib/services/ble_field_validator.dart`
- Frontend: `lib/services/ble_data_processor.dart`
- Frontend: `lib/screens/ble_import_page.dart`

---

## 📞 聯絡資訊

- **Email**: 411135055@gms.ndhu.edu.tw
- **Repository**: KyleliuNDHU/tree-project-frontend
