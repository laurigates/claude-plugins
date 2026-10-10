#!/usr/bin/env bash
# Regression test for blueprint-feature-tracker-sync.sh (issues #1553, #2867).
# Plants a feature-tracker.json plus a tiny git repo (the injectable
# --project-dir seam) and asserts the semantic invariants:
#   - a not_started feature whose listed implementation files all exist on
#     disk (with a commit) is backfilled UP to complete, and its commit SHA
#     is merged into implementation.commits;
#   - the never-downgrade guard keeps a feature already marked in_progress
#     from being lowered even though its files do not exist;
#   - the statistics rollup counts the backfilled state;
#   - (#2867) an OBJECT-shaped `features` collection (the shape
#     feature-tracker.schema.json declares: FR category -> nested `features`
#     object of FR sub-features) is backfilled through the nested record and
#     written back as an object, not crashed on with STATUS=OK;
#   - (#2867) a tracker whose shape jq cannot process yields STATUS=ERROR and a
#     non-zero exit, and is not rewritten.
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

tmp_root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -n "$tmp_root" && -d "$tmp_root" ]] || { echo "mktemp -d returned no dir" >&2; exit 1; }
trap 'rm -rf "$tmp_root"' EXIT
home="${tmp_root}/home"
mkdir -p "$home"

# new_project <name>: a fresh git repo with docs/blueprint/ and src/.
new_project() {
  local dir="${tmp_root}/$1"
  mkdir -p "${dir}/docs/blueprint" "${dir}/src"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  git -C "$dir" config commit.gpgsign false
  printf '%s' "$dir"
}

proj="$(new_project array)"
[[ -n "$proj" && -d "$proj" ]] || fail "could not create the array fixture project"

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
grep -q "^EVIDENCE_FLIPPED=1$" <<<"$out" \
  || fail "expected EVIDENCE_FLIPPED=1, got:\n$out"
grep -q "TYPE=status_inferred FR=FR-001 FROM=not_started TO=complete" <<<"$out" \
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
grep -q "FR=FR-002" <<<"$out" \
  && fail "FR-002 must not be flipped (never-downgrade), but appears in issues:\n$out"
pass "never-downgrade guard keeps a higher status from being lowered"

# Invariant 4: statistics rollup reflects the backfilled state.
grep -q "^STAT_COMPLETE=1$" <<<"$out" \
  || fail "expected STAT_COMPLETE=1, got:\n$out"
grep -q "^STAT_IN_PROGRESS=1$" <<<"$out" \
  || fail "expected STAT_IN_PROGRESS=1, got:\n$out"
grep -q "^FEATURES_TOTAL=2$" <<<"$out" \
  || fail "expected FEATURES_TOTAL=2, got:\n$out"
grep -q "^COMPLETION_PERCENTAGE=50$" <<<"$out" \
  || fail "expected COMPLETION_PERCENTAGE=50, got:\n$out"
grep -q "^FEATURES_SHAPE=array$" <<< "$out" \
  || fail "expected FEATURES_SHAPE=array, got:\n$out"
[ "$(jq -r '.features | type' "${proj}/docs/blueprint/feature-tracker.json")" = "array" ] \
  || fail "array shape not preserved on write"
pass "statistics rollup counts the backfilled state"

# ── #2867: object-shaped features ────────────────────────────────────────────
# FR1 is a category (no status of its own); FR1.1 is a not_started sub-feature
# whose file exists -> complete; FR1.2 is already in_progress -> untouched.
# FR2 carries its own status and no files. A category is not a record, so
# FEATURES_TOTAL counts FR1.1, FR1.2 and FR2 only.
oproj="$(new_project object)"
[[ -n "$oproj" && -d "$oproj" ]] || fail "could not create the object fixture project"
otracker="${oproj}/docs/blueprint/feature-tracker.json"
cat > "$otracker" <<'JSON'
{
  "version": "1.0.0",
  "features": {
    "FR1": {
      "name": "Authentication",
      "features": {
        "FR1.1": {
          "name": "Login",
          "status": "not_started",
          "phase": "phase-1",
          "implementation": { "files": ["src/login.js"], "commits": [] }
        },
        "FR1.2": {
          "name": "Logout",
          "status": "in_progress",
          "phase": "phase-1",
          "implementation": { "files": ["src/missing.js"], "commits": [] }
        }
      }
    },
    "FR2": {
      "name": "Reporting",
      "status": "blocked",
      "phase": "phase-2",
      "features": {}
    }
  }
}
JSON
echo "login" > "${oproj}/src/login.js"
git -C "$oproj" add docs/blueprint/feature-tracker.json src/login.js
git -C "$oproj" commit -q -m "feat(login): implement login"

oout="$(bash "$sync_script" --home-dir "$home" --project-dir "$oproj" 2>&1)"
orc=$?

[ "$orc" -eq 0 ] || fail "object-shaped tracker: expected exit 0, got $orc:\n$oout"
grep -q "Cannot index" <<< "$oout" \
  && fail "object-shaped tracker: jq indexing error leaked into output:\n$oout"
grep -q "^FEATURES_SHAPE=object$" <<< "$oout" \
  || fail "expected FEATURES_SHAPE=object, got:\n$oout"
grep -q "^FEATURES_TOTAL=3$" <<< "$oout" \
  || fail "expected FEATURES_TOTAL=3 (FR1.1, FR1.2, FR2; category FR1 is not a record), got:\n$oout"
grep -q "TYPE=status_inferred FR=FR1.1 FROM=not_started TO=complete" <<< "$oout" \
  || fail "expected nested FR1.1 inferred not_started->complete, got:\n$oout"
grep -q "^STATUS=WARN$" <<< "$oout" \
  || fail "expected STATUS=WARN (one evidence flip), got:\n$oout"
pass "object-shaped features: nested FR1.1 record is backfilled"

[ "$(jq -r '.features | type' "$otracker")" = "object" ] \
  || fail "object shape not preserved on write: .features is now $(jq -r '.features | type' "$otracker")"
[ "$(jq -r '.features.FR1.features["FR1.1"].status' "$otracker")" = "complete" ] \
  || fail "FR1.1 status not persisted as complete: $(jq -c '.features.FR1.features["FR1.1"]' "$otracker")"
[ "$(jq '.features.FR1.features["FR1.1"].implementation.commits | length' "$otracker")" -ge 1 ] \
  || fail "FR1.1 commit SHA not backfilled: $(jq -c '.features.FR1.features["FR1.1"]' "$otracker")"
[ "$(jq -r '.features.FR1.features["FR1.2"].status' "$otracker")" = "in_progress" ] \
  || fail "never-downgrade guard failed on nested FR1.2"
jq -e '.features.FR1 | has("status") | not' "$otracker" >/dev/null \
  || fail "category FR1 gained a status field it never had"
pass "object-shaped features: shape preserved, status + commits persisted"

for kv in STAT_COMPLETE=1 STAT_IN_PROGRESS=1 STAT_BLOCKED=1 STAT_NOT_STARTED=0 COMPLETION_PERCENTAGE=33.3; do
  grep -q "^${kv}$" <<< "$oout" || fail "object-shaped tracker: expected ${kv}, got:\n$oout"
done
pass "object-shaped features: statistics rollup counts nested records"

# ── #2867: a tracker jq cannot process must not report STATUS=OK ─────────────
# Valid JSON, wrong shape: a top-level array (jq cannot index it with
# .features) and a scalar `features` value. Both previously ran to STATUS=OK
# with empty STAT_* fields and exit 0.
check_malformed() {
  local name="$1" body="$2" mproj mtracker mout mrc before after
  mproj="$(new_project "$name")"
  [[ -n "$mproj" && -d "$mproj" ]] || fail "could not create the $name fixture project"
  mtracker="${mproj}/docs/blueprint/feature-tracker.json"
  printf '%s\n' "$body" > "$mtracker"
  before="$(cat "$mtracker")"
  mout="$(bash "$sync_script" --home-dir "$home" --project-dir "$mproj" 2>&1)"
  mrc=$?
  after="$(cat "$mtracker")"
  [ "$mrc" -ne 0 ] || fail "$name tracker: expected a non-zero exit, got 0:\n$mout"
  grep -q "^STATUS=ERROR$" <<< "$mout" \
    || fail "$name tracker: expected STATUS=ERROR, got:\n$mout"
  grep -q "^STATUS=OK$" <<< "$mout" \
    && fail "$name tracker: STATUS=OK must never be emitted on failure:\n$mout"
  grep -q "SEVERITY=ERROR" <<< "$mout" \
    || fail "$name tracker: expected an ERROR issue naming the failure, got:\n$mout"
  [ "$before" = "$after" ] || fail "$name tracker: a failed run rewrote the tracker"
  pass "$name tracker: STATUS=ERROR, non-zero exit, tracker untouched"
}
check_malformed toplevel-array '[{"features": []}]'
check_malformed scalar-features '{"features": "FR1, FR2"}'

echo "ALL TESTS PASSED"
