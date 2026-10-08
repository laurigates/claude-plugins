#!/usr/bin/env bash
# Regression test for check-runtime.sh (runtime scope).
# Semantic invariants guarded:
#   1. Clean ~/.claude.json + no history.jsonl → STATUS=OK, retention default 30.
#   2. Dead projects[] → WARN, and the cleanup hint names the native `claude purge`.
#   3. Legacy per-project `history` arrays in ~/.claude.json (pre-history.jsonl
#      layout) are counted and reported as INFO, never raising STATUS.
#   4. ~/.claude/history.jsonl is measured (bytes, entries, malformed lines,
#      entries for deleted project dirs) and is reported as NOT covered by the
#      cleanupPeriodDays sweep.
#   5. cleanupPeriodDays resolution: local > project > user > default 30;
#      0 / non-integer → ERROR (it fails validation and pauses the sweep).
#   6. history.jsonl over --history-warn-mb → WARN.
# Exit 0 on success, non-zero on failure.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check_script="${script_dir}/../check-runtime.sh"

fail() { printf 'FAIL: %b\n' "$1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed; cannot run check-runtime tests"
  exit 0
fi

[ -f "$check_script" ] || fail "check-runtime.sh not found at $check_script"

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

expect() {  # $1 = output, $2 = anchored regex, $3 = label
  echo "$1" | grep -qE "$2" || fail "$3: expected /$2/ in:\n$1"
}
reject() {  # $1 = output, $2 = regex, $3 = label
  echo "$1" | grep -qE "$2" && fail "$3: did not expect /$2/ in:\n$1"
  return 0
}

# -----------------------------------------------------------------------------
# Case 1: clean state
# -----------------------------------------------------------------------------
home1="${tmp_root}/h1"; proj1="${tmp_root}/p1"
mkdir -p "$home1/.claude" "$proj1"
jq -n --arg p "$proj1" '{projects: {($p): {allowedTools: []}}, mcpServers: {}}' > "$home1/.claude.json"
out1="$(bash "$check_script" --home-dir "$home1" --project-dir "$proj1")"
expect "$out1" '^STATUS=OK$' "Case1"
expect "$out1" '^LEGACY_PROJECT_HISTORY_ENTRIES=0$' "Case1"
expect "$out1" '^HISTORY_JSONL_EXISTS=false$' "Case1"
expect "$out1" '^CLEANUP_PERIOD_DAYS=30$' "Case1"
expect "$out1" '^CLEANUP_PERIOD_SOURCE=default$' "Case1"
pass "clean state → OK, default retention 30"

# -----------------------------------------------------------------------------
# Case 2: dead project → WARN + `claude purge` hint
# -----------------------------------------------------------------------------
home2="${tmp_root}/h2"; mkdir -p "$home2/.claude"
jq -n '{projects: {"/nonexistent/gone-project": {}}}' > "$home2/.claude.json"
out2="$(bash "$check_script" --home-dir "$home2" --project-dir "$tmp_root")"
expect "$out2" '^STATUS=WARN$' "Case2"
expect "$out2" '^PROJECTS_DEAD=1$' "Case2"
expect "$out2" 'claude purge' "Case2 cleanup hint"
pass "dead project → WARN with claude purge hint"

# -----------------------------------------------------------------------------
# Case 3: legacy per-project history arrays → INFO only
# -----------------------------------------------------------------------------
home3="${tmp_root}/h3"; proj3="${tmp_root}/p3"
mkdir -p "$home3/.claude" "$proj3"
jq -n --arg p "$proj3" '{projects: {($p): {history: [{display: "a"}, {display: "b"}, {display: "c"}]}}}' > "$home3/.claude.json"
out3="$(bash "$check_script" --home-dir "$home3" --project-dir "$proj3")"
expect "$out3" '^LEGACY_PROJECT_HISTORY_ENTRIES=3$' "Case3"
expect "$out3" '^LEGACY_PROJECT_HISTORY_PROJECTS=1$' "Case3"
expect "$out3" 'SEVERITY=INFO TYPE=legacy_project_history' "Case3"
expect "$out3" '^STATUS=OK$' "Case3 (INFO must not raise STATUS)"
expect "$out3" '^ISSUE_COUNT=0$' "Case3"
pass "legacy projects[].history → INFO, STATUS stays OK"

# -----------------------------------------------------------------------------
# Case 4: history.jsonl measured; dead-project + malformed lines counted
# -----------------------------------------------------------------------------
home4="${tmp_root}/h4"; proj4="${tmp_root}/p4"
mkdir -p "$home4/.claude" "$proj4"
jq -n '{}' > "$home4/.claude.json"
{
  jq -nc --arg p "$proj4" '{display: "one", timestamp: 1, project: $p}'
  jq -nc --arg p "$proj4" '{display: "two", timestamp: 2, project: $p}'
  jq -nc '{display: "three", timestamp: 3, project: "/nonexistent/gone-project"}'
  echo '{not json'
} > "$home4/.claude/history.jsonl"
out4="$(bash "$check_script" --home-dir "$home4" --project-dir "$proj4")"
expect "$out4" '^HISTORY_JSONL_EXISTS=true$' "Case4"
expect "$out4" '^HISTORY_JSONL_ENTRIES=4$' "Case4"
expect "$out4" '^HISTORY_JSONL_MALFORMED=1$' "Case4"
expect "$out4" '^HISTORY_JSONL_DEAD_PROJECT_ENTRIES=1$' "Case4"
expect "$out4" '^HISTORY_JSONL_SWEPT=false$' "Case4 (not covered by cleanupPeriodDays)"
expect "$out4" 'SEVERITY=INFO TYPE=history_dead_projects' "Case4"
expect "$out4" '^STATUS=OK$' "Case4"
pass "history.jsonl measured, dead/malformed counted, not swept"

# -----------------------------------------------------------------------------
# Case 5: cleanupPeriodDays precedence and validation
# -----------------------------------------------------------------------------
home5="${tmp_root}/h5"; proj5="${tmp_root}/p5"
mkdir -p "$home5/.claude" "$proj5/.claude"
jq -n '{}' > "$home5/.claude.json"
echo '{"cleanupPeriodDays": 90}' > "$home5/.claude/settings.json"
out5a="$(bash "$check_script" --home-dir "$home5" --project-dir "$proj5")"
expect "$out5a" '^CLEANUP_PERIOD_DAYS=90$' "Case5 user"
expect "$out5a" '^CLEANUP_PERIOD_SOURCE=user$' "Case5 user"

echo '{"cleanupPeriodDays": 14}' > "$proj5/.claude/settings.json"
echo '{"cleanupPeriodDays": 7}' > "$proj5/.claude/settings.local.json"
out5b="$(bash "$check_script" --home-dir "$home5" --project-dir "$proj5")"
expect "$out5b" '^CLEANUP_PERIOD_DAYS=7$' "Case5 local wins"
expect "$out5b" '^CLEANUP_PERIOD_SOURCE=local$' "Case5 local wins"

echo '{"cleanupPeriodDays": 0}' > "$proj5/.claude/settings.local.json"
out5c="$(bash "$check_script" --home-dir "$home5" --project-dir "$proj5")"
expect "$out5c" '^STATUS=ERROR$' "Case5 zero"
expect "$out5c" 'SEVERITY=ERROR TYPE=invalid_cleanup_period' "Case5 zero"

echo '{"cleanupPeriodDays": "thirty"}' > "$proj5/.claude/settings.local.json"
out5d="$(bash "$check_script" --home-dir "$home5" --project-dir "$proj5")"
expect "$out5d" 'SEVERITY=ERROR TYPE=invalid_cleanup_period' "Case5 non-integer"
pass "cleanupPeriodDays: local > project > user > default; 0/non-int → ERROR"

# -----------------------------------------------------------------------------
# Case 6: oversized history.jsonl → WARN
# -----------------------------------------------------------------------------
home6="${tmp_root}/h6"; mkdir -p "$home6/.claude"
jq -n '{}' > "$home6/.claude.json"
line="$(jq -nc --arg p "$tmp_root" --arg d "$(printf 'x%.0s' $(seq 1 1000))" '{display: $d, timestamp: 1, project: $p}')"
for _ in $(seq 1 1200); do echo "$line"; done > "$home6/.claude/history.jsonl"
out6="$(bash "$check_script" --home-dir "$home6" --project-dir "$tmp_root" --history-warn-mb 1)"
expect "$out6" 'SEVERITY=WARN TYPE=history_large' "Case6"
expect "$out6" '^STATUS=WARN$' "Case6"
out6b="$(bash "$check_script" --home-dir "$home6" --project-dir "$tmp_root")"
reject "$out6b" 'TYPE=history_large' "Case6 default threshold"
pass "history.jsonl over --history-warn-mb → WARN"

echo "ALL PASS"
