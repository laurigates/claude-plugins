#!/usr/bin/env bash
# Measure the per-invocation input-token cost of each system-prompt config.
#
# Runs a fixed *tool-free* prompt (single iteration) under three configs and
# reads `result.usage` from the stream-JSON. Holding tools + CLAUDE.md + rules +
# cwd constant, the default-vs-probe delta in total input tokens isolates the
# system-prompt cost. Total input = input + cache_creation + cache_read (the
# full billed prompt size, independent of cache state / run order).
#
# Configs:
#   default          — built-in Claude Code system prompt (static + dynamic)
#   default-exclude  — built-in with --exclude-dynamic-system-prompt-sections
#                      (per-machine sections moved to first user message)
#   probe            — --system-prompt-file prompts/probe.md (full replacement)
#
# Usage: measure-prompt-tokens.sh [--reps N] [--model ID] [--prompt TEXT]
#        [--effort low|medium|high|xhigh]

set -euo pipefail

reps=3
model="claude-opus-4-8"
effort="low"
prompt="Reply with exactly the word: ok"

while [ $# -gt 0 ]; do
  case "$1" in
    --reps) reps="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --effort) effort="$2"; shift 2 ;;
    --prompt) prompt="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
probe_file="$root/prompts/probe.md"
[ -f "$probe_file" ] || { echo "ERROR: prompt not found: $probe_file" >&2; exit 1; }

# Run one config once; echo "total input_only cache_create cache_read output".
run_once() {
  local cfg="$1"
  local -a args=(
    -p "$prompt"
    --model "$model"
    --effort "$effort"
    --output-format stream-json --verbose
    --dangerously-skip-permissions
  )
  case "$cfg" in
    default) ;;
    default-exclude) args+=(--exclude-dynamic-system-prompt-sections) ;;
    probe) args+=(--system-prompt-file "$probe_file") ;;
  esac
  claude "${args[@]}" 2>/dev/null | jq -rs '
    (map(select(.type=="result")) | last) // empty
    | .usage
    | [ (.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens),
        .input_tokens, .cache_creation_input_tokens, .cache_read_input_tokens,
        .output_tokens ]
    | @tsv'
}

declare -A sum_total
echo "=== PROMPT TOKEN MEASUREMENT ==="
echo "MODEL=$model"
echo "EFFORT=$effort"
echo "REPS=$reps"
echo "PROMPT=$prompt"
printf 'CONFIG\trep\ttotal_in\tinput\tcache_create\tcache_read\toutput\n'
for cfg in default default-exclude probe; do
  sum_total[$cfg]=0
  for ((i = 1; i <= reps; i++)); do
    line="$(run_once "$cfg")"
    [ -n "$line" ] || { echo "WARN: empty usage for $cfg rep $i" >&2; continue; }
    total="$(printf '%s' "$line" | cut -f1)"
    sum_total[$cfg]=$(( sum_total[$cfg] + total ))
    printf '%s\t%d\t%s\n' "$cfg" "$i" "$line"
  done
done

echo "=== MEANS (total input tokens) ==="
mean_default=$(( sum_total[default] / reps ))
mean_exclude=$(( sum_total[default-exclude] / reps ))
mean_probe=$(( sum_total[probe] / reps ))
printf 'DEFAULT_MEAN=%d\n' "$mean_default"
printf 'DEFAULT_EXCLUDE_MEAN=%d\n' "$mean_exclude"
printf 'PROBE_MEAN=%d\n' "$mean_probe"
printf 'PROBE_VS_DEFAULT_DELTA=%d\n' "$(( mean_probe - mean_default ))"
if [ "$mean_default" -gt 0 ]; then
  printf 'PROBE_VS_DEFAULT_PCT=%d\n' "$(( (mean_probe - mean_default) * 100 / mean_default ))"
fi
echo "=== END PROMPT TOKEN MEASUREMENT ==="
