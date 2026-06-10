#!/usr/bin/env bash
# Regression test for git-derive-docs.sh (issue #1552).
# Plants a tiny git repo with controlled feat/fix/docs commits and asserts the
# commit-convention frequencies tally correctly, file-naming aggregation works,
# and dependency/migration signals are detected. Fully offline.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
derive_script="${script_dir}/../git-derive-docs.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run git-derive-docs tests (jq parity with sibling tests)"
  exit 0
fi

[ -f "$derive_script" ] || fail "git-derive-docs.sh not found at $derive_script"

repo="$(mktemp -d)"
trap 'rm -rf "$repo"' EXIT

git -C "$repo" init -q
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config commit.gpgsign false

commit() {
  local subject="$1"; shift
  for f in "$@"; do
    mkdir -p "$repo/$(dirname "$f")"
    echo "x" >> "$repo/$f"
    git -C "$repo" add "$f"
  done
  git -C "$repo" commit -q -m "$subject"
}

# 3 feat, 2 fix, 1 docs, 1 migration-language refactor, 1 dependency commit.
commit "feat(api): add endpoint" "src/api/routes.ts"
commit "feat(api): add handler" "src/api/handler.ts"
commit "feat(ui): add button" "src/ui/button.ts"
commit "fix(api): null guard" "src/api/routes.ts"
commit "fix(ui): layout bug" "src/ui/button.ts"
commit "docs(readme): update install" "README.md"
commit "refactor(core): migrate from foo to bar" "src/core/lib.ts"
commit "chore(deps): upgrade typescript" "package.json"

out="$(bash "$derive_script" --project-dir "$repo" --depth 50)"

# Commit-convention tallies.
echo "$out" | grep -q "^CONV_feat=3$" \
  || fail "expected CONV_feat=3, got:\n$(echo "$out" | grep '^CONV_feat=')"
pass "feat commit-convention frequency tallied (3)"

echo "$out" | grep -q "^CONV_fix=2$" \
  || fail "expected CONV_fix=2, got:\n$(echo "$out" | grep '^CONV_fix=')"
pass "fix commit-convention frequency tallied (2)"

echo "$out" | grep -q "^CONV_docs=1$" \
  || fail "expected CONV_docs=1, got:\n$(echo "$out" | grep '^CONV_docs=')"
echo "$out" | grep -q "^CONV_refactor=1$" \
  || fail "expected CONV_refactor=1, got:\n$(echo "$out" | grep '^CONV_refactor=')"
echo "$out" | grep -q "^CONV_chore=1$" \
  || fail "expected CONV_chore=1, got:\n$(echo "$out" | grep '^CONV_chore=')"
pass "docs/refactor/chore conventions each tallied (1 each)"

# File-naming aggregation: src/api touched most → should appear as a DIR_ entry.
echo "$out" | grep -qE "^DIR_[0-9]+=src/api$" \
  || fail "expected a DIR_ entry for src/api, got:\n$(echo "$out" | grep '^DIR_')"
pass "file-naming aggregation surfaces top directory (src/api)"

# Extension distribution: .ts is the dominant added extension.
echo "$out" | grep -qE "^EXT_ts=[0-9]+$" \
  || fail "expected EXT_ts entry, got:\n$(echo "$out" | grep '^EXT_')"
pass "added-file extension distribution surfaces .ts"

# Dependency + migration signals.
echo "$out" | grep -q "^DEP_MANIFEST_COMMITS=1$" \
  || fail "expected DEP_MANIFEST_COMMITS=1, got:\n$(echo "$out" | grep '^DEP_MANIFEST_COMMITS=')"
pass "dependency-manifest commit detected (package.json)"

migration=$(echo "$out" | grep "^MIGRATION_COMMITS=" | cut -d= -f2)
[ "$migration" -ge 2 ] 2>/dev/null \
  || fail "expected MIGRATION_COMMITS>=2 (migrate + upgrade), got: $migration"
pass "migration/upgrade language detected (${migration} commits)"

# Trailer invariants.
echo "$out" | grep -q "^=== GIT DERIVE DOCS ===$" || fail "missing section header"
echo "$out" | grep -q "^=== END GIT DERIVE DOCS ===$" || fail "missing section footer"
echo "$out" | grep -q "^STATUS=OK$" || fail "expected STATUS=OK"
echo "$out" | grep -q "^ISSUE_COUNT=0$" || fail "expected ISSUE_COUNT=0"
pass "structured-output trailers present, STATUS=OK"

# Non-repo path errors cleanly.
nonrepo="$(mktemp -d)"
nrout="$(bash "$derive_script" --project-dir "$nonrepo" 2>&1)"
nrcode=$?
rm -rf "$nonrepo"
echo "$nrout" | grep -q "^GIT_REPO=false$" \
  || fail "expected GIT_REPO=false on non-repo path, got:\n$nrout"
[ "$nrcode" -ne 0 ] || fail "expected non-zero exit on non-repo path"
pass "non-repo path reports GIT_REPO=false and exits non-zero"

echo "ALL TESTS PASSED"
