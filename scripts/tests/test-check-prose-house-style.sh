#!/usr/bin/env bash
# Regression tests for scripts/check-prose-house-style.sh.
#
# Run: bash scripts/tests/test-check-prose-house-style.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Every invariant is PAIRED: a clean fixture that must pass beside a broken one
# that must fail. A guard that only ever sees green output is indistinguishable
# from a guard that cannot fire -- an all-green run asserts nothing on its own.
#
# The fixture is a COPY OF THE REAL ARTEFACTS, not a retyped stand-in. A
# hand-written imitation of SignificanceAssertion.yml would test the imitation;
# copying prose-plugin/ and hooks-plugin/ wholesale means these cases exercise
# the files that actually ship.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GUARD="$SCRIPT_DIR/check-prose-house-style.sh"
PASS=0
FAIL=0

WORK=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then echo "bad sandbox dir" >&2; exit 1; fi
trap 'rm -rf "$WORK"' EXIT

# seed ROOT -- a pristine copy of the real artefacts the guard inspects.
seed() {
    local root="$1"
    rm -rf "$root"
    mkdir -p "$root/scripts"
    cp -R "$REPO_ROOT/prose-plugin" "$root/prose-plugin"
    cp -R "$REPO_ROOT/hooks-plugin" "$root/hooks-plugin"
    cp "$GUARD" "$root/scripts/"
}

# expect NAME EXPECTED_STATUS ROOT
expect() {
    local name="$1" want="$2" root="$3" got
    got=$("$GUARD" "$root" 2>&1 | sed -n 's/^STATUS=//p' | head -1)
    if [ "$got" = "$want" ]; then
        PASS=$((PASS + 1))
        echo "PASS: $name (STATUS=$got)"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $name — wanted STATUS=$want, got STATUS=${got:-<none>}"
        "$GUARD" "$root" 2>&1 | sed -n '/^ISSUES:/,$p' | head -6
    fi
}

# --- baseline: the shipped tree is clean -----------------------------------
expect "shipped tree passes" OK "$REPO_ROOT"

# --- 1. a significance marker dropped from the vale rule -------------------
R="$WORK/sig"; seed "$R"
grep -v 'precisely why' "$R/prose-plugin/styles/House/SignificanceAssertion.yml" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/styles/House/SignificanceAssertion.yml"
expect "dropped significance marker is caught" ERROR "$R"

# --- 2. vale rule and script layer drift apart -----------------------------
# The rule keeps all four markers but the script loses one. Both layers encode
# the same list; a guard that only checked one would miss this.
R="$WORK/drift"; seed "$R"
sed 's/|precisely why//' "$R/prose-plugin/skills/prose-check/scripts/positional-tics.py" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/skills/prose-check/scripts/positional-tics.py"
expect "vale/script marker drift is caught" ERROR "$R"

# --- 3. E-Prime re-enabled --------------------------------------------------
R="$WORK/eprime"; seed "$R"
grep -v 'write-good.E-Prime = NO' "$R/prose-plugin/styles/.vale.ini" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/styles/.vale.ini"
expect "E-Prime disable removed is caught" ERROR "$R"

# --- 4. third-party styles loaded wholesale --------------------------------
# The measured failure this prevents: BasedOnStyles = write-good produced 37
# E-Prime alerts out of 47 on communication.md.
R="$WORK/wholesale"; seed "$R"
sed 's/^BasedOnStyles = House$/BasedOnStyles = House, write-good, proselint/' \
    "$R/prose-plugin/styles/.vale.ini" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/styles/.vale.ini"
expect "wholesale write-good load is caught" ERROR "$R"

# --- 5. a House rule loses its link: back to the owning rule ---------------
R="$WORK/link"; seed "$R"
grep -v '^link:' "$R/prose-plugin/styles/House/Filler.yml" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/styles/House/Filler.yml"
expect "missing link: is caught" ERROR "$R"

# --- 6. the hard-wrap join removed from the script -------------------------
# Without it pysbd splits on every newline and communication.md measures 78
# sentences / 8.2 mean words instead of 46 / 15.2. Plausible, and wrong.
R="$WORK/unwrap"; seed "$R"
sed 's/join(s.strip() for s in buf)/join(buf)/' \
    "$R/prose-plugin/skills/prose-check/scripts/positional-tics.py" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/skills/prose-check/scripts/positional-tics.py"
expect "removed hard-wrap join is caught" ERROR "$R"

# --- 7. the hook turned into a blocker -------------------------------------
R="$WORK/block"; seed "$R"
printf '\nexit 2\n' >> "$R/hooks-plugin/hooks/prose-house-style-nudge.sh"
expect "hook that blocks is caught" ERROR "$R"

# --- 8. the hook deregistered from the manifest ----------------------------
R="$WORK/unreg"; seed "$R"
grep -v 'prose-house-style-nudge.sh' "$R/hooks-plugin/.claude-plugin/plugin.json" > "$R/tmp" \
    && mv "$R/tmp" "$R/hooks-plugin/.claude-plugin/plugin.json"
expect "unregistered hook is caught" ERROR "$R"

# --- 9. candidates-not-verdicts framing dropped ----------------------------
R="$WORK/verdicts"; seed "$R"
grep -v 'FINDINGS_ARE=candidates_for_judgment_not_defects' \
    "$R/prose-plugin/skills/prose-check/scripts/prose-check.sh" > "$R/tmp" \
    && mv "$R/tmp" "$R/prose-plugin/skills/prose-check/scripts/prose-check.sh"
expect "dropped candidates-not-verdicts marker is caught" ERROR "$R"

# --- 10. a House rule that fires on nothing --------------------------------
# The defect this catches actually shipped: TicketPlaceholder's five `raw:`
# entries were concatenated by vale into one impossible pattern instead of being
# OR'd, so the rule matched nothing and its output was identical to a clean
# document. Token-presence checks pass on such a rule; only running it does not.
#
# Requires vale. Without it the guard reports RULES_EXERCISED=skipped_no_vale
# and cannot fire, so asserting ERROR here would be asserting the tool's absence.
if command -v vale >/dev/null 2>&1; then
    R="$WORK/silent"; seed "$R"
    sed 's/^  - somewhat$/  - zzzzznevermatches/; /^  - arguably$/d; /^  - it could be said that$/d; /^  - in a sense$/d' \
        "$R/prose-plugin/styles/House/Hedge.yml" > "$R/tmp" \
        && mv "$R/tmp" "$R/prose-plugin/styles/House/Hedge.yml"
    expect "House rule that matches nothing is caught" ERROR "$R"
else
    echo "SKIP: House rule that matches nothing — vale not on PATH"
fi

# --- 11. an unmodified copy still passes -----------------------------------
# The negative control for every case above: if a pristine copy of the tree
# failed, the failures above would prove nothing about the specific break.
R="$WORK/clean"; seed "$R"
expect "pristine copy still passes" OK "$R"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
