# VLGEO2_3190 還原檢查表（貼在實驗前）

## 開機正常時應看到

- [ ] 開機進 **STD** 主選單（非卡在 UPGRADING）
- [ ] SETTINGS → 可進 GPS / BLUETOOTH / MEMORY
- [ ] 量測 + SEND → BLE 有 PHGF（MEMORY OFF）

## 還原 App（約 5 分鐘）

1. USB 連 Mac → `/Volumes/VL_GEO2`
2. 複製 `firmware_backup/VLGEO2_3190_20260531/STD V37.VL7` → `PRG/`
3. 安全退出 USB，開機
4. SETTINGS → SELECT PROG → **STD V37** → START
5. 若無 LICENSE 畫面 → 正常（STD 免費）

## 還原 BIOS（約 10 分鐘，僅異常時）

1. 複製 `firmware_backup/downloads/VLGEO2_V3.5.VLB` → **根目錄**
2. 拔 USB，**關機**
3. **按住 SEND**，插 USB，等升級完成
4. 拔 USB，開機 → 再做「還原 App」

## BIOS 救援模式

- 關機 → **SEND + DME** 長按開機 → SELECT PROG / START PROG

## 三鍵重置（app 鎖死）

- **ON + DME + SEND** 同時按

## 備份位置

`tree-project-frontend/test/vlgeo2_ble_analysis/firmware_backup/`
