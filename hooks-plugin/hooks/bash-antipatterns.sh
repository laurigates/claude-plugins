#!/bin/bash
# PreToolUse hook for Bash tool - detects anti-patterns and reminds Claude
# to use built-in tools instead of shell commands

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the command from the tool input
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# If no command, allow it
if [ -z "$COMMAND" ]; then
    exit 0
fi

# Function to output a blocking message (exit code 2 = blocking error)
block_with_reminder() {
    local message="$1"
    echo "$message" >&2
    exit 2
}

# Check for cat used to read files (but allow cat in pipelines and heredocs)
# Patterns: cat file, cat /path/file, cat "./file"
if echo "$COMMAND" | grep -Eq '^\s*cat\s+[^|><]' && \
   ! echo "$COMMAND" | grep -Eq '<<|cat\s*>'; then
    block_with_reminder "REMINDER: Use the Read tool instead of 'cat' to read files. The Read tool provides better context with line numbers and handles large files appropriately."
fi

# Check for head/tail used to read files (not in pipelines)
if echo "$COMMAND" | grep -Eq '^\s*(head|tail)\s+(-[0-9n]+\s+)?[^|]' && \
   ! echo "$COMMAND" | grep -q '|'; then
    block_with_reminder "REMINDER: Use the Read tool with offset/limit parameters instead of 'head' or 'tail'. Example: Read with offset=100, limit=50 to read specific lines."
fi

# Check for sed used for editing (in-place edits)
if echo "$COMMAND" | grep -Eq "sed\s+(-i|--in-place)"; then
    block_with_reminder "REMINDER: Use the Edit tool instead of 'sed -i' to modify files. The Edit tool provides safer, more precise string replacements with proper error handling."
fi

# Check for awk used for file modifications
if echo "$COMMAND" | grep -Eq "awk\s+.*>\s*['\"]?[^|]+" && \
   echo "$COMMAND" | grep -Eq "(>|>>)\s*['\"]?\\\$"; then
    block_with_reminder "REMINDER: Use the Edit tool instead of 'awk' for file modifications. The Edit tool is safer and more precise."
fi

# Check for cat/echo writing to files (not heredocs in valid bash scripts)
if echo "$COMMAND" | grep -Eq '(^|\s)(echo|printf)\s+.*>\s*[^&]' && \
   ! echo "$COMMAND" | grep -Eq '(echo|printf).*>>\s*/dev/null'; then
    # Allow echo to /dev/null, but warn about file writes
    if echo "$COMMAND" | grep -Eq '(echo|printf)\s+[^>]+>\s*[a-zA-Z/\.]'; then
        block_with_reminder "REMINDER: Use the Write tool instead of 'echo/printf > file' to create files. The Write tool properly handles file creation and provides better error handling."
    fi
fi

# Check for cat > file (writing files)
if echo "$COMMAND" | grep -Eq 'cat\s*>\s*[^|]'; then
    block_with_reminder "REMINDER: Use the Write tool instead of 'cat > file' to create files. The Write tool is the proper way to write file contents."
fi

# Check for timeout command
if echo "$COMMAND" | grep -Eq '^\s*timeout\s+'; then
    block_with_reminder "REMINDER: The 'timeout' command is usually unnecessary - the Bash tool has its own timeout parameter. Human approval time typically exceeds any timeout value anyway. Remove the timeout wrapper and use the command directly."
fi

# Check for find command (should use Glob)
if echo "$COMMAND" | grep -Eq '^\s*find\s+' && \
   ! echo "$COMMAND" | grep -Eq 'find\s+.*-exec'; then
    block_with_reminder "REMINDER: Use the Glob tool instead of 'find' for file pattern matching. Glob is faster and optimized for codebase searches. Example: Glob with pattern '**/*.ts' instead of 'find . -name \"*.ts\"'"
fi

# Check for grep/rg command (should use Grep tool)
if echo "$COMMAND" | grep -Eq '^\s*(grep|rg)\s+' && \
   ! echo "$COMMAND" | grep -q '|'; then
    block_with_reminder "REMINDER: Use the Grep tool instead of 'grep' or 'rg' commands. The Grep tool is optimized for codebase searches with proper permissions and result formatting."
fi

# Check for ls used for file listing (should often use Glob)
if echo "$COMMAND" | grep -Eq '^\s*ls\s+.*\*'; then
    block_with_reminder "REMINDER: Consider using the Glob tool for pattern-based file listing. Glob provides sorted results by modification time and handles large directories better."
fi

# If we get here, the command is allowed
exit 0
