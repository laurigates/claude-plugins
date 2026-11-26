#!/usr/bin/env bash
# Config-isolation sweep: clean-slate vs plugins-only vs full.
#
# Holds model + effort + system_prompt fixed and varies ONLY the global config
# surface (via a per-arm $HOME; see arm-prep.sh / docs/config-arms.md). Runs from
# a neutral fixture repo so no project .mcp.json / .claude confounds the arms.
#
# The isolated arms have no OAuth login, so this needs a subscription token:
# exported, or read from the OS keychain through fnox. One-time:
#   claude setup-token, then:  fnox -c ~/.config/fnox/local.toml set CLAUDE_CODE_OAUTH_TOKEN
#
# Usage: run-config.sh [--filter <glob>] [--runs <n>] [--run-id <id>]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Exported token wins; otherwise read it from the keychain through fnox.
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && command -v fnox >/dev/null 2>&1; then
  CLAUDE_CODE_OAUTH_TOKEN="$(fnox get CLAUDE_CODE_OAUTH_TOKEN 2>/dev/null || true)"
fi
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: no CLAUDE_CODE_OAUTH_TOKEN (or ANTHROPIC_API_KEY) exported or in the keychain." >&2
  echo "       Run:  claude setup-token" >&2
  echo "       Then: fnox -c ~/.config/fnox/local.toml set CLAUDE_CODE_OAUTH_TOKEN" >&2
  exit 1
fi
export CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}"
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN}" ]; then
  echo "[run-config] auth: subscription token (len ${#CLAUDE_CODE_OAUTH_TOKEN})"
else
  echo "[run-config] auth: ANTHROPIC_API_KEY"
fi

# Prep the per-arm fake HOMEs and the neutral fixture repo.
bash "$here/arm-prep.sh"
fixture="${CLAUDE_PROBE_FIXTURE:-/tmp/claude-probe-fixture}"
bash "$here/make-fixture.sh" "$fixture"
echo "[run-config] fixture cwd: $fixture"

# Run the three arms from the fixture cwd. run-suite reads tests/conditions by
# absolute path and writes results under claude-probe/, so cwd can be the fixture.
( cd "$fixture" && bash "$here/run-suite.sh" --conditions cfg-clean,cfg-plugins,cfg-full "$@" )
