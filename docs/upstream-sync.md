# Upstream Sync Rules — Custom Fork of GOWA (MANDATORY)

> Applies to EVERY agent (AI or human) operating on this repository.
> Read this fully before any `git fetch` / `git merge` / `git pull` that
> involves the remote `upstream`. Violating these rules can silently wipe
> local customizations. Helper: `scripts/upstream-sync.sh` automates this
> procedure end to end.

## Repository topology

| Remote | URL | Role |
|---|---|---|
| `origin` | `git@github.com:thepeakconnoisseurs/gowa-api.git` | Team fork — backup / collaboration target. Pushing requires explicit user approval. |
| `upstream` | `https://github.com/aldinokemal/go-whatsapp-web-multidevice.git` | Original developer's repo — the ONLY source of updates. Never push here. |

Branch `main` on this clone IS the custom branch: it carries the team's
customizations on top of upstream history (local lineage: `d7440c8`
"chore: configure deployment and ignore local tooling dirs", plus merge
commits `6ae4c23`, `228c337`, `ae13f6e`).

## Custom-file inventory (the identifier)

These are the ONLY paths where this fork intentionally diverges from
upstream. Anything not on this list should follow upstream.

| Path | Local authority | What must survive every sync |
|---|---|---|
| `docker-compose.yml` | FULL local | `container_name: gowa-api`, image tag `gowa-api:latest`, bind `127.0.0.1:3500:3000`, networks `n8n-tpc` (external) + `gowa-api` (bridge), json-file logging caps |
| `.gitignore` | UNION | local entries `.agents`, `_bmad` (note: `.claude`, `src/gowa` etc. already exist upstream) |
| `docs/*.md` generated set (index, project-overview, architecture, api-contracts-gowa, data-models-gowa, source-tree-analysis, component-inventory, development-guide, deployment-guide, project-scan-report.json) | FULL local | Identifier snapshot of the fork's customized state (committed `b34f816`). Upstream never has these filenames; keep them on conflicts. |
| `src/.env` | never in git | gitignored; never commit, never overwrite |

Identifier sources when re-deriving this list: local commit log
(`git log --merges`, author-committed non-merge commits), this document,
and the generated docs set above.

## Why a clean merge can still destroy customizations (READ THIS)

Three-way merge semantics: for each file, git compares ours / base
(merge-base) / theirs.

- ours changed + theirs changed -> conflict (visible, safe-ish).
- ours changed + theirs unchanged -> ours kept (safe).
- **ours unchanged since base + theirs changed -> THEIRS IS TAKEN
  SILENTLY.** If the customized value was already recorded in the base
  (it is, right after a previous protected merge), the next upstream
  change to that file replaces the customization WITHOUT any conflict
  marker. This is not an error — it is correct 3-way merge behavior.
  `.gitattributes merge=ours` does NOT protect this case (merge drivers
  only run when both sides changed).

Therefore: the restore + verify steps below are MANDATORY EVEN WHEN the
merge reports "Automatic merge went well".

## Mandatory procedure (manual)

1. **Pre-flight.** Require a clean tree (`git status --porcelain` empty).
   Create a rollback point: `git branch backup/pre-upstream-sync-<date> HEAD`.
2. **Fetch.** `git fetch upstream --prune`. Never `git pull` (it hides steps).
3. **Assess.** `git merge-base HEAD upstream/main` as BASE, then:
   - `git log --oneline HEAD..upstream/main` — what is incoming;
   - `git diff --name-only $BASE upstream/main` — which files change;
   - intersect that list with the custom-file inventory above.
4. **Merge, uncommitted.** `git merge --no-ff --no-commit upstream/main`.
   Resolve genuine conflicts in NON-custom files by taking upstream
   (upstream is authoritative for everything not in the inventory).
5. **Restore local authority (MANDATORY, even if step 4 was clean):**
   `git restore --source=HEAD --staged --worktree -- docker-compose.yml`
   For `.gitignore`: keep the merged result, but re-append any of
   `.agents`, `_bmad` that went missing (union semantics).
6. **Verification gate (MANDATORY, before committing):**
   - `grep '127.0.0.1:3500:3000' docker-compose.yml`
   - `grep 'n8n-tpc' docker-compose.yml`
   - `grep 'container_name: gowa-api' docker-compose.yml`
   - `grep -x '.agents' .gitignore && grep -x '_bmad' .gitignore`
   Any miss -> fix or abort; do NOT commit a failing state.
7. **Commit** the merge; the message must state that local customizations
   were preserved and list any upstream changes to protected files that
   were intentionally skipped.
8. **Validate.** Run `go test ./...` and `go vet ./...` from `src/` (or
   `docker compose build` when no Go toolchain exists) before declaring done.

## Forbidden operations (any of these can wipe the custom branch)

- `git merge/pull -X theirs` or `-X ours` (global strategy options)
- `git checkout upstream/main -- <path>` / `git restore --source=upstream/main`
- `git reset --hard upstream/main` (or any hard reset past local commits)
- Rebasing `main` onto `upstream/main`; `git push --force` to origin
- Merging with a dirty working tree
- Pushing anything to `upstream` (read-only remote)

## Keeping this document true

When you add a NEW locally customized file, you MUST in the same change:
add it to the inventory table, add it to `PROTECTED_PATHS` (or the
`.gitignore` union list) in `scripts/upstream-sync.sh`, and add a
verification marker. An inventory entry without an enforced marker is a
rule that will be violated eventually.

## Rollback

If a sync goes wrong before committing: `git merge --abort`.
After committing: `git reset --hard backup/pre-upstream-sync-<date>`
(backup branches are listed by `git branch --list 'backup/*'`).

## Sync log

| Date | Upstream range | Result | Notes |
|---|---|---|---|
| 2026-06-21 | ..`e567365` | clean (ort) | merge `6ae4c23` |
| 2026-07-16 | `e567365`..`ed6403a` | clean (ort) | merge `228c337`; upstream deleted `docs/agent-progress.md` in `3a9a18a` |
| 2026-10-25 | `ed6403a`..`5e17e8c` (v9.2.2 -> v9.7.0, 112 commits) | clean, protected files verified | merge `ae13f6e`; `.gitignore` union kept local `.agents`/`_bmad`, accepted upstream `.mcp.json`; `docker-compose.yml` untouched by upstream; docs set committed at `b34f816`; backup branch `backup/pre-upstream-sync-20261025` |
