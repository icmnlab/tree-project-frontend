# Field Survey Standard Operating Procedure

Operator runbook for initial and maintenance tree surveys using VLGEO2 BLE and the mobile app.

**Audience**: Field survey crews (two-person teams)  
**Last reviewed**: 2026-06-29  
**Technical reference**: `VLGEO2_STD_APPLICATION_GUIDE.md`, `SURVEY_HISTORY.md`, `HANDOFF.md`

---

## Scope

Covers the **primary production path**: home → **VLGEO2 Live Session** → pending → integrated form → transfer to official records.

Out of scope for routine field work (see §Deferred features):

- Batch BLE file import (SEND FILES)
- Instrument Classic Bluetooth GPS
- External GNSS modules

---

## Roles (two-person team)

| Role | Responsibilities |
|------|------------------|
| **Operator A** | VLGEO2 operation, SEND, confirm app receives height/distance/azimuth |
| **Operator B** | Tape DBH at breast height, photos, form entry |

**Critical rule**: DBH must come from **tape circumference converted to diameter**, entered manually in the app. Do not use the rangefinder’s remote diameter as the official DBH.

---

## Pre-flight checklist

### Mobile app

- [ ] Latest survey APK installed; registered via invite code
- [ ] Bluetooth and location (GPS) permissions granted
- [ ] Login succeeds (confirms backend reachability)
- [ ] Battery ≥ 50% or power bank available

### VLGEO2

- [ ] Charged; Bluetooth on
- [ ] **ENABLE MEM off** — use per-tree **SEND**, not SEND FILES
- [ ] Operators familiar with height measurement per instrument manual

### Session setup (before first tree)

| Field | Meaning |
|-------|---------|
| **Program** (UI: 專案) | Survey program |
| **Zone** (UI: 區) | Block within program; has optional boundary |
| **Session name** | Shared label for the day (e.g. `2026-06-05-AM`) |

Select **program → zone** before measuring.

---

## Terminology

| Spoken term | App label | Meaning |
|-------------|-----------|---------|
| Program | 專案 | Top-level survey program |
| Zone / block | 區 | Sample area within program |

See `PROJECT_DATA_AND_DOMAIN.md` for database mapping.

---

## Initial survey — live BLE (primary mode)

### Connect

```
Home → VLGEO2 Live Session → scan → select device → connected
```

### Per-tree sequence

```
① Measure with VLGEO2 at the tree
② Press SEND on instrument
③ App receives height, distance, azimuth
④ Phone GPS at the tree (stand beside trunk)
⑤ Complete integrated form (DBH, species, photos)
⑥ Submit
⑦ Return to live session → next tree
```

### GPS rules

| Rule | Detail |
|------|--------|
| Source | **Phone GPS only** — BLE SEND does not carry GPS |
| Position | **Tree location** — stand at the trunk |
| No fix | Do not create record; move to open sky → retry GPS or re-SEND |
| Cancel fix | Abandon this tree; SEND again when ready |

### Form notes

- **DBH**: manual entry from tape circumference
- **Species**: optional photo ID; app prefers common Chinese name
- **Photos**: at least one whole-tree or feature photo recommended
- **Success**: tree in official DB; removed from pending queue

### Change program or zone mid-session

Use top-right switch on live session screen. Trees **already submitted** stay in the original zone; only subsequent SENDs use the new selection. When unsure, end session and start fresh.

Initial survey has **no navigation to next tree** (reserved for maintenance workflows).

---

## Maintenance survey

```
Home → Maintenance → select program / zone / session → list or map
  → select existing tree → confirm → connect VLGEO2 → same per-tree flow
```

| Mode | Action |
|------|--------|
| List | Search tree ID, select, enter BLE |
| Map | Tap marker in zone → confirm → BLE |

| Aspect | Initial | Maintenance |
|--------|---------|-------------|
| Tree selection | Walk-up, measure each tree | Pick existing tree first |
| Data write | New tree | Append measurement history + update snapshot |
| History | — | Preview prior measurements when selecting |

New trees discovered during maintenance: use **Add tree** — same flow as initial survey.

### Lifecycle (dead / fallen / removed)

- Form pre-fills prior species; photo ID prompts if result differs
- Status **dead / fallen / removed** → tree **retired**: excluded from active carbon and maintenance queue; map greyed; history retained
- **Restore** (survey admin+): tree detail → lifecycle card
- Built-in + shared custom status options; see `SURVEY_HISTORY.md` and backend `treeLifecycle.js`

---

## Viewing measurement history

| Location | Use |
|----------|-----|
| Tree detail page | All users |
| Maintenance tree picker | Compare before re-measure |
| Integrated form (maintenance) | Reference while in field |

Newest measurement first.

---

## Tree ID display

| Surface | Display | Notes |
|---------|---------|-------|
| Field list / map | Numeric only (e.g. `123`) | Strips `PT-` prefix |
| Subtitle | `ST-xxx` | Internal system ID |
| Admin / detail | Full prefixed IDs | Matches database |

**ID alignment**: live per-tree workflow avoids batch ID mismatch. Batch BLE import ID rules are **not finalized** — do not rely on batch mode for primary field work.

---

## Troubleshooting

| Symptom | Action |
|---------|--------|
| No response after SEND | Check BLE link; finish or cancel open form; reconnect if needed |
| “Disable ENABLE MEM” | Turn off memory mode; use single-tree SEND |
| No GPS | Move to open area; **Retry GPS** (measurement data retained) |
| BLE disconnect | Auto-reconnect pauses during form; manual reconnect available |
| Abandon mid-form | Cancel → task stays in **pending** |
| Submit offline | Stays pending until network returns |

---

## Manual entry (no BLE)

Home → **Tree Survey**:

| Mode | Use |
|------|-----|
| Smart | Guided entry with auto zone hints |
| Quick | Experienced operators |
| Edit (tree detail) | Fix snapshot fields — **does not** add measurement history |

Re-measurements with history must use BLE or pending transfer, not edit.

---

## Deferred / not recommended

| Feature | Reason |
|---------|--------|
| Batch BLE (SEND FILES) | Complex; GPS gaps; ID alignment unresolved |
| Instrument GPS over BLE | Not implemented; phone GPS used |
| External GNSS | Not procured — see `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` |

---

## End-of-day checklist

- [ ] Submitted trees absent from pending (unless transfer retry needed)
- [ ] Note pending IDs for next session
- [ ] VLGEO2 powered off / BLE disconnected
- [ ] Trees without GPS fix logged for re-measure

---

## Escalation

| Issue | Contact |
|-------|---------|
| Accounts / invites | Project admin |
| Instrument | Instrument owner / manual |
| App / data | System maintainer |
| Server connectivity | Host / network admin |

---

## Related documents

- `FIELD_SURVEY_SOP.md` (this file) — operators  
- `VERIFICATION_CHECKLIST.md` — QA after deploy  
- `HANDOFF.md` — developers
