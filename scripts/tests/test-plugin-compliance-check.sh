#!/usr/bin/env bash
# shellcheck disable=SC2015  # test idiom: `cond && pass || fail` — `pass` returns 0
# shellcheck disable=SC2016  # fixture SKILL.md bodies are literal text: ``` and ${...} must not expand
# shellcheck disable=SC2034  # some cases capture rc_* alongside out_* but assert on output only
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

# The license/author fields every manifest and marketplace entry must carry
# (#2698/#2699). The writers below take the metadata as a JSON fragment so the
# license-gate cases at the end can drop or corrupt one field on one surface
# while everything else stays byte-identical to the clean fixture.
CLEAN_META=',
  "author": {"name": "Fixture Author"},
  "license": "MIT"'

# write_marketplace <entry-meta-fragment>
write_marketplace() {
  cat > "$root/.claude-plugin/marketplace.json" <<JSON
{
  "name": "fixture-marketplace",
  "plugins": [
    {
      "name": "${PLUGIN}",
      "source": "./${PLUGIN}",
      "description": "Fixture plugin for the compliance-check self-test.",
      "version": "1.0.0"$1
    }
  ]
}
JSON
}
write_marketplace "$CLEAN_META"
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
# write_manifest <manifest-meta-fragment>
write_manifest() {
  cat > "$root/$PLUGIN/.claude-plugin/plugin.json" <<JSON
{
  "name": "${PLUGIN}",
  "version": "1.0.0",
  "description": "Fixture plugin for the compliance-check self-test."$1
}
JSON
}
write_manifest "$CLEAN_META"
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

# ============================================================================
# session-end / session-wrap: GITHUB_DRIFT requires --with-dedup (issue #2357)
#
# session-survey.sh only populates its GITHUB_DRIFT section when invoked with
# --with-dedup — omitted, the section is always empty and any dedup guard that
# reads it (redundant-tracker test, taskwarrior-sync) silently runs against
# nothing. The regression guard must be SEMANTIC: it asserts --with-dedup is on
# the actual session-survey.sh invocation LINE, not merely that the substring
# "--with-dedup" appears anywhere in the file (which a body could satisfy with
# explanatory prose while the real command stays broken).
#
# The fixture is named literally "session-wrap" because check_skill_body()
# keys this rule off the skill directory's basename. It also carries the other
# session-wrap-scoped tokens (+upstream / workflow-verify-before-filing / "is
# its own tracker" / "annotate the existing task") so those UNRELATED checks
# stay green and every ❌ assertion below is attributable to this rule alone.
# ============================================================================

make_session_wrap_fixture() {
  # make_session_wrap_fixture <survey-invocation-line> <extra-body-line>
  local invocation="$1"
  local extra="${2:-}"
  local dir="$root/$PLUGIN/skills/session-wrap"
  rm -rf "$dir"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: session-wrap\n'
    printf 'description: Fixture session-wrap. Use when exercising the compliance self-test.\n'
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-08-11\n'
    printf 'modified: 2026-08-11\n'
    printf 'reviewed: 2026-08-11\n'
    printf -- '---\n\n'
    printf '# Fixture session-wrap\n\n'
    printf '## When to Use This Skill\n\n'
    printf '| Use this skill when... | Use another skill when... |\n'
    printf '|---|---|\n'
    printf '| Exercising the fixture | Doing anything real |\n\n'
    printf '## Execution\n\n'
    printf 'Run the shared collector:\n\n'
    printf '```sh\n%s\n```\n\n' "$invocation"
    printf 'The GITHUB_DRIFT section is what the redundant-tracker test\n'
    printf 'below reads: an open PR or assigned issue is its own tracker,\n'
    printf 'so annotate the existing task instead of adding a duplicate.\n'
    printf 'Track an upstream candidate with +upstream, or route it through\n'
    printf 'workflow-verify-before-filing before filing anything.\n\n'
    if [ -n "$extra" ]; then
      printf '%s\n' "$extra"
    fi
  } > "$dir/SKILL.md"
}

# --- The regression: GITHUB_DRIFT referenced, invocation missing --with-dedup
make_session_wrap_fixture \
  'bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits'
run_check; out_missing="$OUT"; rc_missing="$RC"

assert_contains "missing --with-dedup on the invocation line is flagged ❌" \
  "$out_missing" "SKILL.md references GITHUB_DRIFT but at least one session-survey.sh invocation line is missing --with-dedup"
assert_contains "missing --with-dedup names the issue (#2357)" "$out_missing" "#2357"

# --- Guard integrity: the string alone (prose, not on the command line) must
# NOT satisfy the check — proves this is a semantic pairing, not a bare grep.
make_session_wrap_fixture \
  'bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits' \
  'Note: pass --with-dedup to populate GITHUB_DRIFT.'
run_check; out_prose_only="$OUT"; rc_prose_only="$RC"

assert_contains "--with-dedup) in prose alone still flags the invocation line" \
  "$out_prose_only" "SKILL.md references GITHUB_DRIFT but at least one session-survey.sh invocation line is missing --with-dedup"

# --- The fix: --with-dedup on the actual invocation line clears the finding
make_session_wrap_fixture \
  'bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-dedup'
run_check; out_fixed="$OUT"; rc_fixed="$RC"

assert_absent "with --with-dedup on the invocation line, no #2357 finding" \
  "$out_fixed" "missing --with-dedup"
assert_eq "with --with-dedup, session-wrap fixture exits 0" "$rc_fixed" "0"

rm -rf "${root:?}/$PLUGIN/skills/session-wrap"


# --------------------------------------------------------------------------
# Regression test for the session-end blueprint auto-drain gate (issue #2358).
#
# The jq gate that auto-confirms the Blueprint tracker-sync pass must require
# ALL THREE of autonomy_level >= 1, task_registry[...].enabled == true, and
# task_registry[...].auto_run == true — not just the first and third. A task
# the owner disabled (`enabled: false`) must never auto-run unattended just
# because `auto_run: true` and `autonomy_level >= 1`.
#
# THE SEMANTIC INVARIANT UNDER TEST: the two-field form (autonomy_level +
# auto_run, missing the enabled check) must be REJECTED (❌, exit 1), and the
# three-field form must PASS clean. A syntactic pin on "the string 'enabled'
# appears somewhere in the body" would be insufficient — prose that merely
# mentions "enabled" without wiring it into the actual jq filter must still
# fail, so the fixture below carries prose naming "enabled" beside a gate line
# that omits the check from the filter itself.
make_session_end_skill() {
  local gate_line="$1"
  local dir="$root/$PLUGIN/skills/session-end"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: session-end\n'
    printf 'description: Fixture session-end. Use when exercising the compliance self-test.\n'
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-08-11\n'
    printf 'modified: 2026-08-11\n'
    printf 'reviewed: 2026-08-11\n'
    printf -- '---\n\n'
    printf '# session-end\n\n'
    printf 'Blueprint tracker-sync qualifies when UNDRAINED_COUNT >= 1 and delegates\n'
    printf 'via --drain-wave. The gate checks the manifest'"'"'s enabled field.\n\n'
    printf 'Upstream candidates always route through workflow-verify-before-filing.\n\n'
    printf '```sh\n%s\n```\n' "$gate_line"
  } > "$dir/SKILL.md"
}

# --- The regression: old two-field form (no enabled check) must FAIL --------
rm -rf "${root:?}/$PLUGIN/skills/headingonly"
make_session_end_skill 'jq -r '"'"'if ((.automation.autonomy_level // 0) >= 1) and (.task_registry["feature-tracker-sync"].auto_run == true) then "auto" else "ask" end'"'"' docs/blueprint/manifest.json 2>/dev/null'
run_check; out_twofield="$OUT"; rc_twofield="$RC"

assert_eq "old two-field gate (no enabled check) exits 1" "$rc_twofield" "1"
assert_contains "old two-field gate is flagged by name" \
  "$out_twofield" "session-end: the blueprint auto-drain jq gate must pin task_registry[...].enabled == true"

# --- Guard integrity: the correct three-field form must PASS clean ---------
rm -rf "${root:?}/$PLUGIN/skills/session-end"
make_session_end_skill 'jq -r '"'"'if ((.automation.autonomy_level // 0) >= 1) and (.task_registry["feature-tracker-sync"].enabled == true) and (.task_registry["feature-tracker-sync"].auto_run == true) then "auto" else "ask" end'"'"' docs/blueprint/manifest.json 2>/dev/null'
run_check; out_threefield="$OUT"; rc_threefield="$RC"

assert_eq "three-field gate exits 0" "$rc_threefield" "0"
assert_absent "three-field gate raises no auto-drain gate issue" \
  "$out_threefield" "blueprint auto-drain jq gate"

# ---------------------------------------------------------------------------
# #2699: license/author metadata gate (and the #2698 data it keeps fixed).
#
# THE SEMANTIC INVARIANT UNDER TEST: a plugin.json or marketplace.json entry
# with no `license`, a `license` outside the allowlist ["MIT"], or no
# `author.name` is a BLOCKING ❌ issue (exit 1) — never a ⚠️ recommendation,
# because a recommendation exits 0 and gates nothing. The `--license-only`
# mode is what CI runs as the gate: it must emit the structured === LICENSE ===
# block and carry the verdict in its exit code. Before the gate existed, every
# case below exited 0 with no license finding at all.
# ---------------------------------------------------------------------------

# run_license_check → same contract as run_check, for the CI invocation shape:
# `--license-only` with NO plugin args, so auto-detection is exercised too.
run_license_check() {
  ( cd "$root" && bash scripts/plugin-compliance-check.sh --license-only ) > "$tmp/run.out" 2>&1
  RC=$?
  OUT="$(cat "$tmp/run.out")"
}

# count_lines <haystack> <ERE> → number of matching lines (0 when none).
count_lines() { grep -cE "$2" <<<"$1" || true; }

NO_LICENSE_META=',
  "author": {"name": "Fixture Author"}'
NO_AUTHOR_META=',
  "license": "MIT"'
APACHE_META=',
  "author": {"name": "Fixture Author"},
  "license": "Apache-2.0"'
STRING_AUTHOR_META=',
  "author": "Fixture Author",
  "license": "MIT"'

# --- Guard integrity: the clean fixture passes the gate in both modes -------
write_manifest "$CLEAN_META"; write_marketplace "$CLEAN_META"
run_check; out_lic_clean="$OUT"; rc_lic_clean="$RC"
assert_eq "license: clean fixture exits 0 (full run)" "$rc_lic_clean" "0"
assert_absent "license: clean fixture raises no ❌" "$out_lic_clean" "❌"
run_license_check; out_lo_clean="$OUT"; rc_lo_clean="$RC"
assert_eq "license-only: clean fixture exits 0" "$rc_lo_clean" "0"
assert_contains "license-only: opens the LICENSE section" "$out_lo_clean" "=== LICENSE ==="
assert_contains "license-only: closes the LICENSE section" "$out_lo_clean" "=== END LICENSE ==="
assert_contains "license-only: auto-detected and checked the one manifest" "$out_lo_clean" "MANIFESTS_CHECKED=1"
assert_contains "license-only: checked the one marketplace entry" "$out_lo_clean" "ENTRIES_CHECKED=1"
assert_contains "license-only: clean STATUS=OK" "$out_lo_clean" "STATUS=OK"
assert_contains "license-only: clean ISSUE_COUNT=0" "$out_lo_clean" "ISSUE_COUNT=0"
assert_absent "license-only: skips the per-skill checks (no compliance table)" "$out_lo_clean" "## Plugin Compliance Review"

# --- (a) plugin.json without `license` → ❌ issue, not ⚠️ recommendation ----
write_manifest "$NO_LICENSE_META"
run_check; out_a="$OUT"; rc_a="$RC"
assert_eq "manifest without license exits 1 (blocking)" "$rc_a" "1"
assert_contains "manifest without license is a ❌ issue" \
  "$out_a" "❌ ${PLUGIN}: plugin.json missing 'license' (allowed: MIT)"
assert_eq "manifest without license is NOT a ⚠️ recommendation" \
  "$(count_lines "$out_a" '⚠️.*license')" "0"
assert_contains "plugin.json column reports ❌" "$out_a" "| ${PLUGIN} | ❌ |"
run_license_check; out_a_lo="$OUT"; rc_a_lo="$RC"
assert_eq "license-only: manifest without license exits 1" "$rc_a_lo" "1"
assert_contains "license-only: MISSING_LICENSE=1" "$out_a_lo" "MISSING_LICENSE=1"
assert_contains "license-only: STATUS=ERROR" "$out_a_lo" "STATUS=ERROR"
assert_contains "license-only: names the defect row" \
  "$out_a_lo" "SEVERITY=ERROR TYPE=missing_license SURFACE=plugin.json PLUGIN=${PLUGIN}"

# --- (b) a license outside the allowlist → ❌ not in allowlist --------------
write_manifest "$APACHE_META"
run_check; out_b="$OUT"; rc_b="$RC"
assert_eq "Apache-2.0 manifest exits 1" "$rc_b" "1"
assert_contains "Apache-2.0 manifest is a ❌ allowlist issue" \
  "$out_b" "❌ ${PLUGIN}: plugin.json license 'Apache-2.0' not in allowlist [MIT]"
run_license_check; out_b_lo="$OUT"
assert_contains "license-only: DISALLOWED_LICENSE=1" "$out_b_lo" "DISALLOWED_LICENSE=1"
assert_contains "license-only: allowlist is stated" "$out_b_lo" "ALLOWED_LICENSES=MIT"

# --- (a') plugin.json without author, and author as a bare string ----------
write_manifest "$NO_AUTHOR_META"
run_check; out_c="$OUT"; rc_c="$RC"
assert_eq "manifest without author exits 1" "$rc_c" "1"
assert_contains "manifest without author is a ❌ issue" \
  "$out_c" "❌ ${PLUGIN}: plugin.json missing 'author.name'"
write_manifest "$STRING_AUTHOR_META"
run_license_check; out_c_lo="$OUT"; rc_c_lo="$RC"
assert_eq "license-only: string author (schema wants an object) exits 1" "$rc_c_lo" "1"
assert_contains "license-only: string author counts as MISSING_AUTHOR=1" "$out_c_lo" "MISSING_AUTHOR=1"
write_manifest "$CLEAN_META"

# --- (c) marketplace entry without author / without license → ❌ ----------
write_marketplace "$NO_AUTHOR_META"
run_check; out_d="$OUT"; rc_d="$RC"
assert_eq "entry without author exits 1" "$rc_d" "1"
assert_contains "entry without author is a ❌ issue" \
  "$out_d" "❌ ${PLUGIN}: marketplace.json entry missing 'author.name'"
run_license_check; out_d_lo="$OUT"
assert_contains "license-only: entry without author → MISSING_AUTHOR=1" "$out_d_lo" "MISSING_AUTHOR=1"
assert_contains "license-only: names the entry surface" \
  "$out_d_lo" "TYPE=missing_author SURFACE=marketplace.json PLUGIN=${PLUGIN}"

write_marketplace "$NO_LICENSE_META"
run_check; out_e="$OUT"; rc_e="$RC"
assert_eq "entry without license exits 1" "$rc_e" "1"
assert_contains "entry without license is a ❌ issue" \
  "$out_e" "❌ ${PLUGIN}: marketplace.json entry missing 'license' (allowed: MIT)"
run_license_check; out_e_lo="$OUT"; rc_e_lo="$RC"
assert_eq "license-only: entry without license exits 1" "$rc_e_lo" "1"
assert_contains "license-only: entry without license → MISSING_LICENSE=1" "$out_e_lo" "MISSING_LICENSE=1"

# --- (d) restoring the clean fixture returns both modes to green ------------
write_marketplace "$CLEAN_META"
run_check; rc_f="$RC"
assert_eq "restored fixture exits 0 (full run)" "$rc_f" "0"
run_license_check; rc_f_lo="$RC"
assert_eq "restored fixture exits 0 (license-only)" "$rc_f_lo" "0"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
