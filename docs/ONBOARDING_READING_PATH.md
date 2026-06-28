# Onboarding Reading Path

How to read documentation on GitHub, what you need to understand, and whether docs alone are enough to continue development.

**Last reviewed**: 2026-06-29  
**Entry point**: [`docs/README.md`](./README.md)

---

## Where to start on GitHub

Both repos live under **`icmnlab`**:

| Repo | Start here |
|------|------------|
| **frontend** | [`docs/README.md`](./README.md) → this file |
| **backend** | [`docs/README.md`](../../backend/docs/README.md) → links back to frontend `docs/` |

Do **not** start from scattered markdown at repo root alone — the hub orders documents by priority.

---

## Recommended reading order (developers)

| Day | Time | Read / do |
|-----|------|-----------|
| **1** | 2–3 h | `README.md` (hub) → `HANDOFF.md` §1–§5 → `ARCHITECTURE.md` → clone both repos → run backend + `flutter run` |
| **1** | 1 h | `CODEBASE_INVENTORY.md` (skim) → `API_REFERENCE.md` (bookmark) |
| **2** | 2 h | Your domain: survey → `SURVEY_HISTORY.md`; boundaries → `BOUNDARY_SYSTEM_DESIGN.md`; BLE → `VLGEO2_STD_APPLICATION_GUIDE.md` |
| **2** | 1 h | `DATABASE_DESIGN.md` → `DATABASE_SCHEMA.md` → `backend/docs/SOURCE_LAYOUT.md` |
| **3** | 2 h | `BUILD_GUIDE.md` + `LOCAL_DEVELOPER_SETUP.md` → create `key.properties`, `.env` |
| **Before deploy** | | `LAB_DEPLOYMENT_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md`, `VERIFICATION_CHECKLIST.md` |
| **Before Play Store** | | `ANDROID_RELEASE_AND_PLAY_STORE.md` |

**Operators / field crews**: `FIELD_SURVEY_SOP.md` only — skip ML research files.

---

## Do you need to understand every source file?

**No** — that is not how Google, Amazon, or Microsoft run handovers.

| Layer | What to know | Where |
|-------|--------------|-------|
| **System story** | Request flow, data flow (BLE → pending → transfer), auth, deploy | `ARCHITECTURE.md`, `HANDOFF.md` §8 |
| **Find anything** | Directory counts, feature map | `CODEBASE_INVENTORY.md`, `SOURCE_LAYOUT.md` |
| **Change a feature** | One module guide + matching route/service files | Module guide + `API_REFERENCE.md` |
| **Database** | Table purposes, design rationale, migration order | `DATABASE_DESIGN.md`, `DATABASE_SCHEMA.md` |
| **Long tail** | Look up when needed | Tests, one-off scripts, research tier |

Rough scale: ~380 tracked source files; **~12 backend + frontend files** explain ~80% of production behavior (listed in `ARCHITECTURE.md` §4 and `HANDOFF.md` §8).

As the **original author**, you do **not** need to recite every file in a face-to-face session. Western practice: **docs + runnable demo + Q&A**, not a line-by-line code review.

---

## Does Western documentation include database, frontend, and backend?

**Yes**, at the appropriate depth:

| Area | Documented? | Primary docs |
|------|-------------|--------------|
| PostgreSQL schema & migrations | Yes | `DATABASE_DESIGN.md`, `DATABASE_SCHEMA.md`, `DATABASE_NORMALIZATION.md` |
| Backend routes / services / middleware | Yes | `API_REFERENCE.md`, `backend/docs/SOURCE_LAYOUT.md`, OpenAPI |
| Flutter screens / services | Yes (by feature) | `ARCHITECTURE.md` §5, `CODEBASE_INVENTORY.md`, module guides |
| Local secrets & build files | Yes | `LOCAL_DEVELOPER_SETUP.md`, `BUILD_GUIDE.md`, `HANDOFF_SECRETS_CHECKLIST.md` |
| Play Store / release signing | Yes | `ANDROID_RELEASE_AND_PLAY_STORE.md` |
| VM-specific IPs & passwords | **No** (local ops log only) | Not in git — merged into runbook after school verification |

Big-tech pattern: **schema and migration index in git**; production row data never in git.

---

## Can the next team develop from docs alone?

**Yes**, if they also have:

1. Toolchain installed (Flutter, Node, PostgreSQL or remote DB)
2. Secrets created per `HANDOFF_SECRETS_CHECKLIST.md` (`.env`, `key.properties`, Maps keys)
3. GitHub write access to `icmnlab` repos

**Not in git** (by design): passwords, keystores, school VM console steps until Phase 4 runbook is finalized.

After reading, **validate by running**:

```bash
# Backend
cd tree-project-backend && npm ci && node scripts/migrate.js && npm start

# Frontend
cd tree-project-frontend && flutter pub get && flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api   # emulator example
```

Green CI + local run = documentation matches code.

---

## Document tiers (what to skip)

| Tier | Examples | When to read |
|------|----------|--------------|
| **Production** | ARCHITECTURE, HANDOFF, module guides, runbooks | Always |
| **Experimental** | EXPERIMENTAL_FEATURES, VISUAL_MEASUREMENT, AI_* | When enabling flags |
| **Research** | DBH_*_RESEARCH, external GNSS | Thesis / history only — see `RESEARCH_REFERENCE.md` |

---

## In-person handover vs GitHub docs

| In GitHub | Local only (never push) |
|-----------|-------------------------|
| Architecture, API, DB schema, build, verification | `project_code/docs/DEPLOYMENT_LOG.md` |
| Generic deployment runbook (`LAB_DEPLOYMENT_GUIDE.md`) | `REDEPLOY_MANUAL.md`, `COMMANDS_CHEATSHEET.md` |
| Secrets **templates** (`.env.example`, `key.properties.example`) | Actual passwords, webhook secrets, VM accounts |
| `HANDOVER_CHECKLIST.md` sign-off | Face-to-face talk track (`HANDOVER_SCRIPT.md`) |

Recipient long-term source of truth = **GitHub `docs/`**. Live session = walk through hub + one end-to-end demo + assign homework from `HANDOVER_CHECKLIST.md`.

---

## Related

- [`DOCUMENTATION_COVERAGE.md`](./DOCUMENTATION_COVERAGE.md) — coverage audit
- [`HANDOVER_CHECKLIST.md`](./HANDOVER_CHECKLIST.md) — sign-off items
- [`LOCAL_DEVELOPER_SETUP.md`](./LOCAL_DEVELOPER_SETUP.md) — files each developer creates locally
