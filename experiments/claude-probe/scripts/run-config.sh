#!/usr/bin/env bash
# Config-isolation sweep: clean-slate vs plugins-only vs full.
#
# Holds model + effort + system_prompt fixed and varies ONLY the global config
# surface (via a per-arm $HOME; see arm-prep.sh / docs/config-arms.md). Runs from
# a neutral fixture repo so no project .mcp.json / .claude confounds the arms.
#
# The isolated arms have no OAuth login, so this sources a subscription token
# from ~/.api_tokens. One-time:  claude setup-token
#   then:  echo 'export CLAUDE_CODE_OAUTH_TOKEN="sk-ant-oat01-..."' >> ~/.api_tokens
#
# Usage: run-config.sh [--filter <glob>] [--runs <n>] [--run-id <id>]
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load auth token without letting a stray line in ~/.api_tokens abort the run.
if [ -f "$HOME/.api_tokens" ]; then
  set +e +u
  set -a
  # shellcheck disable=SC1091
  . "$HOME/.api_tokens" 2>/dev/null
  set +a
  set -e -u
fi
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: no CLAUDE_CODE_OAUTH_TOKEN (or ANTHROPIC_API_KEY) in ~/.api_tokens." >&2
  echo "       Run:  claude setup-token" >&2
  echo "       Then: echo 'export CLAUDE_CODE_OAUTH_TOKEN=\"<token>\"' >> ~/.api_tokens" >&2
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
