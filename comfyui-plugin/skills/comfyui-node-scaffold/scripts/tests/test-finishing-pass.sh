#!/usr/bin/env bash
# test-finishing-pass.sh — regression test for the scaffold "finishing pass"
# (issue #1877).
#
# The scaffold used to produce a CI-green pack that was invisibly missing the
# four registry-ready / fleet-consistent pieces (icon, banner, screenshot
# pipeline, renovate-not-dependabot). This test EXECUTES the generator and
# asserts the deterministic pieces are now emitted and wired, and that the
# finishing-pass audit surfaces the follow-ups the generator can't do itself:
#   1. icon.svg + banner.svg emitted (valid XML)
#   2. pyproject [tool.comfy] Icon/Banner point at the raw-GitHub PNG URLs
#      (never the old empty `Icon = ""`)
#   3. registry-health.yml + clear-autorelease-labels.yml workflows emitted
#   4. renovate.json emitted; NO dependabot.yml anywhere
#   5. justfile carries a `just assets` recipe (svg -> png rasterize)
#   6. README '## What it does' is no longer a bare TODO stub
#   7. the finishing-pass audit prints (icon/banner emitted + screenshot follow-up)
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

AUDIT="$(python3 "$SCAFFOLD" --name comfyui-fp-demo --display "Finishing Pass" \
    --desc "A demo pack." --variant frontend --widgets seed --dir "$WORK" 2>&1)"
PACK="$WORK/comfyui-fp-demo"

# 1. icon.svg + banner.svg emitted, valid XML.
for asset in icon.svg banner.svg; do
    if [ -f "$PACK/$asset" ] && python3 -c "import xml.dom.minidom as m; m.parse('$PACK/$asset')" 2>/dev/null; then
        check "$asset emitted as valid XML" "yes" "yes"
    else
        check "$asset emitted as valid XML" "yes" "no"
    fi
done

# 2. pyproject Icon/Banner point at the raw-GitHub PNG URLs (never empty).
if grep -q '^Icon = ""' "$PACK/pyproject.toml"; then
    check "pyproject Icon is no longer the empty stub" "wired" "empty"
else
    check "pyproject Icon is no longer the empty stub" "wired" "wired"
fi
for field in Icon Banner; do
    if grep -Eq "^${field} = \"https://raw.githubusercontent.com/.+/main/${field,,}.png\"" "$PACK/pyproject.toml"; then
        check "pyproject $field points at the raw-GitHub PNG URL" "yes" "yes"
    else
        check "pyproject $field points at the raw-GitHub PNG URL" "yes" "no"
    fi
done

# 3. registry-health + clear-autorelease workflows emitted.
for wf in registry-health.yml clear-autorelease-labels.yml; do
    if [ -f "$PACK/.github/workflows/$wf" ]; then
        check "$wf workflow emitted" "yes" "yes"
    else
        check "$wf workflow emitted" "yes" "no"
    fi
done

# 4. renovate present, dependabot absent.
if [ -f "$PACK/renovate.json" ]; then
    check "renovate.json emitted" "yes" "yes"
else
    check "renovate.json emitted" "yes" "no"
fi
if [ -f "$PACK/.github/dependabot.yml" ]; then
    check "no dependabot.yml emitted" "absent" "present"
else
    check "no dependabot.yml emitted" "absent" "absent"
fi

# 5. `just assets` rasterize recipe.
if grep -qE '^assets:' "$PACK/justfile" && grep -q 'rsvg-convert' "$PACK/justfile"; then
    check "justfile has a 'just assets' rasterize recipe" "yes" "yes"
else
    check "justfile has a 'just assets' rasterize recipe" "yes" "no"
fi

# 6. README '## What it does' is not a bare TODO stub.
if grep -Pzoq '## What it does\n\nTODO' "$PACK/README.md" 2>/dev/null; then
    check "README 'What it does' is not a bare TODO stub" "improved" "stub"
else
    check "README 'What it does' is not a bare TODO stub" "improved" "improved"
fi

# 7. The finishing-pass audit prints.
case "$AUDIT" in
    *"Finishing pass"*"screenshot pipeline"*)
        check "finishing-pass audit prints the checklist" "yes" "yes" ;;
    *)
        check "finishing-pass audit prints the checklist" "yes" "no" ;;
esac

# 8. Gesture variant also gets the finishing pass (variant-independent).
python3 "$SCAFFOLD" --name comfyui-fp-gesture --display "FP Gesture" \
    --desc "y" --variant gesture --dir "$WORK" >/dev/null 2>&1
GPACK="$WORK/comfyui-fp-gesture"
if [ -f "$GPACK/icon.svg" ] && [ -f "$GPACK/.github/workflows/registry-health.yml" ]; then
    check "gesture variant also gets icon.svg + registry-health.yml" "yes" "yes"
else
    check "gesture variant also gets icon.svg + registry-health.yml" "yes" "no"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
