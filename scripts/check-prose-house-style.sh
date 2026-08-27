#!/usr/bin/env bash
# check-prose-house-style.sh -- semantic guard for the derived prose rubric.
#
# THE CONVENTION
# ~/.claude/rules/communication.md is the canonical house prose rubric.
# prose-plugin/styles/House/*.yml and prose-check's positional-tics.py are a
# DERIVED ENCODING of it, kept deliberately so per
# documentation-plugin:docs-single-source: the rule files carry `link:` pointers
# rather than restating the rationale.
#
# WHY A SEMANTIC GUARD (.claude/rules/regression-testing.md)
# A derived copy with no gate drifts silently. Every one of these files stays
# YAML-valid and shell-valid while losing the token that makes it do its job --
# an agent "tightening" SignificanceAssertion.yml can drop "precisely why" and
# nothing parses differently. The syntactic floor is worthless here; what has to
# be asserted is that the load-bearing tokens survive.
#
# The guard runs BOTH directions where it can:
#   - the four significance markers this script hardcodes are the ones
#     communication.md itself lists, and they must appear in the vale rule AND
#     in positional-tics.py, so the two layers cannot drift apart;
#   - the Filler / Hedge / ThroatClearing token lists must match the lists in
#     prose-distill/SKILL.md, which is where they are actually written. That
#     cross-check is what stops the vale rules becoming a second source.
#
# Output: structured KEY=VALUE per .claude/rules/structured-script-output.md.
#   --strict  exit 1 when ISSUE_COUNT > 0 (for pre-commit / CI). Default: report.

set -uo pipefail

STRICT=0
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        *) [ -d "$arg" ] && ROOT_DIR="$(cd "$arg" && pwd)" ;;
    esac
done

STYLES="$ROOT_DIR/prose-plugin/styles"
HOUSE="$STYLES/House"
SKILL_DIR="$ROOT_DIR/prose-plugin/skills/prose-check"
TICS="$SKILL_DIR/scripts/positional-tics.py"
ORCH="$SKILL_DIR/scripts/prose-check.sh"
DISTILL="$ROOT_DIR/prose-plugin/skills/prose-distill/SKILL.md"
HOOK="$ROOT_DIR/hooks-plugin/hooks/prose-house-style-nudge.sh"
HOOK_MANIFEST="$ROOT_DIR/hooks-plugin/.claude-plugin/plugin.json"

# The three portentous nouns communication.md names, plus the mirrored-clause
# opener from its own worked example. Changing this list means the rubric
# changed; update the rule file first, then here.
SIGNIFICANCE_MARKERS=("which is the" "what makes" "the thing that" "precisely why")

issue_count=0
files_checked=0
declare -a issues=()

fail() { issue_count=$((issue_count + 1)); issues+=("  - $1"); }

require() {
    local file="$1" token="$2" msg="$3" rel="${1#"$ROOT_DIR"/}"
    if [ ! -f "$file" ]; then
        fail "SEVERITY=ERROR FILE=$rel MSG=missing file ($msg)"
        return
    fi
    grep -qiF -- "$token" "$file" || \
        fail "SEVERITY=ERROR FILE=$rel TOKEN=\"$token\" MSG=$msg"
}

# extract_distill_tokens LEVEL_LABEL -- pull the quoted token list out of
# prose-distill's Hierarchy of Cuts, so the vale rules are checked against the
# place those lists are actually written rather than against a second copy here.
extract_distill_tokens() {
    grep -m1 -F -- "**$1**" "$DISTILL" 2>/dev/null \
        | grep -oE '"[^"]+"' | tr -d '"'
}

# --- 1. significance markers, both layers ----------------------------------
SIG_RULE="$HOUSE/SignificanceAssertion.yml"
for marker in "${SIGNIFICANCE_MARKERS[@]}"; do
    require "$SIG_RULE" "$marker" "significance marker dropped from the vale rule"
    if [ -f "$TICS" ]; then
        grep -qiF -- "$marker" "$TICS" || \
            fail "SEVERITY=ERROR FILE=${TICS#"$ROOT_DIR"/} TOKEN=\"$marker\" MSG=vale rule and script layer disagree on the significance markers"
    fi
done
[ -f "$SIG_RULE" ] && files_checked=$((files_checked + 1))

# --- 2. derived token lists match prose-distill ----------------------------
if [ -f "$DISTILL" ]; then
    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        require "$HOUSE/Filler.yml" "$tok" "filler token diverged from prose-distill level 2"
    done < <(extract_distill_tokens "Filler words")

    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        require "$HOUSE/Hedge.yml" "$tok" "hedge token diverged from prose-distill level 3"
    done < <(extract_distill_tokens "Hedge words")

    while IFS= read -r tok; do
        [ -n "$tok" ] || continue
        require "$HOUSE/ThroatClearing.yml" "$tok" "throat-clearing token diverged from prose-distill level 4"
    done < <(extract_distill_tokens "Throat-clearing")
else
    fail "SEVERITY=ERROR FILE=prose-plugin/skills/prose-distill/SKILL.md MSG=missing; the Filler/Hedge/ThroatClearing lists have no source to check against"
fi

# --- 3. E-Prime stays off ---------------------------------------------------
# Measured at 37 alerts out of 47 on communication.md -- 79% noise from one rule.
# Loading write-good wholesale would silently reintroduce it, so the disable is
# asserted rather than assumed.
VALE_INI="$STYLES/.vale.ini"
require "$VALE_INI" "write-good.E-Prime = NO" "E-Prime re-enabled or the explicit disable removed"
if [ -f "$VALE_INI" ] && grep -qE '^BasedOnStyles\s*=.*(write-good|proselint)' "$VALE_INI"; then
    fail "SEVERITY=ERROR FILE=${VALE_INI#"$ROOT_DIR"/} MSG=write-good/proselint loaded via BasedOnStyles; the third-party rules must stay a curated allowlist"
fi

# --- 4. every House rule links back to its owning rule ----------------------
if [ -d "$HOUSE" ]; then
    while IFS= read -r yml; do
        files_checked=$((files_checked + 1))
        grep -qE '^link:\s*http' "$yml" || \
            fail "SEVERITY=ERROR FILE=${yml#"$ROOT_DIR"/} MSG=no link: back to the rule that owns this criterion (docs-single-source)"
        grep -qE '^extends:\s*\w+' "$yml" || \
            fail "SEVERITY=ERROR FILE=${yml#"$ROOT_DIR"/} MSG=no extends: -- not a valid vale rule"
    done < <(find "$HOUSE" -name '*.yml' -type f | sort)
else
    fail "SEVERITY=ERROR FILE=prose-plugin/styles/House MSG=House style package missing"
fi

# --- 5. the metric rule keeps its formula ----------------------------------
require "$HOUSE/MeanSentenceLength.yml" "extends: metric" "mean-sentence-length rule is no longer a metric rule"
require "$HOUSE/MeanSentenceLength.yml" "words / sentences" "mean-sentence-length formula changed"

# --- 6. the script layer keeps the unwrapping step -------------------------
# Without joining hard wraps, pysbd splits on every newline and communication.md
# measures 78 sentences / 8.2 mean words instead of 46 / 15.2 -- wrong numbers
# that look plausible. The join is the single most droppable line in the file.
require "$TICS" "join(s.strip() for s in buf)" "hard-wrap joining removed; sentence counts will silently go wrong"
require "$TICS" "pysbd" "segmenter swapped away from pysbd (47/48 on the Golden Rules Set)"

# --- 7. candidates-not-verdicts framing + the mechanics survive ------------
#
# Checked across the skill's prose as a WHOLE, not against SKILL.md alone. The
# repo's `split` CI job auto-extracts reference sections into REFERENCE.md when
# a SKILL.md grows -- it did exactly that to this skill -- so pinning a token to
# one filename makes the guard fail on a relocation that lost nothing. What has
# to survive is the claim, wherever the split puts it.
require_in_skill() {
    local token="$1" msg="$2" f
    for f in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/REFERENCE.md"; do
        if [ -f "$f" ] && grep -qiF -- "$token" "$f"; then
            return
        fi
    done
    fail "SEVERITY=ERROR FILE=prose-plugin/skills/prose-check/{SKILL,REFERENCE}.md TOKEN=\"$token\" MSG=$msg"
}

require_in_skill "candidates" "skill prose no longer frames findings as candidates rather than defects"
require_in_skill "raw" "skill prose dropped the vale raw:-concatenation trap, the defect that shipped a rule matching nothing"
require_in_skill "hard wrap" "skill prose dropped the load-bearing unwrapping step"
require "$ORCH" "FINDINGS_ARE=candidates_for_judgment_not_defects" "orchestrator rollup dropped the candidates-not-verdicts marker"

# --- 8. the hook nudges, never blocks --------------------------------------
require "$HOOK" "CLAUDE_HOOKS_ENABLE_PROSE_CHECK" "hook lost its opt-in guard"
require "$HOOK" "updatedToolOutput" "hook no longer augments output; it may have become a blocker"
if [ -f "$HOOK" ] && grep -qE '^\s*exit\s+2\b' "$HOOK"; then
    fail "SEVERITY=ERROR FILE=${HOOK#"$ROOT_DIR"/} MSG=hook exits 2 (blocks); style must nudge, not block (hook-block-vs-nudge.md)"
fi
if [ -f "$HOOK_MANIFEST" ] && command -v jq >/dev/null 2>&1; then
    grep -q 'prose-house-style-nudge.sh' "$HOOK_MANIFEST" || \
        fail "SEVERITY=ERROR FILE=hooks-plugin/.claude-plugin/plugin.json MSG=hook not registered; it will never fire"
fi

# --- 9. every House rule can actually fire ---------------------------------
# The token checks above prove a rule CONTAINS the right words. They cannot
# prove the rule MATCHES anything -- and a rule that matches nothing produces
# output identical to a clean document, so the defect is invisible.
#
# This shipped once: TicketPlaceholder's five `raw:` entries were concatenated
# by vale into a single impossible pattern rather than OR'd, and it silently
# checked nothing. So run every rule against a fixture built to trip all of
# them, and require each to report at least one alert.
#
# Skipped when vale is absent -- the token checks still hold, and a guard must
# not fail on a missing optional tool. RULES_EXERCISED= says which happened.
CONTROL="$SKILL_DIR/fixtures/house-rule-control.md"
rules_exercised="skipped_no_vale"
if command -v vale >/dev/null 2>&1 && [ -f "$CONTROL" ] && [ -d "$HOUSE" ]; then
    control_out=$(cd "$STYLES" && vale --config "$STYLES/.vale.ini" \
        --output=line --no-exit "$CONTROL" 2>/dev/null)
    fired=0
    while IFS= read -r yml; do
        rule="$(basename "$yml" .yml)"
        # MeanSentenceLength is a metric rule over the whole file; it reports
        # under the same House.<name> label, so no special case is needed.
        if printf '%s\n' "$control_out" | grep -qF "House.$rule"; then
            fired=$((fired + 1))
        else
            fail "SEVERITY=ERROR FILE=${yml#"$ROOT_DIR"/} MSG=rule fires on nothing in the control fixture; it may be silently broken (check raw: concatenation and tokens: word boundaries)"
        fi
    done < <(find "$HOUSE" -name '*.yml' -type f | sort)
    rules_exercised="$fired"
elif [ ! -f "$CONTROL" ]; then
    fail "SEVERITY=ERROR FILE=prose-plugin/skills/prose-check/fixtures/house-rule-control.md MSG=control fixture missing; House rules can no longer be proven to fire"
fi

echo "=== PROSE HOUSE STYLE ==="
echo "RUBRIC_SOURCE=~/.claude/rules/communication.md"
echo "HOUSE_RULES_CHECKED=$files_checked"
echo "RULES_EXERCISED=$rules_exercised"
echo "SIGNIFICANCE_MARKERS=${#SIGNIFICANCE_MARKERS[@]}"
echo "STATUS=$([ "$issue_count" -gt 0 ] && echo ERROR || echo OK)"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
fi
echo "=== END PROSE HOUSE STYLE ==="

[ "$STRICT" -eq 1 ] && [ "$issue_count" -gt 0 ] && exit 1
exit 0
