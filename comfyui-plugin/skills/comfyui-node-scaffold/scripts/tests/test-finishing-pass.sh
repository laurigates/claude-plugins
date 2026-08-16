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
#   4. renovate.json emitted; NO dependabot.yml and NO renovate.yml anywhere
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
# Blocks 14-16 pin the two scaffold back-ports from issues #2186 / #2187 — the
# generator-level half of defects that had only ever been fixed on deployed
# packs (~/.claude/rules/scaffold-fix-backport.md):
#   14. the @laurigates/comfy-modal-kit pin. It sat at `^0.2.0` while the kit
#       published 0.10.0, and it is NOT Renovate-managed (a .py generator is
#       outside every customManager here, #2222), so nothing flagged the rot.
#   15. the banner tagline fits the canvas. Interpolating the full --desc at
#       font-size 44 ran off a 1344px banner, invisible until someone
#       rasterized the PNG. Fixed earlier but never pinned.
#   16. release-please keeps uv.lock's self-version in step (#2187), including
#       the two plausible-but-wrong jsonpath forms that leave it stale while
#       looking configured.
#
# Requires python3 and git; SKIPs cleanly when python3 is unavailable. Block 16's
# semantic half additionally needs `uv` and SKIPs without it; block 14's
# freshness NOTE is advisory and suppressed by SCAFFOLD_OFFLINE=1.

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
# A repo-local renovate.yml is a SECOND runner beside the gitops-managed
# autodiscover App, so every pack carried two open "Dependency Dashboard"
# issues. Deleted fleet-wide 2026-08-16; this pins the generator to match.
if [ -f "$PACK/.github/workflows/renovate.yml" ]; then
    check "no renovate.yml workflow emitted" "absent" "present"
else
    check "no renovate.yml workflow emitted" "absent" "absent"
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

# 13. Sub-family accent. comfy-registry-lifecycle documents that glyph colour
#     encodes the sub-family (#ffb02e touch/interaction, #6ba6ff info/gallery),
#     but both SVG templates hardcoded orange, so the generator could not emit
#     the rule it documented. The 2026-07-30 vector-banner restyle then flipped
#     four info/gallery packs from blue to orange against a blue icon.
python3 "$SCAFFOLD" --name comfyui-fp-info --display "FP Info" --desc "i" \
    --variant gesture --subfamily info --dir "$WORK" >/dev/null 2>&1
IPACK="$WORK/comfyui-fp-info"

for asset in icon.svg banner.svg; do
    check "info sub-family emits the blue accent in $asset" "yes" \
        "$(grep -q '#6ba6ff' "$IPACK/$asset" && echo yes || echo no)"
    check "  ...and no orange accent survives in $asset" "yes" \
        "$(grep -qiE '#(ffb02e|ff8a00|ff9a1f|ffb86b|ffce8a|b85e00)' "$IPACK/$asset" && echo no || echo yes)"
    # Guard integrity: the default sub-family must still be orange, or the
    # assertions above would pass against a template recoloured blue wholesale.
    check "touch sub-family still emits the orange accent in $asset" "yes" \
        "$(grep -q '#ffb02e' "$PACK/$asset" && echo yes || echo no)"
done

# The tile/backdrop/wordmark are neutral in BOTH sub-families. Recolouring them
# would drift the family tile and break just assets' 346x346+27+27 gate.
for tok in '#1f1f2a' '#12121a' '#2a2a36' '#f5f5f7'; do
    check "neutral $tok count is identical across sub-families" \
        "$(grep -o "$tok" "$PACK/banner.svg" | wc -l | tr -d ' ')" \
        "$(grep -o "$tok" "$IPACK/banner.svg" | wc -l | tr -d ' ')"
done

# 14. comfy-modal-kit pin (issue #2186). The template pinned `^0.2.0` — four
#     minors behind the published kit — so every pack scaffolded in between was
#     born stale and needed a manual bump before it could use current kit APIs.
#     The pin is NOT Renovate-managed (it lives in a .py generator; this repo's
#     customManagers see only skill markdown + install_pkgs.sh), so nothing
#     flagged the rot. Pin the two mechanical invariants here and print an
#     advisory freshness NOTE.
KIT_CONST="$(python3 - "$SCAFFOLD" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^MODAL_KIT_VERSION = "([^"]+)"', src, re.M)
print(m.group(1) if m else "")
PY
)"
check "MODAL_KIT_VERSION constant is readable" "yes" \
    "$([ -n "$KIT_CONST" ] && echo yes || echo no)"
# The exact stale value the issue was filed about — a literal regression pin.
check "modal-kit pin is no longer the stale ^0.2.0" "moved" \
    "$([ "$KIT_CONST" = "^0.2.0" ] && echo stale || echo moved)"
# The emitted package.json must carry the constant verbatim, or the constant
# and the template can drift and the bump above buys nothing.
KIT_EMITTED="$(python3 - "$PACK/package.json" <<'PY'
import json, sys
deps = json.load(open(sys.argv[1], encoding="utf-8")).get("dependencies", {})
print(deps.get("@laurigates/comfy-modal-kit", ""))
PY
)"
check "modal variant emits the modal-kit pin from the constant" "$KIT_CONST" "$KIT_EMITTED"
# Guard integrity: the gesture variant has no modal to hook, so it must NOT
# declare the kit — without this, the assertion above could pass against a
# template that pins the kit everywhere.
GESTURE_KIT="$(python3 - "$GPACK/package.json" <<'PY'
import json, sys
deps = json.load(open(sys.argv[1], encoding="utf-8")).get("dependencies", {})
print(deps.get("@laurigates/comfy-modal-kit", "absent"))
PY
)"
check "gesture variant declares no modal-kit dependency" "absent" "$GESTURE_KIT"

# Advisory only — never a check(). A hard failure here would turn an unrelated
# PR red the day the kit publishes a minor (the "gate red on arrival" hazard in
# .claude/rules/generated-fleet-drift.md). Bounded fetch so CI cannot hang.
if command -v npm >/dev/null 2>&1 && [ -z "${SCAFFOLD_OFFLINE:-}" ]; then
    KIT_LATEST="$(npm view @laurigates/comfy-modal-kit version \
        --fetch-timeout=5000 --fetch-retries=0 2>/dev/null | tail -1)"
    if [ -n "$KIT_LATEST" ]; then
        python3 - "$KIT_CONST" "$KIT_LATEST" <<'PY'
import sys
pin, latest = sys.argv[1], sys.argv[2]
base = pin.lstrip("^~")
pin_parts = base.split(".")
latest_parts = latest.split(".")
# Caret on a 0.x version is minor-locked: ^0.10.0 == >=0.10.0 <0.11.0.
covered = (
    pin_parts[:2] == latest_parts[:2]
    if pin.startswith("^") and pin_parts[0] == "0"
    else pin_parts[0] == latest_parts[0]
)
if not covered:
    print(
        f"NOTE: MODAL_KIT_VERSION={pin} does not cover the published latest "
        f"({latest}). This pin is not Renovate-managed (#2222) — bump it in "
        f"scaffold.py so new packs are not born stale (#2186).",
        file=sys.stderr,
    )
PY
    fi
fi

# 15. Banner tagline fit (issue #2186). The banner draws its subtitle at
#     font-size 44 from x=340 on a 1344px canvas; interpolating the full --desc
#     ran the text off the right edge, invisible until someone rasterized the
#     PNG and looked at it. Measured on a 1344x576 render: the derived 44-char
#     tagline ends at x=1210 (133px margin); the same banner carrying the full
#     166-char --desc reaches x=1343 — clipped at the edge.
MAX_TAGLINE="$(python3 - "$SCAFFOLD" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^MAX_TAGLINE_CHARS = (\d+)", src, re.M)
print(m.group(1) if m else "")
PY
)"
check "MAX_TAGLINE_CHARS constant is readable" "yes" \
    "$([ -n "$MAX_TAGLINE" ] && echo yes || echo no)"

read_tagline() { # read_tagline <pack> — the font-size 44 <text> body
    python3 - "$1/banner.svg" <<'PY'
import re, sys
svg = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'font-size="44"[^>]*>([^<]*)</text>', svg)
print(m.group(1) if m else "")
PY
}

LONG_DESC="Drag one output onto another to take over its downstream links, reroute a connection's source, and keep the graph tidy without rewiring every downstream node by hand."
python3 "$SCAFFOLD" --name comfyui-fp-longdesc --display "FP LongDesc" \
    --desc "$LONG_DESC" --variant gesture --dir "$WORK" >/dev/null 2>&1
LD="$WORK/comfyui-fp-longdesc"
LD_TAGLINE="$(read_tagline "$LD")"
check "long --desc yields a tagline within the canvas budget" "yes" \
    "$([ -n "$LD_TAGLINE" ] && [ "${#LD_TAGLINE}" -le "$MAX_TAGLINE" ] && echo yes || echo no)"
# The specific defect: the whole description reaching the SVG.
check "the full --desc never reaches banner.svg" "yes" \
    "$(grep -qF "$LONG_DESC" "$LD/banner.svg" && echo no || echo yes)"

# Guard integrity: a short --desc must survive VERBATIM. Without this, a
# template that emitted an empty (or always-truncated) tagline would satisfy
# both assertions above while destroying the subtitle.
python3 "$SCAFFOLD" --name comfyui-fp-shortdesc --display "FP ShortDesc" \
    --desc "Reroute a connection's source" --variant gesture --dir "$WORK" >/dev/null 2>&1
check "a short --desc passes through verbatim" "Reroute a connection's source" \
    "$(read_tagline "$WORK/comfyui-fp-shortdesc")"

# An author-supplied --tagline is honoured as given, not re-derived.
python3 "$SCAFFOLD" --name comfyui-fp-tagline --display "FP Tagline" \
    --desc "$LONG_DESC" --tagline "Move a link's source in one drag" \
    --variant gesture --dir "$WORK" >/dev/null 2>&1
check "--tagline overrides the derived subtitle" "Move a link's source in one drag" \
    "$(read_tagline "$WORK/comfyui-fp-tagline")"

# 16. release-please keeps uv.lock in step (issue #2187). release-please bumps
#     pyproject.toml but has no native uv.lock support
#     (googleapis/release-please#2561), so the lock's self-version trailed
#     pyproject on EVERY release (comfyui-filename-prefix at v0.1.1 and v0.1.2).
UVLOCK_JSONPATH="$(python3 - "$PACK/release-please-config.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1], encoding="utf-8"))
paths = [
    e.get("jsonpath", "")
    for pkg in cfg.get("packages", {}).values()
    for e in pkg.get("extra-files", [])
    if e.get("path") == "uv.lock" and e.get("type") == "toml"
]
print(paths[0] if len(paths) == 1 else "")
PY
)"
check "emitted config wires a toml updater for uv.lock" "yes" \
    "$([ -n "$UVLOCK_JSONPATH" ] && echo yes || echo no)"
# Both wrong forms look configured while leaving the lock stale, which is worse
# than an absent updater — verified against a real lock with release-please
# 17.11.1: `$.version` THROWS (it is the lockfile FORMAT revision, not the
# package version) and a bare `@.name==` filter is a SILENT no-op (the tagged
# TOML AST wraps scalars as {start,end,value}, so `@.name` is an object).
check "  ...that targets a [[package]] entry, not the lockfile format version" "yes" \
    "$(grep -q 'package\[?(' <<<"$UVLOCK_JSONPATH" && echo yes || echo no)"
check "  ...and reads through the tagged AST (.name.value)" "yes" \
    "$(grep -q '@\.name\.value' <<<"$UVLOCK_JSONPATH" && echo yes || echo no)"
check "  ...naming this pack" "yes" \
    "$(grep -q "comfyui-fp-demo" <<<"$UVLOCK_JSONPATH" && echo yes || echo no)"

# The audit grades it, so an existing pack that never got the updater is
# reported rather than silently drifting ("sweeps miss packs").
VERIFY_OUT="$(python3 "$SCAFFOLD" --verify "$PACK" 2>&1)"
check "--verify reports RELEASE_PLEASE_UVLOCK=wired on a fresh pack" "yes" \
    "$(grep -qx 'RELEASE_PLEASE_UVLOCK=wired' <<<"$VERIFY_OUT" && echo yes || echo no)"
# Guard integrity: strip the updater and the grade must move. Without this a
# finding hardwired to "wired" would satisfy the assertion above.
UW="$WORK/comfyui-fp-unwired"
python3 "$SCAFFOLD" --name comfyui-fp-unwired --display "FP Unwired" \
    --desc "u" --variant gesture --dir "$WORK" >/dev/null 2>&1
python3 - "$UW" <<'PY'
import json, pathlib, sys
cfg = pathlib.Path(sys.argv[1]) / "release-please-config.json"
data = json.loads(cfg.read_text(encoding="utf-8"))
for pkg in data.get("packages", {}).values():
    pkg.pop("extra-files", None)
cfg.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
VERIFY_OUT="$(python3 "$SCAFFOLD" --verify "$UW" 2>&1)"
check "--verify reports RELEASE_PLEASE_UVLOCK=unwired once stripped" "yes" \
    "$(grep -qx 'RELEASE_PLEASE_UVLOCK=unwired' <<<"$VERIFY_OUT" && echo yes || echo no)"

# Semantic half: the configured selector must actually pick the pack's own
# entry out of a lockfile uv really produced. Catches a uv format change or a
# wrong package-name substitution, neither of which the string checks can see.
if ! command -v uv >/dev/null 2>&1; then
    echo "SKIP: uv unavailable — uv.lock selector check skipped" >&2
else
    (
        cd "$PACK" || exit 1
        # Offline first so a network-less runner still gets a lock from cache;
        # fall back to a normal resolve when the cache is cold.
        uv lock --offline >/dev/null 2>&1 || uv lock >/dev/null 2>&1
    )
    if [ ! -f "$PACK/uv.lock" ]; then
        echo "SKIP: uv lock produced no lockfile (offline?) — selector check skipped" >&2
    else
        SELECTED="$(python3 - "$PACK/uv.lock" "$UVLOCK_JSONPATH" <<'PY'
import re, sys
try:
    import tomllib
except ModuleNotFoundError:  # python < 3.11
    print("SKIP")
    sys.exit(0)
name = re.search(r"@\.name\.value\s*==\s*'([^']+)'", sys.argv[2])
if not name:
    print("UNPARSEABLE")
    sys.exit(0)
lock = tomllib.load(open(sys.argv[1], "rb"))
hits = [p for p in lock.get("package", []) if p.get("name") == name.group(1)]
print(f"{len(hits)}:{hits[0].get('version') if hits else ''}")
PY
)"
        PKG_VERSION="$(grep -m1 '^version = ' "$PACK/pyproject.toml" | cut -d'"' -f2)"
        case "$SELECTED" in
            SKIP*) echo "SKIP: tomllib unavailable — selector check skipped" >&2 ;;
            *)
                check "jsonpath selects exactly one [[package]] entry in a real uv.lock" \
                    "1:$PKG_VERSION" "$SELECTED" ;;
        esac
    fi
fi

# 17. the gesture skeleton is recognizable on the FIRST pointerdown (issue
#     #2383). The emitted skeleton demonstrated a two-finger pinch, which
#     comfyui-touch-resize shipped and then removed as unfixable AS DESIGNED
#     (touch-resize#58): a pinch is not recognizable until the SECOND finger
#     lands, by which point the first finger's pointerdown has already reached
#     LiteGraph and opened a node-drag or canvas-pan transaction. Everything
#     else in that module existed only to unwind the half-open transaction —
#     including the `if (lock) e.stopImmediatePropagation()` hedge. Every
#     gesture pack scaffolded from it inherited a defect class the family had
#     already root-caused and abandoned.
GS="$WORK/comfyui-fp-gesture-shape"
python3 "$SCAFFOLD" --name comfyui-fp-gesture-shape --display "FP Gesture Shape" \
    --desc "Drag a selected node's corner handle to resize it" \
    --variant gesture --dir "$WORK" >/dev/null 2>&1
GS_SRC="$GS/src/index.ts"
GS_TEST="$GS/tests/js/index.test.js"

# Guard integrity first: without a non-empty, helper-exporting source every
# "does not contain X" assertion below passes against a generator that emits
# nothing at all.
check "gesture variant emits src/index.ts" "yes" \
    "$([ -s "$GS_SRC" ] && echo yes || echo no)"
check "gesture variant emits tests/js/index.test.js" "yes" \
    "$([ -s "$GS_TEST" ] && echo yes || echo no)"
check "  ...exporting pure geometry helpers" "yes" \
    "$(grep -qE '^export function ' "$GS_SRC" && echo yes || echo no)"

# The defect lives in CODE, not in prose: the skeleton is expected to keep
# NAMING the removed pinch so the next author learns why it went (the same
# instruction-vs-explanation split check-agent-tool-selection.sh makes), so
# every negative below runs against a comment-stripped view of the file.
code_only() { # code_only <file> — source with // and /* */ comments removed
    python3 - "$1" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
sys.stdout.write("".join(re.sub(r"//.*$", "", ln) + "\n" for ln in src.splitlines()))
PY
}
for f in "$GS_SRC" "$GS_TEST"; do
    CODE="$(code_only "$f")"
    check "no pinch* symbol in $(basename "$f")" "yes" \
        "$(grep -qi 'pinch' <<<"$CODE" && echo no || echo yes)"
    check "no stopImmediatePropagation hedge in $(basename "$f")" "yes" \
        "$(grep -q 'stopImmediatePropagation' <<<"$CODE" && echo no || echo yes)"
done
# Guard integrity for code_only(): the rationale must SURVIVE in the comments,
# or the negatives above are satisfied by a skeleton that simply deleted the
# explanation along with the code.
check "the skeleton still records why the pinch went" "yes" \
    "$(grep -q 'touch-resize#58' "$GS_SRC" && echo yes || echo no)"

# The contract the replacement must satisfy (references/variants.md § "A
# gesture must be recognizable on the FIRST pointerdown"). Each of these is a
# real invariant, not a spelling: a skeleton that dropped `pinch` but kept
# recognizing the gesture off a move stream would pass the negatives above.
check "the gesture is recognized on pointerdown" "yes" \
    "$(grep -q '"pointerdown"' "$GS_SRC" && echo yes || echo no)"
# A capture listener on an ANCESTOR precedes listeners bound on the canvas
# element whatever order they registered in; a same-element capture listener
# added at setup() fires AFTER LiteGraph's, too late to suppress anything.
GS_CODE="$(code_only "$GS_SRC")"
check "  ...at window capture, ahead of LiteGraph's own canvas listener" "yes" \
    "$(grep -q 'window.addEventListener(' <<<"$GS_CODE" && echo yes || echo no)"
check "  ...and not on the canvas element, where it would register too late" "yes" \
    "$(grep -q 'el.addEventListener(' <<<"$GS_CODE" && echo no || echo yes)"
check "  ...by hit-testing that first event" "yes" \
    "$(grep -q 'hitHandle' <<<"$GS_CODE" && echo yes || echo no)"
# touch-action would unbalance Comfy.SimpleTouchSupport's module-global
# touchCount — the "recovers only by switching apps" symptom.
check "  ...pointer-events only, never setting touch-action" "yes" \
    "$(grep -qi 'touchAction\|touch-action' <<<"$GS_CODE" && echo no || echo yes)"
check "  ...and never intercepting touchstart/touchend" "yes" \
    "$(grep -q 'touchstart\|touchend' <<<"$GS_CODE" && echo no || echo yes)"
# In-place writes bypass LGraphNode's pos/size setters and the Vue layout
# store they feed (useLayoutMutations.moveNode/.resizeNode).
check "  ...assigning geometry, never mutating in place" "yes" \
    "$(grep -qE '\.(size|pos) = ' <<<"$GS_CODE" && echo yes || echo no)"
check "  ...and never writing size[0]/pos[0] in place" "yes" \
    "$(grep -qE '\.(size|pos)\[[01]\] =' <<<"$GS_CODE" && echo no || echo yes)"
# The whole layer stays a no-op when the canvas is absent, so the native
# corner-handle resize always survives.
check "  ...no-op when app.canvas is absent" "yes" \
    "$(grep -q 'gesture layer not installed' "$GS_SRC" && echo yes || echo no)"
# The hit radius is capped and the ceiling is recorded, per the measurement in
# variants.md (body-corner handles land ~17px from the first slots).
check "  ...with a capped hit radius in CONFIG" "yes" \
    "$(grep -q 'handleHitRadius' "$GS_SRC" && echo yes || echo no)"

# The emitted vitest suite must exercise the new helpers, or the pack ships a
# green suite that tests nothing the skeleton still contains.
check "the emitted suite tests hitHandle" "yes" \
    "$(grep -q 'hitHandle' "$GS_TEST" && echo yes || echo no)"
check "the emitted suite tests resizedGeometry" "yes" \
    "$(grep -q 'resizedGeometry' "$GS_TEST" && echo yes || echo no)"
# Every symbol the suite imports must actually be exported by the source —
# an import of a deleted helper is a red suite in every generated pack.
GS_MISSING="$(python3 - "$GS_SRC" "$GS_TEST" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
test = open(sys.argv[2], encoding="utf-8").read()
exported = set(re.findall(r"^export function (\w+)", src, re.M))
imported = set()
for block in re.findall(r"import \{([^}]*)\} from \"\.\./\.\./src/index\.ts\"", test):
    imported |= {s.strip() for s in block.split(",") if s.strip()}
print(",".join(sorted(imported - exported)))
PY
)"
check "every helper the suite imports is exported by src/index.ts" "" "$GS_MISSING"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
