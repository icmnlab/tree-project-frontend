# 换电脑开发交接（2026-05）

> **Repo**：https://github.com/<GITHUB_OWNER>/tree-project-frontend  
> **Clone**：`git clone https://github.com/<GITHUB_OWNER>/tree-project-frontend.git`  
> **主分支**：`main`（与 GitHub 同步后再开发）

---

## 一、30 秒摘要

逐棵量树用 **VLGEO2 BLE（PHGF）**；GPS 改 **LG290P + ESP32（TreeGNSS BLE）→ 手机 APP**。  
Geo2 BLE 逐棵 **无 GPS**；外接 GNSS **standalone ~0.7 m**，优于 Geo2 **~2.5 m**。  
**APP 外接 GNSS 尚未实作**；**ESP32 TreeGNSS 固件尚未实作**。

---

## 二、新电脑环境

### Flutter APP

```bash
cd tree-project-frontend
flutter pub get
flutter doctor
# Android 实机优先测双 BLE
flutter run
```

- 需 Flutter SDK、Android Studio / Xcode（若测 iOS）
- 环境变量、Firebase/API 若有 `.env` 或本地密钥，**不在 repo**——向 Kyle 索取或对照旧电脑

### ESP32 固件（待建）

- Arduino IDE 或 PlatformIO
- 板子：**ESP32-C3-Zero**（见下方「已购硬件」确认是否带排针）
- Arduino：安装 esp32 包，板型选 **ESP32C3 Dev Module**，开启 **USB CDC On Boot**
- 烧录：按住 **BOOT** 再插 Type-C

### 桌测 LG290P（可选）

- Windows/Mac 装 [CH343 驱动](https://www.waveshare.net/wiki/LG290P_GNSS_RTK_Module) + 移远 **QGNSS**
- Type-C 接 LG290P，天线放窗边

---

## 三、已购硬件（2026-05 微雪下单）

| 品项 | 订单情况 | 注意 |
|------|----------|------|
| **LG290P GNSS RTK Module** | 已买 **¥525.5** | 版本：**不带 RTC 电池**（非 RTK 能力缺失）；RTK/GNSS 与电池版相同 |
| **ESP32-C3 开发板** | 已买 **¥20.79** | **请核对**：低价多为 **贴片版（无排针）**；理想为 **ESP32-C3-Zero-M 带排针** SKU 25532 |

**RTC 电池（ML1220）**：未附。可选补买插 JST → 缩短断电后再定位等待（**不影响精度**）。  
**接线**：LG290P SH1.0 线 → 母杜邦 → ESP32 **RX(GPIO20)** + **GND**；双 Type-C 各接 5V 电源。  
**不必面包板**；详见 [`HANDOFF_外接GNSS現場量測.md`](HANDOFF_外接GNSS現場量測.md)。

---

## 四、文档索引（按阅读顺序）

| 文件 | 用途 |
|------|------|
| **本文** | 换机、clone、环境、待办 |
| [`HANDOFF_外接GNSS現場量測.md`](HANDOFF_外接GNSS現場量測.md) | 精简方案、采购、整合保证 |
| [`HANDOFF_EXTERNAL_GNSS_AND_BLE.md`](HANDOFF_EXTERNAL_GNSS_AND_BLE.md) | 完整规格、UUID、VLGEO2 对比、台湾 RTK |
| `test/vlgeo2_ble_analysis/docs/VLGEO2_GPS_SOLUTION.md` | Geo2 GPS 实测结论 |
| `test/Tree_app_equipment_info/VLGEO2_BLE_PROTOCOL.md` | PHGF / BLE 协议 |

---

## 五、程式现状与待办

### 已完成

- `ble_live_packet_decoder.dart`：PHGF 连续多棵重组 **已修**
- `ble_live_session_page.dart`：Geo2 NUS BLE 现场量测流程
- 交接 / 采购 / 对比文档

### 待做（建议顺序）

1. **`firmware/treegnss_ble_nus/`**  
   - 设备名 `TreeGNSS`  
   - UART **460800** 读 LG290P TXD3 → BLE NUS 转发 NMEA  
   - NUS UUID 与 Geo2 相同（见 `HANDOFF_EXTERNAL_GNSS_AND_BLE.md`）

2. **`lib/services/external_gnss_service.dart`**  
   - 第二路 BLE 连 TreeGNSS  
   - 解析 `$GNGGA` / `$GNGSA` → `latestFix`

3. **`field_session_setup.dart`**：`gpsSource` 加 **`external_gnss`**

4. **`ble_live_session_page.dart`**：`_resolveGpsForLiveMeasurement` 读外接 fix，不再默认手机 GPS

5. **到货验收**：QGNSS 型号 LG290P → nRF Connect 见 `$GNGGA` → APP 双 BLE 实机

### 关键代码入口

```
lib/screens/ble_live_session_page.dart   ← _resolveGpsForLiveMeasurement
lib/widgets/field/field_session_setup.dart
lib/utils/field_gps_capture.dart         ← 现手机 GPS
```

---

## 六、架构（不变）

```
VLGEO2  ──BLE PHGF──→  手机 APP
TreeGNSS (LG290P+ESP32) ──BLE NMEA──→  手机 APP
```

- Geo2 **不能**对外供电；外挂自备 5V 行动电源（~220 mA）
- 3D 打印盒 + Geo2 底 **1/4"-20**；天线垂直朝天

---

## 七、台湾 GNSS / RTK（群组说明用）

| 模式 | 要不要付费 | 精度 |
|------|------------|------|
| **Standalone（现阶段）** | 否 | ~0.7 m，优于 Geo2 |
| **RTK** | 是（e-GNSS 等） | cm 级；需 NTRIP + 网络 + 额外固件 |

Geo2 **硬件无 RTK**；LG290P 有 RTK 能力但 **本次不必开服务**。

---

## 八、仪器

- 型号：**VLGEO2_3190**，STD V3.7 / 可装 `test/vlgeo2_ble_analysis/firmware_backup/installable/STD V39.VL7`
- MEMORY 关 + BLE SEND：有 PHGF、**无 GPS**
- 备选：MEMORY ON + CSV GPS（~2.5 m，零外掛）

---

## 九、联系上下文

- 全项目预算约 NT$14,700；外掛硬件约 ¥550 + 自备电源线
- 需与指导老师确认：外接 GNSS 坐标入库是否合规
- 旧对话可参考 Cursor agent transcript（Kyle 本机）；**以 repo 文档与 `main` 为准**
