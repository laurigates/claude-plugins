#!/usr/bin/env bash
# check-taskcompleted-verification.sh — semantic guard for the hooks-plugin
# TaskCompleted "Implementation Verification" agent-hook prompt.
#
# THE DEFECT THIS PINS (issue #2301)
# The prompt originally judged task completion by inspecting the WORKING TREE
# only. Work that had been committed and pushed therefore presented as no work
# at all, and the hook blocked `TaskUpdate status=completed` with "Agent hook
# condition was not met" — inverting the incentive it should create by
# penalising commit-early-keep-the-tree-clean. A second half: the scope check
# read raw `git status`, which cannot tell "this agent's unrelated changes" from
# "state that was already there", so 22 pre-existing modified files read as a
# scope violation.
#
# WHY A DEDICATED SCRIPT
# The artefact is a prompt string inside plugin.json, not a SKILL.md, so
# `plugin-compliance-check.sh` `check_skill_body()` (which iterates skill files)
# cannot reach it.
#
# WHY SEMANTIC, NOT A GREP FOR ONE PHRASE
# Per .claude/rules/regression-testing.md the invariant must survive a reword
# and fail on a revert. Each rule below is a CONCEPT with several accepted
# spellings — the load-bearing behaviours are: committed work counts as
# evidence (branch log + branch diff over a robustly-derived base), the clean
# tree + commits shape is success, the working-tree fallback survives for
# genuinely-unstarted tasks, scope is judged against the branch diff rather than
# raw `git status`, and the guard STILL blocks a task with no supporting change
# anywhere.
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#   --plugin-json PATH  file to inspect (default: hooks-plugin's plugin.json)
#   --strict            exit 1 when ISSUE_COUNT > 0 (for pre-commit / CI)
# Exit: 0 clean run (or non-strict with findings), 1 strict with findings,
#       2 unknown argument.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_JSON="$ROOT_DIR/hooks-plugin/.claude-plugin/plugin.json"
STRICT=0

usage() {
    cat <<'EOF'
Usage: check-taskcompleted-verification.sh [--plugin-json PATH] [--strict]

  --plugin-json PATH  plugin.json to inspect (default: hooks-plugin/.claude-plugin/plugin.json)
  --strict            exit 1 when ISSUE_COUNT > 0
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1 ;;
        --plugin-json)
            shift
            [ $# -gt 0 ] || { echo "check-taskcompleted-verification.sh: --plugin-json needs a value" >&2; usage >&2; exit 2; }
            PLUGIN_JSON="$1"
            ;;
        --plugin-json=*) PLUGIN_JSON="${1#--plugin-json=}" ;;
        -h|--help) usage; exit 0 ;;
        *)
            # Fail fast rather than swallowing a typo'd flag (issue #2057).
            echo "check-taskcompleted-verification.sh: unknown argument: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

issue_count=0
declare -a issues=()

add_issue() {
    issue_count=$((issue_count + 1))
    issues+=("  - SEVERITY=ERROR RULE=$1 MSG=$2")
}

emit() {
    local status="OK"
    [ "$issue_count" -gt 0 ] && status="ERROR"
    echo "=== TASKCOMPLETED VERIFICATION ==="
    echo "PLUGIN_JSON=${PLUGIN_JSON#"$ROOT_DIR"/}"
    echo "PROMPT_FOUND=${1:-false}"
    echo "PROMPT_CHARS=${2:-0}"
    echo "RULES_CHECKED=${3:-0}"
    echo "STATUS=$status"
    echo "ISSUE_COUNT=$issue_count"
    if [ "$issue_count" -gt 0 ]; then
        echo "ISSUES:"
        printf '%s\n' "${issues[@]}"
        echo ""
        echo "FIX: restore the committed-work consideration in the TaskCompleted"
        echo "     agent-hook prompt; see issue #2301 and .claude/rules/regression-testing.md"
    fi
    echo "=== END TASKCOMPLETED VERIFICATION ==="
    if [ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

if [ ! -f "$PLUGIN_JSON" ]; then
    add_issue "plugin_json_missing" "no such file: $PLUGIN_JSON"
    emit false 0 0
fi

prompt_file="$(mktemp)"
if [ -z "${prompt_file:-}" ] || [ ! -f "$prompt_file" ]; then
    echo "check-taskcompleted-verification.sh: mktemp failed" >&2
    exit 1
fi
trap 'rm -f "$prompt_file"' EXIT

# Extract the TaskCompleted type:"agent" prompt. A missing/duplicated/renamed
# hook is itself a finding, reported through the exit code below.
extract_rc=0
python3 - "$PLUGIN_JSON" >"$prompt_file" 2>/dev/null <<'PY' || extract_rc=$?
import json, sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)  # unparseable JSON

prompts = []
for block in (data.get("hooks") or {}).get("TaskCompleted") or []:
    for handler in block.get("hooks") or []:
        if handler.get("type") == "agent" and handler.get("prompt"):
            prompts.append(handler["prompt"])

if not prompts:
    sys.exit(4)  # no agent hook on TaskCompleted
sys.stdout.write("\n".join(prompts))
PY

case "$extract_rc" in
    0) ;;
    3) add_issue "plugin_json_unparseable" "plugin.json is not valid JSON"; emit false 0 0 ;;
    4) add_issue "agent_hook_missing" "TaskCompleted has no type:\"agent\" hook carrying a prompt"; emit false 0 0 ;;
    *) add_issue "extraction_failed" "could not extract the TaskCompleted agent prompt (rc=$extract_rc)"; emit false 0 0 ;;
esac

prompt_chars=$(wc -c <"$prompt_file" | tr -d ' ')
rules_checked=0

# require_any RULE MSG PATTERN... — pass when ANY alternative spelling matches.
# Alternatives are what make this a semantic gate: a reword that preserves the
# behaviour still matches; a revert that drops the behaviour matches none.
require_any() {
    local rule="$1" msg="$2"
    shift 2
    rules_checked=$((rules_checked + 1))
    local pattern
    for pattern in "$@"; do
        if grep -Eqi -- "$pattern" "$prompt_file"; then
            return 0
        fi
    done
    add_issue "$rule" "$msg"
}

# forbid_all RULE MSG PATTERN... — fail when ANY alternative matches.
forbid_all() {
    local rule="$1" msg="$2"
    shift 2
    rules_checked=$((rules_checked + 1))
    local pattern
    for pattern in "$@"; do
        if grep -Eqi -- "$pattern" "$prompt_file"; then
            add_issue "$rule" "$msg"
            return 0
        fi
    done
}

# --- Concept 1: committed work counts as evidence -------------------------
require_any "branch_log_inspection" \
    "prompt no longer inspects the commits the branch adds over its base (git log <base>..HEAD)" \
    'git log.*\.\.HEAD' \
    'git rev-list.*\.\.HEAD' \
    'git log[^|]*\$?\{?BASE'

require_any "committed_work_is_evidence" \
    "prompt no longer states that commits count as evidence of the work" \
    'evidence.*commit' \
    'commit.*(count|are|is).*evidence' \
    'may live in commits'

# --- Concept 2: the base ref is derived, never hardcoded -------------------
# BASE is the repository's DEFAULT branch. @{u} is deliberately NOT an accepted
# spelling here: on any pushed branch it resolves to origin/<this-branch>, so
# BASE..HEAD is empty and committed work vanishes — the #2301 defect itself.
require_any "base_ref_resolution" \
    "prompt no longer resolves the DEFAULT branch (symbolic-ref refs/remotes/origin/HEAD, or a rev-parse --verify probe)" \
    'symbolic-ref' \
    'refs/remotes/origin/HEAD' \
    'rev-parse --verify'

# The default branch alone is not the base: a branch cut long ago must be
# compared against its divergence point, not against today's default tip.
require_any "base_ref_merge_base" \
    "prompt no longer derives BASE from the divergence point (git merge-base) against the default branch" \
    'merge[- ]base' \
    'fork-point' \
    'divergence point'

require_any "base_ref_unresolved_path" \
    "prompt no longer says what to do when no base ref resolves" \
    'neither resolve' \
    'no base ref' \
    'no upstream' \
    '(cannot|can not|could not|does not|doesn.t) (be )?resolve'

# Only an UNCONDITIONAL base is forbidden: a bare `<branch>..HEAD` range, or a
# BASE assigned straight to a branch name with no ladder. A DOCUMENTED
# `git rev-parse --verify --quiet` probe of origin/main / origin/master is the
# correct engineering answer — origin/HEAD is unset in agent worktrees,
# --single-branch clones and CI checkouts — so a mere MENTION of those refs must
# not fire (that over-match blocked the #2301 repair itself).
forbid_all "base_ref_hardcoded" \
    "prompt hardcodes a base branch name; probe candidates with rev-parse --verify and take merge-base instead" \
    '(origin/)?(main|master)\.\.\.?HEAD' \
    'BASE=["'"'"']?(origin/)?(main|master)\b'

# @{u} is the branch's OWN remote counterpart, so BASE..HEAD is empty on any
# pushed branch. It may still appear as a NAMED anti-pattern (the corrected
# prompt cites it once, with the reason) — only its use AS the base fires.
forbid_all "base_ref_from_upstream" \
    "prompt derives BASE from @{u} (the branch's own remote counterpart); resolve the DEFAULT branch instead — see issue #2301" \
    'BASE=["'"'"']?\$\([^)]*@\{u\}' \
    'BASE=["'"'"']?@\{u\}' \
    '@\{u\}\)?\.\.\.?HEAD'

# --- Concept 3: clean tree + commits is the SUCCESS shape ------------------
require_any "clean_tree_is_success" \
    "prompt no longer frames a clean working tree plus branch commits as the success shape" \
    'clean [a-z ]*tree.*(success|not (the )?failure|never conclude|is not evidence|does not mean|no longer means)' \
    '(success|not (the )?failure).*clean [a-z ]*tree'

# --- Concept 4: working-tree fallback survives for unstarted tasks ---------
require_any "worktree_fallback_preserved" \
    "prompt no longer falls back to the working tree when the branch has no commits ahead of its base" \
    '(no|zero) commits (ahead|over)' \
    'nothing ahead' \
    '(fall|falls|falling) back to the working tree'

require_any "worktree_still_inspected" \
    "prompt no longer inspects the working tree at all" \
    'git status' \
    'working tree'

# --- Concept 5: scope is compared against the branch's own diff ------------
require_any "scope_against_branch_diff" \
    "scope check no longer compares against the branch diff (git diff <base>...HEAD)" \
    'scope.*(branch diff|\.\.\.HEAD)' \
    '(branch diff|\.\.\.HEAD).*scope'

require_any "scope_not_raw_status" \
    "scope check no longer says it is judged against something other than raw git status" \
    '(not|never|rather than|instead of)[^.]*git status'

require_any "preexisting_files_not_violations" \
    "prompt no longer exempts pre-existing / unrelated files from the scope check" \
    '(pre-existing|preexisting|unrelated|concurrent|outside)[^.]*not (a )?scope violation' \
    'not (a )?scope violation'

# --- Concept 6: the guard is NOT weakened ---------------------------------
require_any "still_blocks_without_evidence" \
    "prompt no longer blocks a task marked complete with no supporting change anywhere" \
    'no supporting change' \
    'neither commits[^.]*nor' \
    'no change(s)? (anywhere|at all)'

require_any "blocking_response_preserved" \
    "prompt no longer documents the blocking {\"ok\": false} response" \
    '"ok" *: *false'

emit true "$prompt_chars" "$rules_checked"
