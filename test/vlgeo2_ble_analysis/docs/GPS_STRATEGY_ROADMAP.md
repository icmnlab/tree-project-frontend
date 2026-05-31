# VLGEO2 逐棵 + 儀器 GPS：處理方向（2026-05-31）

> 依 Haglöf 官方手冊、[haglof.app](https://haglof.app)、[Haglöf Link](https://haglof.app/project/haglof-link/)、產品頁與本專案實測整理。

## 核心問題

**能否把「MEMORY 存檔（有 GPS）」改成「一棵 SEND 一棵到 APP」？**

### 手冊結論：**不能原封不動做到**

| 條文 | 內容 |
|------|------|
| §2.1.4 / §4.4.12.1 / §8 | **MEMORY 開 → 不能 IR/Bluetooth 即時傳** |
| §4.4.12 | MEMORY 開 → SEND **寫進 SSD**（`DATA SAVED`），含 ID + GPS |
| §4.4.12.5 | 藍牙匯出 = **SEND FILES** 整檔（BLE），非逐列 |
| §9.3 | MEMORY 關 → BLE SEND = **PHGF/20-byte，無 GPS** |

也就是 Haglöf **刻意二選一**：

```
即時 BT 量測（無 GPS 欄）  ⟷  MEMORY 存檔（有 GPS，無即時 BT）
```

### 官方 App 也沒有「Geo2 逐棵即時串流 + GPS」

[Haglöf Link](https://haglof.app/product/haglof-link/) 對 **Laser Geo / Geo 2** 只列：

- **Receive and share files**（收整檔）
- **沒有** MD II 那種 LINE mode 即時串流

即時串流僅標 Digitech BT / MD II 等卡尺類（[Haglof Link 專案頁](https://haglof.app/project/haglof-link/)）。

---

## 為什麼硬體上「明明有 GPS」卻不能逐棵 BLE 帶座標？

1. **GPS 模組正常** — USB `DATA.CSV` 的 LAT/LON 已證明。  
2. **即時 BLE 封包格式不含座標** — §9.3 只有距離/角度/樹高（20 byte 塞不下 NMEA）。  
3. **含 GPS 的完整列在 STD 的 CSV  writer** — `$;1;1P;...;LAT;...;LON;...`，走 MEMORY 路徑。  
4. **BIOS 負責 Classic NMEA 串流** — §4.6.2，與 BLE PHGF 分層（VLB 有 `Reading gps`、`_COM`）。

不是 GPS 壞，是 **產品把「即時無線」與「含 GPS 存檔」分成兩套韌體邏輯**。

---

## 可行方向（依風險與符合度排序）

### 方向 1 — Classic GPS + BLE 量測（官方 §4.6.2 + §9.3）⭐ 仍首選

- **現場**：仍是一棵一棵 SEND。  
- **APP**：Classic 收 GGA 快取 + BLE 收 PHGF。  
- **硬體**：不改韌體。  
- **阻塞**：Mac Classic 0 byte → **改 Android SPP 驗證**（判斷 Mac vs 儀器）。

### 方向 2 — 實機驗證「MEMORY 開是否仍偷偷送 BLE」（低成本）

手冊說不能，但 worth **一次實驗**：

1. ENABLE MEM = ON  
2. BLE 連線 + 訂閱 NUS  
3. 量測 + SEND  

若 **完全無 notify** → 手冊成立，此路死。  
若有 **CSV 片段或整檔** → 再分析韌體例外（目前無此證據）。

### 方向 3 — MEMORY 妥協流程（有 GPS，非逐棵即時）

| 步驟 | 說明 |
|------|------|
| 場中 | MEM ON，每棵 SEND → 儀器本地存（有 GPS） |
| 場末 | MEMORY → SEND FILES → BLE 收 `DATA.CSV` |
| APP | 解析 CSV 批次入庫 |

**缺點**：不符合「每棵立刻填表單提交」；**優點**：100% 官方、有 GPS。  
[Haglöf Link](https://haglof.app/product/haglof-link/) 官方就是這條路。

**USB 邊量邊監看 DATA.CSV？** §7：插 USB 會進 **USB 磁碟模式**，不適合邊走邊量。

### 方向 4 — 向 Haglöf 訂製應用（官方硬體解法）

[產品頁 §1.3.4](https://haglofsweden.com/project/vertex-laser-geo-2/)：

> 可訂製 custom apps… development and license costs

若學校能走採購/合作，請 Haglöf 做 **「SEND 時 BLE 送 CSV 列或 PHGF+GGA」** 的 `.VL7`，比自行逆向刷機安全。

### 方向 5 — BLE 全 GATT 掃描（方案 2）

確認 GPS 是否藏在未文件化的 characteristic（尚未做）。

### 方向 6 — 逆向 / 自改韌體（最後手段）

- **離線分析 VLB/VL7**：搞清 MEMORY 與 BT 互斥開關在哪（**不刷機**）。  
- **自改刷機**：可能解互斥或改 BLE 封包 → **磚機風險**，不建議在學校主機上試。

---

## 建議執行順序

```
1. Android Classic SPP 測 §4.6.2（1 天）
      ↓ 有 GGA
2. APP 雙通道 POC（Android 先）
      ↓ 仍無 GPS
3. MEMORY+BLE 衝突實驗（半日）
      ↓ 確認手冊
4. BLE 全 GATT 錄包（1 天）
      ↓ 仍無路
5. 決策：Haglöf 訂製 app  OR  接受場末 SEND FILES  OR  備機逆向研究
```

**不建議** 把希望放在「MEMORY 開但逐棵 BLE 送含 GPS 列」— 手冊 + 官方 App 生態都指向 **不行**；除非方向 2 實驗推翻。

---

## 給環境學院溝通用一句話

> VLGEO2 內建 GPS 正常；官方設計是「即時藍牙量測不含座標，含座標請用 Classic GPS 串流或 MEMORY 存檔後整檔匯出」。  
> 我們要達成「逐棵 + 儀器 GPS」，最符合官方的是 **Classic+BLE 雙通道**；若 Classic 在此環境不可用，需 **Haglöf 訂製韌體/應用** 或接受 **場末匯出**。
