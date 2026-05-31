#!/usr/bin/env python3
"""
監看 VLGEO2 USB 磁碟上的 DATA.CSV 是否新增含 GPS 的列。

用途：驗證「MEMORY 開 + USE GPS 開」時，儀器是否把 LAT/LON 寫進存檔（手冊 §4.4.12、§7）。
這與 MEMORY 關的逐棵 BLE PHGF 是不同模式；若此路徑有 GPS，可評估場次匯出或雙通道策略。

用法：
  1. USB 連接儀器（Mac 上應出現 /Volumes/VL_GEO2）
  2. 儀器：USE GPS=ON，ENABLE MEM=ON（依手冊此模式可能無法 BLE 即時 SEND）
  3. python verify_vlgeo2_gps_usb_watch.py
  4. 在儀器上量測並 SEND，看終端是否出現新列
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

DEFAULT_CSV = Path("/Volumes/VL_GEO2/DATA/DATA.CSV")


def parse_rows(text: str) -> list[dict]:
    rows = []
    for ln in text.splitlines():
        ln = ln.strip()
        if not ln.startswith("$"):
            continue
        f = ln.split(";")
        rows.append({
            "raw": ln,
            "type": f[2] if len(f) > 2 else "",
            "id": f[6] if len(f) > 6 else "",
            "lat": f[12] if len(f) > 12 else "",
            "lon": f[14] if len(f) > 14 else "",
            "utc": f[19] if len(f) > 19 else "",
        })
    return rows


def row_key(r: dict) -> str:
    return r["raw"]


def main() -> None:
    parser = argparse.ArgumentParser(description="監看 VLGEO2 USB DATA.CSV 新增列")
    parser.add_argument(
        "--csv",
        type=Path,
        default=DEFAULT_CSV,
        help=f"DATA.CSV 路徑（預設 {DEFAULT_CSV}）",
    )
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()

    csv_path = args.csv
    if not csv_path.is_file():
        print(f"找不到 {csv_path}")
        print("請 USB 連接儀器，確認出現 VL_GEO2 磁碟。")
        sys.exit(1)

    seen: set[str] = set()
    initial = parse_rows(csv_path.read_text(encoding="utf-8", errors="replace"))
    for r in initial:
        seen.add(row_key(r))

    print(f"監看: {csv_path}")
    print(f"現有 ${len(initial)} 列。請在儀器上量測 + SEND（MEMORY 開）。Ctrl+C 結束。\n")

    last_mtime = csv_path.stat().st_mtime
    try:
        while True:
            time.sleep(args.interval)
            mtime = csv_path.stat().st_mtime
            if mtime == last_mtime:
                continue
            last_mtime = mtime
            rows = parse_rows(csv_path.read_text(encoding="utf-8", errors="replace"))
            for r in rows:
                k = row_key(r)
                if k in seen:
                    continue
                seen.add(k)
                has_gps = bool(
                    r["lat"] and r["lon"]
                    and re.search(r"\d", r["lat"])
                    and re.search(r"\d", r["lon"])
                )
                flag = "✅ GPS" if has_gps else "❌ 無 GPS"
                print(
                    f"[新增] {flag} TYPE={r['type']} ID={r['id']} "
                    f"LAT={r['lat']} LON={r['lon']} UTC={r['utc']}"
                )
    except KeyboardInterrupt:
        print("\n結束。")


if __name__ == "__main__":
    main()
