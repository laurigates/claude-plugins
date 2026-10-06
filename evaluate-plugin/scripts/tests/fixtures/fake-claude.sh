#!/usr/bin/env bash
# Stub `claude` CLI for test-rollout-headless.sh (and any other headless-harness
# test). Put a `claude` wrapper that execs this first on PATH; it never touches
# the network.
#
# Behaviour, driven by env vars (bake them into the wrapper: rollout_headless.sh
# runs the child under `env -i`, so vars exported in the test shell do NOT
# reach this stub in clean mode -- which is exactly what the scrub test needs):
#
#   FAKE_CLAUDE_FIXTURE       stream-json JSONL to replay on stdout
#                             (default: stream-skill-commit.jsonl beside this file)
#   FAKE_CLAUDE_LOG           append one invocation record here: ARG/ENV/CWD lines
#   FAKE_CLAUDE_DELAY         seconds to sleep between lines (slow emission, so
#                             --stop-on-skill and --timeout can be exercised)
#   FAKE_CLAUDE_EXIT          exit code after replaying (default 0)
#   FAKE_CLAUDE_REJECT_FLAG   if this flag is in argv, print a commander-style
#                             "unknown option" error and exit 1 with no output
#   FAKE_CLAUDE_AUTH_MARKER   if set to a NAME, emit a "Not logged in" error result
#                             unless the env var NAME is present (inherit mode
#                             keeps parent vars, clean mode drops them)
#   FAKE_CLAUDE_TOUCH         create this file (relative to cwd) before replaying,
#                             so workspace snapshots have something to copy
#
# Log record shape (one per invocation):
#   === INVOCATION ===
#   ARG\t<printf %q of each argv element>
#   ENV\t<NAME>=<value>          (values are test-only; no secrets in tests)
#   CWD\t<pwd>
#   STDIN\t<printf %q of stdin>  (rollout_headless.sh sends the prompt on stdin)
#   CREDS\tyes|no                 ($HOME/.claude/.credentials.json present?)
set -uo pipefail

stdin_text=""
[ -t 0 ] || stdin_text="$(cat)"

fixture="${FAKE_CLAUDE_FIXTURE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/stream-skill-commit.jsonl}"

if [ -n "${FAKE_CLAUDE_LOG:-}" ]; then
  {
    echo "=== INVOCATION ==="
    for a in "$@"; do printf 'ARG\t%q\n' "$a"; done
    while IFS= read -r -d '' kv; do
      printf 'ENV\t%s\n' "${kv//$'\n'/ }"
    done < <(env -0)
    printf 'CWD\t%s\n' "$(pwd -P)"
    printf 'STDIN\t%q\n' "$stdin_text"
    printf 'CREDS\t%s\n' "$([ -f "${HOME:-/nonexistent}/.claude/.credentials.json" ] && echo yes || echo no)"
  } >>"$FAKE_CLAUDE_LOG"
fi

if [ "${1:-}" = "--version" ]; then
  echo "2.1.289 (Claude Code, fake)"
  exit 0
fi

if [ -n "${FAKE_CLAUDE_REJECT_FLAG:-}" ]; then
  for a in "$@"; do
    if [ "$a" = "$FAKE_CLAUDE_REJECT_FLAG" ]; then
      echo "error: unknown option '$FAKE_CLAUDE_REJECT_FLAG'" >&2
      exit 1
    fi
  done
fi

if [ -n "${FAKE_CLAUDE_AUTH_MARKER:-}" ] && [ -z "${!FAKE_CLAUDE_AUTH_MARKER:-}" ]; then
  printf '%s\n' '{"type":"system","subtype":"init","session_id":"00000000-0000-4000-8000-000000000000","model":"claude-haiku-4-5-20251001","cwd":"/","tools":[],"plugins":[],"skills":[],"permissionMode":"default","apiKeySource":"none","claude_code_version":"2.1.289"}'
  printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login","num_turns":0,"total_cost_usd":0,"session_id":"00000000-0000-4000-8000-000000000000","duration_ms":10,"duration_api_ms":0,"usage":{}}'
  exit 1
fi

if [ -n "${FAKE_CLAUDE_TOUCH:-}" ]; then
  mkdir -p "$(dirname "$FAKE_CLAUDE_TOUCH")"
  echo "written by fake-claude" >"$FAKE_CLAUDE_TOUCH"
fi

if [ ! -f "$fixture" ]; then
  echo "fake-claude: fixture not found: $fixture" >&2
  exit 3
fi

delay="${FAKE_CLAUDE_DELAY:-0}"
while IFS= read -r line || [ -n "$line" ]; do
  printf '%s\n' "$line"
  if [ "$delay" != "0" ]; then sleep "$delay"; fi
done <"$fixture"

exit "${FAKE_CLAUDE_EXIT:-0}"
