#!/usr/bin/env bash
# Score one probe arm: subagent context growth, compaction events, hook firings,
# and sentinel recall of the final report.
#
# Usage:
#   analyze.sh <arm-dir> [sentinels.txt]
#     <arm-dir> holds main.jsonl (claude -p stream-json), hooks.jsonl, and
#     home/.claude/projects/**/subagents/agent-*.jsonl (the arm's fake HOME).
#   analyze.sh --transcript <agent-*.jsonl>
#     Context/compaction table for a single subagent transcript (any session).
#
# Output follows .claude/rules/structured-script-output.md.
set -euo pipefail

transcript_table() {
  local f="$1"
  echo "=== TRANSCRIPT $(basename "$f") ==="
  echo "MODEL=$(jq -r 'select(.type=="assistant") | .message.model // empty' "$f" | head -1)"
  # One row per API call (a message id repeats once per content block).
  local ctx
  ctx="$(jq -r 'select(.type=="assistant" and .message.usage)
      | [.message.id, (.message.usage | .input_tokens + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0))]
      | @tsv' "$f" | awk -F'\t' '!seen[$1]++ {print $2}')"
  echo "API_CALLS=$(printf '%s\n' "$ctx" | grep -c . || true)"
  echo "START_CTX=$(printf '%s\n' "$ctx" | head -1)"
  echo "PEAK_CTX=$(printf '%s\n' "$ctx" | sort -n | tail -1)"
  echo "CTX_SERIES=$(printf '%s\n' "$ctx" | paste -sd, -)"
  echo "READ_CALLS=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Read") | .id' "$f" | sort -u | grep -c . || true)"
  echo "DISTINCT_FILES_READ=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path' "$f" | sort -u | grep -c . || true)"
  echo "COMPACTIONS=$(jq -c 'select(.subtype=="compact_boundary")' "$f" | grep -c . || true)"
  echo "COMPACT_TRIGGERS=$(jq -r 'select(.subtype=="compact_boundary") | .compactMetadata.trigger // "?"' "$f" | paste -sd, -)"
  echo "COMPACT_PRE_TOKENS=$(jq -r 'select(.subtype=="compact_boundary") | .compactMetadata.preTokens // "?"' "$f" | paste -sd, -)"
  echo "COMPACT_POST_TOKENS=$(jq -r 'select(.subtype=="compact_boundary") | .compactMetadata.postTokens // "?"' "$f" | paste -sd, -)"
  echo "PROMPT_TOO_LONG=$(jq -c 'select(.type=="assistant" and ((.message.content // "") | tostring | test("prompt is too long"; "i")))' "$f" | grep -c . || true)"
}

if [ "${1:-}" = "--transcript" ]; then
  transcript_table "${2:?usage: analyze.sh --transcript <agent-*.jsonl>}"
  exit 0
fi

arm_dir="${1:?usage: analyze.sh <arm-dir> [sentinels.txt] | --transcript <file>}"
sentinels="${2:-}"
probe_outcome=ok

echo "=== ARM ==="
echo "ARM=$(basename "$arm_dir")"
[ -f "$arm_dir/arm.env" ] && cat "$arm_dir/arm.env"

echo "=== MAIN ==="
report=""
if [ -s "$arm_dir/main.jsonl" ] && jq -e 'select(.type=="result")' "$arm_dir/main.jsonl" >/dev/null 2>&1; then
  echo "MAIN_RESULT_SUBTYPE=$(jq -r 'select(.type=="result") | .subtype' "$arm_dir/main.jsonl" | tail -1)"
  echo "MAIN_COST_USD=$(jq -r 'select(.type=="result") | .total_cost_usd // "?"' "$arm_dir/main.jsonl" | tail -1)"
  report="$(jq -r 'select(.type=="result") | .result // ""' "$arm_dir/main.jsonl")"
else
  echo "MAIN_RESULT_SUBTYPE=missing"
  probe_outcome=run_failed
fi

echo "=== SUBAGENTS ==="
mapfile -t agents < <(find "$arm_dir/home/.claude/projects" -path '*/subagents/agent-*.jsonl' 2>/dev/null | sort)
echo "SUBAGENT_COUNT=${#agents[@]}"
compacted=no
for f in "${agents[@]}"; do
  table="$(transcript_table "$f")"
  printf '%s\n' "$table"
  if printf '%s\n' "$table" | grep -q '^COMPACTIONS=[1-9]'; then compacted=yes; fi
done
echo "SUBAGENT_COMPACTED=$compacted"
[ "${#agents[@]}" -eq 0 ] && [ "$probe_outcome" = ok ] && probe_outcome=no_subagent

echo "=== HOOKS ==="
hooks="$arm_dir/hooks.jsonl"
if [ -s "$hooks" ]; then
  for ev in SubagentStart SubagentStop PreCompact PostCompact; do
    echo "HOOK_${ev}=$(jq -c --arg e "$ev" 'select(.hook_event_name==$e)' "$hooks" | grep -c . || true)"
  done
  echo "PRECOMPACT_WITH_AGENT_ID=$(jq -c 'select(.hook_event_name=="PreCompact" and (.agent_id // null) != null)' "$hooks" | grep -c . || true)"
  echo "PRECOMPACT_TRIGGERS=$(jq -r 'select(.hook_event_name=="PreCompact") | .trigger // "?"' "$hooks" | paste -sd, -)"
  echo "PRECOMPACT_KEYS=$(jq -r 'select(.hook_event_name=="PreCompact") | keys[]' "$hooks" | sort -u | paste -sd, -)"
else
  echo "HOOKS_LOG=empty"
fi

echo "=== SENTINELS ==="
if [ -n "$sentinels" ] && [ -f "$sentinels" ]; then
  correct=0 wrong=0 declared=0 absent=0
  while read -r _ name hex; do
    if printf '%s\n' "$report" | grep -qx "SENTINEL $name $hex"; then correct=$((correct + 1))
    elif printf '%s\n' "$report" | grep -q "^SENTINEL $name "; then wrong=$((wrong + 1))
    elif printf '%s\n' "$report" | grep -q "^MISSING $name"; then declared=$((declared + 1))
    else absent=$((absent + 1)); fi
  done < "$sentinels"
  echo "SENTINELS_EXPECTED=$(grep -c . "$sentinels")"
  echo "SENTINELS_CORRECT=$correct"
  echo "SENTINELS_WRONG=$wrong"
  echo "SENTINELS_DECLARED_MISSING=$declared"
  echo "SENTINELS_ABSENT=$absent"
else
  echo "SENTINELS=skipped"
fi

echo "=== RESULT ==="
echo "OUTCOME=$probe_outcome"
case "$probe_outcome" in
  ok) echo "STATUS=OK"; echo "ISSUE_COUNT=0" ;;
  run_failed) echo "STATUS=ERROR"; echo "REASON=run_failed: main.jsonl has no result event"; echo "ISSUE_COUNT=1" ;;
  *) echo "STATUS=ERROR"; echo "REASON=no_subagent: no subagent transcript under the arm HOME"; echo "ISSUE_COUNT=1" ;;
esac
