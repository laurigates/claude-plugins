#!/usr/bin/env bash
# Offline test for analyze.sh against a synthetic arm directory: one subagent
# that compacts once, a report with one correct / one wrong / one declared-
# missing / one absent sentinel, and a PreCompact hook carrying an agent_id.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
analyze="$here/../scripts/analyze.sh"
tmp="$(mktemp -d)"
if [ -z "$tmp" ] || [ ! -d "$tmp" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$tmp"' EXIT

arm="$tmp/opus_1m_-ac-on"
sub="$arm/home/.claude/projects/p/s/subagents"
mkdir -p "$sub"

cat > "$tmp/sentinels.txt" <<'EOF'
SENTINEL f01.txt aaaaaaaaaaaa
SENTINEL f02.txt bbbbbbbbbbbb
SENTINEL f03.txt cccccccccccc
SENTINEL f04.txt dddddddddddd
EOF

# msg_1 appears twice (two content blocks) and must be counted once.
cat > "$sub/agent-x.jsonl" <<'EOF'
{"type":"assistant","message":{"id":"msg_1","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":20000},"content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/f/f01.txt"}}]}}
{"type":"assistant","message":{"id":"msg_1","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":20000},"content":[{"type":"text","text":"reading"}]}}
{"type":"assistant","message":{"id":"msg_2","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":20000,"cache_creation_input_tokens":90000},"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/f/f02.txt"}}]}}
{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"auto","preTokens":110010,"postTokens":6000}}
{"type":"user","isCompactSummary":true,"message":{"content":"summary"}}
{"type":"assistant","message":{"id":"msg_3","model":"claude-test","usage":{"input_tokens":10,"cache_read_input_tokens":0,"cache_creation_input_tokens":26000},"content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"/f/f02.txt"}}]}}
EOF

cat > "$arm/main.jsonl" <<'EOF'
{"type":"system","subtype":"init"}
{"type":"result","subtype":"success","total_cost_usd":0.5,"result":"SENTINEL f01.txt aaaaaaaaaaaa\nSENTINEL f02.txt 000000000000\nMISSING f03.txt"}
EOF

cat > "$arm/hooks.jsonl" <<'EOF'
{"hook_event_name":"SubagentStart","agent_id":"x"}
{"hook_event_name":"PreCompact","trigger":"auto","agent_id":"x","session_id":"s"}
{"hook_event_name":"PostCompact","trigger":"auto"}
{"hook_event_name":"SubagentStop","agent_id":"x"}
EOF

out="$(bash "$analyze" "$arm" "$tmp/sentinels.txt")"

fail=0
expect() {
  if printf '%s\n' "$out" | grep -qx "$1"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}
expect 'SUBAGENT_COUNT=1'
expect 'API_CALLS=3'
expect 'START_CTX=20010'
expect 'PEAK_CTX=110010'
expect 'CTX_SERIES=20010,110010,26010'
expect 'READ_CALLS=3'
expect 'DISTINCT_FILES_READ=2'
expect 'COMPACTIONS=1'
expect 'COMPACT_TRIGGERS=auto'
expect 'COMPACT_PRE_TOKENS=110010'
expect 'SUBAGENT_COMPACTED=yes'
expect 'HOOK_PreCompact=1'
expect 'PRECOMPACT_WITH_AGENT_ID=1'
expect 'PRECOMPACT_KEYS=agent_id,hook_event_name,session_id,trigger'
expect 'SENTINELS_CORRECT=1'
expect 'SENTINELS_WRONG=1'
expect 'SENTINELS_DECLARED_MISSING=1'
expect 'SENTINELS_ABSENT=1'
expect 'OUTCOME=ok'
expect 'STATUS=OK'
if printf '%s\n' "$out" | grep -q '^REASON='; then echo 'FAIL REASON= absent on OK'; fail=1; else echo 'PASS REASON= absent on OK'; fi

# A missing main transcript is a failed run, not a clean zero.
rm "$arm/main.jsonl"
out="$(bash "$analyze" "$arm" "$tmp/sentinels.txt")"
expect 'OUTCOME=run_failed'
expect 'STATUS=ERROR'
expect 'REASON=run_failed: main.jsonl has no result event'

exit "$fail"
