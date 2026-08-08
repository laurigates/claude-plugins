#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # file-level: SC2015 is the guarded-mktemp shape `check && check || abort` that check-git-sandbox-guards.sh mandates; SC2016 is deliberate — mutation `sed` expressions must carry a literal $(…) / @{u}, not an expansion.
# Regression tests for scripts/check-taskcompleted-verification.sh (issue #2301).
#
# The guard pins that the hooks-plugin TaskCompleted agent-hook prompt still
# considers COMMITTED work as evidence (branch log + branch diff over a derived
# base), still frames "clean tree + commits" as success, still compares scope
# against the branch diff rather than raw `git status`, and still BLOCKS a task
# with no supporting change anywhere.
#
# These tests are SEMANTIC, not syntactic (.claude/rules/regression-testing.md):
#   * TEST B runs the guard against the VERBATIM pre-fix prompt and requires the
#     load-bearing rules to fire.
#   * TEST C is the reword-tolerance half — a differently-worded prompt carrying
#     the same behaviours must PASS, proving the guard is not a grep for one
#     incidental phrase.
#   * TESTS D-H mutate one behaviour at a time out of the fixed prompt and
#     require exactly the matching rule to fire.
#
# Run: bash scripts/tests/test-check-taskcompleted-verification.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
GUARD="$SCRIPTS_DIR/check-taskcompleted-verification.sh"
REAL_JSON="$REPO_ROOT/hooks-plugin/.claude-plugin/plugin.json"

PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

ok() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# make_fixture NAME PROMPT_FILE -> path to a plugin.json carrying that prompt.
make_fixture() {
    local name="$1" prompt_path="$2" out="$WORK/$1.json"
    FIXTURE_PROMPT_PATH="$prompt_path" FIXTURE_OUT="$out" FIXTURE_SRC="$REAL_JSON" \
    python3 - <<'PY'
import json, os

data = json.load(open(os.environ["FIXTURE_SRC"]))
prompt = open(os.environ["FIXTURE_PROMPT_PATH"]).read()
for block in data["hooks"]["TaskCompleted"]:
    for handler in block["hooks"]:
        if handler.get("type") == "agent":
            handler["prompt"] = prompt
json.dump(data, open(os.environ["FIXTURE_OUT"], "w"), indent=2)
PY
    echo "$out"
}

run_guard() { bash "$GUARD" --plugin-json "$1" 2>&1; }

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then ok "$desc"; else
        bad "$desc (missing '$needle')"
    fi
}

assert_lacks() {
    local desc="$1" needle="$2" haystack="$3"
    if printf '%s\n' "$haystack" | grep -qF -- "$needle"; then
        bad "$desc (unexpectedly found '$needle')"
    else ok "$desc"; fi
}

assert_exit() {
    local desc="$1" expected="$2"
    shift 2
    "$@" >/dev/null 2>&1
    local got=$?
    if [ "$got" = "$expected" ]; then ok "$desc"; else bad "$desc (exit $got, wanted $expected)"; fi
}

# ---------------------------------------------------------------------------
echo "TEST A: the real repo passes, and the run is not vacuous"
# ---------------------------------------------------------------------------
out=$(run_guard "$REAL_JSON")
assert_contains "A1: real plugin.json STATUS=OK" "STATUS=OK" "$out"
assert_contains "A2: real plugin.json ISSUE_COUNT=0" "ISSUE_COUNT=0" "$out"
# Guard integrity: without these, every "no issues" assertion below is vacuous.
assert_contains "A3: the agent prompt was actually found" "PROMPT_FOUND=true" "$out"
assert_contains "A4: 15 concept rules ran" "RULES_CHECKED=15" "$out"
assert_exit "A5: real plugin.json exits 0 under --strict" 0 \
    bash "$GUARD" --plugin-json "$REAL_JSON" --strict

# ---------------------------------------------------------------------------
echo "TEST B: the VERBATIM pre-fix prompt is caught"
# ---------------------------------------------------------------------------
cat > "$WORK/prefix.txt" <<'EOF'
You are verifying that a completed task meets quality standards before accepting it. Context: $ARGUMENTS

1. Run git diff --stat to see what files were changed
2. For each changed source file, search for TODO/FIXME/HACK comments that may indicate unfinished work
3. Check that no debugging artifacts remain (stray console.log, print() statements, debugger keywords)
4. If the task involved adding new functionality, check if test files exist nearby or were updated
5. Verify the changes are consistent with the task description

Respond with {"ok": true} if the implementation looks complete and clean, or {"ok": false, "reason": "specific issues found"} if problems remain.
EOF
prefix_json=$(make_fixture prefix "$WORK/prefix.txt")
out=$(run_guard "$prefix_json")
assert_contains "B1: pre-fix prompt STATUS=ERROR" "STATUS=ERROR" "$out"
assert_contains "B2: pre-fix names branch_log_inspection" "RULE=branch_log_inspection" "$out"
assert_contains "B3: pre-fix names committed_work_is_evidence" "RULE=committed_work_is_evidence" "$out"
assert_contains "B4: pre-fix names base_ref_resolution" "RULE=base_ref_resolution" "$out"
assert_contains "B5: pre-fix names clean_tree_is_success" "RULE=clean_tree_is_success" "$out"
assert_contains "B6: pre-fix names scope_against_branch_diff" "RULE=scope_against_branch_diff" "$out"
assert_contains "B7: pre-fix names preexisting_files_not_violations" "RULE=preexisting_files_not_violations" "$out"
assert_exit "B8: pre-fix prompt exits 1 under --strict" 1 \
    bash "$GUARD" --plugin-json "$prefix_json" --strict

# ---------------------------------------------------------------------------
echo "TEST C: reword tolerance — same behaviours, different words, still passes"
# ---------------------------------------------------------------------------
# This is the semantic half. Every sentence below is worded differently from the
# shipped prompt; a guard that grepped for one incidental phrase would fail here.
cat > "$WORK/reword.txt" <<'EOF'
Decide whether a finished task is acceptable. Context: $ARGUMENTS

Committed work counts as evidence. A clean tree on a branch holding commits is a success, not a failure.

Find the repository's default branch: git symbolic-ref --short refs/remotes/origin/HEAD, or failing that probe origin/main and origin/master with git rev-parse --verify --quiet. BASE is the divergence point of HEAD and that branch. When neither resolves, review the uncommitted state alone.
Read git rev-list --oneline BASE..HEAD to see what the branch adds; if it has zero commits over its base, review the working tree instead.
Also read git status --porcelain for uncommitted edits.
Measure scope from the branch diff, git diff --name-only BASE...HEAD, never from raw git status; files it does not list were already there and are not scope violations.
Then look for TODO/FIXME markers, stray debug statements, and missing tests in that set.

Refuse only when the work has real defects, or when there is no change at all - no commits over the base and no edits in the tree.
Answer {"ok": true} when acceptable, else {"ok": false, "reason": "..."}.
EOF
reword_json=$(make_fixture reword "$WORK/reword.txt")
out=$(run_guard "$reword_json")
assert_contains "C1: reworded prompt STATUS=OK" "STATUS=OK" "$out"
assert_contains "C2: reworded prompt ISSUE_COUNT=0" "ISSUE_COUNT=0" "$out"

# ---------------------------------------------------------------------------
echo "TEST D-H: one behaviour removed at a time from the shipped prompt"
# ---------------------------------------------------------------------------
# Start from the real prompt and mutate it, so each case isolates one behaviour.
python3 - "$REAL_JSON" > "$WORK/shipped.txt" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for block in data["hooks"]["TaskCompleted"]:
    for handler in block["hooks"]:
        if handler.get("type") == "agent":
            sys.stdout.write(handler["prompt"])
PY

mutate() { # mutate NAME SED_EXPR
    local name="$1" expr="$2"
    sed -E "$expr" "$WORK/shipped.txt" > "$WORK/$name.txt"
    make_fixture "$name" "$WORK/$name.txt"
}

# D: drop the branch-log/branch-diff inspection line entirely.
d_json=$(mutate nobranchlog '/git log --oneline/d')
out=$(run_guard "$d_json")
assert_contains "D1: dropping the branch log fires branch_log_inspection" \
    "RULE=branch_log_inspection" "$out"

# E: hardcode the base branch instead of deriving it.
e_json=$(mutate hardcodedbase 's#BASE\.\.HEAD#origin/main..HEAD#g')
out=$(run_guard "$e_json")
assert_contains "E1: hardcoding origin/main fires base_ref_hardcoded" \
    "RULE=base_ref_hardcoded" "$out"
assert_exit "E2: hardcoded base exits 1 under --strict" 1 \
    bash "$GUARD" --plugin-json "$e_json" --strict

# E3-E8 pin the BASE-resolution rules against the #2301 repair itself. The
# pre-repair rules matched `origin/(main|master)` ANYWHERE and accepted `@{u}`
# as a valid derivation — so they blocked the corrected prompt while still
# passing the defective one. These cases pin both polarities.

# E3 guard integrity: a DOCUMENTED `rev-parse --verify` probe of origin/main /
# origin/master is the correct fallback (origin/HEAD is unset in agent
# worktrees, --single-branch clones and CI checkouts), not a hardcoded base.
real_out=$(run_guard "$REAL_JSON")
assert_lacks "E3: a documented origin/main probe is not a hardcoded base" \
    "RULE=base_ref_hardcoded" "$real_out"

# E4: a BASE assigned straight to a branch name, with no ladder, still fires.
e4_json=$(mutate uncondbase 's#BASE=\$\(git merge-base HEAD <default-branch>\)#BASE=origin/main#')
out=$(run_guard "$e4_json")
assert_contains "E4: an unconditional BASE=origin/main fires base_ref_hardcoded" \
    "RULE=base_ref_hardcoded" "$out"

# E5: @{u} used AS the base is the #2301 defect itself — on any pushed branch it
# resolves to origin/<this-branch>, so BASE..HEAD is empty and commits vanish.
e5_json=$(mutate upstreambase 's#BASE=\$\(git merge-base HEAD <default-branch>\)#BASE=$(git rev-parse --abbrev-ref @{u})#')
out=$(run_guard "$e5_json")
assert_contains "E5: deriving BASE from @{u} fires base_ref_from_upstream" \
    "RULE=base_ref_from_upstream" "$out"

# E6 guard integrity: the corrected prompt NAMES @{u} once as an anti-pattern,
# so a rule that merely greps for @{u} would fire on the correct prompt.
assert_lacks "E6: naming @{u} as an anti-pattern does not fire base_ref_from_upstream" \
    "RULE=base_ref_from_upstream" "$real_out"

# E7: @{u} as the range endpoint is the same defect in its other spelling.
e7_json=$(mutate upstreamrange 's#BASE\.\.HEAD#@{u}..HEAD#g')
out=$(run_guard "$e7_json")
assert_contains "E7: an @{u}..HEAD range fires base_ref_from_upstream" \
    "RULE=base_ref_from_upstream" "$out"

# E8: @{u} must NOT satisfy base_ref_resolution — accepting it as a valid
# derivation is precisely what let the defective prompt pass the guard.
e8_json=$(mutate upstreamonly 's#git symbolic-ref --short refs/remotes/origin/HEAD#git rev-parse --abbrev-ref --symbolic-full-name @\{u\}#; s#rev-parse --verify --quiet#rev-parse --abbrev-ref#g; s#--verify --quiet#--abbrev-ref#g')
out=$(run_guard "$e8_json")
assert_contains "E8: @{u} alone does not satisfy base_ref_resolution" \
    "RULE=base_ref_resolution" "$out"

# E9: dropping merge-base leaves BASE at the default branch TIP, not the
# divergence point — a long-lived branch would then diff against unrelated work.
e9_json=$(mutate nomergebase 's#\$\(git merge-base HEAD <default-branch>\)#<default-branch>#')
out=$(run_guard "$e9_json")
assert_contains "E9: dropping merge-base fires base_ref_merge_base" \
    "RULE=base_ref_merge_base" "$out"

# F: drop the "clean tree + commits = success" framing.
f_json=$(mutate nocleanframe '/is the success shape/d')
out=$(run_guard "$f_json")
assert_contains "F1: dropping the framing fires clean_tree_is_success" \
    "RULE=clean_tree_is_success" "$out"
# Guard integrity: the mutation is surgical, so the branch-log rule still passes.
assert_lacks "F2: the branch-log rule is unaffected by the framing mutation" \
    "RULE=branch_log_inspection" "$out"

# G: revert the scope check to raw git status.
g_json=$(mutate rawstatusscope '/^Scope:/d')
out=$(run_guard "$g_json")
assert_contains "G1: dropping the scope paragraph fires scope_against_branch_diff" \
    "RULE=scope_against_branch_diff" "$out"
assert_contains "G2: dropping the scope paragraph fires preexisting_files_not_violations" \
    "RULE=preexisting_files_not_violations" "$out"

# H: WEAKENING — remove the "block when there is no change anywhere" clause.
h_json=$(mutate weakened '/^Withhold completion when/d')
out=$(run_guard "$h_json")
assert_contains "H1: removing the no-evidence block fires still_blocks_without_evidence" \
    "RULE=still_blocks_without_evidence" "$out"

# I: dropping the working-tree fallback (would break genuinely-unstarted tasks).
i_json=$(mutate nofallback 's/ If the branch has no commits ahead of BASE, fall back to the working tree\.//')
out=$(run_guard "$i_json")
assert_contains "I1: dropping the fallback fires worktree_fallback_preserved" \
    "RULE=worktree_fallback_preserved" "$out"

# ---------------------------------------------------------------------------
echo "TEST J: structural failures are reported, not silently passed"
# ---------------------------------------------------------------------------
python3 - "$REAL_JSON" "$WORK/noagent.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for block in data["hooks"]["TaskCompleted"]:
    block["hooks"] = [h for h in block["hooks"] if h.get("type") != "agent"]
json.dump(data, open(sys.argv[2], "w"), indent=2)
PY
out=$(run_guard "$WORK/noagent.json")
assert_contains "J1: a removed agent hook is reported" "RULE=agent_hook_missing" "$out"
assert_contains "J2: a removed agent hook reports PROMPT_FOUND=false" "PROMPT_FOUND=false" "$out"

printf 'not json {' > "$WORK/broken.json"
out=$(run_guard "$WORK/broken.json")
assert_contains "J3: unparseable JSON is reported" "RULE=plugin_json_unparseable" "$out"

out=$(run_guard "$WORK/does-not-exist.json")
assert_contains "J4: a missing file is reported" "RULE=plugin_json_missing" "$out"

assert_exit "J5: an unknown argument exits 2 rather than being swallowed" 2 \
    bash "$GUARD" --strictt

echo ""
echo "PASSED=$PASS FAILED=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
