#!/usr/bin/env bash
# Measure the real per-invocation input-token cost of each catalog variant.
# Adapted from experiments/claude-probe/scripts/measure-prompt-tokens.sh.
#
# For each variant, assemble its arm system prompt (router + catalog), run a
# fixed tiny tool-free prompt once, and read `result.usage` total input tokens
# from the stream-JSON. The arm's system prompt is the only thing that varies,
# so the total input is the catalog's real token cost (+ a fixed router/tooling
# constant). Writes catalogs/catalog_tokens.json for render-frontier.py.
#
# Usage: measure-catalog-tokens.sh [--reps N] [--model ID] [--effort LEVEL]

set -uo pipefail

reps=1
model="claude-haiku-4-5"
effort="low"
prompt="Reply with exactly the word: ok"

while [ $# -gt 0 ]; do
  case "$1" in
    --reps) reps="$2"; shift 2 ;;
    --model) model="$2"; shift 2 ;;
    --effort) effort="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

measure_once() {
  local arm_prompt="$1"
  local neutral; neutral="$(mktemp -d)"
  ( cd "$neutral" && IS_SANDBOX=1 claude -p "$prompt" \
    --model "$model" --effort "$effort" \
    --system-prompt-file "$arm_prompt" \
    --strict-mcp-config \
    --output-format stream-json --verbose \
    --dangerously-skip-permissions </dev/null 2>/dev/null ) | jq -rs '
      (map(select(.type=="result")) | last) // empty
      | .usage
      | (.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens)'
  rm -rf "$neutral"
}

echo "=== CATALOG TOKEN MEASUREMENT ==="
echo "MODEL=$model"
echo "EFFORT=$effort"
echo "REPS=$reps"
printf 'VARIANT\trep\ttotal_input\n'

tmp_json="$root/catalogs/catalog_tokens.json"
declare -A mean
for variant in none names short medium full; do
  arm_prompt="$("$here/build-arm-prompt.sh" "$variant")"
  sum=0; got=0
  for ((i = 1; i <= reps; i++)); do
    val="$(measure_once "$arm_prompt")"
    if [ -z "$val" ] || ! [[ "$val" =~ ^[0-9]+$ ]]; then
      echo "WARN: empty/invalid usage for $variant rep $i" >&2
      continue
    fi
    printf '%s\t%d\t%s\n' "$variant" "$i" "$val"
    sum=$(( sum + val )); got=$(( got + 1 ))
  done
  if [ "$got" -gt 0 ]; then
    mean[$variant]=$(( sum / got ))
  else
    mean[$variant]=0
  fi
  printf '%s_MEAN=%d\n' "$variant" "${mean[$variant]}"
done

# Emit JSON for the frontier renderer.
python3 - "$tmp_json" "${mean[none]}" "${mean[names]}" "${mean[short]}" "${mean[medium]}" "${mean[full]}" <<'PY'
import json, sys
out, none, names, short, medium, full = sys.argv[1:7]
json.dump({
    "measured_with": {"note": "total input tokens incl. fixed router+tooling constant"},
    "none": int(none), "names": int(names), "short": int(short),
    "medium": int(medium), "full": int(full),
}, open(out, "w"), indent=2)
print(f"wrote {out}")
PY
echo "=== END CATALOG TOKEN MEASUREMENT ==="
