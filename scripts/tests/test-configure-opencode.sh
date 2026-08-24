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

echo "=== TEST D: default plugin array (subtask2 + pty + dcp) ==="
# Fresh fixture so we assert against the primary opencode.json, not a .sample.
plugfix="$(mktemp -d)"
bash "$configure" "$plugfix" >/dev/null   # no --plugins → script default
assert "default plugin array contains @openspoon/subtask2 + opencode-pty + @tarquinen/opencode-dcp, valid JSON, no double dcp" \
  "$(python3 - "$plugfix/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get("plugin")
ok = (
    isinstance(p, list)
    and "@openspoon/subtask2" in p
    and "opencode-pty" in p
    and "@tarquinen/opencode-dcp" in p
    # dcp is a default now, but never list TWO copies of it
    # (the GitHub repo name opencode-dynamic-context-pruning is the same package).
    and sum(1 for x in p if "dynamic-context-pruning" in x or "opencode-dcp" in x) == 1
)
print("true" if ok else "false")
PY
)"
rm -rf "$plugfix"

echo "=== TEST F: build-agent bash allowlist (real schema, not the brainstorm shape) ==="
# Regression: the GLM-5.2 brainstorm proposed "permissions": { "file_edits": ...,
# "bash": { "allow": [...], "default": ... }} — wrong on every key. The real schema
# is agent.<name>.permission.bash as a {pattern: allow|ask|deny} map.
agentfix="$(mktemp -d)"
bash "$configure" "$agentfix" >/dev/null
assert "opencode.json has agent.build.permission.bash as a pattern map (no permissions/file_edits)" \
  "$(python3 - "$agentfix/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
blob = json.dumps(d)
bash_perm = d.get("agent", {}).get("build", {}).get("permission", {}).get("bash")
ok = (
    "permissions" not in d          # wrong (plural) top-level key
    and "file_edits" not in blob    # wrong permission key name
    and isinstance(bash_perm, dict) # pattern -> verdict map, not {allow:[]}
    and "allow" not in bash_perm    # the brainstorm's {bash:{allow:[]}} shape
    and any(v == "allow" for v in bash_perm.values())
)
print("true" if ok else "false")
PY
)"
rm -rf "$agentfix"

echo "=== TEST E: empty plugin list → valid array ==="
emptyfix="$(mktemp -d)"
[ -n "$emptyfix" ] || { echo "mktemp failed" >&2; exit 1; }
# --no-adapter is what makes the array genuinely empty; without it the adapter
# entry is always present (that is the #2094 cutover — TEST G pins it).
bash "$configure" "$emptyfix" --plugins "" --no-adapter >/dev/null
assert "--plugins '' --no-adapter yields a valid empty plugin array" \
  "$(python3 - "$emptyfix/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("true" if d.get("plugin") == [] else "false")
PY
)"
assert "--no-adapter omits the skill permission deny" \
  "$(python3 - "$emptyfix/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("true" if "skill" not in (d.get("permission") or {}) else "false")
PY
)"
rm -rf "$emptyfix"

echo ""
echo "=== TEST G: skill-discovery adapter is registered (#2094) ==="
adapterfix="$(mktemp -d)"
[ -n "$adapterfix" ] || { echo "mktemp failed" >&2; exit 1; }
bash "$configure" "$adapterfix" --plugins "" >/dev/null
# The adapter REPLACES the flattened skill export, so both halves must land:
# the [path, config] plugin entry AND the native-listing suppression. Either
# alone is a broken cutover — the entry without the deny double-lists skills,
# the deny without the entry leaves the model with no skill surface at all.
assert "adapter entry is a [path, config] tuple pointing at adapters/opencode/index.ts" \
  "$(python3 - "$adapterfix/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
tuples = [p for p in d.get("plugin", []) if isinstance(p, list)]
ok = (
    len(tuples) == 1
    and tuples[0][0].endswith("/adapters/opencode/index.ts")
    and isinstance(tuples[0][1], dict)
    and isinstance(tuples[0][1].get("k"), int)
    and tuples[0][1].get("pins") == []
)
print("true" if ok else "false")
PY
)"
assert "native skill listing is suppressed via permission.skill=deny" \
  "$(python3 - "$adapterfix/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("true" if (d.get("permission") or {}).get("skill") == "deny" else "false")
PY
)"
bash "$configure" "$adapterfix/k" --plugins "" --adapter-k 9 >/dev/null
assert "--adapter-k overrides the injection budget" \
  "$(python3 - "$adapterfix/k/opencode.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
tuples = [p for p in d.get("plugin", []) if isinstance(p, list)]
print("true" if tuples and tuples[0][1].get("k") == 9 else "false")
PY
)"
rm -rf "$adapterfix"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then echo "STATUS=FAIL"; exit 1; fi
echo "STATUS=OK"
