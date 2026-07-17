#!/usr/bin/env bash
# PostToolUse hook for Bash tool - teaches built-in-tool alternatives by augmenting
# the agent-visible tool output rather than blocking the command (Claude Code 2.1.121+).
#
# Companion to bash-antipatterns.sh: that hook continues to PreToolUse-block patterns
# that risk data loss or security (git reset --hard, curl | bash, fork bombs, etc.).
# This hook handles the "soft-teach" antipatterns where the command produces a
# useful result and the right response is "here is your result + use the dedicated
# tool next time."
#
# Why PostToolUse + updatedToolOutput instead of PreToolUse + exit 2?
#
# 2026-W20 friction analysis:
# - grep/rg vs Grep tool: 41 events / 33 sessions / 24% per-session rate / 21%
#   same-session repeat-block rate
# - find vs Glob: 29 events / 25 sessions / 17% per-session / 12% repeat-block
# - git && chains: 39/36/23% per-session / 8% repeat-block
#
# git && chains land at ~8% repeat-block because the agent has a concrete fallback
# (issue git commands as separate Bash calls). grep/rg sits at 21% because the
# agent sees only the block message - not the would-have-been-result - so the
# "use Grep" advice lands abstractly. By letting the command run and prepending
# the corrective hint to the result, the agent learns the right tool while still
# getting the data it asked for.

set -euo pipefail

# Phase 1 opt-in: this hook is wired into plugin.json by default but no-ops
# unless the user explicitly enables it. Matches event-logger.sh convention.
# See hooks-plugin/docs/teach-mode-experiment.md for rationale.
if [ "${CLAUDE_HOOKS_ENABLE_BASH_ANTIPATTERNS_TEACH:-}" != "1" ]; then
    exit 0
fi

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
if [ "$TOOL_NAME" != "Bash" ]; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Compose the hint based on which soft-teach pattern (if any) the command matched.
# A command can match at most one hint - we pick the most specific. hint_key is a
# stable identifier for the matched pattern, used below for session-scoped dedup.
hint=""
hint_key=""

# cat file (not in pipeline, not heredoc)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*cat\s+[^|><]' && \
   ! echo "$COMMAND" | grep -Eq '<<|cat\s*>' && \
   ! echo "$COMMAND" | grep -q '|'; then
    hint="Use the Read tool instead of 'cat' to read files. Read returns line-numbered content and respects token budgets."
    hint_key="read-cat"
fi

# head/tail file (not in pipeline)
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*(head|tail)\s+(-[0-9n]+\s+)?[^|]' && \
   ! echo "$COMMAND" | grep -q '|'; then
    hint="Use the Read tool with offset/limit parameters instead of 'head' or 'tail'. Example: Read with offset=100, limit=50."
    hint_key="read-headtail"
fi

# find -name without directory-discovery flags
# Mirrors bash-antipatterns.sh: -delete is exempt because Glob can only list, not
# delete, so the Glob hint is useless for a delete action (issue #1671). -exec/-ok
# are intentionally not exempt (arbitrary command execution).
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*find\s+' && \
   ! echo "$COMMAND" | grep -Eq 'find\s+.*(-maxdepth|-mindepth|-type\s|-print0|-delete\b)'; then
    hint="Use the Glob tool for filename matching. Example: Glob(pattern=\"**/*.ts\") instead of 'find . -name \"*.ts\"'. Keep 'find' only when you need -maxdepth/-type d/-print0, or a -delete action."
    hint_key="glob-find"
fi

# grep/rg as standalone search (not piped, not -q, not -l/-c/-L filter modes)
# Mirrors bash-antipatterns.sh: file-list/count modes (-l, -c, -L) are filters,
# not codebase searches the Grep tool replaces (issue #1592).
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*(grep|rg)\s+' && \
   ! echo "$COMMAND" | grep -q '|' && \
   ! echo "$COMMAND" | grep -Eq '(grep|rg)[^|]*\s(-[a-zA-Z]*q[a-zA-Z]*(\s|$)|--quiet(\s|$))' && \
   ! echo "$COMMAND" | grep -Eq '(grep|rg)[^|]*\s(-[a-zA-Z]*[lcL][a-zA-Z]*(\s|$)|--count(\s|$)|--files-with-matches(\s|$)|--files-without-match(\s|$))'; then
    hint="Use the Grep tool for codebase searches. Example: Grep(pattern=\"foo\", path=\"src\", -n=true). Keep grep/rg for pipelines, boolean -q checks, or -l/-c filter modes."
    hint_key="grep"
fi

# ls with a glob
if [ -z "$hint" ] && \
   echo "$COMMAND" | grep -Eq '^\s*ls\s+.*\*'; then
    hint="Use the Glob tool for pattern-based file listing - it returns paths sorted by modification time and handles large directories better."
    hint_key="glob-ls"
fi

# Long pipeline (5+ pipes) fed from a discouraged head stage — demoted here
# from the bash-antipatterns.sh hard block (issues #1873, #2051, #2052).
#
# Pipes are counted PER PIPELINE, not per Bash invocation: the command is
# split on statement separators (newlines, `;`, `&&`, `||`) after stripping
# quoted strings, and the threshold applies to the longest single pipeline.
# This fixes the aggregate-count defect (#2051): five independent 1-pipe
# statements plus a printf | tee rollup no longer sum to a "6-pipe scrape".
# A discouraged head is a cat/echo/printf source or a redundant grep | grep
# text-scrape in the SAME pipeline; log-stream pipelines (kubectl logs /
# journalctl / docker logs / …) are exempt from the grep | grep clause
# (#1833). Command substitutions are not parsed — a `$( … | … )` counts
# toward its host statement, which is conservative but acceptable for a
# non-blocking nudge.
if [ -z "$hint" ]; then
    TEACH_LOG_STREAM_RE='\b(journalctl|stern)\b|\b(kubectl|oc|docker|podman|nerdctl|nomad|heroku|gcloud|crictl|flyctl|fly|k)\b[^|]*[[:space:]]logs\b'
    PIPE_MAX=0
    while IFS= read -r seg; do
        [ -z "$seg" ] && continue
        seg_pipes=$(printf '%s' "$seg" | tr -cd '|' | wc -c | tr -d ' ')
        [ "$seg_pipes" -ge 5 ] || continue
        seg_head=false
        if printf '%s\n' "$seg" | grep -Eq '\b(cat|echo|printf)[[:space:]][^|]*\|'; then
            seg_head=true
        elif ! printf '%s\n' "$seg" | grep -Eq "$TEACH_LOG_STREAM_RE" && \
             printf '%s\n' "$seg" | grep -Eq 'grep\b[^|]*\|[^|]*grep\b'; then
            seg_head=true
        fi
        if [ "$seg_head" = true ] && [ "$seg_pipes" -gt "$PIPE_MAX" ]; then
            PIPE_MAX=$seg_pipes
        fi
    done < <(echo "$COMMAND" \
        | sed "s/'[^']*'//g; s/\"[^\"]*\"//g" \
        | awk '{ gsub(/\|\|/, "\n"); gsub(/&&/, "\n"); gsub(/;/, "\n"); print }')
    if [ "$PIPE_MAX" -ge 5 ]; then
        hint="This pipeline has $PIPE_MAX pipes fed from a cat/echo/printf or redundant grep|grep head. Prefer JSON output from the source (--format=json) parsed with jq, a single awk program, or splitting into steps. A long pipeline of legitimate transforms (jq | sort | uniq -c | sort) is fine."
        hint_key="long-pipeline"
    fi
fi

# No soft-teach pattern matched - leave tool output untouched.
if [ -z "$hint" ]; then
    exit 0
fi

# Session-scoped dedup: emit each distinct hint at most once per session.
#
# updatedToolOutput is replayed on every subsequent turn (it persists in the
# transcript like any tool result), so an un-capped hint on a high-frequency
# command (grep, cat) accumulates one replayed copy per matching call for the
# rest of the session. The lesson is identical each time, so the marginal copies
# are pure transcript bloat. Teaching once per pattern caps the replay cost at
# six hint banners for an entire session regardless of call count, while still
# delivering the correction the first time the agent reaches for the idiom.
#
# State lives in a per-session file (sanitised session_id, same convention as
# git-stash-session-init.sh) and is removed by git-session-cleanup.sh at
# SessionEnd. When session_id is absent we skip dedup and fall through to the
# old always-emit behaviour rather than guess at a key.
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' | tr -cd 'a-zA-Z0-9_-')
if [ -n "$SESSION_ID" ]; then
    SEEN_DIR="${TMPDIR:-/tmp}/claude-bash-teach-seen"
    SEEN_FILE="${SEEN_DIR}/${SESSION_ID}"
    if [ -f "$SEEN_FILE" ] && grep -qxF "$hint_key" "$SEEN_FILE" 2>/dev/null; then
        # Already taught this lesson this session - leave tool output untouched.
        exit 0
    fi
    mkdir -p "$SEEN_DIR" 2>/dev/null || true
    echo "$hint_key" >> "$SEEN_FILE" 2>/dev/null || true
fi

# Build the augmented tool output: original response first, then the hint banner.
# We stringify tool_response defensively because its shape varies per Bash exit code
# and per harness version. jq's `tostring` handles strings, objects, and null.
ORIGINAL=$(echo "$INPUT" | jq -r '.tool_response | if type == "string" then . else tostring end // empty')

# Compose the augmented output. Trailing newline before the hint keeps the banner
# visually distinct from command output, especially when stdout ends without one.
AUGMENTED=$(printf '%s\n\n--- bash-antipatterns hint ---\n💡 %s\n' "$ORIGINAL" "$hint")

# Emit the PostToolUse JSON envelope. hookSpecificOutput.updatedToolOutput replaces
# what the model sees as the tool result (Claude Code 2.1.121+).
jq -n --arg out "$AUGMENTED" '{
    hookSpecificOutput: {
        hookEventName: "PostToolUse",
        updatedToolOutput: $out
    }
}'

exit 0
