#!/usr/bin/env bash
# Regression test for scripts/check-agent-failure-contract.sh — the #1601
# completion-manifest invariant specifically.
#
# Issue #1601: a refactor subagent assigned a large CLOSED LIST of mechanical
# deletions stops early but returns a plausible (often truncated) self-report,
# so the under-delivery is invisible unless the orchestrator re-runs the
# authoritative checker. The fix adds a Completion Manifest requirement +
# batch-size cap to agents-plugin/agents/refactor.md and #1601 / manifest
# language to parallel-agent-dispatch SKILL.md + REFERENCE.md. This test guards
# that those semantic markers survive future bulk edits.
#
# Guards:
#   A. the real repo passes (exit 0) — every marker present in the live files
#   B. a faithful fixture copy passes (exit 0)
#   C. refactor.md missing the "Completion Manifest" section → exit 1
#   D. refactor.md missing the "#1601" reference → exit 1
#   E. parallel-agent-dispatch SKILL.md missing "#1601" → exit 1
#   F. parallel-agent-dispatch REFERENCE.md missing "Completion manifest" → exit 1
#   G. parallel-agent-dispatch SKILL.md missing the #1868 resume-hazard caveat → exit 1
#   H. parallel-agent-dispatch SKILL.md missing "#1868" → exit 1
#
# Issue #1868: Workflow({resumeFromRunId}) re-runs an already-succeeded
# isolation:"worktree" agent instead of returning its cached result, re-firing
# its outward side effects (a duplicate PR). Guards G/H keep the documented
# caveat from being silently dropped by a future bulk edit.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-agent-failure-contract.sh"

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

# build_fixture <dest-root> — copy the four contract files + the checker into a
# self-contained fixture tree that the checker can run against (it cds to its
# own parent and resolves the target files relative to there).
build_fixture() {
  local root="$1"
  mkdir -p "$root/scripts"
  cp "$checker" "$root/scripts/check-agent-failure-contract.sh"
  mkdir -p "$root/agent-patterns-plugin/skills/parallel-agent-dispatch"
  mkdir -p "$root/agent-patterns-plugin/skills/custom-agent-definitions"
  mkdir -p "$root/agents-plugin/agents"
  cp "$repo_root/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" \
     "$root/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md"
  cp "$repo_root/agent-patterns-plugin/skills/parallel-agent-dispatch/REFERENCE.md" \
     "$root/agent-patterns-plugin/skills/parallel-agent-dispatch/REFERENCE.md"
  cp "$repo_root/agent-patterns-plugin/skills/custom-agent-definitions/SKILL.md" \
     "$root/agent-patterns-plugin/skills/custom-agent-definitions/SKILL.md"
  cp "$repo_root/agents-plugin/agents/refactor.md" \
     "$root/agents-plugin/agents/refactor.md"
}

# strip_marker <file> <fixed-string> — rewrite the file with every line
# containing the literal needle removed.
strip_marker() {
  local file="$1" needle="$2" tmp
  tmp="$(mktemp)"
  grep -vF -- "$needle" "$file" > "$tmp"
  mv "$tmp" "$file"
}

run_fixture() {
  # run_fixture <root> — run the fixture checker, echo its exit code.
  bash "$1/scripts/check-agent-failure-contract.sh" >/dev/null 2>&1
  echo "$?"
}

# --- Guard A: real repo passes ---
bash "$checker" >/dev/null 2>&1
real_rc=$?
assert "A: real repo passes the contract check (exit 0)" \
  "$([ "$real_rc" -eq 0 ] && echo true || echo false)"

# --- Guard B: faithful fixture passes ---
fx_b="$(mktemp -d)"
build_fixture "$fx_b"
assert "B: faithful fixture copy passes (exit 0)" \
  "$([ "$(run_fixture "$fx_b")" -eq 0 ] && echo true || echo false)"
rm -rf "$fx_b"

# --- Guard C: refactor.md missing Completion Manifest section ---
fx_c="$(mktemp -d)"
build_fixture "$fx_c"
strip_marker "$fx_c/agents-plugin/agents/refactor.md" "Completion Manifest"
assert "C: missing Completion Manifest section fails (exit 1)" \
  "$([ "$(run_fixture "$fx_c")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_c"

# --- Guard D: refactor.md missing #1601 reference ---
fx_d="$(mktemp -d)"
build_fixture "$fx_d"
strip_marker "$fx_d/agents-plugin/agents/refactor.md" "#1601"
assert "D: refactor.md missing #1601 fails (exit 1)" \
  "$([ "$(run_fixture "$fx_d")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_d"

# --- Guard E: SKILL.md missing #1601 ---
fx_e="$(mktemp -d)"
build_fixture "$fx_e"
strip_marker "$fx_e/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "#1601"
assert "E: dispatch SKILL.md missing #1601 fails (exit 1)" \
  "$([ "$(run_fixture "$fx_e")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_e"

# --- Guard F: REFERENCE.md missing the manifest line ---
fx_f="$(mktemp -d)"
build_fixture "$fx_f"
strip_marker "$fx_f/agent-patterns-plugin/skills/parallel-agent-dispatch/REFERENCE.md" "Completion manifest"
assert "F: REFERENCE.md missing 'Completion manifest' fails (exit 1)" \
  "$([ "$(run_fixture "$fx_f")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_f"

# --- Guard G: SKILL.md missing the #1868 resumeFromRunId re-run caveat ---
# Issue #1868: Workflow({resumeFromRunId}) re-runs succeeded worktree agents,
# opening duplicate PRs. Strip the caveat heading phrase and confirm the check
# fails, so a bulk edit can't silently drop the resume-hazard documentation.
fx_g="$(mktemp -d)"
build_fixture "$fx_g"
strip_marker "$fx_g/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "re-runs succeeded worktree agents"
assert "G: dispatch SKILL.md missing the #1868 caveat heading fails (exit 1)" \
  "$([ "$(run_fixture "$fx_g")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_g"

# --- Guard H: SKILL.md missing the #1868 issue reference ---
fx_h="$(mktemp -d)"
build_fixture "$fx_h"
strip_marker "$fx_h/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "#1868"
assert "H: dispatch SKILL.md missing #1868 fails (exit 1)" \
  "$([ "$(run_fixture "$fx_h")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_h"

echo "check-agent-failure-contract (#1601/#1868): ${pass_count} passed, ${fail_count} failed"
[ "$fail_count" -eq 0 ]
