#!/bin/bash
# Pre-compact primer hook
# Generates customInstructions for the compaction process to preserve key context.
# This extracts active work state from the transcript and tells the compaction
# what information to prioritize in the summary.

set -euo pipefail

# Read hook input from stdin
input=$(cat)

transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

if [ -z "$transcript_path" ] || [ ! -f "$transcript_path" ]; then
  # No transcript available, output minimal instructions
  echo '{"systemMessage":"When compacting this conversation, prioritize preserving: current task objectives, files being modified, decisions made, blockers encountered."}'
  exit 0
fi

# Extract context from transcript
primer_parts=()

# 1. Extract the most recent todo state (last TodoWrite result)
recent_todos=$(tac "$transcript_path" | jq -r '
  select(.type == "tool_result" or .type == "tool_use")
  | select(.tool_name == "TodoWrite" or .name == "TodoWrite")
' 2>/dev/null | head -1)

if [ -n "$recent_todos" ]; then
  primer_parts+=("the current todo/task list state and progress on each item")
fi

# 2. Extract recently modified files (from Write/Edit tool uses)
modified_files=$(jq -r '
  select(.type == "tool_use")
  | select(.name == "Write" or .name == "Edit")
  | .input.file_path // empty
' "$transcript_path" 2>/dev/null | sort -u | tail -20)

if [ -n "$modified_files" ]; then
  file_list=$(echo "$modified_files" | tr '\n' ', ' | sed 's/,$//')
  primer_parts+=("files actively being modified: ${file_list}")
fi

# 3. Check for git operations (indicates commit/branch context)
git_context=$(jq -r '
  select(.type == "tool_use")
  | select(.name == "Bash")
  | .input.command // empty
  | select(startswith("git "))
' "$transcript_path" 2>/dev/null | tail -5)

if [ -n "$git_context" ]; then
  primer_parts+=("git workflow state (branch, uncommitted changes, recent commits)")
fi

# 4. Check for test/build commands (indicates development cycle state)
dev_commands=$(jq -r '
  select(.type == "tool_use")
  | select(.name == "Bash")
  | .input.command // empty
  | select(test("(npm|bun|yarn|pnpm|pytest|cargo|go) (test|build|run|check)"))
' "$transcript_path" 2>/dev/null | tail -3)

if [ -n "$dev_commands" ]; then
  primer_parts+=("test/build results and any failures that need fixing")
fi

# Build the custom instructions
base_instruction="When compacting this conversation, prioritize preserving:"
instructions="$base_instruction"

if [ ${#primer_parts[@]} -gt 0 ]; then
  for part in "${primer_parts[@]}"; do
    instructions="$instructions\n- $part"
  done
else
  instructions="$base_instruction\n- current task objectives and progress\n- files being modified and their purpose\n- key decisions and constraints discovered\n- any blockers or errors encountered"
fi

instructions="$instructions\n- the overall goal the user is working toward\n- any architectural decisions or constraints discovered\n- error messages or issues that still need resolution"

# Output as systemMessage JSON
escaped_instructions=$(echo -e "$instructions" | jq -Rs .)
echo "{\"systemMessage\":${escaped_instructions}}"
exit 0
