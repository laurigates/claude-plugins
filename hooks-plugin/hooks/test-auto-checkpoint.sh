#!/usr/bin/env bash
# Regression tests for auto-checkpoint.sh (issue #2610)
#
# Run: bash hooks-plugin/hooks/test-auto-checkpoint.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers:
#   - Issue #2610: non-destructive stash creation preserving untracked files
#     and modified tracked files in the working directory
#   - Checkpoint stash created in `git stash list` before destructive operations
#   - Untracked files still exist and are never deleted
#   - Modified tracked files still exist with modifications intact
#   - CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 disables checkpoint creation
#   - Non-destructive commands (cat, git status) do not create a stash
#   - Clean working tree does not create a stash
#   - Other destructive commands trigger checkpointing (git reset, restore, etc.)
#   - Non-Bash tools are ignored
#   - Non-git directories degrade silently without error
#   - Build artifact deletion is exempt from checkpointing

set -euo pipefail

# Neutralize any inherited git context before building sandbox repos (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
      GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="${AUTO_CHECKPOINT_HOOK:-$HOOK_DIR/auto-checkpoint.sh}"
PASS=0
FAIL=0

SANDBOX=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$SANDBOX" ] || [ ! -d "$SANDBOX" ]; then
    echo "bad sandbox dir" >&2
    exit 1
fi

NON_GIT_DIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$NON_GIT_DIR" ] || [ ! -d "$NON_GIT_DIR" ]; then
    echo "bad non-git sandbox dir" >&2
    exit 1
fi

trap 'rm -rf "$SANDBOX" "$NON_GIT_DIR"' EXIT

pass() {
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s (%s)\n" "$1" "$2" >&2
}

# Initialize the test repo
init_repo() {
    git -C "$SANDBOX" init -q
    git -C "$SANDBOX" config commit.gpgsign false
    git -C "$SANDBOX" config user.email "test@example.com"
    git -C "$SANDBOX" config user.name "Test"
    echo "initial tracked content" > "$SANDBOX/tracked.txt"
    git -C "$SANDBOX" add tracked.txt
    git -C "$SANDBOX" commit -q -m "initial commit"
}

# Reset repo to dirty state: modified tracked file + untracked file, no stashes
setup_dirty_tree() {
    git -C "$SANDBOX" stash clear 2>/dev/null || true
    echo "initial tracked content" > "$SANDBOX/tracked.txt"
    git -C "$SANDBOX" add tracked.txt
    git -C "$SANDBOX" commit -q --amend -m "initial commit" 2>/dev/null || true
    echo "modified tracked content" >> "$SANDBOX/tracked.txt"
    echo "untracked content" > "$SANDBOX/untracked.txt"
}

# Run the hook inside a directory with given command and tool name
run_hook() {
    local dir="$1"
    local cmd="$2"
    local tool_name="${3:-Bash}"
    local json
    json=$(jq -nc --arg tn "$tool_name" --arg cmd "$cmd" \
        '{tool_name: $tn, tool_input: {command: $cmd}}')
    (cd "$dir" && printf '%s' "$json" | bash "$HOOK")
}

init_repo

echo "Running auto-checkpoint regression tests..."

# Test 1: Destructive command (rm -rf) creates checkpoint and preserves files
setup_dirty_tree
stderr_out=$(run_hook "$SANDBOX" "rm -rf dummy" "Bash" 2>&1)
exit_code=$?

if [ "$exit_code" -eq 0 ]; then
    pass "rm -rf exits 0"
else
    fail "rm -rf exits 0" "exited with $exit_code"
fi

stash_list=$(git -C "$SANDBOX" stash list)
if echo "$stash_list" | grep -q "auto-checkpoint before rm -rf"; then
    pass "rm -rf creates checkpoint stash in git stash list"
else
    fail "rm -rf creates checkpoint stash in git stash list" "stash list was: '$stash_list'"
fi

if echo "$stderr_out" | grep -q "Created checkpoint stash before rm -rf"; then
    pass "rm -rf prints checkpoint notice on stderr"
else
    fail "rm -rf prints checkpoint notice on stderr" "stderr was: '$stderr_out'"
fi

# Invariant: untracked files must still exist and be intact (issue #2610)
if [ -f "$SANDBOX/untracked.txt" ] && [ "$(< "$SANDBOX/untracked.txt")" = "untracked content" ]; then
    pass "untracked files still exist with intact content"
else
    fail "untracked files still exist with intact content" "file missing or content changed"
fi

# Invariant: modified tracked files must still have modifications intact
if grep -q "modified tracked content" "$SANDBOX/tracked.txt"; then
    pass "modified tracked files still exist with modifications"
else
    fail "modified tracked files still exist with modifications" "tracked file lost modifications"
fi

# Test 2: CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 disables checkpoint creation
setup_dirty_tree
CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 run_hook "$SANDBOX" "rm -rf dummy" "Bash" >/dev/null 2>&1 || true

stash_count=$(git -C "$SANDBOX" stash list | wc -l | tr -d ' ')
if [ "$stash_count" -eq 0 ]; then
    pass "CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 creates no stash"
else
    fail "CLAUDE_HOOKS_DISABLE_AUTO_CHECKPOINT=1 creates no stash" "found $stash_count stashes"
fi

# Test 3: Non-destructive command (cat file.txt) creates no stash
setup_dirty_tree
run_hook "$SANDBOX" "cat file.txt" "Bash" >/dev/null 2>&1 || true

stash_count=$(git -C "$SANDBOX" stash list | wc -l | tr -d ' ')
if [ "$stash_count" -eq 0 ]; then
    pass "cat file.txt creates no stash"
else
    fail "cat file.txt creates no stash" "found $stash_count stashes"
fi

# Test 4: Non-destructive command (git status) creates no stash
setup_dirty_tree
run_hook "$SANDBOX" "git status" "Bash" >/dev/null 2>&1 || true

stash_count=$(git -C "$SANDBOX" stash list | wc -l | tr -d ' ')
if [ "$stash_count" -eq 0 ]; then
    pass "git status creates no stash"
else
    fail "git status creates no stash" "found $stash_count stashes"
fi

# Test 5: Clean repository creates no stash
git -C "$SANDBOX" stash clear 2>/dev/null || true
rm -f "$SANDBOX/untracked.txt"
git -C "$SANDBOX" checkout -q -- "$SANDBOX/tracked.txt"
run_hook "$SANDBOX" "rm -rf dummy" "Bash" >/dev/null 2>&1 || true

stash_count=$(git -C "$SANDBOX" stash list | wc -l | tr -d ' ')
if [ "$stash_count" -eq 0 ]; then
    pass "clean repo creates no stash"
else
    fail "clean repo creates no stash" "found $stash_count stashes"
fi

# Test 6: Other destructive operations trigger checkpointing
# 6a: git reset
setup_dirty_tree
run_hook "$SANDBOX" "git reset --hard HEAD~1" "Bash" >/dev/null 2>&1 || true
if git -C "$SANDBOX" stash list | grep -q "auto-checkpoint before git reset"; then
    pass "git reset creates checkpoint stash"
else
    fail "git reset creates checkpoint stash" "stash list: $(git -C "$SANDBOX" stash list)"
fi

# 6b: git checkout -- <files>
setup_dirty_tree
run_hook "$SANDBOX" "git checkout -- tracked.txt" "Bash" >/dev/null 2>&1 || true
if git -C "$SANDBOX" stash list | grep -q "auto-checkpoint before git checkout file restore"; then
    pass "git checkout -- creates checkpoint stash"
else
    fail "git checkout -- creates checkpoint stash" "stash list: $(git -C "$SANDBOX" stash list)"
fi

# 6c: git restore <files>
setup_dirty_tree
run_hook "$SANDBOX" "git restore tracked.txt" "Bash" >/dev/null 2>&1 || true
if git -C "$SANDBOX" stash list | grep -q "auto-checkpoint before git restore"; then
    pass "git restore creates checkpoint stash"
else
    fail "git restore creates checkpoint stash" "stash list: $(git -C "$SANDBOX" stash list)"
fi

# 6d: git clean -f
setup_dirty_tree
run_hook "$SANDBOX" "git clean -fd" "Bash" >/dev/null 2>&1 || true
if git -C "$SANDBOX" stash list | grep -q "auto-checkpoint before git clean"; then
    pass "git clean -f creates checkpoint stash"
else
    fail "git clean -f creates checkpoint stash" "stash list: $(git -C "$SANDBOX" stash list)"
fi

# Test 7: Non-Bash tool is ignored
setup_dirty_tree
run_hook "$SANDBOX" "rm -rf dummy" "Read" >/dev/null 2>&1 || true
stash_count=$(git -C "$SANDBOX" stash list | wc -l | tr -d ' ')
if [ "$stash_count" -eq 0 ]; then
    pass "non-Bash tool (Read) creates no stash"
else
    fail "non-Bash tool (Read) creates no stash" "found $stash_count stashes"
fi

# Test 8: Non-git directory exits 0 cleanly without error
non_git_exit=0
run_hook "$NON_GIT_DIR" "rm -rf dummy" "Bash" >/dev/null 2>&1 || non_git_exit=$?
if [ "$non_git_exit" -eq 0 ]; then
    pass "non-git directory exits 0 cleanly"
else
    fail "non-git directory exits 0 cleanly" "exited with $non_git_exit"
fi

# Test 9: Build artifact deletion is exempt from checkpointing
setup_dirty_tree
run_hook "$SANDBOX" "rm -rf node_modules" "Bash" >/dev/null 2>&1 || true
stash_count=$(git -C "$SANDBOX" stash list | wc -l | tr -d ' ')
if [ "$stash_count" -eq 0 ]; then
    pass "rm -rf node_modules creates no stash"
else
    fail "rm -rf node_modules creates no stash" "found $stash_count stashes"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
