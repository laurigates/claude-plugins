#!/usr/bin/env bash
# test-check-workflow-js-model.sh — SEMANTIC regression tests for
# scripts/check-workflow-js-model.sh (issue #2210).
#
# It EXECUTES the guard against planted fixture trees rather than grepping the
# guard's source (.claude/rules/regression-testing.md: a syntactic gate cements
# a broken command — the #1417 → #1819 lesson). The corpus of bundled
# `*/skills/*/workflows/*.workflow.js` files is CURRENTLY EMPTY, so every
# positive case has to be planted.
#
# Cases:
#   A. empty corpus                       → STATUS=OK, exit 0 (plain AND --strict)
#   B. compliant harness                  → STATUS=OK, exit 0
#   C. missing effort                     → ERROR, --strict exit 1, plain exit 0
#   D. non-opus model (sonnet)            → ERROR non_opus_model
#   E. unknown argument                   → exit 2, usage on stderr, no scan
#   F. .claude/worktrees/ copy pruned     → not double-counted, path never leaks
#   G. orphan .js (no framing section)    → ERROR unreachable_workflow
#   H. absent model                       → WARN only; exit 0 even with --strict
#   I. invalid effort tier                → ERROR invalid_effort
#   J. worktree dispatch w/o the clauses  → ERROR missing_worktree_clause
#   K. GUARD INTEGRITY — the parser must not fire on `agent(...)` text that
#      lives inside a comment or a template-literal prompt, AND the compliant
#      fixture must report AGENT_CALLS>0 (otherwise every "no issues" verdict in
#      this file is vacuous and the test has silently degraded to a no-op).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHECK="${REPO_ROOT}/scripts/check-workflow-js-model.sh"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

[ -f "$CHECK" ] || { echo "missing script: $CHECK" >&2; exit 1; }

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Fixture builders
# ---------------------------------------------------------------------------

# mk_root <name> — an empty fixture repo root; echoes its path.
mk_root() {
    local d="$WORK/$1"
    mkdir -p "$d"
    echo "$d"
}

# mk_skill <root> <plugin> <skill> — creates the skill dir + a SKILL.md whose
# framing section is complete (harness heading, filename, both worktree clauses).
# Callers mutate the SKILL.md afterwards to build the negative cases.
mk_skill() {
    local root="$1" plugin="$2" skill="$3"
    local dir="$root/$plugin/skills/$skill"
    mkdir -p "$dir/workflows"
    cat > "$dir/SKILL.md" <<'MD'
---
name: fixture-skill
description: Fixture. Use when testing the bundled-workflow guard.
---

## Workflow harness (template)

`workflows/audit.workflow.js` ships beside this skill. It is a TEMPLATE to adapt.

> Never `Workflow({resumeFromRunId})` to retry a few failed worktree agents (#1868).

> Push, PR creation, and GitHub mutations happen only in the single sequential
> finalise stage, never inside a fanned-out agent.
MD
    echo "$dir"
}

# mk_js <skill-dir> <basename> <model-literal-or-empty> <effort-literal-or-empty>
mk_js() {
    local dir="$1" base="$2" model="$3" effort="$4" opts=""
    [ -n "$model" ] && opts="${opts}model:'${model}', "
    [ -n "$effort" ] && opts="${opts}effort:'${effort}', "
    {
        echo "export default async function ({ agent, parallel }) {"
        echo "  const r = await agent(\`Audit the thing.\`,"
        echo "    { label:'audit', schema: S, ${opts}phase:'discover' });"
        echo "  return r;"
        echo "}"
    } > "$dir/workflows/$base"
}

run() { # run <root> [extra args…] → exit code, output discarded
    bash "$CHECK" --project-dir "$1" "${@:2}" >/dev/null 2>&1
    echo $?
}

out() { # out <root> [extra args…] → stdout+stderr
    bash "$CHECK" --project-dir "$1" "${@:2}" 2>&1
}

field() { # field <output> <KEY> → value
    printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2-
}

# ---------------------------------------------------------------------------
# A. Empty corpus — the repo's current state. A guard that errors here is broken.
# ---------------------------------------------------------------------------
root=$(mk_root A)
o=$(out "$root")
check "A: empty corpus STATUS=OK"          "OK" "$(field "$o" STATUS)"
check "A: empty corpus FILES_SCANNED=0"    "0"  "$(field "$o" FILES_SCANNED)"
check "A: empty corpus exit 0"             "0"  "$(run "$root")"
check "A: empty corpus --strict exit 0"    "0"  "$(run "$root" --strict)"

# ---------------------------------------------------------------------------
# B. Compliant harness.
# ---------------------------------------------------------------------------
root=$(mk_root B)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js opus low
o=$(out "$root")
check "B: compliant STATUS=OK"        "OK" "$(field "$o" STATUS)"
check "B: compliant FILES_SCANNED=1"  "1"  "$(field "$o" FILES_SCANNED)"
check "B: compliant exit 0 --strict"  "0"  "$(run "$root" --strict)"
# GUARD INTEGRITY (K, part 1): if the parser found no agent() call, every
# "no issues" assertion above proves nothing.
check "K: compliant fixture AGENT_CALLS=1" "1" "$(field "$o" AGENT_CALLS)"

# ---------------------------------------------------------------------------
# C. Missing effort → ERROR; --strict exits 1, plain run still exits 0.
# ---------------------------------------------------------------------------
root=$(mk_root C)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js opus ""
o=$(out "$root")
check "C: missing effort STATUS=ERROR"    "ERROR" "$(field "$o" STATUS)"
check "C: missing effort ERROR_COUNT=1"   "1"     "$(field "$o" ERROR_COUNT)"
check "C: missing effort typed"           "1"     "$(printf '%s\n' "$o" | grep -c 'TYPE=missing_effort')"
check "C: missing effort --strict exit 1" "1"     "$(run "$root" --strict)"
check "C: missing effort plain exit 0"    "0"     "$(run "$root")"

# ---------------------------------------------------------------------------
# D. Non-opus model.
# ---------------------------------------------------------------------------
root=$(mk_root D)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js sonnet low
o=$(out "$root")
check "D: sonnet STATUS=ERROR"          "ERROR" "$(field "$o" STATUS)"
check "D: sonnet typed non_opus_model"  "1"     "$(printf '%s\n' "$o" | grep -c 'TYPE=non_opus_model')"
check "D: sonnet names the model"       "1"     "$(printf '%s\n' "$o" | grep -c 'MODEL=sonnet')"
check "D: sonnet --strict exit 1"       "1"     "$(run "$root" --strict)"

# ---------------------------------------------------------------------------
# E. Unknown argument → exit 2 with usage, and nothing scanned (#2057).
# ---------------------------------------------------------------------------
root=$(mk_root E)
e_out=$(bash "$CHECK" --project-dir "$root" --only-verdictz=x 2>&1); e_rc=$?
check "E: unknown arg exit 2"            "2" "$e_rc"
check "E: unknown arg named on stderr"   "1" "$(printf '%s\n' "$e_out" | grep -c -- '--only-verdictz=x')"
check "E: unknown arg prints usage"      "1" "$(printf '%s\n' "$e_out" | grep -c '^Usage: check-workflow-js-model.sh')"
check "E: unknown arg scans nothing"     "0" "$(printf '%s\n' "$e_out" | grep -c '^FILES_SCANNED=')"

# ---------------------------------------------------------------------------
# F. .claude/worktrees/ copies are pruned, never double-counted (#1492/#1548).
# ---------------------------------------------------------------------------
root=$(mk_root F)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js opus low
before=$(field "$(out "$root")" FILES_SCANNED)
wt="$root/.claude/worktrees/agent-deadbeef"
mkdir -p "$wt"
cp -R "$root/demo-plugin" "$wt/demo-plugin"
o=$(out "$root")
check "F: worktree clone not counted"  "$before" "$(field "$o" FILES_SCANNED)"
check "F: worktree path never leaks"   "0"       "$(printf '%s\n' "$o" | grep -c '\.claude/worktrees/')"
check "F: worktree clone still STATUS=OK" "OK"   "$(field "$o" STATUS)"

# ---------------------------------------------------------------------------
# G. Orphan .js — the sibling SKILL.md lacks the framing section.
# ---------------------------------------------------------------------------
root=$(mk_root G)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js opus low
printf -- '---\nname: x\ndescription: y. Use when z.\n---\n\nNo harness section here.\n' > "$d/SKILL.md"
o=$(out "$root")
check "G: orphan STATUS=ERROR"              "ERROR" "$(field "$o" STATUS)"
check "G: orphan typed unreachable_workflow" "2"    "$(printf '%s\n' "$o" | grep -c 'TYPE=unreachable_workflow')"
check "G: orphan --strict exit 1"           "1"     "$(run "$root" --strict)"

# ---------------------------------------------------------------------------
# H. Absent model → WARN only (issue #2210: inheriting the session model is
#    acceptable), so STATUS=WARN but the run still exits 0 even under --strict.
# ---------------------------------------------------------------------------
root=$(mk_root H)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js "" low
o=$(out "$root")
check "H: absent model STATUS=WARN"       "WARN" "$(field "$o" STATUS)"
check "H: absent model ERROR_COUNT=0"     "0"    "$(field "$o" ERROR_COUNT)"
check "H: absent model WARN_COUNT=1"      "1"    "$(field "$o" WARN_COUNT)"
check "H: absent model --strict exit 0"   "0"    "$(run "$root" --strict)"

# ---------------------------------------------------------------------------
# I. Invalid effort tier.
# ---------------------------------------------------------------------------
root=$(mk_root I)
d=$(mk_skill "$root" demo-plugin demo-skill)
mk_js "$d" audit.workflow.js opus turbo
o=$(out "$root")
check "I: invalid effort typed"      "1" "$(printf '%s\n' "$o" | grep -c 'TYPE=invalid_effort')"
check "I: invalid effort names it"   "1" "$(printf '%s\n' "$o" | grep -c 'EFFORT=turbo')"
check "I: invalid effort exit 1"     "1" "$(run "$root" --strict)"

# ---------------------------------------------------------------------------
# J. Worktree-dispatching template whose SKILL.md framing drops the clauses.
# ---------------------------------------------------------------------------
root=$(mk_root J)
d=$(mk_skill "$root" demo-plugin demo-skill)
cat > "$d/workflows/audit.workflow.js" <<'JS'
export default async function ({ agent }) {
  return await agent(`Implement it.`,
    { label:'impl', model:'opus', effort:'low', isolation:'worktree' });
}
JS
# Guard integrity: with the clauses present it must be clean.
check "J: worktree clauses present → OK" "OK" "$(field "$(out "$root")" STATUS)"
# Now strip both clauses. The backticks are literal markdown in the fixture, not
# a command substitution — single quotes are deliberate.
# shellcheck disable=SC2016
printf -- '---\nname: x\ndescription: y. Use when z.\n---\n\n## Workflow harness (template)\n\n`workflows/audit.workflow.js` ships beside this skill.\n' > "$d/SKILL.md"
o=$(out "$root")
check "J: missing worktree clauses typed" "2" "$(printf '%s\n' "$o" | grep -c 'TYPE=missing_worktree_clause')"
check "J: missing worktree clauses exit 1" "1" "$(run "$root" --strict)"

# ---------------------------------------------------------------------------
# K (part 2). GUARD INTEGRITY — agent() text inside a comment or a template
# literal is not a call site. A parser that matched raw text would report
# AGENT_CALLS=3 and flag two phantom sonnet violations here.
# ---------------------------------------------------------------------------
root=$(mk_root K)
d=$(mk_skill "$root" demo-plugin demo-skill)
cat > "$d/workflows/audit.workflow.js" <<'JS'
export default async function ({ agent }) {
  // Never write agent(prompt, {model:'sonnet'}) — opus only.
  /* Also not a call: agent(p, {model:'haiku'}) */
  const brief = `Do not literally run agent(x, {model:'sonnet'}) yourself.`;
  return await agent(brief, { label:'audit', model:'opus', effort:'medium' });
}
JS
o=$(out "$root")
check "K: only the real call is parsed"   "1"  "$(field "$o" AGENT_CALLS)"
check "K: comment/template text is clean" "OK" "$(field "$o" STATUS)"
check "K: no phantom non_opus_model"      "0"  "$(printf '%s\n' "$o" | grep -c 'TYPE=non_opus_model')"

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$pass" "$fail"
[ "$fail" -eq 0 ]
