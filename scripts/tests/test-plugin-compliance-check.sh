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
# The configure-pre-commit default_stages check (#2824) parses fences with the
# shared markdown helper, resolved relative to the repo root the script cd's to.
mkdir -p "$root/scripts/lib"
cp "$REPO_ROOT/scripts/lib/extract-md-elements.py" "$root/scripts/lib/"

PLUGIN="fixture-plugin"

# The license/author/repository fields every manifest and marketplace entry
# must carry (#2698/#2699/#2772). The writers below take the metadata as a JSON
# fragment so the license-gate cases at the end can drop or corrupt one field on
# one surface while everything else stays byte-identical to the clean fixture.
CLEAN_META=',
  "author": {"name": "Fixture Author"},
  "repository": "https://github.com/example/fixture-marketplace",
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
    printf 'workflow-verify-before-filing before filing anything.\n'
    printf 'Under --orchestrated, list outward items as DEFERRED: lines.\n\n'
    if [ -n "$extra" ]; then
      printf '%s\n' "$extra"
    fi
  } > "$dir/SKILL.md"
}

# --- The regression: GITHUB_DRIFT referenced, invocation missing --with-dedup
make_session_wrap_fixture \
  'bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits'
run_check; out_missing="$OUT"

assert_contains "missing --with-dedup on the invocation line is flagged ❌" \
  "$out_missing" "SKILL.md references GITHUB_DRIFT but at least one session-survey.sh invocation line is missing --with-dedup"
assert_contains "missing --with-dedup names the issue (#2357)" "$out_missing" "#2357"

# --- Guard integrity: the string alone (prose, not on the command line) must
# NOT satisfy the check — proves this is a semantic pairing, not a bare grep.
make_session_wrap_fixture \
  'bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits' \
  'Note: pass --with-dedup to populate GITHUB_DRIFT.'
run_check; out_prose_only="$OUT"

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
  # make_session_end_skill <gate-line> [lanes-body]  — lanes-body defaults to
  # the compliant Act-before-Ask shape so the #2358 cases test only the gate.
  local gate_line="$1"
  local lanes="${2-$SESSION_END_LANES_OK}"
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
    printf '```sh\n%s\n```\n\n' "$gate_line"
    printf '%s\n' "$lanes"
  } > "$dir/SKILL.md"
}

SESSION_END_LANES_OK='| Taskwarrior sync | at least one session-linked task |

#### Backlog is reported, never walked

### Step 3: Run the Act lane now

Run `session-plugin:session-wrap` with `--orchestrated`, then
`session-plugin:session-distill` with `--orchestrated`, then
`feedback-plugin:feedback-session --confirmed "<findings>"`.

### Step 4: One question for the Ask lane

Ask once for the DEFERRED: lines.'

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

# --------------------------------------------------------------------------
# session-end: reversible work first, one question last, no backlog walk.
#
# THE SEMANTIC INVARIANT UNDER TEST: the Act lane (Step 3) precedes the single
# Ask-lane question (Step 4); the taskwarrior pass qualifies on a
# session-linked task, never on an OPEN_TASKS count. The compliant shape is
# the three-field case above (exit 0); each mutation below must exit 1 and be
# named.
GATE3='jq -r '"'"'if ((.automation.autonomy_level // 0) >= 1) and (.task_registry["feature-tracker-sync"].enabled == true) and (.task_registry["feature-tracker-sync"].auto_run == true) then "auto" else "ask" end'"'"' docs/blueprint/manifest.json 2>/dev/null'

# --- Ask before Act (the old preview-then-confirm order) must FAIL ----------
rm -rf "${root:?}/$PLUGIN/skills/session-end"
make_session_end_skill "$GATE3" "${SESSION_END_LANES_OK/\#\#\# Step 3: Run the Act lane now/### Step 5: Run the Act lane now}"
run_check; out_order="$OUT"; rc_order="$RC"
assert_eq "session-end: Ask before Act exits 1" "$rc_order" "1"
assert_contains "session-end: Ask before Act is named" \
  "$out_order" "must run the Act lane (Step 3) before the single Ask-lane question (Step 4)"

# --- Backlog-count qualifier (the old OPEN_TASKS row) must FAIL --------------
rm -rf "${root:?}/$PLUGIN/skills/session-end"
make_session_end_skill "$GATE3" "${SESSION_END_LANES_OK/at least one session-linked task/\`OPEN_TASKS\` ≥ 1}"
run_check; out_backlog="$OUT"; rc_backlog="$RC"
assert_eq "session-end: OPEN_TASKS qualifier exits 1" "$rc_backlog" "1"
assert_contains "session-end: OPEN_TASKS qualifier is named" \
  "$out_backlog" "must require a session-linked task, not an OPEN_TASKS count"

# --- Dropping --orchestrated from the wrap hand-off must FAIL ----------------
rm -rf "${root:?}/$PLUGIN/skills/session-end"
make_session_end_skill "$GATE3" "${SESSION_END_LANES_OK/session-wrap\` with \`--orchestrated/session-wrap\`}"
run_check; out_orch="$OUT"; rc_orch="$RC"
assert_eq "session-end: wrap hand-off without --orchestrated exits 1" "$rc_orch" "1"
assert_contains "session-end: missing wrap --orchestrated is named" \
  "$out_orch" "single-question contract with the sub-skills"
# --- Feedback moved back behind the question (Step 4) must FAIL -----------
rm -rf "${root:?}/$PLUGIN/skills/session-end"
fb_line='`feedback-plugin:feedback-session --confirmed "<findings>"`.'
lanes_fb_late="${SESSION_END_LANES_OK/, then
$fb_line/.}
Then run $fb_line"
make_session_end_skill "$GATE3" "$lanes_fb_late"
run_check; out_fb="$OUT"; rc_fb="$RC"
assert_eq "session-end: feedback behind the question exits 1" "$rc_fb" "1"
assert_contains "session-end: feedback behind the question is named" \
  "$out_fb" "feedback-session --confirmed must run in Step 3 (Act lane)"
rm -rf "${root:?}/$PLUGIN/skills/session-end"
make_session_end_skill "$GATE3"

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

FIXTURE_REPO='"repository": "https://github.com/example/fixture-marketplace"'
NO_LICENSE_META=',
  "author": {"name": "Fixture Author"},
  '"$FIXTURE_REPO"
NO_AUTHOR_META=',
  '"$FIXTURE_REPO"',
  "license": "MIT"'
APACHE_META=',
  "author": {"name": "Fixture Author"},
  '"$FIXTURE_REPO"',
  "license": "Apache-2.0"'
STRING_AUTHOR_META=',
  "author": "Fixture Author",
  '"$FIXTURE_REPO"',
  "license": "MIT"'
# #2772: `repository` is required on both surfaces; `homepage` is deliberately
# not (Lauri, 2026-11-01: option 2). A non-string repository counts as missing.
NO_REPOSITORY_META=',
  "author": {"name": "Fixture Author"},
  "license": "MIT"'
OBJECT_REPOSITORY_META=',
  "author": {"name": "Fixture Author"},
  "repository": {"url": "https://github.com/example/fixture-marketplace"},
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
write_marketplace "$CLEAN_META"

# --- (e) #2772: plugin.json / entry without `repository` → ❌ ---------------
write_manifest "$NO_REPOSITORY_META"
run_check; out_g="$OUT"; rc_g="$RC"
assert_eq "manifest without repository exits 1" "$rc_g" "1"
assert_contains "manifest without repository is a ❌ issue" \
  "$out_g" "❌ ${PLUGIN}: plugin.json missing 'repository'"
run_license_check; out_g_lo="$OUT"; rc_g_lo="$RC"
assert_eq "license-only: manifest without repository exits 1" "$rc_g_lo" "1"
assert_contains "license-only: MISSING_REPOSITORY=1" "$out_g_lo" "MISSING_REPOSITORY=1"
assert_contains "license-only: names the repository defect row" \
  "$out_g_lo" "SEVERITY=ERROR TYPE=missing_repository SURFACE=plugin.json PLUGIN=${PLUGIN}"
write_manifest "$OBJECT_REPOSITORY_META"
run_license_check; out_g2_lo="$OUT"; rc_g2_lo="$RC"
assert_eq "license-only: object repository (schema wants a string) exits 1" "$rc_g2_lo" "1"
assert_contains "license-only: object repository counts as MISSING_REPOSITORY=1" "$out_g2_lo" "MISSING_REPOSITORY=1"
write_manifest "$CLEAN_META"

write_marketplace "$NO_REPOSITORY_META"
run_check; out_h="$OUT"; rc_h="$RC"
assert_eq "entry without repository exits 1" "$rc_h" "1"
assert_contains "entry without repository is a ❌ issue" \
  "$out_h" "❌ ${PLUGIN}: marketplace.json entry missing 'repository'"
run_license_check; out_h_lo="$OUT"
assert_contains "license-only: entry without repository names the entry surface" \
  "$out_h_lo" "TYPE=missing_repository SURFACE=marketplace.json PLUGIN=${PLUGIN}"

# --- (d) restoring the clean fixture returns both modes to green ------------
write_marketplace "$CLEAN_META"
run_check; rc_f="$RC"
assert_eq "restored fixture exits 0 (full run)" "$rc_f" "0"
run_license_check; rc_f_lo="$RC"
assert_eq "restored fixture exits 0 (license-only)" "$rc_f_lo" "0"

# ============================================================================
# references/ reachability (issue #2700)
#
# A skill split into references/ (.claude/rules/skill-quality.md §
# "references/ — a multi-file split for large skills") reaches its detail only
# through links from SKILL.md or the REFERENCE.md index. A reference file that
# no entry point names is never loaded at all, and nothing else checks that.
#
# THE SEMANTIC INVARIANT UNDER TEST:
#   reverse — every references/*.md is named from SKILL.md or REFERENCE.md.
# It is asserted on the ❌ line AND the exit code, and a clean split is pinned
# to exit 0 so the guard cannot pass by flagging everything.
#
# The forward direction (a link naming a references/ file that does not exist)
# moved to scripts/check-skill-xrefs.py in issue #2952, so a broken link is
# reported once. Its regression cases live in
# scripts/tests/test-check-skill-xrefs.sh; the cases here pin that this script
# no longer reports it.
# ============================================================================

make_refs_skill() {
  # make_refs_skill <body-line...>  — SKILL.md whose body is the given lines;
  # references/present.md and references/other.md always exist.
  local dir="$root/$PLUGIN/skills/refsplit"
  rm -rf "$dir"
  mkdir -p "$dir/references"
  printf '# present\n' > "$dir/references/present.md"
  printf '# other\n' > "$dir/references/other.md"
  {
    printf -- '---\n'
    printf 'name: refsplit\n'
    printf 'description: Fixture refsplit. Use when exercising the compliance self-test.\n'
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-09-23\n'
    printf 'modified: 2026-09-23\n'
    printf 'reviewed: 2026-09-23\n'
    printf -- '---\n\n'
    printf '# Fixture refsplit\n\n'
    printf '## When to Use This Skill\n\n'
    printf '| Use this skill when... | Use another skill when... |\n'
    printf '|---|---|\n'
    printf '| Exercising the fixture | Doing anything real |\n\n'
    local line
    for line in "$@"; do printf '%s\n' "$line"; done
  } > "$dir/SKILL.md"
}

# --- Guard integrity: a clean split (anchor link + plain link) exits 0 -------
rm -rf "${root:?}/$PLUGIN/skills/session-end"
make_refs_skill \
  'See [present](references/present.md#some-section) for one path.' \
  'See [other](references/other.md) for the other.'
run_check; out_refs_ok="$OUT"; rc_refs_ok="$RC"
assert_eq "clean references/ split exits 0" "$rc_refs_ok" "0"
assert_absent "clean references/ split raises no #2700 finding" "$out_refs_ok" "#2700"

# --- forward is owned by check-skill-xrefs.py (#2952): no duplicate report ---
make_refs_skill \
  'See [present](references/present.md) and [other](references/other.md).' \
  'See [gone](references/missing.md#step-3) for the moved step.'
run_check; out_refs_dead="$OUT"; rc_refs_dead="$RC"
assert_eq "dead references/ link in SKILL.md is not this script's finding (exits 0)" "$rc_refs_dead" "0"
assert_absent "dead references/ link in SKILL.md raises no #2700 line" \
  "$out_refs_dead" "#2700"

make_refs_skill 'See [present](references/present.md) and [other](references/other.md).'
printf -- '- [gone](references/index-only-missing.md)\n' > "$root/$PLUGIN/skills/refsplit/REFERENCE.md"
run_check; out_refs_dead_idx="$OUT"; rc_refs_dead_idx="$RC"
assert_eq "dead references/ link in REFERENCE.md is not this script's finding (exits 0)" "$rc_refs_dead_idx" "0"
assert_absent "dead references/ link in REFERENCE.md raises no #2700 line" \
  "$out_refs_dead_idx" "#2700"
assert_absent "dead references/ link in REFERENCE.md is not named by this script" \
  "$out_refs_dead_idx" "index-only-missing.md"

# --- reverse: a reference file nothing names is unreachable -----------------
make_refs_skill 'See [present](references/present.md) only.'
run_check; out_refs_orphan="$OUT"; rc_refs_orphan="$RC"
assert_eq "orphaned reference file exits 1" "$rc_refs_orphan" "1"
assert_contains "orphaned reference file is flagged ❌ by path" \
  "$out_refs_orphan" "❌ ${PLUGIN}/refsplit: references/other.md is named from neither SKILL.md nor REFERENCE.md"

# --- reverse: the thin REFERENCE.md index counts as an entry point ----------
make_refs_skill 'See [present](references/present.md) only.'
printf -- '| Path | File |\n|---|---|\n| other | [references/other.md](references/other.md) |\n' \
  > "$root/$PLUGIN/skills/refsplit/REFERENCE.md"
run_check; out_refs_index="$OUT"; rc_refs_index="$RC"
assert_eq "reference file named only from REFERENCE.md exits 0" "$rc_refs_index" "0"
assert_absent "reference file named only from REFERENCE.md is not flagged" \
  "$out_refs_index" "#2700"

rm -rf "${root:?}/$PLUGIN/skills/refsplit"

# ---------------------------------------------------------------------------
# PR #2771 / issue #2720: changelog-review Step 6 must not tell the CI triage
# run to write the version state file.
#
# THE SEMANTIC INVARIANT UNDER TEST: the pre-fix Step 6 (write the state file,
# no CI carve-out) is a ❌ issue and exit 1; the fixed Step 6 passes clean. The
# carve-out tokens placed in a DIFFERENT section must still fail, which proves
# the check reads the Step 6 slice rather than grepping the whole body.
make_changelog_review_skill() {
  # make_changelog_review_skill <step6-extra-line> <later-section-line>
  local dir="$root/$PLUGIN/skills/changelog-review"
  rm -rf "$dir"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: changelog-review\n'
    printf 'description: Fixture changelog-review. Use when exercising the compliance self-test.\n'
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-09-24\n'
    printf 'modified: 2026-09-24\n'
    printf 'reviewed: 2026-09-24\n'
    printf -- '---\n\n'
    printf '# Fixture changelog-review\n\n'
    printf '### Step 6: Update Version Tracking\n\n'
    printf 'Update `.claude-code-version-check.json` with the new version.\n\n'
    [ -n "$1" ] && printf '%s\n\n' "$1"
    printf '## Automation Integration\n\n'
    [ -n "$2" ] && printf '%s\n' "$2"
    printf 'Body text.\n'
  } > "$dir/SKILL.md"
}

FIXED_STEP6='In the CI triage run the workflow owns the state file; write the entry to `triage-entry.json` instead.'

# --- The regression: pre-fix Step 6 with no CI carve-out must FAIL ----------
make_changelog_review_skill '' ''
run_check; out_cr_prefix="$OUT"; rc_cr_prefix="$RC"
assert_eq "changelog-review: pre-fix Step 6 exits 1" "$rc_cr_prefix" "1"
assert_contains "changelog-review: pre-fix Step 6 flags the state-file owner token" \
  "$out_cr_prefix" "SKILL.md Step 6 must retain 'the workflow owns the state file'"
assert_contains "changelog-review: pre-fix Step 6 flags the triage-entry.json token" \
  "$out_cr_prefix" "SKILL.md Step 6 must retain 'triage-entry.json'"

# --- Guard integrity: carve-out outside Step 6 must still FAIL --------------
make_changelog_review_skill '' "$FIXED_STEP6"
run_check; out_cr_elsewhere="$OUT"; rc_cr_elsewhere="$RC"
assert_eq "changelog-review: carve-out outside Step 6 still exits 1" "$rc_cr_elsewhere" "1"
assert_contains "changelog-review: carve-out outside Step 6 is still flagged" \
  "$out_cr_elsewhere" "SKILL.md Step 6 must retain 'the workflow owns the state file'"

# --- The fix: carve-out inside Step 6 passes clean --------------------------
make_changelog_review_skill "$FIXED_STEP6" ''
run_check; out_cr_fixed="$OUT"; rc_cr_fixed="$RC"
assert_eq "changelog-review: fixed Step 6 exits 0" "$rc_cr_fixed" "0"
assert_absent "changelog-review: fixed Step 6 raises no Step 6 issue" \
  "$out_cr_fixed" "SKILL.md Step 6 must retain"

rm -rf "${root:?}/$PLUGIN/skills/changelog-review"

# --- check_skill_body DENYLIST checks read the skill's sidecars too ----------
# The 2026-10 split moved skill content into `references/*.md`. A "must NOT
# contain X" check that reads only SKILL.md stops seeing X the moment the split
# moves it, yet the agent still reads it there. The `task +LATEST _get uuid`
# ban applies to every skill, so it is the case exercised. The reference file is
# linked from SKILL.md so the #2700 orphan check stays quiet and the run's only
# possible ❌ is the one under test.
make_skill sidecarban with
printf '\nSee [usage](references/usage.md).\n' >> "$root/$PLUGIN/skills/sidecarban/SKILL.md"
mkdir -p "$root/$PLUGIN/skills/sidecarban/references"
printf '# Usage\n\nCapture it with `task +LATEST _get uuid`.\n' \
  > "$root/$PLUGIN/skills/sidecarban/references/usage.md"
run_check; out_sb="$OUT"; rc_sb="$RC"
assert_eq "denylist: a banned command in references/*.md exits 1" "$rc_sb" "1"
assert_contains "denylist: the banned command in a sidecar is named" \
  "$out_sb" "SKILL.md or a sidecar ships the broken 'task +LATEST _get uuid'"

# Guard integrity: the same sidecar quoting it in a blockquote is a gotcha
# callout, not a recommendation, and stays clean.
printf '# Usage\n\n> Not `task +LATEST _get uuid`, which returns empty.\n' \
  > "$root/$PLUGIN/skills/sidecarban/references/usage.md"
run_check; out_sbq="$OUT"; rc_sbq="$RC"
assert_eq "denylist: a blockquoted mention in a sidecar exits 0" "$rc_sbq" "0"
assert_absent "denylist: a blockquoted mention in a sidecar is not flagged" \
  "$out_sbq" "_get uuid"

rm -rf "${root:?}/$PLUGIN/skills/sidecarban"

# ============================================================================
# git-plugin scope-required pin covers git-pr (issue #2774)
#
# The pin in check_skill_body() keys off plugin == git-plugin AND the skill
# name, so the fixture plugin is renamed to git-plugin for this section and the
# sandbox metadata is rewritten to match. git-pr is one of the three names #2774
# added beside git-commit / github-pr-title; a body that shows the
# `type(scope)` template but never says the scope is required must FAIL, and the
# same body carrying the sentence must PASS clean.
# ============================================================================
write_plugin_metadata() {
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
  write_manifest "$CLEAN_META"
  printf '# %s\n\nFixture.\n' "$PLUGIN" > "$root/$PLUGIN/README.md"
}
PLUGIN_SAVED="$PLUGIN"
PLUGIN="git-plugin"
write_plugin_metadata

make_skill git-pr with
printf '\n## PR Title Format\n\n```\n<type>(<scope>): <subject>\n```\n' \
  >> "$root/$PLUGIN/skills/git-pr/SKILL.md"
run_check; out_scope_missing="$OUT"; rc_scope_missing="$RC"
assert_eq "scope pin: git-pr without the sentence exits 1" "$rc_scope_missing" "1"
assert_contains "scope pin: git-pr without the sentence is flagged ❌" \
  "$out_scope_missing" "❌ git-plugin/git-pr: SKILL.md must state 'The scope is required'"

printf '\n**The scope is required.** Write `type(scope): …`.\n' \
  >> "$root/$PLUGIN/skills/git-pr/SKILL.md"
run_check; out_scope_ok="$OUT"; rc_scope_ok="$RC"
assert_eq "scope pin: git-pr with the sentence exits 0" "$rc_scope_ok" "0"
assert_absent "scope pin: git-pr with the sentence raises no scope issue" \
  "$out_scope_ok" "must state 'The scope is required'"

rm -rf "${root:?}/git-plugin"
PLUGIN="$PLUGIN_SAVED"
write_plugin_metadata
# ---------------------------------------------------------------------------
# configure-* portfolio standards (#2757, #2745, #2824).
#
# check_skill_body() keys each rule off the skill directory's basename, so the
# fixtures carry the real skill names. Each rule gets a red fixture (the
# pre-fix shape), a green one (the fix), and a guard case that a shallow grep
# would get wrong.
# ---------------------------------------------------------------------------

# make_named_skill <name> <body> [reference-md]
make_named_skill() {
  local dir="$root/$PLUGIN/skills/$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$1"
    printf 'description: Fixture %s. Use when exercising the compliance self-test.\n' "$1"
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-10-09\n'
    printf 'modified: 2026-10-09\n'
    printf 'reviewed: 2026-10-09\n'
    printf -- '---\n\n'
    printf '# Fixture %s\n\n' "$1"
    printf '%s\n' "$2"
    [ -n "${3:-}" ] && printf '\nSee [REFERENCE.md](REFERENCE.md).\n'
  } > "$dir/SKILL.md"
  if [ -n "${3:-}" ]; then
    printf '%s\n' "$3" > "$dir/REFERENCE.md"
  fi
}

# --- (a) configure-release-please: @v5 is the standard (#2757) --------------
RP_TOKENS='Token: `create-github-app-token` reading `RELEASE_PLEASE_APP_ID`.
- A `0.0.0` entry with no release tag and no `initial-version` is a FAIL.
3. **Missing manifest**: Create with `0.0.0` and set `initial-version` in the config.'
RP_INITIAL='Set "initial-version": "0.1.0" before the first tag.'
RP_REF_V4='```yaml
steps:
  - uses: googleapis/release-please-action@v4
```'
RP_REF_V5='```yaml
steps:
  - uses: googleapis/release-please-action@v5
```
'"$RP_INITIAL"

make_named_skill configure-release-please "- Action version: \`googleapis/release-please-action@v4\`
$RP_TOKENS" "$RP_REF_V4"
run_check; out_rp4="$OUT"; rc_rp4="$RC"
assert_eq "release-please: a @v4 standard exits 1" "$rc_rp4" "1"
assert_contains "release-please: a missing @v5 standard is named" \
  "$out_rp4" "SKILL.md must name 'googleapis/release-please-action@v5'"
assert_contains "release-please: a @v4 ref is flagged" \
  "$out_rp4" "still sets release-please-action older than @v5"

# Guard: SKILL.md fixed but the sidecar template still on @v4 — the mixed state
# REFERENCE.md was in when #2757 was filed — must still fail.
make_named_skill configure-release-please "- Action version: \`googleapis/release-please-action@v5\`
$RP_TOKENS" "$RP_REF_V4"
run_check; out_rpmix="$OUT"; rc_rpmix="$RC"
assert_eq "release-please: a @v4 template left in REFERENCE.md exits 1" "$rc_rpmix" "1"
assert_contains "release-please: the sidecar @v4 template is flagged" \
  "$out_rpmix" "still sets release-please-action older than @v5"

make_named_skill configure-release-please "- Action version: \`googleapis/release-please-action@v5\`
$RP_TOKENS" "$RP_REF_V5"
run_check; out_rp5="$OUT"; rc_rp5="$RC"
assert_eq "release-please: the @v5 standard exits 0" "$rc_rp5" "0"
assert_absent "release-please: the @v5 standard raises no #2757 issue" "$out_rp5" "#2757"
assert_absent "release-please: the fixed manifest bootstrap raises no #3301 issue" "$out_rp5" "#3301"

# (a2) #3301: the pre-fix manifest bootstrap — `0.0.0` with no initial-version,
# and the "placeholder" sentence in REFERENCE.md — must fail on every axis.
RP_SKILL_OLD="- Action version: \`googleapis/release-please-action@v5\`
Token: \`create-github-app-token\` reading \`RELEASE_PLEASE_APP_ID\`.
3. **Missing manifest**: Create with initial version \`0.0.0\`"
RP_REF_OLD='```yaml
steps:
  - uses: googleapis/release-please-action@v5
```
Version `0.0.0` is a placeholder — release-please updates it automatically.'
make_named_skill configure-release-please "$RP_SKILL_OLD" "$RP_REF_OLD"
run_check; out_rp0="$OUT"; rc_rp0="$RC"
assert_eq "release-please: a 0.0.0 bootstrap without initial-version exits 1" "$rc_rp0" "1"
assert_contains "release-please: the manifest fix without initial-version is named" \
  "$out_rp0" "'Missing manifest' fix must set 'initial-version'"
assert_contains "release-please: the missing untagged-0.0.0 audit is named" \
  "$out_rp0" "must flag a 0.0.0 manifest with no release tag"
assert_contains "release-please: the REFERENCE template without initial-version is named" \
  "$out_rp0" "REFERENCE.md manifest template must pair 0.0.0"
assert_contains "release-please: the placeholder sentence is flagged" \
  "$out_rp0" "calls the 0.0.0 manifest a harmless placeholder"

# Guard: initial-version named elsewhere in SKILL.md but not on the
# Missing-manifest line still fails — a shallow grep would pass it.
make_named_skill configure-release-please "$RP_SKILL_OLD
- A \`0.0.0\` entry with no release tag and no \`initial-version\` is a FAIL." "$RP_REF_V5"
run_check; out_rpg="$OUT"; rc_rpg="$RC"
assert_eq "release-please: initial-version off the Missing-manifest line exits 1" "$rc_rpg" "1"
assert_contains "release-please: the Missing-manifest line is still flagged" \
  "$out_rpg" "'Missing manifest' fix must set 'initial-version'"
rm -rf "${root:?}/$PLUGIN/skills/configure-release-please"

# --- (b) configure-workflows: Renovate is App-covered (#2745) ---------------
CW_TABLE_OLD='| Project Type | Required Workflows |
|--------------|-------------------|
| Frontend | container-build, release-please, renovate (optional: claude-auto-fix) |
| Infrastructure | release-please, renovate |'
CW_TABLE_NEW='| Project Type | Required Workflows |
|--------------|-------------------|
| Frontend | container-build, release-please (optional: claude-auto-fix) |
| Infrastructure | release-please |'
CW_COVERAGE='A repo the `laurigates-renovate` App covers with a per-repo runner: WARN: duplicate Renovate identity.'
CW_RP_V5='| Check | Standard | Severity |
|-------|----------|----------|
| Action version | v5 | WARN if older |'

make_named_skill configure-workflows "$CW_TABLE_OLD

| Check | Standard | Severity |
|-------|----------|----------|
| Action version | v4 | WARN if older |"
run_check; out_cwold="$OUT"; rc_cwold="$RC"
assert_eq "workflows: the pre-fix skill exits 1" "$rc_cwold" "1"
assert_contains "workflows: the missing App-coverage token is named" \
  "$out_cwold" "must retain the Renovate App-coverage token 'laurigates-renovate'"
assert_contains "workflows: the missing duplicate-identity verdict is named" \
  "$out_cwold" "must retain the Renovate App-coverage token 'duplicate Renovate identity'"
assert_contains "workflows: renovate as a required workflow is flagged" \
  "$out_cwold" "the Required Workflows table lists renovate unconditionally"
assert_contains "workflows: a v4 release-please row is flagged" \
  "$out_cwold" "Release Please Workflow Checks row must require action v5"

# Guard: the tokens alone do not clear the table finding — renovate still listed
# in the project-type rows must keep failing.
make_named_skill configure-workflows "$CW_TABLE_OLD

$CW_COVERAGE

$CW_RP_V5"
run_check; out_cwtok="$OUT"; rc_cwtok="$RC"
assert_eq "workflows: tokens with renovate still required exits 1" "$rc_cwtok" "1"
assert_contains "workflows: the table finding survives the tokens" \
  "$out_cwtok" "the Required Workflows table lists renovate unconditionally"

# Guard: renovate named OUTSIDE the table (the scoped-caller prose) is fine.
make_named_skill configure-workflows "$CW_TABLE_NEW

$CW_COVERAGE A renovate caller is only for orgs the App does not cover.

$CW_RP_V5"
run_check; out_cwnew="$OUT"; rc_cwnew="$RC"
assert_eq "workflows: the fixed skill exits 0" "$rc_cwnew" "0"
assert_absent "workflows: the fixed skill raises no #2745 issue" "$out_cwnew" "#2745"
assert_absent "workflows: the fixed skill raises no #2757 issue" "$out_cwnew" "#2757"
rm -rf "${root:?}/$PLUGIN/skills/configure-workflows"

# --- (c) configure-pre-commit: default_stages beside commit-msg (#2824) -----
PC_BLOCK_NO_STAGES='```yaml
default_install_hook_types:
  - pre-commit
  - commit-msg

repos: []
```'
PC_INLINE_NO_STAGES='```yaml
default_install_hook_types: [pre-commit, commit-msg]
repos: []
```'
PC_BLOCK_STAGES='```yaml
default_install_hook_types:
  - pre-commit
  - commit-msg
default_stages: [pre-commit]

repos: []
```'
PC_PRECOMMIT_ONLY='```yaml
default_install_hook_types:
  - pre-commit

repos: []
```'
PC_BASH_MENTION='```bash
echo "default_install_hook_types: [pre-commit, commit-msg]"
```'

make_named_skill configure-pre-commit "Body." "$PC_BLOCK_NO_STAGES"
run_check; out_pcblock="$OUT"; rc_pcblock="$RC"
assert_eq "pre-commit: commit-msg without default_stages exits 1" "$rc_pcblock" "1"
assert_contains "pre-commit: the offending fence is named by file and line" \
  "$out_pcblock" "YAML fence at ${PLUGIN}/skills/configure-pre-commit/REFERENCE.md:1 installs commit-msg"

# Guard: the inline-list spelling is the same config and must fail too.
make_named_skill configure-pre-commit "Body." "$PC_INLINE_NO_STAGES"
run_check; out_pcinline="$OUT"; rc_pcinline="$RC"
assert_eq "pre-commit: inline [.., commit-msg] without default_stages exits 1" "$rc_pcinline" "1"
assert_contains "pre-commit: the inline-list fence is flagged" \
  "$out_pcinline" "sets no default_stages"

# Guard: a fence in SKILL.md itself is checked, not only the sidecar.
make_named_skill configure-pre-commit "$PC_BLOCK_NO_STAGES"
run_check; out_pcskill="$OUT"; rc_pcskill="$RC"
assert_eq "pre-commit: an offending fence in SKILL.md exits 1" "$rc_pcskill" "1"
assert_contains "pre-commit: the SKILL.md fence is named" \
  "$out_pcskill" "YAML fence at ${PLUGIN}/skills/configure-pre-commit/SKILL.md:"

# The fix, plus two shapes that must stay clean: a config installing only the
# pre-commit type, and a non-YAML fence that merely mentions the key.
make_named_skill configure-pre-commit "Body.

$PC_BASH_MENTION" "$PC_BLOCK_STAGES

$PC_PRECOMMIT_ONLY"
run_check; out_pcfix="$OUT"; rc_pcfix="$RC"
assert_eq "pre-commit: default_stages beside commit-msg exits 0" "$rc_pcfix" "0"
assert_absent "pre-commit: the fixed skill raises no #2824 issue" "$out_pcfix" "#2824"
rm -rf "${root:?}/$PLUGIN/skills/configure-pre-commit"
# Issues #2865 / #2858: ai-review-max-turns must keep the bot-actor refusal
# ('non-human actor') and the base-branch config restore ('.claude-pr/') on
# its SKILL.md page.
#
# THE SEMANTIC INVARIANT UNDER TEST: the block is scoped to
# github-actions-plugin/ai-review-max-turns, so the sandbox is re-pointed at
# that plugin name and carries a copy of the REAL skill directory. The real
# skill exits 0 (so the guard is satisfiable by the shipped text), and the
# same copy with either token removed exits 1 naming that token. Mutating the
# real file rather than a synthetic fixture is what proves the pin reads the
# page an agent lands on.
FIXTURE_PLUGIN="$PLUGIN"
PLUGIN="github-actions-plugin"
mkdir -p "$root/$PLUGIN/.claude-plugin" "$root/$PLUGIN/skills"
write_marketplace "$CLEAN_META"
write_manifest "$CLEAN_META"
printf '{\n  "packages": {\n    "%s": {\n      "component": "%s",\n      "release-type": "simple"\n    }\n  }\n}\n' \
  "$PLUGIN" "$PLUGIN" > "$root/release-please-config.json"
printf '{\n  "%s": "1.0.0"\n}\n' "$PLUGIN" > "$root/.release-please-manifest.json"
printf '# %s\n\nFixture.\n' "$PLUGIN" > "$root/$PLUGIN/README.md"
cp -R "$REPO_ROOT/github-actions-plugin/skills/ai-review-max-turns" "$root/$PLUGIN/skills/"
armt="$root/$PLUGIN/skills/ai-review-max-turns/SKILL.md"
cp "$armt" "$tmp/armt.orig"

run_check; out_armt="$OUT"; rc_armt="$RC"
assert_eq "ai-review-max-turns: the shipped SKILL.md exits 0" "$rc_armt" "0"
assert_absent "ai-review-max-turns: the shipped SKILL.md raises no token issue" \
  "$out_armt" "ai-review-max-turns: SKILL.md must retain token"

for armt_token in 'non-human actor' '.claude-pr/'; do
  python3 - "$tmp/armt.orig" "$armt" "$armt_token" <<'PY'
import sys
src, dst, token = sys.argv[1:4]
text = open(src, encoding="utf-8").read()
assert token in text, f"fixture precondition: {token!r} not in the shipped SKILL.md"
open(dst, "w", encoding="utf-8").write(text.replace(token, "REDACTED"))
PY
  run_check; out_armt_red="$OUT"; rc_armt_red="$RC"
  assert_eq "ai-review-max-turns: dropping '${armt_token}' exits 1" "$rc_armt_red" "1"
  assert_contains "ai-review-max-turns: dropping '${armt_token}' names the token" \
    "$out_armt_red" "SKILL.md must retain token '${armt_token}'"
done

rm -rf "${root:?}/$PLUGIN"
PLUGIN="$FIXTURE_PLUGIN"
write_marketplace "$CLEAN_META"
printf '{\n  "packages": {\n    "%s": {\n      "component": "%s",\n      "release-type": "simple"\n    }\n  }\n}\n' \
  "$PLUGIN" "$PLUGIN" > "$root/release-please-config.json"
printf '{\n  "%s": "1.0.0"\n}\n' "$PLUGIN" > "$root/.release-please-manifest.json"

# Issue #3443: the configure-claude-plugins workflow templates put a `#` line
# inside the `plugins: |` block scalar (content, not a comment, so
# claude-code-action rejects it as a plugin name) and the review template's
# permissions lacked `id-token: write` (claude-code-action fetches its token
# via OIDC, so the job fails before it starts).
#
# THE SEMANTIC INVARIANT UNDER TEST: the check parses each workflow fence as
# YAML, the way the action reads it, rather than grepping for a comment. The
# shipped skill directory is copied in: it exits 0, and each defect put back
# into a copy of the shipped reference (a `#` line inside the first
# `plugins: |`, or the review job's `id-token: write` removed) exits 1 naming
# that defect.
cp -R "$REPO_ROOT/configure-plugin/skills/configure-claude-plugins" "$root/$PLUGIN/skills/"
ccp_ref="$root/$PLUGIN/skills/configure-claude-plugins/references/workflow-templates.md"
cp "$ccp_ref" "$tmp/ccp-ref.orig"

run_check; out_ccp="$OUT"; rc_ccp="$RC"
assert_eq "configure-claude-plugins: the shipped workflow templates exit 0" "$rc_ccp" "0"
assert_absent "configure-claude-plugins: the shipped templates raise no #3443 issue" "$out_ccp" "#3443"

for ccp_mutation in plugins-comment id-token; do
  python3 - "$tmp/ccp-ref.orig" "$ccp_ref" "$ccp_mutation" <<'PY'
import sys
src, dst, mutation = sys.argv[1:4]
text = open(src, encoding="utf-8").read()
if mutation == "plugins-comment":
    anchor = "          plugins: |\n"
    assert anchor in text, "fixture precondition: no `plugins: |` line in the shipped reference"
    text = text.replace(anchor, anchor + "            # a comment line inside the block scalar\n", 1)
else:
    review = text.index("name: Claude Code Review")
    head, tail = text[:review], text[review:]
    assert "  id-token: write\n" in tail, "fixture precondition: review template has no id-token: write"
    text = head + tail.replace("  id-token: write\n", "", 1)
open(dst, "w", encoding="utf-8").write(text)
PY
  run_check; out_ccp_red="$OUT"; rc_ccp_red="$RC"
  assert_eq "configure-claude-plugins: reintroducing ${ccp_mutation} exits 1" "$rc_ccp_red" "1"
  case "$ccp_mutation" in
    plugins-comment) ccp_needle="inside its plugins: block scalar" ;;
    id-token) ccp_needle="without id-token: write" ;;
  esac
  assert_contains "configure-claude-plugins: reintroducing ${ccp_mutation} is named (#3443)" \
    "$out_ccp_red" "$ccp_needle"
done
rm -rf "${root:?}/$PLUGIN/skills/configure-claude-plugins"

# --- model: haiku limits (Haiku 5.5 re-evaluation, 2026-10) ------------------
# Haiku is allowed except where one of two measured hazards applies, and each
# hazard is paired with the allowed case beside it so the suite fails both a
# lint that still bans all haiku and one that bans none.
# make_haiku_skill <name> <extra-frontmatter-lines> [body-line]
make_haiku_skill() {
  make_skill "$1" with
  local f="$root/$PLUGIN/skills/$1/SKILL.md"
  awk -v extra="model: haiku\n${HAIKU_EFFORT_LINE-effort: low\n}$2" \
    'NR > 1 && /^---$/ && !done { printf "%s", extra; done = 1 } { print }' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  [ -n "${3:-}" ] && printf '%s\n' "$3" >> "$f"
  return 0
}

make_haiku_skill haikuok ""
run_check; out_hk="$OUT"; rc_hk="$RC"
assert_eq "haiku: a user-invocable skill with no AskUserQuestion exits 0" "$rc_hk" "0"
assert_absent "haiku: the allowed case raises no haiku issue" "$out_hk" "model: haiku"
rm -rf "${root:?}/$PLUGIN/skills/haikuok"

make_haiku_skill haikuask "" "Confirm with AskUserQuestion before writing."
run_check; out_hka="$OUT"; rc_hka="$RC"
assert_eq "haiku: haiku + AskUserQuestion exits 1" "$rc_hka" "1"
assert_contains "haiku: haiku + AskUserQuestion is named (#881)" \
  "$out_hka" "haikuask: model: haiku with AskUserQuestion is disallowed"
rm -rf "${root:?}/$PLUGIN/skills/haikuask"

make_haiku_skill haikuref "user-invocable: false\n"
run_check; out_hkr="$OUT"; rc_hkr="$RC"
assert_eq "haiku: user-invocable: false without fork exits 1" "$rc_hkr" "1"
assert_contains "haiku: the turn-scope leak is named" \
  "$out_hkr" "haikuref: model: haiku on a user-invocable: false skill"
rm -rf "${root:?}/$PLUGIN/skills/haikuref"

make_haiku_skill haikufork "user-invocable: false\ncontext: fork\n"
run_check; out_hkf="$OUT"; rc_hkf="$RC"
assert_eq "haiku: user-invocable: false WITH context: fork exits 0" "$rc_hkf" "0"
assert_absent "haiku: a forked reference skill is not flagged" "$out_hkf" "model: haiku"
rm -rf "${root:?}/$PLUGIN/skills/haikufork"

# Haiku 5.5 defaults to effort medium; a haiku skill must pin one (PR #3019).
HAIKU_EFFORT_LINE="" make_haiku_skill haikunoeffort ""
run_check; out_hkn="$OUT"; rc_hkn="$RC"
assert_eq "haiku: haiku with no effort exits 1" "$rc_hkn" "1"
assert_contains "haiku: the missing effort is named" \
  "$out_hkn" "haikunoeffort: model: haiku requires an explicit effort"
rm -rf "${root:?}/$PLUGIN/skills/haikunoeffort"

HAIKU_EFFORT_LINE="effort: medium\n" make_haiku_skill haikumedium ""
run_check; out_hkm="$OUT"; rc_hkm="$RC"
assert_eq "haiku: haiku with an explicit non-low effort exits 0" "$rc_hkm" "0"
assert_absent "haiku: an explicit effort raises no haiku issue" "$out_hkm" "model: haiku"
rm -rf "${root:?}/$PLUGIN/skills/haikumedium"

# ---------------------------------------------------------------------------
# #2360 C5: feedback-session creates labels at apply time, not in Step 1.
#
# Step 1 used to run `gh label create` before any finding was collected, so a
# `--dry-run` wrote labels and a `--confirmed` run whose findings all deduped
# away still created them. THE SEMANTIC INVARIANT UNDER TEST: label creation
# appears only in the Step 5 (issue creation) section; any mention of it before
# Step 5 is ❌ (exit 1), and a Step 5 that never creates the labels is ❌ too.
# ---------------------------------------------------------------------------
make_feedback_skill() {
  # make_feedback_skill <step1-label-line> <step5-label-line>
  local dir="$root/$PLUGIN/skills/feedback-session"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: feedback-session\n'
    printf 'description: Fixture feedback-session. Use when exercising the compliance self-test.\n'
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-11-07\n'
    printf 'modified: 2026-11-07\n'
    printf 'reviewed: 2026-11-07\n'
    printf -- '---\n\n'
    printf '# feedback-session\n\n'
    printf 'Seed prose becomes SEED_FINDINGS. `--confirmed` skips Step 4.\n\n'
    printf '### Step 1: Resolve target repo and check label policy\n\n'
    printf 'When the dominant source differs from the cwd remote, ask: Mismatch detected.\n\n'
    printf '%s\n\n' "$1"
    printf '### Step 4: Present findings for review\n\nIf `--dry-run`, stop here.\n\n'
    printf '### Step 5: Create approved issues\n\n%s\n\n' "$2"
    printf 'gh issue create --title "feedback(<plugin>): <desc>"\n\n'
    printf '### Step 6: Report summary\n\nPrint the table.\n'
  } > "$dir/SKILL.md"
}
FB_CHECK_IAC='**1b. Check whether labels are IaC-managed** (read-only).'
FB_CREATE='**5a. Create missing labels** — only when at least one finding is approved.'

# --- Creation in Step 1 (the pre-fix shape) must FAIL -----------------------
make_feedback_skill "**1b–1c. Check IaC-managed labels, then create missing labels**" "Create each issue."
run_check; out_fbl1="$OUT"; rc_fbl1="$RC"
assert_eq "feedback-session: label creation in Step 1 exits 1" "$rc_fbl1" "1"
assert_contains "feedback-session: label creation in Step 1 is named" \
  "$out_fbl1" "feedback-session: label creation must happen in Step 5"

# --- A raw gh label create before Step 5 must FAIL even if Step 5 creates too
rm -rf "${root:?}/$PLUGIN/skills/feedback-session"
make_feedback_skill "$FB_CHECK_IAC Then run \`gh label create session-feedback\`." "$FB_CREATE"
run_check; out_fbl2="$OUT"; rc_fbl2="$RC"
assert_eq "feedback-session: gh label create before Step 5 exits 1" "$rc_fbl2" "1"
assert_contains "feedback-session: gh label create before Step 5 is named" \
  "$out_fbl2" "feedback-session: label creation must happen in Step 5"

# --- Dropping label creation entirely must FAIL ------------------------------
rm -rf "${root:?}/$PLUGIN/skills/feedback-session"
make_feedback_skill "$FB_CHECK_IAC" "Create each issue."
run_check; out_fbl3="$OUT"; rc_fbl3="$RC"
assert_eq "feedback-session: no label creation at all exits 1" "$rc_fbl3" "1"
assert_contains "feedback-session: missing Step 5 label creation is named" \
  "$out_fbl3" "feedback-session: Step 5 must create missing labels"

# --- Guard integrity: check in Step 1, create in Step 5 PASSES ---------------
rm -rf "${root:?}/$PLUGIN/skills/feedback-session"
make_feedback_skill "$FB_CHECK_IAC" "$FB_CREATE"
run_check; out_fbl4="$OUT"; rc_fbl4="$RC"
assert_eq "feedback-session: create-at-apply-time shape exits 0" "$rc_fbl4" "0"
assert_absent "feedback-session: compliant shape raises no label issue" \
  "$out_fbl4" "label creation must happen in Step 5"
rm -rf "${root:?}/$PLUGIN/skills/feedback-session"

# ============================================================================
# Regression (#3308): the end-to-end pipelines (foundryvtt-module, comfy-node)
# resolve <owner> from context, but each scaffold defaults --publisher to one
# maintainer's account. A `scaffold.py --name` line without --publisher writes
# that account into module.json's url/manifest/download while the repo is
# created under <owner>. The guard keys on the skill directory name, so the
# fixture is named literally "foundryvtt-module" and carries the #2142
# owner-reference token so that unrelated rule stays green.
# ============================================================================
make_pipeline_skill() {
  # make_pipeline_skill <scaffold-line-or-empty> [<extra-body-line>]
  local dir="$root/$PLUGIN/skills/foundryvtt-module"
  rm -rf "$dir"
  mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: foundryvtt-module\n'
    printf 'description: Fixture pipeline. Use when exercising the compliance self-test.\n'
    printf 'allowed-tools: Read\n'
    printf 'created: 2026-11-13\n'
    printf 'modified: 2026-11-13\n'
    printf 'reviewed: 2026-11-13\n'
    printf -- '---\n\n'
    printf '# Fixture foundryvtt-module\n\n'
    printf 'Phases 3 to 5 are owned by comfyui-plugin:comfy-node.\n\n'
    if [ -n "$1" ]; then
      printf '```sh\n%s\n```\n\n' "$1"
    fi
    if [ -n "${2:-}" ]; then
      printf '%s\n' "$2"
    fi
  } > "$dir/SKILL.md"
}
PIPE_BASE='python3 ${CLAUDE_SKILL_DIR}/../foundryvtt-module-scaffold/scaffold.py --name foundryvtt-x --display "X" --desc "X." --variant basic'

# --- The pre-fix shape: no --publisher on the scaffold line must FAIL --------
make_pipeline_skill "$PIPE_BASE"
run_check; out_pub1="$OUT"; rc_pub1="$RC"
assert_eq "pipeline: scaffold line without --publisher exits 1" "$rc_pub1" "1"
assert_contains "pipeline: missing --publisher is named (#3308)" \
  "$out_pub1" "invocation omits --publisher <owner>"

# --- Guard integrity: --publisher in prose only must still FAIL --------------
make_pipeline_skill "$PIPE_BASE" 'Pass --publisher <owner> to the scaffold.'
run_check; out_pub2="$OUT"; rc_pub2="$RC"
assert_eq "pipeline: --publisher in prose only exits 1" "$rc_pub2" "1"
assert_contains "pipeline: prose-only --publisher still flags the line" \
  "$out_pub2" "invocation omits --publisher <owner>"

# --- Guard integrity: losing the scaffold line entirely must FAIL ------------
make_pipeline_skill ""
run_check; out_pub3="$OUT"; rc_pub3="$RC"
assert_eq "pipeline: no scaffold invocation at all exits 1" "$rc_pub3" "1"
assert_contains "pipeline: missing scaffold invocation is named" \
  "$out_pub3" "lost its 'scaffold.py --name' invocation"

# --- The fix: --publisher <owner> on the scaffold line PASSES ----------------
make_pipeline_skill "$PIPE_BASE --publisher <owner> --author \"<author>\""
run_check; out_pub4="$OUT"; rc_pub4="$RC"
assert_eq "pipeline: scaffold line with --publisher exits 0" "$rc_pub4" "0"
assert_absent "pipeline: compliant shape raises no #3308 issue" \
  "$out_pub4" "#3308"
rm -rf "${root:?}/$PLUGIN/skills/foundryvtt-module"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
