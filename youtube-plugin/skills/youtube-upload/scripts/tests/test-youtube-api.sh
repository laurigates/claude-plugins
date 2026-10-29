#!/usr/bin/env bash
# Regression tests for youtube_api.py: validation, the videos.update merge,
# and --dry-run request bodies. Auto-discovered by
# scripts/run-skill-script-tests.sh via */skills/*/scripts/tests/test-*.sh.
#
# Semantic, not syntactic: the unit tests execute the script's functions and
# its CLI in --dry-run mode and assert on the emitted request body. The case
# that matters most is the update merge -- videos.update deletes every omitted
# mutable property of a named part, so an update that sends only the new title
# wipes the description and tags. No network and no Google client libraries:
# the script imports them lazily, and one test asserts dry-run never does.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not on PATH"
    exit 0
fi

python3 -m unittest discover -s "$SCRIPT_DIR" -p 'test_youtube_api.py' 2>&1
status=$?

# --help must work without the client libraries installed.
if ! python3 "$SCRIPT_DIR/../youtube_api.py" --help >/dev/null 2>&1; then
    echo "FAIL: youtube_api.py --help" >&2
    status=1
fi

exit "$status"
