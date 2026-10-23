#!/usr/bin/env bash
# Run one synthetic-task cell: copy the task fixture into a fresh workdir, run a
# lean headless `claude -p` on it, grade the workdir with the hidden check, and
# append one JSON line to the results file.
#
# Usage: run_cell.sh <set-dir> <task-id> <model-id> <rep> [effort]
#   <set-dir>   basic/ or hard/ (after its make_tasks.py has built tasks/)
#   effort      default medium
#
# Env:
#   MC_RUNS_DIR         per-cell workdirs + results (default ${TMPDIR:-/tmp}/model-compare-runs)
#   MC_RESULTS          results JSONL (default $MC_RUNS_DIR/results.jsonl)
#   MC_MAX_BUDGET_USD   per-cell --max-budget-usd cap (default 1.00)
#   MC_TIMEOUT          per-cell wall-clock seconds (default 1200)
#
# The lean flags (no settings, plugins, slash commands or MCP) cut the fixed
# prompt from ~35K to ~6.5K tokens, so a cell measures the model on the task,
# not the harness overhead. Each cell gets its own --session-id: a child
# `claude -p` launched from inside a session otherwise inherits the parent's id
# and writes into the same transcript.
set -u
[ $# -ge 4 ] || { echo "usage: run_cell.sh <set-dir> <task-id> <model-id> <rep> [effort]" >&2; exit 2; }
SET=$(cd "$1" 2>/dev/null && pwd) || { echo "no such set dir: $1" >&2; exit 2; }
TID=$2 MODEL=$3 REP=$4 EFFORT=${5:-medium}
T="$SET/tasks/$TID"
if [ ! -f "$T/prompt.txt" ] || [ ! -f "$T/check.py" ]; then
    echo "task not built: $T (run $SET/validate.sh)" >&2; exit 2
fi
command -v claude >/dev/null 2>&1 || { echo "claude CLI not found" >&2; exit 2; }
RUNS=${MC_RUNS_DIR:-${TMPDIR:-/tmp}/model-compare-runs}
RESULTS=${MC_RESULTS:-$RUNS/results.jsonl}
CELL="$RUNS/$(basename "$SET")/$TID.$MODEL.$REP"
rm -rf "$CELL"; mkdir -p "$CELL/work" "$(dirname "$RESULTS")"
cp -r "$T/fixture/." "$CELL/work/"
SID=$(python3 -c 'import uuid; print(uuid.uuid4())')
START=$(date +%s)
( cd "$CELL/work" && timeout "${MC_TIMEOUT:-1200}" claude -p "$(cat "$T/prompt.txt")" \
    --model "$MODEL" --effort "$EFFORT" --session-id "$SID" \
    --disable-slash-commands --strict-mcp-config --setting-sources "" \
    --exclude-dynamic-system-prompt-sections \
    --tools "Bash,Read,Edit,Write" --allowedTools "Bash,Read,Edit,Write" \
    --output-format json --max-budget-usd "${MC_MAX_BUDGET_USD:-1.00}" \
    </dev/null >"$CELL/out.json" 2>"$CELL/err.txt" )
EXIT=$?
DUR=$(( $(date +%s) - START ))
CHECK=$(cd "${TMPDIR:-/tmp}" && python3 -I "$T/check.py" "$CELL/work" 2>&1 | tail -1)
python3 -c 'import json,sys; json.loads(sys.argv[1])' "$CHECK" 2>/dev/null || CHECK='{"score": 0, "detail": ["check crashed"]}'
TR=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$SID.jsonl" 2>/dev/null | head -1)
# A transcript that names the set dir or a check.py means the agent may have
# read the hidden grader; the cell is flagged, not dropped. A model's own
# scratch script named check.py also trips it, so inspect before discarding.
SNOOP=false
[ -n "$TR" ] && grep -qF -e "$SET" -e 'check.py' "$TR" && SNOOP=true
PEAK=0
[ -n "$TR" ] && PEAK=$(jq -s '[.[] | select(.type=="assistant") | .message.usage | select(.) | .input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens] | max // 0' "$TR")
jq -nc --arg s "$(basename "$SET")" --arg t "$TID" --arg m "$MODEL" --argjson r "$REP" --arg e "$EFFORT" \
   --argjson exit "$EXIT" --argjson dur "$DUR" --argjson check "$CHECK" \
   --argjson snoop "$SNOOP" --arg tr "${TR:-}" --argjson peak "${PEAK:-0}" \
   --slurpfile out <(jq -c . "$CELL/out.json" 2>/dev/null || echo '{}') \
   '{set:$s, task:$t, model:$m, rep:$r, effort:$e, exit:$exit, dur_s:$dur, score:$check.score,
     failed:$check.detail, snoop:$snoop, transcript:$tr,
     cost:($out[0].total_cost_usd // null), turns:($out[0].num_turns // null),
     served:(($out[0].modelUsage // {}) | keys), stop:($out[0].subtype // null),
     max_prompt:$peak}' >>"$RESULTS"
