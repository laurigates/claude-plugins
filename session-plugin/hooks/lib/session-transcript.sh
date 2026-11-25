#!/usr/bin/env bash
# Shared transcript readers for the session-plugin hooks. Sourced, not run.
#
# One definition of "an end-of-session skill ran" and "a genuine user turn",
# so the Stop nudge (session-end-nudge.sh) and the close ledger
# (session-ledger.sh) agree on both. Regression coverage lives in each
# hook's test-*.sh.
#
# Both callers already run under these flags; restating them keeps the lib
# safe to source from a new hook and satisfies the hooks lint.
set -euo pipefail

# session_end_skill_ran <transcript> — exit 0 when a session-wrap /
# session-end / session-distill / session-workflow-capture invocation appears
# in the transcript, either as a slash command (<command-name> tag in the
# expansion) or through the Skill tool ("skill":"…" in the tool_use input).
session_end_skill_ran() {
    local transcript="$1"
    grep -q 'command-name>[^<]*session-\(wrap\|end\|distill\|workflow-capture\)' "$transcript" 2>/dev/null \
        || grep -q '"skill"[[:space:]]*:[[:space:]]*"[^"]*session-\(wrap\|end\|distill\|workflow-capture\)' "$transcript" 2>/dev/null
}

# session_genuine_user_lines <transcript> — print the transcript lines that
# are prompts the user typed.
#
# Drops tool_result lines (role=user but harness-generated) and slash-command
# expansions (role=user but skill markdown). Then drops harness-injected
# user-role content (#3180): a line whose origin kind is human is always
# kept; otherwise isMeta records, any non-human origin (task-notification,
# scheduled tasks, ...), and task-notification / system-reminder /
# PR-activity wake / webhook / child-session bodies go. Queued messages need
# no filter: they are "type":"queue-operation" records without
# "role":"user", and a dequeued one arrives as an ordinary user record.
session_genuine_user_lines() {
    local transcript="$1"
    grep '"role":"user"' "$transcript" 2>/dev/null \
        | grep -v '"tool_use_id"' \
        | grep -v 'command-name>' \
        | awk '
            /"origin":[{]"kind":"human"/ { print; next }
            /"isMeta":true/ { next }
            /"origin":[{]"kind":"/ { next }
            /<(task-notification|system-reminder|webhook-payload|child-session-event)>/ { next }
            /<wake[ >]/ { next }
            { print }
        ' || true
}

# session_user_text — read one transcript line on stdin, print its text
# (Claude Code shape .message.content, or bare .content; string or blocks).
session_user_text() {
    jq -r '(.message // .).content
           | if type == "string" then .
             else [.[]? | select(.type == "text") | .text] | join(" ") end' \
        2>/dev/null || true
}
