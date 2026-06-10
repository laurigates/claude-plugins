#!/usr/bin/env bash
# Regression test for blueprint-feature-tracker-sync.sh (issue #1553).
# Plants a feature-tracker.json plus a tiny git repo (the injectable
# --project-dir seam) and asserts the semantic invariants:
#   - a not_started feature whose listed implementation files all exist on
#     disk (with a commit) is backfilled UP to complete, and its commit SHA
#     is merged into implementation.commits;
#   - the never-downgrade guard keeps a feature already marked in_progress
#     from being lowered even though its files do not exist;
#   - the statistics rollup counts the backfilled state.
# Exit 0 on success, non-zero on failure. SKIP (exit 0) if git/jq absent.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sync_script="${script_dir}/../blueprint-feature-tracker-sync.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run blueprint-feature-tracker-sync tests"
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed; cannot run blueprint-feature-tracker-sync tests"
  exit 0
fi

[ -f "$sync_script" ] || fail "blueprint-feature-tracker-sync.sh not found at $sync_script"

proj="$(mktemp -d)"
home="$(mktemp -d)"
trap 'rm -rf "$proj" "$home"' EXIT

git -C "$proj" init -q
git -C "$proj" config user.email "test@example.com"
git -C "$proj" config user.name "Test"
git -C "$proj" config commit.gpgsign false

mkdir -p "${proj}/docs/blueprint" "${proj}/src"

# FR-001: not_started but its single implementation file exists -> backfill to complete.
# FR-002: already in_progress, its files do NOT exist -> never-downgrade guard holds.
cat > "${proj}/docs/blueprint/feature-tracker.json" <<'JSON'
{
  "project": "fixture",
  "features": [
    {
      "id": "FR-001",
      "status": "not_started",
      "implementation": { "files": ["src/login.js"], "commits": [] }
    },
    {
      "id": "FR-002",
      "status": "in_progress",
      "implementation": { "files": ["src/missing.js"], "commits": [] }
    }
  ]
}
JSON

# Land the FR-001 file with a commit so git log yields a SHA to backfill.
echo "login" > "${proj}/src/login.js"
git -C "$proj" add docs/blueprint/feature-tracker.json src/login.js
git -C "$proj" commit -q -m "feat(login): implement login"

out="$(bash "$sync_script" --home-dir "$home" --project-dir "$proj")"

# Invariant 1: the not_started feature with existing evidence is backfilled up.
echo "$out" | grep -q "^EVIDENCE_FLIPPED=1$" \
  || fail "expected EVIDENCE_FLIPPED=1, got:\n$out"
echo "$out" | grep -q "TYPE=status_inferred FR=FR-001 FROM=not_started TO=complete" \
  || fail "expected FR-001 inferred not_started->complete, got:\n$out"
pass "implemented-evidence backfills not_started feature up to complete"

# Invariant 2: the commit SHA is merged into FR-001 implementation.commits.
fr1_commits="$(jq '[.features[] | select(.id=="FR-001") | .implementation.commits[]] | length' \
  "${proj}/docs/blueprint/feature-tracker.json")"
[ "$fr1_commits" -ge 1 ] \
  || fail "expected FR-001 to have >=1 backfilled commit, got $fr1_commits"
fr1_status="$(jq -r '.features[] | select(.id=="FR-001") | .status' \
  "${proj}/docs/blueprint/feature-tracker.json")"
[ "$fr1_status" = "complete" ] \
  || fail "expected FR-001 status complete on disk, got $fr1_status"
pass "commit SHA backfilled into implementation.commits and status persisted"

# Invariant 3: the never-downgrade guard keeps in_progress from being lowered.
fr2_status="$(jq -r '.features[] | select(.id=="FR-002") | .status' \
  "${proj}/docs/blueprint/feature-tracker.json")"
[ "$fr2_status" = "in_progress" ] \
  || fail "never-downgrade guard failed: FR-002 should stay in_progress, got $fr2_status"
echo "$out" | grep -q "FR=FR-002" \
  && fail "FR-002 must not be flipped (never-downgrade), but appears in issues:\n$out"
pass "never-downgrade guard keeps a higher status from being lowered"

# Invariant 4: statistics rollup reflects the backfilled state.
echo "$out" | grep -q "^STAT_COMPLETE=1$" \
  || fail "expected STAT_COMPLETE=1, got:\n$out"
echo "$out" | grep -q "^STAT_IN_PROGRESS=1$" \
  || fail "expected STAT_IN_PROGRESS=1, got:\n$out"
echo "$out" | grep -q "^FEATURES_TOTAL=2$" \
  || fail "expected FEATURES_TOTAL=2, got:\n$out"
echo "$out" | grep -q "^COMPLETION_PERCENTAGE=50$" \
  || fail "expected COMPLETION_PERCENTAGE=50, got:\n$out"
pass "statistics rollup counts the backfilled state"

echo "ALL TESTS PASSED"
