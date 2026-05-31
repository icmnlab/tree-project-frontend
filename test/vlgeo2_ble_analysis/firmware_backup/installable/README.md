# 可直接使用的 Geo2 應用（免 license）

本資料夾**只放免費、可合法安裝**的檔案。需付費 license 的 BAF / 3D Pile **不在此**（見 `../downloads/README_LICENSED.md`）。

| 檔案 | 版本 | 用途 |
|------|------|------|
| `STD V39.VL7` | STD 3.9 | 標準量測 app（1P/3P 樹高等），**買機附贈、免費升級** |

你機上目前是 **STD V3.7**；V3.9 主要是 feet 胸徑 bugfix，**不會**單獨解決 BLE 逐棵 GPS，但可安全升級。

---

## 一、安裝 STD V39（與 V37 並存）

1. **USB** 連 Mac → 儀器進 **USB mode** → 出現 `/Volumes/VL_GEO2`
2. 複製 **`STD V39.VL7`** → **`VL_GEO2/PRG/`**（**不要刪** 既有的 `STD V37.VL7`）
3. Mac **安全退出** 磁碟 → **拔 USB**
4. 儀器開機 → **SETTINGS → SELECT PROG**
5. 選 **STD V39**（或檔名對應的 STD 3.9）→ **START**
6. 若無 LICENSE 錯誤 → 成功

### 切回 V3.7

**SETTINGS → SELECT PROG → STD V37 → START**（V37 檔仍在 `PRG/` 即可）。

### 還原參考

完整還原步驟：`../RESTORE_CHECKLIST.md`

---

## 二、現場量測 + 儀器 GPS（推薦工程 SOP）

Classic COM 在 Mac 上無資料；USB 與量測互斥。**可用流程：**

### 儀器設定（每場次一次）

| 項目 | 設定 |
|------|------|
| BLUETOOTH | ON |
| USE GPS | ON |
| EXTERN.GPS | OFF（用內建 GPS）或 ON（外接高精度 GPS，見 `../../docs/EXTERNAL_GNSS_ENGINEERING.md`） |
| ENABLE MEM | **ON** |
| 手機 | 先配對 BLE **`VLGEO2_3190`**（不是 `_COM`） |

### 每一棵樹

1. 用 **HEIGHT 1P / 3P**（或你們 SOP）量測  
2. 按 **SEND** → 螢幕 **DATA SAVED**（寫入 SSD `DATA/DATA.CSV`，含 LAT/LON）  
3. 手機 APP：**同步**（觸發儀器 **MEMORY → SEND FILES**，BLE 收 CSV）  
4. APP **只取最新一列** → 填 DBH → 提交  

（第 3 步等同 Haglof Link 收整檔；你們在 APP 端 diff 最後一列即可。）

### 驗證腳本（Mac，收工後 USB）

```bash
/Users/kyle/project_code/.venv/bin/python \
  tree-project-frontend/test/vlgeo2_ble_analysis/verify_vlgeo2_gps_usb_watch.py
```

MEM ON 量測 + SEND 時，終端應出現 `[新增] ✅ GPS ...`。

---

## 三、不要在本機安装的檔案

`../downloads/` 內的 **BAF V14.VL7**、**Pile V25.VL7** 需向 [Haglöf](https://haglof.app) **每台 Geo2 另購 license**，未購買前**勿複製到 PRG/**。
