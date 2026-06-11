#!/usr/bin/env python3
"""
VLGEO2 電腦端 GPS 驗證（依 Haglöf 硬體手冊 Rev.1 2024-04-30）

目的：在寫進 APP 之前，確認「逐棵 SEND（MEMORY 關）」時儀器是否送出 GPS。

手冊重點：
  - §9.2 / §9.3：量測封包（PHGF 或 20-byte）不含 GPS 座標
  - §4.6.2：USE GPS 開 + EXTERN.GPS 關 → 儀器可作外部 GPS，送 GGA/RMC 等（§10）
  - §4.4.12 + §4.5：MEMORY 開 → 無法 Bluetooth 即時傳；GPS+ID 存於 DATA.CSV（§7）

用法：
  1. 儀器：BLUETOOTH=ON, USE GPS=ON, ENABLE MEM=OFF（現場逐棵模式）
  2. Mac 藍牙開啟，VLGEO2 在範圍內
  3. 執行：
       python verify_vlgeo2_gps_ble.py
  4. 連線成功後，在儀器上量測並按 SEND（可連續多棵）
  5. Ctrl+C 結束，查看摘要與 log 檔

可選：檢查 USB 匯出的 DATA.CSV 是否含 LAT/LON
       python verify_vlgeo2_gps_ble.py --csv /Volumes/VL_GEO2/DATA/DATA.CSV
"""

from __future__ import annotations

import argparse
import asyncio
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

from bleak import BleakClient, BleakScanner

# Haglöf GATT（手冊 §9.3）
HAGLOF_SERVICE = "9e000000-f685-4ea5-b58a-85287cb04965"
HAGLOF_TX = "9e010000-f685-4ea5-b58a-85287cb04965"

# Nordic UART（部分韌體/批次匯出亦使用）
NUS_SERVICE = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
NUS_TX = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

GPS_PREFIXES = ("$GPGGA", "$GNGGA", "$GLGGA", "$GAGGA", "$GPGLL", "$GNGLL",
                "$GPRMC", "$GNRMC", "$GPVTG", "$GNVTG", "$GPGSA", "$GNGSA",
                "$GPGSV", "$GNGSV")

MEASUREMENT_PREFIXES = ("$PHGF",)

PHGF_SENTENCE_RE = re.compile(r"\$PHGF,HVV,[^*]+\*[0-9A-Fa-f]{2}")
GGA_SENTENCE_RE = re.compile(
    r"\$(?:GP|GN|GL|GA)GGA,[^*]+\*[0-9A-Fa-f]{2}"
)
RMC_SENTENCE_RE = re.compile(
    r"\$(?:GP|GN)RMC,[^*]+\*[0-9A-Fa-f]{2}"
)


@dataclass
class SessionStats:
    started: datetime = field(default_factory=datetime.now)
    notify_chunks: int = 0
    notify_bytes: int = 0
    phgf_lines: list[str] = field(default_factory=list)
    gps_lines: list[str] = field(default_factory=list)
    other_lines: list[str] = field(default_factory=list)
    last_gga: dict | None = None
    phgf_with_prior_gga: list[dict] = field(default_factory=list)

    def summary_lines(self) -> list[str]:
        lines = [
            "",
            "=" * 72,
            " 驗證摘要（依手冊解讀）",
            "=" * 72,
            f"  開始時間: {self.started.isoformat(timespec='seconds')}",
            f"  BLE 分片: {self.notify_chunks} 次, {self.notify_bytes} bytes",
            f"  PHGF 量測句: {len(self.phgf_lines)}",
            f"  GPS NMEA 句: {len(self.gps_lines)}",
            f"  其他文字行: {len(self.other_lines)}",
            "",
        ]

        if self.phgf_lines and not self.gps_lines:
            lines += [
                "  結論 A: 收到 PHGF，但整段連線期間沒有任何 GGA/RMC 等 GPS 句。",
                "          → 依 §9.2，PHGF 本身不含 GPS；若也無 §4.6.2 GPS 串流，",
                "            逐棵 SEND 模式下 APP 無法從 BLE 取得儀器座標。",
            ]
        elif self.phgf_lines and self.gps_lines:
            paired = len(self.phgf_with_prior_gga)
            lines += [
                "  結論 B: 同時收到 PHGF 與 GPS NMEA（符合 §4.6.2 外部 GPS 模式假設）。",
                f"          每次 SEND 前已有 GGA 快照: {paired}/{len(self.phgf_lines)} 次",
                "          → APP 可在收到 PHGF 時配對「最新一筆儀器 GGA/RMC」。",
            ]
            if self.last_gga:
                lines.append(
                    f"          最後 GGA: lat={self.last_gga.get('lat')} "
                    f"lon={self.last_gga.get('lon')} fix={self.last_gga.get('fix')}"
                )
        elif not self.phgf_lines and self.gps_lines:
            lines += [
                "  結論 C: 有 GPS 串流但尚未收到 PHGF。",
                "          請在儀器上完成量測並按 SEND，再觀察是否出現 $PHGF,HVV,...",
            ]
        else:
            lines += [
                "  結論 D: 尚未收到 PHGF 或 GPS。",
                "          請確認 BLUETOOTH 已開；逐棵模式需 MEMORY 關並按 SEND。",
            ]

        lines.append("=" * 72)
        return lines


class NmeaAssembler:
    """累積 BLE notify；支援 §9.3 前綴 + PHGF 無換行（第二棵 SEND 實機格式）。"""

    def __init__(self) -> None:
        self._buf = ""
        self._last_phgf_end = 0

    def feed(self, data: bytes) -> tuple[list[str], list[str]]:
        if not data:
            return [], []
        chunk = "".join(
            chr(b) for b in data
            if b in (0x0D, 0x0A) or 0x20 <= b <= 0x7E
        )
        if not chunk:
            return [], []

        self._buf += chunk
        text = self._buf

        phgf_lines: list[str] = []
        for m in PHGF_SENTENCE_RE.finditer(text):
            if m.end() <= self._last_phgf_end:
                continue
            phgf_lines.append(m.group(0))
            self._last_phgf_end = m.end()

        if self._last_phgf_end > 0:
            self._buf = text[self._last_phgf_end :]
            self._last_phgf_end = 0
        elif len(self._buf) > 512:
            self._buf = self._buf[-256:]

        gps_lines: list[str] = []
        for regex in (GGA_SENTENCE_RE, RMC_SENTENCE_RE):
            for m in regex.finditer(text):
                line = m.group(0)
                if line not in gps_lines:
                    gps_lines.append(line)

        if "\n" in chunk or "\r" in chunk:
            for line in re.split(r"\r?\n", chunk):
                line = line.strip()
                if not line:
                    continue
                if line.startswith("$PHGF") and line not in phgf_lines:
                    phgf_lines.append(line)
                elif any(line.startswith(p) for p in GPS_PREFIXES):
                    if line not in gps_lines:
                        gps_lines.append(line)

        return phgf_lines, gps_lines

    @property
    def buffer_tail(self) -> str:
        return self._buf


def parse_gga(line: str) -> dict | None:
    """解析 GGA 取得 lat/lon/fix（WGS84，手冊 §10）。"""
    if not any(line.startswith(p) for p in ("$GPGGA", "$GNGGA", "$GLGGA", "$GAGGA")):
        return None
    fields = line.split(",")
    if len(fields) < 10:
        return None
    try:
        fix = int(fields[6] or "0")
    except ValueError:
        fix = 0
    lat_raw, lat_hemi = fields[2], fields[3]
    lon_raw, lon_hemi = fields[4], fields[5]
    if not lat_raw or not lon_raw:
        return {"fix": fix, "lat": None, "lon": None, "raw": line}

    def dm_to_deg(raw: str, hemi: str) -> float:
        # ddmm.mmmm
        dot = raw.index(".")
        deg = int(raw[: dot - 2])
        minutes = float(raw[dot - 2 :])
        val = deg + minutes / 60.0
        if hemi in ("S", "W"):
            val = -val
        return val

    return {
        "fix": fix,
        "lat": dm_to_deg(lat_raw, lat_hemi),
        "lon": dm_to_deg(lon_raw, lon_hemi),
        "hdop": fields[8] if len(fields) > 8 else "",
        "raw": line,
    }


def parse_phgf(line: str) -> dict | None:
    if not line.startswith("$PHGF"):
        return None
    parts = line.split(",")
    if len(parts) < 12:
        return None
    out = {
        "hd": parts[2],
        "az": parts[4],
        "pitch": parts[6],
        "sd": parts[8],
        "height": parts[10],
        "raw": line,
    }
    if len(parts) > 13:
        out["remote_diameter"] = f"{parts[12]} {parts[13]}"
    return out


def classify_line(line: str) -> str:
    upper = line.upper()
    if upper.startswith(MEASUREMENT_PREFIXES):
        return "phgf"
    if any(upper.startswith(p) for p in GPS_PREFIXES):
        return "gps"
    if upper.startswith("$"):
        return "other_nmea"
    if ";" in line and (line.startswith("$") or line.startswith("#")):
        return "csv"
    return "text"


def check_csv_gps(csv_path: Path) -> None:
    """檢查 USB 匯出 DATA.CSV 的 LAT/LON（手冊 §7，MEMORY+GPS 存檔模式）。"""
    print(f"\n檢查 CSV: {csv_path}")
    if not csv_path.is_file():
        print("  檔案不存在")
        return

    text = csv_path.read_text(encoding="utf-8", errors="replace")
    lines = [ln.strip() for ln in text.splitlines() if ln.strip().startswith("$")]
    with_gps = 0
    without_gps = 0
    samples: list[str] = []

    for ln in lines:
        fields = ln.split(";")
        # 依專案 golden CSV：index 12=LAT, 14=LON（0-based 在 split 後需對照 header）
        lat = fields[12] if len(fields) > 12 else ""
        lon = fields[14] if len(fields) > 14 else ""
        if lat and lon and re.search(r"\d", lat) and re.search(r"\d", lon):
            with_gps += 1
            if len(samples) < 3:
                rec_id = fields[6] if len(fields) > 6 else "?"
                samples.append(f"    ID={rec_id} LAT={lat} LON={lon}")
        else:
            without_gps += 1

    print(f"  資料列: {len(lines)}（$ 開頭）")
    print(f"  含 LAT/LON: {with_gps}")
    print(f"  無 GPS: {without_gps}")
    if samples:
        print("  範例:")
        for s in samples:
            print(s)
    print(
        "\n  說明: CSV 含 GPS 通常表示 MEMORY 開且量測時 USE GPS 開（§4.4.12）。"
        "\n        這與 MEMORY 關的逐棵 BLE SEND 是不同模式。"
    )


HAGLOF_SVC_SHORT = "9e000000-f685-4ea5-b58a-85287cb04965"


@dataclass
class ScanEntry:
    """對齊 APP [BleDeviceScanner]：platformName + RSSI + 廣播名。"""
    device: object
    display_name: str
    rssi: int
    service_uuids: list[str]

    @property
    def address(self) -> str:
        return self.device.address


def _entry_display_name(device, advertisement_data) -> str:
    # Windows 上 device.name 常為空；APP 用 platformName（來自廣播 local_name）
    name = (device.name or getattr(advertisement_data, "local_name", None) or "").strip()
    return name or "未知裝置"


def _is_vlgeo_candidate(entry: ScanEntry) -> bool:
    n = entry.display_name.upper()
    if "VLGEO" in n or "HAGLOF" in n:
        return True
    uuids = {u.lower() for u in entry.service_uuids}
    if HAGLOF_SVC_SHORT in uuids:
        return True
    return False


async def scan_like_app(timeout: float = 15.0) -> list[ScanEntry]:
    """與 APP 相同：掃描 15s、累積 scanResults、依 RSSI 排序。"""
    entries: dict[str, ScanEntry] = {}

    def detection_callback(device, advertisement_data):
        name = _entry_display_name(device, advertisement_data)
        rssi = getattr(advertisement_data, "rssi", None)
        if rssi is None:
            rssi = -999
        uuids = list(getattr(advertisement_data, "service_uuids", []) or [])
        entries[device.address] = ScanEntry(
            device=device,
            display_name=name,
            rssi=int(rssi),
            service_uuids=uuids,
        )

    scanner = BleakScanner(detection_callback=detection_callback)
    print(f"掃描 BLE 裝置 {timeout:.0f}s（同 APP BleDeviceScanner）…")
    await scanner.start()
    await asyncio.sleep(timeout)
    await scanner.stop()
    return sorted(entries.values(), key=lambda e: e.rssi, reverse=True)


def _print_scan_list(title: str, items: list[ScanEntry]) -> None:
    print(f"\n{title}（{len(items)}）")
    if not items:
        print("  （無）")
        return
    for i, e in enumerate(items):
        print(f"  [{i}] {e.display_name}  {e.address}  RSSI {e.rssi}")


async def find_vlgeo2(
    timeout: float = 15.0,
    *,
    address: str | None = None,
    pick_index: int | None = None,
) -> object | None:
    if address:
        print(f"略過掃描，直接連線（--address）: {address}")
        # BleakClient 接受 address 字串；建立輕量 device 物件
        class _AddrOnly:
            def __init__(self, addr: str):
                self.address = addr
                self.name = addr

        return _AddrOnly(address.strip())

    all_entries = await scan_like_app(timeout)
    candidates = [e for e in all_entries if _is_vlgeo_candidate(e)]

    _print_scan_list("VLGEO / HAGLÖF 候選（APP 篩選 VLGEO|HAGLOF）", candidates)
    if not candidates and all_entries:
        _print_scan_list(
            "未符合名稱篩選；完整掃描列表（可從 APP 複製 MAC 用 --address）",
            all_entries[:20],
        )

    if not candidates:
        print(
            "\n未找到 VLGEO2。"
            "請確認儀器藍牙已開；若 APP 看得到，請在 APP 點裝置複製 MAC，"
            "再執行: --address XX:XX:XX:XX:XX:XX"
        )
        return None

    if pick_index is not None:
        idx = pick_index
    elif len(candidates) == 1:
        idx = 0
    else:
        print("\n找到多個候選，請選序號（與 APP 列表相同）：")
        choice = input("序號 [0]: ").strip() or "0"
        idx = int(choice)

    chosen = candidates[idx]
    print(f"\n已選: {chosen.display_name}  {chosen.address}  RSSI {chosen.rssi}")
    return chosen.device


@dataclass
class LiveSessionSim:
    """對齊 ble_live_session_page：_liveSeq + _isProcessingTree。"""

    is_processing: bool = False
    live_seq: int = 0

    def accept_phgf(self, info: dict | None, raw_line: str) -> bool:
        if self.is_processing:
            print("  ⚠ 上一棵尚未處理完（_isProcessingTree）— 本封包略過")
            return False
        self.is_processing = True
        self.live_seq += 1
        n = self.live_seq
        print(f"\n>>> 第 {n} 棵 · APP 流程模擬")
        if info:
            print(
                f"    #${n} NMEA H={info.get('height')} HD={info.get('hd')} "
                f"SD={info.get('sd')} AZ={info.get('az')} pitch={info.get('pitch')}"
            )
        print(f"    raw: {raw_line}")
        # 實機 APP 會等 GPS+表單；監聽模式立即解鎖以驗證「第二棵 SEND」
        self.is_processing = False
        print(f"    → 第 {n} 棵可繼續（已解鎖，請再按 SEND 測第二棵）")
        return True


async def run_ble_monitor(
    duration: float | None,
    log_path: Path,
    *,
    verbose: bool = False,
    both_channels: bool = False,
    tx: str = "auto",
    ble_address: str | None = None,
    pick_index: int | None = None,
    scan_timeout: float = 15.0,
) -> SessionStats:
    device = await find_vlgeo2(
        scan_timeout,
        address=ble_address,
        pick_index=pick_index,
    )
    if not device:
        sys.exit(1)

    stats = SessionStats()
    assembler = NmeaAssembler()
    live_sim = LiveSessionSim()
    last_notify_at = datetime.now()
    log_file = log_path.open("w", encoding="utf-8")
    raw_log = log_path.with_suffix(".hex.log").open("w", encoding="utf-8")
    log_file.write(f"# VLGEO2 GPS verify session {stats.started.isoformat()}\n")
    log_file.write(f"# device={device.name} address={device.address}\n\n")
    raw_log.write("# raw notify hex\n")

    def on_phgf(source: str, line: str) -> None:
        kind = "phgf"
        ts = datetime.now().strftime("%H:%M:%S")
        log_file.write(f"[{ts}] [{source}] [{kind}] {line}\n")
        log_file.flush()

        stats.phgf_lines.append(line)
        info = parse_phgf(line)
        snap = stats.last_gga
        if snap and snap.get("lat") is not None:
            stats.phgf_with_prior_gga.append({"phgf": info, "gga": snap})
        live_sim.accept_phgf(info, line)
        if snap:
            print(f"    （儀器 GGA 快照 fix={snap.get('fix')} — APP 現場改用手機 GPS）")
        else:
            print("    （無儀器 GGA；與現行 APP 一致，現場用手機 GPS）")

    def on_gps_line(source: str, line: str) -> None:
        ts = datetime.now().strftime("%H:%M:%S")
        log_file.write(f"[{ts}] [{source}] [gps] {line}\n")
        log_file.flush()
        stats.gps_lines.append(line)
        gga = parse_gga(line)
        if gga:
            stats.last_gga = gga
            if gga.get("lat") is not None:
                print(f"[GPS GGA] fix={gga['fix']} lat={gga['lat']:.6f} "
                      f"lon={gga['lon']:.6f}")
            else:
                print(f"[GPS GGA] fix={gga['fix']} (無座標)")
        else:
            print(f"[GPS] {line.split(',', 1)[0]}")

    def make_handler(source: str):
        def handler(_sender, data: bytearray) -> None:
            nonlocal last_notify_at
            last_notify_at = datetime.now()
            stats.notify_chunks += 1
            stats.notify_bytes += len(data)
            raw = bytes(data)
            ts = datetime.now().strftime("%H:%M:%S")
            raw_log.write(f"[{ts}] [{source}] {raw.hex()}\n")
            raw_log.flush()

            if verbose:
                preview = raw.decode("ascii", errors="replace")
                print(f"[RX {source}] {len(raw)}B {preview[:70]!r}")

            phgf_lines, gps_lines = assembler.feed(raw)
            for line in phgf_lines:
                on_phgf(source, line)
            for line in gps_lines:
                on_gps_line(source, line)

            # 對齊 APP：無完整 PHGF 時印分片預覽
            if not phgf_lines and any(b in raw for b in (0x24, 0x2C)):
                preview = raw.decode("ascii", errors="replace")
                preview = "".join(c for c in preview if c.isprintable())
                if preview:
                    print(f"分片 ({len(raw)}B): {preview[:120]}")

            if verbose and not phgf_lines and not gps_lines and raw:
                tail = assembler.buffer_tail
                if tail:
                    print(f"    緩衝尾: {tail[:80]!r}")
        return handler

    async def heartbeat() -> None:
        while True:
            await asyncio.sleep(5)
            idle = (datetime.now() - last_notify_at).total_seconds()
            print(
                f"[心跳] notify={stats.notify_chunks} PHGF={len(stats.phgf_lines)} "
                f"GPS={len(stats.gps_lines)} 距上次 RX {idle:.0f}s "
                f"緩衝={len(assembler.buffer_tail)}B"
            )

    print(f"\n連線: {device.name} ({device.address})")
    print("\n儀器設定請確認（手冊）：")
    print("  • SETTINGS → BLUETOOTH = ON")
    print("  • SETTINGS → GPS → USE GPS = ON，EXTERN.GPS = OFF  （§4.6.2）")
    print("  • SETTINGS → MEMORY → ENABLE MEM = OFF               （§4.5 逐棵 SEND）")
    print("\n連線後請在儀器上量測并按 SEND。Ctrl+C 結束。")
    print("（第二棵起可能為 §9.3 前綴+PHGF 無換行，腳本已支援 regex 擷取）\n")

    # Windows：掃描結束後僅用 MAC 字串常連不上；須傳 BLEDevice 物件或立即重找
    connect_target = device
    if not hasattr(device, "address") or type(device).__name__ == "_AddrOnly":
        connect_target = await BleakScanner.find_device_by_address(
            device.address, timeout=10.0
        )
        if connect_target is None:
            raise RuntimeError(
                f"無法連線 {device.address}：掃描快取已過期，請再執行一次讓腳本重新掃描"
            )

    async with BleakClient(connect_target, timeout=20.0) as client:
        print(f"已連線: {client.is_connected}")
        services = client.services
        subscribed = []

        # 與 APP 相同：優先只訂閱一個 TX，避免重複 notify
        tx_candidates = [
            ("Haglof TX", HAGLOF_TX),
            ("NUS TX", NUS_TX),
        ]
        char_uuids = {
            c.uuid.lower() for s in services for c in s.characteristics
        }

        if both_channels:
            to_sub = tx_candidates
        elif tx == "nus":
            to_sub = tx_candidates[1:]
        elif tx == "haglof":
            to_sub = tx_candidates[:1]
        else:
            to_sub = (
                tx_candidates
                if HAGLOF_TX.lower() in char_uuids
                else tx_candidates[1:]
            )

        for label, uuid in to_sub:
            if uuid.lower() in char_uuids:
                await client.start_notify(uuid, make_handler(label))
                subscribed.append(label)
                print(f"  已訂閱 {label} ({uuid})")

        if not subscribed:
            print("  ⚠ 找不到 Haglof/NUS TX，列出服務：")
            for s in services:
                print(f"    service {s.uuid}")
                for c in s.characteristics:
                    print(f"      char {c.uuid} props={c.properties}")

        hb_task = asyncio.create_task(heartbeat())
        try:
            if duration:
                await asyncio.sleep(duration)
            else:
                while True:
                    await asyncio.sleep(1)
        except asyncio.CancelledError:
            pass
        finally:
            hb_task.cancel()

    log_file.close()
    raw_log.close()
    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description="VLGEO2 BLE GPS 驗證（電腦端）")
    parser.add_argument(
        "--csv",
        type=Path,
        help="可選：檢查 USB 匯出 DATA.CSV 是否含 LAT/LON",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=None,
        help="監聽秒數（預設無限，Ctrl+C 結束）",
    )
    parser.add_argument(
        "--ble",
        action="store_true",
        help="明確執行 BLE 監聽（僅 --csv 時可省略 BLE）",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="印出每個 BLE 分片與緩衝狀態",
    )
    parser.add_argument(
        "--both-channels",
        action="store_true",
        help="同時訂閱 Haglof + NUS（預設只訂閱一個，與 APP 相同）",
    )
    parser.add_argument(
        "--tx",
        choices=("auto", "haglof", "nus"),
        default="auto",
        help="訂閱哪個 TX（auto=Haglof 優先，實機數據常在 NUS 時用 --tx nus）",
    )
    parser.add_argument(
        "--log-dir",
        type=Path,
        default=Path(__file__).parent / "raw_captures",
        help="log 輸出目錄",
    )
    parser.add_argument(
        "--address",
        type=str,
        default=None,
        help="直接連線 MAC（APP 藍牙頁裝置列 subtitle 上的位址）",
    )
    parser.add_argument(
        "--pick",
        type=int,
        default=None,
        help="掃描後自動選第 N 個 VLGEO 候選（0-based）",
    )
    parser.add_argument(
        "--scan-timeout",
        type=float,
        default=15.0,
        help="掃描秒數（APP 預設 15）",
    )
    args = parser.parse_args()

    if args.csv:
        check_csv_gps(args.csv)
        if not args.ble and args.duration is None:
            return

    print("\n" + "=" * 72)
    print(" VLGEO2 電腦端 GPS 驗證")
    print(" 依 Haglöf 硬體手冊 §4.5 / §4.6 / §9 / §10")
    print("=" * 72)

    if sys.platform == "darwin":
        print("\nMac 提示: 若掃描不到裝置，請到「系統設定 → 隱私權 → 藍牙」")
        print("          允許 Terminal / Cursor 使用藍牙。\n")

    args.log_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path = args.log_dir / f"gps_verify_{stamp}.log"

    try:
        stats = asyncio.run(
            run_ble_monitor(
                args.duration,
                log_path,
                verbose=args.verbose,
                both_channels=args.both_channels,
                tx=args.tx,
                ble_address=args.address,
                pick_index=args.pick,
                scan_timeout=args.scan_timeout,
            )
        )
    except KeyboardInterrupt:
        print("\n\n使用者中斷。")
        sys.exit(0)

    for line in stats.summary_lines():
        print(line)
    print(f"\n完整 log: {log_path}")

    summary_path = log_path.with_suffix(".summary.txt")
    summary_path.write_text("\n".join(stats.summary_lines()), encoding="utf-8")
    print(f"摘要檔: {summary_path}")


if __name__ == "__main__":
    main()
