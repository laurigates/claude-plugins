#!/usr/bin/env bash
# Regression test for inspect_eval.sh and its documented invocation in
# evaluate-matrix/SKILL.md.
#
# DEFECTS PINNED (docs/regression-ledger.md)
#   1. inspect_eval.sh counted `.cases | length`. No evals.json in this repo has
#      a `cases` key — the array is `.evals` (references/schemas.md) — so jq
#      evaluated `null | length` = 0 and NUM_CASES was 0 for every skill. The
#      evaluate-skill preflight and the verification gate both read that number.
#   2. evaluate-matrix/SKILL.md told the agent to run
#      `inspect_eval.sh --plugin-dir <plugin>/skills/<skill>`. --plugin-dir is
#      mode 1 (list a whole plugin) and looks for `<dir>/skills`, so a skill dir
#      reported SKILLS_DIR_EXISTS=false / STATUS=ERROR and never counted cases.
#      The single-skill form is `--plugin <plugin> --skill <skill>`.
#
# What this pins:
#   (a) NUM_CASES for git-plugin/skills/git-commit equals jq '.evals|length'
#       (computed at run time, so adding a case does not break the test)
#   (b) a fixture carrying a decoy `cases` key is counted from `.evals`
#   (c) a skill with no evals.json reports EVALS_JSON_EXISTS=false, NUM_CASES=0
#   (d) mode 1 (--plugin-dir <plugin>) still lists skills and evals
#   (e) mode 1 on a skill dir fails loudly (why defect 2 was a defect)
#   (f) evaluate-matrix/SKILL.md documents the single-skill form, and no
#       evaluate-plugin skill passes a `skills/` path to --plugin-dir
#
# Showing it red: INSPECT_EVAL overrides the script under test and
# EVAL_MATRIX_SKILL the SKILL.md, so the pre-fix versions can be run through
# this suite without touching the working tree:
#   git show origin/main:evaluate-plugin/scripts/inspect_eval.sh > /tmp/old.sh  # any pre-fix ref
#   INSPECT_EVAL=/tmp/old.sh bash evaluate-plugin/scripts/tests/test-inspect-eval.sh
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scripts_dir="$(dirname "$script_dir")"
plugin_root="$(dirname "$scripts_dir")"
repo_root="$(dirname "$plugin_root")"
inspect="${INSPECT_EVAL:-$scripts_dir/inspect_eval.sh}"
matrix_skill="${EVAL_MATRIX_SKILL:-$plugin_root/skills/evaluate-matrix/SKILL.md}"

fail_count=0
pass_count=0

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() {
  # field <output> <KEY>  -> prints the value after KEY=
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2-
}

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed"
  exit 0
fi

sandbox="$(mktemp -d)"
if [ -z "$sandbox" ] || [ ! -d "$sandbox" ]; then
  echo "FAIL: mktemp -d did not return a directory" >&2
  exit 1
fi
trap 'rm -rf "$sandbox"' EXIT

echo "=== TEST: git-commit NUM_CASES matches .evals length ==="
gc_evals="$repo_root/git-plugin/skills/git-commit/evals.json"
expected_gc="$(jq '.evals | length' "$gc_evals")"
gc_out="$(cd "$repo_root" && bash "$inspect" --plugin git-plugin --skill git-commit)"
check "(a) EVALS_JSON_EXISTS for git-commit" "true" "$(field "$gc_out" EVALS_JSON_EXISTS)"
check "(a) SKILL_MD_EXISTS for git-commit" "true" "$(field "$gc_out" SKILL_MD_EXISTS)"
check "(a) NUM_CASES == jq '.evals|length'" "$expected_gc" "$(field "$gc_out" NUM_CASES)"
check "(a) git-commit has at least one case (a 0 here is the defect)" "nonzero" \
  "$([ "${expected_gc:-0}" -gt 0 ] && echo nonzero || echo zero)"

echo "=== TEST: a decoy cases key is ignored ==="
mkdir -p "$sandbox/demo-plugin/skills/with-evals" "$sandbox/demo-plugin/skills/no-evals"
printf -- '---\nname: with-evals\n---\n' > "$sandbox/demo-plugin/skills/with-evals/SKILL.md"
printf -- '---\nname: no-evals\n---\n' > "$sandbox/demo-plugin/skills/no-evals/SKILL.md"
cat > "$sandbox/demo-plugin/skills/with-evals/evals.json" <<'EOF'
{
  "skill_name": "with-evals",
  "cases": [{"id": "decoy"}],
  "evals": [
    {"id": "e1", "prompt": "one", "expectations": []},
    {"id": "e2", "prompt": "two", "expectations": []},
    {"id": "e3", "prompt": "three", "expectations": []}
  ]
}
EOF
fx_out="$(cd "$sandbox" && bash "$inspect" --plugin demo-plugin --skill with-evals)"
check "(b) NUM_CASES counts .evals (3), not .cases (1)" "3" "$(field "$fx_out" NUM_CASES)"

print_out="$(cd "$sandbox" && bash "$inspect" --plugin demo-plugin --skill with-evals --print-evals)"
check "(b) --print-evals emits the === EVALS === block" "yes" \
  "$(grep -q '^=== EVALS ===$' <<<"$print_out" && echo yes || echo no)"

echo "=== TEST: a skill without evals.json ==="
ne_out="$(cd "$sandbox" && bash "$inspect" --plugin demo-plugin --skill no-evals)"
check "(c) EVALS_JSON_EXISTS=false" "false" "$(field "$ne_out" EVALS_JSON_EXISTS)"
check "(c) NUM_CASES=0" "0" "$(field "$ne_out" NUM_CASES)"

echo "=== TEST: mode 1 (--plugin-dir) still lists a plugin ==="
m1_out="$(cd "$repo_root" && bash "$inspect" --plugin-dir git-plugin)"
m1_rc=$?
expected_skills="$(find "$repo_root/git-plugin/skills" -maxdepth 3 -name SKILL.md | wc -l | tr -d ' ')"
expected_evals="$(find "$repo_root/git-plugin/skills" -maxdepth 3 -name evals.json | wc -l | tr -d ' ')"
check "(d) mode 1 exits 0" "0" "$m1_rc"
check "(d) SKILLS_DIR_EXISTS=true" "true" "$(field "$m1_out" SKILLS_DIR_EXISTS)"
check "(d) SKILL_COUNT matches the SKILL.md glob" "$expected_skills" "$(field "$m1_out" SKILL_COUNT)"
check "(d) EVALS_COUNT matches the evals.json glob" "$expected_evals" "$(field "$m1_out" EVALS_COUNT)"
check "(d) git-commit/evals.json is listed under === EVALS ===" "yes" \
  "$(grep -q 'git-commit/evals.json$' <<<"$m1_out" && echo yes || echo no)"

echo "=== TEST: mode 1 on a skill dir fails (the old matrix invocation) ==="
bad_out="$(cd "$repo_root" && bash "$inspect" --plugin-dir git-plugin/skills/git-commit)"
bad_rc=$?
check "(e) --plugin-dir <plugin>/skills/<skill> exits 1" "1" "$bad_rc"
check "(e) and reports STATUS=ERROR" "ERROR" "$(field "$bad_out" STATUS)"
check "(e) and never reports NUM_CASES" "" "$(field "$bad_out" NUM_CASES)"

echo "=== TEST: evaluate-matrix documents the single-skill form ==="
check "(f) evaluate-matrix uses --plugin <plugin> --skill <skill>" "yes" \
  "$(grep -qF 'inspect_eval.sh --plugin <plugin> --skill <skill>' "$matrix_skill" && echo yes || echo no)"
# No evaluate-plugin skill or workflow may hand a skills/ path to --plugin-dir.
misuse="$(grep -rnE 'inspect_eval\.sh --plugin-dir [^ `]*skills/' "$plugin_root/skills" || true)"
check "(f) no inspect_eval.sh --plugin-dir <...>/skills/ invocation" "" "$misuse"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=ERROR"
  exit 1
fi
echo "STATUS=OK"
