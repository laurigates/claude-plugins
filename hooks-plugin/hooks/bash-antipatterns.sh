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

# Check for commit message being written to temp file
# Pattern: cat > /tmp/commit_msg.txt or similar, often with heredoc containing conventional commit
if echo "$COMMAND" | grep -Eq 'cat\s*>\s*[^|]*commit' || \
   echo "$COMMAND" | grep -Eq "(cat|echo|printf)\s*>\s*/tmp/.*<<.*EOF" && \
   echo "$COMMAND" | grep -Eq '(feat|fix|docs|refactor|test|chore|perf|ci)(\(.+\))?[!:]'; then
    block_with_reminder "REMINDER: Use HEREDOC directly in git commit:

git commit -m \"\$(cat <<'EOF'
type(scope): description

Body text here.

Fixes #123
EOF
)\""
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

# Check for reading task output files (should use TaskOutput tool)
# Detects patterns like: cat /tmp/claude/*/tasks/*.output, tail ...tasks/...output, sleep && cat ...output
if echo "$COMMAND" | grep -Eq '(cat|tail|head).*(/tasks/|\.output)' || \
   echo "$COMMAND" | grep -Eq 'sleep.*&&.*(cat|tail)'; then
    block_with_reminder "REMINDER: Use the TaskOutput tool instead of Bash commands to read task output. The TaskOutput tool is designed for checking on background tasks - use it with the task_id parameter. Example: TaskOutput with task_id and block=false for non-blocking status checks."
fi

# Check for excessive pipe chains (5+ pipes suggest over-complexity)
# Strip heredoc body content first to avoid counting markdown table pipes
# or other literal content as shell pipe operators
COMMAND_SHELL_ONLY=$(echo "$COMMAND" | awk '
    BEGIN { ih = 0 }
    ih == 0 {
        if (match($0, /<<-?[[:space:]]*[^[:space:]]*[A-Za-z_][A-Za-z_0-9]*/)) {
            s = substr($0, RSTART)
            gsub(/<<-?[[:space:]]*/, "", s)
            gsub(/^[^A-Za-z_]+/, "", s)
            gsub(/[^A-Za-z_0-9].*/, "", s)
            if (s != "") { delim = s; ih = 1 }
            print; next
        }
        print; next
    }
    ih == 1 {
        t = $0; gsub(/^[[:space:]]+/, "", t); gsub(/[[:space:]]+$/, "", t)
        if (t == delim) { ih = 0 }
    }
')
# Strip quoted strings and || operators before counting actual shell pipes
# - Single-quoted strings contain regex alternation (grep -E '(a|b|c)')
# - Double-quoted strings may contain literal pipe characters
# - || is logical OR, not a pipe operator
PIPE_COUNT=$(echo "$COMMAND_SHELL_ONLY" | sed "s/'[^']*'//g; s/\"[^\"]*\"//g; s/||//g" | tr -cd '|' | wc -c)
if [ "$PIPE_COUNT" -ge 5 ]; then
    block_with_reminder "REMINDER: This command has $PIPE_COUNT pipes - consider simplifying. Options:
- Use JSON output from the source (--reporter=json, --format=json) and parse with jq
- Use awk for multi-step text processing in one command
- Break into multiple steps with intermediate analysis
- For test failures: use test runner's built-in summary/grouping features"
fi

# Check for multi-grep chains parsing test/task output
# Pattern: grep ... | grep ... with sed/cut suggests parsing structured output as text
if echo "$COMMAND" | grep -Eq 'grep.*\|.*grep.*\|.*(sed|cut|awk)' && \
   echo "$COMMAND" | grep -Eq '(\.output|/tasks/|Error|fail|FAIL)'; then
    block_with_reminder "REMINDER: Parsing test output with grep chains is fragile. Better alternatives:
- Use --reporter=json (Bun, Vitest, Jest) and parse with jq
- Use --reporter=junit for CI-style XML output
- Check test runner docs for built-in failure grouping options
- For Bun: 'bun test --reporter=json 2>&1 | jq .testResults'"
fi

# Check for broad git staging commands (git add -A, git add --all, git add .)
# These can accidentally include sensitive files (.env, credentials) or large binaries.
# Pattern handles git global flags like -C <path> before the subcommand.
if echo "$COMMAND" | grep -Eq '^\s*git\s+(.+\s+)?add\s+(-A|--all|\.(\s|$))'; then
    block_with_reminder "REMINDER: Avoid broad staging commands like 'git add -A', 'git add --all', or 'git add .'.
These can accidentally include sensitive files (.env, credentials) or large binaries.

Instead, stage specific files by name:
  git add src/file1.ts src/file2.ts

Or review what would be staged first:
  git status --porcelain"
fi

# Check for chained git commands (git X && git Y)
# This pattern can cause index.lock race conditions where the lock from the first
# command hasn't been released before the second command tries to acquire it.
# The fix is to run git commands as separate Bash calls, not chained.
if echo "$COMMAND" | grep -Eq 'git\s+\S+.*&&.*git\s+\S+'; then
    block_with_reminder "REMINDER: Chaining git commands with '&&' can cause index.lock race conditions.
The lock file from the first command may not be released before the second runs.
Instead of: git fetch && git switch -c branch
Run git commands as separate Bash tool calls:
1. git fetch
2. git switch -c branch
This avoids race conditions and is more reliable."
fi

# Check for git reset --hard (destructive operation, usually unnecessary)
# After pushing commits to a PR branch, agents sometimes think they need to reset main.
# However, once the PR is merged, git pull will cleanly resolve the situation.
# Exclude heredocs (<<) so commit messages mentioning "git reset" don't trigger this.
if echo "$COMMAND" | grep -Eq '^\s*git\s+reset\s+--hard' && \
   ! echo "$COMMAND" | grep -Eq '<<'; then
    block_with_reminder "REMINDER: 'git reset --hard' is destructive and usually unnecessary.

COMMON SCENARIO - Accidentally committed to main, then pushed to a PR branch:
Once the PR is merged on GitHub, the local main branch resolves itself cleanly
when you run 'git pull'. Wait for the merge, then pull.

Use these alternatives instead:
- Sync with remote after PR merge: use 'git pull' - it resolves everything
- Discard uncommitted changes: use 'git checkout -- <file>' or 'git restore <file>'
- Undo a local commit (not pushed): use 'git reset --soft HEAD~1' (keeps changes staged)
- Switch branches cleanly: use 'git stash' then 'git checkout <branch>'

FOR THE 'ACCIDENTAL COMMIT TO MAIN' CASE: Wait for the PR to merge, then
'git pull' on main will fast-forward to include your commits. Problem solved.

IF THIS COMMAND IS TRULY REQUIRED (rare - corrupted git state):
Ask the user to run it manually with:
1. The exact command: $COMMAND
2. Why it's needed for this specific situation
3. What alternatives you tried"
fi

# Check for git push -u that would set main/master tracking to a feature branch.
# Pattern: git push -u origin <branch> (no colon refspec) while on main/master
# but pushing to a differently-named branch — this sets main's upstream to
# origin/<feature-branch>, which is wrong.
# Correct form: git push origin main:<feature-branch> (explicit refspec, no -u)
if echo "$COMMAND" | grep -Eq '^\s*git\s+push\b' && \
   echo "$COMMAND" | grep -Eq '\s-u\b' && \
   echo "$COMMAND" | grep -Eq '\sorigin\s+[a-zA-Z0-9._/-]+\s*$' && \
   ! echo "$COMMAND" | grep -q ':'; then
    PUSH_BRANCH=$(echo "$COMMAND" | grep -oE 'origin\s+[a-zA-Z0-9._/-]+' | awk '{print $2}')
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [ -n "$CURRENT_BRANCH" ] && [ -n "$PUSH_BRANCH" ] && \
       [ "$CURRENT_BRANCH" != "$PUSH_BRANCH" ] && \
       { [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; }; then
        block_with_reminder "REMINDER: 'git push -u origin $PUSH_BRANCH' while on '$CURRENT_BRANCH' will set $CURRENT_BRANCH to track origin/$PUSH_BRANCH instead of origin/$CURRENT_BRANCH.

This is the main-branch development pattern: push to a remote feature branch WITHOUT -u:
  git push origin $CURRENT_BRANCH:$PUSH_BRANCH

The -u flag is only correct when local and remote branch names match:
  git push -u origin $CURRENT_BRANCH  (pushes main to origin/main)"
    fi
fi

# If we get here, the command is allowed
exit 0
