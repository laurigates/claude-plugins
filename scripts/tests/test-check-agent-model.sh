#!/usr/bin/env bash
# Regression test for scripts/check-agent-model.sh
# (.claude/rules/agent-development.md § "Model Selection for Agents" — the
#  task-shape tiers for plugin agents, #3116).
#
# Guards:
#   A. the real repo stays clean — every agent declares a tier model, so the check exits 0
#   B. an all-opus fixture tree exits 0
#   C. a `model: haiku` agent exits 1 and names the offending file
#   D. `model: sonnet` WITHOUT `effort:` exits 1 and names the file; with an
#      explicit `effort:` it exits 0 and is counted in SONNET_AGENTS;
#      `model: inherit` exits 1 (the pick must be explicit); an invalid effort
#      past line 20 still fails; a CRLF file is parsed
#   E. an allowlisted file is honored (via the CHECK_AGENT_MODEL_ALLOWLIST seam)
#   F. agent worktree copies under .claude/worktrees/ are pruned, not scanned
#      (#1492 parity)
#   H. a `model: fable` agent exits 0 (sanctioned for the hardest delegated work)
#   I. `effort: low` exits 0; `effort: ultra` exits 1 and names the bad value;
#      an agent with no `effort:` line exits 0 (the field is optional)
#   J. a lean haiku reader (omitClaudeMd + Read/Grep/Glob tools + effort) exits
#      0; dropping any one condition exits 1 and names it; a sonnet agent passes
#      on its own tier, never as a lean-haiku exemption
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-agent-model.sh"

pass_count=0
fail_count=0

assert() {
  # assert <description> <condition-result-string "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() { grep -q -- "$2" <<<"$1" && echo true || echo false; }

# make_agent <path> <model> — write a minimal agent .md with the given model.
make_agent() {
  local agent_name
  agent_name="$(basename "$1" .md)"
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
---
name: $agent_name
model: $2
description: Fixture agent for the model lint test.
tools: Read
created: 2026-06-18
modified: 2026-06-18
reviewed: 2026-06-18
---
Fixture body.
EOF
}

# make_agent_effort <path> <model> <effort-line-or-empty> — like make_agent but
# optionally adds an `effort:` frontmatter line (pass "" to omit it).
make_agent_effort() {
  local agent_name
  agent_name="$(basename "$1" .md)"
  mkdir -p "$(dirname "$1")"
  {
    echo "---"
    echo "name: $agent_name"
    echo "model: $2"
    [ -n "$3" ] && echo "effort: $3"
    echo "description: Fixture agent for the model lint test."
    echo "tools: Read"
    echo "created: 2026-06-18"
    echo "modified: 2026-06-18"
    echo "reviewed: 2026-06-18"
    echo "---"
    echo "Fixture body."
  } > "$1"
}

# run <project-dir> [env-assignment] — invoke the checker, capture combined
# output + exit code into globals OUT / RC.
run() {
  local dir="$1"
  OUT="$(bash "$checker" --project-dir "$dir" 2>&1)"
  RC=$?
}

echo "=== TEST A: real repo is clean (all agents opus) ==="
run "$repo_root"
assert "real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

# --- TEST B: all-opus fixture tree -------------------------------------------
echo "=== TEST B: all-opus fixture exits 0 ==="
fx_b="$(mktemp -d)"
trap 'rm -rf "$fx_b" "${fx_c:-}" "${fx_d:-}" "${fx_e:-}" "${fx_f:-}" "${fx_g:-}" "${fx_h:-}" "${fx_i:-}"' EXIT
make_agent "$fx_b/demo-plugin/agents/good.md" opus
make_agent "$fx_b/other-plugin/agents/also-good.md" opus
run "$fx_b"
assert "all-opus fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "all-opus fixture reports 2 checked" "$(contains "$OUT" 'All 2 agent files declare a tier model')"

# --- TEST C: a model: haiku agent --------------------------------------------
echo "=== TEST C: model: haiku agent exits 1 and is named ==="
fx_c="$(mktemp -d)"
make_agent "$fx_c/demo-plugin/agents/good.md" opus
make_agent "$fx_c/demo-plugin/agents/bad.md" haiku
run "$fx_c"
assert "haiku fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "haiku fixture names the offending file" "$(contains "$OUT" 'agents/bad.md')"
assert "haiku fixture reports the bad model" "$(contains "$OUT" 'model: haiku')"

# --- TEST D: a model: sonnet agent -------------------------------------------
echo "=== TEST D: sonnet needs an explicit effort; inherit is rejected ==="
fx_d="$(mktemp -d)"
make_agent "$fx_d/demo-plugin/agents/legacy.md" sonnet
run "$fx_d"
assert "effortless sonnet exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "effortless sonnet names the offending file" "$(contains "$OUT" 'agents/legacy.md')"
assert "effortless sonnet names the missing effort" "$(contains "$OUT" 'model: sonnet needs an explicit effort:')"
rm -f "$fx_d/demo-plugin/agents/legacy.md"
make_agent_effort "$fx_d/demo-plugin/agents/bounded.md" sonnet low
run "$fx_d"
assert "sonnet + effort exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "sonnet + effort is counted" "$(contains "$OUT" 'SONNET_AGENTS=1')"
make_agent "$fx_d/demo-plugin/agents/inherits.md" inherit
run "$fx_d"
assert "inherit exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "inherit is named" "$(contains "$OUT" 'model: inherit')"
rm -f "$fx_d/demo-plugin/agents/inherits.md"
# An invalid effort past line 20 is still validated: the sonnet check reads the
# whole frontmatter, so a head -20 effort read would let it pass unchecked.
{
  echo "---"; echo "name: deep"; echo "model: sonnet"
  for i in $(seq 1 20); do echo "pad$i: x"; done
  echo "effort: bogus"; echo "---"; echo "Fixture body."
} > "$fx_d/demo-plugin/agents/deep.md"
run "$fx_d"
assert "late invalid effort exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "late invalid effort is named" "$(contains "$OUT" 'effort: bogus')"
rm -f "$fx_d/demo-plugin/agents/deep.md"
# A CRLF agent file is parsed, not skipped as frontmatter-less.
make_agent_effort "$fx_d/demo-plugin/agents/crlf.md" sonnet low
sed 's/$/\r/' "$fx_d/demo-plugin/agents/crlf.md" > "$fx_d/crlf.tmp" && mv "$fx_d/crlf.tmp" "$fx_d/demo-plugin/agents/crlf.md"
run "$fx_d"
assert "CRLF sonnet + effort exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

# --- TEST E: an allowlisted file is honored ----------------------------------
echo "=== TEST E: allowlisted file is honored ==="
fx_e="$(mktemp -d)"
make_agent "$fx_e/demo-plugin/agents/instrument.md" haiku
# Without the allowlist this would fail; with it the file is exempt.
e_out="$(CHECK_AGENT_MODEL_ALLOWLIST='demo-plugin/agents/instrument.md' \
  bash "$checker" --project-dir "$fx_e" 2>&1)"
e_rc=$?
assert "allowlisted haiku agent exits 0" "$([ "$e_rc" -eq 0 ] && echo true || echo false)"
assert "allowlisted file is not named as an error" "$([ "$(contains "$e_out" 'instrument.md')" = "false" ] && echo true || echo false)"

# --- TEST F: .claude/worktrees/ copies are pruned (#1492) --------------------
echo "=== TEST F: worktree copies are pruned, not scanned (#1492) ==="
fx_f="$(mktemp -d)"
make_agent "$fx_f/demo-plugin/agents/good.md" opus
# A worktree copy nested inside a plugin dir — must be pruned by the stage-2 find.
make_agent "$fx_f/demo-plugin/.claude/worktrees/agent-deadbeef/agents/leaked.md" haiku
# A worktree copy at the repo root — must be excluded by the stage-1 maxdepth.
make_agent "$fx_f/.claude/worktrees/agent-cafef00d/demo-plugin/agents/leaked2.md" haiku
run "$fx_f"
assert "worktree fixture exits 0 (copies pruned)" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "worktree fixture reports only the 1 real agent" "$(contains "$OUT" 'All 1 agent files declare a tier model')"
assert "no .claude/worktrees/ path leaks into output" "$([ "$(contains "$OUT" '.claude/worktrees/')" = "false" ] && echo true || echo false)"

# --- TEST G: the scan ROOT is itself a worktree (#2219) ----------------------
# TEST F pins that SIBLING worktrees are pruned. The inverse — proj_dir IS an
# agent worktree — is the #2219 defect: every descendant path then contains
# `/.claude/worktrees/`, so a bare `*/.claude/worktrees/*` prune matches the whole
# scan root and the guard scans ZERO files while still exiting 0. Since
# worktree-isolated subagents are this repo's normal way of doing plugin work, that
# made an agent's own local verification structurally incapable of failing.
echo "=== TEST G: a worktree-shaped scan root still scans its own files (#2219) ==="
fx_g="$(mktemp -d)"
[ -n "$fx_g" ] || { echo "mktemp failed" >&2; exit 1; }
# Build a root whose PATH contains .claude/worktrees/, mirroring a real agent worktree.
wt_root="$fx_g/repo/.claude/worktrees/agent-abc123"
make_agent "$wt_root/demo-plugin/agents/good.md" opus
make_agent "$wt_root/other-plugin/agents/also-good.md" opus
run "$wt_root"
assert "worktree-shaped root exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
# The load-bearing assertion: a NON-ZERO scan count. Pre-fix this reported
# "No agent files found" — indistinguishable from a clean tree.
assert "worktree-shaped root scans both agents (not zero)" "$(contains "$OUT" 'AGENT_FILES_SCANNED=2')"
assert "worktree-shaped root does not report an empty scan" "$([ "$(contains "$OUT" 'No agent files found')" = "false" ] && echo true || echo false)"

# Guard integrity: a defect planted inside that worktree-shaped root must still be
# CAUGHT. Without this, the assertions above would also pass against a guard that
# discovered the files but stopped checking them.
make_agent "$wt_root/demo-plugin/agents/bad.md" sonnet
run "$wt_root"
assert "defect inside a worktree-shaped root is caught" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "defect inside a worktree-shaped root is named" "$(contains "$OUT" 'agents/bad.md')"

# And a worktree nested INSIDE the worktree-shaped root must still be pruned, so
# the anchored prune did not simply disable sibling pruning altogether.
rm -f "$wt_root/demo-plugin/agents/bad.md"
make_agent "$wt_root/.claude/worktrees/agent-nested/demo-plugin/agents/leaked.md" haiku
run "$wt_root"
assert "sibling worktree nested under a worktree root is still pruned" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "nested worktree copy is not counted" "$(contains "$OUT" 'AGENT_FILES_SCANNED=2')"

# --- TEST H: a model: fable agent is sanctioned --------------------------
echo "=== TEST H: model: fable agent exits 0 (sanctioned for hardest delegated work) ==="
fx_h="$(mktemp -d)"
make_agent "$fx_h/demo-plugin/agents/hardest.md" fable
run "$fx_h"
assert "fable fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

# --- TEST I: effort: validation -----------------------------------------------
echo "=== TEST I: effort: low passes; effort: ultra fails and is named; absent effort passes ==="
fx_i="$(mktemp -d)"
make_agent_effort "$fx_i/demo-plugin/agents/low-effort.md" opus low
run "$fx_i"
assert "effort: low exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"

rm -f "$fx_i/demo-plugin/agents/low-effort.md"
make_agent_effort "$fx_i/demo-plugin/agents/bad-effort.md" opus ultra
run "$fx_i"
assert "effort: ultra exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "effort: ultra names the offending file" "$(contains "$OUT" 'agents/bad-effort.md')"
assert "effort: ultra names the bad value" "$(contains "$OUT" 'effort: ultra')"

rm -f "$fx_i/demo-plugin/agents/bad-effort.md"
make_agent_effort "$fx_i/demo-plugin/agents/no-effort.md" opus ""
run "$fx_i"
assert "no effort: line exits 0 (field is optional)" "$([ "$RC" -eq 0 ] && echo true || echo false)"

# --- TEST J: the lean Haiku reader ---------------------------------------------
# haiku passes only with omitClaudeMd: true + a Read/Grep/Glob-only tools list +
# an explicit effort. Each failing case removes exactly one condition from the
# passing one, so the suite fails both a guard that still bans every haiku agent
# and one that lets any haiku agent through.
echo "=== TEST J: lean haiku reader passes; each missing condition fails and is named ==="
# make_lean <path> <omit-line-or-empty> <tools-block> <effort-line-or-empty>
make_lean() {
  local agent_name
  agent_name="$(basename "$1" .md)"
  mkdir -p "$(dirname "$1")"
  {
    echo "---"
    echo "name: $agent_name"
    echo "model: haiku"
    [ -n "$2" ] && echo "$2"
    printf '%s\n' "$3"
    [ -n "$4" ] && echo "$4"
    echo "description: Fixture agent for the model lint test."
    echo "---"
    echo "Fixture body."
  } > "$1"
}
fx_j="$(mktemp -d)"
[ -n "$fx_j" ] || { echo "mktemp failed" >&2; exit 1; }

make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "tools: Read, Grep, Glob" "effort: low"
run "$fx_j"
assert "lean haiku reader exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "lean haiku reader is counted" "$(contains "$OUT" 'LEAN_HAIKU_AGENTS=1')"

make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "$(printf 'tools:\n  - Read\n  - Glob')" "effort: low"
run "$fx_j"
assert "YAML-list tools form also passes" "$([ "$RC" -eq 0 ] && echo true || echo false)"

make_lean "$fx_j/demo-plugin/agents/lean.md" "" "tools: Read, Grep, Glob" "effort: low"
run "$fx_j"
assert "missing omitClaudeMd exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "missing omitClaudeMd is named" "$(contains "$OUT" 'needs omitClaudeMd: true')"

make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "tools: Read, Edit" "effort: low"
run "$fx_j"
assert "a write tool exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "the write tool is named" "$(contains "$OUT" "tool 'Edit' is outside")"

make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "description-placeholder: x" "effort: low"
run "$fx_j"
assert "omitted tools exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "omitted tools is named" "$(contains "$OUT" 'needs an explicit tools:')"

make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "tools: Read" ""
run "$fx_j"
assert "missing effort exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "missing effort is named" "$(contains "$OUT" 'needs an explicit effort:')"

# Keys that hand the agent capability outside Read/Grep/Glob (#3047 review).
for key_line in "mcpServers: [github]" "skills: [git-commit]" "hooks: {}"; do
  make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "$(printf 'tools: Read\n%s' "$key_line")" "effort: low"
  run "$fx_j"
  assert "a lean haiku agent declaring '${key_line%%:*}:' exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
  assert "the '${key_line%%:*}:' key is named" "$(contains "$OUT" "declares ${key_line%%:*}:")"
done

# A second tools: key would be the value YAML keeps (last wins).
make_lean "$fx_j/demo-plugin/agents/lean.md" "omitClaudeMd: true" "$(printf 'tools: Read\ntools: Read, Bash')" "effort: low"
run "$fx_j"
assert "a duplicate tools: key exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "the duplicate tools: key is named" "$(contains "$OUT" 'declares tools: more than once')"

# A sonnet agent passes on its own tier, never as a lean-haiku exemption.
rm -f "$fx_j/demo-plugin/agents/lean.md"
make_agent_effort "$fx_j/demo-plugin/agents/lean-sonnet.md" sonnet low
run "$fx_j"
assert "sonnet + effort passes on its own tier" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "sonnet is not counted as lean haiku" "$(contains "$OUT" 'LEAN_HAIKU_AGENTS=0')"

# --- Summary -----------------------------------------------------------------
echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
