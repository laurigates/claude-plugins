#!/usr/bin/env bash
# Regression tests for bash-antipatterns-teach.sh
#
# Run: bash hooks-plugin/hooks/test-bash-antipatterns-teach.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Unlike test-bash-antipatterns.sh (which asserts on exit codes), this hook
# returns exit 0 always. The contract is the stdout JSON: for matched
# antipatterns, `.hookSpecificOutput.updatedToolOutput` is an OBJECT matching the
# Bash tool's own output shape ({interrupted,isImage,noOutputExpected,stderr,stdout})
# with the hint merged into `.stdout`; empty stdout for non-matches and when the
# env-var guard is off.
#
# The object shape is the point, not an implementation detail: the harness
# validates updatedToolOutput against the tool's result schema, so a JSON string
# there is rejected ("expected object, received string") and the hint is silently
# discarded — the hook becomes a no-op (issue #2275). These tests pin the shape so
# a version comment does not have to.
# shellcheck disable=SC2016   # file-level: single-quoted `$(...)`/`$a` are deliberate literal command strings fed to the hook
set -euo pipefail

HOOK="$(dirname "$0")/bash-antipatterns-teach.sh"
PASS=0
FAIL=0

# Build a minimal PostToolUse input. tool_response is the REAL Bash result object
# the harness sends — not a bare string, which the harness never produces and
# which let the pre-#2275 suite pass against a broken hook.
# Optional second arg sets session_id (enables the once-per-session dedup path).
_payload() {
    local cmd="$1" session="${2:-}"
    jq -nc --arg cmd "$cmd" --arg session "$session" '{
        tool_name: "Bash",
        tool_input: {command: $cmd},
        tool_response: {
            interrupted: false,
            isImage: false,
            noOutputExpected: false,
            stderr: "",
            stdout: "sample stdout output\n"
        }
    } + (if $session == "" then {} else {session_id: $session} end)'
}

# Run the hook for a command under a given session id; echo non-empty stdout.
_run_session() {
    local cmd="$1" session="$2"
    _payload "$cmd" "$session" \
        | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true
}

# With the env var set, the hook should emit JSON whose
# .hookSpecificOutput.updatedToolOutput contains the expected substring.
assert_emits() {
    local desc="$1" cmd="$2" needle="$3"
    local out
    out=$(_payload "$cmd" | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true)
    if [ -z "$out" ]; then
        printf "  FAIL: %s (expected hint, got empty stdout)\n" "$desc"
        FAIL=$((FAIL + 1))
        return
    fi
    # Read the free text out of the OBJECT's stdout field. Against the pre-#2275
    # hook, updatedToolOutput is a string, so `.stdout` on it errors and body is
    # empty — which is exactly the regression signal.
    local body
    body=$(echo "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout // empty' 2>/dev/null || true)
    if [ -z "$body" ]; then
        printf "  FAIL: %s (updatedToolOutput.stdout missing — is updatedToolOutput still a string?)\n" "$desc"
        FAIL=$((FAIL + 1))
        return
    fi
    if echo "$body" | grep -qF "$needle"; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (substring %q not found in hint)\n" "$desc" "$needle"
        FAIL=$((FAIL + 1))
    fi
}

# With the env var set, the hook should produce empty stdout (non-matching command).
assert_silent() {
    local desc="$1" cmd="$2"
    local out
    out=$(_payload "$cmd" | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true)
    if [ -z "$out" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected silent, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

# With the env var unset, the hook should always produce empty stdout.
# Unset it explicitly: the developer's shell may export the opt-in var
# (e.g. via ~/.api_tokens / .zshrc), which made this block fail locally
# while passing in clean CI.
assert_disabled() {
    local desc="$1" cmd="$2"
    local out
    out=$(_payload "$cmd" | env -u CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH bash "$HOOK" 2>/dev/null || true)
    if [ -z "$out" ]; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected env-guard silence, got: %s)\n" "$desc" "$out"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== bash-antipatterns-teach hook tests ==="

echo ""
echo "cat / head / tail file reads (standalone):"
assert_emits "cat README.md emits Read hint" "cat README.md" "Read tool"
assert_emits "head -50 file.md emits Read offset/limit hint" "head -50 file.md" "Read tool with offset/limit"
assert_emits "tail -50 file.md emits Read offset/limit hint" "tail -50 file.md" "Read tool with offset/limit"

echo ""
echo "find without directory-discovery flags:"
assert_emits "find -name only emits Glob hint" "find . -name '*.ts'" "Glob tool"
assert_silent "find -maxdepth -type d is exempt" "find . -maxdepth 1 -type d"
assert_silent "find -type f -print0 is exempt" "find . -type f -print0"
# issue #1671: -delete is exempt (Glob cannot delete); -exec is not (arbitrary exec)
assert_silent "find -name -delete is exempt (Glob cannot delete)" "find . -name '*.tmp' -delete"
assert_emits "find -name -exec still emits Glob hint" "find . -name '*.log' -exec rm {} +" "Glob tool"

echo ""
echo "grep / rg standalone searches:"
assert_emits "grep -rn pattern emits Grep hint" "grep -rn foo src/" "Grep tool"
assert_emits "rg with --type emits Grep hint" "rg foo --type ts" "Grep tool"
assert_silent "grep -q boolean check is exempt" "grep -q pattern file"
assert_silent "rg --quiet boolean check is exempt" "rg --quiet pattern file"

echo ""
echo "ls with glob:"
assert_emits "ls *.md emits Glob hint" "ls *.md" "Glob tool"

echo ""
echo "long pipeline nudge (demoted from the hard block, #1873/#2051/#2052):"
assert_emits "6-pipe cat-headed text-scrape emits long-pipeline hint" \
    "cat f.log | grep a | grep -v b | awk '{print}' | sort | uniq -c | sort -rn" \
    "pipes fed from a cat/echo/printf"
assert_emits "5-pipe redundant grep|grep scrape emits long-pipeline hint" \
    "ps aux | grep proc | grep -v grep | sed s/a/b/ | cut -f1 | sort" \
    "pipes fed from a cat/echo/printf"
assert_silent "6-pipe jq-headed transform pipeline is silent (legit head)" \
    "jq -r '[.a,.b]|@tsv' r.jsonl | sort | uniq -c | sort -k2 | head | tail"
assert_silent "independent 1-pipe statements + printf | tee do not sum past threshold (#2051)" \
    'a=$(gh issue create | tail -1); b=$(gh issue create | tail -1); c=$(gh issue create | tail -1); d=$(gh issue create | tail -1); e=$(gh issue create | tail -1); printf "%s\n" "$a" | tee /tmp/x.txt'
assert_silent "kubectl logs grep|grep 5-pipe diagnosis is silent (log stream, #1833)" \
    'kubectl logs -n ns pod | grep -iE "err|403" | grep -ivE "noise" | grep -v other | cut -f1 | tail -15'

echo ""
echo "heredoc bodies and trailing comments are DATA, not shell (#2518):"
# The hook scans COMMAND_SHELL_ONLY (heredoc bodies + trailing `#` comments
# stripped), the same projection bash-antipatterns.sh computes. Before that lift,
# every nudge here scanned the raw command: `^` anchors to the start of each LINE,
# so a heredoc-body line was read as if it were the executed command, and the
# long-pipeline segmenter counted a markdown table row's `|` characters as pipes.
#
# Case A is the reported break: a markdown table documenting the OTHER detectors,
# written to a file via a heredoc. Its `| ... |` cells carry 6 "pipes" and the row
# text contains a `printf ` token, satisfying the discouraged-head test.
TEACH_HEREDOC_TABLE="cat > /tmp/notes.md <<'EOF'
| Pattern | Events | Sessions | Rate | Repeat |
|---|---|---|---|---|
| \`echo/printf > file\` -> Write | 18 | 16 | 15.2% | 12.5% |
| \`find\` -> Glob | 29 | 25 | 17% | 12% |
EOF"
assert_silent "A: heredoc body that is a markdown table is silent" "$TEACH_HEREDOC_TABLE"

# B is the load-bearing control: the identical table text arriving as a quoted
# ARGUMENT was already handled correctly (the segmenter strips quoted spans), so
# the hook already had the "this is data" concept — it just did not extend it to
# heredocs. B passing both pre- and post-fix is what proves A was the gap.
assert_silent "B: same table text as a single-quoted argument stays silent" \
    "gh issue create --body '| \`echo/printf > file\` -> Write | 18 | 16 | 15.2% | 12.5% |'"

# C/D are the must-still-fire / must-stay-silent controls. A permissive patch that
# silences the genuine scrape fails here rather than passing quietly.
assert_emits "C: genuine 5-pipe cat-headed scrape still fires" \
    "cat f.log | grep a | grep -v b | awk '{print}' | sort | uniq -c" \
    "pipes fed from a cat/echo/printf"
assert_silent "D: echo hello stays silent" "echo hello"

# The same per-line `^` exposure in the other four nudges: a heredoc body line
# that BEGINS with the watched word is prose, not a command.
assert_silent "heredoc body line beginning with 'find -name' is silent" \
    "gh pr create --body \"\$(cat <<'EOF'
Repro steps:
find . -name '*.ts'
EOF
)\""
assert_silent "heredoc body line beginning with 'tail -20 file' is silent" \
    "git commit -F - <<'EOF'
fix(x): stop truncating logs
tail -20 build.log
EOF"
assert_silent "heredoc body line beginning with 'grep -rn' is silent" \
    "git commit -F - <<'EOF'
docs: record the search that found it
grep -rn foo src/
EOF"
assert_silent "heredoc body line beginning with 'ls *.md' is silent" \
    "git commit -F - <<'EOF'
docs: note the listing idiom
ls *.md
EOF"

# Trailing `#` comments are likewise excluded from the shell projection.
assert_silent "trailing comment carrying a 5-pipe cat scrape is silent" \
    'git log --oneline -5  # cat x | a | b | c | d | e'

# Over-strip controls: neither projection may swallow real commands.
assert_emits "a real command AFTER the heredoc terminator still fires" \
    "cat > /tmp/x.md <<'EOF'
hello
EOF
grep -rn foo src/" \
    "Grep tool"
assert_emits "a trailing comment does not exempt the command it annotates" \
    "cat README.md  # skim the intro" \
    "Read tool"

echo ""
echo "pipelines and unrelated commands stay silent:"
assert_silent "cat file | head -10 (pipeline) is silent" "cat README.md | head -10"
assert_silent "git status --porcelain is silent" "git status --porcelain"
assert_silent "echo hello is silent" "echo hello"

echo ""
echo "heredoc bodies and trailing comments are DATA, not shell (#2518):"
# The teach hook scans the same COMMAND_SHELL_ONLY projection the safety hook
# computes: heredoc bodies and trailing `#` comments removed. Every detector here
# is `^`-anchored, and `^` matches the start of every LINE — so before the fix a
# heredoc-body line that merely *looked* like a watched command was nudged as if
# it were one. The live report: a `gh issue comment` whose body was a markdown
# table (zero shell pipes) drew the long-pipeline nudge, because the table's cell
# separators were counted as pipes and a cell containing the word `printf` was
# read as the discouraged head stage.
#
# Case B below is the load-bearing control: the identical table text arriving as
# a quoted argument was ALREADY handled correctly, so the hook had the
# "this is data" concept and simply did not extend it to heredocs.
HEREDOC_TABLE='gh issue comment 2420 --body-file - <<XEOF
| Detector | ev | sess | prev | rpt |
|---|---|---|---|---|
| `echo/printf > file` -> Write | 18 | 16 | 15.2% | 12.5% |
| `sed -i` -> Edit | 15 | 15 | 14.3% | 0.0% |
XEOF'
assert_silent "A: markdown table in a heredoc body draws no long-pipeline nudge" \
    "$HEREDOC_TABLE"
assert_silent "B: the same table as a quoted --body argument stays silent (control)" \
    'gh issue comment 2420 --body '"'"'| Detector | ev | `echo/printf > file` -> Write | 18 | 16 |'"'"''
assert_emits "C: a genuine 6-pipe cat-headed scrape still fires (control)" \
    "cat f.log | grep a | grep -v b | awk '{print}' | sort | uniq -c | sort -rn" \
    "pipes fed from a cat/echo/printf"
assert_silent "D: echo hello stays silent (control)" "echo hello"

# Every remaining detector, one heredoc-body case each. `cat` was already silent
# by accident (its own `<<` exclusion), so it is pinned rather than fixed.
assert_silent "heredoc body: 'cat README.md' draws no Read hint" \
    'gh pr create --body-file - <<XEOF
cat README.md
XEOF'
assert_silent "heredoc body: 'head -50 notes.md' draws no Read hint" \
    'gh pr create --body-file - <<XEOF
head -50 notes.md
XEOF'
assert_silent "heredoc body: 'tail -20 notes.md' draws no Read hint" \
    'gh pr create --body-file - <<XEOF
tail -20 notes.md
XEOF'
assert_silent "heredoc body: 'find . -name' draws no Glob hint" \
    'gh pr create --body-file - <<XEOF
find . -name "*.ts"
XEOF'
assert_silent "heredoc body: 'grep -rn foo src/' draws no Grep hint" \
    'gh pr create --body-file - <<XEOF
grep -rn foo src/
XEOF'
assert_silent "heredoc body: 'ls *.md' draws no Glob hint" \
    'gh pr create --body-file - <<XEOF
ls *.md
XEOF'

# GUARD INTEGRITY. Without these, a projection that simply blanked the whole
# command would pass every assert_silent above while teaching nothing ever again.
assert_emits "GUARD: a real grep sharing the heredoc-opening line still fires" \
    'grep -rn foo src/ && gh pr create --body-file - <<XEOF
| a | b |
XEOF' \
    "Grep tool"
assert_emits "GUARD: a real grep AFTER the heredoc terminator still fires" \
    'gh pr create --body-file - <<XEOF
| a | b |
XEOF
grep -rn foo src/' \
    "Grep tool"
assert_emits "GUARD: a real grep on line 2 of a multi-line command still fires" \
    'cd /tmp
grep -rn foo src/' \
    "Grep tool"

# Trailing `#` comments are stripped too — the same projection, and the pipe
# counter is the detector that a comment can actually push over its threshold.
assert_silent "trailing comment pipes do not inflate the pipeline count" \
    "cat f.log | grep a | grep -v b  # scraped from x | y | z | w | v | u"
assert_emits "GUARD: a trailing comment does not disarm a genuine 6-pipe scrape" \
    "cat f.log | grep a | grep -v b | awk '{print}' | sort | uniq -c | sort -rn  # scrape" \
    "pipes fed from a cat/echo/printf"

echo ""
echo "env-var guard (disabled by default):"
assert_disabled "cat README.md is silent when env var unset" "cat README.md"
assert_disabled "grep -rn foo src/ is silent when env var unset" "grep -rn foo src/"
assert_disabled "find . -name '*.ts' is silent when env var unset" "find . -name '*.ts'"

echo ""
echo "session-scoped dedup (each hint emits at most once per session):"
# Use a unique session id so the seen-file starts clean for this test run.
SID="test-dedup-$$-$RANDOM"
SEEN_FILE="${TMPDIR:-/tmp}/claude-bash-teach-seen/${SID}"
rm -f "$SEEN_FILE" 2>/dev/null || true

# First grep under this session emits the hint.
if [ -n "$(_run_session 'grep -rn foo src/' "$SID")" ]; then
    printf "  PASS: %s\n" "first grep in session emits hint"
    PASS=$((PASS + 1))
else
    printf "  FAIL: %s\n" "first grep in session should emit hint"
    FAIL=$((FAIL + 1))
fi

# Second grep under the same session is silent (already taught).
if [ -z "$(_run_session 'grep -rn bar lib/' "$SID")" ]; then
    printf "  PASS: %s\n" "repeat grep in same session is silent"
    PASS=$((PASS + 1))
else
    printf "  FAIL: %s\n" "repeat grep in same session should be silent"
    FAIL=$((FAIL + 1))
fi

# A different pattern in the same session still emits (dedup is per-pattern).
if [ -n "$(_run_session 'cat README.md' "$SID")" ]; then
    printf "  PASS: %s\n" "different pattern in same session still emits"
    PASS=$((PASS + 1))
else
    printf "  FAIL: %s\n" "different pattern in same session should emit"
    FAIL=$((FAIL + 1))
fi

# Same pattern under a fresh session emits again (dedup is per-session).
SID2="test-dedup-$$-$RANDOM-b"
rm -f "${TMPDIR:-/tmp}/claude-bash-teach-seen/${SID2}" 2>/dev/null || true
if [ -n "$(_run_session 'grep -rn foo src/' "$SID2")" ]; then
    printf "  PASS: %s\n" "same pattern in a new session emits again"
    PASS=$((PASS + 1))
else
    printf "  FAIL: %s\n" "same pattern in a new session should emit again"
    FAIL=$((FAIL + 1))
fi

# Without a session_id, dedup is skipped: both calls emit (backward compatible).
if [ -n "$(_run_session 'grep -rn foo src/' '')" ] && [ -n "$(_run_session 'grep -rn foo src/' '')" ]; then
    printf "  PASS: %s\n" "no session_id falls through to always-emit"
    PASS=$((PASS + 1))
else
    printf "  FAIL: %s\n" "no session_id should always emit"
    FAIL=$((FAIL + 1))
fi

rm -f "$SEEN_FILE" "${TMPDIR:-/tmp}/claude-bash-teach-seen/${SID2}" 2>/dev/null || true

echo ""
echo "output contract: updatedToolOutput is an OBJECT (#2275):"

# Run the hook against a fully-specified payload (these cases vary tool_response).
_run_raw() {
    printf '%s' "$1" | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true
}

# Assert a jq filter is truthy over the hook's stdout JSON.
assert_jq() {
    local desc="$1" json="$2" filter="$3"
    if printf '%s' "$json" | jq -e "$filter" >/dev/null 2>&1; then
        printf "  PASS: %s\n" "$desc"
        PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (jq filter false; got: %s)\n" "$desc" "$json"
        FAIL=$((FAIL + 1))
    fi
}

# Baseline: the standard object payload used by every assert_emits case above.
CONTRACT_OUT=$(_payload "cat README.md" | CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH=1 bash "$HOOK" 2>/dev/null || true)

# The direct contract. Pre-fix this is "string".
assert_jq "updatedToolOutput is a JSON object, not a string" \
    "$CONTRACT_OUT" '.hookSpecificOutput.updatedToolOutput | type == "object"'

# Field completeness against the documented Bash output shape.
assert_jq "updatedToolOutput carries the full Bash field set" \
    "$CONTRACT_OUT" \
    '.hookSpecificOutput.updatedToolOutput
     | has("interrupted") and has("isImage") and has("noOutputExpected")
       and has("stderr") and has("stdout")'

# Integrity guard: without this, every "type == object" assertion above would
# also pass against a hook that emitted an empty/placeholder object.
assert_jq "updatedToolOutput.stdout is non-empty (suite cannot degrade to a no-op)" \
    "$CONTRACT_OUT" '.hookSpecificOutput.updatedToolOutput.stdout | length > 0'

# stdout is original-then-divider-then-hint, in that order.
assert_jq "stdout preserves the original output, then the hint banner, in order" \
    "$CONTRACT_OUT" \
    '.hookSpecificOutput.updatedToolOutput.stdout
     | index("sample stdout output") as $a
     | index("--- bash-antipatterns hint ---") as $b
     | index("Read tool") as $c
     | ($a != null) and ($b != null) and ($c != null) and ($a < $b) and ($b < $c)'

# Negative: the pre-fix `tostring` serialized the WHOLE response object into the
# free text, leaking harness field names into what the model reads as stdout.
assert_jq "stdout does not leak the serialized response object" \
    "$CONTRACT_OUT" \
    '.hookSpecificOutput.updatedToolOutput.stdout | contains("\"noOutputExpected\":") | not'

# Non-stdout fields survive unmodified — catches a "fix" that rebuilds the
# object from defaults instead of merging into the harness's own object.
CONTRACT_PRESERVE=$(_run_raw '{
    "tool_name": "Bash",
    "tool_input": {"command": "cat README.md"},
    "tool_response": {"interrupted": true, "isImage": false, "noOutputExpected": true,
                      "stderr": "warn-line", "stdout": "partial output"}
}')
assert_jq "non-stdout fields are merged through unchanged" \
    "$CONTRACT_PRESERVE" \
    '.hookSpecificOutput.updatedToolOutput
     | .interrupted == true and .noOutputExpected == true
       and .stderr == "warn-line" and .isImage == false'
assert_jq "original stdout is preserved when other fields are set" \
    "$CONTRACT_PRESERVE" \
    '.hookSpecificOutput.updatedToolOutput.stdout | contains("partial output")'

# Defensive branch: a bare-string tool_response must still yield an object.
CONTRACT_STRING=$(_run_raw '{
    "tool_name": "Bash",
    "tool_input": {"command": "cat README.md"},
    "tool_response": "legacy string output"
}')
assert_jq "string tool_response still yields a full object" \
    "$CONTRACT_STRING" \
    '.hookSpecificOutput.updatedToolOutput
     | (type == "object") and has("interrupted") and has("isImage")
       and has("noOutputExpected") and has("stderr")
       and (.stdout | contains("legacy string output")) and (.stdout | contains("Read tool"))'

# Defensive branch: an absent tool_response must not crash or emit a string.
CONTRACT_ABSENT=$(_run_raw '{
    "tool_name": "Bash",
    "tool_input": {"command": "cat README.md"}
}')
assert_jq "absent tool_response still yields a full object with the hint" \
    "$CONTRACT_ABSENT" \
    '.hookSpecificOutput.updatedToolOutput
     | (type == "object") and has("interrupted") and has("isImage")
       and has("noOutputExpected") and has("stderr")
       and (.stdout | contains("Read tool"))'
assert_jq "absent tool_response does not stringify null into stdout" \
    "$CONTRACT_ABSENT" \
    '.hookSpecificOutput.updatedToolOutput.stdout | startswith("null") | not'

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
