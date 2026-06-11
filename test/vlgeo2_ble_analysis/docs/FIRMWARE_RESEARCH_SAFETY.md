# VLGEO2 韌體研究安全手冊（防磚機）

> 目標：研究修改 `.VL7` / `.VLB` 以支援「逐棵 SEND + 儀器 GPS」  
> 原則：**先能救回，再動手**；**先官方流程練熟，再改副本**  
> 序號：**VLGEO2_3190** | 現況：STD **V3.7** | 官方最新：BIOS **V3.5**、STD **V3.9**

---

## 0. 法律與保固（手冊 §13.4）

- Haglöf 聲明：**Unauthorized duplication is prohibited**
- 改韌體可能導致 **保固失效**（misuse/negligence）
- 學校設備若損壞，**賠償責任**需與指導老師/環境學院先確認

**建議**：書面記錄「研究授權／自負風險」後再動機器。

---

## 1. 韌體兩層架構（必須分開想）

| 層級 | 副檔名 | 位置 | 誰管什麼 | 刷壞後果 |
|------|--------|------|----------|----------|
| **BIOS** | `.VLB` | USB 根目錄 → SEND+USB 升級 | 藍牙 stack、GPS `Reading gps`、`_COM`、開機 | **最嚴重**；可能只顯示 UPGRADING / ERROR |
| **應用** | `.VL7` | `VL_GEO2:\PRG\` → SELECT PROG | 量測選單、PHGF、MEMORY、CSV 格式 | 較可救；BIOS 仍可進 SELECT PROG |

我們從 VLB 字串已見：`UPGRADING`、`BOOT DONE`、`CRC error`、`FATAL ERROR`、`LICENSE`、`*.VL7`、`\PRG\`。

**修改 GPS+BLE 可能需動 VLB 或 VL7**——優先 **只研究/改 VL7 副本**；**VLB 最後才碰**。

---

## 2. 黃金規則（絕對）

1. **永遠保留可開機的原始組合**（見 §3 備份）
2. **永遠不要刪 PRG 裡唯一的 `STD V37.VL7`**，直到 V39 或還原流程練熟
3. **改過的檔只放 repo 副本**，檔名加 `_MOD`；**不要**直接覆蓋 `/Volumes/VL_GEO2/`
4. **先練「官方升級 + 還原」**，再考慮自改
5. **電量 ≥ 50% 或插電** 才做 BIOS 升級
6. **先複製 DATA/** 到電腦（含 `DATA.CSV`、設定）

---

## 3. 必做備份清單（已完成部分）

本 repo：`firmware_backup/`

| 檔案 | SHA256（前 16） | 用途 |
|------|-----------------|------|
| `VLGEO2_3190_20260531/STD V37.VL7` | `8b52cbcc1ced24cb` | **還原用主 app** |
| `VLGEO2_3190_20260531/setup.bin` | `5e027084a6484e6a` | 設定還原 |
| `VLGEO2_3190_20260531/DATA.CSV` | 樣本 | 參考 |
| `downloads/VLGEO2_V3.5.VLB` | `493432349f170533` | **官方 BIOS 救磚** |
| `downloads/STD V39.VL7` | `dbef30d6306e69de` | 可選升級/對照 |

**USB 現場再備份一次**（動機器前）：

```bash
TS=$(date +%Y%m%d_%H%M%S)
DEST=tree-project-frontend/test/vlgeo2_ble_analysis/firmware_backup/USB_SNAPSHOT_$TS
mkdir -p "$DEST"
cp -R "/Volumes/VL_GEO2/DATA" "/Volumes/VL_GEO2/PRG" "/Volumes/VL_GEO2/SETTINGS" "$DEST/"
# 若根目錄有 .VLB 也一併 cp
```

---

## 4. 官方復原流程（救磚用）

### 4.1 應用程式壞了 / 進不去 STD

**BIOS 模式**（手冊 §3）：

1. **關機**
2. **按住 SEND + DME**，再開機 → 進 BIOS 選單
3. 選 **SELECT PROG** → 選 **STD V37**（或 PRG 內任一有效 `.VL7`）
4. **START PROG**

若畫面鎖死（§2.1.6）：**同時按 ON + DME + SEND** 重置。

**USB 還原 app**（[Upgrade Bios & Software.pdf](https://haglof.app)）：

1. 開機 → USB → 複製 **`STD V37.VL7`** 到 `VL_GEO2:\PRG\`
2. 拔線 → SETTINGS → SELECT PROG → 選 app → **START**  
   （付費 app 才要 LICENSE；**STD 免費**）

### 4.2 BIOS 升級失敗 / 異常

**官方重刷**（[Vertex Laser Geo 2 Firmware 3.5](https://haglof.app/product/vertex-laser-geo-2-firmware/)）：

1. 開機 → USB → 複製 **`VLGEO2_V3.5.VLB`** 到 **根目錄**（不是 PRG）
2. **拔 USB、關機**
3. **關機狀態按住 SEND**，插入 USB → 開始升級
4. 完成後拔 USB

若出現 `CRC error` / `FATAL ERROR`（VLB 字串）→ **勿刷自改 VLB**；只刷 **haglof.app 下載的原始 V3.5**。

### 4.3 仍無法開機

手冊 §13.1：**聯繫經銷商/原廠維修**（保固外需自費）。  
**不要**連續多次刷未知檔。

---

## 5. 安全研究階段（建議順序）

### 階段 A — 零風險（僅電腦）

- [x] 備份 V37 / V39 / V3.5 VLB
- [x] `COMPARE_V37_V39_VLB.md`、`analyze_vlgeo_firmware.py`
- [ ] `binwalk` / hex diff V37 vs V39（找結構，不刷）
- [ ] 標記 VLB 內 `Reading gps`、`_COM`、`LICENSE` 偏移（grep/strings）

### 階段 B — 官方可逆操作（低風險，在機器上）

**B1. 並存安裝 STD 3.9（不刪 V37）**

1. USB 複製 `STD V39.VL7` → `PRG/`（與 V37 並存）
2. SELECT PROG → 試 V39 → 量測是否正常
3. 隨時 SELECT PROG → 切回 **V37**

**B2. 官方 BIOS 3.5 升級（中風險，但可再用官方 VLB 刷）**

- 升級前：**階段 A 備份 + 電量足**
- 升級後：重測 Classic §4.6.2、BLE PHGF
- 若變差：仍可用同 procedure 再刷一次官方 V3.5

**⚠️ 在 B1/B2 成功、且你親手還原過 V37 之前，禁止刷任何 `_MOD` 檔。**

### 階段 C — 修改副本（仍不刷機）

- 只在 repo 內改 `STD V37_MOD.VL7`（複製後改）
- 檢查：檔尾是否為 `...ee0000` 模式（V37/V39 皆有固定尾段）
- 若 VLB 有 **CRC / LICENSE** 檢查，自改 VL7 可能 **無法通過 OPEN**（需實驗）

### 階段 D — 刷修改檔（高風險，最後）

**僅在滿足全部條件時：**

- [ ] B1/B2 還原已成功至少 2 次
- [ ] 指導老師/單位同意
- [ ] PRG 內保留 **未修改的 V37**
- [ ] 先刷 **VL7 修改版**，**不刷 VLB**
- [ ] 失敗 → SELECT PROG 回 V37

---

## 6. 改什麼較可能達成 GPS + 逐棵？

| 改動目標 | 較可能檔案 | 難度 | 磚機風險 |
|----------|------------|------|----------|
| SEND 時多送 GGA | **VLB**（BLE notify） | 極高 | 高 |
| 打破 MEMORY/BT 互斥 | **VL7** 或 VLB | 高 | 中 |
| PHGF 後附加 CSV 列 | **VL7** | 高 | 低（可切回 V37） |

**務實策略**：先 **VL7 離線逆向** 找 MEMORY 與 BT 互斥的 branch；**VLB 只讀**。

---

## 7. 工具（本 repo）

```bash
# 離線分析
python \
  tree-project-frontend/test/vlgeo2_ble_analysis/analyze_vlgeo_firmware.py

# 可選：binwalk（若已安裝）
# binwalk firmware_backup/downloads/VLGEO2_V3.5.VLB
```

---

## 8. 網路資料索引

| 資源 | URL |
|------|-----|
| 硬體手冊 Rev.1 | [Grube PDF mirror](https://cdn.grube.de/2025/02/14/Manual_Hagloef-Vertex-Laser-Geo2_80-194-02_80-195-02_en_30042024.pdf) |
| BIOS/Software 升級 PDF | `firmware_backup/downloads/Upgrade Bios & Software.pdf` |
| 官方 BIOS 3.5 | [haglof.app](https://haglof.app/product/vertex-laser-geo-2-firmware/) |
| 官方 STD 3.9 | [haglof.app/std](https://haglof.app/product/std/) |
| 3D Pile（含 MEMORY+BT 轉檔說明） | [haglof.app/3d-pile](https://haglof.app/product/3d-pile/) — V2.5 提到 Bluetooth Obex in MEMORY |
| 產品頁（custom app） | [haglofsweden.com](https://haglofsweden.com/project/vertex-laser-geo-2/) |
| 聯絡原廠 | [contact](https://haglofsweden.com/get-in-touch/contact-us/) |

**網上幾乎沒有** Geo2 自改韌體教學或救磚社群帖——安全網只有 **官方 VLB/VL7 + BIOS 模式**。

---

## 9. 研究目標的現實評估

- **能還原**：有（官方 V37 + V3.5 VLB + BIOS SELECT PROG）
- **能保證改成功**：無公開文件、無範例 patch
- **最低風險路徑**：階段 A→B1→C；**階段 D 最後且只改 VL7**

---

## 10. 下一步（建議你同意後再做）

1. **USB 快照備份**（§3 指令）
2. **B1：只加 V39 不刪 V37**，確認 SELECT PROG 可切換
3. **離線 diff** V37/V39 + VLB strings 報告
4. **仍不要刷 `_MOD`**

若 B1 成功，代表 **應用層可逆**；再談改副本。
