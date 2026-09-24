#!/usr/bin/env bash
# shellcheck disable=SC2016  # literal markdown backticks in rule-table fixtures, never expansions
# Regression test for scripts/check-workflow-model.sh
# (.claude/rules/workflow-model-effort.md — every Claude workflow pins
#  `--model opus` and an explicit `--effort` level).
#
# Guards:
#   A. the real repo stays clean — every invoking workflow is opus+effort, exit 0
#   B. an opus+effort claude_args fixture exits 0 and reports the count
#   C. a `--model haiku` workflow exits 1, names the file, reports the model
#   D. a `--model sonnet` workflow exits 1 and names the file
#   E. `--model opus` WITHOUT `--effort` exits 1 (missing_effort — the invariant
#      the agent-model guard does not have)
#   F. CLI/npx form with `--model haiku` exits 1 (second parser path)
#   G. CLI/npx form with opus+effort exits 0
#   H. a workflow with no Claude invocation is not counted, exit 0
#   I. a reusable-only workflow is skipped, exit 0
#   J. `--effort bogus` (invalid level) exits 1 (invalid_effort)
#   K. an allowlisted file is honored (via the CHECK_WORKFLOW_MODEL_ALLOWLIST seam)
#   L. a prompt: block that DOCUMENTS `--model`/`--effort` in prose does not
#      false-positive (extraction is scoped to claude_args + CLI flag lines)
#   M. an unknown dash-argument (e.g. `--strict`) exits 2 and scans NOTHING,
#      instead of being swallowed into the explicit-files list and reporting a
#      vacuous WORKFLOWS_SCANNED=0 / STATUS=OK / exit 0 (#2057)
#   N. every INVOKING workflow has a row in the rule's canonical per-workflow
#      table (#2630 Rec 2): the table is hand-maintained and had silently
#      fallen two workflows behind the scanned set. Only the FIRST cell of a
#      row inside the "Per-workflow table (canonical)" section counts, so a
#      mention in a rationale cell or in another section does not satisfy it;
#      a rule file whose table parses to zero rows is a misfire, not a pass.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-workflow-model.sh"

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

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }
# has_line <text> <KEY=VALUE> — whole-line match. A substring match lets a
# sibling key satisfy an assertion (`TABLE_ROWS=1` inside `MISSING_TABLE_ROWS=1`,
# the #2297 anchoring lesson), so every new KEY=VALUE assertion is anchored.
has_line() { grep -qxF -- "$2" <<<"$1" && echo true || echo false; }

# make_rule_table <project-dir> <row-cell>... — write a minimal
# .claude/rules/workflow-model-effort.md whose canonical table carries one row
# per argument (each argument is the row's FIRST cell, verbatim).
make_rule_table() {
  local dir="$1"; shift
  mkdir -p "$dir/.claude/rules"
  {
    echo "# Workflow Model + Effort"
    echo ""
    echo "## Per-workflow table (canonical)"
    echo ""
    echo "| Workflow | Model + effort | Rationale |"
    echo "|----------|----------------|-----------|"
    local cell
    for cell in "$@"; do
      echo "| $cell | \`opus\` / \`low\` | fixture row |"
    done
    echo ""
    echo "## Enforcement: classification"
  } > "$dir/.claude/rules/workflow-model-effort.md"
}

# make_action_workflow <path> <claude_args-value> — minimal claude-code-action
# workflow with the given claude_args string.
make_action_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: action workflow"
on: { workflow_dispatch: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: "$2"
          prompt: "Do a thing."
EOF
}

# make_cli_workflow <path> <model> <effort> — minimal npx-CLI form workflow.
make_cli_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: cli workflow"
on: { push: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - run: |
          cat <<'P' | npx @anthropic-ai/claude-code --print \\
            --model $2 \\
            --effort $3 \\
            --max-turns 20 \\
            -
          Resolve the thing.
          P
EOF
}

# make_cli_workflow_noeffort <path> <model> — CLI form without --effort.
make_cli_workflow_noeffort() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: cli workflow"
on: { push: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - run: |
          cat <<'P' | npx @anthropic-ai/claude-code --print --model $2 --max-turns 20 -
          Resolve the thing.
          P
EOF
}

# make_plain_workflow <path> — a workflow with no Claude invocation.
make_plain_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: plain workflow"
on: { push: {} }
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - run: echo build
EOF
}

# make_reusable_workflow <path> — delegates to an external reusable workflow.
make_reusable_workflow() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
name: "Fixture: reusable caller"
on: { pull_request: {} }
jobs:
  review:
    uses: owner/.github/.github/workflows/reusable-claude-review.yml@main
    secrets: inherit
EOF
}

# run <project-dir> — invoke the checker, capture combined output + exit code.
run() {
  OUT="$(bash "$checker" --project-dir "$1" 2>&1)"
  RC=$?
}

echo "=== TEST A: real repo is clean (all invoking workflows opus+effort) ==="
run "$repo_root"
assert "real repo exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
# Non-vacuity for TEST N on the real tree: the membership verdict is only
# meaningful if the canonical table was actually parsed.
assert "real repo rule table is present" "$(has_line "$OUT" 'RULE_TABLE=present')"
assert "real repo has no invoking workflow missing a table row" "$(has_line "$OUT" 'MISSING_TABLE_ROWS=0')"
a_rows=$(sed -n 's/^TABLE_ROWS=//p' <<<"$OUT")
assert "real repo table parses to >= 9 rows (got '${a_rows:-none}')" "$([ "${a_rows:-0}" -ge 9 ] 2>/dev/null && echo true || echo false)"

# --- TEST B: opus+effort claude_args fixture ---------------------------------
echo "=== TEST B: opus+effort claude_args exits 0 ==="
fx_b="$(mktemp -d)"
trap 'rm -rf "$fx_b" "${fx_c:-}" "${fx_d:-}" "${fx_e:-}" "${fx_f:-}" "${fx_g:-}" "${fx_h:-}" "${fx_i:-}" "${fx_j:-}" "${fx_k:-}" "${fx_l:-}"' EXIT
make_action_workflow "$fx_b/.github/workflows/good.yml" "--model opus --effort low --max-turns 25"
run "$fx_b"
assert "opus+effort fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "opus+effort fixture reports 1 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=1')"
assert "opus+effort fixture STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"

# --- TEST C: --model haiku ---------------------------------------------------
echo "=== TEST C: --model haiku exits 1 and is named ==="
fx_c="$(mktemp -d)"
make_action_workflow "$fx_c/.github/workflows/bad.yml" "--model haiku --max-turns 25"
run "$fx_c"
assert "haiku fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "haiku fixture names the file" "$(contains "$OUT" 'bad.yml')"
assert "haiku fixture reports MODEL=haiku" "$(contains "$OUT" 'MODEL=haiku')"
assert "haiku fixture TYPE=non_opus_model" "$(contains "$OUT" 'TYPE=non_opus_model')"

# --- TEST D: --model sonnet --------------------------------------------------
echo "=== TEST D: --model sonnet exits 1 and is named ==="
fx_d="$(mktemp -d)"
make_action_workflow "$fx_d/.github/workflows/legacy.yml" "--model sonnet --effort medium"
run "$fx_d"
assert "sonnet fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "sonnet fixture names the file" "$(contains "$OUT" 'legacy.yml')"
assert "sonnet fixture reports MODEL=sonnet" "$(contains "$OUT" 'MODEL=sonnet')"

# --- TEST E: opus WITHOUT --effort -------------------------------------------
echo "=== TEST E: opus without --effort exits 1 (missing_effort) ==="
fx_e="$(mktemp -d)"
make_action_workflow "$fx_e/.github/workflows/no-effort.yml" "--model opus --max-turns 25"
run "$fx_e"
assert "no-effort fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "no-effort fixture TYPE=missing_effort" "$(contains "$OUT" 'TYPE=missing_effort')"

# --- TEST F: CLI/npx form with --model haiku ---------------------------------
echo "=== TEST F: CLI form --model haiku exits 1 (second parser path) ==="
fx_f="$(mktemp -d)"
make_cli_workflow "$fx_f/.github/workflows/cli-bad.yml" haiku medium
run "$fx_f"
assert "CLI haiku fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "CLI haiku fixture reports MODEL=haiku" "$(contains "$OUT" 'MODEL=haiku')"

# --- TEST G: CLI/npx form with opus+effort -----------------------------------
echo "=== TEST G: CLI form opus+effort exits 0 ==="
fx_g="$(mktemp -d)"
make_cli_workflow "$fx_g/.github/workflows/cli-good.yml" opus medium
run "$fx_g"
assert "CLI opus+effort fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "CLI opus+effort fixture reports 1 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=1')"

# --- TEST H: no Claude invocation --------------------------------------------
echo "=== TEST H: no-invocation workflow not counted, exit 0 ==="
fx_h="$(mktemp -d)"
make_plain_workflow "$fx_h/.github/workflows/plain.yml"
run "$fx_h"
assert "plain fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "plain fixture reports 0 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=0')"
assert "plain fixture counts a skip" "$(contains "$OUT" 'SKIPPED_NO_INVOCATION=1')"

# --- TEST I: reusable-only workflow ------------------------------------------
echo "=== TEST I: reusable-only workflow skipped, exit 0 ==="
fx_i="$(mktemp -d)"
make_reusable_workflow "$fx_i/.github/workflows/reusable.yml"
run "$fx_i"
assert "reusable fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "reusable fixture reports 0 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=0')"
assert "reusable fixture counts a reusable skip" "$(contains "$OUT" 'SKIPPED_REUSABLE=1')"

# --- TEST J: invalid effort level --------------------------------------------
echo "=== TEST J: --effort bogus exits 1 (invalid_effort) ==="
fx_j="$(mktemp -d)"
make_action_workflow "$fx_j/.github/workflows/bogus.yml" "--model opus --effort bogus"
run "$fx_j"
assert "bogus-effort fixture exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "bogus-effort fixture TYPE=invalid_effort" "$(contains "$OUT" 'TYPE=invalid_effort')"

# --- TEST K: allowlist seam is honored ---------------------------------------
echo "=== TEST K: allowlisted file is honored ==="
fx_k="$(mktemp -d)"
make_action_workflow "$fx_k/.github/workflows/instrument.yml" "--model haiku"
k_out="$(CHECK_WORKFLOW_MODEL_ALLOWLIST='.github/workflows/instrument.yml' \
  bash "$checker" --project-dir "$fx_k" 2>&1)"
k_rc=$?
assert "allowlisted haiku workflow exits 0" "$([ "$k_rc" -eq 0 ] && echo true || echo false)"
assert "allowlisted file is not named as an error" "$([ "$(contains "$k_out" 'instrument.yml')" = "false" ] && echo true || echo false)"

# --- TEST L: prompt prose mentioning the flags must not false-positive --------
echo "=== TEST L: prompt prose documenting --model/--effort does not false-positive ==="
fx_l="$(mktemp -d)"
mkdir -p "$fx_l/.github/workflows"
cat > "$fx_l/.github/workflows/audit.yml" <<'EOF'
name: "Fixture: audit workflow"
on: { workflow_dispatch: {} }
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          claude_args: "--model opus --effort medium --max-turns 25"
          prompt: |
            Audit whether each workflow uses the right --model/--effort for its
            job. Recommend raising --effort to high, or lowering --effort to low.
EOF
run "$fx_l"
assert "prose-mentioning fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "prose-mentioning fixture STATUS=OK" "$(contains "$OUT" 'STATUS=OK')"
assert "prose-mentioning fixture counts 1 invoking" "$(contains "$OUT" 'INVOKING_WORKFLOWS=1')"

# --- TEST M: an unknown dash-argument is rejected, never swallowed ------------
# Before the fix, `--strict` fell through the parser's catch-all into
# explicit_files, so discovery was skipped, `[ -f "--strict" ]` skipped the one
# "file", and the gate printed WORKFLOWS_SCANNED=0 / STATUS=OK / exit 0. Both
# halves are asserted: the exit code AND that nothing was scanned, so a fix that
# merely accepts `--strict` as a no-op does not satisfy this case.
echo "=== TEST M: unknown dash-argument exits 2 and scans nothing ==="
m_out="$(bash "$checker" --strict 2>&1)"
m_rc=$?
assert "unknown --strict exits 2" "$([ "$m_rc" -eq 2 ] && echo true || echo false)"
assert "unknown --strict names the argument" "$(contains "$m_out" 'unknown argument: --strict')"
assert "unknown --strict prints usage" "$(contains "$m_out" 'Usage: check-workflow-model.sh')"
assert "unknown --strict emits no report" "$([ "$(contains "$m_out" 'WORKFLOWS_SCANNED=')" = "false" ] && echo true || echo false)"
assert "unknown --strict does not claim a pass" "$([ "$(contains "$m_out" 'STATUS=OK')" = "false" ] && echo true || echo false)"

# --project-dir without a directory is the same class (the value would shift).
m2_out="$(bash "$checker" --project-dir 2>&1)"
m2_rc=$?
assert "--project-dir with no value exits 2" "$([ "$m2_rc" -eq 2 ] && echo true || echo false)"
assert "--project-dir with no value names the flag" "$(contains "$m2_out" 'requires a directory')"
m3_out="$(bash "$checker" --project-dir "$repo_root/definitely-not-a-dir" 2>&1)"
m3_rc=$?
assert "--project-dir with a missing dir exits 2" "$([ "$m3_rc" -eq 2 ] && echo true || echo false)"
assert "--project-dir error names the flag" "$(contains "$m3_out" 'requires a directory')"

# GUARD INTEGRITY: rejecting dash-arguments must not break the pre-commit-style
# positional file form, nor `--help`. Without these, a checker that exited 2 on
# every invocation would satisfy every assertion above.
fx_m="$(mktemp -d)"
make_action_workflow "$fx_m/.github/workflows/good.yml" "--model opus --effort low"
m4_out="$(bash "$checker" "$fx_m/.github/workflows/good.yml" 2>&1)"
m4_rc=$?
assert "explicit positional file still exits 0" "$([ "$m4_rc" -eq 0 ] && echo true || echo false)"
assert "explicit positional file is still scanned" "$(contains "$m4_out" 'WORKFLOWS_SCANNED=1')"
assert "explicit positional file is still classified" "$(contains "$m4_out" 'INVOKING_WORKFLOWS=1')"
bash "$checker" --help >/dev/null 2>&1
m5_rc=$?
assert "--help exits 0" "$([ "$m5_rc" -eq 0 ] && echo true || echo false)"
# Explicit-file mode checks model/effort only: a pre-commit file list is not the
# set the table mirrors, and the real repo's table cannot be expected to name a
# fixture file. The skip is reported, never silent.
assert "explicit positional file skips table membership (reported)" "$(has_line "$m4_out" 'RULE_TABLE=skipped_explicit_files')"

# --- TEST N: canonical-table membership (#2630 Rec 2) ------------------------
echo "=== TEST N: every invoking workflow has a canonical-table row ==="
fx_n="$(mktemp -d)"
trap 'rm -rf "$fx_b" "${fx_c:-}" "${fx_d:-}" "${fx_e:-}" "${fx_f:-}" "${fx_g:-}" "${fx_h:-}" "${fx_i:-}" "${fx_j:-}" "${fx_k:-}" "${fx_l:-}" "${fx_m:-}" "${fx_n:-}"' EXIT
make_action_workflow "$fx_n/.github/workflows/good.yml" "--model opus --effort low"
make_action_workflow "$fx_n/.github/workflows/unlisted.yml" "--model opus --effort medium"
make_plain_workflow "$fx_n/.github/workflows/plain.yml"
make_reusable_workflow "$fx_n/.github/workflows/reusable.yml"

# N1: the #2630 shape — one invoking workflow listed, one not.
make_rule_table "$fx_n" '`good.yml`'
run "$fx_n"
assert "N1: unlisted invoking workflow exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "N1: TYPE=missing_table_row reported" "$(contains "$OUT" 'TYPE=missing_table_row')"
assert "N1: the unlisted file is named" "$(contains "$OUT" 'FILE=.github/workflows/unlisted.yml')"
assert "N1: the listed file is NOT named" "$([ "$(contains "$OUT" 'missing_table_row FILE=.github/workflows/good.yml')" = "false" ] && echo true || echo false)"
assert "N1: exactly one missing row counted" "$(has_line "$OUT" 'MISSING_TABLE_ROWS=1')"
assert "N1: table parsed (1 row)" "$(has_line "$OUT" 'TABLE_ROWS=1')"
# Non-invoking workflows mirror nothing in the table and must not be demanded.
assert "N1: no-invocation workflow not demanded" "$([ "$(contains "$OUT" 'FILE=.github/workflows/plain.yml')" = "false" ] && echo true || echo false)"
assert "N1: reusable-only workflow not demanded" "$([ "$(contains "$OUT" 'FILE=.github/workflows/reusable.yml')" = "false" ] && echo true || echo false)"

# N2: guard integrity — list both and the same fixture is clean.
make_rule_table "$fx_n" '`good.yml`' '`unlisted.yml` (CLI)'
run "$fx_n"
assert "N2: fully listed fixture exits 0" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "N2: MISSING_TABLE_ROWS=0" "$(has_line "$OUT" 'MISSING_TABLE_ROWS=0')"
assert "N2: a first cell carrying a trailing qualifier still counts (2 rows)" "$(has_line "$OUT" 'TABLE_ROWS=2')"

# N3: a mention OUTSIDE the first cell of a canonical-table row does not count:
# not in the rationale cell of a row whose first cell names no workflow, not in
# the first cell of a row in a DIFFERENT table, and not in prose. Each shape
# kills a distinct wrong implementation (whole-line match; no section bound;
# whole-file grep), so a row whose first cell already names some workflow would
# prove nothing — the leftmost token would be picked either way.
make_rule_table "$fx_n" '`good.yml`' '(external)'
sed -i.bak 's/^| (external) | `opus` \/ `low` | fixture row |$/| (external) | — | see `unlisted.yml` |/' "$fx_n/.claude/rules/workflow-model-effort.md"
rm -f "$fx_n/.claude/rules/workflow-model-effort.md.bak"
printf '\n## Another table\n\n| Workflow | Note |\n|---|---|\n| `unlisted.yml` | not the canonical table |\n\nProse naming `unlisted.yml` outside any table.\n' \
  >> "$fx_n/.claude/rules/workflow-model-effort.md"
if grep -qF 'see `unlisted.yml`' "$fx_n/.claude/rules/workflow-model-effort.md"; then n3_planted=true; else n3_planted=false; fi
assert "N3: fixture validity — the rationale-cell mention was planted" "$n3_planted"
run "$fx_n"
assert "N3: rationale-cell / other-table / prose mention does not satisfy membership" "$(contains "$OUT" 'FILE=.github/workflows/unlisted.yml')"
assert "N3: exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "N3: only the canonical first cell counted (1 row)" "$(has_line "$OUT" 'TABLE_ROWS=1')"

# N4: a rule file whose canonical table parses to ZERO rows is a misfire
# (renamed heading, reformatted table), never a clean pass.
mkdir -p "$fx_n/.claude/rules"
printf '# Workflow Model + Effort\n\n## Some other heading\n\n| Workflow | x |\n|---|---|\n| `good.yml` | y |\n' \
  > "$fx_n/.claude/rules/workflow-model-effort.md"
run "$fx_n"
assert "N4: unparsed table exits 1" "$([ "$RC" -eq 1 ] && echo true || echo false)"
assert "N4: TYPE=rule_table_unparsed reported" "$(contains "$OUT" 'TYPE=rule_table_unparsed')"
assert "N4: RULE_TABLE=unparsed" "$(has_line "$OUT" 'RULE_TABLE=unparsed')"

# N5: no rule file at all (every other fixture in this suite) — reported as
# absent, not treated as a violation.
rm -f "$fx_n/.claude/rules/workflow-model-effort.md"
run "$fx_n"
assert "N5: absent rule file does not fail membership" "$([ "$RC" -eq 0 ] && echo true || echo false)"
assert "N5: RULE_TABLE=absent reported" "$(has_line "$OUT" 'RULE_TABLE=absent')"

# --- Summary -----------------------------------------------------------------
echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
