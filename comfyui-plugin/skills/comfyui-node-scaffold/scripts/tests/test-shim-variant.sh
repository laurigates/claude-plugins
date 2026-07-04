#!/usr/bin/env bash
# test-shim-variant.sh — regression test for the CSS/shim scaffold variant
# (issue #1930).
#
# The scaffold previously offered only frontend/backend/gesture. A pack whose
# whole job is injecting scoped CSS + registering commands (no modal, no
# comfy-modal-kit) — like comfyui-touch-shim — had to be scaffolded as a
# standalone-modal skeleton and then hand-gutted. This test EXECUTES the
# generator and asserts:
#   1. shim variant → CSS-shim index.ts (SHIMS registry + applyCssShim/
#      removeCssShim, NO comfy-modal-kit import, NO openModalShell); package.json
#      has NO comfy-modal-kit dependency but DOES add the jsdom devDep; the
#      vitest suite asserts the shim <style> lifecycle
#   2. frontend + --widgets → the widget-intercept index.ts is UNCHANGED (has
#      `const TARGET_WIDGETS`, no SHIMS, no jsdom) — guards against the shim
#      branch over-applying to the modal variants
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

# 1. Shim variant.
python3 "$SCAFFOLD" --name comfyui-shim-probe --display "Shim Probe" \
    --desc "x" --variant shim --dir "$WORK" >/dev/null 2>&1
SH="$WORK/comfyui-shim-probe"
SH_INDEX="$SH/src/index.ts"
SH_TEST="$SH/tests/js/index.test.js"
SH_PKG="$SH/package.json"

if [ ! -f "$SH_INDEX" ]; then
    echo "FAIL: shim scaffold did not produce src/index.ts" >&2
    exit 1
fi

# The CSS-shim registry + lifecycle are the load-bearing exports.
if grep -q 'export const SHIMS' "$SH_INDEX"; then
    check "shim index.ts declares the SHIMS registry" "present" "present"
else
    check "shim index.ts declares the SHIMS registry" "present" "absent"
fi
if grep -q 'export function applyCssShim' "$SH_INDEX"; then
    check "shim index.ts exports applyCssShim()" "present" "present"
else
    check "shim index.ts exports applyCssShim()" "present" "absent"
fi
if grep -q 'export function removeCssShim' "$SH_INDEX"; then
    check "shim index.ts exports removeCssShim()" "present" "present"
else
    check "shim index.ts exports removeCssShim()" "present" "absent"
fi
# No modal-kit dependency: neither an import from the package nor openModalShell.
if grep -qE 'import .* from "@laurigates/comfy-modal-kit"' "$SH_INDEX"; then
    check "shim index.ts does NOT import the modal kit" "absent" "present"
else
    check "shim index.ts does NOT import the modal kit" "absent" "absent"
fi
if grep -q 'openModalShell' "$SH_INDEX"; then
    check "shim index.ts does NOT use openModalShell" "absent" "present"
else
    check "shim index.ts does NOT use openModalShell" "absent" "absent"
fi
if grep -q 'const TARGET_WIDGETS' "$SH_INDEX"; then
    check "shim index.ts has NO widget-intercept vein" "absent" "present"
else
    check "shim index.ts has NO widget-intercept vein" "absent" "absent"
fi
# package.json: no comfy-modal-kit runtime dep, but the jsdom devDep is added.
if grep -q 'comfy-modal-kit' "$SH_PKG"; then
    check "shim package.json has NO comfy-modal-kit dependency" "absent" "present"
else
    check "shim package.json has NO comfy-modal-kit dependency" "absent" "absent"
fi
if grep -q '"jsdom"' "$SH_PKG"; then
    check "shim package.json declares jsdom devDependency" "present" "present"
else
    check "shim package.json declares jsdom devDependency" "present" "absent"
fi
# vitest suite asserts the shim <style> lifecycle under jsdom.
if grep -q '@vitest-environment jsdom' "$SH_TEST"; then
    check "shim smoke test runs under jsdom" "present" "present"
else
    check "shim smoke test runs under jsdom" "present" "absent"
fi
if grep -q 'applyCssShim' "$SH_TEST" && grep -q 'removeCssShim' "$SH_TEST"; then
    check "shim smoke test exercises the apply/remove lifecycle" "present" "present"
else
    check "shim smoke test exercises the apply/remove lifecycle" "present" "absent"
fi

# 2. Frontend + widgets: the shim branch must NOT over-apply.
python3 "$SCAFFOLD" --name comfyui-widget-probe --display "Widget Probe" \
    --desc "x" --variant frontend --widgets ckpt_name --dir "$WORK" >/dev/null 2>&1
WG="$WORK/comfyui-widget-probe"
WG_INDEX="$WG/src/index.ts"
WG_PKG="$WG/package.json"

if grep -q 'const TARGET_WIDGETS' "$WG_INDEX"; then
    check "widget variant keeps the intercept vein" "present" "present"
else
    check "widget variant keeps the intercept vein" "present" "absent"
fi
if grep -q 'export const SHIMS' "$WG_INDEX"; then
    check "widget variant does NOT emit the shim registry" "absent" "present"
else
    check "widget variant does NOT emit the shim registry" "absent" "absent"
fi
if grep -q 'comfy-modal-kit' "$WG_PKG"; then
    check "widget variant keeps the comfy-modal-kit dependency" "present" "present"
else
    check "widget variant keeps the comfy-modal-kit dependency" "present" "absent"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
