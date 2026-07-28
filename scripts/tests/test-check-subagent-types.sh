#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: fixture bodies deliberately contain literal backticks/`$` in single quotes
# Regression test for scripts/check-subagent-types.sh
#
# The defect this guards (test-analyze, Refs #2174): a skill body named
# `subagent_type` values that resolved to no agent anywhere, so every dispatch
# it instructed failed at "Agent type not found" — invisible to every existing
# structural lint.
#
# Guards:
#   A. the real repo has zero unresolvable subagent_type values (exit 0)
#   B. the exact pre-fix test-analyze routing table is REJECTED, and every one
#      of its 6 stale names is reported by name (guard integrity: a guard that
#      cannot fail on the original defect is not a guard)
#   C. a plugin-qualified value that resolves passes
#   D. a bare-but-resolvable value is a WARN, not an ERROR — and --strict
#      escalates it
#   E. built-in agent types (general-purpose, Explore) are never flagged
#   F. prose mentions / jq field reads / the uppercase shell var are NOT
#      extracted as dispatches (false-positive integrity)
#   G. an exception entry suppresses a value at one path only
#   H. .claude/worktrees/ copies are pruned, not scanned (#1492 parity)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-subagent-types.sh"

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

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

# make_agent <path> — minimal agent .md so the inventory picks it up.
make_agent() {
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: %s\nmodel: opus\n---\nFixture agent.\n' "$(basename "$1" .md)" > "$1"
}

# make_skill <path> <body>
make_skill() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

run() {
  local dir="$1"; shift
  OUT="$(bash "$checker" --project-dir "$dir" "$@" 2>&1)"
  RC=$?
}

# --- TEST A: the real repo is clean ------------------------------------------
echo "=== TEST A: real repo has no unresolvable subagent_type ==="
run "$repo_root"
assert "real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "real repo reports UNRESOLVABLE=0" "$(contains "$OUT" 'UNRESOLVABLE=0')"
assert "real repo scanned some skill files" "$([ "$(contains "$OUT" 'FILES_SCANNED=0')" = "false" ] && echo true || echo false)"

fx_b=""; fx_c=""; fx_d=""; fx_e=""; fx_f=""; fx_g=""; fx_h=""
cleanup() { rm -rf "$fx_b" "$fx_c" "$fx_d" "$fx_e" "$fx_f" "$fx_g" "$fx_h"; }
trap cleanup EXIT

# --- TEST B: the pre-fix routing table is rejected ---------------------------
# Verbatim shape of the defect: the six stale names test-analyze shipped.
echo "=== TEST B: pre-fix test-analyze table is rejected, each stale name named ==="
fx_b="$(mktemp -d)"
[ -n "$fx_b" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_b/agents-plugin/agents/review.md"
make_agent "$fx_b/agents-plugin/agents/security-audit.md"
make_agent "$fx_b/agents-plugin/agents/debug.md"
make_agent "$fx_b/agents-plugin/agents/refactor.md"
make_agent "$fx_b/agents-plugin/agents/test.md"
make_agent "$fx_b/agents-plugin/agents/ci.md"
make_agent "$fx_b/agents-plugin/agents/docs.md"
make_skill "$fx_b/testing-plugin/skills/test-analyze/SKILL.md" '# Test Analysis

- Accessibility → Use `Task` tool with `subagent_type: code-review`
- Security → Use `Task` tool with `subagent_type: security-audit`
- Performance → Use `Task` tool with `subagent_type: system-debugging`
- Code quality → Use `Task` tool with `subagent_type: code-refactoring`
- Flaky tests → Use `Task` tool with `subagent_type: test-architecture`
- CI/CD → Use `Task` tool with `subagent_type: cicd-pipelines`
- Docs → Use `Task` tool with `subagent_type: documentation`'
run "$fx_b"
assert "pre-fix table exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "pre-fix table reports UNRESOLVABLE=6" "$(contains "$OUT" 'UNRESOLVABLE=6')"
for stale in code-review system-debugging code-refactoring test-architecture cicd-pipelines documentation; do
  assert "pre-fix table names stale value $stale" "$(contains "$OUT" "VALUE=$stale")"
done
# security-audit is the one of the seven that did resolve as a bare name.
assert "pre-fix table treats security-audit as WARN, not ERROR" \
  "$(contains "$OUT" 'TYPE=unqualified_subagent_type FILE=testing-plugin/skills/test-analyze/SKILL.md VALUE=security-audit')"

# --- TEST C: qualified values resolve ----------------------------------------
echo "=== TEST C: plugin-qualified values pass ==="
fx_c="$(mktemp -d)"
[ -n "$fx_c" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_c/agents-plugin/agents/review.md"
make_agent "$fx_c/agents-plugin/agents/docs.md"
make_skill "$fx_c/demo-plugin/skills/thing/SKILL.md" '# Thing

| Category | Dispatch |
|---|---|
| Review | `subagent_type: agents-plugin:review` |
| Docs | `subagent_type: agents-plugin:docs` |'
run "$fx_c"
assert "qualified fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "qualified fixture is STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
assert "qualified fixture checked 2 refs" "$(contains "$OUT" 'REFS_CHECKED=2')"

# --- TEST D: bare-but-resolvable is WARN; --strict escalates -----------------
echo "=== TEST D: bare-but-resolvable is WARN, escalated by --strict ==="
fx_d="$(mktemp -d)"
[ -n "$fx_d" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_d/agents-plugin/agents/review.md"
make_skill "$fx_d/demo-plugin/skills/thing/SKILL.md" 'Use `subagent_type: review` here.'
run "$fx_d"
assert "bare resolvable exits 0 by default" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "bare resolvable is STATUS=WARN" "$(contains "$OUT" 'STATUS=WARN')"
assert "bare resolvable suggests the qualified form" "$(contains "$OUT" 'FIX=agents-plugin:review')"
run "$fx_d" --strict
assert "bare resolvable exits 1 under --strict" "$([ "$RC" -eq 1 ] && echo true || echo false)"

# --- TEST E: built-ins are never flagged -------------------------------------
echo "=== TEST E: built-in agent types pass ==="
fx_e="$(mktemp -d)"
[ -n "$fx_e" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_e/agents-plugin/agents/review.md"
make_skill "$fx_e/demo-plugin/skills/thing/SKILL.md" 'Task({subagent_type: "general-purpose"}) and "subagent_type": "Explore",'
run "$fx_e"
assert "built-ins exit 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "built-ins are STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
assert "built-ins were counted as refs" "$(contains "$OUT" 'REFS_CHECKED=2')"

# --- TEST F: non-dispatch mentions are not extracted -------------------------
echo "=== TEST F: prose / jq / shell-var mentions are not dispatches ==="
fx_f="$(mktemp -d)"
[ -n "$fx_f" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_f/agents-plugin/agents/review.md"
make_skill "$fx_f/demo-plugin/skills/thing/SKILL.md" 'Invocations are keyed by `subagent_type`.
Event fields include `subagent_type`/`subagent_prompt` for SubagentStart.
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '"'"'.subagent_type // empty'"'"')'
run "$fx_f"
assert "non-dispatch mentions exit 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "non-dispatch mentions extract nothing" "$(contains "$OUT" 'REFS_CHECKED=0')"

# --- TEST G: exceptions are path-scoped --------------------------------------
echo "=== TEST G: an exception suppresses one path only ==="
fx_g="$(mktemp -d)"
[ -n "$fx_g" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_g/agents-plugin/agents/review.md"
make_skill "$fx_g/demo-plugin/skills/doc-example/SKILL.md" 'subagent_type: "third-party-agent"'
make_skill "$fx_g/demo-plugin/skills/real/SKILL.md" 'subagent_type: "third-party-agent"'
OUT="$(CHECK_SUBAGENT_TYPE_EXCEPTIONS='demo-plugin/skills/doc-example/SKILL.md|third-party-agent' \
  bash "$checker" --project-dir "$fx_g" 2>&1)"
RC=$?
assert "exception fixture still fails on the un-excepted path" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "exception fixture reports exactly 1 unresolvable" "$(contains "$OUT" 'UNRESOLVABLE=1')"
assert "exception fixture names the un-excepted file" "$(contains "$OUT" 'FILE=demo-plugin/skills/real/SKILL.md')"
assert "exception fixture does not name the excepted file" \
  "$([ "$(contains "$OUT" 'FILE=demo-plugin/skills/doc-example/SKILL.md')" = "false" ] && echo true || echo false)"

# --- TEST H: worktree copies are pruned (#1492 parity) -----------------------
echo "=== TEST H: .claude/worktrees/ copies are pruned, not scanned ==="
fx_h="$(mktemp -d)"
[ -n "$fx_h" ] || { echo "mktemp failed" >&2; exit 1; }
make_agent "$fx_h/agents-plugin/agents/review.md"
make_skill "$fx_h/demo-plugin/skills/thing/SKILL.md" 'subagent_type: agents-plugin:review'
# A worktree copy nested inside a plugin dir carrying a broken value.
make_skill "$fx_h/demo-plugin/.claude/worktrees/agent-deadbeef/skills/leak/SKILL.md" 'subagent_type: ghost-agent'
run "$fx_h"
assert "worktree fixture exits 0 (copy pruned)" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "worktree fixture scanned only the real skill" "$(contains "$OUT" 'FILES_SCANNED=1')"
assert "no .claude/worktrees/ path leaks into output" \
  "$([ "$(contains "$OUT" '.claude/worktrees/')" = "false" ] && echo true || echo false)"

# --- Summary -----------------------------------------------------------------
echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
