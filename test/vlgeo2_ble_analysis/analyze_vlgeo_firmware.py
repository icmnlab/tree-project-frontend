#!/usr/bin/env python3
"""離線分析 VLGEO2 韌體副本（.VL7 / setup.bin）。不碰 /Volumes/VL_GEO2/。"""

from __future__ import annotations

import argparse
import hashlib
import re
from pathlib import Path

GPS_BLE_PATTERNS = {
    "GPS/座標": [r"GPS", r"GGA", r"RMC", r"NMEA", r"LAT", r"LON", r"GPSPOS", r"MAPGPS"],
    "BLE/藍牙": [r"BLE", r"BLUETOOTH", r"6e4000", r"9e0000", r"GATT", r"NOTIFY"],
    "量測": [r"PHGF", r"SEND", r"HVV", r"3P", r"1P", r"MEMORY"],
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def analyze_vl7(path: Path) -> None:
    data = path.read_bytes()
    print(f"\n=== {path.name} ({len(data)} bytes) SHA256={sha256(path)[:16]}… ===")
    strings = [
        s.decode("ascii", errors="replace")
        for s in re.findall(rb"[\x20-\x7e]{4,}", data)
    ]
    for cat, pats in GPS_BLE_PATTERNS.items():
        hits = sorted({s for s in strings if any(re.search(p, s, re.I) for p in pats)})
        print(f"\n[{cat}] {len(hits)} 條")
        for h in hits[:15]:
            print(f"  {h}")
        if len(hits) > 15:
            print(f"  …+{len(hits) - 15} more")

    for needle, label in [
        (b"$GNGGA", "GNGGA"),
        (b"$GNRMC", "GNRMC"),
        (b"6e400003", "NUS TX"),
        (b"9e010000", "Haglof TX"),
    ]:
        pos = data.find(needle)
        print(f"  search {label}: {'@' + str(pos) if pos >= 0 else 'NOT FOUND'}")


def analyze_setup(path: Path) -> None:
    data = path.read_bytes()
    print(f"\n=== setup.bin ({len(data)} bytes) ===")
    for i in range(0, len(data), 16):
        chunk = data[i : i + 16]
        hexpart = " ".join(f"{b:02x}" for b in chunk)
        print(f"  {i:04x}  {hexpart}")


def main() -> None:
    parser = argparse.ArgumentParser(description="VLGEO2 韌體副本離線分析")
    parser.add_argument(
        "dir",
        nargs="?",
        default="firmware_backup/VLGEO2_3190_20260531",
        help="備份資料夾（相對於本腳本目錄或絕對路徑）",
    )
    args = parser.parse_args()
    base = Path(args.dir)
    if not base.is_absolute():
        base = Path(__file__).resolve().parent / base

    for pattern in ("*.VL7", "*.VLB", "setup.bin"):
        for f in sorted(base.glob(pattern)):
            if f.suffix.upper() == ".VL7" or f.suffix.upper() == ".VLB":
                analyze_vl7(f)
            elif f.name == "setup.bin":
                analyze_setup(f)


if __name__ == "__main__":
    main()
