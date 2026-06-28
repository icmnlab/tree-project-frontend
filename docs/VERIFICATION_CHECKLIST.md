# Post-Deployment Verification Checklist

Smoke and regression checklist after backend deploy and APK release.

**Last reviewed**: 2026-06-29  
**Target versions**: App `18.10.4+26` (see `pubspec.yaml`); DB migrations **≥ 35**  
**Use**: Lab-dedicated test accounts (not personal accounts)

---

## How to use this document

1. Complete **Prerequisites** (§1).
2. Items in **§2** are covered by CI — spot-check on device only.
3. Work through **§3–§11** manually; hardware/BLE/camera items require physical devices.
4. Log failures using **§12** template.

Related: `BOUNDARY_SYSTEM_DESIGN.md`, `SURVEY_HISTORY.md`, `CARBON_CALCULATION.md`.

---

## 1. Prerequisites

- [ ] Backend `main` deployed; migrations ≥ 35 applied
- [ ] Flutter build ≥ `18.10.4+26`
- [ ] Phone reaches lab backend (`<SERVER_IP>` or Tailscale — use placeholders, not committed hosts)
- [ ] Hardware: VLGEO2 (STD V3.7+), optional T4 for HEIGHT DME tests
- [ ] Accounts: admin + surveyor A + surveyor B (maintenance lock tests)

### 1.1 Verification harness (optional)

| Command | Purpose |
|---------|---------|
| `flutter run` | Debug: prints `[VERIFY][PASS/FAIL/SKIP]` codes |
| `--dart-define=RUN_VERIFICATION_HARNESS=true` | Same harness on release builds |
| `--dart-define=ENABLE_FIELD_LOGS=true` | BLE / maintenance field logs |
| `--dart-define=SKIP_VERIFICATION_HARNESS=true` | Disable harness |

After login, hot restart (`R`) so JWT-backed checks re-run.

### 1.2 Quick backend check

```powershell
curl.exe -s -m 12 http://<SERVER_IP>:3000/health
```

Expect `OK`. Point app at lab API:

```powershell
flutter run --dart-define=API_BASE_URL=http://<SERVER_IP>:3000/api
```

**GPS SOP**: Stand **at the tree** when fixing coordinates. Do not GPS from the sighting position (HD offset can shift map markers by tens of metres).

---

## 2. CI-automated (spot-check on device)

These invariants run on every push. Manual retest optional unless debugging regressions.

| Area | Invariant | Test location |
|------|-----------|---------------|
| Maintenance GPS | No update → keep coords; update → phone GPS | `maintenance_gps_flow_test.dart` |
| Maintenance new tree | Session add not in todo/map | `maintenance_session_test.dart` |
| Maintenance lock | Second user 409 LOCKED | `maintenance_locks.test.js` |
| Handbook DBH | Instrument diameter ≠ official DBH | `handbook_dbh_source_test.dart`, `instrument_traceability.test.js` |
| Transfer trace | History has instrument fields | `instrument_traceability.test.js` |
| GPS guard | Unfixed GPS blocks transfer | `transfer_gps_guard.test.js` |
| Request dedup | Same `X-Request-Id` idempotent | `requestIdDedup.test.js` |
| Lifecycle | Status → active/dead/fallen/removed | `treeLifecycle.test.js`, `tree_lifecycle_retire.test.js` |
| Tree statuses | Catalog CRUD + 枯立木→dead | `tree_statuses.test.js` |
| Admin self | Cannot disable/delete self | `admin_self_protection.test.js` |
| Boundaries | Import/export/self-intersect | `project_boundary_import.test.js`, `boundary_input_test.dart` |
| BLE coords | tree/surveyor/mixed_pending | `ble_pending_workflow_test.dart` |

**Requires physical hardware** (cannot fully automate): SEND dialog UX, dual-device lock UX, T4 RF, EOT file transfer, camera live trunk overlay, 409 merge dialog UI.

---

## 3. Maintenance session (P0)

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| M1 | Maintenance → re-measure → BLE SEND | GPS prompt: cancel / keep / update | [ ] |
| M2 | Choose keep + tree has coords | Pending keeps old lat/lon | [ ] |
| M3 | Choose update | Phone GPS; transfer updates tree | [ ] |
| M4 | Add new tree in session | Returns to list; not in todo/map | [ ] |
| M5 | A locks tree X in BLE | B blocked or sees lock owner | [ ] |
| M6 | A completes/leaves | Lock released; B can enter | [ ] |
| M7 | Handbook mode + remote diameter | Instrument DBH reference only; manual DBH | [ ] |
| M8 | Admin → user → project link | Select program before zones | [ ] |

---

## 4. Instrument modes (HEIGHT 3P / DME)

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| I3P-1 | HEIGHT 3P, MEM off, SEND | Form height matches HUD | [ ] |
| I3P-2 | Two consecutive SENDs | Second PHGF parses (prefix fix) | [ ] |
| IDME-1 | HEIGHT DME + T4, SEND | Height in form | [ ] |
| IDME-2 | MEM on, SEND FILES with DME rows | Pending/import retains DME rows | [ ] |
| IRD-1 | Remote diameter on, SEND | Instrument DBH shown; manual official DBH | [ ] |

---

## 5. BLE file transfer & traceability

MEMORY **on** → SEND FILES; MEMORY **off** → live SEND only.

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| EOT-1 | Import → SEND FILES complete | Green EOT; parsed rows | [ ] |
| EOT-2 | Disconnect mid-transfer | Incomplete; not success | [ ] |
| CSV-1 | File with 3P multi-SEQ same ID | Net height = max−min | [ ] |
| LIVE-1 | Live 3P → transfer | History `instrument_type`=3P | [ ] |
| LIVE-2 | Live DME → transfer | History type=DME | [ ] |
| TR-1 | Batch transfer | `tree_measurement_raw.instrument_type` set | [ ] |
| TR-2 | Remote diameter transfer | Raw/history `instrument_dbh_cm`; manual dbh | [ ] |

---

## 6. Optimistic lock (pending form)

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| L1 | Pending task → submit | Success, no conflict | [ ] |
| L2 | Live SEND → submit | Success | [ ] |
| L3 | Two devices same task; B submits first | A gets 409 dialog | [ ] |
| L4 | L3 → manual merge → resubmit | Second submit succeeds | [ ] |
| L5 | Edit tree DBH; concurrent edit | 409 if stale `updated_at` | [ ] |

---

## 7. Project boundaries

Sample files: `docs/boundary_samples/`.

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| B1 | Draw boundary → switch project in dropdown → save | `project_code` matches selection | [ ] |
| B2 | `GET /api/project-boundaries/by_code/{code}` | 200 + polygon | [ ] |
| B3 | Manual V3 → boundary chip | Matches backend status | [ ] |
| B4 | Suggest boundary from ≥3 GPS trees | Preview + save | [ ] |
| B5 | Logout A → login B → BLE match | No stale boundary cache | [ ] |
| B6 | Surveyor find_project | Only authorized projects | [ ] |
| B8–B23 | Paste coords / import KML / GeoJSON / export | Per `boundary_samples/README.md` | [ ] |

---

## 8. Auth & invites

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| A1 | `POST /api/invites` (admin JWT) | Invite code returned | [ ] |
| A2 | Register with invite → login | Success | [ ] |
| A3 | New user project scope | Matches invite | [ ] |
| A4–A6 | Invite UI: zones, grouping, delete | See `ADMIN_AND_INVITE_DESIGN.md` | [ ] |

---

## 9. Lifecycle & tree status

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| LC1–LC4 | Maintenance species inherit / photo mismatch dialog | Per `SURVEY_HISTORY.md` | [ ] |
| LC5–LC10 | Retire / restore / map grey / carbon exclusion | Active carbon excludes retired | [ ] |
| LC11–LC12 | Photos on detail + history panel | Latest + per-measurement thumbs | [ ] |
| ST1–ST5 | Shared status catalog + custom status | `tree_statuses.test.js` behaviour | [ ] |

---

## 10. Other regression

| ID | Area | Expected | ✓ |
|----|------|----------|---|
| N1–N6 | New project + boundary + map/BLE | `BOUNDARY_SYSTEM_DESIGN.md` | [ ] |
| F1–F3 | Scanner / integrated photo | Trunk overlay in integrated path | [ ] |
| R1 | Duplicate `X-Request-Id` on batch POST | Same `inserted_ids` | [ ] |
| I1 | English locale | Field cards translated | [ ] |

---

## 11. Known limitations (not failures)

- Boundary client validation may fail-open when cache empty — backend `/check` is authoritative
- Overlapping boundaries: first match wins
- `project_name` denormalization may drift from `projects.name` — canonical key is `project_code`

---

## 12. Issue report template

```
Date:
Device:
Account role:
Checklist ID (e.g. B2):
Expected:
Actual:
Screenshot / logs:
```
