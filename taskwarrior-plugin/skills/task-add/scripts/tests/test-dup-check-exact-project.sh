#!/usr/bin/env bash
# test-dup-check-exact-project.sh — semantic regression test for the task-add
# skill's Step 3 duplicate check by bpid (issue #2951).
#
# Step 3 used to filter with `task project:myrepo bpid:"$BPID" export`. In
# taskwarrior, `project:` is a PREFIX match: `project:myrepo` also matches
# `myrepo-docs` and `myrepo.sub`. So a task already filed in a sibling project
# was reported as a duplicate of the one being filed, and the skill offered to
# "update instead of re-add" a task that belongs to a different repo.
#
# `bpid:` has the same shape — verified on 3.4.2, `bpid:WO-012` also returns
# `WO-0123` — so the same command reported a different work order as a duplicate.
#
# The fix matches both values EXACTLY in jq (`select(.bpid == $b and ... == $p)`),
# which works on every taskwarrior version. A grep for the new string would not prove it works
# (`.claude/rules/regression-testing.md` § semantic vs syntactic), so this test
# EXTRACTS the documented command from SKILL.md and from the quick-reference
# row and EXECUTES each one against a scratch store:
#   1. control: the old `project:myrepo bpid:...` form DOES return the
#      myrepo-docs task — the prefix behaviour this fix exists for is real
#   2. the documented command returns NOTHING for `myrepo` when the only
#      matching bpid lives in `myrepo-docs`
#   3. the documented command DOES return a real duplicate in `myrepo` (so a
#      command that always prints nothing cannot pass), with its uuid
#   4. with `--no-project` (empty $PROJECT) it matches a project-less task only
#   5. control + check for bpid: `bpid:WO-012` returns a `WO-0123` task, and
#      the documented command does not
#
# Requires the real `task` CLI; SKIPs cleanly when taskwarrior is unavailable so
# it degrades on a contributor's machine. CI builds Taskwarrior 3.x and lists
# this path in scripts/required-to-run-tests.txt, so a skip there fails the run.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="${SCRIPT_DIR}/../../SKILL.md"
QUICKREF_FILE="${SCRIPT_DIR}/../../references/quick-reference.md"

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

if ! command -v task >/dev/null 2>&1; then
    echo "SKIP: task CLI not available" >&2
    exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available" >&2
    exit 0
fi

# --- Extract the documented commands -----------------------------------------
#
# SKILL.md: the first line in the Step 3 section that runs `task` with the
# `bpid:"$BPID"` filter and `export`. Taken from the section rather than by an
# exact string, so the OLD prefix-match form is extracted (and then fails the
# semantic assertions) if it is ever restored.
skill_cmd="$(awk '
    /^### Step 3:/ { in_step = 1; next }
    in_step && /^### / { exit }
    in_step && /^task .*bpid:"\$BPID".* export/ { print; exit }
' "$SKILL_FILE")"
check "SKILL.md Step 3 documents a bpid duplicate-check command" "found" "${skill_cmd:+found}"

# quick-reference.md: the backticked command in the "Duplicate check by bpid"
# row, with the markdown table's `\|` escapes turned back into pipes. Its
# literal values are WO-012 / myrepo, which the fixtures below use too.
quickref_cmd="$(grep -m1 'Duplicate check by bpid' "$QUICKREF_FILE" \
    | awk -F'`' '{ print $2 }' | sed -e 's/\\|/|/g')"
check "quick-reference documents a bpid duplicate-check command" "found" "${quickref_cmd:+found}"

# --- Scratch store ------------------------------------------------------------
# Isolated — never touches the user's real taskwarrior data.
SCRATCH="$(mktemp -d)"
if [ -z "$SCRATCH" ] || [ ! -d "$SCRATCH" ]; then echo "mktemp failed" >&2; exit 1; fi
trap 'rm -rf "$SCRATCH"' EXIT
export TASKDATA="$SCRATCH" TASKRC="${SCRATCH}/.taskrc"
{
    printf 'data.location=%s\n' "$SCRATCH"
    printf 'uda.bpid.type=string\nuda.bpid.label=BPID\n'
} > "$TASKRC"

tw() { task rc.confirmation=no rc.verbose=nothing "$@" </dev/null >/dev/null 2>&1; }

# The only WO-012 task lives in a sibling project whose name starts with myrepo.
tw add "sibling docs task" project:myrepo-docs bpid:WO-012

run_doc() { # run_doc <command> <project> <bpid> — prints the command's output
    PROJECT="$2" BPID="$3" bash -c "$1" 2>/dev/null
}
count_rows() { # count JSON objects in jq's pretty-printed stream
    grep -c '"id"' || true
}

# 1. Control: the old prefix form really does see the sibling project's task.
old_hits="$(task project:myrepo bpid:WO-012 export 2>/dev/null | jq 'length')"
check "control: 'project:myrepo' prefix-matches myrepo-docs" "1" "${old_hits:-empty}"

# 2. The documented commands report no duplicate for myrepo.
check "SKILL.md: myrepo-docs task is not a duplicate for myrepo" \
    "0" "$(run_doc "$skill_cmd" myrepo WO-012 | count_rows)"
check "quick-reference: myrepo-docs task is not a duplicate for myrepo" \
    "0" "$(run_doc "$quickref_cmd" myrepo WO-012 | count_rows)"

# 3. A real duplicate in myrepo is still found, uuid included
#    (.claude/rules/task-id-stability.md — the uuid is the handle to act on).
tw add "real duplicate" project:myrepo bpid:WO-012
real_uuid="$(task rc.verbose=nothing +LATEST uuids 2>/dev/null)"
check "SKILL.md: real duplicate in myrepo is found" \
    "1" "$(run_doc "$skill_cmd" myrepo WO-012 | count_rows)"
check "quick-reference: real duplicate in myrepo is found" \
    "1" "$(run_doc "$quickref_cmd" myrepo WO-012 | count_rows)"
skill_uuid="$(run_doc "$skill_cmd" myrepo WO-012 | jq -r '.uuid // empty' 2>/dev/null)"
check "SKILL.md: duplicate report carries the task uuid" "$real_uuid" "${skill_uuid:-missing}"

# 4. --no-project: an empty $PROJECT matches only a project-less task.
tw add "cross-cutting task" bpid:WO-099
tw add "sibling with same bpid" project:myrepo-docs bpid:WO-099
check "SKILL.md: empty \$PROJECT matches the project-less task only" \
    "1" "$(run_doc "$skill_cmd" "" WO-099 | count_rows)"

# 5. bpid is matched exactly too: a WO-0123 task in myrepo is not a duplicate
#    of WO-012 (fresh bpid pair so earlier fixtures don't interfere).
tw add "longer work-order id" project:myrepo bpid:WO-2340
bpid_prefix_hits="$(task bpid:WO-234 export 2>/dev/null | jq 'length')"
check "control: 'bpid:WO-234' prefix-matches WO-2340" "1" "${bpid_prefix_hits:-empty}"
check "SKILL.md: WO-2340 task is not a duplicate of WO-234" \
    "0" "$(run_doc "$skill_cmd" myrepo WO-234 | count_rows)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
