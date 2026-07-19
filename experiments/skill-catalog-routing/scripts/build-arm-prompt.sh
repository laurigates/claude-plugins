#!/usr/bin/env bash
# Assemble the per-arm router system prompt: prompts/system-router.md followed by
# the injected catalog body for the given variant. Writes
# .arm-prompts/system.<variant>.md and prints its path.
#
# The result is a COMPLETE system-prompt replacement (used with
# --system-prompt-file), so Claude Code's own built-in skill listing never
# appears — the only skill vocabulary the model sees is the catalog we inject.
#
# Usage: build-arm-prompt.sh <none|names|short|medium|full>

set -euo pipefail

variant="${1:?usage: build-arm-prompt.sh <none|names|short|medium|full>}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
router="$root/prompts/system-router.md"
out_dir="$root/.arm-prompts"
out="$out_dir/system.$variant.md"

[ -f "$router" ] || { echo "ERROR: router prompt not found: $router" >&2; exit 1; }
mkdir -p "$out_dir"

if [ "$variant" = "none" ]; then
  # C0 — no catalog. Router prompt only.
  cp "$router" "$out"
else
  # Any variant whose catalog file exists (names/short/medium/full/domain-*/
  # compact/…). New variants need no edit here — just a built catalog.
  catalog="$root/catalogs/catalog.$variant.json"
  [ -f "$catalog" ] || { echo "ERROR: catalog not found: $catalog — run build-catalogs.py first (unknown variant '$variant'?)" >&2; exit 1; }
  {
    cat "$router"
    printf '\n\n## Available skills\n\n'
    # One skill per line, exactly as stored in the catalog's `line` field.
    python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
for e in data["entries"]:
    print(e["line"])
' "$catalog"
  } > "$out"
fi

printf '%s\n' "$out"
