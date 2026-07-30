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
# A printed audit is not a gate, though: comfyui-touch-manager published with
# `Icon = ""` for weeks and comfyui-output-swap deferred `just assets` for 31
# hours AFTER its audit flagged it, both caught only by a human. So this test
# also covers the two gates that replaced the note:
#   9.  `--verify <pack>` re-runs the audit against an existing pack and emits
#       STATUS=ERROR / exit 1 while the PNGs are missing...
#   10. ...and STATUS=OK / exit 0 once finished (the gate is achievable, not
#       aspirational — without this, an always-ERROR gate would pass test 9)
#   11. the emitted tests/test_publish_hygiene.py actually FAILS when the PNGs
#       [tool.comfy] points at are missing, PASSES when they exist, and FAILS
#       again when the PLACEHOLDER-GLYPH marker survives. Executed, not grepped:
#       asserting the test's TEXT is emitted is a syntactic gate on a semantic
#       property, which is exactly how the #1417 fix shipped broken.
#   12. the two gates AGREE. The first cut shipped a pack test asserting only
#       "at least one asset declared" while --verify graded an undeclared key
#       ERROR, so a pack with Icon and no Banner was "ready" per CI and
#       "broken" per the audit (comfyui-image-browser sat in that gap).
#
# Requires python3 and git; SKIPs cleanly when python3 is unavailable.

set -uo pipefail

# Neutralize inherited git context (#1745): an exported GIT_DIR/GIT_WORK_TREE
# overrides `git -C`, so the sandbox git ops below would mutate the real shared
# checkout instead of the throwaway pack.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
    GIT_NAMESPACE GIT_PREFIX

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

# 7. The finishing-pass audit prints — and grades. A flat `[ ]` list made a
#    publish-blocking gap look identical to a deferrable one, which is how
#    "tracked, not blocking" became a defensible read of a missing icon.
check "finishing-pass audit prints the checklist" "yes" \
    "$(grep -q 'Finishing pass' <<<"$AUDIT" && echo yes || echo no)"
check "audit grades the missing PNGs as ERROR" "yes" \
    "$(grep -q 'ERROR' <<<"$AUDIT" && echo yes || echo no)"
check "audit grades the screenshot follow-up as WARN" "yes" \
    "$(grep -qi 'screenshot' <<<"$AUDIT" && grep -q 'WARN' <<<"$AUDIT" && echo yes || echo no)"
# The pointer is what makes the audit re-runnable instead of a one-shot note.
check "audit points at the re-runnable --verify gate" "yes" \
    "$(grep -q -- '--verify' <<<"$AUDIT" && echo yes || echo no)"

# 8. Gesture variant also gets the finishing pass (variant-independent).
python3 "$SCAFFOLD" --name comfyui-fp-gesture --display "FP Gesture" \
    --desc "y" --variant gesture --dir "$WORK" >/dev/null 2>&1
GPACK="$WORK/comfyui-fp-gesture"
if [ -f "$GPACK/icon.svg" ] && [ -f "$GPACK/.github/workflows/registry-health.yml" ]; then
    check "gesture variant also gets icon.svg + registry-health.yml" "yes" "yes"
else
    check "gesture variant also gets icon.svg + registry-health.yml" "yes" "no"
fi

# --- The gates that replaced the printed note -------------------------------

GATE="$WORK/comfyui-fp-gate"
python3 "$SCAFFOLD" --name comfyui-fp-gate --display "FP Gate" \
    --desc "z" --variant gesture --dir "$WORK" >/dev/null 2>&1

# 9. --verify on an unfinished pack: ERROR + exit 1, naming the missing PNG.
VERIFY_OUT="$(python3 "$SCAFFOLD" --verify "$GATE" 2>&1)"
VERIFY_RC=$?
check "--verify exits 1 on an unfinished pack" "1" "$VERIFY_RC"
check "--verify reports STATUS=ERROR" "yes" \
    "$(grep -qx 'STATUS=ERROR' <<<"$VERIFY_OUT" && echo yes || echo no)"
check "--verify reports ICON_PNG=missing" "yes" \
    "$(grep -qx 'ICON_PNG=missing' <<<"$VERIFY_OUT" && echo yes || echo no)"
check "--verify reports PLACEHOLDER_GLYPH=present" "yes" \
    "$(grep -qx 'PLACEHOLDER_GLYPH=present' <<<"$VERIFY_OUT" && echo yes || echo no)"

# 10. Guard integrity: once finished, --verify must go green. Without this a
#     gate hardwired to ERROR would satisfy test 9 while being useless.
touch "$GATE/icon.png" "$GATE/banner.png"
python3 - "$GATE" <<'PY'
import pathlib, sys
pack = pathlib.Path(sys.argv[1])
for svg in ("icon.svg", "banner.svg"):
    p = pack / svg
    p.write_text(p.read_text().replace("PLACEHOLDER-GLYPH", "BESPOKE"))
PY
VERIFY_OUT="$(python3 "$SCAFFOLD" --verify "$GATE" 2>&1)"
VERIFY_RC=$?
check "--verify exits 0 once the ERRORs are cleared" "0" "$VERIFY_RC"
check "--verify reports ICON_PNG=present" "yes" \
    "$(grep -qx 'ICON_PNG=present' <<<"$VERIFY_OUT" && echo yes || echo no)"

# 11. The emitted pack test must actually fail/pass, not merely exist.
if ! command -v git >/dev/null 2>&1; then
    echo "SKIP: git unavailable — pack-test execution checks skipped" >&2
else
    PT="$WORK/comfyui-fp-pytest"
    python3 "$SCAFFOLD" --name comfyui-fp-pytest --display "FP Pytest" \
        --desc "w" --variant gesture --dir "$WORK" >/dev/null 2>&1
    check "emitted pack ships tests/test_publish_hygiene.py" "yes" \
        "$([ -f "$PT/tests/test_publish_hygiene.py" ] && echo yes || echo no)"

    git -C "$PT" init -b main >/dev/null 2>&1
    git -C "$PT" add -A >/dev/null 2>&1

    # Runs the one test standalone — it needs only git + a regex, so no dev
    # group and no pathspec install (the template imports pathspec lazily).
    run_asset_test() {
        python3 -c "
import sys
sys.path.insert(0, sys.argv[1] + '/tests')
import test_publish_hygiene as t
t.test_registry_display_assets_present()
" "$1" 2>&1
    }

    OUT="$(run_asset_test "$PT")"; RC=$?
    check "pack test FAILS while icon.png is missing" "1" "$RC"
    check "  ...and names the fix command" "yes" \
        "$(grep -q "just assets" <<<"$OUT" && echo yes || echo no)"

    touch "$PT/icon.png" "$PT/banner.png"
    python3 - "$PT" <<'PY'
import pathlib, sys
pack = pathlib.Path(sys.argv[1])
for svg in ("icon.svg", "banner.svg"):
    p = pack / svg
    p.write_text(p.read_text().replace("PLACEHOLDER-GLYPH", "BESPOKE"))
PY
    git -C "$PT" add -A >/dev/null 2>&1
    run_asset_test "$PT" >/dev/null 2>&1
    check "pack test PASSES once the PNGs are committed" "0" "$?"

    # Placeholder art is as user-visible as no art: re-arming the marker must
    # re-fail even though both PNGs now exist.
    python3 - "$PT" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "icon.svg"
p.write_text(p.read_text().replace("BESPOKE", "PLACEHOLDER-GLYPH"))
PY
    OUT="$(run_asset_test "$PT")"; RC=$?
    check "pack test FAILS again on a surviving PLACEHOLDER-GLYPH" "1" "$RC"
    check "  ...and says to re-run the rasterize" "yes" \
        "$(grep -q "PLACEHOLDER-GLYPH" <<<"$OUT" && echo yes || echo no)"

    # An untracked PNG is not a shipped PNG — the registry serves from the repo.
    rm -f "$PT/icon.png"
    python3 - "$PT" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "icon.svg"
p.write_text(p.read_text().replace("PLACEHOLDER-GLYPH", "BESPOKE"))
PY
    git -C "$PT" rm --cached icon.png >/dev/null 2>&1
    touch "$PT/icon.png"   # exists on disk, absent from the index
    OUT="$(run_asset_test "$PT")"; RC=$?
    check "pack test FAILS on an untracked icon.png" "1" "$RC"

    # 12. The two gates must agree. The first cut of this fix shipped a pack
    #     test asserting only "at least one asset declared" while --verify
    #     graded an undeclared key ERROR — so a pack with `Icon` and no
    #     `Banner` was simultaneously "ready" (CI) and "broken" (audit).
    #     comfyui-image-browser sat in exactly that gap. Both gates now
    #     require BOTH keys, and this block proves they move together.
    DV="$WORK/comfyui-fp-divergence"
    python3 "$SCAFFOLD" --name comfyui-fp-divergence --display "FP Divergence" \
        --desc "v" --variant gesture --dir "$WORK" >/dev/null 2>&1
    git -C "$DV" init -b main >/dev/null 2>&1

    finish_pack() { # finish_pack <pack> — rasterize + commit both PNGs
        touch "$1/icon.png" "$1/banner.png"
        python3 - "$1" <<'PY'
import pathlib, sys
pack = pathlib.Path(sys.argv[1])
for svg in ("icon.svg", "banner.svg"):
    p = pack / svg
    p.write_text(p.read_text().replace("PLACEHOLDER-GLYPH", "BESPOKE"))
PY
        git -C "$1" add -A >/dev/null 2>&1
    }

    # 12a. Guard integrity: a fully finished pack is green on BOTH gates.
    #      Without this, 12b would also pass against a gate hardwired to fail.
    finish_pack "$DV"
    run_asset_test "$DV" >/dev/null 2>&1
    check "agreement: finished pack PASSES the pack test" "0" "$?"
    python3 "$SCAFFOLD" --verify "$DV" >/dev/null 2>&1
    check "agreement: finished pack passes --verify (exit 0)" "0" "$?"

    # 12b. Drop ONLY the Banner key — every PNG stays present and tracked, so
    #      the sole difference is the undeclared key. Both gates must fail.
    python3 - "$DV" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / "pyproject.toml"
kept = [ln for ln in p.read_text().splitlines(True) if not ln.startswith("Banner = ")]
p.write_text("".join(kept))
PY
    git -C "$DV" add -A >/dev/null 2>&1
    check "divergence fixture actually dropped the Banner key" "absent" \
        "$(grep -q '^Banner = ' "$DV/pyproject.toml" && echo present || echo absent)"

    OUT="$(run_asset_test "$DV")"; RC=$?
    check "undeclared Banner FAILS the pack test" "1" "$RC"
    check "  ...and names the missing Banner key" "yes" \
        "$(grep -q 'Banner is unset' <<<"$OUT" && echo yes || echo no)"

    VERIFY_OUT="$(python3 "$SCAFFOLD" --verify "$DV" 2>&1)"; VERIFY_RC=$?
    check "undeclared Banner makes --verify exit 1" "1" "$VERIFY_RC"
    check "  ...with STATUS=ERROR (the same verdict as the pack test)" "yes" \
        "$(grep -qx 'STATUS=ERROR' <<<"$VERIFY_OUT" && echo yes || echo no)"
    check "  ...reported as BANNER_PNG=undeclared" "yes" \
        "$(grep -qx 'BANNER_PNG=undeclared' <<<"$VERIFY_OUT" && echo yes || echo no)"
    # The Icon half must stay green, or "both gates fail" proves nothing about
    # which key drove the failure.
    check "  ...while the still-declared Icon stays ICON_PNG=present" "yes" \
        "$(grep -qx 'ICON_PNG=present' <<<"$VERIFY_OUT" && echo yes || echo no)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
