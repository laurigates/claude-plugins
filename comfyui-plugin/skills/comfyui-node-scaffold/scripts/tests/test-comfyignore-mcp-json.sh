#!/usr/bin/env bash
# test-comfyignore-mcp-json.sh — regression test: the generated .comfyignore
# excludes the repo-level .mcp.json (issue #3838).
#
# Every pack receives a repo-level .mcp.json from the gitops claude-config sync.
# comfy-cli ships every git-tracked file .comfyignore does not match, so the
# generated tests/test_publish_hygiene.py failed with "Files would ship in the
# registry tarball that are not classified as runtime content: ['.mcp.json']".
# The packs were fixed by hand; this pins the scaffold back-port. It EXECUTES
# the generator for every variant and asserts:
#   1. .comfyignore lists `.mcp.json` as its own line (syntactic floor)
#   2. the generated hygiene test, run against a pack with a git-tracked
#      .mcp.json, passes test_only_expected_runtime_paths_ship (semantic: the
#      pattern actually matches under comfy-cli's gitwildmatch rules), and
#   3. the same test FAILS when .mcp.json is removed from .comfyignore
#      (paired control: proves (2) is not passing vacuously)
#
# Requires python3 and git; SKIPs cleanly without them. Checks 2-3 need the
# `pathspec` module (or `uv` to supply it) and SKIP without either.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="${SCRIPT_DIR}/../../scaffold.py"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

if ! command -v python3 >/dev/null 2>&1 || ! command -v git >/dev/null 2>&1; then
    echo "SKIP: python3 or git not available" >&2
    exit 0
fi
if [ ! -f "$SCAFFOLD" ]; then
    echo "FAIL: scaffold.py not found at $SCAFFOLD" >&2
    exit 1
fi

WORK="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

# Pick an interpreter that can import pathspec, or none.
PY_CMD=()
if python3 -c 'import pathspec' >/dev/null 2>&1; then
    PY_CMD=(python3)
elif command -v uv >/dev/null 2>&1 \
    && uv run --quiet --no-project --with pathspec python3 -c 'import pathspec' >/dev/null 2>&1; then
    PY_CMD=(uv run --quiet --no-project --with pathspec python3)
fi

# Runs the generated runtime-path test standalone against pack $1.
run_runtime_paths_test() {
    "${PY_CMD[@]}" -c "
import sys
sys.path.insert(0, sys.argv[1] + '/tests')
import test_publish_hygiene as t
t.test_only_expected_runtime_paths_ship()
" "$1" 2>&1
}

for variant in frontend backend gesture shim; do
    name="comfyui-mcpjson-${variant}"
    python3 "$SCAFFOLD" --name "$name" --display "Mcpjson ${variant}" \
        --desc "x" --variant "$variant" --dir "$WORK" >/dev/null 2>&1
    P="$WORK/$name"

    if grep -qx '\.mcp\.json' "$P/.comfyignore" 2>/dev/null; then
        check "$variant: .comfyignore lists .mcp.json" "present" "present"
    else
        check "$variant: .comfyignore lists .mcp.json" "present" "absent"
    fi

    [ "${#PY_CMD[@]}" -gt 0 ] || continue

    # A synced repo-level .mcp.json, git-tracked like in a real pack.
    printf '{"mcpServers": {}}\n' > "$P/.mcp.json"
    git -C "$P" init -q -b main >/dev/null 2>&1
    git -C "$P" add -A >/dev/null 2>&1

    OUT="$(run_runtime_paths_test "$P")"; RC=$?
    check "$variant: hygiene test passes with a tracked .mcp.json" "0" "$RC"
    [ "$RC" -eq 0 ] || printf '%s\n' "$OUT" >&2

    # Control: drop the exclusion and the same test must name .mcp.json.
    grep -vx '\.mcp\.json' "$P/.comfyignore" > "$P/.comfyignore.tmp"
    mv "$P/.comfyignore.tmp" "$P/.comfyignore"
    OUT="$(run_runtime_paths_test "$P")"; RC=$?
    check "$variant: control — hygiene test fails without the exclusion" "1" "$RC"
    check "$variant: control — failure names .mcp.json" "yes" \
        "$(grep -q "'\.mcp\.json'" <<<"$OUT" && echo yes || echo no)"
done

if [ "${#PY_CMD[@]}" -eq 0 ]; then
    echo "SKIP: pathspec unavailable (no module, no uv) — executed checks skipped" >&2
fi

echo
echo "test-comfyignore-mcp-json.sh: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
