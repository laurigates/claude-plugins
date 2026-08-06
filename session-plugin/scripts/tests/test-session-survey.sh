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

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
