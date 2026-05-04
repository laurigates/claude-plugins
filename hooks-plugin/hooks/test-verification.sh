#!/usr/bin/env bash
# TaskCompleted hook - runs an explicitly-fast test recipe when a team task
# completes, but only if HEAD has advanced since the session began.
#
# Three layered constraints, each independently silent:
#
#   Layer 1 (fast-recipe required) - only runs when the project defines an
#     explicit fast test recipe (just/make `test-quick` / `test-unit` /
#     `test-fast`, or a `test:quick` / `test:unit` / `test:fast` script in
#     package.json). The previous fallback to plain `just test` / `make test`
#     / `npm test` / `pytest` / `cargo test` / `go test` is gone — projects
#     with hour-long suites and no fast variant are now no-ops here.
#
#   Layer 2 (HEAD baseline) - skips when current HEAD matches the commit
#     recorded by git-stash-session-init.sh at session start. No commits
#     landed → nothing new to verify.
#
#   Layer 3 (event) - this hook is wired to TaskCompleted, not Stop, so it
#     fires once per completed Agent Teams task instead of after every
#     Claude response.
#
# A 45-second hard timeout via `timeout` keeps slow recipes from hanging the
# event. Timeouts approve with a warning rather than block the task.
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
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')

# Guard: stop_hook_active - only meaningful when the hook is wired to Stop;
# kept for safety in case a user re-attaches it there.
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

# ── Layer 2: HEAD baseline ────────────────────────────────────────────────────
# Skip when HEAD has not advanced since session start — no commits landed,
# nothing new to verify. The baseline is written by git-stash-session-init.sh.
SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9_-')
TEST_BASELINE_FILE="/tmp/claude-test-baselines/${SESSION_ID}"
if [ -n "$SESSION_ID" ] && [ -f "$TEST_BASELINE_FILE" ]; then
    BASELINE_HEAD=$(cat "$TEST_BASELINE_FILE" 2>/dev/null || true)
    CURRENT_HEAD=$(git -C "$CWD" rev-parse HEAD 2>/dev/null || true)
    if [ -n "$BASELINE_HEAD" ] && [ "$BASELINE_HEAD" = "$CURRENT_HEAD" ]; then
        exit 0
    fi
fi

# ── Source-file gate ─────────────────────────────────────────────────────────
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

# Filter out non-source files (docs, config, metadata, build recipes).
# Extensionless config/build files (justfile, Makefile, Dockerfile, ...) are
# matched by basename so an edit to the project's recipe file alone doesn't
# trigger a test run.
SOURCE_FILES=$(
    echo "$CHANGED_FILES" \
        | grep -vE '\.(md|json|yml|yaml|toml|lock|txt|cfg|ini|env|gitignore|prettierrc|eslintrc|editorconfig)$' \
        | grep -vE '(^|/)(LICENSE|justfile|[Mm]akefile|GNUmakefile|Dockerfile|Containerfile|Vagrantfile|Procfile|Rakefile|Gemfile|Pipfile)$' \
        || true
)

# Guard: no source files changed
if [ -z "$SOURCE_FILES" ]; then
    exit 0
fi

# ── Layer 1: fast-recipe detection ───────────────────────────────────────────
# Only run when the project defines an explicit fast recipe. A bare `test`
# recipe (full suite) does NOT qualify — projects with hour-long suites must
# opt in by defining a fast variant.
TEST_CMD=""

if [ -f "$CWD/justfile" ]; then
    for recipe in test-quick test-unit test-fast; do
        if grep -qE "^${recipe}([[:space:]]|:|$)" "$CWD/justfile" 2>/dev/null; then
            TEST_CMD="just $recipe"
            break
        fi
    done
fi

if [ -z "$TEST_CMD" ] && [ -f "$CWD/Makefile" ]; then
    for target in test-quick test-unit test-fast; do
        if grep -qE "^${target}:" "$CWD/Makefile" 2>/dev/null; then
            TEST_CMD="make $target"
            break
        fi
    done
fi

if [ -z "$TEST_CMD" ] && [ -f "$CWD/package.json" ]; then
    package_runner="npm run"
    if [ -f "$CWD/bun.lockb" ] || [ -f "$CWD/bun.lock" ]; then
        package_runner="bun run"
    fi
    for script_name in test:quick test:unit test:fast; do
        if jq -e --arg s "$script_name" '.scripts[$s]' "$CWD/package.json" >/dev/null 2>&1; then
            TEST_CMD="$package_runner $script_name"
            break
        fi
    done
fi

# Guard: no fast recipe found - silent no-op (Layer 1 contract)
if [ -z "$TEST_CMD" ]; then
    exit 0
fi

# ── Run the fast recipe ───────────────────────────────────────────────────────
# Hard timeout to prevent hanging. Exit code 124 = timeout killed the process.
TEST_OUTPUT=$(cd "$CWD" && timeout "$TEST_TIMEOUT" bash -c "$TEST_CMD" 2>&1) || TEST_EXIT=$?
TEST_EXIT=${TEST_EXIT:-0}

# Tests passed
if [ "$TEST_EXIT" -eq 0 ]; then
    exit 0
fi

# Timeout — don't block, just warn. A "fast" recipe that exceeds 45s is itself
# a project-hygiene signal, not a reason to interrupt the task.
if [ "$TEST_EXIT" -eq 124 ]; then
    # shellcheck disable=SC2016  # jq expression, not shell expansion
    jq -n --arg reason "Test verification timed out after ${TEST_TIMEOUT}s (${TEST_CMD}). The 'fast' recipe is no longer fast — consider trimming it." \
        '{"decision": "approve", "reason": $reason}'
    exit 0
fi

# Tests failed - extract last 20 lines as summary
SUMMARY=$(echo "$TEST_OUTPUT" | tail -20)

# Output block decision with proper JSON escaping via jq
# shellcheck disable=SC2016  # jq expression, not shell expansion
jq -n --arg reason "Test failures detected (${TEST_CMD}):\n${SUMMARY}" \
    '{"decision": "block", "reason": $reason}'
