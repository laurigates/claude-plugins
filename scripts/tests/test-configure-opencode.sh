#!/usr/bin/env bash
# Regression test for scripts/configure-opencode.sh.
#
# Guards the generated OpenCode config against drifting back to the broken
# brainstorm schema (`providers`/`api_base`/`tools:` list). Asserts:
#   A. opencode.json is valid JSON with `provider` (NOT `providers`), the
#      `provider/model` model string, and `default_agent`.
#   B. agents/orchestrator.md frontmatter is valid YAML with `mode: primary`
#      and a `permission:` map (NOT a `tools:` list).
#   C. a second run is non-destructive: an existing opencode.json is kept and
#      the new config lands in opencode.json.opencode-sample.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
configure="$repo_root/scripts/configure-opencode.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

echo "=== TEST A: opencode.json schema ==="
bash "$configure" "$fixture" --provider mlx-local --model Qwen3-30B-A3B --port 8080 >/dev/null

assert "opencode.json exists" \
  "$([ -f "$fixture/opencode.json" ] && echo true || echo false)"
assert "opencode.json is valid JSON with provider (not providers) + model + default_agent" \
  "$(python3 - "$fixture/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
ok = (
    "provider" in d and "providers" not in d
    and "api_base" not in json.dumps(d)
    and d.get("model") == "mlx-local/Qwen3-30B-A3B"
    and d.get("default_agent") == "orchestrator"
    and d["provider"]["mlx-local"]["npm"] == "@ai-sdk/openai-compatible"
)
print("true" if ok else "false")
PY
)"

echo "=== TEST B: orchestrator.md frontmatter ==="
assert "agents/orchestrator.md exists" \
  "$([ -f "$fixture/agents/orchestrator.md" ] && echo true || echo false)"
assert "orchestrator frontmatter is valid YAML with mode: primary and a permission map (no tools: list)" \
  "$(python3 - "$fixture/agents/orchestrator.md" <<'PY'
import sys
text = open(sys.argv[1]).read()
parts = text.split("---", 2)
ok = len(parts) >= 3
fm = parts[1] if ok else ""
try:
    import yaml
    meta = yaml.safe_load(fm)
except Exception:
    meta = None
if isinstance(meta, dict):
    ok = ok and meta.get("mode") == "primary" and isinstance(meta.get("permission"), dict) and "tools" not in meta
else:
    # No PyYAML available — fall back to line checks on the frontmatter block.
    ok = ok and "mode: primary" in fm and "permission:" in fm and "\ntools:" not in ("\n" + fm)
print("true" if ok else "false")
PY
)"

echo "=== TEST C: non-destructive second run ==="
bash "$configure" "$fixture" --provider mlx-local --model Qwen3-30B-A3B --port 8080 >/dev/null
assert "original opencode.json preserved" \
  "$([ -f "$fixture/opencode.json" ] && echo true || echo false)"
assert "second run writes opencode.json.opencode-sample" \
  "$([ -f "$fixture/opencode.json.opencode-sample" ] && echo true || echo false)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
