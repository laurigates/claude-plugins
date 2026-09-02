#!/usr/bin/env bash
# Regression test for scripts/check-context-engineering.py (Channel M scanner).
#
# WHAT IT GUARDS
# The scanner's whole value is that its numbers are trustworthy and comparable
# across model eras. Three failure classes would silently destroy that:
#
#   1. NON-DETERMINISM. The C4 overlap pass hashes 8-word shingles. Using the
#      builtin hash() would make collisions vary per process (PYTHONHASHSEED
#      randomises str hashing), so pair counts would drift between runs of an
#      unchanged tree. Guarded by hashing --json twice and comparing.
#   2. SILENT PROXY DRIFT. If a proxy regex stops matching (e.g. a refactor
#      breaks frontmatter parsing), totals collapse to 0 and the report reads
#      as "we're already compliant". Guarded by asserting each dimension emits
#      a plausible non-degenerate value on a synthetic fixture with known
#      properties.
#   3. FORMAT BREAKAGE. Orchestrating skills parse STATUS=/ISSUE_COUNT= per
#      .claude/rules/structured-script-output.md. Guarded by asserting the
#      section wrapper and required keys exist.
#
# The fixture is built in a temp dir so the test asserts exact values rather
# than tracking the live repo's moving numbers.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
scanner="$repo_root/scripts/check-context-engineering.py"

pass_count=0
fail_count=0

assert() {
  # assert <description> <actual> <expected>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (got '$2', want '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

assert_true() {
  # assert_true <description> <condition-result "true"/"false">
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

value_of() {
  # value_of <output> <KEY> — echoes the value or empty string
  printf '%s\n' "$1" | grep -m1 -E "^$2=" | cut -d= -f2-
}

# Neutralise inherited git context before any git op (#1745): an exported
# GIT_DIR/GIT_WORK_TREE overrides `git -C`, so a sandbox `git init` would
# target the real shared .git instead of the throwaway dir.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

fixture="$(mktemp -d)"
# Guard the empty-mktemp vector (#1692): `git -C ""` falls back to the CWD.
[ -n "$fixture" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

# --- fixture: two skills and two rules with deliberately known properties ----

mkdir -p "$fixture/demo-plugin/skills/dense-skill"
cat >"$fixture/demo-plugin/skills/dense-skill/SKILL.md" <<'SKILL_EOF'
---
name: dense-skill
description: A deliberately over-constrained skill used as a scanner fixture.
args: <path>
---

# dense-skill

You MUST do this. You MUST NOT do that. NEVER skip the check. ALWAYS verify.
DO NOT proceed without confirmation. Avoid the shortcut. This is REQUIRED.

## When to Use This Skill

| Use this when | Use something else when |
|---|---|
| The fixture needs a boilerplate section | It does not |

## Steps

```bash
echo one
echo two
echo three
```

```bash
echo four
echo five
echo six
```

```bash
echo seven
echo eight
echo nine
```
SKILL_EOF

mkdir -p "$fixture/demo-plugin/skills/lean-skill/scripts"
cat >"$fixture/demo-plugin/skills/lean-skill/SKILL.md" <<'SKILL_EOF'
---
name: lean-skill
description: A lean skill with supporting files and an enumerated interface.
args: --check|--fix
argument-hint: "--check"
---

# lean-skill

Run the bundled script and report what it prints.

## Parameters

| Flag | Effect |
|---|---|
| `--check` | Report only |
| `--fix` | Apply the change |
SKILL_EOF
printf 'Detail that loads on demand.\n' >"$fixture/demo-plugin/skills/lean-skill/REFERENCE.md"
printf '#!/usr/bin/env bash\necho hi\n' >"$fixture/demo-plugin/skills/lean-skill/scripts/run.sh"

mkdir -p "$fixture/.claude/rules"
printf 'x%.0s' $(seq 1 500) >"$fixture/CLAUDE.md"
cat >"$fixture/.claude/rules/procedural-unscoped.md" <<'RULE_EOF'
# Procedural Unscoped Rule

## How to do the thing

1. First step
2. Second step
3. Third step
RULE_EOF
cat >"$fixture/.claude/rules/scoped.md" <<'RULE_EOF'
---
paths:
  - "**/*.py"
---
# Scoped Rule

An invariant that only applies to Python files.
RULE_EOF

# --- run ---------------------------------------------------------------------

out="$("$scanner" --project-dir "$fixture" --max-issues 0 2>&1)"
scan_status=$?
assert "scanner exits 0 without --strict" "$scan_status" "0"

# 3. FORMAT — the structured-script-output contract.
assert_true "emits section header" \
  "$(printf '%s' "$out" | grep -qF '=== CONTEXT ENGINEERING ===' && echo true || echo false)"
assert_true "emits section footer" \
  "$(printf '%s' "$out" | grep -qF '=== END CONTEXT ENGINEERING ===' && echo true || echo false)"
assert_true "emits STATUS" "$(printf '%s' "$out" | grep -qE '^STATUS=(OK|WARN|ERROR)$' && echo true || echo false)"
assert_true "emits ISSUE_COUNT" "$(printf '%s' "$out" | grep -qE '^ISSUE_COUNT=[0-9]+$' && echo true || echo false)"

# 2. PROXY DRIFT — each dimension must report the fixture's known properties.
assert "counts both fixture skills" "$(value_of "$out" SKILL_COUNT)" "2"

# C1: dense-skill carries 7 constraint markers in prose; lean-skill carries none.
# (MUST, MUST NOT, NEVER, ALWAYS, DO NOT, Avoid, REQUIRED — "MUST NOT" counts
# once, not as MUST + NOT, because the alternation tries the longer form first.)
assert "C1 counts constraint markers" "$(value_of "$out" C1_MARKERS_TOTAL)" "7"
assert "C1 flags the dense skill" "$(value_of "$out" C1_DENSE_SKILLS)" "1"

# C2: both declare args:, only lean-skill enumerates alternatives.
assert "C2 counts args skills" "$(value_of "$out" C2_SKILLS_WITH_ARGS)" "2"
assert "C2 counts enumerated args" "$(value_of "$out" C2_ARGS_ENUMERATED)" "1"
assert "C2 flags the opaque interface" "$(value_of "$out" C2_OPAQUE_ARG_INTERFACES)" "1"

# C3: lean-skill has REFERENCE.md + scripts/ (3 levels), dense-skill has neither.
assert "C3 counts flat skills" "$(value_of "$out" C3_LEVEL1_ONLY)" "1"
assert "C3 counts 3-level skills" "$(value_of "$out" C3_LEVEL3)" "1"

# C4: exactly one fixture skill carries the mandated boilerplate section.
assert "C4 counts When-to-Use sections" "$(value_of "$out" C4_BOILERPLATE_WHEN_TO_USE_SKILLS)" "1"

# C5: CLAUDE.md (500 chars) + the one unscoped rule; the scoped rule is excluded.
assert "C5 measures CLAUDE.md" "$(value_of "$out" C5_CLAUDE_MD_CHARS)" "500"
assert "C5 counts all rules" "$(value_of "$out" C5_RULES_TOTAL)" "2"
assert "C5 counts only unscoped rules" "$(value_of "$out" C5_UNSCOPED_RULES)" "1"
assert_true "C5 always-loaded exceeds CLAUDE.md alone" \
  "$([ "$(value_of "$out" C5_ALWAYS_LOADED_CHARS)" -gt 500 ] && echo true || echo false)"

# C6: dense-skill has 3 multi-line shell blocks and no scripts/ dir.
assert "C6 counts skills with scripts/" "$(value_of "$out" C6_SKILLS_WITH_SCRIPTS)" "1"
assert "C6 flags prose procedure without script" "$(value_of "$out" C6_PROSE_PROCEDURE_NO_SCRIPT)" "1"

# The always-loaded ratchet: ERROR + exit 1 once the budget is crossed.
strict_out="$("$scanner" --project-dir "$fixture" --always-loaded-budget 10 --strict 2>&1)"
strict_status=$?
assert "--strict exits 1 over budget" "$strict_status" "1"
assert "STATUS=ERROR over budget" "$(value_of "$strict_out" STATUS)" "ERROR"

lax_out="$("$scanner" --project-dir "$fixture" --always-loaded-budget 999999 --strict >/dev/null 2>&1; echo $?)"
assert "--strict exits 0 under budget" "$lax_out" "0"

# 1. NON-DETERMINISM — identical trees must produce byte-identical JSON.
hash_a="$("$scanner" --project-dir "$fixture" --json | sha256sum | cut -d' ' -f1)"
hash_b="$(PYTHONHASHSEED=1 "$scanner" --project-dir "$fixture" --json | sha256sum | cut -d' ' -f1)"
hash_c="$(PYTHONHASHSEED=random "$scanner" --project-dir "$fixture" --json | sha256sum | cut -d' ' -f1)"
assert "JSON is stable across runs" "$hash_a" "$hash_b"
assert "JSON is stable under PYTHONHASHSEED=random" "$hash_a" "$hash_c"

# Default project-dir resolves from the CWD, not from the script's own location.
# Regression: the scanner lives inside a plugin skill, so a __file__-derived
# default scanned the skill directory and reported SKILL_COUNT=0 — a silent
# "nothing to fix" indistinguishable from a clean repo.
git -C "$fixture" init --quiet
default_out="$(cd "$fixture" && "$scanner" 2>&1)"
assert "default project-dir finds the repo root from CWD" "$(value_of "$default_out" SKILL_COUNT)" "2"

# --target scopes the scan to one skill.
target_out="$("$scanner" --project-dir "$fixture" --target demo-plugin/skills/lean-skill 2>&1)"
assert "--target scopes to one skill" "$(value_of "$target_out" SKILL_COUNT)" "1"

# --- portfolio C5 budget (--also) --------------------------------------------
# A per-repo budget cannot see what a session that loads several repos side by
# side actually pays: each repo sits inside its own budget while the stacked
# surface is several times either. Guards the aggregation, the gate, and the
# two properties that make the number trustworthy — order-independence and
# ERROR visibility.

fixture2="$(mktemp -d)"
[ -n "$fixture2" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture" "$fixture2"' EXIT
mkdir -p "$fixture2/.claude/rules"
printf 'y%.0s' $(seq 1 300) >"$fixture2/CLAUDE.md"
printf 'z%.0s' $(seq 1 200) >"$fixture2/.claude/rules/second-unscoped.md"
# A scoped rule in the second repo must NOT count toward the portfolio total.
cat >"$fixture2/.claude/rules/second-scoped.md" <<'RULE_EOF'
---
paths:
  - "**/*.ts"
---
# Scoped — excluded from the always-loaded surface.
RULE_EOF

pf_out="$("$scanner" --project-dir "$fixture" --also "$fixture2" --max-issues 0 2>&1)"
primary_c5="$(value_of "$out" C5_ALWAYS_LOADED_CHARS)"
assert "portfolio counts both repos" "$(value_of "$pf_out" C5_PORTFOLIO_REPOS)" "2"
assert "portfolio sums the two surfaces" \
  "$(value_of "$pf_out" C5_PORTFOLIO_ALWAYS_LOADED_CHARS)" "$((primary_c5 + 500))"
assert_true "portfolio emits a per-repo breakdown line for the --also repo" \
  "$(printf '%s' "$pf_out" | grep -qE "^  - REPO=$(basename "$fixture2") CHARS=500 " && echo true || echo false)"

# Order-independence: the determinism contract must survive --also being passed
# in any order, or two CI runs of an unchanged tree disagree. Needs a THIRD repo
# so there are two --also args to actually swap.
fixture3="$(mktemp -d)"
[ -n "$fixture3" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
trap 'rm -rf "$fixture" "$fixture2" "$fixture3"' EXIT
mkdir -p "$fixture3/.claude/rules"
printf 'w%.0s' $(seq 1 100) >"$fixture3/CLAUDE.md"

pf_hash_a="$("$scanner" --project-dir "$fixture" --also "$fixture2" --also "$fixture3" --json | sha256sum | cut -d' ' -f1)"
pf_hash_b="$("$scanner" --project-dir "$fixture" --also "$fixture3" --also "$fixture2" --json | sha256sum | cut -d' ' -f1)"
assert "portfolio JSON is identical when --also order is swapped" "$pf_hash_a" "$pf_hash_b"
pf_hash_c="$("$scanner" --project-dir "$fixture" --also "$fixture2" --also "$fixture3" --json | sha256sum | cut -d' ' -f1)"
assert "portfolio JSON is stable across runs" "$pf_hash_a" "$pf_hash_c"

# Two --also roots sharing a basename must still sort deterministically: a
# stable sort keyed on the name alone would fall back to argument order, which
# is exactly the non-determinism this scanner exists to rule out.
dup_root_a="$(mktemp -d)" || { echo 'FATAL: mktemp failed' >&2; exit 1; }
[ -n "$dup_root_a" ] || { echo 'FATAL: empty mktemp dir' >&2; exit 1; }
[ -d "$dup_root_a" ] || { echo 'FATAL: mktemp dir missing' >&2; exit 1; }
dup_root_b="$(mktemp -d)" || { echo 'FATAL: mktemp failed' >&2; exit 1; }
[ -n "$dup_root_b" ] || { echo 'FATAL: empty mktemp dir' >&2; exit 1; }
[ -d "$dup_root_b" ] || { echo 'FATAL: mktemp dir missing' >&2; exit 1; }
dup_a="$dup_root_a/config"; dup_b="$dup_root_b/config"
mkdir -p "$dup_a/.claude/rules" "$dup_b/.claude/rules"
printf 'a%.0s' $(seq 1 100) >"$dup_a/CLAUDE.md"
printf 'b%.0s' $(seq 1 900) >"$dup_b/CLAUDE.md"
dup_hash_a="$("$scanner" --project-dir "$fixture" --also "$dup_a" --also "$dup_b" --json | sha256sum | cut -d' ' -f1)"
dup_hash_b="$("$scanner" --project-dir "$fixture" --also "$dup_b" --also "$dup_a" --json | sha256sum | cut -d' ' -f1)"
assert "same-basename roots sort deterministically" "$dup_hash_a" "$dup_hash_b"
rm -rf "$dup_a" "$dup_b"

# The breakdown is sorted by repo name, so the emitted order is independent of
# the order the roots were supplied in.
sorted_repos="$("$scanner" --project-dir "$fixture" --also "$fixture3" --also "$fixture2" 2>&1 \
  | grep -oE '^  - REPO=[^ ]+' | sed 's/^  - REPO=//')"
assert "breakdown is emitted in repo-name order" \
  "$sorted_repos" "$(printf '%s\n' "$sorted_repos" | sort)"

# The gate itself.
"$scanner" --project-dir "$fixture" --also "$fixture2" --portfolio-budget 10 --strict >/dev/null 2>&1
assert "--strict exits 1 over the portfolio budget" "$?" "1"
"$scanner" --project-dir "$fixture" --also "$fixture2" --portfolio-budget 999999 --strict >/dev/null 2>&1
assert "--strict exits 0 under the portfolio budget" "$?" "0"

# A repo inside its OWN budget can still bust the portfolio budget — the whole
# reason this mode exists. Primary budget generous, portfolio budget tight.
split_out="$("$scanner" --project-dir "$fixture" --also "$fixture2" \
  --always-loaded-budget 999999 --portfolio-budget 10 --max-issues 0 2>&1)"
assert "per-repo pass + portfolio fail yields ERROR" "$(value_of "$split_out" STATUS)" "ERROR"
assert_true "portfolio ERROR names the offending repos" \
  "$(printf '%s' "$split_out" | grep -qE 'TYPE=portfolio_always_loaded_over_budget.*'"$(basename "$fixture2")"'=500' && echo true || echo false)"

# ERROR must outrank WARNs in the listing: --max-issues could otherwise truncate
# away the only line explaining why STATUS=ERROR.
trunc_out="$("$scanner" --project-dir "$fixture" --also "$fixture2" --portfolio-budget 10 --max-issues 1 2>&1)"
assert_true "ERROR is listed first, never truncated by --max-issues" \
  "$(printf '%s' "$trunc_out" | grep -A1 '^ISSUES:' | grep -qE 'SEVERITY=ERROR.*portfolio_always_loaded_over_budget' && echo true || echo false)"

# --also and --target are mutually exclusive: --target drops rules and CLAUDE.md,
# which is the entire C5 surface, so the portfolio total would silently be wrong.
"$scanner" --project-dir "$fixture" --also "$fixture2" --target demo-plugin/skills/lean-skill >/dev/null 2>&1
assert "--also with --target is rejected" "$?" "2"

# A non-existent --also root must fail loudly, not silently contribute 0.
"$scanner" --project-dir "$fixture" --also "$fixture/definitely-not-here" >/dev/null 2>&1
assert "--also on a missing path exits 1" "$?" "1"

# Without --also the portfolio keys must be absent entirely (no behaviour change
# for every existing caller).
assert_true "no --also means no portfolio keys" \
  "$(printf '%s' "$out" | grep -qE '^C5_PORTFOLIO' && echo false || echo true)"

echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ]
