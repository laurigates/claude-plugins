#!/usr/bin/env bash
# Stop hook - runs tests if source files were modified during the session
# Replaces the agent-based test verification hook with a deterministic script
# to eliminate LLM latency on every stop event
#
# Uses a hard timeout to prevent hanging when test suites are slow.
# Prefers quick/unit test recipes over full suites for fast feedback.
set -euo pipefail

# Hard timeout in seconds - prevents hanging on slow test suites
# The hook framework timeout (60s) doesn't reliably kill child processes,
# so we enforce our own limit via the timeout command.
TEST_TIMEOUT="${CLAUDE_HOOKS_TEST_TIMEOUT:-45}"

# Allow disabling via environment variable
if [ "${CLAUDE_HOOKS_DISABLE_TEST_VERIFICATION:-0}" = "1" ]; then
    exit 0
fi

# Read JSON input from stdin and extract fields
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Guard: stop_hook_active - prevent infinite loops
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Guard: no working directory provided
if [ -z "$CWD" ]; then
    exit 0
fi

# Guard: not a git repository
if ! git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

# Collect all changed files: staged, unstaged, and untracked
CHANGED_FILES=$(
    {
        git -C "$CWD" diff --name-only 2>/dev/null || true
        git -C "$CWD" diff --name-only --cached 2>/dev/null || true
        git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
)

# Guard: no files changed at all
if [ -z "$CHANGED_FILES" ]; then
    exit 0
fi

# Filter out non-source files (docs, config, metadata)
SOURCE_FILES=$(echo "$CHANGED_FILES" | grep -vE '\.(md|json|yml|yaml|toml|lock|txt|cfg|ini|env|gitignore|prettierrc|eslintrc|editorconfig)$' | grep -v '^LICENSE' || true)

# Guard: no source files changed
if [ -z "$SOURCE_FILES" ]; then
    exit 0
fi

# Detect test runner and build command
# Priority: explicit build recipes (justfile/Makefile) first since they handle
# venv/env setup correctly, then language-specific tool detection
TEST_CMD=""

if [ -f "$CWD/justfile" ]; then
    # Prefer fast test recipes over full suite to avoid hanging on slow tests
    if grep -q '^test-quick' "$CWD/justfile" 2>/dev/null; then
        TEST_CMD="just test-quick"
    elif grep -q '^test-unit' "$CWD/justfile" 2>/dev/null; then
        TEST_CMD="just test-unit"
    elif grep -q '^test' "$CWD/justfile" 2>/dev/null; then
        TEST_CMD="just test"
    fi
elif [ -f "$CWD/Makefile" ]; then
    if grep -q '^test-quick:' "$CWD/Makefile" 2>/dev/null; then
        TEST_CMD="make test-quick"
    elif grep -q '^test-unit:' "$CWD/Makefile" 2>/dev/null; then
        TEST_CMD="make test-unit"
    elif grep -q '^test:' "$CWD/Makefile" 2>/dev/null; then
        TEST_CMD="make test"
    fi
elif [ -f "$CWD/bun.lockb" ] || [ -f "$CWD/bun.lock" ]; then
    # Bun project - check for test script
    if [ -f "$CWD/package.json" ] && jq -e '.scripts.test' "$CWD/package.json" >/dev/null 2>&1; then
        TEST_CMD="bun run test -- --bail=1"
    fi
elif [ -f "$CWD/package.json" ] && jq -e '.scripts.test' "$CWD/package.json" >/dev/null 2>&1; then
    TEST_CMD="npm test -- --bail=1"
elif [ -f "$CWD/pytest.ini" ] || [ -f "$CWD/setup.cfg" ] && grep -q '\[tool:pytest\]' "$CWD/setup.cfg" 2>/dev/null; then
    # Use uv run if uv.lock exists (project uses uv for dependency management)
    if [ -f "$CWD/uv.lock" ]; then
        TEST_CMD="uv run pytest -x --tb=short"
    else
        TEST_CMD="pytest -x --tb=short"
    fi
elif [ -f "$CWD/pyproject.toml" ] && grep -q '\[tool\.pytest' "$CWD/pyproject.toml" 2>/dev/null; then
    if [ -f "$CWD/uv.lock" ]; then
        TEST_CMD="uv run pytest -x --tb=short"
    else
        TEST_CMD="pytest -x --tb=short"
    fi
elif [ -f "$CWD/Cargo.toml" ]; then
    TEST_CMD="cargo test"
elif [ -f "$CWD/go.mod" ]; then
    TEST_CMD="go test ./..."
fi

# Guard: no test runner found
if [ -z "$TEST_CMD" ]; then
    exit 0
fi

# Run tests with hard timeout to prevent hanging
# Exit code 124 = timeout killed the process
TEST_OUTPUT=$(cd "$CWD" && timeout "$TEST_TIMEOUT" bash -c "$TEST_CMD" 2>&1) || TEST_EXIT=$?
TEST_EXIT=${TEST_EXIT:-0}

# Tests passed
if [ "$TEST_EXIT" -eq 0 ]; then
    exit 0
fi

# Timeout - don't block, just warn and let Claude continue
if [ "$TEST_EXIT" -eq 124 ]; then
    jq -n --arg reason "Test verification timed out after ${TEST_TIMEOUT}s (${TEST_CMD}). Tests may be slow — consider adding a fast test-unit or test-quick recipe." \
        '{"decision": "warn", "reason": $reason}'
    exit 0
fi

# Tests failed - extract last 20 lines as summary
SUMMARY=$(echo "$TEST_OUTPUT" | tail -20)

# Output block decision with proper JSON escaping via jq
# shellcheck disable=SC2016  # jq expression, not shell expansion
jq -n --arg reason "Test failures detected (${TEST_CMD}):\n${SUMMARY}" \
    '{"decision": "block", "reason": $reason}'
