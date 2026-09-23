#!/usr/bin/env bash
# shellcheck disable=SC2016   # single quotes are the point: every fixture is the
# LITERAL text a user typed, handed to the hook unexpanded. Letting the harness
# expand `$T` or `$(…)` would test this shell, not the hook.
# Regression tests for auto-checkpoint.sh (issues #2610, #2652)
#
# Run: bash hooks-plugin/hooks/test-auto-checkpoint.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# #2652 sections (below the #2610 block), all driving the SHIPPED hook:
#   A. False positives from the issue thread create NO stash — an out-of-repo
#      `rm -rf`, a `gh issue comment --body` / `--body-file` heredoc quoting the
#      pattern, `echo`/`grep`/`git commit` carrying it — each beside an in-repo
#      control that MUST still checkpoint.
#   B. A GENERIC spelling probe: variants of every destructive base are
#      generated mechanically (program spelling, prefix wrapper, rm flag
#      spelling, git global options, shell-string wrapper, shell context) and
#      every one must checkpoint. Hand-enumerated spellings are what let five
#      earlier attempts ship a fail-open (`\rm`, `bash --norc -c`, …).
#   C. A DIFFERENTIAL: the same set runs through every baseline — the hook's own
#      no-parser path, and `git show <ref>:…` for HEAD and the pinned pre-#2652
#      commit when those objects exist and differ — and a spelling any baseline
#      checkpoints but the hook skips fails the suite.
#   D. Fail-safe polarity: with ast-grep hidden or broken, the old matcher still
#      decides, so an in-repo `rm -rf` still checkpoints.
#   E. The allow path exits 0 under macOS's /bin/bash 3.2.
#
# Without a working ast-grep, A-C and the parser half of D cannot run: the
# #2610 block and the no-parser polarity still run, and the suite ends on a
# single SKIP line so scripts/run-skill-script-tests.sh counts it as skipped —
# which is an error there, because this suite is listed in
# scripts/required-to-run-tests.txt.
#
# Covers (#2610):
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

# Every progress line is indented: when ast-grep is absent the suite must end on
# a SKIP line that is its only unindented output (see the header).
echo "  Running auto-checkpoint regression tests..."

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

# ═════════════════════════════════════════════════════════════════════════════
# #2652 — command-position parsing, operand locality, and the fail-safe floor
# ═════════════════════════════════════════════════════════════════════════════

# The pre-#2652 hook: the commit that last touched it before the fix (#2641).
PINNED_BASELINE_REF=834c2adf59c87f56a7979c742863dfbf3403a683

HAVE_WORKING_ASTGREP=false
if command -v ast-grep >/dev/null 2>&1; then
    HAVE_WORKING_ASTGREP=true
elif command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'; then
    HAVE_WORKING_ASTGREP=true
fi

# A dirty sandbox for everything below: a modified tracked file, an untracked
# file, and an untracked src/ directory (the symlink case needs a real
# directory to point at).
setup_dirty_tree
mkdir -p "$SANDBOX/src"
echo "source" > "$SANDBOX/src/main.txt"
SANDBOX_NAME=$(basename "$SANDBOX")

stash_count() { git -C "$SANDBOX" stash list | wc -l | tr -d ' '; }

# Run one command through a hook file inside repo $1. Sets VERDICT
# (CHECKPOINT|skip, read off the hook's own notice) and LAST_RC. Extra
# arguments are env assignments. `@TOP@` in the command becomes the repo path,
# so an absolute in-repo spelling follows whichever sandbox runs it.
#
# Every run first writes a fresh value into the TRACKED file. Two identical
# `git stash create` calls in the same second produce the SAME commit, and
# `git stash store` of the commit refs/stash already points at adds no entry —
# which reads as "no checkpoint" to a stash count. An untracked file does not
# help: `git stash create` leaves untracked content out of the commit.
VERDICT=""
LAST_RC=0
RUN_SEQ=0
run_verdict_in() {
    local repo=$1 hook=$2 cmd=$3 json out
    shift 3
    cmd=${cmd//@TOP@/$repo}
    RUN_SEQ=$((RUN_SEQ + 1))
    echo "modified tracked content $RUN_SEQ" > "$repo/tracked.txt"
    json=$(jq -nc --arg c "$cmd" '{tool_name: "Bash", tool_input: {command: $c}}')
    LAST_RC=0
    out=$(cd "$repo" && printf '%s' "$json" | env "$@" "${BASH_BIN:-bash}" "$hook" 2>&1) || LAST_RC=$?
    if grep -q 'Created checkpoint stash before' <<<"$out"; then VERDICT=CHECKPOINT; else VERDICT=skip; fi
}
run_verdict() {
    run_verdict_in "$SANDBOX" "$@"
}

# Assert on the ground truth — a stash entry appeared or not — and on exit 0.
expect() { # $1 = CHECKPOINT|skip, $2 = label, $3 = command, rest = env assignments
    local want=$1 label=$2 cmd=$3 before after got
    shift 3
    before=$(stash_count)
    run_verdict "$HOOK" "$cmd" "$@"
    after=$(stash_count)
    if [ "$after" -gt "$before" ]; then got=CHECKPOINT; else got=skip; fi
    if [ "$LAST_RC" -ne 0 ]; then
        fail "$label" "hook exited $LAST_RC"
    elif [ "$got" = "$want" ]; then
        pass "$label"
    else
        fail "$label" "expected $want, got $got for: $(printf '%s' "$cmd" | tr '\n' '~')"
    fi
}

echo "  == D. fail-safe polarity: no parser, or a broken one, falls back to the old matcher =="

NOPARSE=CLAUDE_HOOKS_AUTO_CHECKPOINT_NO_ASTGREP=1
expect CHECKPOINT "no parser: in-repo rm -rf ./src still checkpoints" \
    'rm -rf ./src' "$NOPARSE"
expect CHECKPOINT "no parser: out-of-repo rm -rf over-checkpoints, as before #2652" \
    'rm -rf /tmp/scratch-2652' "$NOPARSE"
expect CHECKPOINT "no parser: pattern quoted in a gh body over-checkpoints, as before #2652" \
    "gh issue comment 1 --body 'we should stop matching rm -rf /tmp/foo in command text'" "$NOPARSE"
expect CHECKPOINT "no parser: git checkout -- still checkpoints" \
    'git checkout -- tracked.txt' "$NOPARSE"

# A parser that fails, answers nothing, or answers garbage must degrade to the
# old matcher, never to silence. Each fake is made executable and confirmed to
# be the ast-grep the hook will find, so a green row cannot mean the real
# parser ran instead.
FAKE_ROOT=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$FAKE_ROOT" ] || [ ! -d "$FAKE_ROOT" ]; then
    echo "bad fake-parser dir" >&2
    exit 1
fi
trap 'rm -rf "$SANDBOX" "$NON_GIT_DIR" "$FAKE_ROOT"' EXIT
for fake_kind in exit2 empty-array garbage; do
    mkdir -p "$FAKE_ROOT/$fake_kind"
    case $fake_kind in
        exit2) printf '#!/usr/bin/env bash\nexit 2\n' > "$FAKE_ROOT/$fake_kind/ast-grep" ;;
        empty-array) printf '#!/usr/bin/env bash\ncat >/dev/null\necho "[]"\n' > "$FAKE_ROOT/$fake_kind/ast-grep" ;;
        garbage) printf '#!/usr/bin/env bash\ncat >/dev/null\necho "{not json"\n' > "$FAKE_ROOT/$fake_kind/ast-grep" ;;
    esac
    chmod +x "$FAKE_ROOT/$fake_kind/ast-grep"
    resolved=$(PATH="$FAKE_ROOT/$fake_kind:$PATH" command -v ast-grep)
    if [ "$resolved" != "$FAKE_ROOT/$fake_kind/ast-grep" ]; then
        fail "broken parser ($fake_kind): the fake is the ast-grep on PATH" "resolved to $resolved"
        continue
    fi
    expect CHECKPOINT "broken parser ($fake_kind): in-repo rm -rf ./src still checkpoints" \
        'rm -rf ./src' "PATH=$FAKE_ROOT/$fake_kind:$PATH"
    expect CHECKPOINT "broken parser ($fake_kind): out-of-repo rm -rf falls back to the old matcher" \
        'rm -rf /tmp/scratch-2652' "PATH=$FAKE_ROOT/$fake_kind:$PATH"
    expect CHECKPOINT "broken parser ($fake_kind): git reset --hard still checkpoints" \
        'git reset --hard' "PATH=$FAKE_ROOT/$fake_kind:$PATH"
done

if [ "$HAVE_WORKING_ASTGREP" = false ]; then
    echo "  Results: $PASS passed, $FAIL failed (parser sections not run)"
    if [ "$FAIL" -gt 0 ]; then
        exit 1
    fi
    echo "SKIP: no working ast-grep on PATH; the #2652 parser sections (A, B, C, the parser half of D, E) require it."
    echo "      Install: npm install -g @ast-grep/cli   (CI pins @ast-grep/cli@0.43.0)"
    exit 0
fi

expect skip "parser present: out-of-repo rm -rf is skipped (the parser path is live)" \
    'rm -rf /tmp/scratch-2652'

echo "  == A. false positives from the #2652 thread, each beside an in-repo control =="

# Out-of-repo deletions (repros 1 and 2)
expect skip "out-of-repo literal: rm -rf /tmp/scratch-2652" 'rm -rf /tmp/scratch-2652'
expect CHECKPOINT "  control: rm -rf ./src" 'rm -rf ./src'
expect skip "out-of-repo literal under /private/tmp" 'rm -rf /private/tmp/scratch-2652'
expect skip "out-of-repo quoted /var/folders literal (repro 2's mktemp path)" \
    'rm -rf "/var/folders/xx/T/tmp.abc123"'
expect skip "out-of-repo real sibling directory, quoted literal" "rm -rf \"$NON_GIT_DIR/scratch\""
expect skip "out-of-repo glob under a sibling directory" "rm -rf $NON_GIT_DIR/scratch-*"
expect skip "two out-of-repo operands" 'rm -rf /tmp/scratch-a /private/tmp/scratch-b'
expect skip "out-of-repo rm with a redirect" 'rm -rf /tmp/scratch-2652 2>/dev/null'
expect skip "out-of-repo rm, then echo" 'rm -rf /tmp/scratch-2652 && echo done'
expect skip "out-of-repo rm with a trailing comment naming ./src" 'rm -rf /tmp/scratch-2652 # not ./src'
expect skip "git -C another directory is not this repository" "git -C \"$NON_GIT_DIR\" reset --hard"
expect CHECKPOINT "  control: rm -rf dummy" 'rm -rf dummy'
expect CHECKPOINT "  control: absolute path inside the repository" "rm -rf \"$SANDBOX/src\""
expect CHECKPOINT "  control: the repository toplevel itself" "rm -rf \"$SANDBOX\""
expect CHECKPOINT "  control: an ANCESTOR of the repository" "rm -rf \"$SANDBOX/..\""
expect CHECKPOINT "  control: '..' walking from outside back into the repository" \
    "rm -rf \"$NON_GIT_DIR/../$SANDBOX_NAME/src\""
ln -s "$SANDBOX/src" "$NON_GIT_DIR/link-into-repo"
expect CHECKPOINT "  control: a symlink outside the repository pointing into it" \
    "rm -rf \"$NON_GIT_DIR/link-into-repo/\""
SANDBOX_UPPER=$(printf '%s' "$SANDBOX" | tr '[:lower:]' '[:upper:]')
expect CHECKPOINT "  control: the repository path in another letter case" "rm -rf \"$SANDBOX_UPPER/src\""
expect CHECKPOINT "  control: one out-of-repo and one in-repo operand" 'rm -rf /tmp/scratch-2652 ./src'
expect CHECKPOINT "  control: a build-artifact name no longer exempts a second operand" 'rm -rf dist ./src'
expect CHECKPOINT "  control: a relative operand after cd (cd could point anywhere)" 'cd /tmp && rm -rf scratch'
expect CHECKPOINT "  control: a tilde operand is not resolved" 'rm -rf ~/scratch-2652'
expect CHECKPOINT "  control: brace expansion is not resolved" 'rm -rf /tmp/{a,b}'
expect CHECKPOINT "  control: git -C . still targets this repository" 'git -C . reset --hard'

# Repro 2's variable form is NOT statically resolvable: #2652 is reduced for it,
# not fixed. Pinned so nobody "fixes" it by trusting the variable.
expect CHECKPOINT "residual: rm -rf \"\$T\" (mktemp variable) still checkpoints" \
    "$(printf '%s\n' 'T=$(mktemp -d)' 'rm -rf "$T"')"

# Text that deletes nothing (repros 3 and 4)
expect skip "gh issue comment --body quoting the pattern (repro 4)" \
    "gh issue comment 1 --body 'we should stop matching rm -rf /tmp/foo in command text'"
expect skip "gh issue comment --body-file heredoc quoting the pattern (repro 3)" \
    "$(printf '%s\n' "gh issue comment 2652 --body-file - <<'EOF'" \
        'Second repro: `rm -rf "$T"` on a mktemp dir, then rm -rf ./src and git reset --hard.' \
        'EOF')"
expect skip "gh pr create --body \"\$(cat <<'EOF' …)\" quoting the pattern" \
    "$(printf '%s\n' "gh pr create --title t --body \"\$(cat <<'EOF'" \
        'We stop matching rm -rf ./src and git checkout -- tracked.txt in text.' \
        'EOF' ')"')"
expect skip "git commit -m \"\$(cat <<'EOF' …)\" quoting the pattern" \
    "$(printf '%s\n' "git commit -m \"\$(cat <<'EOF'" 'fix: rm -rf ./src is not run here' 'EOF' ')"')"
expect skip "gh issue create --body | tail -1" \
    "gh issue create --title t --body 'rm -rf ./src and git clean -fd' | tail -1"
expect skip "echo carrying the pattern" 'echo "rm -rf ./src"'
expect skip "printf carrying the pattern" "printf 'git reset --hard\n'"
expect skip "grep for the pattern" "grep -n 'rm -rf' README.md"
expect skip "rg for the pattern" "rg 'rm\\s+-rf' ."
expect skip "git commit -m carrying the pattern" 'git commit -m "docs: never run git checkout -- tracked.txt"'
expect skip "git log --grep for the pattern" "git log --grep 'git clean -fd'"
expect skip "escaped backticks inside a gh body are text" 'gh issue create --title t --body "Use \`rm -rf ./src\` carefully"'
expect skip "echo to /dev/null" 'echo "rm -rf ./src" > /dev/null'
expect CHECKPOINT "  control: unescaped backticks inside a gh body RUN" 'gh issue create --title t --body "Use `rm -rf ./src` carefully"'
expect CHECKPOINT "  control: the same echo piped into a shell" 'echo "rm -rf ./src" | bash'
expect CHECKPOINT "  control: the same echo written to a file" 'echo "rm -rf ./src" >> run.sh'
expect CHECKPOINT "  control: the same heredoc piped into a shell" \
    "$(printf '%s\n' "cat <<'EOF' | bash" 'rm -rf ./src' 'EOF')"
expect CHECKPOINT "  control: the same heredoc fed to bash" \
    "$(printf '%s\n' "bash <<'EOF'" 'rm -r -f ./src' 'EOF')"
expect CHECKPOINT "  control: a heredoc to an unknown program keeps the old matcher" \
    "$(printf '%s\n' "python3 - <<'EOF'" 'import os; os.system("rm -rf ./src")' 'EOF')"
expect CHECKPOINT "  control: a variable holding the command, then run" "X='rm -rf ./src'; \$X"
expect CHECKPOINT "  control: printf -v, then run" "printf -v X 'rm -rf ./src'; \$X"
expect CHECKPOINT "  control: rg --pre runs a command" "rg --pre 'rm -rf ./src' foo"
expect CHECKPOINT "  control: a remote shell string keeps the old matcher" "ssh host 'rm -rf ./src'"
expect CHECKPOINT "  control: python -c keeps the old matcher" "python3 -c \"import os; os.system('rm -rf ./src')\""

echo "  == B + C. generated spelling probe, and the differential against every baseline =="

dq() { # double-quote a string for the shell
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//\$/\\\$}
    s=${s//\`/\\\`}
    printf '"%s"' "$s"
}
sq() { # single-quote a string for the shell
    local s=$1 q="'\\''"
    s=${s//\'/$q}
    printf "'%s'" "$s"
}
fill() { # $1 = template with one X placeholder, $2 = replacement
    printf '%s%s%s' "${1%%X*}" "$2" "${1#*X}"
}
spell_prog() { # $1 = command, $2 = spelling style for its program word
    local prog=${1%% *} rest=${1#* }
    case $2 in
        backslash) printf '\\%s %s' "$prog" "$rest" ;;
        dquote) printf '"%s" %s' "$prog" "$rest" ;;
        squote) printf "'%s' %s" "$prog" "$rest" ;;
        split) printf "%s''%s %s" "${prog:0:1}" "${prog:1}" "$rest" ;;
        abs)
            case $prog in
                rm) printf '/bin/rm %s' "$rest" ;;
                *) printf '/usr/bin/%s %s' "$prog" "$rest" ;;
            esac
            ;;
    esac
}
wrap_shell() { # $1 = template (DQ / SQ mark the script slot), $2 = inner command
    case $1 in
        HEREDOC) printf "bash <<'EOF'\n%s\nEOF" "$2" ;;
        *DQ*) printf '%s%s%s' "${1%%DQ*}" "$(dq "$2")" "${1#*DQ}" ;;
        *SQ*) printf '%s%s%s' "${1%%SQ*}" "$(sq "$2")" "${1#*SQ}" ;;
    esac
}

REP=("rm -rf ./src" "git checkout -- tracked.txt" "git restore tracked.txt" "git clean -fd" "git reset --hard")
RM_ARGS=("-rf ./src" "-fr ./src" "-r -f ./src" "-f -r ./src" "-Rf ./src" "-rfv ./src"
    "--recursive --force ./src" "-r --force ./src" "--rec --for ./src" "-rf -- ./src"
    "-rf dummy" "-rf src/" "-rf ./src/*" '-rf "./src"' "-rf ./a ./src" "./src -rf"
    "-rf @TOP@/src" '-rf "@TOP@"')
GIT_ARGS=("checkout -- tracked.txt" "checkout HEAD -- tracked.txt" "checkout -f -- tracked.txt"
    "-C . checkout -- tracked.txt" "-c core.pager=cat checkout -- tracked.txt"
    "--no-pager checkout -- tracked.txt" "restore tracked.txt" "restore --worktree tracked.txt"
    "restore --staged --worktree tracked.txt" "restore -W tracked.txt" "restore ."
    "clean -fd" "clean -df" "clean -d -f" "clean --force -d" "clean -fdx" "clean -xdf" "clean -f"
    "reset --hard" "reset --hard HEAD~1" "reset" "reset --mixed HEAD" "-C . reset --hard"
    "--git-dir=.git reset --hard" "rm -rf ./src")
STYLES=(backslash dquote squote split abs)
WRAPPERS=('env X=1 ' 'X=1 ' 'timeout 5 ' 'sudo ' 'command ' 'nice -n 5 ' 'nohup ' 'exec ' 'time ' 'xargs -r ')
SHELL_WRAPS=('bash -c DQ' 'sh -c SQ' 'sh -ec SQ' 'bash --norc -c DQ' 'bash --rcfile /dev/null -c DQ'
    'bash -lc DQ' 'zsh -c SQ' 'eval DQ' '\bash -c DQ' '/bin/sh -c SQ' 'sudo bash -c SQ'
    'bash -c SQ _ extra' 'bash -o pipefail -c DQ' 'env -i bash -c SQ' 'echo SQ | sh'
    'printf "%s\n" SQ | bash' 'bash <<< SQ' 'HEREDOC')
SHELL_INNER=("${REP[@]}" "rm -r -f ./src" "rm --recursive --force ./src" '\rm -rf ./src' "git -C . clean -d -f")
CONTEXTS=('X' 'cd . && X' 'X; true' 'true && X' 'false || X' 'X || true' 'for d in 1; do X; done'
    'if true; then X; fi' '( X )' '{ X; }' 'X 2>&1 | cat' 'X &' $'echo start\nX' '! X'
    'echo "$(X)"' 'out=$(X)' 'f() { X; }; f' 'case a in a) X ;; esac' 'while :; do X; break; done')

SPELLINGS=()
for c in "${REP[@]}"; do SPELLINGS+=("$c"); done
for a in "${RM_ARGS[@]}"; do SPELLINGS+=("rm $a"); done
for a in "${GIT_ARGS[@]}"; do SPELLINGS+=("git $a"); done
for c in "${REP[@]}"; do
    for s in "${STYLES[@]}"; do SPELLINGS+=("$(spell_prog "$c" "$s")"); done
    for w in "${WRAPPERS[@]}"; do SPELLINGS+=("$w$c"); done
done
for c in "${SHELL_INNER[@]}"; do
    for h in "${SHELL_WRAPS[@]}"; do SPELLINGS+=("$(wrap_shell "$h" "$c")"); done
done
for c in "rm -rf ./src" "git checkout -- tracked.txt"; do
    for x in "${CONTEXTS[@]}"; do SPELLINGS+=("$(fill "$x" "$c")"); done
done
# Composed axes: a context around a shell wrapper around a respelled program.
for x in 'for d in 1; do X; done' 'X 2>&1 | cat' 'if true; then X; fi'; do
    for h in 'bash --norc -c DQ' 'sh -ec SQ' 'eval DQ'; do
        for c in '\rm -rf ./src' '"git" clean -d -f'; do
            SPELLINGS+=("$(fill "$x" "$(wrap_shell "$h" "$c")")")
        done
    done
done
# The must-checkpoint controls from section A take part in the differential too.
SPELLINGS+=('echo "rm -rf ./src" | bash' "$(printf '%s\n' "cat <<'EOF' | bash" 'rm -rf ./src' 'EOF')"
    "X='rm -rf ./src'; \$X" "ssh host 'rm -rf ./src'" "python3 -c \"import os; os.system('rm -rf ./src')\"")

N_SPELLINGS=${#SPELLINGS[@]}
if [ "$N_SPELLINGS" -ge 300 ]; then
    pass "spelling probe generated $N_SPELLINGS spellings (non-vacuity floor: 300)"
else
    fail "spelling probe generated $N_SPELLINGS spellings" "expected at least 300"
fi

# Baselines: the shipped text at HEAD and at the pinned pre-#2652 commit,
# whenever those objects exist and differ from the hook under test and from each
# other. A shallow CI clone lacks the pinned commit, and after this change lands
# HEAD's copy IS the hook under test; when neither remains, the hook's own
# no-parser path — the pre-#2652 matcher it keeps as its floor — stands in.
BASELINE_DIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$BASELINE_DIR" ] || [ ! -d "$BASELINE_DIR" ]; then
    echo "bad baseline dir" >&2
    exit 1
fi
trap 'rm -rf "$SANDBOX" "$NON_GIT_DIR" "$FAKE_ROOT" "$BASELINE_DIR"' EXIT
BASE_LABELS=()
BASE_FILES=()
for ref in HEAD "$PINNED_BASELINE_REF"; do
    bfile="$BASELINE_DIR/baseline-${#BASE_FILES[@]}.sh"
    if ! git -C "$HOOK_DIR" show "$ref:./auto-checkpoint.sh" > "$bfile" 2>/dev/null; then
        echo "  NOTE: baseline $ref is not in this clone"
        continue
    fi
    dup=0
    if cmp -s "$HOOK" "$bfile"; then dup=1; fi
    for existing in "${BASE_FILES[@]+"${BASE_FILES[@]}"}"; do
        if cmp -s "$existing" "$bfile"; then dup=1; fi
    done
    if [ "$dup" = 1 ]; then
        echo "  NOTE: baseline $ref is identical to a file already compared; skipped"
        continue
    fi
    BASE_LABELS+=("git show $ref")
    BASE_FILES+=("$bfile")
done
BASE_NOPARSE=0
if [ "${#BASE_FILES[@]}" -eq 0 ]; then
    BASE_LABELS+=("the hook's no-parser path (pre-#2652 matcher)")
    BASE_FILES+=("$HOOK")
    BASE_NOPARSE=1
fi
N_BASE=${#BASE_FILES[@]}

# One worker per slice of the spellings, each in its own copy of the sandbox, so
# no two hook runs share a git index or stash ref. A worker writes one line per
# spelling: "<index> <new-verdict> <new-exit> <baseline verdict>...".
WORKERS=4
WORK_DIR="$BASELINE_DIR/work"
mkdir -p "$WORK_DIR"
probe_worker() { # $1 = worker number
    local w=$1 repo="$WORK_DIR/repo-$1" i b line
    cp -R "$SANDBOX" "$repo"
    for ((i = w; i < N_SPELLINGS; i += WORKERS)); do
        run_verdict_in "$repo" "$HOOK" "${SPELLINGS[i]}"
        line="$i $VERDICT $LAST_RC"
        for ((b = 0; b < N_BASE; b++)); do
            if [ "$BASE_NOPARSE" = 1 ]; then
                run_verdict_in "$repo" "${BASE_FILES[b]}" "${SPELLINGS[i]}" "$NOPARSE"
            else
                run_verdict_in "$repo" "${BASE_FILES[b]}" "${SPELLINGS[i]}"
            fi
            line+=" $VERDICT"
        done
        echo "$line"
    done > "$WORK_DIR/result-$w"
}
for ((w = 0; w < WORKERS; w++)); do
    probe_worker "$w" &
done
wait

PROBE_FAIL=0
BASE_HITS=()
BASE_LOST=()
for ((b = 0; b < N_BASE; b++)); do
    BASE_HITS+=(0)
    BASE_LOST+=(0)
done
N_RESULTS=0
while read -r idx new rc rest_verdicts; do
    [ -n "$idx" ] || continue
    N_RESULTS=$((N_RESULTS + 1))
    shown=$(printf '%s' "${SPELLINGS[idx]}" | tr '\n' '~')
    if [ "$new" != CHECKPOINT ] || [ "$rc" -ne 0 ]; then
        PROBE_FAIL=$((PROBE_FAIL + 1))
        fail "spelling probe: must checkpoint" "got $new (exit $rc) for: $shown"
    fi
    b=0
    for bv in $rest_verdicts; do
        if [ "$bv" = CHECKPOINT ]; then
            BASE_HITS[b]=$((BASE_HITS[b] + 1))
            if [ "$new" != CHECKPOINT ]; then
                BASE_LOST[b]=$((BASE_LOST[b] + 1))
                fail "differential vs ${BASE_LABELS[b]}: a spelling it checkpoints is skipped" "$shown"
            fi
        fi
        b=$((b + 1))
    done
done < <(cat "$WORK_DIR"/result-*)
if [ "$N_RESULTS" -ne "$N_SPELLINGS" ]; then
    fail "every generated spelling was run" "$N_RESULTS results for $N_SPELLINGS spellings"
elif [ "$PROBE_FAIL" -eq 0 ]; then
    pass "spelling probe: all $N_SPELLINGS generated spellings checkpoint"
fi
for ((b = 0; b < N_BASE; b++)); do
    # A baseline that checkpoints almost nothing makes its differential vacuous.
    if [ "${BASE_HITS[b]}" -lt $((N_SPELLINGS / 2)) ]; then
        fail "differential vs ${BASE_LABELS[b]} is not vacuous" \
            "the baseline checkpointed only ${BASE_HITS[b]} of $N_SPELLINGS spellings"
    elif [ "${BASE_LOST[b]}" -eq 0 ]; then
        pass "differential vs ${BASE_LABELS[b]}: it checkpoints ${BASE_HITS[b]} of $N_SPELLINGS spellings, none lost"
    fi
done

echo "  == E. the allow path exits 0 under /bin/bash (3.2 on a stock macOS) =="

if [ -x /bin/bash ]; then
    SYSTEM_BASH_VERSION=$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null || echo unknown)
    echo "  system /bin/bash: $SYSTEM_BASH_VERSION"
    BASH_BIN=/bin/bash expect skip "/bin/bash: echo hello" 'echo hello'
    BASH_BIN=/bin/bash expect skip "/bin/bash: git status" 'git status'
    BASH_BIN=/bin/bash expect skip "/bin/bash: out-of-repo rm -rf" 'rm -rf /tmp/scratch-2652 2>/dev/null'
    BASH_BIN=/bin/bash expect skip "/bin/bash: gh --body-file heredoc" \
        "$(printf '%s\n' "gh issue comment 1 --body-file - <<'EOF'" 'rm -rf ./src' 'EOF')"
    BASH_BIN=/bin/bash expect CHECKPOINT "/bin/bash: bash --rcfile /dev/null -c \"rm -r -f ./src\"" \
        'bash --rcfile /dev/null -c "rm -r -f ./src"'
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi

exit 0
