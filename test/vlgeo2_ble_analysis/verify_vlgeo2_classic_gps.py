#!/usr/bin/env python3
"""
VLGEO2 Classic 藍牙（SPP）GPS 驗證 — 方案 1 研究用

手冊 §4.5：Classic 名稱 VLGEO2_XXXXX_COM，PIN 1234
手冊 §4.6.2：USE GPS 開 + EXTERN.GPS 關 → 連外部裝置後送 GGA/RMC

Mac：
  1. 系統設定 → 藍牙 → 配對 VLGEO2_3190_COM（PIN 1234）
  2. 手機 APP 完全斷開 BLE
  3. 儀器：BLUETOOTH=ON, USE GPS=ON, EXTERN.GPS=OFF, ENABLE MEM=OFF
  4. python verify_vlgeo2_classic_gps.py --diag

成功判準：收到 [GPS #n] $GNGGA / $GNRMC（無 fix 時也可能有空欄位 GGA）
"""

from __future__ import annotations

import argparse
import glob
import re
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    print("請安裝 pyserial: pip install pyserial")
    sys.exit(1)

GPS_LINE = re.compile(
    r"\$(?:GP|GN|GL|GA)(?:GGA|RMC|GLL|VTG|GSA|GSV),",
)
DEFAULT_BAUDS = (9600, 115200, 38400, 57600, 4800)


def find_vlgeo_ports() -> list[str]:
    hits: list[str] = []
    for p in list_ports.comports():
        name = (p.device or "") + (p.description or "") + (p.manufacturer or "")
        if re.search(r"VLGEO|HAGLOF|3190|Geo|_COM", name, re.I):
            hits.append(p.device)
    for pattern in ("/dev/cu.VLGEO*", "/dev/tty.VLGEO*", "/dev/cu.*COM*"):
        hits.extend(glob.glob(pattern))
    seen: set[str] = set()
    out: list[str] = []
    for d in hits:
        if d not in seen:
            seen.add(d)
            out.append(d)
    return out


def print_checklist() -> None:
    print(
        """
=== 方案 1：Classic GPS 測試前檢查 ===
儀器
  [ ] BLUETOOTH = ON
  [ ] USE GPS = ON，EXTERN.GPS = OFF
  [ ] ENABLE MEM = OFF
  [ ] 手機 APP 已斷開 BLE（VLGEO2_3190，非 _COM）
Mac
  [ ] 已配對 VLGEO2_XXXXX_COM，PIN 1234
  [ ] 測試期間不要用其他程式佔用 COM
預期
  [ ] 有 fix 時：持續 GGA/RMC
  [ ] 無 fix 時：仍可能收到空欄位 GGA（fix quality 0）
  [ ] 若全程 0 byte → SPP 鏈路未建立，非「沒衛星」
"""
    )


def process_buffer(
    buf: str,
    *,
    gps_count: int,
    phgf_count: int,
    nmea_other: int,
    verbose: bool,
    log_fp,
) -> tuple[str, int, int, int]:
    while "\n" in buf or "\r" in buf:
        for sep in ("\r\n", "\n", "\r"):
            if sep in buf:
                line, buf = buf.split(sep, 1)
                line = line.strip()
                break
        else:
            break
        if not line:
            continue
        if log_fp:
            log_fp.write(line + "\n")
        if line.startswith("$PHGF"):
            phgf_count += 1
            print(f"[PHGF #{phgf_count}] {line[:100]}")
        elif GPS_LINE.match(line):
            gps_count += 1
            print(f"[GPS #{gps_count}] {line[:120]}")
        elif line.startswith("$"):
            nmea_other += 1
            if verbose:
                print(f"[NMEA] {line[:100]}")
    return buf, gps_count, phgf_count, nmea_other


def listen_once(
    port: str,
    baud: int,
    duration: float,
    *,
    dtr: bool | None = None,
    rts: bool | None = None,
    probe: bytes | None = None,
    verbose: bool = False,
    log_fp=None,
    label: str = "",
) -> tuple[int, int, int, int]:
    """回傳 (total_bytes, gps, phgf, other_nmea)"""
    total_bytes = 0
    gps_count = phgf_count = nmea_other = 0
    buf = ""

    kwargs: dict = {
        "port": port,
        "baudrate": baud,
        "timeout": 0.3,
        "bytesize": serial.EIGHTBITS,
        "parity": serial.PARITY_NONE,
        "stopbits": serial.STOPBITS_ONE,
    }
    prefix = f"[{label}] " if label else ""
    print(f"{prefix}開啟 {port} @ {baud} DTR={dtr} RTS={rts} …")

    with serial.Serial(**kwargs) as ser:
        if dtr is not None:
            ser.dtr = dtr
        if rts is not None:
            ser.rts = rts
        ser.reset_input_buffer()
        if probe:
            ser.write(probe)
            ser.flush()
            if verbose:
                print(f"{prefix}已送出 probe {len(probe)} bytes: {probe[:32]!r}")

        deadline = time.time() + duration
        last_report = time.time()
        while time.time() < deadline:
            chunk = ser.read(512)
            if chunk:
                total_bytes += len(chunk)
                if verbose and total_bytes == len(chunk):
                    print(f"{prefix}首包 {len(chunk)} bytes: {chunk[:80]!r}")
                text = chunk.decode("ascii", errors="replace")
                buf += text
                buf, gps_count, phgf_count, nmea_other = process_buffer(
                    buf,
                    gps_count=gps_count,
                    phgf_count=phgf_count,
                    nmea_other=nmea_other,
                    verbose=verbose,
                    log_fp=log_fp,
                )
            elif verbose and time.time() - last_report >= 10:
                elapsed = int(time.time() - (deadline - duration))
                print(f"{prefix}… {elapsed}s 已收 {total_bytes} bytes")
                last_report = time.time()

    print(
        f"{prefix}小結: bytes={total_bytes} GPS={gps_count} PHGF={phgf_count} other_nmea={nmea_other}"
    )
    return total_bytes, gps_count, phgf_count, nmea_other


def run_diag(
    port: str,
    duration: float,
    verbose: bool,
    log_path: Path | None,
) -> int:
    log_fp = log_path.open("w", encoding="utf-8") if log_path else None
    if log_path:
        print(f"原始行 log → {log_path}")

    results: list[tuple[str, int, int, int, int]] = []

    # 1) 預設 9600
    b, g, p, n = listen_once(
        port, 9600, duration, verbose=verbose, log_fp=log_fp, label="9600/default"
    )
    results.append(("9600 default", b, g, p, n))
    if g > 0:
        return 0

    # 2) DTR/RTS 組合（部分 SPP 需拉高）
    for dtr, rts, tag in [
        (True, True, "DTR1_RTS1"),
        (True, False, "DTR1_RTS0"),
        (False, True, "DTR0_RTS1"),
    ]:
        b, g, p, n = listen_once(
            port,
            9600,
            min(duration, 20),
            dtr=dtr,
            rts=rts,
            verbose=verbose,
            log_fp=log_fp,
            label=tag,
        )
        results.append((tag, b, g, p, n))
        if g > 0:
            return 0

    # 3) 送 wake probe（少數裝置需 host 先寫入）
    for probe, tag in [
        (b"\r\n", "probe_crlf"),
        (b"$PMTK314,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0*28\r\n", "probe_pmtk"),
    ]:
        b, g, p, n = listen_once(
            port,
            9600,
            min(duration, 15),
            probe=probe,
            verbose=verbose,
            log_fp=log_fp,
            label=tag,
        )
        results.append((tag, b, g, p, n))
        if g > 0:
            return 0

    # 4) Baud sweep
    for baud in DEFAULT_BAUDS:
        if baud == 9600:
            continue
        b, g, p, n = listen_once(
            port,
            baud,
            min(duration, 12),
            verbose=verbose,
            log_fp=log_fp,
            label=f"baud{baud}",
        )
        results.append((f"baud {baud}", b, g, p, n))
        if g > 0:
            return 0

    # 5) tty vs cu（Mac 上 cu 通常用於 outgoing）
    alt = port.replace("/cu.", "/tty.") if "/cu." in port else port.replace("/tty.", "/cu.")
    if alt != port:
        try:
            b, g, p, n = listen_once(
                alt,
                9600,
                min(duration, 15),
                verbose=verbose,
                log_fp=log_fp,
                label="alt_port",
            )
            results.append((f"alt {alt}", b, g, p, n))
        except serial.SerialException as e:
            print(f"[alt_port] 無法開啟 {alt}: {e}")

    print("\n=== 診斷摘要 ===")
    for name, b, g, p, n in results:
        mark = "✅" if g > 0 else ("⚠️" if b > 0 else "❌")
        print(f"  {mark} {name:16} bytes={b:5} GPS={g} PHGF={p}")

    if log_fp:
        log_fp.close()

    any_bytes = any(r[1] > 0 for r in results)
    any_gps = any(r[2] > 0 for r in results)
    if any_gps:
        print("\n✅ Classic 可收 GPS → 可進行 APP 雙通道（Classic 快取 GGA + BLE PHGF）")
        return 0
    if any_bytes:
        print("\n⚠️ 有收到資料但無 GGA/RMC → 檢查 NMEA 格式或儀器 GPS 設定")
        return 1
    print(
        "\n❌ 全程 0 byte → SPP 未送資料。下一步：\n"
        "  1. Mac 取消配對 _COM → 重配 → 重開儀器\n"
        "  2. 確認手機 BLE 已斷\n"
        "  3. 對照 firmware_backup 內 VLB 的 Reading gps / _COM\n"
        "  4. 白天有 GPS fix 再測一次"
    )
    return 2


def main() -> None:
    parser = argparse.ArgumentParser(description="VLGEO2 Classic BT GPS 監聽（方案 1）")
    parser.add_argument("--port", help="序列埠，例如 /dev/cu.VLGEO2_3190_COM")
    parser.add_argument("--baud", type=int, default=9600)
    parser.add_argument("--duration", type=float, default=120.0)
    parser.add_argument(
        "--diag",
        action="store_true",
        help="依序跑 DTR/RTS、probe、baud、alt port 診斷",
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    parser.add_argument(
        "--log",
        type=Path,
        help="NMEA 行 log 路徑（預設 diag 時寫入 raw_captures/）",
    )
    parser.add_argument("--checklist", action="store_true", help="只印測前檢查表")
    args = parser.parse_args()

    if args.checklist:
        print_checklist()
        return

    print_checklist()

    ports = [args.port] if args.port else find_vlgeo_ports()
    if not ports:
        print("未找到 VLGEO Classic 序列埠。")
        print("\n請在 Mac「系統設定 → 藍牙」配對 VLGEO2_XXXXX_COM（PIN 1234）。")
        for p in list_ports.comports():
            print(f"  {p.device}  {p.description}")
        sys.exit(1)

    port = ports[0]
    if len(ports) > 1 and args.verbose:
        print("偵測到多埠:", ports)

    log_path = args.log
    if args.diag and log_path is None:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_path = Path(__file__).resolve().parent / "raw_captures" / f"classic_gps_{ts}.log"
        log_path.parent.mkdir(parents=True, exist_ok=True)

    if args.diag:
        code = run_diag(port, args.duration, args.verbose, log_path)
        sys.exit(code)

    print(f"開啟 {port} @ {args.baud} …（加 --diag 跑完整排查）\n")
    _, gps, phgf, _ = listen_once(
        port,
        args.baud,
        args.duration,
        verbose=args.verbose,
        log_fp=log_path.open("w", encoding="utf-8") if log_path else None,
    )
    print(f"\n摘要: GPS 句={gps}, PHGF 句={phgf}")
    if gps == 0:
        print("未收到 GGA/RMC。建議：python verify_vlgeo2_classic_gps.py --diag -v")
    else:
        print("Classic 通道可取得儀器 GPS → APP 應採「Classic GPS + BLE 量測」。")


if __name__ == "__main__":
    main()
