# VLGEO2 BLE 協議深度解析

## 一、概述

VLGEO2 (Vertex Laser Geo 2) 是 Haglöf Sweden 製造的專業樹高測量儀器。本文檔基於對實際 BLE 通訊的深度分析，記錄了手機與 VLGEO2 之間的完整通訊協議。

---

## 二、BLE 服務結構

VLGEO2 提供以下 BLE 服務：

### 1. 標準服務
| 服務名稱 | UUID | 說明 |
|---------|------|------|
| Generic Access | `0x1800` | 設備基本資訊 |
| Device Information | `0x180A` | 製造商資訊 |

### 2. 自定義服務 (Haglöf 專有)
| 服務名稱 | UUID | 用途 |
|---------|------|------|
| **Primary Data Service** | `9e000000-f685-4ea5-b58a-85287cb04965` | **主要數據傳輸** |
| Nordic UART Service | `6e400001-b5a3-f393-e0a9-e50e24dcca9e` | 備用 UART |
| Unknown Service 1 | `69465a7c-6ce7-43bf-9549-8ebfde563e0e` | 未知 |
| Unknown Service 2 | `9e020000-f685-4ea5-b58a-85287cb04965` | 未知 |

### 3. 關鍵 Characteristic
| Characteristic | UUID | 屬性 | 說明 |
|----------------|------|------|------|
| **TX (數據輸出)** | `9e010000-f685-4ea5-b58a-85287cb04965` | Notify, Read | VLGEO2 發送數據到手機 |
| RX (命令輸入) | `9e020000...` 或透過 NUS | Write | 手機發送命令到 VLGEO2 |

---

## 三、通訊流程

### 連線與觸發傳輸

```
手機                                    VLGEO2
  |                                       |
  |-------- Connect (BLE) --------------->|
  |<------- Connected --------------------|
  |                                       |
  |-------- Discover Services ----------->|
  |<------- Service List -----------------|
  |                                       |
  |==== 關鍵步驟：啟用 Notifications ====|
  |                                       |
  |-------- Write CCCD (0x0100) --------->|  寫入 Client Characteristic
  |        to 9e010000...                 |  Configuration Descriptor
  |<------- Notifications Enabled --------|
  |                                       |
  |<======= DATA STREAM START ============|  VLGEO2 自動開始發送數據！
  |<------- Notification (20 bytes) ------|
  |<------- Notification (20 bytes) ------|
  |<------- ...                      -----|
  |<------- Notification (3 bytes EOT) ---|  結束訊號
  |                                       |
```

### 關鍵發現：觸發機制

1. **手機不需要發送任何命令來觸發傳輸**
2. 只需要對 TX Characteristic 啟用 Notifications (寫入 CCCD = `0x01 0x00`)
3. VLGEO2 會**自動**開始發送 DATA.CSV 的完整內容

---

## 四、封包結構

### ATT MTU
- 標準 ATT MTU: **20 bytes**
- 這是 BLE 4.0 的默認值，VLGEO2 使用此大小

### 封包類型

| 類型 | 長度 | 識別特徵 | 內容說明 |
|------|------|----------|----------|
| **正常封包** | 20 bytes | 不以 `44 xx 00` 開頭 | 純 CSV 數據 |
| **標記封包** | 20 bytes | 以 `44 xx 00` 開頭 | 前 3 bytes 是標記，後 17 bytes 是數據 |
| **殘留封包** | 5 bytes | 任何內容 | 前 3 bytes 是數據，**後 2 bytes 是雜訊** |
| **結束封包** | 3 bytes | `0x04 0x7C 0x??` | EOT (End of Transmission) |

### 標記封包 (`44 xx 00`) 的來源

這是 **PacketLogger** (BLE 監聽工具) 插入的標記，不是 VLGEO2 原始數據。

常見的標記變體：
- `44 CD 00` - 最常見 (約 99%)
- `44 36 00` - 罕見
- `44 86 00` - 在某些情況下出現

### 5-byte 殘留封包的原因

當 PacketLogger 標記插入時，會打斷正常的 20-byte 封包邊界：

```
原始數據流：[...data...][...data...][...data...]
                        ↓ PacketLogger 插入標記
實際封包：  [...data][3 bytes + 2 bytes padding][44 xx 00 + 17 bytes data]
                     ↑ 5-byte 殘留封包
                     前 3 bytes 是真實數據
                     後 2 bytes 是填充/雜訊
```

---

## 五、數據格式

### CSV 結構
VLGEO2 發送的是標準 CSV 格式，包含 33 個欄位：

```
MARK;STATUS;TYPE;PROD;VER;SNR;ID;UNIT;TRPH;REFH;P.OFF;DECL;LAT;N/S;LON;E/W;
ALTITUDE;HDOP;DATE;UTC;SEQ;AREA;VOL;SD;HD;H;DIA;PITCH;AZ;X(m);Y(m);Z(m);UTM ZONE;
```

### 關鍵欄位索引
| 索引 | 欄位名 | 說明 | 範例 |
|------|--------|------|------|
| 6 | ID | 記錄編號 | `10001` |
| 12 | LAT | 緯度 | `23.9814233` |
| 14 | LON | 經度 | `120.5366472` |
| 19 | UTC | 時間 (HHMMSS) | `143256` |
| 24 | HD | 水平距離 (m) | `4.5` |
| 25 | H | 樹高 (m) | `12.3` |

---

## 六、結束訊號 (EOT)

傳輸結束時，VLGEO2 發送一個 3-byte 的 EOT 訊號：

```
0x04 0x7C 0x??
```

- `0x04` = ASCII EOT (End of Transmission)
- `0x7C` = `|` (管道符號)
- 第三個 byte 可能是校驗碼或序號

**重要**：只有收到 EOT 訊號才表示傳輸成功完成。

---

## 七、正確的解碼演算法

```dart
List<int> decodePacket(List<int> data) {
  final int pktLen = data.length;
  
  if (pktLen == 20) {
    // 20-byte 封包
    if (data[0] == 0x44 && data[2] == 0x00) {
      // 標記封包：跳過前 3 bytes
      return data.sublist(3);
    }
    // 正常封包：保留全部
    return data;
  } else if (pktLen == 5) {
    // 殘留封包：只保留前 3 bytes
    return data.sublist(0, 3);
  } else {
    // 其他：過濾非 ASCII
    return data.where((b) => 
      (b >= 0x20 && b <= 0x7E) || b == 0x0D || b == 0x0A
    ).toList();
  }
}
```

---

## 八、統計數據

### DATA_2.CSV (336 筆記錄)
| 指標 | 數值 |
|------|------|
| 總封包數 | 2,458 |
| 正常 20-byte | 2,008 |
| 5-byte 殘留 | 223 |
| 標記封包 | 224 |
| 其他 | 3 |
| 準確率 | **100%** |

### OLD_DATA (11 筆記錄)
| 指標 | 數值 |
|------|------|
| 總封包數 | 532 |
| 正常 20-byte | 426 |
| 5-byte 殘留 | 46 |
| 標記封包 | 49 |
| 其他 | 11 |
| 準確率 | **100%** |

---

## 九、常見問題 (FAQ)

### Q: 為什麼 iPhone 官方 APP 不會出錯？
A: iPhone 使用的 PacketLogger 標記不同，或者官方 APP 有內建的封包邊界處理邏輯。

### Q: 是否需要發送命令觸發傳輸？
A: **不需要**。只要啟用 TX Characteristic 的 Notifications，VLGEO2 就會自動發送。

### Q: 如何知道傳輸結束？
A: 收到 3-byte 的 EOT 訊號 (`0x04 0x7C ...`)。

### Q: `44 xx 00` 標記是什麼？
A: 這是 PacketLogger/nRF Connect 等 BLE 監聽工具插入的標記，不是 VLGEO2 的原始數據。

---

## 十、參考資料

- **設備**: VLGEO2_ 3190 (MAC: C4:D3:6A:BA:63:7E)
- **製造商**: Haglöf Sweden
- **型號**: GEO2
- **手冊**: Manual_Hagloef-Vertex-Laser-Geo2_80-194-02_80-195-02_en_30042024.pdf (Page 33-34)
