#!/usr/bin/env bash
# upstream-sync.sh - MANDATORY safe sync from upstream for the customized gowa fork.
# Run from anywhere inside the repo: scripts/upstream-sync.sh
# Rules and rationale: docs/upstream-sync.md (read it before editing this script).
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Files whose LOCAL version is authoritative during upstream merges.
PROTECTED_PATHS=(docker-compose.yml)

# .gitignore is union-merged: these local entries must survive every sync.
REQUIRED_GITIGNORE_ENTRIES=(".claude" ".agents" "_bmad")

verify() {
  local fail=0
  grep -q '127\.0\.0\.1:3500:3000' docker-compose.yml      || { echo "VERIFY FAIL: docker-compose.yml lost the 127.0.0.1:3500 bind"; fail=1; }
  grep -q 'n8n-tpc' docker-compose.yml                     || { echo "VERIFY FAIL: docker-compose.yml lost the n8n-tpc network"; fail=1; }
  grep -q 'container_name: gowa-api' docker-compose.yml    || { echo "VERIFY FAIL: docker-compose.yml lost container_name: gowa-api"; fail=1; }
  local e
  for e in "${REQUIRED_GITIGNORE_ENTRIES[@]}"; do
    grep -qx "$e" .gitignore || { echo "VERIFY FAIL: .gitignore lost entry: $e"; fail=1; }
  done
  [ "$fail" -eq 0 ] && echo "VERIFY OK: all custom markers intact"
  return "$fail"
}

[ -z "$(git status --porcelain)" ] || { echo "ABORT: working tree not clean. Commit or stash first."; exit 1; }

echo "== 1/6 fetch upstream =="
git fetch upstream --prune

BASE="$(git merge-base HEAD upstream/main)"
if [ "$(git rev-parse upstream/main)" = "$(git rev-parse "$BASE")" ]; then
  echo "Nothing to merge: upstream/main is already an ancestor of HEAD."
  exit 0
fi

echo "== 2/6 upstream changes touching protected files since ${BASE:0:8} =="
git diff --name-only "$BASE" upstream/main -- "${PROTECTED_PATHS[@]}" .gitignore | sed 's/^/  upstream changed: /' || true

echo "== 3/6 incoming upstream commits (head -30) =="
git log --oneline "HEAD..upstream/main" | head -30

echo "== 4/6 merge --no-ff --no-commit =="
if ! git merge --no-ff --no-commit upstream/main; then
  echo "CONFLICTS raised. Resolve NON-custom files taking upstream, then run:"
  echo "  git restore --source=HEAD --staged --worktree -- ${PROTECTED_PATHS[*]}"
  echo "then the .gitignore union step and verification from docs/upstream-sync.md, then commit."
  exit 1
fi

echo "== 5/6 enforce local authority on protected files (mandatory even when clean) =="
git restore --source=HEAD --staged --worktree -- "${PROTECTED_PATHS[@]}"
MISSING=()
for e in "${REQUIRED_GITIGNORE_ENTRIES[@]}"; do
  grep -qx "$e" .gitignore || MISSING+=("$e")
done
if [ "${#MISSING[@]}" -gt 0 ]; then
  printf '\n# local custom entries (kept by scripts/upstream-sync.sh)\n' >> .gitignore
  printf '%s\n' "${MISSING[@]}" >> .gitignore
  git add .gitignore
  echo "  re-appended .gitignore entries: ${MISSING[*]}"
fi

echo "== 6/6 verification gate =="
if ! verify; then
  echo "ABORT: verification FAILED - merge left uncommitted for inspection (git status). Fix or 'git merge --abort'."
  exit 1
fi

git commit -m "Merge upstream/main (local customizations preserved; see docs/upstream-sync.md)"
echo "DONE. HEAD: $(git log --oneline -1)"
echo "Next: validate with 'cd src && go test ./... && go vet ./...' (or 'docker compose build')."
