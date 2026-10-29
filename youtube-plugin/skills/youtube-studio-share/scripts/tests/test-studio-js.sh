#!/usr/bin/env bash
# Regression tests for the YouTube Studio page scripts (env.js, probe.js,
# studio.js). Auto-discovered by scripts/run-skill-script-tests.sh via
# */skills/*/scripts/tests/test-*.sh.
#
# Two layers:
#   1. `node --check` on every script (syntax).
#   2. studio-fixture.test.mjs: the scripts run in jsdom against a fixture
#      edit page in English and Finnish. It pins the safety behaviour --
#      "Notify via email" ends unchecked, the share is left unsaved until
#      save(), a wrong-domain tab fails before ticking anything, a visible
#      error stops the flow, whoami never returns credential-shaped ytcfg keys.
#      The fixture is not Studio's real DOM; live selectors are verified by
#      probe() in a real session.
#
# jsdom is installed into a temp dir on each run (pinned, no lockfile in the
# repo). Without node or network the fixture layer SKIPs, and says so.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSDOM_VERSION="30.1.1"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node not on PATH"
    exit 0
fi

status=0
for f in env.js probe.js studio.js; do
    if ! node --check "$SCRIPT_DIR/../$f"; then
        echo "FAIL: node --check $f" >&2
        status=1
    fi
done

if ! command -v npm >/dev/null 2>&1; then
    echo "SKIP: npm not on PATH; fixture tests not run"
    exit "$status"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
if ! npm install --silent --no-audit --no-fund --prefix "$tmp" "jsdom@${JSDOM_VERSION}" >/dev/null 2>&1; then
    echo "SKIP: could not install jsdom@${JSDOM_VERSION}; fixture tests not run"
    exit "$status"
fi

# Run directly: node:test executes the file's tests and exits non-zero on a
# failure; the jsdom location is passed as an argument.
node "$SCRIPT_DIR/studio-fixture.test.mjs" "$tmp/node_modules" 2>&1 || status=1

exit "$status"
