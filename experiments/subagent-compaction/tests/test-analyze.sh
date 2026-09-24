#!/usr/bin/env bash
# Offline test for analyze.sh against synthetic arm directories: one subagent
# that compacts once, a report with one correct / one wrong / one declared-
# missing / one absent sentinel, and a PreCompact hook carrying an agent_id.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
analyze="$here/../scripts/analyze.sh"
tmp="$(mktemp -d)"
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/sentinels.txt" <<'EOF'
SENTINEL f01.txt aaaaaaaaaaaa
SENTINEL f02.txt bbbbbbbbbbbb
SENTINEL f03.txt cccccccccccc
SENTINEL f04.txt dddddddddddd
EOF

# make_arm <dir> <final-report-text-as-json-string>
make_arm() {
  local arm="$1" report="$2" sub="$1/home/.claude/projects/p/s/subagents"
  mkdir -p "$sub"
  # msg_1 appears twice (two content blocks) and must be counted once.
  cat > "$sub/agent-x.jsonl" <<EOF
{"type":"assistant","message":{"id":"msg_1","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":20000},"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/f/f01.txt"}}]}}
{"type":"assistant","message":{"id":"msg_1","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":20000},"content":[{"type":"text","text":"reading"}]}}
{"type":"assistant","message":{"id":"msg_2","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":20000,"cache_creation_input_tokens":90000},"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/f/f02.txt"}}]}}
{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":110010,"postTokens":6000}}
{"type":"user","isCompactSummary":true,"message":{"content":"summary"}}
{"type":"assistant","message":{"id":"msg_3","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":26000},"content":[{"type":"text","text":$report}]}}
EOF
  # The main relay deliberately differs, so a main-sourced score is detectable.
  cat > "$arm/main.jsonl" <<'EOF'
{"type":"system","subtype":"init"}
{"type":"result","subtype":"success","total_cost_usd":0.5,"result":"SENTINEL f01.txt 000000000000"}
EOF
  cat > "$arm/hooks.jsonl" <<'EOF'
{"hook_event_name":"SubagentStart","agent_id":"x"}
{"hook_event_name":"PreCompact","trigger":"auto","agent_id":"x","session_id":"s"}
{"hook_event_name":"PostCompact","trigger":"auto"}
{"hook_event_name":"SubagentStop","agent_id":"x"}
EOF
}

fail=0
out=""
has() { printf '%s\n' "$out" | grep -qx "$1"; }
expect() { if has "$1"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi; }
absent() { if printf '%s\n' "$out" | grep -q "$1"; then echo "FAIL absent $1"; fail=1; else echo "PASS absent $1"; fi; }
run() { out="$(bash "$analyze" "$1" "$tmp/sentinels.txt" || true)"; }

# --- 1. Baseline: subagent report scored, compaction counted -----------------
arm="$tmp/opus_1m_-ac-on"
make_arm "$arm" '"SENTINEL f01.txt aaaaaaaaaaaa\nSENTINEL f02.txt 000000000000\nMISSING f03.txt"'
run "$arm"
expect 'SUBAGENT_COUNT=1'
expect 'API_CALLS=3'
expect 'START_CTX=20010'
expect 'PEAK_CTX=110010'
expect 'CTX_SERIES=20010,110010,26010'
expect 'READ_CALLS=2'
expect 'DISTINCT_FILES_READ=2'
expect 'COMPACTIONS=1'
expect 'COMPACTIONS_AUTO=1'
expect 'COMPACT_TRIGGERS=auto'
expect 'COMPACT_PRE_TOKENS=110010'
expect 'SUBAGENT_COMPACTED=yes'
expect 'SUBAGENT_AUTO_COMPACTED=yes'
expect 'SUBAGENT_PARSE_ERRORS=0'
expect 'HOOK_PreCompact=1'
expect 'PRECOMPACT_WITH_AGENT_ID=1'
expect 'PRECOMPACT_KEYS=agent_id,hook_event_name,session_id,trigger'
expect 'REPORT_SOURCE=subagent'
expect 'SENTINELS_EXPECTED=4'
expect 'SENTINELS_CORRECT=1'
expect 'SENTINELS_WRONG=1'
expect 'SENTINELS_DECLARED_MISSING=1'
expect 'SENTINELS_ABSENT=1'
expect 'STATUS=OK'
expect 'ISSUE_COUNT=0'
absent '^REASON='

# --- 2. Formatting noise: CR, backticks, list markers normalize away ---------
arm2="$tmp/fmt"
# Backticks are literal report content, not command substitution.
# shellcheck disable=SC2016
make_arm "$arm2" '"- `SENTINEL f01.txt aaaaaaaaaaaa`\r\n2. SENTINEL f02.txt bbbbbbbbbbbb  \r\n* MISSING f03.txt"'
run "$arm2"
expect 'SENTINELS_CORRECT=2'
expect 'SENTINELS_WRONG=0'
expect 'SENTINELS_DECLARED_MISSING=1'

# --- 3. Exact matching: a prefix-sharing name must not count ----------------
arm3="$tmp/exact"
make_arm "$arm3" '"MISSING f01.txt.bak\nSENTINEL f02.txt.bak bbbbbbbbbbbb"'
run "$arm3"
expect 'SENTINELS_CORRECT=0'
expect 'SENTINELS_DECLARED_MISSING=0'
expect 'SENTINELS_ABSENT=4'
expect 'STATUS=WARN'
expect 'REASON=report_unparsed: no sentinel or MISSING line found in the subagent report'

# --- 4. Truncated transcript: WARN, not a clean "no compaction" --------------
arm4="$tmp/trunc"
make_arm "$arm4" '"SENTINEL f01.txt aaaaaaaaaaaa"'
printf '{"type":"system","subtype":"compact_bou' >> "$arm4/home/.claude/projects/p/s/subagents/agent-x.jsonl"
run "$arm4"
expect 'SUBAGENT_PARSE_ERRORS=1'
expect 'STATUS=WARN'
expect 'ISSUE_COUNT=1'
expect '  - SEVERITY=WARN TYPE=transcript_truncated MSG=1 unparseable transcript line(s); counts may be incomplete'

# --- 5. No subagent text: fall back to the main relay ------------------------
arm5="$tmp/fallback"
make_arm "$arm5" '""'
jq -c 'if .message.id=="msg_3" then .message.content=[] else . end' \
  "$arm5/home/.claude/projects/p/s/subagents/agent-x.jsonl" > "$tmp/x" \
  && mv "$tmp/x" "$arm5/home/.claude/projects/p/s/subagents/agent-x.jsonl"
jq -c 'if .message.id=="msg_1" then .message.content=[.message.content[] | select(.type!="text")] else . end' \
  "$arm5/home/.claude/projects/p/s/subagents/agent-x.jsonl" > "$tmp/x" \
  && mv "$tmp/x" "$arm5/home/.claude/projects/p/s/subagents/agent-x.jsonl"
run "$arm5"
expect 'REPORT_SOURCE=main'
expect 'SENTINELS_WRONG=1'

# --- 6. Missing main transcript is a failed run, not a clean zero ------------
rm "$arm/main.jsonl"
run "$arm"
expect 'STATUS=ERROR'
expect 'REASON=run_failed: main.jsonl has no result event'
if bash "$analyze" "$arm" "$tmp/sentinels.txt" >/dev/null; then
  echo 'FAIL exit 1 on ERROR'; fail=1
else
  echo 'PASS exit 1 on ERROR'
fi

# --- 7. No subagent at all ---------------------------------------------------
arm7="$tmp/nosub"
mkdir -p "$arm7"
cp "$arm2/main.jsonl" "$arm7/main.jsonl"
run "$arm7"
expect 'SUBAGENT_COUNT=0'
expect 'STATUS=ERROR'
expect 'REASON=no_subagent: no subagent transcript under the arm HOME'

exit "$fail"
