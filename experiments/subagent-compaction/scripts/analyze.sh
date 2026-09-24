#!/usr/bin/env bash
# Score one probe arm: subagent context growth, compaction events, hook firings,
# and sentinel recall of the subagent's final report.
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

# A transcript cut off mid-write (killed run) has an unparseable last line.
# Parse line by line and count the bad ones, so a truncated file reads as WARN
# instead of a clean "no compaction".
clean_copy() {  # clean_copy <src> <dst> -> prints number of unparseable lines
  local src="$1" dst="$2" total good
  jq -cR 'fromjson? | select(type == "object")' "$src" > "$dst" 2>/dev/null || true
  total="$(grep -c . "$src" || true)"
  good="$(grep -c . "$dst" || true)"
  echo $(( total - good ))
}

transcript_table() {  # transcript_table <clean-jsonl> <display-name>
  local f="$1"
  echo "=== TRANSCRIPT $2 ==="
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
  # Only an auto compaction answers Q1; a manual or reactive one does not.
  echo "COMPACTIONS_AUTO=$(jq -c 'select(.subtype=="compact_boundary" and .compactMetadata.trigger=="auto")' "$f" | grep -c . || true)"
  echo "COMPACT_TRIGGERS=$(jq -r 'select(.subtype=="compact_boundary") | .compactMetadata.trigger // "?"' "$f" | paste -sd, -)"
  echo "COMPACT_PRE_TOKENS=$(jq -r 'select(.subtype=="compact_boundary") | .compactMetadata.preTokens // "?"' "$f" | paste -sd, -)"
  echo "COMPACT_POST_TOKENS=$(jq -r 'select(.subtype=="compact_boundary") | .compactMetadata.postTokens // "?"' "$f" | paste -sd, -)"
  echo "PROMPT_TOO_LONG=$(jq -c 'select(.type=="assistant" and ((.message.content // "") | tostring | test("prompt is too long"; "i")))' "$f" | grep -c . || true)"
  echo "=== END TRANSCRIPT $2 ==="
}

# The subagent's own final report: the last assistant text, or the message of a
# SubagentHandback tool call where the harness delivers reports that way.
final_report() {  # final_report <clean-jsonl>
  # Slurp so a multi-line text block stays one element; take the last one.
  jq -rs '[.[] | select(.type=="assistant") | .message.content[]?
      | if .type=="text" then .text
        elif .type=="tool_use" and .name=="SubagentHandback" then (.input.message // "")
        else empty end] | last // ""' "$1"
}

# emit_result: the RESULT block from the issues array ("SEVERITY|TYPE|MSG").
# Exits 1 on ERROR, 0 otherwise.
emit_result() {
  local status=OK i first="" first_type first_msg more="" sev typ msg
  echo "=== RESULT ==="
  for i in "${issues[@]}"; do
    case "$i" in ERROR\|*) status=ERROR ;; WARN\|*) [ "$status" = OK ] && status=WARN ;; esac
  done
  echo "STATUS=$status"
  if [ "$status" != OK ]; then
    for i in "${issues[@]}"; do
      case "$i" in "$status"\|*) first="$i"; break ;; esac
    done
    IFS='|' read -r _ first_type first_msg <<<"$first"
    if [ "${#issues[@]}" -gt 1 ]; then more=" (+$(( ${#issues[@]} - 1 )) more)"; fi
    echo "REASON=$(printf '%s: %s' "$first_type" "$first_msg" | cut -c1-180)$more"
  fi
  echo "ISSUE_COUNT=${#issues[@]}"
  if [ "${#issues[@]}" -gt 0 ]; then
    echo "ISSUES:"
    for i in "${issues[@]}"; do
      IFS='|' read -r sev typ msg <<<"$i"
      echo "  - SEVERITY=$sev TYPE=$typ MSG=$msg"
    done
  fi
  echo "=== END RESULT ==="
  if [ "$status" = ERROR ]; then exit 1; fi
  exit 0
}

issues=()  # "SEVERITY|TYPE|MSG"
work="$(mktemp -d)"
if [ -z "$work" ] || [ ! -d "$work" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$work"' EXIT

if [ "${1:-}" = "--transcript" ]; then
  src="${2:?usage: analyze.sh --transcript <agent-*.jsonl>}"
  if [ ! -s "$src" ]; then
    issues+=("ERROR|transcript_missing|$src is missing or empty")
    emit_result
  fi
  bad="$(clean_copy "$src" "$work/t.jsonl")"
  transcript_table "$work/t.jsonl" "$(basename "$src")"
  echo "PARSE_ERRORS=$bad"
  if [ "$bad" -gt 0 ]; then
    issues+=("WARN|transcript_truncated|$bad unparseable transcript line(s); counts may be incomplete")
  fi
  emit_result
fi

arm_dir="${1:?usage: analyze.sh <arm-dir> [sentinels.txt] | --transcript <file>}"
sentinels="${2:-}"

echo "=== ARM ==="
echo "ARM=$(basename "$arm_dir")"
if [ -f "$arm_dir/arm.env" ]; then cat "$arm_dir/arm.env"; fi
echo "=== END ARM ==="

echo "=== MAIN ==="
main_report=""
if [ -s "$arm_dir/main.jsonl" ]; then
  clean_copy "$arm_dir/main.jsonl" "$work/main.jsonl" >/dev/null
fi
if [ -s "$work/main.jsonl" ] && jq -e 'select(.type=="result")' "$work/main.jsonl" >/dev/null 2>&1; then
  echo "MAIN_RESULT_SUBTYPE=$(jq -r 'select(.type=="result") | .subtype' "$work/main.jsonl" | tail -1)"
  echo "MAIN_COST_USD=$(jq -r 'select(.type=="result") | .total_cost_usd // "?"' "$work/main.jsonl" | tail -1)"
  main_report="$(jq -r 'select(.type=="result") | .result // ""' "$work/main.jsonl")"
else
  echo "MAIN_RESULT_SUBTYPE=missing"
  issues+=("ERROR|run_failed|main.jsonl has no result event")
fi
echo "=== END MAIN ==="

echo "=== SUBAGENTS ==="
mapfile -t agents < <(find "$arm_dir/home/.claude/projects" -path '*/subagents/agent-*.jsonl' 2>/dev/null | sort)
echo "SUBAGENT_COUNT=${#agents[@]}"
compacted=no auto_compacted=no parse_errors=0 files_read_max=0 sub_report=""
for f in "${agents[@]}"; do
  clean="$work/$(basename "$f")"
  bad="$(clean_copy "$f" "$clean")"
  parse_errors=$(( parse_errors + bad ))
  table="$(transcript_table "$clean" "$(basename "$f")")"
  printf '%s\n' "$table"
  echo "PARSE_ERRORS=$bad"
  if grep -q '^COMPACTIONS=[1-9]' <<<"$table"; then compacted=yes; fi
  if grep -q '^COMPACTIONS_AUTO=[1-9]' <<<"$table"; then auto_compacted=yes; fi
  n="$(grep -m1 '^DISTINCT_FILES_READ=' <<<"$table" | cut -d= -f2)"
  if [ "${n:-0}" -gt "$files_read_max" ]; then files_read_max="$n"; fi
  r="$(final_report "$clean")"
  if [ -n "$r" ]; then sub_report="$r"; fi
done
echo "SUBAGENT_COMPACTED=$compacted"
echo "SUBAGENT_AUTO_COMPACTED=$auto_compacted"
echo "SUBAGENT_PARSE_ERRORS=$parse_errors"
echo "=== END SUBAGENTS ==="
if [ "${#agents[@]}" -eq 0 ]; then
  issues+=("ERROR|no_subagent|no subagent transcript under the arm HOME")
fi
if [ "$parse_errors" -gt 0 ]; then
  issues+=("WARN|transcript_truncated|$parse_errors unparseable transcript line(s); counts may be incomplete")
fi
if [ "${#agents[@]}" -gt 0 ] && [ "$files_read_max" -eq 0 ]; then
  issues+=("WARN|no_files_read|the subagent issued no Read calls")
fi

echo "=== HOOKS ==="
hooks="$arm_dir/hooks.jsonl"
if [ -s "$hooks" ]; then
  clean_copy "$hooks" "$work/hooks.jsonl" >/dev/null
  for ev in SubagentStart SubagentStop PreCompact PostCompact; do
    echo "HOOK_${ev}=$(jq -c --arg e "$ev" 'select(.hook_event_name==$e)' "$work/hooks.jsonl" | grep -c . || true)"
  done
  echo "PRECOMPACT_WITH_AGENT_ID=$(jq -c 'select(.hook_event_name=="PreCompact" and (.agent_id // null) != null)' "$work/hooks.jsonl" | grep -c . || true)"
  echo "PRECOMPACT_TRIGGERS=$(jq -r 'select(.hook_event_name=="PreCompact") | .trigger // "?"' "$work/hooks.jsonl" | paste -sd, -)"
  echo "PRECOMPACT_KEYS=$(jq -r 'select(.hook_event_name=="PreCompact") | keys[]' "$work/hooks.jsonl" | sort -u | paste -sd, -)"
else
  echo "HOOKS_LOG=empty"
fi
echo "=== END HOOKS ==="

echo "=== SENTINELS ==="
if [ -n "$sentinels" ] && [ -f "$sentinels" ]; then
  # Score what the subagent itself returned; the main agent's relay can add
  # formatting. Fall back to the relay only when no subagent text exists.
  if [ -n "$sub_report" ]; then report="$sub_report"; echo "REPORT_SOURCE=subagent"
  else report="$main_report"; echo "REPORT_SOURCE=main"; fi
  # Normalize: CR, backticks, list markers and surrounding whitespace.
  printf '%s\n' "$report" | tr -d '\r`' | sed -E 's/^[[:space:]]*([-*+]|[0-9]+\.)[[:space:]]+//; s/^[[:space:]]+//; s/[[:space:]]+$//' > "$work/report.txt"
  # Exact field matching: no regex, so "." in file names and prefixes of
  # other names ("f01.txt.bak") cannot match. A sentinel for a file that does
  # not exist is fabricated too: SENTINELS_WRONG counts wrong values and
  # invented names, SENTINELS_UNKNOWN_NAMES the latter alone.
  awk '
    FNR == NR {
      if ($1 == "SENTINEL" && NF == 3) seen[$2] = $3
      else if ($1 == "MISSING" && NF == 2) missing[$2] = 1
      next
    }
    NF == 3 {
      exp_n++
      truth[$2] = 1
      if ($2 in seen) { if (seen[$2] == $3) c++; else w++ }
      else if ($2 in missing) d++
      else a++
    }
    END {
      for (n in seen) if (!(n in truth)) u++
      printf "SENTINELS_EXPECTED=%d\nSENTINELS_CORRECT=%d\nSENTINELS_WRONG=%d\nSENTINELS_UNKNOWN_NAMES=%d\nSENTINELS_DECLARED_MISSING=%d\nSENTINELS_ABSENT=%d\n", exp_n, c, w + u, u, d, a
    }' "$work/report.txt" "$sentinels" | tee "$work/scores.txt"
  exp_n="$(grep '^SENTINELS_EXPECTED=' "$work/scores.txt" | cut -d= -f2)"
  absent="$(grep '^SENTINELS_ABSENT=' "$work/scores.txt" | cut -d= -f2)"
  if [ "$exp_n" -gt 0 ] && [ "$absent" -eq "$exp_n" ] && [ "${#agents[@]}" -gt 0 ]; then
    issues+=("WARN|report_unparsed|no sentinel or MISSING line found in the subagent report")
  fi
else
  echo "SENTINELS=skipped"
fi
echo "=== END SENTINELS ==="

emit_result
