#!/usr/bin/env bash
# shellcheck disable=SC2015  # test idiom: `cond && pass || fail` — `pass` returns 0
set -uo pipefail

# Regression test for plugin-compliance-check.sh check_skill_when_to_use().
#
# Issue #2141, step 1. The `## When to Use This Skill` section was REQUIRED by
# .claude/rules/skill-quality.md and enforced here as a hard ❌ ERROR (exit 1).
# That mandate was demoted on 2026-07-26 by .claude/rules/context-engineering.md
# ("recommended where it disambiguates sibling skills"), leaving the rule and
# the guard in direct contradiction: a skill that correctly followed the new
# rule failed the lint.
#
# THE SEMANTIC INVARIANT UNDER TEST (per .claude/rules/regression-testing.md):
# a SKILL.md with no When-to-Use section must yield a ⚠️ RECOMMENDATION and
# **exit 0** — not a ❌ issue and not a non-zero exit. Asserting only that some
# warning string appears would be a syntactic gate: the pre-fix script also
# printed a line mentioning the heading (as a ❌), and it is the EXIT CODE that
# blocks a developer's commit. Both halves are asserted.
#
# Why a sandbox repo root: plugin-compliance-check.sh `cd`s to
# "$(dirname "$0")/.." and resolves .claude-plugin/marketplace.json,
# release-please-config.json, and .release-please-manifest.json relative to it.
# Running the real script against a /tmp fixture therefore ALWAYS exits 1 on
# "No entry in marketplace.json" et al., which would make an exit-0 assertion
# impossible. So the test copies the script (and its one dependency,
# scripts/audit-skill-descriptions.py) into a throwaway root that carries
# matching metadata — the same "execute a copy of the real script" shape as
# scripts/tests/test-audit-skill-descriptions-dedup.sh.

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

tmp="$(mktemp -d)"
[ -n "$tmp" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
assert_contains() {
  # assert_contains <description> <haystack> <needle>
  if grep -qF "$3" <<<"$2"; then
    echo "  PASS: $1"
    pass=$((pass + 1))
  else
    echo "  FAIL: $1"
    echo "    expected to find: $3"
    fail=$((fail + 1))
  fi
}
assert_absent() {
  # assert_absent <description> <haystack> <needle>
  if grep -qF "$3" <<<"$2"; then
    echo "  FAIL: $1"
    echo "    expected NOT to find: $3"
    fail=$((fail + 1))
  else
    echo "  PASS: $1"
    pass=$((pass + 1))
  fi
}
assert_eq() {
  # assert_eq <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    echo "  PASS: $1"
    pass=$((pass + 1))
  else
    echo "  FAIL: $1"
    echo "    expected: $3"
    echo "    actual:   $2"
    fail=$((fail + 1))
  fi
}

# ---------------------------------------------------------------- sandbox root
root="$tmp/root"
mkdir -p "$root/scripts" "$root/.claude-plugin"
cp "$REPO_ROOT/scripts/plugin-compliance-check.sh" "$root/scripts/"
cp "$REPO_ROOT/scripts/audit-skill-descriptions.py" "$root/scripts/"

PLUGIN="fixture-plugin"
cat > "$root/.claude-plugin/marketplace.json" <<JSON
{
  "name": "fixture-marketplace",
  "plugins": [
    {
      "name": "${PLUGIN}",
      "source": "./${PLUGIN}",
      "description": "Fixture plugin for the compliance-check self-test.",
      "version": "1.0.0"
    }
  ]
}
JSON
cat > "$root/release-please-config.json" <<JSON
{
  "packages": {
    "${PLUGIN}": {
      "component": "${PLUGIN}",
      "release-type": "simple"
    }
  }
}
JSON
printf '{\n  "%s": "1.0.0"\n}\n' "$PLUGIN" > "$root/.release-please-manifest.json"

mkdir -p "$root/$PLUGIN/.claude-plugin"
cat > "$root/$PLUGIN/.claude-plugin/plugin.json" <<JSON
{
  "name": "${PLUGIN}",
  "version": "1.0.0",
  "description": "Fixture plugin for the compliance-check self-test."
}
JSON
printf '# %s\n\nFixture.\n' "$PLUGIN" > "$root/$PLUGIN/README.md"

# make_skill <name> <with|without>  — the ONLY difference is the When-to-Use section.
make_skill() {
  local dir="$root/$PLUGIN/skills/$1"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$1"
    printf 'description: Fixture skill %s. Use when exercising the compliance self-test.\n' "$1"
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-07-28\n'
    printf 'modified: 2026-07-28\n'
    printf 'reviewed: 2026-07-28\n'
    printf -- '---\n\n'
    printf '# Fixture %s\n\n' "$1"
    if [ "$2" = "with" ]; then
      printf '## When to Use This Skill\n\n'
      printf '| Use this skill when... | Use another skill when... |\n'
      printf '|---|---|\n'
      printf '| Exercising the fixture | Doing anything real |\n\n'
    fi
    printf 'Body text for the fixture skill.\n'
  } > "$dir/SKILL.md"
}

# run_check → writes the run's stdout+stderr to $OUT and its exit code to $RC.
# Not a command substitution: `RC=$?` inside `$( … )` would be set in the
# subshell and lost, which is exactly how an exit-code assertion silently
# degrades into asserting nothing.
run_check() {
  ( cd "$root" && bash scripts/plugin-compliance-check.sh "$PLUGIN" ) > "$tmp/run.out" 2>&1
  RC=$?
  OUT="$(cat "$tmp/run.out")"
}

echo "test-plugin-compliance-check:"

# --- Guard integrity A: the sandbox itself is clean --------------------------
# If a fixture WITH the section did not already exit 0, the exit-0 assertion in
# case B would prove nothing about the When-to-Use change — it could be passing
# for an unrelated reason, or failing for one. This pins the baseline.
make_skill haswhen with
run_check; out_with="$OUT"; rc_with="$RC"
assert_eq "baseline: fixture WITH the section exits 0" "$rc_with" "0"
assert_absent "baseline: no ❌ issues in the sandbox" "$out_with" "❌"

# --- The regression: no section → ⚠️ recommendation, exit 0 (#2141) ----------
rm -rf "${root:?}/$PLUGIN/skills/haswhen"
make_skill nowhen without
run_check; out_without="$OUT"; rc_without="$RC"

assert_eq "missing section exits 0 (advisory, not blocking)" "$rc_without" "0"
assert_contains "missing section is reported under Recommendations" \
  "$out_without" "### Recommendations"
assert_contains "missing section emits a ⚠️ line naming the skill" \
  "$out_without" "⚠️ ${PLUGIN}/nowhen: SKILL.md has no '## When to Use This Skill' section"
assert_absent "missing section does NOT emit a ❌ issue" "$out_without" "❌"
assert_absent "missing section does NOT open an Issues Found block" \
  "$out_without" "### Issues Found"
# The compliance table's When-to-Use column must degrade to ⚠️, not ❌.
assert_contains "When-to-Use column reports ⚠️ for the plugin" \
  "$out_without" "| ${PLUGIN} |"
assert_absent "plugin overall verdict is not ❌" "$out_without" "| ❌ |"

# --- Guard integrity B: the check still SEES the section --------------------
# Without this, the change could have degraded into a no-op (e.g. the check
# stopped running, or was wired out of the main loop) and every assertion above
# would still pass. A heading with no following table must still be flagged —
# advisory now, but flagged.
make_skill_heading_no_table() {
  local dir="$root/$PLUGIN/skills/$1"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$1"
    printf 'description: Fixture skill %s. Use when exercising the compliance self-test.\n' "$1"
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-07-28\n'
    printf 'modified: 2026-07-28\n'
    printf 'reviewed: 2026-07-28\n'
    printf -- '---\n\n'
    printf '# Fixture %s\n\n' "$1"
    printf '## When to Use This Skill\n\n'
    printf 'Prose instead of the expected markdown table.\n\n'
    printf 'More prose, still no table.\n\n'
    printf 'Yet more prose.\n\n'
    printf 'Still nothing.\n\n'
    printf 'Nothing here either.\n\n'
    printf 'Or here.\n'
  } > "$dir/SKILL.md"
}
rm -rf "${root:?}/$PLUGIN/skills/nowhen"
make_skill_heading_no_table headingonly
run_check; out_heading="$OUT"; rc_heading="$RC"

assert_eq "heading without a table exits 0 (also advisory)" "$rc_heading" "0"
assert_contains "heading without a table is still detected" \
  "$out_heading" "is not followed by a markdown table within 10 lines"
assert_absent "heading without a table does NOT emit a ❌ issue" "$out_heading" "❌"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
