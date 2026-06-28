#!/usr/bin/env bash
# test-standalone-variant.sh — regression test for the standalone-modal scaffold
# variant (issue #1806).
#
# Before the fix, `scaffold.py --variant backend` with NO --widgets emitted the
# per-widget intercept "vein" (TARGET_WIDGETS / openPicker / enhanceNode /
# widget.onPointerDown) — wrong for a backend pack whose UI is a standalone
# modal opened from a toolbar button / command. This test EXECUTES the generator
# and asserts:
#   1. backend + no widgets  → standalone index.ts (no `const TARGET_WIDGETS`,
#      has `openShell` + `actionBarButtons`) and the jsdom modal-mount smoke test
#      + jsdom in devDependencies
#   2. backend + widgets     → the widget-intercept index.ts is UNCHANGED
#      (has `const TARGET_WIDGETS`, no `openShell`, no jsdom) — guards against
#      the standalone branch over-applying
#
# Requires python3; SKIPs cleanly when it is unavailable.

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

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available" >&2
    exit 0
fi
if [ ! -f "$SCAFFOLD" ]; then
    echo "FAIL: scaffold.py not found at $SCAFFOLD" >&2
    exit 1
fi

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# 1. Standalone variant: backend, no --widgets.
python3 "$SCAFFOLD" --name comfyui-sb-standalone --display "SB Standalone" \
    --desc "x" --variant backend --dir "$WORK" >/dev/null 2>&1
SB="$WORK/comfyui-sb-standalone"
SB_INDEX="$SB/src/index.ts"
SB_TEST="$SB/tests/js/index.test.js"
SB_PKG="$SB/package.json"

# `const TARGET_WIDGETS` is the widget-vein declaration; the standalone index.ts
# only mentions TARGET_WIDGETS in an explanatory comment, never declares it.
if grep -q 'const TARGET_WIDGETS' "$SB_INDEX"; then
    check "standalone index.ts has NO widget-intercept vein" "absent" "present"
else
    check "standalone index.ts has NO widget-intercept vein" "absent" "absent"
fi
if grep -q 'export function openShell' "$SB_INDEX"; then
    check "standalone index.ts exports openShell()" "present" "present"
else
    check "standalone index.ts exports openShell()" "present" "absent"
fi
if grep -q 'actionBarButtons' "$SB_INDEX"; then
    check "standalone index.ts registers an action-bar launcher" "present" "present"
else
    check "standalone index.ts registers an action-bar launcher" "present" "absent"
fi
if grep -q '@vitest-environment jsdom' "$SB_TEST"; then
    check "standalone smoke test runs under jsdom" "present" "present"
else
    check "standalone smoke test runs under jsdom" "present" "absent"
fi
if grep -q 'openShell' "$SB_TEST"; then
    check "standalone smoke test mounts the modal (openShell)" "present" "present"
else
    check "standalone smoke test mounts the modal (openShell)" "present" "absent"
fi
if grep -q '"jsdom"' "$SB_PKG"; then
    check "standalone package.json declares jsdom devDependency" "present" "present"
else
    check "standalone package.json declares jsdom devDependency" "present" "absent"
fi

# 2. Widget variant: backend WITH --widgets. The standalone branch must NOT apply.
python3 "$SCAFFOLD" --name comfyui-sb-widget --display "SB Widget" \
    --desc "x" --variant backend --widgets ckpt_name --dir "$WORK" >/dev/null 2>&1
WG="$WORK/comfyui-sb-widget"
WG_INDEX="$WG/src/index.ts"
WG_PKG="$WG/package.json"

if grep -q 'const TARGET_WIDGETS' "$WG_INDEX"; then
    check "widget variant keeps the intercept vein" "present" "present"
else
    check "widget variant keeps the intercept vein" "present" "absent"
fi
if grep -q 'export function openShell' "$WG_INDEX"; then
    check "widget variant does NOT emit standalone openShell" "absent" "present"
else
    check "widget variant does NOT emit standalone openShell" "absent" "absent"
fi
if grep -q '"jsdom"' "$WG_PKG"; then
    check "widget variant does NOT add jsdom" "absent" "present"
else
    check "widget variant does NOT add jsdom" "absent" "absent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
