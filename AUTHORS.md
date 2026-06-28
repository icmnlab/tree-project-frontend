# Authors

**Last updated**: 2026-06-29

---

## Primary author

| Field | Value |
|-------|-------|
| Name / GitHub | **KyleliuNDHU** |
| Role | Original developer and primary maintainer through handover (2025–2026) |
| Copyright | Copyright (c) 2025 **KyleliuNDHU** — see [LICENSE](LICENSE) |

### Scope (this repository)

- Flutter application (`sustainable_treeai`, Android primary)
- Field survey UI (V2/V3), map, project/area management, boundary draw/import
- BLE integration with VLGEO2, maintenance survey workflows
- Species identification UI, statistics, experimental feature entry points
- Client test suite (`flutter test`) and CI
- Handover documentation under `docs/`

Backend counterpart: `tree-project-backend` — see that repo's `AUTHORS.md`.

---

## GitHub contributor graph

On the recipient org (`icmnlab/tree-project-frontend`), GitHub lists **one contributor** (`KyleliuNDHU`). That is expected: the handover repo uses a **fresh snapshot** history, not the full development log.

Authorship is established by **`LICENSE` + this file**, not by commit count on the recipient remote.

---

## Fresh-snapshot handover

When pushing to the recipient GitHub org, use a single snapshot commit (`git checkout --orphan`) so old commits (which may contain dev-only hostnames or secrets) are not transferred.

Procedure: `docs/LAB_DEPLOYMENT_GUIDE.md` §0.1 or `scripts/prepare_fresh_handover.ps1`.

The deliverer keeps a **private archive** of the full development history (`git log`, `git shortlog`) as personal evidence. That archive is **not** pushed to the recipient.

---

## Recipient obligations (MIT License)

1. Retain the copyright notice in `LICENSE` on all copies and substantial portions.
2. Do not remove or falsify this attribution file.
3. You may modify the code freely; do not claim original authorship or delete copyright/attribution files.

---

## Related

- `HANDOFF.md` §0 — handover context for new maintainers
- `HANDOVER_CHECKLIST.md` — delivery sign-off
- `docs/DOCUMENTATION_RETENTION.md` — which docs may be archived or removed
