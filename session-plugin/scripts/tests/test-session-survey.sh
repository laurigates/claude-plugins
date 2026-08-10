#!/usr/bin/env bash
# Regression tests for session-survey.sh — the shared read-only collector.
# Covers: empty state, populated taskwarrior, GitHub drift dedup, summary mode,
# the no-git / no-tools degradation paths, and the #2276 / #2271 / #2232 fixes.
#
# Every test EXECUTES the collector against stub binaries on the documented
# SESSION_SURVEY_*_BIN seams — no greps for literal strings in the source.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="${SESSION_SURVEY_UNDER_TEST:-$SCRIPT_DIR/../session-survey.sh}"

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
check_le() {
  local label="$1" actual="$2" bound="$3"
  if [ -n "$actual" ] && [ "$actual" -le "$bound" ] 2>/dev/null; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label (got '$actual', wanted <= $bound)"
  fi
}
check_lt() {
  local label="$1" a="$2" b="$3"
  if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] 2>/dev/null; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label (got '$a', wanted < '$b')"
  fi
}
# Whole-line KEY=VALUE match. `check` is a substring test, and several keys are
# suffixes of others — `RECENT_TASK_1_PROJECT=x` and `STALE_1_PROJECT=x` both
# CONTAIN `PROJECT=x`, so an unanchored assertion can be satisfied by a
# neighbouring row instead of the key under test (the #2219 lesson).
check_line() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s\n' "$haystack" | grep -qxF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "  expected a whole line: $needle"
  fi
}
# Exact count of whole lines matching an anchored ERE. The injection guard:
# a value carrying a newline shows up as an EXTRA `KEY=` line, and neither a
# presence assertion (`check_line`) nor an absence one can see a duplicate —
# only counting can.
check_count_line() {
  local label="$1" haystack="$2" pattern="$3" want="$4" got
  got=$(printf '%s\n' "$haystack" | grep -cE "$pattern" || true)
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label (got '$got' lines matching /$pattern/, wanted '$want')"
  fi
}
check_eq() {
  local label="$1" actual="$2" want="$3"
  if [ "$actual" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label (got '$actual', wanted '$want')"
  fi
}

# Guarded sandbox (check-git-sandbox-guards.sh: every mktemp -d must be guarded).
SANDBOX="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
[ -n "$SANDBOX" ] || { echo "empty sandbox path"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

# Neutralize inherited git context so the sandbox git ops can never reach the
# real shared checkout (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
      GIT_NAMESPACE GIT_PREFIX 2>/dev/null || true

mkrepo() {  # $1 = absolute path
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" commit -q --allow-empty -m "init"
}

REPO="$SANDBOX/repo"
mkrepo "$REPO"

# Millisecond clock. BSD `date` has no %N (shell-scripting.md), so python3 or
# perl does the timing; the whole-second fallback only degrades precision.
now_ms() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import time; print(int(time.time()*1000))'
  elif command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'print int(time()*1000)'
  else
    echo $(( $(date +%s) * 1000 ))
  fi
}

# Taskwarrior compact timestamp N days ago (GNU then BSD).
tw_stamp() {
  date -u -d "-$1 days" +%Y%m%dT%H%M%SZ 2>/dev/null \
    || date -u -v-"$1"d +%Y%m%dT%H%M%SZ
}

# --- Stub binaries via the documented env seams -----------------------------
STUB="$SANDBOX/stub"
mkdir -p "$STUB"

# task stub. ONE export branch: the collector takes a single all-projects
# snapshot and scopes it in jq, so the fixture models an all-projects export
# (every task carries its own .project). The bpid branch is checked first
# because that filter string also contains "export".
cat > "$STUB/task" <<'TASKSTUB'
#!/usr/bin/env bash
args="$*"
if [ -n "${TASK_ARGV_LOG:-}" ]; then printf '%s\n' "$args" >> "$TASK_ARGV_LOG"; fi
case "$args" in
  *"bpid.any:"*) cat "$TASK_BPID_FIXTURE" 2>/dev/null || echo "[]" ;;
  *"export"*)    cat "$TASK_ALL_FIXTURE" 2>/dev/null || echo "[]" ;;
  *) echo "[]" ;;
esac
TASKSTUB
chmod +x "$STUB/task"

# gh stub: issue/pr lists from fixtures. "pr list" branches on the query so
# --author and --head can serve distinct fixtures (the #1915 union).
# GH_STUB_SLEEP simulates a slow/hung network call; GH_ARGV_LOG records argv.
cat > "$STUB/gh" <<'GHSTUB'
#!/usr/bin/env bash
args="$*"
if [ -n "${GH_ARGV_LOG:-}" ]; then printf '%s\n' "$args" >> "$GH_ARGV_LOG"; fi
if [ -n "${GH_STUB_SLEEP:-}" ]; then sleep "$GH_STUB_SLEEP"; fi
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue list")  cat "$GH_ISSUE_FIXTURE" 2>/dev/null || echo "[]" ;;
  "pr list")
    case "$args" in
      *--author*) cat "${GH_PR_AUTHOR_FIXTURE:-$GH_PR_FIXTURE}" 2>/dev/null || echo "[]" ;;
      *--head*)   cat "${GH_PR_HEAD_FIXTURE:-$GH_PR_FIXTURE}" 2>/dev/null || echo "[]" ;;
      *)          cat "$GH_PR_FIXTURE" 2>/dev/null || echo "[]" ;;
    esac
    ;;
  *) echo "[]" ;;
esac
GHSTUB
chmod +x "$STUB/gh"

# date stub: counts invocations, then delegates to the real binary. Used to
# assert that the recent-task scan does not fork `date` per task (TEST Z).
REAL_DATE="$(command -v date)"
cat > "$STUB/date" <<DATESTUB
#!/usr/bin/env bash
if [ -n "\${DATE_CALL_LOG:-}" ]; then printf 'x\n' >> "\$DATE_CALL_LOG"; fi
exec "$REAL_DATE" "\$@"
DATESTUB
chmod +x "$STUB/date"

export SESSION_SURVEY_TASK_BIN="$STUB/task"
export SESSION_SURVEY_GH_BIN="$STUB/gh"

run() { bash "$COLLECTOR" --project-dir "$REPO" --project demo "$@"; }
run_at() { local d="$1"; shift; bash "$COLLECTOR" --project-dir "$d" "$@"; }

# --- TEST A: all empty -------------------------------------------------------
export TASK_ALL_FIXTURE=/dev/null
export TASK_BPID_FIXTURE=/dev/null
export GH_ISSUE_FIXTURE=/dev/null GH_PR_FIXTURE=/dev/null
out=$(run)
check "A: project section present" "$out" "PROJECT=demo"
check "A: empty taskwarrior" "$out" "OPEN_TASKS=0"
check "A: git clean" "$out" "DIRTY=false"
check "A: every section reports STATUS=OK" "$out" "=== END STALE_ACTIVE_ELSEWHERE ==="

# --- TEST B: populated taskwarrior with UUID + annotation --------------------
# Fixtures now carry .project — they model an ALL-PROJECTS export.
echo '[{"uuid":"aaaa-1111","project":"demo","description":"Cluster fallback rules","tags":["ACTIVE"],"modified":"20260504T101010Z","annotations":[{"description":"PR #1774 awaiting review"}]},{"uuid":"bbbb-2222","project":"demo","description":"Confirm shutdown date","modified":"20260601T101010Z"}]' > "$SANDBOX/proj.json"
export TASK_ALL_FIXTURE="$SANDBOX/proj.json"
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
check "C: a successful gh query reports ready" "$out" "GH_READY=true"

# --- TEST D: summary mode (hook) --------------------------------------------
out=$(run --with-dedup --summary)
check "D: summary header" "$out" "=== SESSION SURVEY SUMMARY ==="
check "D: thread count present" "$out" "THREADS="
check "D: summary carries the scope signal" "$out" "TASK_SCOPE=project"
check "D: summary carries the confidence signal" "$out" "PROJECT_CONFIDENCE=high"
check_absent "D: summary omits full task detail" "$out" "TASK_1_UUID="

# --- TEST E: cross-project +ACTIVE footnote ---------------------------------
# Derived by jq from the single snapshot — no second `task +ACTIVE export`.
echo '[{"uuid":"aaaa-1111","project":"demo","description":"Cluster fallback rules","tags":["ACTIVE"],"modified":"20260504T101010Z","annotations":[{"description":"PR #1774 awaiting review"}]},{"uuid":"bbbb-2222","project":"demo","description":"Confirm shutdown date","modified":"20260601T101010Z"},{"uuid":"cccc-3333","project":"other-proj","description":"stale elsewhere","tags":["ACTIVE"],"modified":"20260601T101010Z"}]' > "$SANDBOX/proj-plus-elsewhere.json"
export TASK_ALL_FIXTURE="$SANDBOX/proj-plus-elsewhere.json"
out=$(run)
check "E: elsewhere active surfaced" "$out" "STALE_1_PROJECT=other-proj"
check "E: scoped count still excludes the other project" "$out" "OPEN_TASKS=2"

# --- TEST G: --with-commits surfaces recent commits (wrap/end) --------------
git -C "$REPO" commit -q --allow-empty -m "second commit"
out=$(run --with-commits)
check "G: commits section present" "$out" "=== COMMITS ==="
check "G: recent commit subject surfaced" "$out" "second commit"
out=$(run)
check_absent "G: commits omitted without the flag" "$out" "=== COMMITS ==="

# --- TEST H: authored PR with no matching local branch is surfaced (#1915) ---
# Refspec-pushed PRs leave no local branch; --author @me must still find them.
echo '[{"number":27,"title":"feat: refspec-pushed PR","url":"http://x/27","state":"OPEN","updatedAt":"2026-07-02T10:00:00Z"}]' > "$SANDBOX/author-prs.json"
export GH_PR_AUTHOR_FIXTURE="$SANDBOX/author-prs.json" GH_PR_HEAD_FIXTURE=/dev/null
out=$(run)
check "H: authored PR counted despite no local branch" "$out" "PR_COUNT=1"
check "H: authored PR number surfaced" "$out" "PR_1_NUMBER=27"

# --- TEST I: author + head PRs are unioned and deduped by number (#1915) -----
export GH_PR_HEAD_FIXTURE="$SANDBOX/author-prs.json"
out=$(run)
check "I: overlapping author/head PR deduped" "$out" "PR_COUNT=1"
unset GH_PR_AUTHOR_FIXTURE GH_PR_HEAD_FIXTURE

# --- TEST J: --with-blueprint degrades to MANIFEST=false without a manifest --
out=$(run --with-blueprint)
check "J: manifest absent reported" "$out" "MANIFEST=false"
check "J: undrained zero without manifest" "$out" "UNDRAINED_COUNT=0"
check "J: blueprint section closes with STATUS=OK" "$out" "=== END BLUEPRINT ==="
out=$(run)
check_absent "J: blueprint section omitted without the flag" "$out" "=== BLUEPRINT ==="

# --- TEST K: tracker feature counts via explicit-path union ------------------
# The phase itself carries status "not_started"; a recursive `.. | objects`
# jq would count it as a third ready feature. READY_COUNT must stay 2.
mkdir -p "$REPO/docs/blueprint"
echo '{}' > "$REPO/docs/blueprint/manifest.json"
cat > "$REPO/docs/blueprint/feature-tracker.json" <<'TRACKER'
{
  "phases": [
    {
      "name": "phase-1",
      "status": "not_started",
      "features": [
        {"id": "FR-1", "status": "not_started"},
        {"id": "FR-2", "status": "not_started"},
        {"id": "FR-3", "status": "blocked"}
      ]
    }
  ],
  "tasks": {
    "pending": [],
    "in_progress": [{"id": "WO-031", "description": "mid-flight WO"}],
    "completed": []
  }
}
TRACKER
out=$(run --with-blueprint)
check "K: manifest detected" "$out" "MANIFEST=true"
check "K: tracker detected" "$out" "TRACKER=true"
check "K: ready count skips the phase's own status" "$out" "READY_COUNT=2"
check "K: blocked count" "$out" "BLOCKED_COUNT=1"
check "K: in-flight WO surfaced" "$out" "INFLIGHT_WOS=WO-031"

# --- TEST L: undrained = closed-bpid WOs ∩ tracker tasks.pending -------------
echo '[{"uuid":"dddd-4444","description":"land WO-045","status":"completed","bpid":"WO-045"}]' > "$SANDBOX/bpid.json"
export TASK_BPID_FIXTURE="$SANDBOX/bpid.json"
cat > "$REPO/docs/blueprint/feature-tracker.json" <<'TRACKER'
{
  "features": [{"id": "FR-9", "status": "in_progress", "implementing_wos": ["WO-045"]}],
  "tasks": {
    "pending": [
      {"id": "WO-045", "description": "closed in tw, not drained"},
      {"id": "WO-099", "description": "still genuinely pending"}
    ],
    "in_progress": [],
    "completed": []
  }
}
TRACKER
out=$(run --with-blueprint)
check "L: closed bpid task counted" "$out" "CLOSED_BPID_COUNT=1"
check "L: undrained intersection is 1" "$out" "UNDRAINED_COUNT=1"
check "L: undrained WO surfaced" "$out" "UNDRAINED_WOS=WO-045"
check_absent "L: still-pending WO-099 not surfaced as undrained" "$out" "WO-099"

# --- TEST M: manifest-only (the dogfooding shape) degrades cleanly -----------
rm "$REPO/docs/blueprint/feature-tracker.json"
out=$(run --with-blueprint)
rc=$?
check "M: exits 0 with manifest but no tracker" "$rc" "0"
check "M: tracker absence reported" "$out" "TRACKER=false"
check "M: closed bpid still emitted as informational signal" "$out" "CLOSED_BPID_COUNT=1"
check "M: undrained forced to 0 without a tracker" "$out" "UNDRAINED_COUNT=0"
export TASK_BPID_FIXTURE=/dev/null
rm -rf "$REPO/docs"

# --- TEST F: no-git / no-tools degrade cleanly ------------------------------
out=$(SESSION_SURVEY_TASK_BIN=/nonexistent/task SESSION_SURVEY_GH_BIN=/nonexistent/gh \
  bash "$COLLECTOR" --project-dir "$SANDBOX" --project demo 2>&1)
rc=$?
check "F: exits 0 with no tools" "$rc" "0"
check "F: task unavailable reported" "$out" "TASK_AVAILABLE=false"
check "F: not a git repo reported" "$out" "IN_GIT=false"
check "F: task-absent is never a confident zero" "$out" "TASK_SCOPE=none"
check "F: task-absent reports low confidence" "$out" "PROJECT_CONFIDENCE=low"

# --- TEST N: gh unavailable is surfaced, never a silent false zero -----------
# Claude Code on the web has no gh CLI; the digest must say GH_READY=false in
# both GitHub-backed sections (and summary) so consumers can tell "not
# queried" from "no issues" — the skill then falls back to the GitHub MCP
# tools instead of presenting a clean state.
out=$(SESSION_SURVEY_GH_BIN=/nonexistent/gh run --with-dedup)
check "N: gh absent → GH_READY=false in PRS section" \
  "$(printf '%s' "$out" | sed -n '/=== PRS ===/,/=== END PRS ===/p')" "GH_READY=false"
check "N: gh absent → GH_READY=false in GITHUB_DRIFT section" \
  "$(printf '%s' "$out" | sed -n '/=== GITHUB_DRIFT ===/,/=== END GITHUB_DRIFT ===/p')" "GH_READY=false"
check "N: drift section still parse-stable when gh absent" "$out" "DRIFT_COUNT=0"
out=$(SESSION_SURVEY_GH_BIN=/nonexistent/gh run --with-dedup --summary)
check "N: summary carries GH_READY=false" "$out" "GH_READY=false"

# gh present but failing every query must read the same as absent. Real `gh`
# exits non-zero on `pr list`/`issue list` when unauthenticated (or when the
# repo has no GitHub remote), which is the signal GH_READY now keys on.
cat > "$STUB/gh-noauth" <<'GHNOAUTH'
#!/usr/bin/env bash
exit 1
GHNOAUTH
chmod +x "$STUB/gh-noauth"
out=$(SESSION_SURVEY_GH_BIN="$STUB/gh-noauth" run --with-dedup)
check "N: failing gh queries → GH_READY=false" "$out" "GH_READY=false"
check "N: failing gh queries → PR_COUNT=0, not a phantom PR" "$out" "PR_COUNT=0"

# ============================================================================
# #2276 — the SessionStart hook must degrade, not die
# ============================================================================

# --- TEST O: a hung gh is bounded, and never reads as a clean zero -----------
export GH_STUB_SLEEP=10
start=$(date +%s)
out=$(SESSION_SURVEY_GH_TIMEOUT=1 run --with-dedup)
elapsed=$(( $(date +%s) - start ))
unset GH_STUB_SLEEP
check_le "O: a 10s-hung gh is bounded by SESSION_SURVEY_GH_TIMEOUT=1" "$elapsed" 4
check "O: local PROJECT section still emitted" "$out" "PROJECT=demo"
check "O: local TASKWARRIOR section still emitted" "$out" "=== END TASKWARRIOR ==="
check "O: local GIT section still emitted" "$out" "=== END GIT ==="
check "O: a timed-out query is not a clean zero" \
  "$(printf '%s' "$out" | sed -n '/=== PRS ===/,/=== END PRS ===/p')" "GH_READY=false"
check "O: the timeout is surfaced as a diagnostic" "$out" "GH_TIMEOUT=true"

# --- TEST O2: no-network sections precede the network-backed ones ------------
# Structural, not timing: this is what makes a truncated digest useful.
out=$(run --with-dedup)
tw_end=$(printf '%s\n' "$out" | grep -n '^=== END TASKWARRIOR ===$' | head -1 | cut -d: -f1)
git_end=$(printf '%s\n' "$out" | grep -n '^=== END GIT ===$' | head -1 | cut -d: -f1)
prs_start=$(printf '%s\n' "$out" | grep -n '^=== PRS ===$' | head -1 | cut -d: -f1)
check_lt "O2: TASKWARRIOR is emitted before PRS" "$tw_end" "$prs_start"
check_lt "O2: GIT is emitted before PRS" "$git_end" "$prs_start"

# --- TEST P: the gh auth-status probe is gone --------------------------------
export GH_ARGV_LOG="$SANDBOX/gh-argv.log"
: > "$GH_ARGV_LOG"
out=$(run --with-dedup)
argv=$(cat "$GH_ARGV_LOG")
check_absent 'P: no "gh auth status" round-trip' "$argv" "auth status"
check "P: the real issue query still runs" "$argv" "issue list"
check "P: the real PR query still runs" "$argv" "pr list"
unset GH_ARGV_LOG

# --- TEST Q: the gh calls run in parallel, not serially ----------------------
export GH_STUB_SLEEP=2
start=$(date +%s)
out=$(SESSION_SURVEY_GH_TIMEOUT=6 run --with-dedup)
elapsed=$(( $(date +%s) - start ))
unset GH_STUB_SLEEP
# Bound is 2x the parallel time and half the serial time (pre-fix: 8s), so CI
# jitter cannot flip it in either direction.
check_le "Q: 3 x 2s gh calls complete in parallel" "$elapsed" 4
check "Q: parallel results still reach the digest" "$out" "ASSIGNED_ISSUES=2"

# ============================================================================
# #2271 + #2232 — one coherent taskwarrior-scoping solution
# ============================================================================

# --- TEST R: the git remote's repo name resolves a wrong basename (#2271) ----
# chezmoi shape: directory basename != the real project slug.
CHEZMOI="$SANDBOX/chezmoi-src"
mkrepo "$CHEZMOI"
git -C "$CHEZMOI" remote add origin https://github.com/u/dotfiles.git
echo '[{"uuid":"e1","project":"dotfiles","description":"chezmoi apply drift","modified":"20260601T101010Z"},{"uuid":"e2","project":"dotfiles","description":"prune stale symlinks","modified":"20260601T101010Z"}]' > "$SANDBOX/dotfiles.json"
export TASK_ALL_FIXTURE="$SANDBOX/dotfiles.json"
out=$(run_at "$CHEZMOI")
check "R: basename is still reported as the detected project" "$out" "PROJECT=chezmoi-src"
check "R: the remote's repo name is surfaced" "$out" "PROJECT_REMOTE_NAME=dotfiles"
check "R: scope resolved via the git remote" "$out" "TASK_SCOPE=remote-name"
check "R: resolved slug reported" "$out" "PROJECT_RESOLVED=dotfiles"
check "R: uncertainty is visible" "$out" "PROJECT_CONFIDENCE=low"
check "R: the 2 real tasks are found, not a false zero" "$out" "OPEN_TASKS=2"
check "R: resolved tasks carry their UUID" "$out" "TASK_1_UUID="

# --- TEST R2 (guard integrity): a matching basename stays confident ----------
echo '[{"uuid":"f1","project":"chezmoi-src","description":"a","modified":"20260601T101010Z"},{"uuid":"f2","project":"chezmoi-src","description":"b","modified":"20260601T101010Z"}]' > "$SANDBOX/chezmoi-owned.json"
export TASK_ALL_FIXTURE="$SANDBOX/chezmoi-owned.json"
out=$(run_at "$CHEZMOI")
check "R2: matching basename keeps the project scope" "$out" "TASK_SCOPE=project"
check "R2: matching basename stays confident" "$out" "PROJECT_CONFIDENCE=high"
check "R2: matching basename counts its tasks" "$out" "OPEN_TASKS=2"
check_absent "R2: no spurious PROJECT_RESOLVED when nothing was resolved" "$out" "PROJECT_RESOLVED="

# --- TEST S: portfolio checkout falls back to all projects (#2232) -----------
PORTFOLIO="$SANDBOX/repos"
mkrepo "$PORTFOLIO"   # deliberately no remote: no alternate slug can win
NOW_STAMP="$(tw_stamp 0)"
cat > "$SANDBOX/portfolio.json" <<EOF
[{"uuid":"p1","project":"alpha","description":"fix alpha ci","modified":"$NOW_STAMP"},
 {"uuid":"p2","project":"beta","description":"beta release notes","modified":"$NOW_STAMP"},
 {"uuid":"p3","project":"beta","description":"beta lint","modified":"$NOW_STAMP"},
 {"uuid":"p4","project":"gamma","description":"gamma docs","modified":"$NOW_STAMP"},
 {"uuid":"p5","project":"gamma","description":"gamma deps","modified":"$NOW_STAMP"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/portfolio.json"
out=$(run_at "$PORTFOLIO")
check "S: the project-scoped count is honestly zero" "$out" "OPEN_TASKS=0"
check "S: the all-projects total is surfaced" "$out" "TASKS_ALL_PROJECTS=5"
check "S: the narrowing is visible" "$out" "TASK_SCOPE=all-projects-fallback"
check "S: uncertainty is visible" "$out" "PROJECT_CONFIDENCE=low"
check "S: recently-touched tasks are surfaced" "$out" "RECENT_TASK_COUNT=5"
check "S: recent rows carry their project" "$out" "RECENT_TASK_1_PROJECT="
check "S: recent rows carry their UUID" "$out" "RECENT_TASK_1_UUID="
out=$(run_at "$PORTFOLIO" --summary)
threads=$(printf '%s\n' "$out" | grep -m1 '^THREADS=' | cut -d= -f2)
check "S: the fallback reaches the hook's nudge decision" \
  "$( [ "${threads:-0}" -ge 5 ] && echo yes || echo "no (THREADS=$threads)" )" "yes"

# --- TEST S2: visible uncertainty is independent of the recency window -------
OLD_STAMP="$(tw_stamp 30)"
sed "s/$NOW_STAMP/$OLD_STAMP/g" "$SANDBOX/portfolio.json" > "$SANDBOX/portfolio-old.json"
export TASK_ALL_FIXTURE="$SANDBOX/portfolio-old.json"
out=$(run_at "$PORTFOLIO")
check "S2: nothing recent inside the window" "$out" "RECENT_TASK_COUNT=0"
check "S2: the narrowing is still visible" "$out" "TASK_SCOPE=all-projects-fallback"
check "S2: confidence is still low" "$out" "PROJECT_CONFIDENCE=low"
check_absent "S2: no recent rows outside the window" "$out" "RECENT_TASK_1_UUID="
out=$(run_at "$PORTFOLIO" --recent-days 60)
check "S2: --recent-days widens the window" "$out" "RECENT_TASK_COUNT=5"

# --- TEST T (guard integrity): a genuine zero stays confident ----------------
export TASK_ALL_FIXTURE=/dev/null
out=$(run_at "$REPO")
check "T: empty store scoped to the basename" "$out" "TASK_SCOPE=project"
check "T: an empty store is a confident zero" "$out" "PROJECT_CONFIDENCE=high"
check "T: no tasks anywhere" "$out" "TASKS_ALL_PROJECTS=0"
check_absent "T: no recent-task rows on the confident path" "$out" "RECENT_TASK_1_UUID="
# A user-asserted --project earns a confident zero even against a full store.
export TASK_ALL_FIXTURE="$SANDBOX/portfolio.json"
out=$(run)
check "T: an explicit --project keeps its confident zero" "$out" "PROJECT_CONFIDENCE=high"
check "T: an explicit --project keeps the project scope" "$out" "TASK_SCOPE=project"

# --- TEST U: ONE taskwarrior snapshot, not two bolted-on fallbacks -----------
export TASK_ARGV_LOG="$SANDBOX/task-argv.log"
: > "$TASK_ARGV_LOG"
out=$(run_at "$PORTFOLIO")
exports=$(grep -c 'export' "$TASK_ARGV_LOG" || true)
check_eq "U: exactly one export call feeds every consumer" "$exports" "1"
check_absent "U: scoping happens in jq, never a project: filter" \
  "$(cat "$TASK_ARGV_LOG")" "project:"
unset TASK_ARGV_LOG

# --- TEST V: UNPUSHED is a single-line integer -------------------------------
# On a branch with no upstream `git log @{u}..HEAD` fails; the old
# `grep -c '' || echo 0` printed 0 AND exited 1, so `|| echo 0` also ran and
# UNPUSHED became "0\n0" — a bare 0 line inside the digest.
export TASK_ALL_FIXTURE=/dev/null
out=$(run)
unpushed_lines=$(printf '%s\n' "$out" | grep -c '^UNPUSHED=' || true)
bare_zero_lines=$(printf '%s\n' "$out" | grep -c '^0$' || true)
check_eq "V: exactly one UNPUSHED key" "$unpushed_lines" "1"
check_eq "V: no bare integer line leaked into the digest" "$bare_zero_lines" "0"
check "V: UNPUSHED is a single-line value" "$out" "UNPUSHED=0"

# --- TEST X: without jq there is no scoping, so never a confident zero -------
# Build a PATH with every binary the collector needs EXCEPT jq.
NOJQ="$SANDBOX/nojq"
mkdir -p "$NOJQ"
for b in date awk grep cat sed basename mktemp git rm head cut sleep seq bash sh env dirname; do
  p=$(command -v "$b" 2>/dev/null) && ln -sf "$p" "$NOJQ/$b"
done
# Fixture validity: fail loudly rather than degrading into a silent no-op.
check_eq "X: fixture — jq is genuinely absent from the restricted PATH" \
  "$(PATH="$NOJQ" command -v jq >/dev/null 2>&1 && echo present || echo absent)" "absent"
check_eq "X: fixture — git is genuinely present on the restricted PATH" \
  "$(PATH="$NOJQ" command -v git >/dev/null 2>&1 && echo present || echo absent)" "present"
export TASK_ALL_FIXTURE="$SANDBOX/portfolio.json"
out=$(PATH="$NOJQ" bash "$COLLECTOR" --project-dir "$REPO" --project demo 2>&1)
check "X: task binary still reported available" "$out" "TASK_AVAILABLE=true"
check "X: no jq means no scoping was possible" "$out" "TASK_SCOPE=unknown"
check "X: an unscopeable count is never confident" "$out" "PROJECT_CONFIDENCE=low"
check "X: the digest is still parse-stable" "$out" "=== END TASKWARRIOR ==="

# ============================================================================
# Repairs to the #2276 / #2271 / #2232 change set
# ============================================================================

# --- TEST Y: `project:` scoping is a HIERARCHY match, not string equality ----
# `task project:bluepad32` matches `bluepad32` AND every `bluepad32.<sub>`.
# Exact equality dropped every subproject task out of the project scope — and
# in the fallback shape a subproject task modified outside --recent-days then
# vanished from the digest COMPLETELY, silently skipping session-end's
# taskwarrior-sync gate. The repo's own docs use hierarchical projects.
BP="$SANDBOX/bluepad32"
mkrepo "$BP"
OLD10="$(tw_stamp 10)"
cat > "$SANDBOX/subproject.json" <<EOF
[{"uuid":"sub-1","project":"bluepad32.own","description":"subproject task","modified":"$OLD10","ghid":42}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/subproject.json"
out=$(run_at "$BP")
check "Y: a subproject task is inside project scope" "$out" "OPEN_TASKS=1"
check "Y: subproject scope is the confident project path" "$out" "TASK_SCOPE=project"
check "Y: a resolved hierarchy is not low confidence" "$out" "PROJECT_CONFIDENCE=high"
check "Y: the subproject task carries its UUID" "$out" "TASK_1_UUID=sub-1"
check "Y: the subproject task carries its GHID" "$out" "TASK_1_GHID=42"
check "Y: the subproject task carries its staleness" "$out" "TASK_1_STALE_DAYS=10"
# The vanish case: outside --recent-days, so RECENT_TASK_* cannot rescue it.
check "Y: nothing recent — the scoped count is the only thing carrying it" \
  "$out" "RECENT_TASK_COUNT=0"
out=$(run_at "$BP" --summary)
threads=$(printf '%s\n' "$out" | grep -m1 '^THREADS=' | cut -d= -f2)
check_eq "Y: the subproject task reaches the hook's nudge decision" "$threads" "1"

# --- TEST Y2 (guard integrity): only a literal `.` separates hierarchy levels -
# A blanket startswith() would swallow `bluepad32-extra`, over-widening the
# scope — the opposite failure to the one above.
cat > "$SANDBOX/prefix-not-child.json" <<EOF
[{"uuid":"pre-1","project":"bluepad32-extra","description":"different project","modified":"$OLD10"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/prefix-not-child.json"
out=$(run_at "$BP")
check "Y2: a name-prefix sibling is NOT a subproject" "$out" "OPEN_TASKS=0"
check "Y2: nothing matched, so the widening is visible" "$out" "TASK_SCOPE=all-projects-fallback"
check_absent "Y2: the sibling project's task is not scoped in" "$out" "TASK_1_UUID=pre-1"

# --- TEST Y3: an in-scope subproject is not ALSO "+ACTIVE elsewhere" ---------
cat > "$SANDBOX/subproject-active.json" <<EOF
[{"uuid":"sub-2","project":"bluepad32.own","description":"active subproject","tags":["ACTIVE"],"modified":"$OLD10"},
 {"uuid":"far-1","project":"unrelated","description":"genuinely elsewhere","tags":["ACTIVE"],"modified":"$OLD10"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/subproject-active.json"
out=$(run_at "$BP")
check "Y3: the subproject +ACTIVE counts as in-scope" "$out" "ACTIVE_TASKS=1"
check_absent "Y3: an in-scope subproject is not double-reported as elsewhere" \
  "$out" "STALE_1_PROJECT=bluepad32.own"
check "Y3: a genuinely different project IS still reported elsewhere" \
  "$out" "STALE_1_PROJECT=unrelated"
check "Y3: exactly one elsewhere row" "$out" "ELSEWHERE_COUNT=1"

# --- TEST Z: the recent-task scan is flat in the size of the store -----------
# It runs in the SessionStart hook path over the WHOLE all-projects store, so
# it must neither fork `date` per task nor scan past the recency window.
jq -n --arg m "$(tw_stamp 0)" \
  '[range(800) | {uuid:("u"+(.|tostring)), project:("p"+((.%25)|tostring)),
                  description:("task "+(.|tostring)), modified:$m}]' \
  > "$SANDBOX/big-in.json"
jq -n --arg m "$(tw_stamp 30)" \
  '[range(800) | {uuid:("u"+(.|tostring)), project:("p"+((.%25)|tostring)),
                  description:("task "+(.|tostring)), modified:$m}]' \
  > "$SANDBOX/big-out.json"

# Structural half: `date` invocations must not scale with the store. Bounded by
# now_epoch + the cutoff stamp + one days_since per EMITTED row (<=10).
export DATE_CALL_LOG="$SANDBOX/date-calls.log"
export TASK_ALL_FIXTURE="$SANDBOX/big-in.json"
: > "$DATE_CALL_LOG"
out=$(PATH="$STUB:$PATH" bash "$COLLECTOR" --project-dir "$PORTFOLIO" --summary --with-dedup)
date_calls=$(grep -c 'x' "$DATE_CALL_LOG" || true)
check_le "Z: <=30 date forks for an 800-task store (was: one per task)" "$date_calls" 30
unset DATE_CALL_LOG
# Fixture validity: the store really is 800 tasks inside the window, so the
# bound above is not passing against a scan that never ran.
out=$(run_at "$PORTFOLIO")
check "Z: fixture — all 800 are inside the window" "$out" "RECENT_TASK_COUNT=800"
check "Z: only the first 10 are emitted as rows" "$out" "RECENT_TASK_TRUNCATED=true"
check "Z: the 10th row is emitted" "$out" "RECENT_TASK_10_UUID="
check_absent "Z: the 11th row is not" "$out" "RECENT_TASK_11_UUID="

# Wall clock, both directions. Pre-fix this was ~2.3s either way (the scan was
# unconditional and never short-circuited); post-fix it is well under a second.
start=$(date +%s)
out=$(run_at "$PORTFOLIO" --summary --with-dedup)
elapsed=$(( $(date +%s) - start ))
check_le "Z: an 800-task in-window store stays under 1s" "$elapsed" 1
export TASK_ALL_FIXTURE="$SANDBOX/big-out.json"
start=$(date +%s)
out=$(run_at "$PORTFOLIO" --summary --with-dedup)
elapsed=$(( $(date +%s) - start ))
check_le "Z: an 800-task out-of-window store stays under 1s" "$elapsed" 1
check "Z: nothing in the window is honestly zero" "$out" "RECENT_TASK_COUNT=0"

# --- TEST Z3: the scan short-circuits at the window edge --------------------
# The feed is sorted newest-first, so the first out-of-window row ends the scan
# (`break`, not `continue`). Absolute timings are machine-dependent, so this is
# a RELATIVE measurement against the same collector: an all-out-of-window store
# must be markedly cheaper than an all-in-window store of identical size, since
# only the former can stop at row 1. With `continue` the two converge (measured
# 449ms vs 985ms with the break; 809ms vs 931ms without it).
jq -n --arg m "$(tw_stamp 0)" \
  '[range(20000) | {uuid:("u"+(.|tostring)), project:"p",
                    description:("t"+(.|tostring)), modified:$m}]' > "$SANDBOX/huge-in.json"
jq -n --arg m "$(tw_stamp 30)" \
  '[range(20000) | {uuid:("u"+(.|tostring)), project:"p",
                    description:("t"+(.|tostring)), modified:$m}]' > "$SANDBOX/huge-out.json"
time_scan() {  # $1 = fixture; min of two runs, to damp scheduler noise
  local f="$1" best="" t0 t1 d
  # `_` (not `i`): the counter is deliberately unused — two iterations, min wins.
  for _ in 1 2; do
    t0=$(now_ms)
    TASK_ALL_FIXTURE="$f" run_at "$PORTFOLIO" --summary >/dev/null 2>&1
    t1=$(now_ms)
    d=$((t1 - t0))
    if [ -z "$best" ] || [ "$d" -lt "$best" ]; then best="$d"; fi
  done
  printf '%s' "$best"
}
ms_in=$(time_scan "$SANDBOX/huge-in.json")
ms_out=$(time_scan "$SANDBOX/huge-out.json")
# Fixture validity: if the in-window scan is itself trivial, the ratio below is
# measuring noise rather than the short-circuit.
check_eq "Z3: fixture — the full scan is slow enough to measure" \
  "$( [ "${ms_in:-0}" -ge 200 ] && echo yes || echo "no (${ms_in}ms)" )" "yes"
check_eq "Z3: an out-of-window store short-circuits instead of scanning" \
  "$( [ $(( ms_out * 100 )) -le $(( ms_in * 75 )) ] && echo yes \
      || echo "no (out=${ms_out}ms in=${ms_in}ms)" )" "yes"

# --- TEST Z2: an unorderable stamp must not end the scan early --------------
# The scan `break`s on the first out-of-window row (the feed is sorted
# newest-first). A row whose timestamp cannot be ordered is skipped instead —
# it is not evidence that the window has been left.
NOW0="$(tw_stamp 0)"
cat > "$SANDBOX/mixed-stamps.json" <<EOF
[{"uuid":"m1","project":"a","description":"recent one","modified":"$NOW0"},
 {"uuid":"m2","project":"a","description":"no timestamp at all"},
 {"uuid":"m3","project":"b","description":"recent two","modified":"$NOW0"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/mixed-stamps.json"
out=$(run_at "$PORTFOLIO")
check "Z2: both dateable in-window tasks survive the scan" "$out" "RECENT_TASK_COUNT=2"

# --- TEST AA: an EMPTY column must not shift every later one left -----------
# TAB is an IFS *whitespace* character, so `IFS=$'\t' read` collapses a run of
# tabs: a task with no annotations reported its ghid as TASK_n_ANNOT (and
# emitted no TASK_n_GHID), and a task with no project shifted its description
# into RECENT_TASK_n_PROJECT.
cat > "$SANDBOX/ghid-no-annot.json" <<EOF
[{"uuid":"g1","project":"demo","description":"linked task","modified":"$OLD10","ghid":42}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/ghid-no-annot.json"
out=$(run)
check "AA: ghid lands in GHID when there are no annotations" "$out" "TASK_1_GHID=42"
check_absent "AA: ghid does not masquerade as an annotation" "$out" "TASK_1_ANNOT=42"
# Guard integrity: the populated case must still work, or the fix could be
# "drop the annotation column".
cat > "$SANDBOX/ghid-with-annot.json" <<EOF
[{"uuid":"g1","project":"demo","description":"linked task","modified":"$OLD10","ghid":42,
  "annotations":[{"description":"blocked on review"}]}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/ghid-with-annot.json"
out=$(run)
check "AA: annotation still surfaced when present" "$out" "TASK_1_ANNOT=blocked on review"
check "AA: ghid still surfaced alongside an annotation" "$out" "TASK_1_GHID=42"
# Same collapse in the fallback rows: an empty .project.
cat > "$SANDBOX/no-project.json" <<EOF
[{"uuid":"n1","description":"unprojected work","modified":"$NOW0"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/no-project.json"
out=$(run_at "$PORTFOLIO")
check "AA: an unprojected task keeps its description in DESC" \
  "$out" "RECENT_TASK_1_DESC=unprojected work"
check_absent "AA: the description does not shift into PROJECT" \
  "$out" "RECENT_TASK_1_PROJECT=unprojected work"

# --- TEST AA2: a hazardous byte INSIDE a column must not shift later ones ---
# AA covers an EMPTY column; this covers a POPULATED one carrying a byte that
# breaks the row. Switching the delimiter from TAB to US fixed the empty-field
# collapse but `join($us)` escapes nothing, where the former `@tsv` escaped
# \t \n \r \\ by construction — so a description containing a NEWLINE split one
# row into two and shifted every later column, and in the fallback rows the task
# vanished from the digest entirely. A literal US byte in the content is the
# same class. Every projection must strip tab, CR, LF and US.
NL_DESC='line one
line two'
jq -nc --arg d "$NL_DESC" --arg m "$OLD10" \
  '[{uuid:"h1",project:"demo",description:$d,modified:$m,ghid:99}]' \
  > "$SANDBOX/newline-desc.json"
export TASK_ALL_FIXTURE="$SANDBOX/newline-desc.json"
out=$(run)
check "AA2: exactly one task is reported" "$out" "OPEN_TASKS=1"
check "AA2: the newline is flattened, not row-splitting" "$out" "TASK_1_DESC=line one line two"
check "AA2: ghid still lands in GHID" "$out" "TASK_1_GHID=99"
check_absent "AA2: no phantom second task row" "$out" "TASK_2_UUID="
# The fallback rows are the more damaging half: pre-fix the task disappeared.
# These rows are windowed by --recent-days, so the fixture needs a fresh stamp.
jq -nc --arg d "$NL_DESC" --arg m "$NOW0" \
  '[{uuid:"h1",project:"demo",description:$d,modified:$m}]' \
  > "$SANDBOX/newline-desc-fresh.json"
export TASK_ALL_FIXTURE="$SANDBOX/newline-desc-fresh.json"
out=$(run_at "$PORTFOLIO")
check "AA2: a newline description survives into the fallback rows" \
  "$out" "RECENT_TASK_COUNT=1"
check "AA2: the fallback description is flattened" \
  "$out" "RECENT_TASK_1_DESC=line one line two"
# A literal US byte in the content is the same hazard as the delimiter itself.
jq -nc --arg us "$(printf '\037')" --arg m "$OLD10" \
  '[{uuid:"h2",project:"demo",description:("before" + $us + "after"),modified:$m,ghid:77}]' \
  > "$SANDBOX/us-desc.json"
export TASK_ALL_FIXTURE="$SANDBOX/us-desc.json"
out=$(run)
check "AA2: an embedded US byte is flattened" "$out" "TASK_1_DESC=before after"
check "AA2: an embedded US byte does not shift GHID" "$out" "TASK_1_GHID=77"
# Guard integrity: an ordinary description must still pass through untouched,
# or the fix could be "blank the description column".
jq -nc --arg m "$OLD10" \
  '[{uuid:"h3",project:"demo",description:"ordinary description",modified:$m,ghid:55}]' \
  > "$SANDBOX/plain-desc.json"
export TASK_ALL_FIXTURE="$SANDBOX/plain-desc.json"
out=$(run)
check "AA2: an ordinary description is unmodified" "$out" "TASK_1_DESC=ordinary description"
check "AA2: an ordinary row still carries its ghid" "$out" "TASK_1_GHID=55"

# --- TEST AB: --summary makes the calls whose output it prints --------------
# Gating the issues job on --with-dedup left `--summary` alone emitting
# GH_READY=false / ASSIGNED_ISSUES=0 with zero gh calls made: fabricated zeros.
export TASK_ALL_FIXTURE=/dev/null
export GH_ARGV_LOG="$SANDBOX/gh-argv-summary.log"
: > "$GH_ARGV_LOG"
out=$(run --summary)
argv=$(cat "$GH_ARGV_LOG")
check "AB: --summary alone actually queries GitHub" "$argv" "issue list"
check "AB: --summary alone reports a real GH_READY" "$out" "GH_READY=true"
check "AB: --summary alone reports the real assigned count" "$out" "ASSIGNED_ISSUES=2"
unset GH_ARGV_LOG
# Guard integrity: a failing gh must still read false, not a blanket true.
out=$(SESSION_SURVEY_GH_BIN="$STUB/gh-noauth" run --summary)
check "AB: a failing gh still reports GH_READY=false in summary" "$out" "GH_READY=false"
check "AB: a failing gh reports no assigned issues" "$out" "ASSIGNED_ISSUES=0"

# --- TEST AC: summary mode honours the same ordering guarantee --------------
# The #2276 "degrade, don't die" property was only true of the full digest:
# summary reaped GitHub BEFORE emitting anything, so a hard kill during the
# gh wait produced no output at all there.
out=$(run --summary --with-dedup)
proj_line=$(printf '%s\n' "$out" | grep -n '^PROJECT=' | head -1 | cut -d: -f1)
tasks_line=$(printf '%s\n' "$out" | grep -n '^OPEN_TASKS=' | head -1 | cut -d: -f1)
ghready_line=$(printf '%s\n' "$out" | grep -n '^GH_READY=' | head -1 | cut -d: -f1)
check_lt "AC: PROJECT precedes GH_READY in summary" "$proj_line" "$ghready_line"
check_lt "AC: OPEN_TASKS precedes GH_READY in summary" "$tasks_line" "$ghready_line"
# And the property that ordering exists for: a kill mid-gh still yields output.
export GH_STUB_SLEEP=6
partial=$(SESSION_SURVEY_GH_TIMEOUT=9 timeout 2 bash "$COLLECTOR" \
  --project-dir "$REPO" --project demo --summary --with-dedup 2>/dev/null || true)
unset GH_STUB_SLEEP
check "AC: a hard kill during the gh wait still emits the local block" \
  "$partial" "OPEN_TASKS="
check_absent "AC: the killed run never reached the network keys" "$partial" "GH_READY="

# --- TEST AD: numeric knobs are validated, not silently swallowed -----------
export TASK_ALL_FIXTURE="$SANDBOX/big-in.json"
out=$(run_at "$PORTFOLIO" --recent-days abc)
check "AD: a non-numeric --recent-days falls back to the default" "$out" "RECENT_DAYS=2"
check "AD: the rejected value is reported, never silent" "$out" "RECENT_DAYS_INVALID=abc"
check "AD: the window still works — no silent zero" "$out" "RECENT_TASK_COUNT=800"
# Guard integrity: a valid value must NOT be reported as invalid.
out=$(run_at "$PORTFOLIO" --recent-days 7)
check "AD: a valid --recent-days is honoured" "$out" "RECENT_DAYS=7"
check_absent "AD: a valid --recent-days raises no invalid key" "$out" "RECENT_DAYS_INVALID="
# The same swallow reached the watchdog's `sleep`: an unparseable budget made
# it return instantly and kill every gh call.
export TASK_ALL_FIXTURE=/dev/null
export GH_STUB_SLEEP=1
out=$(SESSION_SURVEY_GH_TIMEOUT=abc run --with-dedup)
check "AD: a non-numeric gh budget falls back to the default" "$out" "GH_BUDGET=4"
check "AD: the rejected budget is reported" "$out" "GH_BUDGET_INVALID=abc"
check "AD: a slow gh still completes under the fallback budget" "$out" "ASSIGNED_ISSUES=2"
# Guard integrity: a genuinely tiny budget must still cut the call off.
out=$(SESSION_SURVEY_GH_TIMEOUT=0 run --with-dedup)
unset GH_STUB_SLEEP
check "AD: a real budget of 0 still bounds a slow gh" "$out" "GH_READY=false"
check_absent "AD: a valid budget raises no invalid key" "$out" "GH_BUDGET_INVALID="

# --- TEST AE: the spinup consumer documents the scope signals ---------------
# The collector's honesty is only worth anything if its primary consumer acts
# on it: session-spinup must know the keys exist and must not instruct an
# unconditional "nothing pending under project:<name>".
SPINUP="$SCRIPT_DIR/../../skills/session-spinup"
spinup_docs=$(cat "$SPINUP/SKILL.md" "$SPINUP/REFERENCE.md" 2>/dev/null)
check "AE: spinup names TASK_SCOPE" "$spinup_docs" "TASK_SCOPE"
check "AE: spinup names PROJECT_CONFIDENCE" "$spinup_docs" "PROJECT_CONFIDENCE"
check "AE: spinup names the fallback rows" "$spinup_docs" "RECENT_TASK_"
check "AE: spinup names the widened scope by value" "$spinup_docs" "all-projects-fallback"
check "AE: the clean-queue claim is gated on confidence" \
  "$(cat "$SPINUP/REFERENCE.md" 2>/dev/null)" "PROJECT_CONFIDENCE=high"

# ============================================================================
# #2304 — a nested repo whose backlog is filed under the PARENT workspace slug
#
# Shape from the report: eleven packs live under one `comfyui-nodes` workspace
# and all file under `project:comfyui-nodes`. The nested basename matches no
# task, so the survey reported OPEN_TASKS=0 — an EMPTY answer, which is exactly
# what "this pass does not qualify" looks like to session-end.
# ============================================================================

WS="$SANDBOX/ws"
PARENT="$WS/comfyui-nodes"
CHILD="$PARENT/comfyui-gallery-loader"
mkrepo "$PARENT"
mkrepo "$CHILD"          # deliberately NO remote: remote-name cannot resolve it
# Fixture validity: the child must really be its own repo, or the walk under
# test never has an ancestor to find.
check_eq "AF: fixture — the child is its own git repo" \
  "$(git -C "$CHILD" rev-parse --show-toplevel)" "$(cd "$CHILD" && pwd -P)"

cat > "$SANDBOX/nested-parent-slug.json" <<'EOF'
[{"uuid":"n1","project":"comfyui-nodes","description":"gallery loader thumbnails","modified":"20260601T101010Z"},
 {"uuid":"n2","project":"comfyui-nodes","description":"registry banner drift","modified":"20260601T101010Z"}]
EOF

run_nested() { bash "$COLLECTOR" --project-dir "$CHILD" --home-dir "$WS" "$@"; }

# --- TEST AF: the walk finds the ancestor slug that holds the work -----------
export TASK_ALL_FIXTURE="$SANDBOX/nested-parent-slug.json"
export TASK_ARGV_LOG="$SANDBOX/task-argv-nested.log"
: > "$TASK_ARGV_LOG"
out=$(run_nested)
check_line "AF: the effective slug is the ancestor's" "$out" "PROJECT=comfyui-nodes"
check_line "AF: the derivation is named" "$out" "DETECTION=cwd-repo-basename-ancestor"
check_line "AF: the scope is named" "$out" "TASK_SCOPE=ancestor-name"
check_line "AF: the resolved slug is reported" "$out" "PROJECT_RESOLVED=comfyui-nodes"
check_line "AF: the real backlog is found, not a false zero" "$out" "OPEN_TASKS=2"
check_line "AF: a derived slug is never confident" "$out" "PROJECT_CONFIDENCE=low"
check "AF: resolved tasks carry their UUID" "$out" "TASK_1_UUID=n1"
check_absent "AF: an adopted slug is not also flagged ambiguous" "$out" "PROJECT_AMBIGUOUS="
# The walk must not cost a taskwarrior query: every candidate is scoped in jq
# over the ONE snapshot (parallel-safe-queries.md — no `task ... list`, no
# extra export whose non-zero exit could cancel siblings).
nested_exports=$(grep -c 'export' "$TASK_ARGV_LOG" || true)
check_eq "AF: the walk adds no taskwarrior query" "$nested_exports" "1"
check_absent "AF: scoping stays in jq, never a project: filter" \
  "$(cat "$TASK_ARGV_LOG")" "project:"
unset TASK_ARGV_LOG
# The signal reaches the hook's summary too.
out=$(run_nested --summary)
check_line "AF: summary carries the ancestor scope" "$out" "TASK_SCOPE=ancestor-name"
check_line "AF: summary carries the resolved slug" "$out" "PROJECT_RESOLVED=comfyui-nodes"

# --- TEST AF2 (guard integrity): a slug that DOES match is never rewritten ---
# Without this, "always walk up" would pass AF while destroying every correct
# per-repo scope in the corpus.
cat > "$SANDBOX/nested-own-slug.json" <<'EOF'
[{"uuid":"o1","project":"comfyui-gallery-loader","description":"own backlog","modified":"20260601T101010Z"},
 {"uuid":"o2","project":"comfyui-nodes","description":"workspace backlog","modified":"20260601T101010Z"},
 {"uuid":"o3","project":"comfyui-nodes","description":"workspace backlog 2","modified":"20260601T101010Z"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/nested-own-slug.json"
out=$(run_nested)
check_line "AF2: a matching basename keeps its own slug" "$out" "PROJECT=comfyui-gallery-loader"
check_line "AF2: a matching basename keeps the project scope" "$out" "TASK_SCOPE=project"
check_line "AF2: a matching basename stays confident" "$out" "PROJECT_CONFIDENCE=high"
check_line "AF2: it counts its OWN tasks, not the ancestor's" "$out" "OPEN_TASKS=1"
check_absent "AF2: no ancestor detection when nothing needed resolving" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
check_absent "AF2: no spurious PROJECT_RESOLVED" "$out" "PROJECT_RESOLVED="
check_absent "AF2: no spurious PROJECT_AMBIGUOUS" "$out" "PROJECT_AMBIGUOUS="

# --- TEST AG: .claude/session.json declares the slug, and it wins ------------
# Explicit beats guessing: the declaration outranks the basename EVEN WHEN the
# basename would itself have matched, so the guard cannot be satisfied by an
# implementation that only consults the file as a last resort.
mkdir -p "$CHILD/.claude"
echo '{"project":"comfyui-nodes"}' > "$CHILD/.claude/session.json"
out=$(run_nested)
check_line "AG: the declared slug is the effective one" "$out" "PROJECT=comfyui-nodes"
check_line "AG: the derivation is named" "$out" "DETECTION=declared"
check_line "AG: a declared slug is scoped like any project" "$out" "TASK_SCOPE=project"
check_line "AG: an explicit declaration is authoritative" "$out" "PROJECT_CONFIDENCE=high"
check_line "AG: it counts the DECLARED slug's tasks, not the basename's" "$out" "OPEN_TASKS=2"
check_absent "AG: a declared slug is never rewritten by the walk" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
out=$(run_nested --summary)
check_line "AG: summary carries the declared detection" "$out" "DETECTION=declared"
# An explicit --project still outranks the declaration.
out=$(run_nested --project comfyui-gallery-loader)
check_line "AG: --project still outranks a declaration" "$out" "DETECTION=override"
check_line "AG: --project selects its own slug" "$out" "PROJECT=comfyui-gallery-loader"
# A malformed declaration degrades to the derived signals rather than aborting.
# (The fixture still holds one task under the basename, so falling back is
# observable as the basename's OWN count — not merely as a missing key.)
echo 'not json at all' > "$CHILD/.claude/session.json"
out=$(run_nested)
rc=$?
check_eq "AG: a malformed declaration still exits 0" "$rc" "0"
check_line "AG: a malformed declaration falls back to the basename" \
  "$out" "PROJECT=comfyui-gallery-loader"
check_line "AG: the fallback counts the basename's tasks" "$out" "OPEN_TASKS=1"
check_absent "AG: a malformed declaration is never treated as declared" \
  "$out" "DETECTION=declared"
echo '{"other":"key"}' > "$CHILD/.claude/session.json"
out=$(run_nested)
check_line "AG: a session.json without a project key falls back" \
  "$out" "PROJECT=comfyui-gallery-loader"
check_absent "AG: a project-less session.json is never treated as declared" \
  "$out" "DETECTION=declared"

# --- TEST AG3: the declaration is UNTRUSTED repo content --------------------
# `.claude/session.json` arrives with a clone, so unlike --project (supplied by
# the invoking skill) its value is attacker/breakage-controlled. It is emitted
# as `PROJECT=` into a KEY=VALUE digest whose consumers read LINE-WISE
# (session-spinup-nudge.sh: `grep -m1 "^KEY="`), so a value carrying a newline
# injects whole fabricated rows. The degradation cases above are both
# UNPARSEABLE files; these are WELL-FORMED objects that clear the `type ==
# "object"` guard and reach the digest — the shapes that guard cannot catch.
inject='{"project":"comfyui-nodes\nOPEN_TASKS=999\nTHREADS=0"}'
printf '%s' "$inject" > "$CHILD/.claude/session.json"
out=$(run_nested)
check_absent "AG3: an injected OPEN_TASKS never reaches the digest" \
  "$out" "OPEN_TASKS=999"
check_count_line "AG3: the digest carries exactly one OPEN_TASKS row" \
  "$out" '^OPEN_TASKS=' 1
check_count_line "AG3: the digest carries exactly one PROJECT row" \
  "$out" '^PROJECT=' 1
check_absent "AG3: a multi-line declaration is never treated as declared" \
  "$out" "DETECTION=declared"
check_line "AG3: it degrades to the derived slug" \
  "$out" "PROJECT=comfyui-gallery-loader"
check_line "AG3: and to that slug's OWN count" "$out" "OPEN_TASKS=1"
# Consumer-level: the summary is what the SessionStart nudge parses, and the
# payload targets exactly the two keys it reads (OPEN_TASKS, THREADS).
out=$(run_nested --summary)
check_absent "AG3: the summary carries no injected OPEN_TASKS" \
  "$out" "OPEN_TASKS=999"
check_count_line "AG3: the summary carries exactly one OPEN_TASKS row" \
  "$out" '^OPEN_TASKS=' 1
check_count_line "AG3: the summary carries exactly one THREADS row" \
  "$out" '^THREADS=' 1
check_absent "AG3: the injected THREADS=0 never suppresses the nudge" \
  "$out" "THREADS=0"
# A non-string `.project` renders multi-line too, and passes `type == "object"`.
printf '%s' '{"project":["comfyui-nodes","x"]}' > "$CHILD/.claude/session.json"
out=$(run_nested)
check_count_line "AG3: an array .project emits exactly one PROJECT row" \
  "$out" '^PROJECT=' 1
# The count alone cannot see this shape: jq renders the array across four
# lines, of which only the first starts with `PROJECT=`. The leaked JSON body
# is what the digest must never carry.
check_absent "AG3: an array .project never leaks JSON into the digest" \
  "$out" '"comfyui-nodes",'
check_absent "AG3: an array .project is never treated as declared" \
  "$out" "DETECTION=declared"
check_line "AG3: an array .project degrades to the derived slug" \
  "$out" "PROJECT=comfyui-gallery-loader"
printf '%s' '{"project":123}' > "$CHILD/.claude/session.json"
out=$(run_nested)
check_absent "AG3: a numeric .project is never treated as declared" \
  "$out" "DETECTION=declared"
check_line "AG3: a numeric .project degrades to the derived slug" \
  "$out" "PROJECT=comfyui-gallery-loader"
# Guard integrity: rejecting bad shapes must not degenerate into rejecting
# EVERY declaration — the ordinary single-line string still wins outright.
echo '{"project":"comfyui-nodes"}' > "$CHILD/.claude/session.json"
out=$(run_nested)
check_line "AG3: a plain string declaration still wins" "$out" "DETECTION=declared"
check_line "AG3: and still selects the declared slug" "$out" "PROJECT=comfyui-nodes"
check_line "AG3: and still counts the declared slug's tasks" "$out" "OPEN_TASKS=2"

# --- TEST AG4: the declaration is read at the REPO ROOT, not only the cwd ----
# The lookup walks "$project_dir" then "$repo_root". Every case above invokes
# with --project-dir == the repo root, so the two are indistinguishable and the
# repo-root arm is dead weight no assertion can see. A session started in a
# SUBDIRECTORY is the ordinary case that separates them.
DEEP="$CHILD/sub/deeper"
mkdir -p "$DEEP"
out=$(bash "$COLLECTOR" --project-dir "$DEEP" --home-dir "$WS")
check_line "AG4: a declaration at the repo root is found from a subdir" \
  "$out" "DETECTION=declared"
check_line "AG4: and selects the declared slug" "$out" "PROJECT=comfyui-nodes"
check_line "AG4: and is scoped like any project" "$out" "TASK_SCOPE=project"
check_line "AG4: and stays authoritative" "$out" "PROJECT_CONFIDENCE=high"
# The count is attributable: the fixture holds 2 under the declared slug and 1
# under the basename, so a lookup that missed the repo root reports 1, not 2.
check_line "AG4: it counts the DECLARED slug's tasks from the subdir" \
  "$out" "OPEN_TASKS=2"
# Guard integrity: with no declaration the SAME invocation falls back to the
# basename, so the assertions above are attributable to the repo-root lookup
# and not to a fixture that would resolve either way.
mv "$CHILD/.claude/session.json" "$SANDBOX/session.json.bak"
out=$(bash "$COLLECTOR" --project-dir "$DEEP" --home-dir "$WS")
check_line "AG4: without a declaration the subdir uses the basename" \
  "$out" "DETECTION=cwd-repo-basename"
check_line "AG4: and that slug's own count" "$out" "OPEN_TASKS=1"
mv "$SANDBOX/session.json.bak" "$CHILD/.claude/session.json"

# --- TEST AH: PROJECT_AMBIGUOUS — the zero we may not adopt away ------------
# A user-asserted slug is never rewritten, so its zero must instead SAY that an
# ancestor holds N tasks. Otherwise session-end reads a clean 0 and skips.
echo '{"project":"comfyui-gallery-loader"}' > "$CHILD/.claude/session.json"
export TASK_ALL_FIXTURE="$SANDBOX/nested-parent-slug.json"
out=$(run_nested)
check_line "AH: the declared slug's zero is reported honestly" "$out" "OPEN_TASKS=0"
check_line "AH: the declared slug is not rewritten" "$out" "PROJECT=comfyui-gallery-loader"
check_line "AH: the ancestor holding the work is named" "$out" "PROJECT_AMBIGUOUS=comfyui-nodes"
# "0 here, N under <slug>" needs the N, or the consumer can only say "some".
check_line "AH: the ancestor's task count is reported" "$out" "PROJECT_AMBIGUOUS_TASKS=2"
out=$(run_nested --summary)
check_line "AH: the ambiguity reaches the hook summary" "$out" "PROJECT_AMBIGUOUS=comfyui-nodes"
# The N travels with the slug. Without it a summary consumer can only render
# "0 here, SOME under <slug>", which is not what the key exists to say.
check_line "AH: the summary carries the ancestor's count too" \
  "$out" "PROJECT_AMBIGUOUS_TASKS=2"
# Same for an explicit --project override.
rm -f "$CHILD/.claude/session.json"
out=$(run_nested --project comfyui-gallery-loader)
check_line "AH: an overridden slug is not rewritten either" "$out" "DETECTION=override"
check_line "AH: an overridden zero still names the ancestor" "$out" "PROJECT_AMBIGUOUS=comfyui-nodes"

# --- TEST AH2 (guard integrity): an honest zero stays a CLEAN zero ----------
# Nothing anywhere: the confident-zero path must not gain a phantom ancestor.
export TASK_ALL_FIXTURE=/dev/null
out=$(run_nested)
check_line "AH2: an empty store is still zero" "$out" "OPEN_TASKS=0"
check_line "AH2: an empty store keeps the project scope" "$out" "TASK_SCOPE=project"
check_line "AH2: an empty store is a confident zero" "$out" "PROJECT_CONFIDENCE=high"
check_absent "AH2: an empty store raises no ambiguity" "$out" "PROJECT_AMBIGUOUS="
check_absent "AH2: an empty store triggers no ancestor adoption" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
# Tasks exist, but under no ancestor of this repo: the honest zero is preserved
# and no ancestor may be named.
cat > "$SANDBOX/unrelated-slugs.json" <<'EOF'
[{"uuid":"u1","project":"zeta","description":"unrelated","modified":"20260601T101010Z"},
 {"uuid":"u2","project":"eta","description":"also unrelated","modified":"20260601T101010Z"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/unrelated-slugs.json"
out=$(run_nested)
check_line "AH2: unrelated tasks leave the scoped count at zero" "$out" "OPEN_TASKS=0"
check_absent "AH2: no ancestor is invented when none holds tasks" "$out" "PROJECT_AMBIGUOUS="
check_absent "AH2: no ancestor adoption when none holds tasks" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
check_line "AH2: the existing widening still applies" "$out" "TASK_SCOPE=all-projects-fallback"

# --- TEST AI: task unavailable — the existing degradation is preserved ------
export TASK_ALL_FIXTURE="$SANDBOX/nested-parent-slug.json"
out=$(SESSION_SURVEY_TASK_BIN=/nonexistent/task run_nested 2>&1)
rc=$?
check_eq "AI: no task binary still exits 0" "$rc" "0"
check_line "AI: task unavailable is reported" "$out" "TASK_AVAILABLE=false"
check_line "AI: task-absent is never a confident zero" "$out" "TASK_SCOPE=none"
check_line "AI: task-absent reports low confidence" "$out" "PROJECT_CONFIDENCE=low"
check_absent "AI: no ancestor is claimed without data to claim it from" \
  "$out" "PROJECT_AMBIGUOUS="
check_absent "AI: no ancestor adoption without a store to check against" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
check "AI: the digest is still parse-stable" "$out" "=== END TASKWARRIOR ==="

# --- TEST AJ: the walk stops at $HOME and never escapes it ------------------
# `above` is a repo ANCESTOR of the nested repo but sits at/above the boundary.
ABOVE="$SANDBOX/above"
BHOME="$ABOVE/home"
BNESTED="$BHOME/nested"
mkrepo "$ABOVE"
mkrepo "$BNESTED"
cat > "$SANDBOX/above-slug.json" <<'EOF'
[{"uuid":"a1","project":"above","description":"outside the boundary","modified":"20260601T101010Z"},
 {"uuid":"a2","project":"above","description":"also outside","modified":"20260601T101010Z"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/above-slug.json"
out=$(bash "$COLLECTOR" --project-dir "$BNESTED" --home-dir "$BHOME")
check_line "AJ: the boundary keeps the effective slug local" "$out" "PROJECT=nested"
check_line "AJ: nothing above \$HOME is adopted" "$out" "OPEN_TASKS=0"
check_absent "AJ: nothing above \$HOME is even named" "$out" "PROJECT_AMBIGUOUS="
check_absent "AJ: the walk did not escape the boundary" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
# Guard integrity: the SAME tree resolves once the boundary permits the walk,
# so the assertions above are attributable to the bound and not to a fixture
# the walk could never have resolved anyway.
out=$(bash "$COLLECTOR" --project-dir "$BNESTED" --home-dir "$SANDBOX")
check_line "AJ: a permitting boundary finds the same ancestor" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
check_line "AJ: and adopts its slug" "$out" "PROJECT=above"
check_line "AJ: and its tasks" "$out" "OPEN_TASKS=2"

# --- TEST AJ2: the boundary is re-applied to what GIT's own walk returns -----
# AJ only exercises the OUTER check (the first `dir` already fails it, so the
# `rev-parse` line is never reached). The case that needs the INNER one is the
# dotfiles shape the code comment names: $HOME is ITSELF a repo, with a PLAIN
# non-repo directory between it and the nested repo. The outer check passes on
# that plain directory — it IS strictly below $HOME — and git's own upward
# discovery then returns $HOME, escaping the boundary by proxy.
IHOME="$SANDBOX/dotfiles-home"
IPLAIN="$IHOME/plain"
INESTED="$IPLAIN/inner"
mkrepo "$IHOME"
mkdir -p "$IPLAIN"          # deliberately NOT a repo: this is what defeats the
mkrepo "$INESTED"           # outer check and hands the walk to git's discovery
cat > "$SANDBOX/dotfiles-slug.json" <<'EOF'
[{"uuid":"d1","project":"dotfiles-home","description":"the home repo's own backlog","modified":"20260601T101010Z"},
 {"uuid":"d2","project":"dotfiles-home","description":"and another","modified":"20260601T101010Z"}]
EOF
export TASK_ALL_FIXTURE="$SANDBOX/dotfiles-slug.json"
out=$(bash "$COLLECTOR" --project-dir "$INESTED" --home-dir "$IHOME")
check_line "AJ2: a dotfiles repo AT \$HOME does not swallow the slug" \
  "$out" "PROJECT=inner"
check_absent "AJ2: the walk does not escape \$HOME via git's own discovery" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
check_line "AJ2: nothing at the boundary is adopted" "$out" "OPEN_TASKS=0"
check_absent "AJ2: nor named" "$out" "PROJECT_AMBIGUOUS="
check_line "AJ2: the honest zero is still visibly widened" \
  "$out" "TASK_SCOPE=all-projects-fallback"
# Guard integrity: the SAME tree resolves once the boundary sits above $HOME,
# so the non-resolution is attributable to the inner check and not to a fixture
# git could never have reached.
out=$(bash "$COLLECTOR" --project-dir "$INESTED" --home-dir "$SANDBOX")
check_line "AJ2: a permitting boundary reaches the same repo via git" \
  "$out" "DETECTION=cwd-repo-basename-ancestor"
check_line "AJ2: and adopts its slug" "$out" "PROJECT=dotfiles-home"
check_line "AJ2: and its tasks" "$out" "OPEN_TASKS=2"

# ============================================================================
# TEST AK: the prefix-sibling split (#2323)
#
# taskwarrior's CLI `project:<p>` filter is a PREFIX match, so
# `task project:comfyui list` returns every `comfyui-nodes` task too. A slug
# "verified" that way looks confirmed while its own backlog is near-empty, and
# follow-ups then land in a sibling nobody reads. The collector scopes in jq
# (hierarchy match), so it never miscounts — but a `high`-confidence
# `OPEN_TASKS=1` beside 60 sibling tasks is still a misfiled backlog reading as
# a verified one. These tests pin the split being SURFACED, and pin equally
# hard that a store with no siblings is left alone.
# ============================================================================

# The issue's own store: 1 task under `comfyui`, 60 under `comfyui-nodes`.
jq -n --arg m "$(tw_stamp 1)" '
  [{uuid:"cf-1", project:"comfyui", description:"the near-empty sibling", modified:$m}]
  + [range(60) | {uuid:("cn"+(.|tostring)), project:"comfyui-nodes",
                  description:("pack task "+(.|tostring)), modified:$m}]' \
  > "$SANDBOX/comfyui-split.json"

CFY="$SANDBOX/comfyui"
CFN="$SANDBOX/comfyui-nodes"
mkrepo "$CFY"
mkrepo "$CFN"
export TASK_ALL_FIXTURE="$SANDBOX/comfyui-split.json"

# --- AK1: the decisive case — the wrong slug must not report the sibling's 60
out=$(run_at "$CFY")
check_line "AK1: the slug's own backlog is counted, not the prefix hit's" \
  "$out" "OPEN_TASKS=1"
check_line "AK1: the exact-value count is emitted alongside it" \
  "$out" "PROJECT_EXACT_TASKS=1"
check_line "AK1: the swept-in siblings are named" \
  "$out" "PROJECT_PREFIX_SIBLINGS=comfyui-nodes"
check_line "AK1: and counted" "$out" "PROJECT_PREFIX_SIBLING_TASKS=60"
check_line "AK1: a dominated slug is no longer confident" \
  "$out" "PROJECT_CONFIDENCE=low"
check_absent "AK1: the sibling's tasks are never scoped in" "$out" "TASK_1_UUID=cn0"
check_count_line "AK1: exactly one exact-count key" "$out" '^PROJECT_EXACT_TASKS=' 1

# --- AK2 (known-good control): the same store, from the slug that owns it ----
# Without this the fix could be "always report low" and AK1 would still pass.
out=$(run_at "$CFN")
check_line "AK2: the owning slug counts all 60" "$out" "OPEN_TASKS=60"
check_line "AK2: exact count agrees when there are no subprojects" \
  "$out" "PROJECT_EXACT_TASKS=60"
check_line "AK2: the owning slug keeps the project scope" "$out" "TASK_SCOPE=project"
check_line "AK2: and stays confident" "$out" "PROJECT_CONFIDENCE=high"
check_absent "AK2: no siblings, so no sibling keys" "$out" "PROJECT_PREFIX_SIBLINGS="
check_absent "AK2: nor a sibling count" "$out" "PROJECT_PREFIX_SIBLING_TASKS="

# --- AK3 (guard integrity): a SMALLER sibling is surfaced, never a downgrade --
# The downgrade is strict dominance, not "a sibling exists" — otherwise every
# `dotfiles` beside a `dotfiles-archive` would read as unresolved forever.
jq -n --arg m "$(tw_stamp 1)" '
  [range(60) | {uuid:("co"+(.|tostring)), project:"comfyui",
                description:("owned "+(.|tostring)), modified:$m}]
  + [{uuid:"cn-x", project:"comfyui-nodes", description:"one stray", modified:$m}]' \
  > "$SANDBOX/comfyui-minor-sibling.json"
export TASK_ALL_FIXTURE="$SANDBOX/comfyui-minor-sibling.json"
out=$(run_at "$CFY")
check_line "AK3: the owning slug counts its own 60" "$out" "OPEN_TASKS=60"
check_line "AK3: a minority sibling does not cost confidence" \
  "$out" "PROJECT_CONFIDENCE=high"
check_line "AK3: but the split is still surfaced, not silenced" \
  "$out" "PROJECT_PREFIX_SIBLINGS=comfyui-nodes"
check_line "AK3: with its own count" "$out" "PROJECT_PREFIX_SIBLING_TASKS=1"

# --- AK4: a `.` subproject is IN scope and is NOT a prefix sibling -----------
# The two counts differ only here, which is what makes the exact one worth
# emitting: OPEN_TASKS is the hierarchy match, PROJECT_EXACT_TASKS the slug.
jq -n --arg m "$(tw_stamp 1)" '
  [{uuid:"cx-1", project:"comfyui", description:"the slug itself", modified:$m},
   {uuid:"cx-2", project:"comfyui.web", description:"a real subproject", modified:$m},
   {uuid:"cx-3", project:"comfyui.web", description:"another", modified:$m},
   {uuid:"cx-4", project:"comfyui-nodes", description:"a prefix sibling", modified:$m}]' \
  > "$SANDBOX/comfyui-hierarchy.json"
export TASK_ALL_FIXTURE="$SANDBOX/comfyui-hierarchy.json"
out=$(run_at "$CFY")
check_line "AK4: subprojects count inside the scope" "$out" "OPEN_TASKS=3"
check_line "AK4: the exact count excludes them" "$out" "PROJECT_EXACT_TASKS=1"
check_line 'AK4: a dot-separated child is never reported as a prefix sibling' \
  "$out" "PROJECT_PREFIX_SIBLINGS=comfyui-nodes"
check_line "AK4: nor counted as one" "$out" "PROJECT_PREFIX_SIBLING_TASKS=1"
check_line "AK4: a dominant hierarchy scope stays confident" \
  "$out" "PROJECT_CONFIDENCE=high"

# --- AK5: an ASSERTED slug is downgraded too, and named ---------------------
# The reported case was a slug asserted in CLAUDE.md on the strength of a prefix
# hit. Assertion fixes the slug's identity; it cannot assert what the store
# holds — so unlike the adoption rungs, this signal is not suppressed for
# --project. Nothing is rewritten: the scope and the count stay the caller's.
export TASK_ALL_FIXTURE="$SANDBOX/comfyui-split.json"
out=$(bash "$COLLECTOR" --project-dir "$REPO" --project comfyui)
check_line "AK5: an asserted slug keeps its own scope" "$out" "TASK_SCOPE=project"
check_line "AK5: and its own count" "$out" "OPEN_TASKS=1"
check_line "AK5: but not a confident one when siblings dominate" \
  "$out" "PROJECT_CONFIDENCE=low"
check_line "AK5: the sibling holding the backlog is named" \
  "$out" "PROJECT_PREFIX_SIBLINGS=comfyui-nodes"
check_line "AK5: the slug is never rewritten to the sibling" "$out" "PROJECT=comfyui"

# --- AK6: the hook's summary carries the split too --------------------------
out=$(run_at "$CFY" --summary)
check_line "AK6: summary carries the exact count" "$out" "PROJECT_EXACT_TASKS=1"
check_line "AK6: summary names the siblings" \
  "$out" "PROJECT_PREFIX_SIBLINGS=comfyui-nodes"
check_line "AK6: summary carries the sibling count" \
  "$out" "PROJECT_PREFIX_SIBLING_TASKS=60"
check_line "AK6: summary carries the downgrade" "$out" "PROJECT_CONFIDENCE=low"
check_line "AK6: the summary is still parse-stable" \
  "$out" "=== END SESSION SURVEY SUMMARY ==="
out=$(run_at "$CFN" --summary)
check_absent "AK6 (control): no sibling keys in a clean summary" \
  "$out" "PROJECT_PREFIX_SIBLINGS="

# --- AK7: the split reuses the ONE snapshot; no `project:` filter appears ----
export TASK_ARGV_LOG="$SANDBOX/task-argv-2323.log"
: > "$TASK_ARGV_LOG"
export TASK_ALL_FIXTURE="$SANDBOX/comfyui-split.json"
out=$(run_at "$CFY")
exports=$(grep -c 'export' "$TASK_ARGV_LOG" || true)
check_eq "AK7: still exactly one export call" "$exports" "1"
check_absent "AK7: the prefix split never shells out a project: filter" \
  "$(cat "$TASK_ARGV_LOG")" "project:"
unset TASK_ARGV_LOG

# --- AK8: degradation — a missing binary never fabricates a confident number -
export TASK_ALL_FIXTURE="$SANDBOX/comfyui-split.json"
out=$(PATH="$NOJQ" bash "$COLLECTOR" --project-dir "$CFY" 2>&1)
check_line "AK8: no jq means no scoping, so no confidence" \
  "$out" "PROJECT_CONFIDENCE=low"
check_line "AK8: and the unqueried state is named" "$out" "TASK_SCOPE=unknown"
check_line "AK8: the exact count stays an integer, never a sentinel" \
  "$out" "PROJECT_EXACT_TASKS=0"
check_absent "AK8: no siblings are claimed from an unqueried store" \
  "$out" "PROJECT_PREFIX_SIBLINGS="
check_line "AK8: the digest is still parse-stable" "$out" "=== END TASKWARRIOR ==="
# No `task` binary at all.
out=$(SESSION_SURVEY_TASK_BIN="$SANDBOX/does-not-exist" \
  bash "$COLLECTOR" --project-dir "$CFY" 2>/dev/null)
check_line "AK9: a missing task binary is named" "$out" "TASK_AVAILABLE=false"
check_line "AK9: and never confident" "$out" "PROJECT_CONFIDENCE=low"
check_line "AK9: exact count is a parse-stable zero" "$out" "PROJECT_EXACT_TASKS=0"
check_absent "AK9: no siblings from a store that was never opened" \
  "$out" "PROJECT_PREFIX_SIBLINGS="
# An empty store: nothing to split, and nothing to downgrade.
export TASK_ALL_FIXTURE=/dev/null
out=$(run_at "$CFY")
check_line "AK9: an empty store is still a confident zero" \
  "$out" "PROJECT_CONFIDENCE=high"
check_line "AK9: with a zero exact count" "$out" "PROJECT_EXACT_TASKS=0"
check_absent "AK9: and no sibling keys" "$out" "PROJECT_PREFIX_SIBLINGS="

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
