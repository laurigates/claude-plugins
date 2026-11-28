#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh.
#
# Regression test for issue #3666: when #3664 moved the
# blueprint-feature-tracker-status display into references/status-display.md,
# each moved block got a `## …` heading but kept the bold label it already had
# (`## Example output` then `**Example Output**:`, `## Quick commands` then
# `**Quick Commands** (shown at end):`), so the label repeated the heading.
#
# Semantic invariant: in blueprint-plugin skill markdown, the first non-blank
# line after a heading is not a bold label that says the same words as the
# heading (case and punctuation ignored). Fenced code blocks are skipped.
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# Two older reference splits carry the same shape. Issue #3666's decision scoped
# this fix to blueprint-feature-tracker-status, so they are listed here rather
# than edited. Shrink-only: remove an entry when its file is fixed; never add one.
KNOWN=(
    "skills/blueprint-init/references/report-templates.md:quick reference"
    "skills/blueprint-status/references/report-template.md:example output"
)

# Prints `<path>:<line>:<normalised heading>` for every heading whose next
# non-blank line is a bold label with the same normalised words.
find_dupes() { # <file>...
    awk '
        function norm(s) { s = tolower(s); gsub(/[^a-z0-9]+/, " ", s); gsub(/^ +| +$/, "", s); return s }
        FNR == 1 { fence = 0; want = "" }
        /^[[:space:]]*```/ { fence = !fence; want = ""; next }
        fence { next }
        /^[[:space:]]*$/ { next }
        want != "" {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line ~ /^\*\*[^*]+\*\*/) {
                label = line
                sub(/^\*\*/, "", label)
                sub(/\*\*.*$/, "", label)
                if (norm(label) == want) print FILENAME ":" FNR ":" want
            }
            want = ""
        }
        /^#+[[:space:]]/ { h = $0; sub(/^#+[[:space:]]+/, "", h); want = norm(h) }
    ' "$@"
}

# ---- Fixtures: the detector itself ------------------------------------------
sb="$(mktemp -d)"
if [ -z "$sb" ] || [ ! -d "$sb" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$sb"' EXIT

printf '## Example output\n\n**Example Output**:\n```\nx\n```\n' > "$sb/dup.md"
printf '## Example output\n\n```\nx\n```\n' > "$sb/clean.md"
printf '## Steps\n\n**Note**: a different label\n' > "$sb/other.md"
printf '```\n## Example output\n**Example Output**:\n```\n' > "$sb/fenced.md"

[ -n "$(find_dupes "$sb/dup.md")" ] \
    && ok "fixture: a bold label repeating its heading is reported" \
    || notok "fixture: a bold label repeating its heading is not reported"
[ -z "$(find_dupes "$sb/clean.md")" ] \
    && ok "fixture: a heading with no label passes" \
    || notok "fixture: a heading with no label is reported"
[ -z "$(find_dupes "$sb/other.md")" ] \
    && ok "fixture: a bold label with other words passes" \
    || notok "fixture: a bold label with other words is reported"
[ -z "$(find_dupes "$sb/fenced.md")" ] \
    && ok "fixture: a heading inside a fenced block is skipped" \
    || notok "fixture: a heading inside a fenced block is reported"

# ---- The plugin's skill markdown --------------------------------------------
mapfile -t files < <(find "${PLUGIN_DIR}/skills" -type f -name '*.md' | sort)
[ "${#files[@]}" -gt 0 ] \
    && ok "found ${#files[@]} skill markdown files" \
    || notok "found no skill markdown files under ${PLUGIN_DIR}/skills"

found=0
while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    rel="${hit#"$PLUGIN_DIR"/}"
    path="${rel%%:*}"
    heading="${rel##*:}"
    known=0
    for k in "${KNOWN[@]}"; do
        [ "$k" = "$path:$heading" ] && known=1
    done
    if [ "$known" -eq 1 ]; then
        found=$((found + 1))
        continue
    fi
    notok "$rel: bold label repeats the heading above it; drop the label"
done < <(find_dupes "${files[@]}")

# A KNOWN entry that no longer matches has been fixed: shrink the list.
[ "$found" -eq "${#KNOWN[@]}" ] \
    && ok "every KNOWN entry still matches (${found}/${#KNOWN[@]})" \
    || notok "KNOWN lists ${#KNOWN[@]} entries but ${found} still match; remove the fixed ones"

[ "$fail" -eq 0 ] && ok "no bold label repeats its heading outside KNOWN"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
