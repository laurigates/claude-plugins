#!/usr/bin/env bash
# Regression test for scripts/check-agent-model.sh
# (.claude/rules/agent-development.md § "Model Selection for Agents" — the
#  always-Opus standard for plugin agents).
#
# Guards:
#   A. the real repo stays clean — every agent is on opus, so the check exits 0
#   B. an all-opus fixture tree exits 0
#   C. a `model: haiku` agent exits 1 and names the offending file
#   D. a `model: sonnet` agent exits 1 and names the offending file
#   E. an allowlisted file is honored (via the CHECK_AGENT_MODEL_ALLOWLIST seam)
#   F. agent worktree copies under .claude/worktrees/ are pruned, not scanned
#      (#1492 parity)
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

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

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
trap 'rm -rf "$fx_b" "${fx_c:-}" "${fx_d:-}" "${fx_e:-}" "${fx_f:-}" "${fx_g:-}"' EXIT
make_agent "$fx_b/demo-plugin/agents/good.md" opus
make_agent "$fx_b/other-plugin/agents/also-good.md" opus
run "$fx_b"
assert "all-opus fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "all-opus fixture reports 2 checked" "$(contains "$OUT" 'All 2 agent files run on opus')"

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
echo "=== TEST D: model: sonnet agent exits 1 and is named ==="
fx_d="$(mktemp -d)"
make_agent "$fx_d/demo-plugin/agents/legacy.md" sonnet
run "$fx_d"
assert "sonnet fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "sonnet fixture names the offending file" "$(contains "$OUT" 'agents/legacy.md')"
assert "sonnet fixture reports the bad model" "$(contains "$OUT" 'model: sonnet')"

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
assert "worktree fixture reports only the 1 real agent" "$(contains "$OUT" 'All 1 agent files run on opus')"
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

# --- Summary -----------------------------------------------------------------
echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
