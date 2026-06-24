#!/usr/bin/env bash
# Regression tests for session-survey.sh — the shared read-only collector.
# Covers: empty state, populated taskwarrior, GitHub drift dedup, summary mode,
# and the no-git / no-tools degradation paths.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="$SCRIPT_DIR/../session-survey.sh"

pass=0
fail=0
check() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "  expected to find: $needle"
  fi
}
check_absent() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    fail=$((fail + 1))
    echo "FAIL: $label (unexpected: $needle)"
  else
    pass=$((pass + 1))
  fi
}

# Guarded sandbox (check-git-sandbox-guards.sh: every mktemp -d must be guarded).
SANDBOX="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
[ -n "$SANDBOX" ] || { echo "empty sandbox path"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

REPO="$SANDBOX/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name test
git -C "$REPO" commit -q --allow-empty -m "init"

# --- Stub binaries via the documented env seams -----------------------------
STUB="$SANDBOX/stub"
mkdir -p "$STUB"

# task stub: emits per-fixture JSON keyed by the query shape.
cat > "$STUB/task" <<'TASKSTUB'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"+ACTIVE export"*) cat "$TASK_ACTIVE_FIXTURE" 2>/dev/null || echo "[]" ;;
  *"export"*)         cat "$TASK_PROJECT_FIXTURE" 2>/dev/null || echo "[]" ;;
  *) echo "[]" ;;
esac
TASKSTUB
chmod +x "$STUB/task"

# gh stub: auth ok; issue/pr lists from fixtures.
cat > "$STUB/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue list")  cat "$GH_ISSUE_FIXTURE" 2>/dev/null || echo "[]" ;;
  "pr list")     cat "$GH_PR_FIXTURE" 2>/dev/null || echo "[]" ;;
  *) echo "[]" ;;
esac
GHSTUB
chmod +x "$STUB/gh"

export SESSION_SURVEY_TASK_BIN="$STUB/task"
export SESSION_SURVEY_GH_BIN="$STUB/gh"

run() { bash "$COLLECTOR" --project-dir "$REPO" --project demo "$@"; }

# --- TEST A: all empty -------------------------------------------------------
export TASK_PROJECT_FIXTURE=/dev/null TASK_ACTIVE_FIXTURE=/dev/null
export GH_ISSUE_FIXTURE=/dev/null GH_PR_FIXTURE=/dev/null
out=$(run)
check "A: project section present" "$out" "PROJECT=demo"
check "A: empty taskwarrior" "$out" "OPEN_TASKS=0"
check "A: git clean" "$out" "DIRTY=false"
check "A: every section reports STATUS=OK" "$out" "=== END STALE_ACTIVE_ELSEWHERE ==="

# --- TEST B: populated taskwarrior with UUID + annotation --------------------
echo '[{"uuid":"aaaa-1111","description":"Cluster fallback rules","tags":["ACTIVE"],"modified":"20260504T101010Z","annotations":[{"description":"PR #1774 awaiting review"}]},{"uuid":"bbbb-2222","description":"Confirm shutdown date","modified":"20260601T101010Z"}]' > "$SANDBOX/proj.json"
export TASK_PROJECT_FIXTURE="$SANDBOX/proj.json"
out=$(run)
check "B: two open tasks" "$out" "OPEN_TASKS=2"
check "B: emits stable UUID" "$out" "TASK_1_UUID=aaaa-1111"
check "B: active flag" "$out" "TASK_1_ACTIVE=true"
check "B: annotation surfaced" "$out" "PR #1774 awaiting review"
check_absent "B: no numeric task ID leaked as a TASK_n_ID key" "$out" "TASK_1_ID="

# --- TEST C: GitHub drift dedup (issue tracked by a task is dropped) ---------
echo '[{"number":851,"title":"OOMKilled","url":"http://x/851","updatedAt":"2026-06-22T10:00:00Z"},{"number":1774,"title":"already tracked","url":"http://x/1774","updatedAt":"2026-06-20T10:00:00Z"}]' > "$SANDBOX/issues.json"
export GH_ISSUE_FIXTURE="$SANDBOX/issues.json"
out=$(run --with-dedup)
check "C: assigned counts both" "$out" "ASSIGNED_ISSUES=2"
check "C: drift drops the tracked one" "$out" "DRIFT_COUNT=1"
check "C: untracked issue surfaced" "$out" "ISSUE_1_NUMBER=851"
check_absent "C: tracked issue #1774 not surfaced as drift" "$out" "ISSUE_1_NUMBER=1774"

# --- TEST D: summary mode (hook) --------------------------------------------
out=$(run --with-dedup --summary)
check "D: summary header" "$out" "=== SESSION SURVEY SUMMARY ==="
check "D: thread count present" "$out" "THREADS="
check_absent "D: summary omits full task detail" "$out" "TASK_1_UUID="

# --- TEST E: cross-project +ACTIVE footnote ---------------------------------
echo '[{"uuid":"cccc-3333","project":"other-proj","description":"stale elsewhere","tags":["ACTIVE"]}]' > "$SANDBOX/active.json"
export TASK_ACTIVE_FIXTURE="$SANDBOX/active.json"
out=$(run)
check "E: elsewhere active surfaced" "$out" "STALE_1_PROJECT=other-proj"

# --- TEST G: --with-commits surfaces recent commits (wrap/end) --------------
git -C "$REPO" commit -q --allow-empty -m "second commit"
out=$(run --with-commits)
check "G: commits section present" "$out" "=== COMMITS ==="
check "G: recent commit subject surfaced" "$out" "second commit"
out=$(run)
check_absent "G: commits omitted without the flag" "$out" "=== COMMITS ==="

# --- TEST F: no-git / no-tools degrade cleanly ------------------------------
out=$(SESSION_SURVEY_TASK_BIN=/nonexistent/task SESSION_SURVEY_GH_BIN=/nonexistent/gh \
  bash "$COLLECTOR" --project-dir "$SANDBOX" --project demo 2>&1)
rc=$?
check "F: exits 0 with no tools" "$rc" "0"
check "F: task unavailable reported" "$out" "TASK_AVAILABLE=false"
check "F: not a git repo reported" "$out" "IN_GIT=false"

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
