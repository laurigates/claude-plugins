#!/usr/bin/env bash
# Regression test for scripts/export-pi-agents.py (#2633).
#
# The projection is the only thing standing between 21 marketplace subagents and
# invisibility in pi: pi does not read `.claude/agents/`, so an exporter that
# silently drops a tool, misnames a field, or emits a name pi rejects produces
# agents that either under-perform or fail to load with `tools-error:…`. None of
# that raises an error anywhere else, which is why this suite executes the
# exporter rather than grepping it.
#
# Guards:
#   A. Claude Code tool names translate to pi's built-ins, order preserved
#   B. `Agent(a, b)` becomes `allowed_subagents:` (nesting), not a tool grant
#   C. scoped `Bash(cmd *)` widens to `bash` and is REPORTED (`WIDENED_BASH=`)
#   D. Claude-Code-only tools are dropped and REPORTED, never emitted
#   E. `maxTurns` -> `max_turns`, `skills:` list preserved, unknown keys reported
#   F. an agent with no description is SKIPPED and reported, never emitted bare
#   G. the prompt body survives verbatim and the header round-trips as YAML
#   H. every emitted tool name is one of pi's 7 built-ins (the schema contract)
#   I. the justfile recipes exist, are additive, and the export has no network step
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
exporter="$repo_root/scripts/export-pi-agents.py"
justfile="$repo_root/justfile"

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

# --- fixture marketplace -----------------------------------------------------
mkdir -p "$fixture/src/demo-plugin/agents"
cat > "$fixture/src/demo-plugin/agents/worker.md" <<'MD'
---
name: worker
model: opus
color: "#7B1FA2"
description: |
  Does the work.
  Wrapped across lines on purpose.
tools: Glob, Grep, Read, Edit, Write, Bash(git diff *), Bash(git log *), Bash, Agent(reviewer, tester), TodoWrite, WebFetch
skills:
  - alpha-skill
  - beta-skill
context: fork
maxTurns: 20
created: 2026-01-24
modified: 2026-06-28
reviewed: 2026-06-28
---

# Worker Agent

Body line one.

| a | b |
|---|---|
| 1 | 2 |
MD

# `tools: "*"` is the wildcard spelling; it must expand to every built-in, not
# to whatever the map happens to contain.
cat > "$fixture/src/demo-plugin/agents/wildcard.md" <<'MD'
---
name: wildcard
description: Declares the wildcard tool scope.
tools: "*"
maxTurns: 5
---

# Wildcard Agent
MD

# `tools: none` is the one value where an omitted key is NOT equivalent: no key
# grants all 7 built-ins in pi, so dropping it here would widen the agent.
cat > "$fixture/src/demo-plugin/agents/no-tools.md" <<'MD'
---
name: no-tools
description: Declares no built-in tools at all.
tools: none
---

# No Tools Agent
MD

# No description — pi routes subagents by description, so emitting this bare
# would produce an agent the model can never be told to pick.
cat > "$fixture/src/demo-plugin/agents/nameless.md" <<'MD'
---
name: nameless
model: opus
---

# Nameless
MD

echo "=== TEST A/B/C/D/E: projection of a full-frontmatter agent ==="
export_out="$(python3 "$exporter" "$fixture/src" "$fixture/out" 2>&1)"
export_rc=$?
out_agent="$fixture/out/agents/worker.md"
assert "worker.md is emitted" "$([ -f "$out_agent" ] && echo true || echo false)"

# Order is preserved as declared (Glob, Grep, Read, Edit, Write -> find, grep,
# read, edit, write) and `bash` follows the first Bash(...) entry it came from.
assert "tools translate to pi built-ins, in declaration order" \
  "$(python3 - "$out_agent" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
print("true" if fm.get("tools") == "find, grep, read, edit, write, bash" else "false")
PY
)"

assert "Agent(a, b) becomes allowed_subagents, not a tool" \
  "$(python3 - "$out_agent" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
ok = fm.get("allowed_subagents") == "reviewer, tester"
print("true" if ok and "agent" not in str(fm.get("tools", "")).lower() else "false")
PY
)"

assert "maxTurns -> max_turns; skills list preserved; unreviewed keys dropped" \
  "$(python3 - "$out_agent" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
ok = (
    fm.get("max_turns") == 20
    and fm.get("skills") == "alpha-skill, beta-skill"
    and "maxTurns" not in fm
    and "created" not in fm
    and "modified" not in fm
    and "reviewed" not in fm
)
print("true" if ok else "false")
PY
)"

# Guard integrity: the two assertions above are equalities, so a dropped key is
# already excluded — assert the drops by NAME so a loosened comparison cannot
# quietly readmit them, and assert `context` is reported rather than mapped.
assert "Claude-Code-only tools are NOT emitted" \
  "$(python3 - "$out_agent" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
bad = {"TodoWrite", "WebFetch", "TaskOutput", "WebSearch", "context"}
print("true" if not (bad & set(fm)) else "false")
PY
)"

# Two scoped Bash(..) entries plus one bare `Bash`: the count is of entries whose
# scope was dropped, not of `bash` occurrences in the output (which is one).
assert "scoped Bash(..) widening is reported per entry (WIDENED_BASH=2)" \
  "$(case "$export_out" in *"WIDENED_BASH=2"*) echo true ;; *) echo false ;; esac)"

assert "dropped tools are reported by name, never silent" \
  "$(case "$export_out" in *"DROPPED_TOOLS="*"TodoWrite:1"*) case "$export_out" in *"WebFetch:1"*) echo true ;; *) echo false ;; esac ;; *) echo false ;; esac)"

assert "unmapped source keys are reported (DROPPED_KEYS names context)" \
  "$(case "$export_out" in *"DROPPED_KEYS=demo-plugin/agents/worker.md:context"*) echo true ;; *) echo false ;; esac)"

echo "=== TEST F/G/H: skips, body fidelity, and the pi tool-name contract ==="
assert "description-less agent is SKIPPED, not emitted" \
  "$([ ! -f "$fixture/out/agents/nameless.md" ] && echo true || echo false)"
assert "the skip is reported (never silent) and non-zero" \
  "$(case "$export_out" in *"SKIPPED_AGENTS=1"*"nameless.md"*) [ "$export_rc" -ne 0 ] && echo true || echo false ;; *) echo false ;; esac)"

assert "prompt body survives verbatim" \
  "$(python3 - "$out_agent" <<'PY'
import sys
t = open(sys.argv[1]).read()
body = t[t.find("\n---\n", 3) + 5:]
print("true" if body.strip().startswith("# Worker Agent")
      and "| 1 | 2 |" in body else "false")
PY
)"

# The multi-line `description: |` must arrive as ONE logical line: no folded
# scalar, no escaped unicode, no trailing newline artefact.
assert "a block-scalar description lands as a single line" \
  "$(python3 - "$out_agent" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
end = t.find("\n---\n", 3)
fm = yaml.safe_load(t[4:end])
desc = fm.get("description", "")
print("true" if desc == "Does the work. Wrapped across lines on purpose." else "false")
PY
)"

# THE schema contract: pi's `tools:` is a name-only allowlist and an unknown
# entry is a hard error at load time. Assert against the built-in set
# (createCodingTools + createReadOnlyTools, pi 0.84.1) by name, not by count.
assert "every emitted tool is one of pi's 7 built-ins" \
  "$(python3 - "$out_agent" <<'PY'
import sys, yaml
PI_BUILTINS = {"read", "bash", "edit", "write", "grep", "find", "ls"}
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
emitted = {tool.strip() for tool in str(fm.get("tools", "")).split(",") if tool.strip()}
print("true" if emitted and emitted <= PI_BUILTINS else "false")
PY
)"

assert "tools: '*' expands to all 7 built-ins" \
  "$(python3 - "$fixture/out/agents/wildcard.md" <<'PY'
import sys, yaml
PI_BUILTINS = {"read", "bash", "edit", "write", "grep", "find", "ls"}
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
emitted = {tool.strip() for tool in str(fm.get("tools", "")).split(",") if tool.strip()}
print("true" if emitted == PI_BUILTINS else "false")
PY
)"

# The negative direction of the same key: an omitted `tools:` grants all 7 in
# pi, so `none` must survive as `none` rather than being dropped.
assert "tools: none stays none (it must not widen to all built-ins)" \
  "$(python3 - "$fixture/out/agents/no-tools.md" <<'PY'
import sys, yaml
t = open(sys.argv[1]).read()
fm = yaml.safe_load(t[4:t.find("\n---\n", 3)])
print("true" if fm.get("tools") == "none" else "false")
PY
)"

echo "=== TEST I: recipes exist, install is additive, no network step ==="
assert "justfile carries export-pi-agents and install-pi-agents" \
  "$(grep -q '^export-pi-agents' "$justfile" && grep -q '^install-pi-agents' "$justfile" && echo true || echo false)"
assert "setup-pi wires the export in" \
  "$(grep -qE '^setup-pi:.*install-pi-agents' "$justfile" && grep -A 25 '^install-pi-agents' "$justfile" | grep -q 'export-pi-agents.py' && echo true || echo false)"
# The install must never rm -rf the target: ~/.pi/agent/agents/ is shared with
# agents the user wrote, and a clobbering install is unrecoverable.
# shellcheck disable=SC2016  # $target is a literal to match in the justfile, not an expansion
assert "install-pi-agents does not rm -rf its target" \
  "$(grep -A 20 '^install-pi-agents' "$justfile" | grep -qE 'rm -rf "?\$?\{?target|rm -rf \$target' && echo false || echo true)"
assert "the exporter invokes no bunx/npx/network step" \
  "$(grep -qE '(bunx|npx)[[:space:]]|npm install|curl ' "$exporter" && echo false || echo true)"

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
