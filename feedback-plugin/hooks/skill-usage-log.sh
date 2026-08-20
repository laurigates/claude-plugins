#!/usr/bin/env bash
# Skill-usage logger — appends one JSONL record per skill invocation so usage
# survives transcript rotation and is cheap to aggregate.
#
# Two events, because skills arrive by two different paths:
#   PreToolUse(Skill|SlashCommand) → model-invoked skill      (src=tool)
#   UserPromptSubmit               → user-typed /command      (src=slash)
# A user-typed slash command never reaches a tool: the client expands it into
# the prompt itself, so a PreToolUse hook alone misses every one of them.
#
# Output: ~/.claude/skill-usage.jsonl  (override: CLAUDE_SKILL_USAGE_LOG)
# Opt in:  CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG=1  (disabled by default)
#
# Consumed by scripts/skill_usage_report.py, which the weekly `friction-learner`
# slow loop reads to decide WHICH skills are worth analysing.
#
# NEVER write to stdout. A UserPromptSubmit hook's stdout is injected into the
# model's context, so any output here would leak into every single turn.
#
# No -e: telemetry must never break a turn. Every failure path exits 0.
set -uo pipefail

# Opt-in guard — disabled by default. Every turn pays a UserPromptSubmit fire,
# and the log is only useful to someone who intends to analyse it later.
[ "${CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG:-0}" = "1" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)

FIELDS=$(printf '%s' "$INPUT" | jq -r '
    [ .hook_event_name // "-",
      .tool_name       // "-",
      .session_id      // "-",
      .cwd             // "-",
      .permission_mode // "-",
      (.effort.level   // "-") ] | @tsv' 2>/dev/null) || exit 0
IFS=$'\t' read -r EVENT TOOL SESSION CWD MODE EFFORT <<< "$FIELDS"

SKILL=""
ARGS=""
SRC=""

case "$EVENT" in
    PreToolUse)
        case "$TOOL" in
            Skill | SlashCommand) ;;
            *) exit 0 ;;
        esac
        # Skill tool: {"skill": "...", "args": "..."} (args optional).
        # SlashCommand tool: {"command": "/name ..."}.
        SKILL=$(printf '%s' "$INPUT" | jq -r '.tool_input.skill // .tool_input.command // ""' 2>/dev/null)
        ARGS=$(printf '%s' "$INPUT" | jq -r '.tool_input.args // ""' 2>/dev/null)
        SKILL=${SKILL#/}
        SRC="tool"
        ;;
    UserPromptSubmit)
        PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)
        # Accept both the raw typed form ("/git:git-pr fix") and the wrapped
        # form some clients expand it into (<command-name>/git:git-pr</...>).
        if [[ "$PROMPT" == *"<command-name>"* ]]; then
            PROMPT=${PROMPT#*<command-name>}
            PROMPT=${PROMPT%%</command-name>*}
        fi
        PROMPT=${PROMPT#"${PROMPT%%[![:space:]]*}"}
        [[ "$PROMPT" == /* ]] || exit 0
        FIRST=${PROMPT%%[[:space:]]*}
        SKILL=${FIRST#/}
        ARGS=${PROMPT#"$FIRST"}
        ARGS=${ARGS#"${ARGS%%[![:space:]]*}"}
        SRC="slash"
        ;;
    *) exit 0 ;;
esac

# A bare "/" or an empty tool_input yields nothing to attribute.
[ -n "$SKILL" ] || exit 0
# Guard against a path being mistaken for a command ("/tmp/foo.txt ...").
case "$SKILL" in */*) exit 0 ;; esac

PLUGIN="-"
case "$SKILL" in *:*) PLUGIN=${SKILL%%:*} ;; esac

ARGS_LEN=${#ARGS}
ARGS=${ARGS:0:300}

REPO="-"
BRANCH="-"
# Guard the path: git -C "" silently falls back to the process CWD.
if [ -n "$CWD" ] && [ "$CWD" != "-" ] && [ -d "$CWD" ]; then
    TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || TOP=""
    if [ -n "$TOP" ]; then
        REPO=$(basename "$TOP")
        BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null) || BRANCH=""
        [ -n "$BRANCH" ] || BRANCH="-"
    fi
fi

TS=$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
LOG="${CLAUDE_SKILL_USAGE_LOG:-$HOME/.claude/skill-usage.jsonl}"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0

# Rotate at 16 MB so the log can never grow unbounded.
if [ -f "$LOG" ]; then
    SIZE=$(wc -c < "$LOG" 2>/dev/null | tr -d ' ')
    if [ "${SIZE:-0}" -gt 16777216 ] 2>/dev/null; then
        mv -f "$LOG" "$LOG.1" 2>/dev/null || true
    fi
fi

# jq -nc does the JSON escaping, so an arg containing quotes or newlines can
# never corrupt the log.
jq -nc \
    --arg ts "$TS" \
    --arg src "$SRC" \
    --arg skill "$SKILL" \
    --arg plugin "$PLUGIN" \
    --arg args "$ARGS" \
    --argjson args_len "$ARGS_LEN" \
    --arg session "$SESSION" \
    --arg cwd "$CWD" \
    --arg repo "$REPO" \
    --arg branch "$BRANCH" \
    --arg mode "$MODE" \
    --arg effort "$EFFORT" \
    '{v: 1, ts: $ts, src: $src, skill: $skill, plugin: $plugin,
      args: $args, args_len: $args_len, session: $session,
      cwd: $cwd, repo: $repo, branch: $branch,
      permission_mode: $mode, effort: $effort}' >> "$LOG" 2>/dev/null || true

exit 0
