# Development Workflow

How to develop, test, review, and merge changes — GitHub Flow + CI gates.

**Last reviewed**: 2026-06-29  
**Related**: `HANDOFF.md` §4–§6 · `LOCAL_DEVELOPER_SETUP.md` · `backend/tests/FRAMEWORK.md`

---

## Summary

| Topic | Policy |
|-------|--------|
| Branching | **GitHub Flow** — only long-lived branch is `main` |
| Feature branches | `feat/*`, `fix/*`, `chore/*` — create when you start work |
| Merge | Pull Request → **CI green** → merge (protected `main`) |
| Deploy | Merge to `main` triggers webhook deploy (when configured) |
| Docs | Update module guide + `API_REFERENCE.md` when routes/behavior change |

Western practice: **this file + `.github/workflows/ci.yml`** — we document *what CI enforces*, not a copy of every YAML line.

---

## Daily development loop

```
1. git pull origin main
2. git checkout -b feat/my-change
3. Code + local tests (see below)
4. git commit → git push -u origin feat/my-change
5. Open Pull Request on GitHub
6. Wait for CI (both repos if you changed both)
7. Review → Merge to main
8. git checkout main && git pull
```

**Two repos**: frontend and backend are separate. If a feature touches both, open **two PRs** or one coordinated pair; merge backend first if API contract changes.

---

## Local verification (before PR)

### Backend

```bash
cd tree-project-backend
npm ci
cp .env.example .env          # fill DATABASE_URL, JWT_SECRET
node scripts/migrate.js
node scripts/seed_dev_users.js   # dev only — admin/12345
npm start                        # :3000
# another terminal:
node tests/runner.js             # 89 integration cases
```

Optional: `node tests/runner.js --section=contracts` for faster subset.

### Frontend

```bash
cd tree-project-frontend
flutter pub get
flutter analyze                  # advisory locally; CI runs with || true
flutter test                     # 435 cases
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

See `LOCAL_DEVELOPER_SETUP.md` for `key.properties` and Maps key.

---

## Pull Request checklist

- [ ] Scope matches branch name (`feat/` vs `fix/`)
- [ ] Local tests pass (or same subset CI runs)
- [ ] No secrets in diff (`.env`, `key.properties`, passwords)
- [ ] API change → `API_REFERENCE.md` + `node scripts/generate_openapi.js` (backend)
- [ ] Schema change → new `NN_*.pg.sql` in `migrate.js` list + `DATABASE_SCHEMA.md` if new table
- [ ] Behavior change → relevant module guide (e.g. `SURVEY_HISTORY.md`)

---

## CI (GitHub Actions)

**Triggers**: `push` and `pull_request` to `main` (both repos).

### Frontend — `.github/workflows/ci.yml`

| Step | What it does |
|------|----------------|
| Checkout | Clone repo |
| Setup Flutter | stable channel, cached |
| `flutter pub get` | Resolve dependencies |
| `flutter analyze` | Static analysis — **advisory** (`|| true`, does not fail CI) |
| `flutter test` | **435** unit/widget tests — **must pass** |

No backend, no secrets in workflow file.

### Backend — `.github/workflows/ci.yml`

| Step | What it does |
|------|----------------|
| Service `postgres:15` | Ephemeral test database |
| `npm ci` | Locked dependencies |
| `node scripts/migrate.js` | Full schema on empty DB |
| `node scripts/seed_dev_users.js` | Test account `admin/12345` |
| Start `node app.js` | Wait for `/health` on port 3001 |
| `node tests/runner.js` | **89** tests (invariants + contracts + journeys) |
| Stop server | Always runs cleanup |

**CI-only env vars** (set in workflow, not for production):

| Variable | Why |
|----------|-----|
| `DB_SSL=false` | Local Postgres service has no SSL |
| `DISABLE_RATE_LIMIT=true` | Hundreds of requests in one job |
| `OPENAI_API_KEY` / `GEMINI_API_KEY` | Dummy strings — AI modules load at boot; tests do not call AI |
| `JWT_SECRET=ci-test-secret` | Fixed secret for test login |

### What CI does *not* do

- Build release APK/AAB
- Deploy to lab VM
- Run `ml_service` Python tests
- Flutter integration against live server (frontend tests are isolated)

Add those only if product needs them (e.g. release workflow on git tag — see `BUILD_GUIDE.md` CI example).

---

## Branch protection (recommended on `icmnlab`)

| Rule | Purpose |
|------|---------|
| Require PR before merge | No direct push mistakes on `main` |
| Require status checks | `frontend-ci` / `backend-ci` jobs green |
| No force push | Preserve history |

Configure: GitHub repo → Settings → Branches → branch protection rule for `main`.

---

## Commit messages

Follow existing repo style — short imperative subject, optional body:

```
feat: add maintenance lock TTL warning
fix: reject transfer when GPS missing
docs: update DATABASE_DESIGN FAQ
chore: regenerate openapi.yaml
```

---

## Database changes

| Environment | Command |
|-------------|---------|
| Dev / CI fresh DB | `node scripts/migrate.js` |
| Production / lab VM | `node scripts/run_pending_migrations.js` only |

Never run full `migrate.js` on production with survey data unless you intend a full rebuild.

---

## Release vs continuous deploy

| Path | When |
|------|------|
| **Backend** | Merge `main` → webhook → `deploy.sh` (when webhook configured) |
| **Android APK** | Manual `flutter build apk` per `BUILD_GUIDE.md` |
| **Play Store** | Manual AAB per `ANDROID_RELEASE_AND_PLAY_STORE.md` |

CI validates quality; it does not publish mobile apps.

### Lab VM webhook smoke test (first-time handover)

After Funnel + GitHub Webhook are configured on the lab VM:

1. Open a small PR on `icmnlab/tree-project-backend` (e.g. `docs:` one-line change).
2. Merge to `main` after CI passes.
3. On VM: `curl -s -H "X-Admin-Token: …" https://<vm>.ts.net/webhook/status` and `tail /opt/tree-app/logs/deploy.log`.

See local ops log `project_code/docs/DEPLOYMENT_LOG.md` §G.4 for full checklist (not in git).

---

## New team member onboarding

1. Collaborator invite on both `icmnlab` repos  
2. `git config` identity + first push auth (`HANDOFF.md` §6.3)  
3. `LOCAL_DEVELOPER_SETUP.md`  
4. This file — daily loop  
5. `ONBOARDING_READING_PATH.md` — full doc map  

### First push exercise (recommended for handover)

Purpose: verify GitHub access, CI, and (backend) webhook deploy before real feature work.

**Backend (triggers lab VM deploy on merge to `main`):**

```bash
git clone https://github.com/icmnlab/tree-project-backend.git
cd tree-project-backend
git checkout -b chore/my-first-push
# edit docs/README.md — add one line under "Last updated"
git add docs/README.md
git commit -m "docs: handover first-push marker"
git push -u origin chore/my-first-push
# GitHub → Open Pull Request → wait for CI → Merge
```

**Frontend (CI only; rebuild APK separately after merge):**

```bash
git clone https://github.com/icmnlab/tree-project-frontend.git
cd tree-project-frontend
git checkout -b chore/my-first-push
# edit docs/README.md similarly
git push -u origin chore/my-first-push
# PR → CI (flutter test) → merge
```

**Rules**: never commit `.env`, passwords, `key.properties`, or lab IPs in public docs. Server secrets live only on VM `.env` and GitHub Webhook settings.

**After backend merge**: SSH to VM → `tail -n 20 /opt/tree-app/logs/deploy.log` or `GET /webhook/status` with `X-Admin-Token`.

---

## Related files (source of truth)

| File | Role |
|------|------|
| `frontend/.github/workflows/ci.yml` | Frontend CI definition |
| `backend/.github/workflows/ci.yml` | Backend CI definition |
| `backend/tests/FRAMEWORK.md` | How to write integration tests |
| `HANDOFF.md` §5–§6 | Extended troubleshooting, deploy, git auth |
