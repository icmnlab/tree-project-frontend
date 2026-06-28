# Post-Deployment Verification Checklist

Regression and smoke tests after backend deployment and mobile release.

| Field | Value |
|-------|-------|
| **Last reviewed** | 2026-06-29 |
| **App version** | `18.10.4+26` (`pubspec.yaml`) |
| **DB migrations** | ≥ 35 |
| **Accounts** | Use lab-dedicated test accounts |

**Related**: `BOUNDARY_SYSTEM_DESIGN.md`, `SURVEY_HISTORY.md`, `CARBON_CALCULATION.md`, `FIELD_SURVEY_SOP.md`

---

## 1. Prerequisites

- [ ] Backend `main` deployed; migrations ≥ 35 applied
- [ ] Flutter build ≥ `18.10.4+26`
- [ ] Device reaches lab backend (`<SERVER_IP>` or `<TAILSCALE_HOST>` — placeholders only in git)
- [ ] Hardware: VLGEO2 (STD V3.7+); T4 transponder for HEIGHT DME tests
- [ ] Accounts: admin + surveyor A + surveyor B

### 1.1 Verification harness

| Flag | Purpose |
|------|---------|
| `flutter run` (debug) | Prints `[VERIFY][PASS/FAIL/SKIP]` |
| `RUN_VERIFICATION_HARNESS=true` | Enable harness on release builds |
| `SKIP_VERIFICATION_HARNESS=true` | Disable harness |
| `ENABLE_FIELD_LOGS=true` | BLE / maintenance field logs |
| `FIXTURE_PROJECT_CODE=<code>` | Seed-tree checks after login |

After login, hot restart (`R`) so JWT-backed checks re-run.

### 1.2 Backend connectivity

```powershell
curl.exe -s -m 12 http://<SERVER_IP>:3000/health
flutter run --dart-define=API_BASE_URL=http://<SERVER_IP>:3000/api
```

**GPS rule**: Fix coordinates **at the tree trunk**, not at the sighting position (HD offset can shift markers by tens of metres).

### 1.3 Field runbook (hardware + logs)

| Check | Operator action | Expected logs |
|-------|-----------------|---------------|
| M1–M4 | Maintenance → re-measure → SEND → GPS choice | `[Maintain]`, `[FieldGPS]`, `[Pending]` |
| M5/M6 | Dual-device lock | A: lock acquired; B: 409 / UI block |
| EOT-1/2 | SEND FILES / disconnect | `[BleLive] ... EOT` or disconnect message |
| I3P/IDME + T4 | HEIGHT mode → SEND | PHGF parsed, height in form |
| F1–F3 | Integrated photo / species | Trunk overlay in integrated scanner |

---

## 2. CI-automated coverage (spot-check only)

| Area | Invariant | Test |
|------|-----------|------|
| Maintenance GPS | Keep vs update coords | `maintenance_gps_flow_test.dart` |
| Maintenance new tree | Not in session todo/map | `maintenance_session_test.dart` |
| Maintenance lock | 409 LOCKED | `maintenance_locks.test.js` |
| Handbook DBH | Instrument ≠ official DBH | `handbook_dbh_source_test.dart`, `instrument_traceability.test.js` |
| Transfer trace | instrument_type / instrument_dbh_cm | `instrument_traceability.test.js` |
| GPS guard | Unfixed GPS blocks transfer | `transfer_gps_guard.test.js` |
| Request dedup | Same X-Request-Id | `requestIdDedup.test.js` |
| Lifecycle | Status mapping, 枯立木→dead | `treeLifecycle.test.js`, `tree_lifecycle_retire.test.js` |
| Tree statuses | Catalog CRUD | `tree_statuses.test.js` |
| Admin self-protection | Cannot delete self | `admin_self_protection.test.js` |
| Boundaries | Import/export | `project_boundary_import.test.js`, `boundary_input_test.dart` |
| BLE coords | tree/surveyor/mixed_pending | `ble_pending_workflow_test.dart` |

**Manual-only**: SEND dialog UX, dual-device UX feel, T4 RF, EOT interruption, camera overlay, 409 merge dialog.

---

## 3. Maintenance session (P0)

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| M1 | Maintenance → re-measure → BLE SEND | GPS: cancel / keep / update | [ ] |
| M2 | Keep + tree has coords | Pending keeps lat/lon | [ ] |
| M3 | Update GPS | Phone fix; transfer updates tree | [ ] |
| M4 | Add new tree in session | Not in todo/map | [ ] |
| M5 | A enters tree X BLE | B blocked or sees lock | [ ] |
| M6 | A completes/leaves | Lock released | [ ] |
| M7 | Handbook + remote diameter | Instrument DBH reference; manual official DBH | [ ] |
| M8 | Admin → user → projects | Program before zones | [ ] |

---

## 4. Instrument modes (HEIGHT 3P / DME)

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| I3P-1 | HEIGHT 3P, MEM off, SEND | Form height = HUD | [ ] |
| I3P-2 | Two consecutive SENDs | Second PHGF OK | [ ] |
| IDME-1 | HEIGHT DME + T4, SEND | Height in form | [ ] |
| IDME-2 | MEM on, SEND FILES with DME rows | Rows in pending/import | [ ] |
| IRD-1 | Remote diameter on, SEND | Instrument DBH shown; manual official DBH | [ ] |

---

## 5. BLE file transfer & traceability

MEMORY **on** → SEND FILES; MEMORY **off** → live SEND.

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| EOT-1 | Import → SEND FILES complete | Green EOT; parsed rows | [ ] |
| EOT-2 | Disconnect mid-transfer | Incomplete; not success | [ ] |
| CSV-1 | File with 3P multi-SEQ same ID | Net height = max(H)−min(H) | [ ] |
| CSV-2 | File with HEIGHT DME rows | Rows in pending | [ ] |
| LIVE-1 | Live 3P → transfer | History instrument_type=3P | [ ] |
| LIVE-2 | Live DME → transfer | History type=DME | [ ] |
| TR-1 | Batch transfer | raw instrument_type set | [ ] |
| TR-2 | Remote diameter transfer | instrument_dbh_cm in raw/history | [ ] |
| MAP-1 | SEND FILES MAP*.CSV (optional) | SnackBar only; not tree pending | [ ] |

---

## 6. Optimistic lock

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| L1 | Pending task → submit | Success | [ ] |
| L2 | Live SEND → submit | Success | [ ] |
| L3 | Two devices; B submits first | A gets 409 dialog | [ ] |
| L4 | L3 → manual merge → resubmit | Success | [ ] |
| L5 | Edit tree DBH concurrent | 409 if stale updated_at | [ ] |

---

## 7. Project boundaries

Sample files: `docs/boundary_samples/`.

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| B1 | Draw boundary → switch project dropdown → save | project_code matches selection | [ ] |
| B2 | GET `/api/project-boundaries/by_code/{code}` | 200 + polygon | [ ] |
| B3 | Manual V3 → boundary chip | Matches backend status | [ ] |
| B4 | Suggest boundary ≥3 GPS trees | Preview + save | [ ] |
| B5 | Logout A → login B → BLE match | No stale cache | [ ] |
| B6 | Surveyor find_project | Authorized projects only | [ ] |
| B7 | Special chars in project name | No 404 / routing error | [ ] |
| B8 | Paste coords from `coords_sample.txt` | Preview vertices; save | [ ] |
| B9 | Self-intersecting paste | Warning; auto-reorder option; backend 400 if forced | [ ] |
| B10 | Import `sample_boundary.kml` | WGS84 preview | [ ] |
| B11 | Import `sample_boundary_twd97.geojson` | EPSG:3826 → WGS84 | [ ] |
| B12 | Navigate back without save | Unsaved draft warning | [ ] |
| B13 | Switch zone after load | Draft cleared | [ ] |
| B14 | Paste `coords_sample_badrow.txt` | Missing decimal hint; skip bad row | [ ] |
| B15 | Paste `coords_complex_pond.txt` | Concave polygon; no false self-intersect | [ ] |
| B16 | Paste `coords_scrambled_convex.txt` | Self-intersect warning; auto-reorder fixes | [ ] |
| B17 | Manual cross edges → save | Self-intersect dialog; auto-reorder | [ ] |
| B18 | Export KML → re-import | Coords match | [ ] |
| B19 | Import `sample_boundary_complex.kml` | Concave pond OK | [ ] |
| B20 | Import `sample_boundary_points_only.kml` | Points → polygon | [ ] |
| B21 | Real-world KML (pins + polygon) | Uses polygon block; ignores stray pins | [ ] |
| B22 | Import file `coords_sample.txt` | Same as paste flow | [ ] |
| B23 | Import badrow/self-intersect txt | Same as paste warnings | [ ] |

---

## 8. Field measurement / camera

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| F1 | Field measure → scan VLGEO2 | Manual device pick | [ ] |
| F2 | Integrated form → integrated photo | Scanner with live trunk box | [ ] |
| F3 | Photo-only / photo+species modes | Per mode spec | [ ] |

---

## 9. Invites & account isolation

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| A1 | POST `/api/invites` | Invite code | [ ] |
| A2 | Register → login | Success | [ ] |
| A3 | New user scope | Authorized projects only | [ ] |
| A4 | Invite UI: multi-zone binding | ExpansionTile works | [ ] |
| A5 | Invites grouped by date | Same-day grouped | [ ] |
| A6 | Delete invite | 200 + audit DELETE_INVITE | [ ] |

---

## 10. Idempotent upload

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| R1 | Same X-Request-Id on batch POST | Same inserted_ids | [ ] |

---

## 11. New project → boundary → flows

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| N1 | New project → skip boundary → smart mode | No GPS auto-match; “no boundary” chip | [ ] |
| N2 | Manual project + submit | Success | [ ] |
| N3 | New project → draw boundary | Map overlay immediate | [ ] |
| N4 | Map page | Boundary + filter OK | [ ] |
| N5 | BLE import in boundary | Auto-assign project | [ ] |
| N6 | Form tree outside boundary | Warning; optional submit | [ ] |

---

## 12. Lifecycle, photos, tree status

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| LC1 | Maintenance → species prefill | Prior species shown | [ ] |
| LC2 | Keep prefill → submit | Species unchanged | [ ] |
| LC3 | Photo ID different species | Confirm dialog | [ ] |
| LC4 | Photo ID same species | No dialog | [ ] |
| LC5 | Status dead/fallen/removed | Retired; off maintenance queue | [ ] |
| LC6 | Map | Grey/purple retired markers; toggle hide | [ ] |
| LC7 | List | Grey + retired label | [ ] |
| LC8 | Statistics / carbon | Excluded from active totals | [ ] |
| LC9 | Detail → retire (admin) | POST retire works | [ ] |
| LC10 | Detail → restore | Active again | [ ] |
| LC11 | Detail photos | Latest cloud photo | [ ] |
| LC12 | History panel | Per-measurement thumbnails | [ ] |
| ST1 | Status dropdown | Built-ins + (retired) labels | [ ] |
| ST2 | 枯立木 | Non-active carbon; retired UI | [ ] |
| ST3 | Custom status “雷擊” | Saved to catalog | [ ] |
| ST4 | Other device | Custom status in dropdown | [ ] |
| ST5 | Concurrent same custom name | Single row (ON CONFLICT) | [ ] |

---

## 13. Localization

| ID | Steps | Expected | ✓ |
|----|-------|----------|---|
| I1 | Switch English | Field cards in English | [ ] |

---

## 14. Known limitations (not test failures)

- Boundary client validation may fail-open when cache empty — trust backend `/check`
- Overlapping boundaries: first match wins
- `project_name` may drift from `projects.name` — canonical key is `project_code`

---

## 15. Issue report template

```
Date:
Device:
Account role:
Checklist ID:
Expected:
Actual:
Screenshot / logs:
```
