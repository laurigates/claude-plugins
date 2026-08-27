#!/usr/bin/env bash
# PostToolUse hook - runs the house prose rubric over markdown the agent just
# wrote, and over the body of a `gh pr create` / `gh issue create`, augmenting
# the agent-visible tool output with the candidates it found.
#
# NEVER BLOCKS. Style is a nudge, not a gate (.claude/rules/hook-block-vs-nudge.md):
# a hard block on a style preference dead-ends subagents and needs a growing
# false-positive exemption list, and prose candidates are by construction
# judgments rather than defects. The write always succeeds; the hint rides along
# with its result.
#
# OUTPUT CONTRACT - the schema gotcha this hook inherits from
# bash-antipatterns-teach.sh: hookSpecificOutput.updatedToolOutput is validated
# against the TOOL'S OWN output schema. For Bash that is an OBJECT
# ({interrupted,isImage,noOutputExpected,stderr,stdout}); a JSON string is
# rejected ("Invalid input: expected object, received string") and the harness
# silently falls back to the original output, making the hook a no-op (#2275).
# Write/Edit responses are objects too, so the same merge-into-the-original
# approach is used for both: read tool_response, replace exactly one free-text
# field, union it back over the original object so every key the harness expects
# survives.
#
# Opt-in, matching the bash-antipatterns-teach.sh / event-logger.sh convention.

set -euo pipefail

if [ "${CLAUDE_HOOKS_ENABLE_PROSE_CHECK:-}" != "1" ]; then
    exit 0
fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

# The checker lives in a SIBLING plugin, so its path depends on how the plugins
# are laid out. In the source repo hooks-plugin and prose-plugin are siblings
# under the repo root; installed from the marketplace each plugin gets its own
# versioned cache dir (.../cache/<marketplace>/<plugin>/<version>/), so the
# sibling sits one level further up and behind a version component. Probe both,
# then the project dir, and no-op if none resolves - a hook must never fail
# because an optional sibling is absent.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REL="prose-plugin/skills/prose-check/scripts/prose-check.sh"
CHECKER=""
for candidate in \
    "$PLUGIN_ROOT/../$REL" \
    "$PLUGIN_ROOT"/../../prose-plugin/*/skills/prose-check/scripts/prose-check.sh \
    "${CLAUDE_PROJECT_DIR:-}/$REL"; do
    if [ -x "$candidate" ]; then
        CHECKER="$candidate"
        break
    fi
done
[ -n "$CHECKER" ] || exit 0

# Resolve the target file and the draft kind from the tool call.
target=""
kind="doc"
case "$TOOL_NAME" in
    Write|Edit)
        target=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
        case "$target" in
            *.md|*.markdown) ;;
            *) exit 0 ;;
        esac
        # A rule, doc, or skill body is a doc; nothing else to distinguish.
        ;;
    Bash)
        command=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
        echo "$command" | grep -Eq 'gh (pr|issue) create' || exit 0
        kind="ticket"
        # Only a --body-file draft is on disk and checkable. An inline --body is
        # already sent by the time PostToolUse fires, and a heredoc body has no
        # path at all, so there is nothing to lint in either case.
        target=$(echo "$command" | sed -n 's/.*--body-file[= ]\{1,\}\([^ ]*\).*/\1/p' | head -1 | tr -d "\"'")
        [ -n "$target" ] || exit 0
        ;;
    *) exit 0 ;;
esac

[ -f "$target" ] || exit 0

# The checker is advisory; a failure inside it must never surface as a hook
# failure on the user's write.
report=$("$CHECKER" --kind "$kind" "$target" 2>/dev/null) || exit 0

count=$(printf '%s\n' "$report" \
    | awk '/^=== PROSE CHECK ===$/{f=1} f && /^ISSUE_COUNT=/{sub(/^ISSUE_COUNT=/,""); print; exit}')
[ -n "$count" ] || exit 0
[ "$count" -gt 0 ] 2>/dev/null || exit 0

# Only the candidate rows are worth replaying; the per-layer metrics are not.
candidates=$(printf '%s\n' "$report" | grep '^  - SEVERITY=' | head -12)
[ -n "$candidates" ] || exit 0

banner=$(printf '\n--- prose house-style nudge ---\n📝 %s candidate(s) against ~/.claude/rules/communication.md in %s.\nThese are candidates for judgment, not defects - a hedge carrying real uncertainty stays.\n%s\n\nRe-run: %s --kind %s %s\n' \
    "$count" "$target" "$candidates" "$CHECKER" "$kind" "$target")

TOOL_RESPONSE=$(echo "$INPUT" | jq -c '.tool_response // null')

# Bash carries free text in .stdout; Write/Edit responses vary, so fall back to
# the whole object rendered as text rather than inventing a field name.
if [ "$TOOL_NAME" = "Bash" ]; then
    field="stdout"
else
    field="output"
fi

ORIGINAL=$(jq -r --arg f "$field" \
    'if type == "object" then (.[$f] // .stdout // .output // "")
     elif type == "string" then .
     elif type == "null" then ""
     else tostring end' <<<"$TOOL_RESPONSE")

AUGMENTED=$(printf '%s\n%s\n' "$ORIGINAL" "$banner")

# `$orig + {(field): $out}` overwrites exactly one key of the harness's own
# object and invents nothing else. When tool_response is not an object there is
# no schema to preserve, so emit the string form.
jq -n --argjson orig "$TOOL_RESPONSE" --arg out "$AUGMENTED" --arg f "$field" '
  {
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      updatedToolOutput: (
        if ($orig | type) == "object" then $orig + {($f): $out}
        else $out end
      )
    }
  }'
exit 0
