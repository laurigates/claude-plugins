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
# ONE PROMPT, NEVER A UNION (issue #2335)
# The rule set is evaluated against the VERIFIER prompt alone. Joining every
# TaskCompleted agent prompt into one blob before grepping (the pre-#2335 shape)
# let a token carried by ANY sibling hook satisfy a rule for ALL of them, so a
# fully-reverted verifier passed as long as some neighbour mentioned the words.
# The verifier is IDENTIFIED, never inferred: with one agent hook it is that
# hook; with several it is the one whose `statusMessage` matches
# VERIFIER_MARKER. Zero or several matches is itself a finding — the guard never
# guesses which prompt it is supposed to be pinning.
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

# The explicit verifier marker: a TaskCompleted agent hook whose `statusMessage`
# matches this (case-insensitively) declares itself the implementation verifier.
# `statusMessage` is a real, harness-honoured agent-hook field (see
# .claude/rules/prompt-agent-hooks.md), so this is a declaration the config
# already carries rather than a synthetic key invented for the guard.
VERIFIER_MARKER='verif'

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

# Identity of the prompt currently under evaluation. Every finding names it, so
# "which prompt failed" is answered in the report rather than inferred (#2335).
VERIFIER_ID="none"
VERIFIER_SOURCE="none"
AGENT_PROMPT_COUNT=0

add_issue() {
    issue_count=$((issue_count + 1))
    issues+=("  - SEVERITY=ERROR PROMPT=$VERIFIER_ID RULE=$1 MSG=$2")
}

emit() {
    local status="OK"
    [ "$issue_count" -gt 0 ] && status="ERROR"
    echo "=== TASKCOMPLETED VERIFICATION ==="
    echo "PLUGIN_JSON=${PLUGIN_JSON#"$ROOT_DIR"/}"
    echo "AGENT_PROMPT_COUNT=$AGENT_PROMPT_COUNT"
    echo "VERIFIER_ID=$VERIFIER_ID"
    echo "VERIFIER_SOURCE=$VERIFIER_SOURCE"
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

work_dir="$(mktemp -d)"
if [ -z "${work_dir:-}" ] || [ ! -d "$work_dir" ]; then
    echo "check-taskcompleted-verification.sh: mktemp -d failed" >&2
    exit 1
fi
trap 'rm -rf "$work_dir"' EXIT

# Extract EACH TaskCompleted type:"agent" prompt to its OWN file, plus an index
# of `<i><TAB><statusMessage>` rows. Writing them separately is what makes the
# per-prompt evaluation possible: there is no point at which the prompts are
# concatenated, so no sibling hook's vocabulary can satisfy a rule for the
# verifier (#2335 defect 2). A missing/duplicated/renamed hook is itself a
# finding, reported through the exit code below.
extract_rc=0
python3 - "$PLUGIN_JSON" "$work_dir" 2>/dev/null <<'PY' || extract_rc=$?
import json, os, sys

try:
    data = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(3)  # unparseable JSON

out_dir = sys.argv[2]
rows = []
for block in (data.get("hooks") or {}).get("TaskCompleted") or []:
    for handler in block.get("hooks") or []:
        if handler.get("type") == "agent" and handler.get("prompt"):
            idx = len(rows)
            with open(os.path.join(out_dir, "prompt-%d.txt" % idx), "w") as fh:
                fh.write(handler["prompt"])
            status_message = handler.get("statusMessage") or ""
            # Keep the index one row per prompt: a statusMessage carrying a tab
            # or a newline would otherwise shift or split the row.
            for ch in ("\t", "\r", "\n"):
                status_message = status_message.replace(ch, " ")
            rows.append("%d\t%s" % (idx, status_message))

if not rows:
    sys.exit(4)  # no agent hook on TaskCompleted
with open(os.path.join(out_dir, "index.tsv"), "w") as fh:
    fh.write("\n".join(rows) + "\n")
PY

case "$extract_rc" in
    0) ;;
    3) add_issue "plugin_json_unparseable" "plugin.json is not valid JSON"; emit false 0 0 ;;
    4) add_issue "agent_hook_missing" "TaskCompleted has no type:\"agent\" hook carrying a prompt"; emit false 0 0 ;;
    *) add_issue "extraction_failed" "could not extract the TaskCompleted agent prompts (rc=$extract_rc)"; emit false 0 0 ;;
esac

# --- Identify the verifier prompt: never inferred, never a union -------------
declare -a idx_list=() msg_list=()
while IFS=$'\t' read -r idx msg; do
    [ -n "${idx:-}" ] || continue
    idx_list+=("$idx")
    msg_list+=("${msg:-}")
done <"$work_dir/index.tsv"
AGENT_PROMPT_COUNT=${#idx_list[@]}

verifier_idx=""
if [ "$AGENT_PROMPT_COUNT" -eq 1 ]; then
    # Unambiguous: the only agent hook on the event IS the verifier.
    verifier_idx=0
    VERIFIER_SOURCE="sole-agent-hook"
    VERIFIER_ID="agent[0]"
else
    declare -a marked=()
    for i in "${!idx_list[@]}"; do
        if printf '%s' "${msg_list[$i]}" | grep -Eqi -- "$VERIFIER_MARKER"; then
            marked+=("$i")
        fi
    done
    case "${#marked[@]}" in
        1)
            verifier_idx="${marked[0]}"
            VERIFIER_SOURCE="statusMessage"
            VERIFIER_ID="agent[$verifier_idx]"
            ;;
        0)
            VERIFIER_ID="unidentified"
            add_issue "verifier_unidentified" \
                "TaskCompleted carries $AGENT_PROMPT_COUNT type:\"agent\" hooks and none declares itself the verifier; give the verifier a statusMessage matching /$VERIFIER_MARKER/i"
            emit true 0 0
            ;;
        *)
            VERIFIER_ID="ambiguous"
            add_issue "verifier_ambiguous" \
                "${#marked[@]} TaskCompleted type:\"agent\" hooks carry a statusMessage matching /$VERIFIER_MARKER/i; exactly one must"
            emit true 0 0
            ;;
    esac
fi

# From here on EVERY rule reads this one file — the verifier's prompt alone.
prompt_file="$work_dir/prompt-$verifier_idx.txt"
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

# `no upstream` was dropped as an accepted spelling (#2335 audit): it describes a
# DIFFERENT condition — the branch having no `@{u}`, which this prompt forbids
# using as the base at all — so a reword of the `@{u}` anti-pattern sentence
# ("if there is no upstream…") would satisfy this rule while the actual
# unresolved-base handling had been deleted. The surviving spellings all name
# the base ref itself.
require_any "base_ref_unresolved_path" \
    "prompt no longer says what to do when no base ref resolves" \
    'neither resolve' \
    'no base ref' \
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

# Anchored on the INSTRUCTION, not the vocabulary (issue #2335 defect 1). The
# pre-#2335 spellings were the bare tokens `git status` and `working tree`, both
# of which occur throughout the prompt in prose that is not the inspection step
# — including inside a NEGATION ("not raw git status") — so deleting the only
# real inspection step still passed. An accepted spelling must now be either a
# working-tree-scoped `git status` invocation (a porcelain/short flag: the
# machine-readable forms an instruction uses, which prose about the tree does
# not carry), or an imperative inspection verb bound to a `git status`/`git diff`
# call with no sentence boundary between them.
require_any "worktree_still_inspected" \
    "prompt no longer issues a working-tree inspection command (e.g. git status --porcelain / git diff --stat of the uncommitted state)" \
    'git status +(--porcelain|--short|-s|-uall|--untracked)' \
    '(inspect|inspects|examine|examines|review|reviews|read|reads|run|runs|check|checks|look at|looks at)[^.;]*\bgit (status|diff)\b'

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
