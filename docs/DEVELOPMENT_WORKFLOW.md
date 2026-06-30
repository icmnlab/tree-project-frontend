# Development Workflow

How to develop, test, review, and merge changes — GitHub Flow + CI gates.

**Last reviewed**: 2026-06-30  
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

**Author policy (lab handover)**: commit from a **terminal** with `git commit -m "..."` only. Do **not** add `Co-authored-by: Cursor` or other AI trailers. Avoid Cursor IDE's built-in commit UI if it injects co-author lines.

**Author policy (lab handover)**: commit from a **terminal outside Cursor** with `git commit --no-verify -m "..."`. Verify with `git log -1 --format=%B` — no `Co-authored-by: Cursor` line. Do not use Cursor's Source Control commit button if it injects AI trailers.

---

## Git identity — whose contribution is it?

**Question**: If I clone `icmnlab/tree-project-*` and push as a collaborator, do commits count as someone else?

**No.** GitHub attributes each commit to the **author on the commit object**, set by **your local** `git config`:

```powershell
git config user.name    # e.g. anita
git config user.email   # e.g. anita.likebear@gmail.com
```

| What | Who it affects |
|------|----------------|
| `origin` URL = `https://github.com/icmnlab/...` | Where code is pushed (the **org repo**) — correct for everyone |
| `git config user.name` / `user.email` | **Your name** on commits and GitHub contribution graph |
| GitHub login used for `git push` | Must be a **collaborator** with write access — can differ from commit email |

**Requirements for GitHub to link commits to your profile**:

1. `user.email` matches a **verified email** on your GitHub account (or your `@users.noreply.github.com` address).
2. You push branches / merge PRs under **your** GitHub user (e.g. `anita`), not the org account.

**Using `origin` instead of `icmnlab` remote name**: Anita's setup already has `origin` → `icmnlab` — all commands below use `origin`; no second remote required.

---

## Existing clone — first sync (already at `D:\treeproject`)

For collaborators who **already cloned** before PR merges (typical handover):

### Backend (`D:\treeproject\tree-project-backend`)

```powershell
cd D:\treeproject\tree-project-backend
git remote -v          # expect origin → icmnlab/tree-project-backend
git fetch origin
git status             # expect: on main, clean (as of 2026-06-30 handover)
git pull origin main   # sync to merge commit 0bce9f6 (webhook smoke test) or newer
```

**Why pull?** — GitHub `main` moved after PR #1; local was "up to date" only until someone merged on the web.

### Frontend (`D:\treeproject\tree-project-frontend`)

```powershell
cd D:\treeproject\tree-project-frontend
git remote -v          # expect origin → icmnlab/tree-project-frontend
git fetch origin
git pull origin main   # sync PR #1 merge (map detail fix) + later commits

# Discard Flutter auto-generated noise (do NOT commit):
git restore linux/flutter/ macos/Flutter/ windows/flutter/
git status             # should be clean

flutter pub get
```

**If `assets/images/` error after pull**: ensure `main` includes `assets/images/.gitkeep` (chore PR); or `mkdir assets\images` once.

### One-time local files (not in git)

```powershell
cd D:\treeproject\tree-project-frontend\android
copy key.properties.example key.properties
# Edit: set GOOGLE_MAPS_API_KEY (Maps); signing fields optional for debug
```

See `LOCAL_DEVELOPER_SETUP.md` — **do not create** `pubspec.yaml` (already in repo).

### Build APK pointing at lab VM

```powershell
cd D:\treeproject\tree-project-frontend
flutter build apk --release `
  --dart-define=API_BASE_URL=https://vm121-standard-pc-i440fx-piix-1996.tail146e6a.ts.net/api `
  --dart-define=SELF_SIGNED_TRUSTED_HOSTS=.ts.net
```

App login: **管理員登入** → username `admin_icmnlab` (not display name).

---

## Daily loop (after initial sync)

```
1. git pull origin main
2. git checkout -b feat/my-change
3. Code + flutter test / node tests/runner.js
4. git add <files>
5. git commit --no-verify -m "feat: short description"
6. git log -1 --format=%B    # confirm no Co-authored-by
7. git push -u origin feat/my-change
8. GitHub → Open PR → CI green → Merge
9. git checkout main && git pull origin main
```

**Local WIP when pulling**: `git stash` → `git pull origin main` → `git stash pop`.

**Backend merge to `main`** → lab VM webhook runs `deploy.sh` (after Funnel targets `:3000` and webhook Secret matches — see local `DEPLOYMENT_LOG.md` §I.5).

---

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
2. `git config user.name` + `user.email` — **your** identity ([Git identity](#git-identity--whose-contribution-is-it))  
3. Clone **or** [Existing clone — first sync](#existing-clone--first-sync-already-at-dtreeproject) if already at `D:\treeproject`  
4. `LOCAL_DEVELOPER_SETUP.md` — `key.properties`; optional backend `.env` for local server  
5. This file — [Daily loop](#daily-loop-after-initial-sync)  
6. `ONBOARDING_READING_PATH.md` — full doc map  

Lab VM ops: local `project_code/docs/DEPLOYMENT_LOG.md` §I–J (not in git).

### First push exercise (recommended for handover)

Purpose: verify GitHub access, CI, and (backend) webhook deploy before real feature work.

**Important**: Opening or merging a PR on GitHub does **not** require a local `git pull` first. Pull locally only when you need to build, run tests, or start new work after a merge.

**Backend (triggers lab VM deploy on merge to `main`):**

```bash
git clone https://github.com/icmnlab/tree-project-backend.git
cd tree-project-backend
git checkout -b chore/my-first-push
# edit docs/README.md — add one line under "Last updated"
git add docs/README.md
git commit --no-verify -m "docs: handover first-push marker"
git log -1 --format=%B
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

**Local `git status` noise**: after `flutter pub get`, `linux/` / `macos/` / `windows/` `generated_plugin_*` files may show as modified — run `git restore` on those paths; do not commit them.

**Webhook `Invalid signature` in PM2 logs**: GitHub Webhook **Secret** must exactly match VM `DEPLOY_WEBHOOK_SECRET` in `/opt/tree-app/backend/.env`, then `pm2 reload tree-backend --update-env`. See local ops log `project_code/docs/DEPLOYMENT_LOG.md` §I.5.

**After backend merge**: SSH to VM → `tail -n 20 /opt/tree-app/logs/deploy.log` or `GET /webhook/status` with `X-Admin-Token`.

---

## Related files (source of truth)

| File | Role |
|------|------|
| `frontend/.github/workflows/ci.yml` | Frontend CI definition |
| `backend/.github/workflows/ci.yml` | Backend CI definition |
| `backend/tests/FRAMEWORK.md` | How to write integration tests |
| `HANDOFF.md` §5–§6 | Extended troubleshooting, deploy, git auth |
