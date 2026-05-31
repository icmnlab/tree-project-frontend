#!/usr/bin/env python3
"""Aggressive VLGEO2 Classic SPP probe — force session + many open strategies."""

from __future__ import annotations

import glob
import re
import subprocess
import sys
import time

try:
    import serial
except ImportError:
    print("pip install pyserial")
    sys.exit(1)

PORT_CU = "/dev/cu.VLGEO2_3190_COM"
PORT_TTY = "/dev/tty.VLGEO2_3190_COM"
GPS = re.compile(rb"\$(?:GP|GN|GL|GA)(?:GGA|RMC|GLL|VTG|GSA|GSV),")
NMEA = re.compile(rb"\$[A-Z]{2,5},")


def bt_status() -> str:
    try:
        out = subprocess.run(
            ["system_profiler", "SPBluetoothDataType"],
            capture_output=True,
            text=True,
            timeout=30,
        ).stdout
        for block in out.split("\n\n"):
            if "VLGEO" in block and "COM" in block:
                if "Connected:" in block.split("VLGEO")[0][-200:]:
                    return "Connected"
                if "Not Connected:" in out[: out.find(block)]:
                    return "Not Connected (paired)"
        if "VLGEO2" in out and "COM" in out:
            idx = out.find("VLGEO2")
            snippet = out[max(0, idx - 400) : idx + 200]
            if "Connected:" in snippet and "Not Connected:" not in snippet.split("VLGEO2")[0][-100:]:
                return "Connected"
            return "Not Connected (paired)"
    except Exception as e:
        return f"unknown ({e})"
    return "not found"


def listen(
    port: str,
    baud: int,
    seconds: float,
    *,
    dtr: bool | None = None,
    rts: bool | None = None,
    probe: bytes | None = None,
    delay_before_read: float = 0,
    label: str = "",
) -> tuple[int, int, int, bytes]:
    total = gps = nmea = 0
    first: bytes = b""
    tag = label or f"{port}@{baud}"
    print(f"\n=== {tag} | DTR={dtr} RTS={rts} probe={len(probe or b'')}B | bt={bt_status()} ===")
    try:
        with serial.Serial(
            port,
            baudrate=baud,
            timeout=0.25,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
        ) as ser:
            print(f"  opened OK → bt={bt_status()}")
            if dtr is not None:
                ser.dtr = dtr
            if rts is not None:
                ser.rts = rts
            ser.reset_input_buffer()
            if probe:
                ser.write(probe)
                ser.flush()
            if delay_before_read:
                time.sleep(delay_before_read)
            deadline = time.time() + seconds
            raw = b""
            while time.time() < deadline:
                chunk = ser.read(1024)
                if chunk:
                    if not first:
                        first = chunk[:120]
                        print(f"  FIRST {len(chunk)}B: {first!r}")
                    total += len(chunk)
                    raw += chunk
                    gps += len(GPS.findall(chunk))
                    nmea += len(NMEA.findall(chunk))
            if total and not first:
                first = raw[:120]
    except serial.SerialException as e:
        print(f"  OPEN FAIL: {e}")
        return -1, 0, 0, b""
    print(f"  RESULT bytes={total} gps_lines={gps} nmea_lines={nmea} bt={bt_status()}")
    return total, gps, nmea, first


def main() -> None:
    ports = [p for p in (PORT_CU, PORT_TTY) if glob.glob(p.replace("/dev/", "/dev/"))]
    print("VLGEO Classic SPP aggressive probe")
    print(f"Initial BT: {bt_status()}")
    print(f"Ports: {ports}")

    tests: list[tuple] = []
    for port in ports:
        for baud in (9600, 115200, 38400, 57600, 4800):
            tests.append((port, baud, 12, None, None, None, 0, f"{port.split('/')[-1]}@{baud}"))

    # DTR/RTS @ 9600
    for dtr, rts, tag in [(True, True, "DTR1_RTS1"), (True, False, "DTR1_RTS0"), (False, True, "DTR0_RTS1")]:
        tests.append((PORT_CU, 9600, 10, dtr, rts, None, 0, tag))

    # Probes
    for probe, tag in [
        (b"\r\n", "probe_crlf"),
        (b"\r\n\r\n", "probe_crlf2"),
        (b"?\r\n", "probe_q"),
        (b"$PMTK314,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0*28\r\n", "probe_pmtk"),
    ]:
        tests.append((PORT_CU, 9600, 10, True, True, probe, 0.5, tag))

    # Open then wait (session settle)
    tests.append((PORT_CU, 9600, 20, True, True, None, 3.0, "settle_3s"))

    # Re-open loop (disconnect/reconnect simulation)
    print("\n--- Re-open loop (5x open 8s) ---")
    for i in range(5):
        b, g, n, _ = listen(PORT_CU, 9600, 8, dtr=True, rts=True, label=f"reopen_{i+1}")
        if g > 0 or b > 100:
            print(f"\n✅ SUCCESS on reopen_{i+1}")
            return
        time.sleep(1)

    results = []
    for args in tests:
        port, baud, sec, dtr, rts, probe, delay, label = args
        b, g, n, first = listen(port, baud, sec, dtr=dtr, rts=rts, probe=probe, delay_before_read=delay, label=label)
        results.append((label, b, g, n))
        if g > 0:
            print(f"\n✅ GPS NMEA on {label}")
            return
        if b > 0:
            print(f"\n⚠️ Data but no GGA/RMC on {label}: {first!r}")

    print("\n=== SUMMARY ===")
    for label, b, g, n in results:
        mark = "✅" if g else ("⚠️" if b > 0 else "❌")
        print(f"  {mark} {label:28} bytes={b:5} gps={g} nmea={n}")

    print(f"\nFinal BT: {bt_status()}")
    if all(r[1] <= 0 for r in results):
        print(
            "\n全部 0 byte。可能原因：\n"
            "  1. SPP session 未建立（藍牙仍 Not Connected）\n"
            "  2. 手機 BLE 仍佔用同一 MAC\n"
            "  3. 需先在 Mac 藍牙面板點「連線」到 _COM\n"
            "  4. 儀器 BLUETOOTH/GPS 設定未開"
        )


if __name__ == "__main__":
    main()
