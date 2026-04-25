#!/usr/bin/env bash
# scripts/path-bootstrap.sh
#
# SessionStart hook: prepend Homebrew bin directories to PATH so that agent
# subshells inherit the same `head`, `jq`, `gh`, etc. that the parent
# interactive shell sees. Without this, agents spawned via non-login shells
# end up with a `/usr/bin:/bin`-only PATH and report `command not found:
# head` / `command not found: jq` despite the parent having both.
#
# This script is idempotent and safe in remote sandboxes:
#   - Only writes to $CLAUDE_ENV_FILE when the harness sets it.
#   - Only adds directories that actually exist on this machine.
#   - Does not duplicate entries that are already on PATH.
#
# Closes laurigates/claude-plugins#1111
set -euo pipefail

# No env file → nothing to persist; the harness ignores plain stdout writes
# to PATH because each tool call is a fresh subshell.
if [ -z "${CLAUDE_ENV_FILE:-}" ]; then
  exit 0
fi

# Candidate directories, in priority order. /opt/homebrew is Apple Silicon;
# /usr/local is Intel macOS / older installs / many Linux Homebrew layouts.
candidates=(
  /opt/homebrew/bin
  /opt/homebrew/sbin
  /usr/local/bin
  /usr/local/sbin
)

prepend=""
for dir in "${candidates[@]}"; do
  # Skip dirs that don't exist on this machine (e.g. remote sandbox without
  # Homebrew, or Intel-only host where /opt/homebrew is absent).
  [ -d "$dir" ] || continue
  # Skip dirs already on PATH to avoid duplication on session resume.
  case ":${PATH:-}:" in
    *":$dir:"*) continue ;;
  esac
  prepend="${prepend:+$prepend:}$dir"
done

if [ -n "$prepend" ]; then
  printf 'PATH=%s:%s\n' "$prepend" "${PATH:-/usr/bin:/bin}" >> "$CLAUDE_ENV_FILE"
fi

exit 0
