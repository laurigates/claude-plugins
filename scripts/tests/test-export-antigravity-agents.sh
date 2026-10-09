#!/usr/bin/env bash
# Regression test for scripts/export-antigravity-agents.py and Antigravity CLI
# subagent projection.
#
# Antigravity CLI discovers subagents at ~/.gemini/config/agents/<name>/agent.md
# (global) or <workspace>/.agents/agents/<name>/agent.md (project).
#
# Guards:
#   A. every source agent is projected into agents/<name>/agent.md
#   B. frontmatter shape matches Antigravity:
#      - name: preserved
#      - description: preserved
#      - model: mapped (opus->pro, sonnet->flash, haiku->flash_lite, other->inherit)
#      - subagent: true
#      - inheritCustomizations: true
#   C. Claude-Code-only keys (tools/maxTurns/color/dates) are dropped
#   D. prompt body survives verbatim
#   E. an agent with no description is SKIPPED and reported, never emitted bare
#   F. an agent with malformed frontmatter is SKIPPED and reported
#   G. full-corpus projection against this repo exports all agents cleanly with 0 skips
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
exporter="$repo_root/scripts/export-antigravity-agents.py"

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

if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "SKIP: PyYAML not available"
  exit 0
fi

fixture="$(mktemp -d)"
[ -n "$fixture" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

# --- Fixture marketplace ---
mkdir -p "$fixture/src/demo-plugin/agents"

# Agent 1: Opus model + full Claude Code frontmatter
cat > "$fixture/src/demo-plugin/agents/architect.md" <<'MD'
---
name: architect
model: opus
color: "#7B1FA2"
description: System design and architecture reviewer.
tools: Glob, Grep, Read, Bash(git diff *)
maxTurns: 20
created: 2026-01-24
modified: 2026-06-28
---

# Architect Agent

System architecture body line.

| Step | Rationale |
|------|-----------|
| 1    | In-place  |
MD

# Agent 2: Sonnet model
cat > "$fixture/src/demo-plugin/agents/coder.md" <<'MD'
---
name: coder
model: sonnet
description: Fast implementation specialist.
---

# Coder Agent
MD

# Agent 3: Haiku model
cat > "$fixture/src/demo-plugin/agents/scanner.md" <<'MD'
---
name: scanner
model: haiku
description: Quick repo scanner.
---

# Scanner Agent
MD

# Agent 4: No model (default to inherit)
cat > "$fixture/src/demo-plugin/agents/planner.md" <<'MD'
---
name: planner
description: General planner.
---

# Planner Agent
MD

# Agent 5: Missing description (must be SKIPPED)
cat > "$fixture/src/demo-plugin/agents/nodesc.md" <<'MD'
---
name: nodesc
model: opus
---

# No Description
MD

# Agent 6: Malformed frontmatter (must be SKIPPED)
cat > "$fixture/src/demo-plugin/agents/malformed.md" <<'MD'
---
name: [broken unclosed list
description: Bad YAML
---

# Malformed
MD

echo "=== TEST A/B/C/D: agent projection & frontmatter mapping ==="
run_out="$(python3 "$exporter" "$fixture/src" "$fixture/out" 2>&1 || true)"

assert "architect agent.md is emitted in nested directory agents/architect/agent.md" \
  "$([ -f "$fixture/out/agents/architect/agent.md" ] && echo true || echo false)"

assert "architect frontmatter matches Antigravity schema" \
  "$(python3 - "$fixture/out/agents/architect/agent.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
end = t.find("\n---\n", 3)
fm = yaml.safe_load(t[4:end])
expected = {
    "name": "architect",
    "description": "System design and architecture reviewer.",
    "model": "pro",
    "subagent": True,
    "inheritCustomizations": True,
}
print("true" if fm == expected else "false")
PY
)"

assert "Claude-Code-only keys are dropped (tools/maxTurns/color/created/modified)" \
  "$(python3 - "$fixture/out/agents/architect/agent.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
dropped = {"tools", "maxTurns", "color", "created", "modified"}
print("true" if not (dropped & set(fm)) else "false")
PY
)"

assert "prompt body survives verbatim" \
  "$(python3 - "$fixture/out/agents/architect/agent.md" <<'PY'
import sys
t = open(sys.argv[1]).read()
body = t[t.find("\n---\n", 3) + 5:]
print("true" if body.strip().startswith("# Architect Agent") and "| In-place  |" in body else "false")
PY
)"

echo "=== TEST E: model tier mappings ==="
assert "sonnet maps to flash" \
  "$(python3 - "$fixture/out/agents/coder/agent.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
print("true" if fm.get("model") == "flash" else "false")
PY
)"

assert "haiku maps to flash_lite" \
  "$(python3 - "$fixture/out/agents/scanner/agent.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
print("true" if fm.get("model") == "flash_lite" else "false")
PY
)"

assert "missing model maps to inherit" \
  "$(python3 - "$fixture/out/agents/planner/agent.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
print("true" if fm.get("model") == "inherit" else "false")
PY
)"

echo "=== TEST F: skipped agents reported ==="
assert "nodesc.md is SKIPPED and not emitted" \
  "$([ ! -d "$fixture/out/agents/nodesc" ] && echo true || echo false)"
assert "malformed.md is SKIPPED and not emitted" \
  "$([ ! -d "$fixture/out/agents/malformed" ] && echo true || echo false)"
assert "skipped count is 2 in report" \
  "$(case "$run_out" in *"SKIPPED_AGENTS=2"*) echo true ;; *) echo false ;; esac)"

echo "=== TEST G: full-corpus export against repo ==="
repo_out="$(mktemp -d)"
trap 'rm -rf "$fixture" "$repo_out"' EXIT
full_export="$(python3 "$exporter" "$repo_root" "$repo_out" 2>&1)"
full_rc=$?

assert "full repo agent export exits 0" \
  "$([ "$full_rc" -eq 0 ] && echo true || echo false)"
assert "full repo agent export has 0 skipped agents" \
  "$(case "$full_export" in *"SKIPPED_AGENTS=0"*) echo true ;; *) echo false ;; esac)"
assert "all source agents were exported" \
  "$(python3 - "$full_export" <<'PY'
import sys
out = sys.argv[1]
lines = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
src = int(lines.get("SOURCE_AGENTS", -1))
exported = int(lines.get("OUTPUT_AGENTS", -2))
print("true" if src > 0 and src == exported else "false")
PY
)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -eq 0 ]; then
  echo "STATUS=OK"
  exit 0
fi
echo "STATUS=FAIL"
exit 1
