#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
現場測試資料集 — 從 Windows 呼叫後端 seed 腳本

用法（在 frontend 目錄或本腳本目錄）：
  python test/field_test_dataset/seed_field_test_dataset.py --lat 24.15 --lon 120.65 --project-code YOUR_CODE
  python test/field_test_dataset/seed_field_test_dataset.py --lat 24.15 --lon 120.65 --project-code YOUR_CODE --apply
  python test/field_test_dataset/seed_field_test_dataset.py --cleanup --apply

會執行 backend/scripts/seed_field_test_dataset.js（需 backend/.env 含 DATABASE_URL）。
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys


def _backend_root() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(here, "..", "..", "..", "backend"))  # frontend/test/field_test_dataset → backend


def main() -> int:
    parser = argparse.ArgumentParser(description="種入現場測試樹木（歷史 + 維護）")
    parser.add_argument("--lat", type=float, help="緯度（手機 GPS）")
    parser.add_argument("--lon", type=float, help="經度")
    parser.add_argument("--project-code", dest="project_code", help="區 Block 的 project_code")
    parser.add_argument("--species", default="台灣肖楠")
    parser.add_argument("--apply", action="store_true", help="實際寫入 DB")
    parser.add_argument("--cleanup", action="store_true", help="刪除 QA-FIXTURE 測試樹")
    args = parser.parse_args()

    backend = _backend_root()
    script = os.path.join(backend, "scripts", "seed_field_test_dataset.js")
    if not os.path.isfile(script):
        print(f"找不到 {script}", file=sys.stderr)
        return 2

    cmd = ["node", script]
    if args.cleanup:
        cmd.append("--cleanup")
    else:
        if args.lat is None or args.lon is None or not args.project_code:
            print("請提供 --lat --lon --project-code（或 --cleanup）", file=sys.stderr)
            return 2
        cmd.append(f"--lat={args.lat}")
        cmd.append(f"--lon={args.lon}")
        cmd.append(f"--project-code={args.project_code}")
        cmd.append(f"--species={args.species}")
    if args.apply:
        cmd.append("--apply")

    print("執行:", " ".join(cmd))
    print("工作目錄:", backend)
    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    proc = subprocess.run(cmd, cwd=backend, env=env)
    if proc.returncode == 0 and args.apply and not args.cleanup:
        print("\n--- 接下來在 App ---")
        print("flutter run --release --dart-define=ENABLE_FIELD_LOGS=true")
        print("維護量測 → 選相同專案／區 → 地圖／清單找 QA 測試樹")
    return proc.returncode


if __name__ == "__main__":
    sys.exit(main())
