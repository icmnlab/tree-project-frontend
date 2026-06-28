# Documentation Retention Policy

Which files belong in git, which can be removed, and which stay local-only.

**Last reviewed**: 2026-06-29

---

## Tier 1 — Must keep (legal & onboarding)

| File | Location | Why |
|------|----------|-----|
| `LICENSE` | repo root | MIT license text |
| `AUTHORS.md` | repo root | Copyright and handover attribution (canonical) |
| `docs/ARCHITECTURE.md` | frontend | System design entry point |
| `docs/HANDOFF.md` | frontend | Operator/developer onboarding |
| `docs/API_REFERENCE.md` | frontend | REST catalog (human-readable) |

Removing Tier 1 violates handover terms or breaks onboarding.

---

## Tier 2 — Should keep (production & ops)

All reviewed runbooks and module guides listed in `docs/README.md`:

- Deployment, build, secrets, verification, field SOP, handover checklist
- Domain guides (survey, boundaries, BLE, carbon, species, admin, etc.)
- Experimental guides (`EXPERIMENTAL_FEATURES.md`, `VISUAL_MEASUREMENT.md`, …)

These map to real code paths. Deleting them creates gaps for the recipient team.

---

## Tier 3 — Reference (optional but recommended)

| File | Delete? | Notes |
|------|---------|-------|
| `DBH_MEASUREMENT_RESEARCH_V2.md` | Optional | Research notes; production path is `VISUAL_MEASUREMENT.md` + `ml_service/README.md` |
| `DBH_PURE_VISION_RESEARCH.md` | Optional | Superseded by V2; kept for thesis / experiment history |
| `HANDOFF_EXTERNAL_GNSS_AND_BLE.md` | **Keep** | Documents cancelled scope — prevents re-procurement confusion |
| `docs/boundary_samples/*` | **Keep** | Used by `VERIFICATION_CHECKLIST.md` B8–B23 |

**Western practice**: move obsolete docs to `docs/archive/` with a one-line README, or mark `Status: Archived` at the top — do not silently delete without updating links.

---

## Tier 4 — Removed / consolidated

| File | Status |
|------|--------|
| `CONTRIBUTION_RECORD.md` | **Removed** — content merged into `AUTHORS.md` (2026-06-29) |

---

## Local-only (never push)

| Path | Purpose |
|------|---------|
| `project_code/docs/DEPLOYMENT_LOG.md` | VM ops with real IPs/passwords |
| `project_code/docs/archive/` | Pre-rewrite doc snapshots |
| `project_code/docs/REDEPLOY_MANUAL.md` | School-specific cheat sheet |

---

## Decision matrix

| Question | Action |
|----------|--------|
| Does code still exist for this feature? | Keep or archive doc; mark Experimental if hidden |
| Is it duplicate of another doc? | Merge, then delete duplicate + fix links |
| Is it research / thesis only? | Tier 3 — archive OK if linked from retention policy |
| Does MIT / handover require it? | Tier 1 — do not delete |
| Contains secrets or school IPs? | Never commit; keep local |

---

## Related

- `docs/README.md` — current doc index
- `CODEBASE_INVENTORY.md` §6 — documentation phases
