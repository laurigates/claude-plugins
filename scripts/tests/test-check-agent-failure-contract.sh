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
#   F. references/brief-templates.md missing "Completion manifest" → exit 1
#   G. parallel-agent-dispatch SKILL.md missing the #1868 resume-hazard caveat → exit 1
#   H. parallel-agent-dispatch SKILL.md missing "#1868" → exit 1
#   I. parallel-agent-dispatch SKILL.md missing "idle_notification" → exit 1
#   J. parallel-agent-dispatch SKILL.md missing "#2039" → exit 1
#   K. references/failure-recovery.md missing the #1424 "9:1" threshold → exit 1
#   L. references/worktree-hazards.md missing "Nested-repo worktree isolation" → exit 1
#   M. REFERENCE.md index no longer links references/failure-recovery.md → exit 1
#   N. references/worktree-hazards.md missing "may resolve to a LOCAL worktree" → exit 1
#   O. references/failure-recovery.md missing the local-worktree audit section → exit 1
#   P. parallel-agent-dispatch SKILL.md missing "#2447" → exit 1
#   Q. references/worktree-hazards.md missing the draft-PR-early mitigation → exit 1
#   R. parallel-agent-dispatch SKILL.md missing the "worktreePath" tell → exit 1
#
# Issue #1868: Workflow({resumeFromRunId}) re-runs an already-succeeded
# isolation:"worktree" agent instead of returning its cached result, re-firing
# its outward side effects (a duplicate PR). Guards G/H keep the documented
# caveat from being silently dropped by a future bulk edit.
#
# Issue #2039: an implementer agent completes its work, then goes idle emitting
# only an idle_notification — the final report never reaches the orchestrator
# (communication loss, not work loss; recovery is SendMessage-to-resend, never
# respawn). Guards I/J keep the "Idle without report" variant documented.
#
# Issue #2143: parallel-agent-dispatch's supporting material was split from one
# REFERENCE.md into references/*.md by consumer path, and REFERENCE.md became a
# thin index. The markers the checker pins therefore live in specific reference
# files now. Guards K/L prove the checker actually reads those files (a split
# that silently stopped asserting them would still exit 0 without these), and
# guard M proves the index is required to keep linking them — a reference file
# nothing links to is unreachable from the skill even though it still exists.
#
# Issue #2447: a dispatch made with isolation:"remote" can resolve to a LOCAL
# git worktree with nothing in the tool result saying so, and a recovery audit
# that checks only the remote then reports intact-but-unpushed work as lost.
# Guards N–R keep each half of the fix pinned to the file that owns it: the
# mode-detection statement and the draft-PR-early mitigation in
# references/worktree-hazards.md, the local-worktree recovery audit in
# references/failure-recovery.md, and the pointer + tells in SKILL.md.
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
  # references/*.md (#2143) — the split supporting material the checker pins.
  mkdir -p "$root/agent-patterns-plugin/skills/parallel-agent-dispatch/references"
  cp "$repo_root/agent-patterns-plugin/skills/parallel-agent-dispatch/references/"*.md \
     "$root/agent-patterns-plugin/skills/parallel-agent-dispatch/references/"
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

# --- Guard F: references/brief-templates.md missing the manifest line ---
fx_f="$(mktemp -d)"
build_fixture "$fx_f"
strip_marker "$fx_f/agent-patterns-plugin/skills/parallel-agent-dispatch/references/brief-templates.md" "Completion manifest"
assert "F: brief-templates.md missing 'Completion manifest' fails (exit 1)" \
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

# --- Guard I: SKILL.md missing the #2039 idle_notification signal name ---
# Issue #2039: an agent completes its work then goes idle with only an
# idle_notification — the report never arrives. Strip the signal name and
# confirm the check fails, so a bulk edit can't silently drop the variant.
fx_i="$(mktemp -d)"
build_fixture "$fx_i"
strip_marker "$fx_i/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "idle_notification"
assert "I: dispatch SKILL.md missing idle_notification fails (exit 1)" \
  "$([ "$(run_fixture "$fx_i")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_i"

# --- Guard J: SKILL.md missing the #2039 issue reference ---
fx_j="$(mktemp -d)"
build_fixture "$fx_j"
strip_marker "$fx_j/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "#2039"
assert "J: dispatch SKILL.md missing #2039 fails (exit 1)" \
  "$([ "$(run_fixture "$fx_j")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_j"

# --- Guard K: references/failure-recovery.md missing the #1424 kill threshold ---
# The quantitative hook-thrashing heuristic moved out of REFERENCE.md into the
# failure-recovery reference (#2143). Strip the ratio and confirm the checker
# still reads that file — otherwise the split would have silently disarmed it.
fx_k="$(mktemp -d)"
build_fixture "$fx_k"
strip_marker "$fx_k/agent-patterns-plugin/skills/parallel-agent-dispatch/references/failure-recovery.md" "9:1"
assert "K: failure-recovery.md missing the 9:1 threshold fails (exit 1)" \
  "$([ "$(run_fixture "$fx_k")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_k"

# --- Guard L: references/worktree-hazards.md missing the #1838 section ---
fx_l="$(mktemp -d)"
build_fixture "$fx_l"
strip_marker "$fx_l/agent-patterns-plugin/skills/parallel-agent-dispatch/references/worktree-hazards.md" "Nested-repo worktree isolation"
assert "L: worktree-hazards.md missing the nested-repo section fails (exit 1)" \
  "$([ "$(run_fixture "$fx_l")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_l"

# --- Guard M: REFERENCE.md index no longer links a reference file ---
# A reference file nothing links to is unreachable from the skill even though it
# still exists on disk — the failure mode a thin index introduces.
fx_m="$(mktemp -d)"
build_fixture "$fx_m"
strip_marker "$fx_m/agent-patterns-plugin/skills/parallel-agent-dispatch/REFERENCE.md" "references/failure-recovery.md"
assert "M: REFERENCE.md index dropping a references/ link fails (exit 1)" \
  "$([ "$(run_fixture "$fx_m")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_m"

# --- Guard N: worktree-hazards.md missing the remote-may-be-local statement ---
# Issue #2447: isolation:"remote" can resolve to an ordinary local worktree and
# the tool result never says so. Strip the statement and confirm the checker
# fails, so a bulk edit can't silently drop the mode-detection guidance.
fx_n="$(mktemp -d)"
build_fixture "$fx_n"
strip_marker "$fx_n/agent-patterns-plugin/skills/parallel-agent-dispatch/references/worktree-hazards.md" "may resolve to a LOCAL worktree"
assert "N: worktree-hazards.md missing the remote-may-be-local statement fails (exit 1)" \
  "$([ "$(run_fixture "$fx_n")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_n"

# --- Guard O: failure-recovery.md missing the local-worktree audit section ---
# The recovery half: an empty remote is evidence about the PUSH, not the WORK.
# Without this section the documented protocol is remote-only again.
fx_o="$(mktemp -d)"
build_fixture "$fx_o"
strip_marker "$fx_o/agent-patterns-plugin/skills/parallel-agent-dispatch/references/failure-recovery.md" "Audit local worktrees alongside the remote"
assert "O: failure-recovery.md missing the local-worktree audit section fails (exit 1)" \
  "$([ "$(run_fixture "$fx_o")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_o"

# --- Guard P: SKILL.md missing the #2447 issue reference ---
fx_p="$(mktemp -d)"
build_fixture "$fx_p"
strip_marker "$fx_p/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "#2447"
assert "P: dispatch SKILL.md missing #2447 fails (exit 1)" \
  "$([ "$(run_fixture "$fx_p")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_p"

# --- Guard Q: worktree-hazards.md missing the draft-PR-early mitigation ---
# The mitigation that actually worked: commit/push/open a draft PR BEFORE the
# bulk of the work, then push after each commit, so the remote mirrors the work.
fx_q="$(mktemp -d)"
build_fixture "$fx_q"
strip_marker "$fx_q/agent-patterns-plugin/skills/parallel-agent-dispatch/references/worktree-hazards.md" "draft PR before the bulk of the work"
assert "Q: worktree-hazards.md missing the draft-PR-early mitigation fails (exit 1)" \
  "$([ "$(run_fixture "$fx_q")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_q"

# --- Guard R: SKILL.md missing the worktreePath tell ---
fx_r="$(mktemp -d)"
build_fixture "$fx_r"
strip_marker "$fx_r/agent-patterns-plugin/skills/parallel-agent-dispatch/SKILL.md" "worktreePath"
assert "R: dispatch SKILL.md missing the worktreePath tell fails (exit 1)" \
  "$([ "$(run_fixture "$fx_r")" -eq 1 ] && echo true || echo false)"
rm -rf "$fx_r"

echo "check-agent-failure-contract (#1601/#1868/#2039/#2143/#2447): ${pass_count} passed, ${fail_count} failed"
[ "$fail_count" -eq 0 ]
