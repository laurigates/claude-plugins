#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: backticked skill IDs in the planted fixtures are literal markdown, not command substitution
# Regression test for scripts/check-skill-references.sh
#
# The linter resolves every `<name>-plugin:<artifact>` citation against the
# skills and agents on disk. Two genuine dead citations motivated it:
# `configure-plugin:multi-repo-discipline` cited a nonexistent
# `agent-patterns-plugin:agent-coworker-detection`, and
# `.claude/rules/skill-argument-handling.md` cited `project-plugin:refocus`
# after the skill was renamed to `project-plugin:project-refocus`.
#
# SEMANTIC, not syntactic: every case EXECUTES a copy of the real linter
# against a planted fixture tree and asserts on its verdict. Grepping the
# linter for a regex would pass against an extractor that matches nothing --
# and a checker that scans zero files exits 0 exactly like a clean tree.
#
# Detection is the cheap half. Three others are weighted equally:
#
#   NARROWNESS — the first run of this linter against the real tree produced 9
#   false positives out of 11 findings. All were extractor artifacts: the prose
#   word "Cross-plugin:" yielded a phantom `ross-plugin:`, and a bare
#   `<plugin>:` prefix with no name (`**testing-plugin:**`, and the shell line
#   `echo "macos-plugin: not Darwin"`) registered as a dead ID. Both shapes are
#   pinned below; a checker that re-admits them gets reverted rather than used.
#
#   COVERAGE — the walk is not repo-wide (see the linter's COVERAGE header).
#   `.claude/rules/*.md` must be scanned (a dead ID in an always-loaded rule
#   misroutes every session) and `docs/**` must NOT be (ADR-0007 cites the
#   pre-rename `git-plugin:commit`, which is correct for an immutable record).
#
#   NON-VACUITY — a broken discovery walk finds zero skills and then resolves
#   every citation against an empty ground truth, passing everything. The
#   linter must fail loudly on an empty truth set instead.
#
# Exit codes: 0 all assertions pass, 1 otherwise.

set -uo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
linter="$repo_root/scripts/check-skill-references.sh"

pass=0
fail=0

ok() {
  printf '  PASS: %s\n' "$1"
  pass=$((pass + 1))
}

bad() {
  printf '  FAIL: %s\n' "$1"
  printf '        %s\n' "${2:-}"
  fail=$((fail + 1))
}

# Base fixture: one real skill and one real agent, so ground truth is non-empty
# and the clean-tree control is meaningful. The linter resolves its scan root as
# `dirname "$0"/..`, so the copy must live under <fixture>/scripts/.
make_fixture() {
  local dir
  dir="$(mktemp -d)"
  [ -n "$dir" ] || {
    printf 'mktemp -d failed\n' >&2
    exit 1
  }
  mkdir -p "$dir/scripts" \
    "$dir/demo-plugin/skills/real-skill" \
    "$dir/demo-plugin/agents" \
    "$dir/.claude/rules" \
    "$dir/docs/adrs"
  cp "$linter" "$dir/scripts/check-skill-references.sh"
  chmod +x "$dir/scripts/check-skill-references.sh"
  printf -- '---\nname: real-skill\n---\n\nBody.\n' \
    >"$dir/demo-plugin/skills/real-skill/SKILL.md"
  printf -- '---\nname: real-agent\n---\n\nBody.\n' \
    >"$dir/demo-plugin/agents/real-agent.md"
  printf '%s' "$dir"
}

fixture="$(make_fixture)"
trap 'rm -rf "$fixture"' EXIT

# run_case <label> <expect: flag|clean> <relative-path> <file-body>
# Plants one file, runs the linter, asserts the verdict, then removes the file
# so cases stay independent.
run_case() {
  local label="$1" expect="$2" rel="$3" body="$4" out status
  mkdir -p "$fixture/$(dirname "$rel")"
  printf '%s\n' "$body" >"$fixture/$rel"
  out="$("$fixture/scripts/check-skill-references.sh" 2>&1)"
  status=$?
  rm -f "$fixture/$rel"

  case "$expect" in
    flag)
      if [ "$status" -ne 0 ]; then
        ok "$label"
      else
        bad "$label" "expected a finding, linter exited 0: $out"
      fi
      ;;
    clean)
      if [ "$status" -eq 0 ]; then
        ok "$label"
      else
        bad "$label" "expected no finding, linter exited $status: $out"
      fi
      ;;
  esac
}

printf 'test-check-skill-references\n'

# --- control: the base fixture alone must be clean -------------------------
if out="$("$fixture/scripts/check-skill-references.sh" 2>&1)"; then
  ok "control: fixture with only resolvable artifacts exits 0"
else
  bad "control: clean fixture" "$out"
fi

# --- detection --------------------------------------------------------------
run_case "detects a dead skill ID in a SKILL.md" flag \
  "demo-plugin/skills/other/SKILL.md" \
  'See `demo-plugin:no-such-skill` for details.'

run_case "detects a dead ID in an always-loaded rule (.claude/rules IS scanned)" flag \
  ".claude/rules/demo.md" \
  'Invoke `demo-plugin:no-such-skill` before editing.'

run_case "detects a dead ID in a REFERENCE.md" flag \
  "demo-plugin/skills/real-skill/REFERENCE.md" \
  'Related: `demo-plugin:no-such-skill`.'

# --- resolution: real artifacts must not be flagged -------------------------
run_case "a citation resolving to a real SKILL.md is clean" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'See `demo-plugin:real-skill` for details.'

run_case "a citation resolving to a real agent is clean" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Dispatch `demo-plugin:real-agent` for this.'

# --- narrowness: the 9 false positives from the first real run --------------
# The GLUED form is the one that needs the left-boundary guard. With a space
# after the colon the non-empty-name guard already rejects it, so a spaced
# fixture passes even against a linter with no boundary check at all — it would
# assert nothing. Here `Cross-plugin:real-skill` yields the phantom
# `ross-plugin:real-skill` (unresolvable, so: a finding) the moment the
# boundary class is dropped or narrowed to `[^a-z0-9_-]`, which still admits
# the uppercase `C`.
run_case "prose 'Cross-plugin:<word>' does not yield a phantom ross-plugin ID" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Cross-plugin:real-skill coordination is out of scope here.'

run_case "a bare '<plugin>:' prefix with no name is not a citation" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'The changelog carries `**testing-plugin:**` as a heading.'

run_case "a shell line echoing '<plugin>: message' is not a citation" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'test "$(uname -s)" = "Darwin" || { echo "macos-plugin: not Darwin"; exit 1; }'

# --- allowlist --------------------------------------------------------------
run_case "the my-plugin: authoring placeholder is allowed" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'Cite a skill as `my-plugin:code-reviewer` in your own plugin.'

run_case "a glob family form (bun-*) is allowed" clean \
  "demo-plugin/skills/other/SKILL.md" \
  'The `typescript-plugin:bun-*` skills cover this.'

# --- coverage boundaries ----------------------------------------------------
run_case "docs/ is deliberately out of scope (ADRs cite pre-rename IDs)" clean \
  "docs/adrs/0007-demo.md" \
  'The command was `demo-plugin:no-such-skill` at the time of this decision.'

run_case "a blockquote callout may cite a dead ID as an example" clean \
  "demo-plugin/skills/other/SKILL.md" \
  '> Formerly `demo-plugin:no-such-skill`, now renamed.'

# --- non-vacuity ------------------------------------------------------------
empty="$(mktemp -d)"
mkdir -p "$empty/scripts"
cp "$linter" "$empty/scripts/check-skill-references.sh"
chmod +x "$empty/scripts/check-skill-references.sh"
out="$("$empty/scripts/check-skill-references.sh" 2>&1)"
status=$?
if [ "$status" -ne 0 ] && printf '%s' "$out" | grep -q 'discovery walk is broken'; then
  ok "empty ground truth fails loudly instead of passing vacuously"
else
  bad "empty ground truth" "expected exit!=0 naming a broken walk, got $status: $out"
fi
rm -rf "$empty"

# --- cwd independence (the silent no-scan class of #2219/#2290) -------------
printf 'See `demo-plugin:no-such-skill`.\n' \
  >"$fixture/demo-plugin/skills/real-skill/REFERENCE.md"
out="$(cd / && "$fixture/scripts/check-skill-references.sh" 2>&1)"
status=$?
rm -f "$fixture/demo-plugin/skills/real-skill/REFERENCE.md"
if [ "$status" -ne 0 ]; then
  ok "scans correctly when invoked from an unrelated cwd"
else
  bad "cwd independence" "linter found nothing when run from /: $out"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
