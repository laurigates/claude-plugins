#!/usr/bin/env bash
# Regression tests for bash-antipatterns.sh
#
# Run: bash hooks-plugin/hooks/test-bash-antipatterns.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(dirname "$0")/bash-antipatterns.sh"
PASS=0
FAIL=0

assert_exit() {
    local desc="$1" expected="$2" cmd="$3"
    local json
    json=$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd")
    local exit_code=0
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$exit_code"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== bash-antipatterns hook tests ==="

# ── find exemption regression ────────────────────────────────────────────────
# Regression: find with -exec was allowed while find with -maxdepth/-type was
# blocked — the exact opposite of the project rules in agentic-permissions.md
# and shell-scripting.md, which recommend find with those flags for directory
# discovery that Glob cannot replicate.
echo ""
echo "find exemption (directory-discovery flags allowed, -exec blocked):"

assert_exit \
    "find -maxdepth -type d is allowed" 0 \
    "find . -maxdepth 1 -type d"

assert_exit \
    "find -maxdepth -name is allowed" 0 \
    "find . -maxdepth 1 -name '*.yml'"

assert_exit \
    "find -type f -print0 is allowed" 0 \
    "find . -type f -print0"

assert_exit \
    "find -mindepth -maxdepth is allowed" 0 \
    "find . -mindepth 1 -maxdepth 2 -name '*.md'"

assert_exit \
    "find -name only (Glob can do this) is blocked" 2 \
    "find . -name '*.ts'"

assert_exit \
    "find -exec (dangerous, no discovery flags) is blocked" 2 \
    "find . -exec ls {}"

# Regression (issue #1671): find with a -delete action must be allowed even with
# no directory-discovery flag — Glob can only list, it cannot delete, so the
# Glob nudge is useless and blocking is pure friction. -exec/-ok stay blocked
# (arbitrary command execution) — the agent should run explicit steps instead.
assert_exit \
    "find -name -delete is allowed (Glob cannot delete; issue #1671)" 0 \
    "find . -name '*.tmp' -delete"

assert_exit \
    "find -maxdepth -type -delete is allowed (issue #1671 exact repro)" 0 \
    "find /tmp/x -maxdepth 2 -name claude -type l -delete"

assert_exit \
    "find -name -exec rm (arbitrary execution) stays blocked" 2 \
    "find . -name '*.log' -exec rm {} +"

# ── cat pipeline regression ──────────────────────────────────────────────────
# Regression: cat file | command was blocked even though cat is feeding a
# pipeline — the Read tool cannot replace cat in pipelines where data flows
# to other tools like jq, python, grep, etc.
echo ""
echo "cat pipeline exemption (pipelines allowed, standalone cat blocked):"

assert_exit \
    "cat file (standalone) is blocked" 2 \
    "cat file.txt"

assert_exit \
    "cat /path/file (standalone) is blocked" 2 \
    "cat /home/user/.claude/settings.json"

assert_exit \
    "cat file | jq is allowed (pipeline)" 0 \
    "cat config.json | jq '.key'"

assert_exit \
    "cat file | python3 | grep is allowed (pipeline)" 0 \
    "cat ~/.claude/settings.json 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -A5 -i hook"

assert_exit \
    "cat file | command || echo fallback is allowed (pipeline)" 0 \
    "cat ~/.claude/settings.json 2>/dev/null | python3 -m json.tool 2>/dev/null | grep -A5 -i hook || echo not found"

# ── grep -q exemption regression ─────────────────────────────────────────────
# Regression: grep -q was blocked even though the Grep tool does not support
# boolean exit-code checks. grep -q is the standard shell idiom for testing
# whether a pattern exists (e.g. grep -q pattern file && do_thing).
echo ""
echo "grep -q exemption (exit-code checks allowed, plain searches blocked):"

assert_exit \
    "grep -q is allowed (boolean check)" 0 \
    "grep -q pattern file"

assert_exit \
    "grep -iq is allowed (case-insensitive boolean check)" 0 \
    "grep -iq pattern file"

assert_exit \
    "grep -qr is allowed (recursive boolean check)" 0 \
    "grep -qr pattern dir/"

assert_exit \
    "grep -q in conditional is allowed" 0 \
    "grep -q PATTERN file.txt && echo found"

assert_exit \
    "rg --quiet is allowed" 0 \
    "rg --quiet pattern file"

assert_exit \
    "grep pattern file (no -q, no pipe) is blocked" 2 \
    "grep pattern file"

assert_exit \
    "grep -n pattern file (no -q, no pipe) is blocked" 2 \
    "grep -n pattern file"

assert_exit \
    "grep in pipeline is allowed (piped output has different semantics)" 0 \
    "git log --oneline | grep pattern"

# ── echo/printf file-write detection ─────────────────────────────────────────
# Regression: echo "---"; git ... 2>/dev/null was falsely blocked because
# the regex used .* which crossed the ; command separator and matched the
# unrelated 2>/dev/null as if echo were redirecting to a file.
echo ""
echo "echo/printf file-write detection (true positives blocked, false negatives allowed):"

assert_exit \
    "echo text > file is blocked" 2 \
    "echo hello > file.txt"

assert_exit \
    "printf text > file is blocked" 2 \
    "printf hello > file.txt"

assert_exit \
    "echo separator followed by unrelated 2>/dev/null is allowed" 0 \
    "git log --oneline | head -20; echo '---'; git log --oneline 2>/dev/null | head -20"

assert_exit \
    "echo in compound command before git 2>/dev/null is allowed" 0 \
    "cd /some/repo && git log --oneline -10 -- infra/ 2>/dev/null | head -20; echo '---'; git log --oneline 2>/dev/null | head -20"

# ── echo/printf stream-target & quoted-`>` false-positive regression (issue #1701) ──
# The block must only fire on a redirect to a real FILE. These check that:
#   1. a single `> /dev/null` (not just `>>`) is exempt — the comment always
#      claimed echo-to-/dev/null was allowed, but the old exemption matched only
#      `>>`, so `echo x > /dev/null` was wrongly blocked;
#   2. a real file write whose *stderr* is sent to /dev/null still blocks — the
#      `2>/dev/null` must not exempt the genuine `> realfile.txt` write.
assert_exit \
    "echo > /dev/null (single >) is allowed (issue #1701)" 0 \
    "echo x > /dev/null"

assert_exit \
    "real file write with unrelated 2>/dev/null still blocks (issue #1701)" 2 \
    "echo data > realfile.txt 2>/dev/null"

# ── heredoc body false-positive regression ───────────────────────────────────
# Regression: `gh pr create --body "$(cat <<EOF ... EOF)"` bodies containing
# example shell commands (e.g. "git add && git commit" shown as documentation
# in a PR description) triggered the git-chain index.lock detector. The hook
# must strip heredoc bodies before scanning for antipatterns.
#
# These cases have embedded quotes and newlines, so they use jq to build the
# JSON payload safely (assert_exit's printf-based JSON cannot escape them).
echo ""
echo "heredoc body is ignored when scanning for antipatterns:"

assert_exit_complex() {
    local desc="$1" expected="$2" cmd="$3"
    local json
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    local exit_code=0
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$exit_code"
        FAIL=$((FAIL + 1))
    fi
}

heredoc_body_cmd=$(cat <<'OUTER'
gh pr create --title "fix: something" --body "$(cat <<'EOF'
## Workflow

Run git add && git commit to stage and commit.

Then git push origin HEAD to publish.
EOF
)"
OUTER
)

assert_exit_complex \
    "gh pr create with heredoc body mentioning 'git add && git commit' is allowed" 0 \
    "$heredoc_body_cmd"

assert_exit_complex \
    "plain git add && git commit (outside heredoc) is still blocked" 2 \
    "git add file.txt && git commit -m msg"

# ── quoted-string body false-positive regression (issue #1587) ────────────────
# Regression: a git chain documented inside a plain quoted argument (no heredoc)
# — e.g. a gh issue/PR body that *mentions* `git add && git commit` as prose —
# falsely fired the index.lock detector. The detector now scans the
# quoted-string-stripped view, so literal data in --body/--title passes while a
# real chained command still blocks.
assert_exit_complex \
    "gh issue body mentioning 'git add && git commit' (quoted, no heredoc) is allowed" 0 \
    'gh issue create -R o/r --title "bug" --body "the hook blocked git add . && git commit -m x"'

assert_exit_complex \
    "git chain with single-quoted commit message is still blocked" 2 \
    "git add . && git commit -m 'fix: thing'"

# ── heredoc-write-then-feed-CLI regression (issue #1584, #1587) ───────────────
# Regression: `cat > /tmp/body.md <<EOF ... EOF; gh pr create --body-file ...`
# was blocked with the git-commit heredoc reminder even though the command runs
# no git commit at all — the commit-message-to-temp-file detector fired on any
# heredoc-to-/tmp write containing conventional-commit-shaped text, and the
# `cat > file` Write-tool block fired on the heredoc write itself. Writing a
# body file via heredoc and passing it to `gh pr create --body-file` /
# `gh issue edit --body-file` is the recommended multi-line pattern and must pass.
echo ""
echo "heredoc-write-then-feed-CLI is allowed; git-commit message file still nudged:"

prbody_cmd=$(cat <<'OUTER'
cat > /tmp/pr-body.md <<'EOF'
## Summary

fix(api): handle timeout edge case

Closes #123
EOF
gh pr create --draft --title "fix: x" --body-file /tmp/pr-body.md -a laurigates
OUTER
)

assert_exit_complex \
    "cat > /tmp/body.md heredoc fed to gh pr create --body-file is allowed" 0 \
    "$prbody_cmd"

issuebody_cmd=$(cat <<'OUTER'
cat > /tmp/issue-body.md <<'EOF'
chore(scope): something

docs note here.
EOF
gh issue edit 2001 --body-file /tmp/issue-body.md
OUTER
)

assert_exit_complex \
    "cat > /tmp/body.md heredoc fed to gh issue edit --body-file is allowed" 0 \
    "$issuebody_cmd"

# ── echo/printf double-quoted-`>` & /dev-stream regression (issue #1701) ──────
# These cases carry double quotes, so they need jq-based JSON (assert_exit's
# printf cannot escape them). The block scans the quoted-string-stripped view, so
# a `>` inside a double-quoted argument is text, not a redirection; and a stdout
# redirect to a /dev/* stream target is stream handling, not file creation.
echo ""
echo "echo/printf with double-quoted '>' or /dev stream target is allowed (issue #1701):"

assert_exit_complex \
    "echo with literal '>' inside double quotes (no redirection) is allowed" 0 \
    'echo "use foo > bar.txt to write"'

assert_exit_complex \
    "echo section header containing '>' is allowed" 0 \
    'echo "=== build > test ==="; git status'

assert_exit_complex \
    "echo redirected to /dev/stderr is allowed (stream, not a file)" 0 \
    'echo "error happened" > /dev/stderr'

assert_exit_complex \
    "printf redirected to /dev/stderr is allowed (stream, not a file)" 0 \
    'printf "%s\n" "warning" > /dev/stderr'

assert_exit_complex \
    "echo redirected to /dev/tty is allowed (stream, not a file)" 0 \
    'echo hi > /dev/tty'

assert_exit_complex \
    "echo to a real double-quoted-content file still blocks" 2 \
    'echo "content" > realfile.txt'

# True positive preserved: a heredoc commit message to /tmp passed to git commit -F
# still earns the reminder, because the command actually composes a git commit.
gitcommit_cmd=$(cat <<'OUTER'
cat > /tmp/commit_msg.txt <<'EOF'
feat(auth): add OAuth2 support
EOF
git commit -F /tmp/commit_msg.txt
OUTER
)

assert_exit_complex \
    "heredoc commit message to /tmp fed to git commit -F is still blocked" 2 \
    "$gitcommit_cmd"

# Plain `cat > file` with no heredoc is still nudged toward the Write tool.
assert_exit \
    "plain cat > file (no heredoc) is still blocked" 2 \
    "cat > /tmp/scratch.txt"

# ── substitution-format block messages ──────────────────────────────────────
# Regression: block messages were "REMINDER: Use the X tool instead of Y" —
# advisory prose without a concrete substitution. W21 friction analysis showed
# grep/rg same-session repeat-block rate climbed from 21% to 29% even with
# the rule landed; W20's gh-json-fields rule (concrete substitution format)
# drove its target friction from 10/10 sessions to 0/0. This block asserts
# the new messages carry the substitution markers so future bulk edits can't
# silently revert to advisory prose. (Issue #1377)
echo ""
echo "substitution-format block messages (BLOCKED: ... → ...):"

assert_stderr_contains() {
    local desc="$1" needle="$2" cmd="$3"
    local json
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    local stderr_out
    stderr_out=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null || true)
    if echo "$stderr_out" | grep -qF "$needle"; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (stderr missing literal: %s)\n" "$desc" "$needle"
        printf "    got: %s\n" "$stderr_out"
        FAIL=$((FAIL + 1))
    fi
}

assert_stderr_contains \
    "find block message names Glob substitution" \
    'Glob(pattern="**/*.ts")' \
    "find . -name '*.ts'"

assert_stderr_contains \
    "find block message uses BLOCKED: prefix" \
    'BLOCKED:' \
    "find . -name '*.ts'"

assert_stderr_contains \
    "find block message points at rule file" \
    'bash-tool-replacements.md' \
    "find . -name '*.ts'"

assert_stderr_contains \
    "grep block message names Grep substitution" \
    'Grep(pattern="pattern", path="src", -r=true, -n=true)' \
    "grep -rn pattern src/"

assert_stderr_contains \
    "rg block message also names Grep substitution" \
    'Grep(pattern="pattern", glob="*.ts")' \
    "rg pattern --type ts"

assert_stderr_contains \
    "grep block message points at rule file" \
    'bash-tool-replacements.md' \
    "grep -rn pattern src/"

assert_stderr_contains \
    "cat block message names Read substitution" \
    'Read(file_path="/path/to/file.md")' \
    "cat /home/user/file.md"

assert_stderr_contains \
    "cat block message points at rule file" \
    'bash-tool-replacements.md' \
    "cat /home/user/file.md"

assert_stderr_contains \
    "head block message names Read substitution with limit" \
    'Read(file_path="/abs/path/to/file.md", limit=50)' \
    "head -50 file.md"

assert_stderr_contains \
    "tail block message names Read substitution with offset" \
    'Read(file_path="/abs/path/to/file.md", offset=<total_lines - 50>, limit=50)' \
    "tail -50 file.md"

assert_stderr_contains \
    "head block message points at rule file" \
    'bash-tool-replacements.md' \
    "head -50 file.md"

# ── grep -l/-c/-L filter-mode exemption (issue #1592) ────────────────────────
# Regression: grep -l (files-with-matches) and grep -c (count) over a known
# file set are filters, not codebase searches the Grep tool replaces, but they
# were blocked by the grep/rg detector. The uppercase context flag -C (a real
# search) must still be blocked.
echo ""
echo "grep -l/-c/-L filter modes are exempt (-C context is not):"

assert_exit \
    "grep -lE over explicit files is allowed (files-with-matches)" 0 \
    "grep -lE NOTARY /tmp/a.js /tmp/b.js"

assert_exit \
    "grep -c count mode is allowed" 0 \
    "grep -c pattern /tmp/file.js"

assert_exit \
    "grep -rl (recursive files-with-matches) is allowed" 0 \
    "grep -rl pattern src/"

assert_exit \
    "grep -L (files-without-match) is allowed" 0 \
    "grep -L pattern file1 file2"

assert_exit \
    "grep --count long form is allowed" 0 \
    "grep --count pattern file"

assert_exit \
    "grep -C3 (uppercase context) is still blocked (it's a real search)" 2 \
    "grep -C3 pattern file"

# ── task-output read → Read tool, not deprecated TaskOutput (issue #1591) ─────
# Regression: the task-output detector recommended the deprecated TaskOutput
# tool, fired on quoted/heredoc string content that merely *mentions* a
# task-output path, and blocked extraction pipelines over large output files.
echo ""
echo "task-output reads nudge toward Read, allow extraction pipelines, ignore quoted mentions:"

assert_exit \
    "standalone cat of a task-output file is nudged toward Read" 2 \
    "cat /tmp/claude/x/tasks/run.output"

assert_exit \
    "extraction pipeline over a task-output file is allowed" 0 \
    "cat /tmp/claude/x/tasks/run.output | jq .results"

assert_exit \
    "gh issue body merely mentioning a .output path is allowed (quoted string)" 0 \
    "gh issue create --body 'then tail the run.output file for results'"

# The sleep-then-cat polling form reaches the task-output detector specifically
# (a bare `cat`/`tail` read is caught by the generic cat/head-tail detectors
# first). Assert that detector's message recommends Read, not TaskOutput.
assert_stderr_contains \
    "task-output block recommends the Read tool, not TaskOutput" \
    'Use the Read tool' \
    "sleep 5 && cat /tmp/claude/x/tasks/run.output"

assert_stderr_contains \
    "task-output block no longer names the deprecated TaskOutput tool as the fix" \
    'TaskOutput tool is deprecated' \
    "sleep 5 && cat /tmp/claude/x/tasks/run.output"

# ── pipe-count gates on discouraged head stage, not raw count (issue #1603) ───
# Regression: a long pipeline of legitimate transforms (jq | sort | uniq -c |
# sort | …) was hard-blocked purely on pipe count. The block must fire only
# when a discouraged head stage (cat/echo/printf, or a redundant grep | grep)
# feeds the pipeline.
echo ""
echo "long pipelines of legit transforms pass; cat/echo-headed scrapes still blocked:"

assert_exit \
    "jq|sort|uniq|sort|head|tail analysis pipeline is allowed (6 pipes, jq head)" 0 \
    "jq -r '[.a,.b]|@tsv' r.jsonl | sort | uniq -c | sort -k2 | head | tail"

assert_exit \
    "cat-headed 5+ pipe text-scrape is still blocked" 2 \
    "cat f.txt | grep x | grep y | sed s/a/b/ | cut -f1 | sort"

assert_exit \
    "redundant grep | grep | sed | cut | sort chain is still blocked" 2 \
    "ps aux | grep proc | grep -v grep | awk '{print \$2}' | sort | uniq"

# ── grep block message offers the pipe fallback (issue #1602) ─────────────────
# Regression: when the Grep tool is unavailable in a session, the block message
# pointed only at Grep(...). It must also offer the always-allowed pipe form.
echo ""
echo "grep block message offers the pipe fallback for sessions without the Grep tool:"

assert_stderr_contains \
    "grep block message mentions the pipe fallback" \
    'pipe instead' \
    "grep -rn pattern src/"

# ── git push -u colon-refspec footgun, no-colon form allowed (issue #1600) ────
# Regression: the push -u detector blocked the legitimate no-colon form
# `git push -u origin feat/x` (which pushes feat/x, never touching main) on a
# false premise. It must instead catch only the real footgun: -u on a colon
# refspec whose source is the protected branch (git push -u origin main:feat).
# Run against a throwaway repo on `main` so branch detection has a branch.
echo ""
echo "git push -u: no-colon feature push allowed, colon main:feat footgun blocked (#1600):"

PUSH_REPO=$(mktemp -d)
git -C "$PUSH_REPO" init -q -b main
git -C "$PUSH_REPO" config user.email t@e.com
git -C "$PUSH_REPO" config user.name t
git -C "$PUSH_REPO" config commit.gpgsign false
git -C "$PUSH_REPO" commit -q --allow-empty -m init

# $HOOK is a relative path in this suite; resolve it to absolute so the
# subshell `cd "$PUSH_REPO"` below doesn't break the lookup (would exit 127).
HOOK_ABS="$(cd "$(dirname "$HOOK")" && pwd)/$(basename "$HOOK")"

assert_push_exit() {
    local desc="$1" expected="$2" cmd="$3"
    local json exit_code=0
    json=$(jq -nc --arg cmd "$cmd" '{tool_name:"Bash",tool_input:{command:$cmd}}')
    ( cd "$PUSH_REPO" && printf '%s' "$json" | bash "$HOOK_ABS" >/dev/null 2>&1 ) || exit_code=$?
    if [ "$exit_code" -eq "$expected" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected exit %d, got %d)\n" "$desc" "$expected" "$exit_code"; FAIL=$((FAIL + 1))
    fi
}

assert_push_exit \
    "git push -u origin feat/x (no colon) is allowed from main" 0 \
    "git push -u origin feat/x"

assert_push_exit \
    "git push -u origin main:feat/x (colon, source=main) is blocked" 2 \
    "git push -u origin main:feat/x"

assert_push_exit \
    "git push origin main:feat/x without -u is allowed" 0 \
    "git push origin main:feat/x"

rm -rf "$PUSH_REPO"

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
