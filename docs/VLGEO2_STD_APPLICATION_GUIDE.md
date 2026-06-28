# VLGEO2 BLE Integration

Field measurement via Haglöf Vertex Laser Geo 2 over **Bluetooth Low Energy** (not Classic Bluetooth SPP).

**Last reviewed against code**: 2026-06-29  
**Status**: Stable — primary field workflow

---

## Overview

The app parses VLGEO2 measurement data **on the phone** and uploads structured JSON to the backend pending API. There is **no BLE server** component on the backend.

GPS for tree coordinates: **phone GPS** (Geolocator), not instrument Classic BT NMEA.

---

## Supported modes

| Mode | Protocol | App entry | Status |
|------|----------|-----------|--------|
| Live single send | BLE GATT `$PHGF` packets | `ble_live_session_page.dart` | **Primary** |
| File import | BLE `DATA.CSV` + EOT | `ble_import_page.dart` | Supported; SOP may de-emphasize |
| MAP TARGET / TRAIL | `MAP*.CSV` | — | **Not parsed** |
| Classic BT NMEA | SPP | — | **Not implemented** |

---

## User flow

1. Home → **VLGEO2 現場連線** → field session setup dialog.
2. Scan/connect via `flutter_blue_plus`.
3. Live decode: `ble_live_packet_decoder.dart` → pending batch upload.
4. Optional: **藍牙匯入** for full CSV file transfer.

Data path: BLE → pending → `POST /api/pending-measurements/transfer` → `tree_survey`.

---

## Code map

| Layer | File |
|-------|------|
| Live session UI | `lib/screens/ble_live_session_page.dart` |
| Import UI | `lib/screens/ble_import_page.dart` |
| UART discovery | `lib/utils/ble_uart_discovery.dart` |
| Live decoder | `lib/services/ble_live_packet_decoder.dart` |
| CSV decoder | `lib/services/ble_packet_decoder.dart`, `ble_data_processor.dart` |
| Field GPS | `lib/widgets/field/field_session_setup.dart` |
| Backend | `routes/pending_measurements.js` only |

---

## API

- `POST /api/pending-measurements/batch`
- `POST /api/pending-measurements/transfer`

See `SURVEY_HISTORY.md`, `API_REFERENCE.md`.

---

## Hardware references

| Resource | URL |
|----------|-----|
| STD user guide | https://content.protocols.io/files/hun362te.pdf |
| Haglöf STD cloud | https://haglof.app/product/std/ |

Full hardware manual: request from Haglöf distributor (not in repo).

---

## Testing

- `frontend/test/` — BLE packet decoder unit tests
- `test/vlgeo2_ble_analysis/` — research scripts (not production)

---

## Related

- `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` — cancelled external GNSS procurement
- `FIELD_SURVEY_SOP.md` — operator procedures
- `SURVEY_HISTORY.md` — pending → transfer

---

## Naming note

`BleLiveNmeaAssembler` handles **`$PHGF` text on BLE**, not satellite NMEA from Classic Bluetooth.
