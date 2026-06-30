# Development Workflow

How to develop, test, review, and merge changes — GitHub Flow + CI gates.

**Last reviewed**: 2026-06-29 (internal-team GitHub Flow — same as Google/Meta/MS eng on org repos)  
**Related**: `HANDOFF.md` §4–§6 · `LOCAL_DEVELOPER_SETUP.md` · `backend/tests/FRAMEWORK.md`

---

## Summary

| Topic | Policy |
|-------|--------|
| Branching | **GitHub Flow** — only long-lived branch is `main` |
| Feature branches | `feat/*`, `fix/*`, `chore/*` — create when you start work |
| **Contribution model** | **Internal team on org repo** — clone `icmnlab`, push **feature branches**, open **PR** to `main` |
| Remotes | **`origin`** = `icmnlab/tree-project-*` (canonical org repo) |
| Merge | PR → **CI green** → review → merge ( **`main` is protected** — no direct push) |
| Deploy | Merge to `main` triggers webhook deploy (when configured) |
| Docs | Update module guide + `API_REFERENCE.md` when routes/behavior change |

**How big-tech internal teams work** (Google, Meta, Microsoft, Amazon on GitHub/Git-on-Borg): engineers **clone the org repository**, push **short-lived branches** to the **same remote**, and merge via **Pull Request + CI + code review**. Branch protection blocks direct pushes to `main`. **Forking is for open-source external contributors**, not for everyday lab teammates with org access.

**This lab (`icmnlab`)**: add each developer as **org member** or **repo Collaborator (Write)**, enable **branch protection** on `main`, and use the daily loop below. **This file + `.github/workflows/ci.yml`** document what CI enforces.

---

## Repository access (internal team — default)

| Step | Action |
|------|--------|
| 1 | Org admin invites developer to **`icmnlab`** org **or** both repos as **Collaborator (Write)** |
| 2 | Developer accepts invite; uses **their own** GitHub account for `git push` |
| 3 | Admin enables **branch protection** on `main` (PR required, CI required, no force push) |
| 4 | Developer clones **org repo** — `origin` points at `icmnlab` |

```powershell
mkdir D:\treeproject
cd D:\treeproject

git clone https://github.com/icmnlab/tree-project-backend.git
git clone https://github.com/icmnlab/tree-project-frontend.git
```

**Verify:**

```powershell
git remote -v
# origin  https://github.com/icmnlab/tree-project-backend.git (fetch/push)
```

**Rules:**

- **Do** push feature branches: `git push -u origin feat/my-change`
- **Do not** push directly to `main` — branch protection + PR workflow (even if you have Write access)
- Each commit uses **your** `git config user.name` / `user.email` — contributions stay on your profile after merge

---

## Daily development loop

```
1. git pull origin main
2. git checkout -b feat/my-change
3. Code + local tests (see below)
4. git commit --no-verify -m "feat: short description"
5. git log -1 --format=%B    # confirm no Co-authored-by
6. git push -u origin feat/my-change
7. GitHub → Open Pull Request (base main ← compare feat/my-change, same repo)
8. Wait for CI green → review → Merge
9. git checkout main && git pull origin main
```

**Two repos**: frontend and backend are separate. If a feature touches both, open **two PRs** or one coordinated pair; merge backend first if API contract changes.

---

## External contributors (fork — optional)

Use **only** when someone **does not** have `icmnlab` write access (e.g. guest researcher, upstream OSS pattern):

1. Fork `icmnlab/tree-project-*` to their GitHub account  
2. Clone the fork; `git remote add upstream https://github.com/icmnlab/tree-project-*.git`  
3. Push branches to **fork** (`origin`); open PR **from fork** into `icmnlab/main`  

Lab teammates with org/repo access should **not** use fork for daily work — use [Repository access](#repository-access-internal-team--default) instead.

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

## Branch protection (required on `icmnlab`)

| Rule | Purpose |
|------|---------|
| Require PR before merge | **No direct push to `main`** — even team members use feature branches + PR |
| Require status checks | `frontend-ci` / `backend-ci` jobs green before merge |
| No force push | Preserve history |
| (Recommended) Require 1 approval | Code review gate — standard at Google/Meta/Amazon |

Configure: GitHub repo → Settings → Branches → branch protection rule for `main`.

**Write access + protected `main`** is the normal internal-team pattern: you **can** push branches to the org repo; you **cannot** bypass review by pushing to `main`.

---

## Commit messages

Follow existing repo style — short imperative subject, optional body:

```
feat: add maintenance lock TTL warning
fix: reject transfer when GPS missing
docs: update DATABASE_DESIGN FAQ
chore: regenerate openapi.yaml
```

**Author policy (lab handover)**:

- Commit from a **terminal** (PowerShell / bash) with `git commit --no-verify -m "..."`.
- Do **not** add `Co-authored-by: Cursor` or other AI trailers.
- Avoid Cursor IDE's **Source Control → Commit** button if it injects co-author lines.
- After **every** commit, run `git log -1 --format=%B` and confirm the message body has **no** `Co-authored-by:` line (see [Co-authored-by — daily practice](#co-authored-by--daily-practice) below).

**Why `--no-verify`?** — Skips local hooks that some IDE setups attach; does **not** skip GitHub CI on PR.

---

## Git identity — whose contribution is it?

**Question**: If I clone `icmnlab/tree-project-*` and push branches, do commits count as someone else?

**No.** GitHub attributes each commit to the **author on the commit object**, set by **your local** `git config`:

```powershell
git config user.name    # e.g. Your Name
git config user.email   # e.g. you@example.com
```

| What | Who it affects |
|------|----------------|
| `origin` URL = `https://github.com/icmnlab/...` | Org repo — where the team pushes **feature branches** |
| `git config user.name` / `user.email` | **Your name** on commits and GitHub contribution graph |
| GitHub login used for `git push` | Must be a **team member** with repo write access — can differ from commit email |

**Requirements for GitHub to link commits to your profile**:

1. `user.email` matches a **verified email** on your GitHub account (or your `@users.noreply.github.com` address).
2. You push branches and merge PRs under **your** GitHub user, not a shared bot account (unless explicitly agreed).

**Remote naming**: clone from `icmnlab` → default remote name `origin` — used throughout this doc.

---

## New machine — first clone (no repo on disk yet)

Use this on a **new PC** or any machine that has **never** cloned the project. Path examples use `D:\treeproject`; change if you prefer (e.g. `C:\dev\treeproject`).

### 0. Prerequisites (once per machine)

| Tool | Check |
|------|--------|
| Git | `git --version` |
| Flutter 3.x | `flutter doctor` (Android toolchain OK for mobile work) |
| Node 18+ | `node -v` (only if running backend locally) |
| GitHub access | **Org member** or **Collaborator (Write)** on both `icmnlab` repos (see [Repository access](#repository-access-internal-team--default)) |

### 1. Git identity (once per machine — **your** name on commits)

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Use an email **verified on your GitHub account** so contributions appear on your profile. Pushes go to the **org repo** (`icmnlab`); commits still show **your** author identity.

### 2. Clone both org repos

```powershell
mkdir D:\treeproject
cd D:\treeproject

git clone https://github.com/icmnlab/tree-project-backend.git
git clone https://github.com/icmnlab/tree-project-frontend.git
```

**Why two repos?** — Frontend and backend are separate GitHub projects; daily work may touch one or both.

**Verify remotes:**

```powershell
cd D:\treeproject\tree-project-backend
git remote -v    # origin → icmnlab/tree-project-backend

cd D:\treeproject\tree-project-frontend
git remote -v    # origin → icmnlab/tree-project-frontend
```

First `git push` opens browser login (Git Credential Manager) — sign in with **your** GitHub account (must have accepted org/collaborator invite).

### 3. Frontend — dependencies and local secrets

```powershell
cd D:\treeproject\tree-project-frontend
flutter pub get

cd android
copy key.properties.example key.properties
notepad key.properties
```

In `key.properties`, at minimum set **`GOOGLE_MAPS_API_KEY`** (Maps screens). Signing fields can stay as placeholders for debug builds.

**Do not create** `pubspec.yaml` — it is already in the repo.  
**Do not commit** `key.properties`, `.env`, or keystores.

If `flutter pub get` errors on `assets/images/`: `mkdir assets\images` once, or pull `main` after the `assets/images/.gitkeep` chore PR is merged.

### 4. Backend — only if you run the server locally (optional)

Most handover work uses the **lab VM** backend; local backend is optional.

```powershell
cd D:\treeproject\tree-project-backend
copy .env.example .env
notepad .env
# Set DATABASE_URL, JWT_SECRET at minimum — see LOCAL_DEVELOPER_SETUP.md

npm ci
node scripts/migrate.js
node scripts/seed_dev_users.js    # dev DB only — admin/12345
npm start
```

Never use `seed_dev_users.js` against the production lab VM database.

### 5. Verify frontend tests (recommended)

```powershell
cd D:\treeproject\tree-project-frontend
flutter test
```

### 6. Run or build against lab VM

**Debug on device/emulator:**

```powershell
cd D:\treeproject\tree-project-frontend
flutter run -d <device-id> `
  --dart-define=API_BASE_URL=https://vm121-standard-pc-i440fx-piix-1996.tail146e6a.ts.net/api `
  --dart-define=SELF_SIGNED_TRUSTED_HOSTS=.ts.net
```

**Release APK for field testing:**

```powershell
flutter build apk --release `
  --dart-define=API_BASE_URL=https://vm121-standard-pc-i440fx-piix-1996.tail146e6a.ts.net/api `
  --dart-define=SELF_SIGNED_TRUSTED_HOSTS=.ts.net
```

App: **管理員登入** → username `admin_icmnlab`. Empty lab DB — create 專案／區 in the app before field survey.

### 7. Next steps

Continue with [Daily loop (after initial sync)](#daily-loop-after-initial-sync).  
If you later get a second machine that **already** has clones, use [Existing clone — first sync](#existing-clone--first-sync-already-at-dtreeproject) instead of cloning again.

---

## Existing clone — first sync (already at `D:\treeproject`)

For team members who **already cloned** before PR merges:

### Backend (`D:\treeproject\tree-project-backend`)

```powershell
cd D:\treeproject\tree-project-backend
git remote -v          # expect origin → icmnlab/tree-project-backend
git fetch origin
git checkout main
git pull origin main
```

### Frontend (`D:\treeproject\tree-project-frontend`)

```powershell
cd D:\treeproject\tree-project-frontend
git remote -v          # expect origin → icmnlab/tree-project-frontend
git fetch origin
git checkout main
git pull origin main

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
8. GitHub → Open Pull Request (same repo: main ← feat/my-change) → CI green → Merge
9. git checkout main && git pull origin main
```

**Local WIP when pulling**: `git stash` → `git pull origin main` → `git stash pop`.

**Backend merge to `main`** → lab VM webhook runs `deploy.sh` (after Funnel targets `:3000` and webhook Secret matches — see local `DEPLOYMENT_LOG.md` §I.5).

---

## Co-authored-by — daily practice

**Question**: Do I need to check for `Co-authored-by: Cursor` on every commit?

| When | Check? | Why |
|------|--------|-----|
| **After each `git commit`** | **Yes (recommended)** | Cursor / IDE commit UI can inject trailers; one `git log -1 --format=%B` takes 2 seconds |
| **`git pull` / `git status` / start of day** | No | Trailers live on commit objects, not in working tree |
| **Before opening PR** | Optional extra pass | `git log origin/main..HEAD --format=%B` if you used IDE commits on the branch |

**Normal PowerShell flow** (`git commit --no-verify -m "..."`) usually does **not** add co-authors. The check is a safety net when developing inside Cursor.

**If a bad trailer slipped in** (branch not merged yet):

```powershell
# Cursor IDE may inject Co-authored-by even with --no-verify; use commit-tree:
$tree = git rev-parse 'HEAD^{tree}'
$parent = git rev-parse 'HEAD^'
$new = & 'C:\Program Files\Git\bin\git.exe' commit-tree $tree -p $parent -m 'your message without trailer'
git reset --hard $new
git log -1 --format=%B
git push --force-with-lease
```

**If already on `main` and pushed**: leave history as-is for old commits; **new** commits must not add trailers. Lab policy documented in local `DEPLOYMENT_LOG.md` §I.5.2.

---

## After you push a new branch (full checklist)

Use this after step 7 in the [Daily loop](#daily-loop-after-initial-sync): `git push -u origin feat/my-change`.

### On GitHub (web)

| Step | Action | Why |
|------|--------|-----|
| 1 | Open repo → **Compare & pull request** (or `https://github.com/icmnlab/<repo>/compare/main...feat/my-change`) | Push alone does not change `main`; PR is the review + CI gate |
| 2 | Base = **`main`**, compare = **your feature branch** (same repo) | Webhook deploy tracks `main` only |
| 3 | Fill title (imperative, e.g. `fix: resolve species_id on transfer`) + short body (what / why / test plan) | Reviewers and future you rely on PR text |
| 4 | Wait for **CI green** (Actions tab) | Catches broken tests before merge; branch protection should require this |
| 5 | (Optional) Request review from teammate | Human gate — standard internal review |
| 6 | **Merge pull request** → Confirm | Updates `main`; triggers backend deploy webhook when configured |
| 7 | (Optional) **Delete branch** on GitHub | Reduces stale branch clutter |

**You do not need a local `git pull` just to open or merge a PR** — that happens on GitHub. Pull locally when you need to build, test, or start the next branch.

### After merge — by repo

| Repo | What happens automatically | What you do manually |
|------|---------------------------|----------------------|
| **Backend** | GitHub fires **push webhook** → Tailscale Funnel → VM `deploy.sh` (`git pull`, npm, pending migrations, `pm2 reload`) | If deploy fails: fix Funnel target (`http://127.0.0.1:3000`), Webhook Secret, Content type `application/json`; Redeliver in GitHub → check `deploy.log` on VM |
| **Frontend** | CI already ran on PR; merge updates GitHub `main` only | **`flutter build apk --release`** with lab `API_BASE_URL` and distribute APK — CI does not ship mobile builds |

### After merge — on your machine

```powershell
cd D:\treeproject\tree-project-<backend|frontend>
git checkout main
git pull origin main
git branch -d feat/my-change    # optional: delete local branch after merge
```

| Step | Why |
|------|-----|
| `checkout main` | Feature branch is done; `main` is the integration line |
| `pull origin main` | Your disk must match GitHub before the next branch or APK build |
| Delete local branch | Avoid accidentally committing on a merged branch name |

### Verify the change landed

| Change type | Verify |
|-------------|--------|
| Backend API / transfer logic | VM: `tail -n 30 /opt/tree-app/logs/deploy.log` shows new commit hash; `curl http://127.0.0.1:3000/health` |
| Frontend UI | New APK on device; login `admin_icmnlab` + **管理員登入**; retest the user path |
| Docs only | GitHub `main` commit visible; no VM action unless backend docs-only still triggers webhook |

**Two-repo features**: merge **backend first** if the API contract changed; then frontend PR that depends on it.

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

1. Org admin: invite to **`icmnlab`** org **or** both repos as **Collaborator (Write)**; enable **branch protection** on `main`  
2. `git config user.name` + `user.email` — **your** identity ([Git identity](#git-identity--whose-contribution-is-it))  
3. Clone **or** pick one:
   - [New machine — first clone](#new-machine--first-clone-no-repo-on-disk-yet) (new PC)
   - [Existing clone — first sync](#existing-clone--first-sync-already-at-dtreeproject) (`D:\treeproject` already there)  
4. `LOCAL_DEVELOPER_SETUP.md` — `key.properties`; optional backend `.env` for local server  
5. This file — [Daily loop](#daily-loop-after-initial-sync)  
6. `ONBOARDING_READING_PATH.md` — full doc map  

Lab VM ops: local `project_code/docs/DEPLOYMENT_LOG.md` §I–J (not in git).

### First push exercise (recommended for handover)

Purpose: verify GitHub access, CI, and (backend) webhook deploy before real feature work.

**Important**: Opening or merging a PR on GitHub does **not** require a local `git pull` first. Pull locally only when you need to build, run tests, or start new work after a merge.

### First push — scenarios (what can happen)

**Short answer**: Feature branch + `git push -u origin chore/my-first-push` to the **org repo** is standard — **nothing deploys until PR merges to `main`**.

| Situation | What you see | Is it OK? | What to do |
|-----------|--------------|-----------|------------|
| First `git push` ever | Browser opens (Git Credential Manager) | Yes | Sign in with **your** GitHub account |
| Push rejected **403** | `Permission denied` / `Write access not granted` | No (nothing uploaded) | Accept org/collaborator invite; verify `origin` → `icmnlab/...`; Windows Credential Manager → delete `git:https://github.com` → retry |
| Push to **feature branch** | `branch 'feat/x' set up to track 'origin/feat/x'` | **Yes — intended** | Open PR on GitHub; wait for CI |
| Push to **`main`** with branch protection | Rejected by GitHub | **Yes (protection worked)** | Use feature branch + PR instead |
| Push to **`main`** without protection | Updates remote main; webhook may deploy | **Avoid** | Enable branch protection; revert via PR if needed |
| `git push` asks for password | GitHub no longer accepts account passwords for HTTPS | Normal | Use **PAT** as password, or browser login via GCM |
| Wrong `origin` URL | Push to wrong repo | Fix remote | `git remote -v`; `git remote set-url origin https://github.com/icmnlab/tree-project-*.git` |
| After push: "Compare & pull request" | Banner on repo page | Yes | Base `main` ← your branch → Create PR |
| Merge PR | `main` moves; backend VM deploys (if webhook OK) | Yes | `git pull origin main` when you code again |

**Webhook only fires on `main` push** (after merge). Feature-branch pushes run CI on the PR only.

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

## Guided exercise — fix ST-1 `species_id` shows「無」(optional reference)

**Status (2026-07-01)**: **Optional** — not required to close handover. Documented for the **next** developer who touches pending→transfer or species catalog. Original assignee did not run this live; known issue tracked in `HANDOFF.md` §11.3.

**Purpose**: Reference implementation walkthrough for [Daily loop](#daily-loop-after-initial-sync) + [After push](#after-you-push-a-new-branch-full-checklist) on a real bug found during 2026-06-30 field testing.

**When to run**: Before your first species/transfer change, or when fixing ST-* rows with NULL `species_id` in DB.

**Prerequisites**:

| Item | Check |
|------|--------|
| **Collaborator (Write)** or org member on both `icmnlab` repos | GitHub invite accepted |
| `git config user.name` / `user.email` | Your GitHub identity |
| `D:\treeproject` clones with `origin` → `icmnlab` | `git remote -v` |
| Node 18+ (backend tests) | `node -v` |
| Optional: lab VM SSH / Console | For SQL verify after deploy |

Field logs: local `project_code/docs/DEPLOYMENT_LOG.md` §K.

---

### Phase A — Sync and confirm the bug exists

#### A.1 Pull latest `main` (both repos)

**Why**: Fix branch must start from current integration line (includes merged PR #1 on both repos).

```powershell
cd D:\treeproject\tree-project-backend
git fetch origin
git checkout main
git pull origin main

cd D:\treeproject\tree-project-frontend
git fetch origin
git checkout main
git pull origin main
git restore linux/flutter/ macos/Flutter/ windows/flutter/ 2>$null
flutter pub get
```

#### A.2 (Optional) Reproduce on device

Skip if ST-1～ST-3 already exist on lab VM from 2026-06-30 session.

1. Build/run APK with lab API (see [Build APK](#existing-clone--first-sync-already-at-dtreeproject)).
2. **管理員登入** → `admin_icmnlab`.
3. Create 專案／區 → BLE survey → submit 1+ trees.
4. Open tree detail for **ST-1** → **樹種編號** shows「無」 while **樹種名稱** may show 樟 / 測試樹種.

#### A.3 Confirm in DB (VM)

**Why**: Separates UI bug from DB NULL — ST-1 is **`species_id` NULL in DB**, not just stale UI.

```bash
cd /opt/tree-app/backend
set -a && source .env && set +a
psql "$DATABASE_URL" -c "
  SELECT id, system_tree_id, species_id, species_name, dbh_cm
  FROM tree_survey ORDER BY id;"
```

**Before fix**: `species_name` filled, `species_id` NULL or empty.

---

### Phase B — Implement the fix (backend)

#### B.1 Create feature branch

**Why**: Never commit directly to `main`; PR + CI gate.

```powershell
cd D:\treeproject\tree-project-backend
git checkout main
git pull origin main
git checkout -b fix/st-1-species-id-on-transfer
```

#### B.2 Add helper `utils/speciesResolve.js`

**Why**: Transfer lookup was inline and missed `toTraditional` + `species_synonyms`. Central helper matches `normalize_species_traditional.js` §D logic.

Create file `utils/speciesResolve.js`:

```javascript
const { toTraditional } = require('./chineseConvert');

async function tableExists(client, tableName) {
  const r = await client.query(
    `SELECT 1 FROM information_schema.tables
     WHERE table_schema = 'public' AND table_name = $1`,
    [tableName],
  );
  return r.rows.length > 0;
}

/**
 * Resolve tree_species.id for pending → tree_survey transfer.
 * @param {import('pg').PoolClient} client
 * @param {{ speciesName?: string, speciesIdHint?: string }} opts
 * @returns {Promise<string|null>}
 */
async function resolveSpeciesIdForName(client, { speciesName, speciesIdHint } = {}) {
  if (speciesIdHint && String(speciesIdHint).trim()) {
    const hint = String(speciesIdHint).trim();
    const byId = await client.query(
      'SELECT id FROM tree_species WHERE id = $1 LIMIT 1',
      [hint],
    );
    if (byId.rows.length > 0) return byId.rows[0].id;
  }

  if (!speciesName || !String(speciesName).trim()) return null;

  const normalized = toTraditional(String(speciesName).trim());
  if (!normalized) return null;

  const direct = await client.query(
    'SELECT id FROM tree_species WHERE name = $1 OR scientific_name = $1 LIMIT 1',
    [normalized],
  );
  if (direct.rows.length > 0) return direct.rows[0].id;

  if (await tableExists(client, 'species_synonyms')) {
    const syn = await client.query(
      `SELECT ss.canonical_species_id AS id
       FROM species_synonyms ss
       WHERE ss.variant_name = $1
       LIMIT 1`,
      [normalized],
    );
    if (syn.rows.length > 0) return syn.rows[0].id;
  }

  return null;
}

module.exports = { resolveSpeciesIdForName };
```

#### B.3 Wire into transfer — `routes/pending_measurements.js`

**Location**: transfer loop, ~L1004–1018 (search for `// 嘗試查找 species_id`).

**Why**: Replace raw-name-only lookup; also read optional `species_id` from `raw_data_snapshot` (Phase C).

1. Near top of file (with other requires), add:

```javascript
const { resolveSpeciesIdForName } = require('../utils/speciesResolve');
```

2. Replace the inline species lookup block with:

```javascript
      // 嘗試查找 species_id（繁體正規化 + 同義詞 + snapshot hint）
      let speciesId = null;
      const snapshot = parseRawDataSnapshot(p.raw_data_snapshot);
      if (p.species_name || snapshot.species_id) {
        try {
          speciesId = await resolveSpeciesIdForName(client, {
            speciesName: p.species_name,
            speciesIdHint: snapshot.species_id,
          });
        } catch (err) {
          console.warn(`[Transfer] Species lookup failed for ${p.species_name}:`, err.message);
        }
      }
```

**Do not remove** existing `toTraditional(p.species_name)` on INSERT — lookup and stored name stay aligned.

---

### Phase C — Optional frontend belt-and-suspenders

**Why**: Form already calls `_ensureSpeciesId()` but never sends `species_id` to pending; snapshot gives transfer a direct hint.

File: `lib/screens/v3/integrated_tree_form_page.dart`

Before each `_pendingService.updateMeasurement(...)` call, build snapshot merge:

```dart
      final speciesSnapshot = (_speciesId != null && _speciesId!.isNotEmpty)
          ? {'species_id': _speciesId}
          : null;
      final maintenanceSnapshot = _isMaintenance
          ? {'update_tree_location': _updateTreeLocation}
          : null;
      final rawDataSnapshotMerge = {
        if (speciesSnapshot != null) ...speciesSnapshot,
        if (maintenanceSnapshot != null) ...maintenanceSnapshot,
      };
```

Pass `rawDataSnapshotMerge: rawDataSnapshotMerge.isEmpty ? null : rawDataSnapshotMerge` to **all three** `updateMeasurement` calls in `_submitForm` (initial, 409 retry, conflict keepMine).

**If backend-only fix**: skip Phase C; backend helper alone fixes new transfers when synonym/direct name match exists.

**Two PRs**: backend PR first → merge → deploy; then frontend PR + new APK (optional).

---

### Phase D — Local verification

```powershell
cd D:\treeproject\tree-project-backend
npm ci
node scripts/migrate.js
node tests/runner.js
```

**Why `migrate.js`**: CI uses empty Postgres; ensures helper does not break schema assumptions.

**Expect**: 89 tests pass (same as CI). If you add a contract test later, put it under `tests/contracts/`.

Frontend (if Phase C):

```powershell
cd D:\treeproject\tree-project-frontend
flutter test
```

---

### Phase E — Commit, push, PR, merge

```powershell
cd D:\treeproject\tree-project-backend
git add utils/speciesResolve.js routes/pending_measurements.js
git commit --no-verify -m "fix: resolve species_id on pending transfer"
git log -1 --format=%B
git push -u origin fix/st-1-species-id-on-transfer
```

**Check commit message**: no `Co-authored-by:` line.

**GitHub**:

1. Open PR: base `main` ← compare `fix/st-1-species-id-on-transfer`.
2. Title: `fix: resolve species_id on pending transfer`
3. Body template:

```markdown
## Summary
- Add `utils/speciesResolve.js` (toTraditional + species_synonyms + snapshot hint)
- Use in pending → tree_survey transfer

## Test plan
- [ ] `node tests/runner.js` green locally
- [ ] CI green
- [ ] After merge: VM SQL shows species_id for new survey
- [ ] App detail page 樹種編號 not「無」

Fixes ST-1 handover bug (2026-06-30 field test).
```

4. Wait **CI green** → **Merge pull request**.

Follow [After you push a new branch](#after-you-push-a-new-branch-full-checklist) for post-merge steps.

---

### Phase F — After merge: deploy + verify

#### F.1 VM deploy (automatic for backend)

**Why**: Webhook listens to `main` push only.

```bash
tail -n 30 /opt/tree-app/logs/deploy.log
curl -sf http://127.0.0.1:3000/health && echo OK
```

If `deploy.log` unchanged → fix Funnel (`http://127.0.0.1:3000`), Webhook Secret, Redeliver (see `DEPLOYMENT_LOG.md` §I.5).

#### F.2 Backfill existing ST-* rows (no re-survey)

**Why**: Fix applies to **new** transfers; rows already in DB need backfill script §D.

```bash
cd /opt/tree-app/backend
set -a && source .env && set +a
node scripts/normalize_species_traditional.js          # dry-run — read output
node scripts/normalize_species_traditional.js --apply  # writes species_id
psql "$DATABASE_URL" -c "
  SELECT system_tree_id, species_id, species_name FROM tree_survey ORDER BY id;"
```

#### F.3 App verification

1. `git pull origin main` on frontend if you changed Phase C; rebuild APK if needed.
2. Open **ST-1** detail → **樹種編號** should show e.g. `0001`, not「無」.
3. Optional: survey **one new tree** → confirm new row has `species_id` in SQL immediately after transfer.

---

### Phase G — Done checklist (tick before closing exercise)

- [ ] Backend PR merged; VM `deploy.log` shows new commit
- [ ] SQL: all ST-* rows have non-null `species_id` (backfill or re-survey)
- [ ] App: ST-1 樹種編號 visible
- [ ] Local `main` pulled: `git checkout main && git pull origin main`
- [ ] Feature branch deleted (GitHub + local)

---

### Root cause reference (read before coding)

| Layer | Fact |
|-------|------|
| Frontend `integrated_tree_form_page.dart` | `_ensureSpeciesId()` calls `POST /tree_species` and sets `_speciesId` **before** submit |
| Frontend `updateMeasurement()` | Sends **`species_name` only** — not `species_id`; `pending_tree_measurements` has no `species_id` column |
| Backend `pending_measurements.js` transfer (~L1004–1017) | Old code: `WHERE name = $1 OR scientific_name = $1` on **raw** `p.species_name` — **no** `toTraditional`, **no** `species_synonyms` |
| AI identify path | Catalog row may use **scientific name**; UI shows **樟**; synonym in `species_synonyms` but old transfer ignored it |
| Detail page | `_f('species_id','樹種編號')` → NULL displays「無」 |

### Other issues seen same session (not this bug)

| Issue | Log / symptom | Action |
|-------|---------------|--------|
| Cloudinary | `[tree_images] Invalid cloud_name Root` 401 | Set valid `CLOUDINARY_*` in VM `.env`; photos stay local until fixed |
| Google Maps | `animateCamera` PlatformException | Timing/race; lower priority |
| Map detail all「無」 | Fixed frontend PR #1 `47d8cff` | Rebuild APK with current `main` |

Field logs: local `DEPLOYMENT_LOG.md` §K.

---

## Related files (source of truth)

| File | Role |
|------|------|
| `frontend/.github/workflows/ci.yml` | Frontend CI definition |
| `backend/.github/workflows/ci.yml` | Backend CI definition |
| `backend/tests/FRAMEWORK.md` | How to write integration tests |
| `HANDOFF.md` §5–§6 | Extended troubleshooting, deploy, git auth |
