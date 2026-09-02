#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: single-quoted `grep -F` needles are literal by design (must precede the first command)
# Regression test for scripts/agentic-audit-precompute.sh (issue #2557).
#
# The generator used to be inline shell inside `.github/workflows/scheduled-audits.yml`,
# so nothing under scripts/tests/ could reach it and its flagging predicates were
# untestable. This suite pins the two defects that actually live in that block, plus
# the stale-review date-cohort section added alongside the extraction.
#
# HERMETIC: every case runs against a throwaway skill tree under a guarded
# `mktemp -d`, cleaned by trap. The script under test resolves its own REPO_ROOT
# from `${BASH_SOURCE[0]}/..`, so a COPY of the real script is placed at
# <fixture>/scripts/ and the fixture becomes its repo root. The copy is the shipped
# bytes — never a re-typed reimplementation (the #1417 -> #1819 lesson).
#
# NOTE ON PINNED-CURRENT-BEHAVIOUR CASES: the `when to use` grep is unanchored AND
# fence-blind, so an occurrence inside a fenced code block or in body prose satisfies
# it. Those are two independent looseness properties, so they get one fixture each —
# a single fixture pins only the property it happens to violate:
#   * fenced-when-to-use — the phrase is a HEADING, but inside a fence. Reds only if
#     the grep learns to strip fenced blocks; an anchored `^#+ .*when to use` still
#     matches it, so this fixture alone would let that change land silently.
#   * prose-when-to-use  — the phrase is BODY PROSE, outside any fence. Reds only if
#     the grep is anchored to headings; fence-stripping leaves it matching.
# Together they make either change a deliberate, visible edit. Both are asserted as
# CURRENT behaviour, not as desirable behaviour.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
subject="$repo_root/scripts/agentic-audit-precompute.sh"

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

if [ ! -f "$subject" ]; then
  echo "FAIL: subject not found: $subject" >&2
  exit 1
fi

fixture="$(mktemp -d)"
if [ -z "$fixture" ] || [ ! -d "$fixture" ]; then
  echo "FAIL: could not create fixture directory" >&2
  exit 1
fi
trap 'rm -rf "$fixture"' EXIT

# Portable "N days ago" — GNU first, BSD/macOS second.
days_ago() {
  date -d "$1 days ago" +%Y-%m-%d 2>/dev/null || date -v-"$1"d +%Y-%m-%d 2>/dev/null
}

STALE_DATE="$(days_ago 400)"
FRESH_DATE="$(days_ago 5)"
if [ -z "$STALE_DATE" ] || [ -z "$FRESH_DATE" ]; then
  echo "FAIL: could not compute fixture dates on this platform" >&2
  exit 1
fi

mkdir -p "$fixture/scripts"
cp "$subject" "$fixture/scripts/agentic-audit-precompute.sh"

mk_skill() {
  # mk_skill <relative-dir> <heredoc-on-stdin>
  mkdir -p "$fixture/$1"
  cat > "$fixture/$1/SKILL.md"
}

##########
# Fixture skills
##########

# (1) DEFECT: no Bash in allowed-tools, no Agentic Optimizations table.
mk_skill "demo-plugin/skills/no-bash" <<EOF
---
name: no-bash
description: A skill with no Bash grant. Use when reading files.
allowed-tools: Read, Grep
reviewed: $FRESH_DATE
---

## When to Use This Skill

Reading things.
EOF

# (1-control) Same shape but WITH Bash — proves the annotation discriminates
# rather than printing a constant.
mk_skill "demo-plugin/skills/has-bash" <<EOF
---
name: has-bash
description: A skill that runs shell. Use when running commands.
allowed-tools: Read, Bash
reviewed: $FRESH_DATE
---

## When to Use This Skill

Running things.
EOF

# (2a) PINNED CURRENT BEHAVIOUR — FENCE-BLINDNESS. The only occurrence of
# "when to use" is inside a fenced code block. It IS heading-shaped, so an anchored
# `^#+[[:space:]].*when to use` grep would still match it — this fixture pins the
# fence half only, and (2b) pins the anchoring half.
mk_skill "demo-plugin/skills/fenced-when-to-use" <<EOF
---
name: fenced-when-to-use
description: Phrase appears only inside a fence. Use when testing the grep.
allowed-tools: Read
reviewed: $FRESH_DATE
---

## Overview

\`\`\`markdown
## When to use this skill
\`\`\`
EOF

# (2b) PINNED CURRENT BEHAVIOUR — MISSING HEADING ANCHOR. The only occurrence of
# "when to use" is body prose, outside any fence and not heading-shaped. A
# fence-stripping grep would still match it — this fixture pins the anchoring half.
mk_skill "demo-plugin/skills/prose-when-to-use" <<EOF
---
name: prose-when-to-use
description: Phrase appears only as body prose. Use for the unanchored-grep case.
allowed-tools: Read
reviewed: $FRESH_DATE
---

## Overview

Read the section below to learn when to use this skill in anger.
EOF

# (2-control) No occurrence of the phrase anywhere — MUST be reported, otherwise
# the two cases above would pass against a generator that reports nothing at all.
mk_skill "demo-plugin/skills/truly-missing-wtu" <<EOF
---
name: truly-missing-wtu
description: No trigger phrase anywhere. Use when checking the control.
allowed-tools: Read
reviewed: $FRESH_DATE
---

## Overview

Nothing here.
EOF

# (3) POSITIVE CONTROL: reviewed 400 days ago. MUST appear in the stale list AND
# its date MUST appear in the cohort roll-up, so the suite cannot pass vacuously
# against a script that emits an empty report.
mk_skill "demo-plugin/skills/stale-review" <<EOF
---
name: stale-review
description: Long unreviewed. Use when checking staleness.
allowed-tools: Read, Bash
reviewed: $STALE_DATE
---

## When to Use This Skill

## Agentic Optimizations

| Flag | Effect |
|------|--------|
| \`-q\` | quiet |
EOF

# (3-control) Second skill sharing the SAME stale date, so the cohort count is a
# real count (2) rather than an artefact of one row.
mk_skill "demo-plugin/skills/stale-review-sibling" <<EOF
---
name: stale-review-sibling
description: Also long unreviewed. Use when checking cohort counting.
allowed-tools: Read, Bash
reviewed: $STALE_DATE
---

## When to Use This Skill

## Agentic Optimizations

| Flag | Effect |
|------|--------|
| \`-q\` | quiet |
EOF

# (4) A worktree clone: an agent worktree is a full repo copy. It must be pruned,
# not walked (the #2214 timeout class).
mk_skill ".claude/worktrees/agent-deadbeef/demo-plugin/skills/no-bash" <<EOF
---
name: no-bash
description: A worktree clone. Use when nothing.
allowed-tools: Read, Grep
reviewed: $STALE_DATE
---
EOF

##########
# Run
##########

out="$fixture/out.md"
err="$fixture/out.err"
bash "$fixture/scripts/agentic-audit-precompute.sh" >"$out" 2>"$err"
run_status=$?

echo "=== agentic-audit-precompute.sh: contract ==="
assert "exits 0" \
  "$([ "$run_status" -eq 0 ] && echo true || echo false)"
assert "writes nothing to stderr" \
  "$([ ! -s "$err" ] && echo true || echo false)"
assert "produces a non-empty report" \
  "$([ -s "$out" ] && echo true || echo false)"

if [ -s "$err" ]; then
  echo "  stderr:" >&2
  sed 's/^/    /' "$err" >&2
fi

# Section slicing so an assertion about one list cannot be satisfied by a hit in
# another (every fixture skill appears in the MISSING_AGENTIC list too).
section() {
  # section <start-heading-regex> <end-heading-regex>
  awk -v s="$1" -v e="$2" '$0 ~ s {on=1; next} $0 ~ e {on=0} on' "$out"
}
agentic_section="$(section '^## Skills missing Agentic Optimizations table:$' '^## Skills with stale reviews')"
# Literal parens as bracket expressions, NOT `\(` `\)`. `$0 ~ s` compiles s as a
# DYNAMIC regex, and a backslash-escaped paren is undefined in POSIX awk, so awks
# disagree: the GitHub runner's awk warns "escape sequence `\(' treated as plain
# `('" and then reads the parens as a GROUP, so `\(>90 days\)` matches a heading
# with NO parens, this section slices empty, and the stale-list assertion below
# fails there while passing on a build that reads the escape as a literal paren
# (measured: mawk 1.3.4 20240123 tolerates it, the runner's older mawk does not --
# both Linux, so this is a build difference, not a platform one). `[(]` carries no
# escape at all and is literal under every awk.
stale_section="$(section '^## Skills with stale reviews [(]>90 days[)]:$' '^## Stale-review date distribution$')"
cohort_section="$(section '^## Stale-review date distribution$' '^## Skills with missing required')"
sections_section="$(section '^## Skills with missing required sections/frontmatter:$' '^__NEVER_MATCHES__$')"

# A boundary regex that fails to match slices the section EMPTY, which silently
# satisfies every "must NOT contain" assertion below. That is how the `\(`
# mawk-portability bug above reached CI green locally. Fail loudly instead.
for _s in agentic stale cohort sections; do
  eval "_body=\$${_s}_section"
  if [ -z "$_body" ]; then
    echo "FAIL: ${_s}_section sliced empty — a boundary heading did not match." >&2
    echo "      Assertions over it would pass vacuously. Report follows:" >&2
    sed 's/^/    /' "$out" >&2
    exit 1
  fi
done
unset _s _body

##########
# GUARD INTEGRITY — the corpus was really walked
##########
echo "=== guard integrity ==="
assert "reports the 7 real fixture skills (worktree clone pruned, not counted)" \
  "$(grep -q '^Pre-computed data for 7 skills:$' "$out" && echo true || echo false)"
assert "no .claude/worktrees path leaks into the report" \
  "$(! grep -q '\.claude/worktrees' "$out" && echo true || echo false)"
assert "the Agentic-Optimizations list is non-empty" \
  "$([ -n "$(printf '%s' "$agentic_section" | tr -d '[:space:]')" ] && echo true || echo false)"

##########
# DEFECT 1 — has_bash annotation
##########
echo "=== has_bash annotation ==="
assert "a skill with no Bash in allowed-tools reads '(Bash in allowed-tools: no)'" \
  "$(printf '%s\n' "$agentic_section" \
     | grep -qF 'demo-plugin/skills/no-bash/SKILL.md (Bash in allowed-tools: no)' && echo true || echo false)"
assert "a skill WITH Bash in allowed-tools reads '(Bash in allowed-tools: yes)'" \
  "$(printf '%s\n' "$agentic_section" \
     | grep -qF 'demo-plugin/skills/has-bash/SKILL.md (Bash in allowed-tools: yes)' && echo true || echo false)"
# The list ANNOTATES, it does not FILTER: a Bash-less skill must still be listed.
assert "the Bash-less skill is still listed (annotation, not a filter)" \
  "$(printf '%s\n' "$agentic_section" | grep -qF 'demo-plugin/skills/no-bash/SKILL.md' && echo true || echo false)"

##########
# DEFECT 2 — unanchored `when to use` grep (current behaviour pinned)
##########
echo "=== when-to-use detection (current behaviour) ==="
assert "a heading-shaped 'when to use' inside a fence is NOT reported missing (pins fence-blindness)" \
  "$(! printf '%s\n' "$sections_section" \
     | grep -q 'fenced-when-to-use/SKILL.md.*When-to-Use' && echo true || echo false)"
assert "a non-heading 'when to use' in body prose is NOT reported missing (pins the missing heading anchor)" \
  "$(! printf '%s\n' "$sections_section" \
     | grep -q 'prose-when-to-use/SKILL.md.*When-to-Use' && echo true || echo false)"
assert "a skill with no 'when to use' anywhere IS reported missing (control)" \
  "$(printf '%s\n' "$sections_section" \
     | grep -q 'truly-missing-wtu/SKILL.md.*When-to-Use' && echo true || echo false)"

##########
# POSITIVE CONTROL — stale list and the new date-cohort section
##########
echo "=== stale reviews + date cohorts ==="
assert "the 400-day-old skill appears in the stale list" \
  "$(printf '%s\n' "$stale_section" \
     | grep -qF "demo-plugin/skills/stale-review/SKILL.md: reviewed $STALE_DATE" && echo true || echo false)"
assert "a freshly-reviewed skill does NOT appear in the stale list" \
  "$(! printf '%s\n' "$stale_section" | grep -q 'skills/no-bash/SKILL.md' && echo true || echo false)"
assert "the cohort section counts exactly the 2 stale skills" \
  "$(printf '%s\n' "$cohort_section" | grep -qF -- '- Stale skills counted: 2' && echo true || echo false)"
assert "the cohort section reports 1 distinct reviewed: date" \
  "$(printf '%s\n' "$cohort_section" | grep -qF -- '- Distinct `reviewed:` dates among them: 1' && echo true || echo false)"
assert "the stale skill's date appears in the cohort roll-up with its count" \
  "$(printf '%s\n' "$cohort_section" | grep -qE "^  - +2 $STALE_DATE\$" && echo true || echo false)"
# Data, not diagnosis (#2557 Rec 3): this checkout's history is grafted, so a
# shared date cannot be proven to be a bulk edit here.
assert "the cohort section presents itself as data, not a diagnosis" \
  "$(printf '%s\n' "$cohort_section" | grep -q 'not as a diagnosis' && echo true || echo false)"

##########
# Structure — the three original headings survive the extraction verbatim
##########
echo "=== prompt-facing headings ==="
for heading in \
  '## Skills missing Agentic Optimizations table:' \
  '## Skills with stale reviews (>90 days):' \
  '## Skills with missing required sections/frontmatter:' \
  '## Stale-review date distribution'; do
  assert "report carries the heading '$heading'" \
    "$(grep -qxF "$heading" "$out" && echo true || echo false)"
done

echo ""
echo "Passed: $pass_count, Failed: $fail_count"
[ "$fail_count" -eq 0 ]
