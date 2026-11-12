#!/usr/bin/env bash
# shellcheck disable=SC2015   # file-level: `cond && ok … || notok …` is the
# deliberate assertion idiom (ok/notok both exit 0) — see test-check-schema.sh.
# Regression tests for `blueprint-autorun.sh --frontmatter-rows`, the one
# frontmatter parser the write-time hook, the session-start sweep and the
# sync-ids audit share (ADR-0027 Q1, #3549).
#
# Pins:
#   - differential: every row equals check-schema.py split_frontmatter +
#     yaml.safe_load for id, status, title, created, relates-to and
#     github-issues, over the #3549 fixtures and every docs/{adrs,prds,prps}
#     document in this repo (needs uv; prints SKIP otherwise)
#   - the parser gives byte-identical output under every awk on PATH variants
#     present (mawk, gawk, BWK awk, busybox) — macOS ships BWK awk
#   - the file list is sorted (LC_ALL=C) whatever order it is passed in
#   - an unknown flag exits 2 with a usage line
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_DIR="$(cd "${PLUGIN_DIR}/.." && pwd)"
AUTORUN="${PLUGIN_DIR}/scripts/blueprint-autorun.sh"
CHECKER="${PLUGIN_DIR}/scripts/check-schema.py"
REFERENCE="${SCRIPT_DIR}/frontmatter_rows_reference.py"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

work=$(mktemp -d)
if [ -z "$work" ] || [ ! -d "$work" ]; then
    echo "FATAL: mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$work"' EXIT

fx="$work/fixtures"
mkdir -p "$fx"
printf -- '---\nid: ADR-9004  # assigned by sync-ids\nstatus: Accepted # was Proposed\ntitle: Inline comments\ncreated: 2026-07-01\n---\n\n# Body heading\n' > "$fx/01-inline-comment.md"
printf -- '---\nid: ADR-9005\ntitle: "ADR-9005: Use X: a decision"\nstatus: Accepted\n---\n' > "$fx/02-double-quoted.md"
printf -- "---\nid: ADR-9006\ntitle: 'It''s fine'\nstatus: Draft\n---\n" > "$fx/03-single-quoted.md"
printf -- '---\nid: ADR-9007   \nstatus: Draft   \ntitle: Trailing   \t\ncreated: 2026-07-02  \n---\n' > "$fx/04-trailing-ws.md"
printf -- '---\r\nid: ADR-9008\r\nstatus: Accepted\r\ntitle: CRLF document\r\nrelates-to:\r\n  - ADR-0001\r\n---\r\n\r\n# CRLF heading\r\n' > "$fx/05-crlf.md"
# shellcheck disable=SC2016  # literal markdown fence
printf -- '# ADR index\n\nTemplate:\n\n```markdown\n---\nid: ADR-NNNN\ntitle: "ADR-NNNN: Title"\nstatus: Proposed        # Draft | Proposed\n---\n```\n' > "$fx/06-README.md"
# Zero bytes, sorted between two non-empty files: awk sees no record for it.
: > "$fx/06b-empty.md"
printf -- '---\n# a comment line, not a title\nid: ADR-9009\nstatus: Accepted\n---\n\n# Heading after a comment line\n' > "$fx/07-comment-line.md"
printf -- '---\nid: PRD-9010\ntitle: Fix #123\nstatus: Draft\n---\n' > "$fx/08-hash-title.md"
printf -- '---\nid: ADR-9011\nstatus: Accepted\nrelates-to:\n  - ADR-0019  # supersedes\n  - PRD-001\ngithub-issues:\n  - 42\n  - 7 # tracking\n---\n' > "$fx/09-list-comment.md"
printf -- '---\nid: PRP-9012\nstatus: Ready\nrelates-to: [ADR-0001, "PRD-002"]\ngithub-issues: []\n---\n' > "$fx/10-flow-lists.md"
printf -- '---\nid: PRP-9013\nstatus: Ready\n\n# Never closed: no frontmatter\n' > "$fx/11-unclosed.md"
# shellcheck disable=SC2016  # literal markdown fence
printf -- '---\nid: PRP-9014\nstatus: Ready\n---\n\n```bash\n# shell comment, not a heading\n```\n\n# Real heading\n' > "$fx/12-fenced-heading.md"

fixture_files=("$fx"/*.md)
repo_docs=()
for d in docs/adrs docs/prds docs/prps; do
    for f in "${REPO_DIR}/${d}"/*.md; do
        [ -f "$f" ] && repo_docs+=("$f")
    done
done

rows_default=$(bash "$AUTORUN" --frontmatter-rows "${fixture_files[@]}" "${repo_docs[@]}")
[ "$(printf '%s\n' "$rows_default" | wc -l | tr -d ' ')" = "$(( ${#fixture_files[@]} + ${#repo_docs[@]} ))" ] \
    && ok "one row per file (${#fixture_files[@]} fixtures + ${#repo_docs[@]} repo docs)" \
    || notok "row count differs from file count"

# ---- Differential against split_frontmatter + yaml.safe_load ----
if command -v uv >/dev/null 2>&1; then
    diff_out=$(printf '%s\n' "$rows_default" \
        | uv run --quiet --no-project --with 'PyYAML==6.0.2' python3 "$REFERENCE" "$CHECKER" 2>&1)
    diff_rc=$?
    if [ "$diff_rc" -eq 0 ]; then
        ok "differential: parser rows equal split_frontmatter + yaml.safe_load ($(printf '%s\n' "$diff_out" | grep '^ROWS='))"
    else
        notok "differential: $(printf '%s\n' "$diff_out" | grep -v '^SKIPPED' | head -12)"
    fi
else
    printf 'SKIP - uv unavailable; the yaml differential needs it\n'
fi

field() { # field <row-path-suffix> <field-number>
    printf '%s\n' "$rows_default" | awk -F'\037' -v p="$1" -v n="$2" 'index($1, p) { print $n; exit }'
}
[ "$(field 01-inline-comment.md 3)" = "ADR-9004" ] && ok "inline comment is not part of the id" || notok "id=$(field 01-inline-comment.md 3)"
[ "$(field 05-crlf.md 2)" = "1" ] && [ "$(field 05-crlf.md 3)" = "ADR-9008" ] && ok "CRLF document has frontmatter" || notok "CRLF row: $(field 05-crlf.md 2) $(field 05-crlf.md 3)"
[ "$(field 06-README.md 2)" = "0" ] && [ -z "$(field 06-README.md 3)" ] && ok "fenced template in an index README is body text" || notok "README row read the fence"
empty_rows=$(bash "$AUTORUN" --frontmatter-rows "$fx/07-comment-line.md" "$fx/06b-empty.md" "$fx/06-README.md" \
    | awk -F'\037' '{ n = split($1, a, "/"); printf "%s:%s:%s%s%s%s%s%s\n", a[n], $2, $3, $4, $5, $6, $7, $8 }')
[ "$empty_rows" = $'06-README.md:0:ADR index\n06b-empty.md:0:\n07-comment-line.md:1:ADR-9009AcceptedHeading after a comment line' ] \
    && ok "a zero-byte file gets an empty row in its sorted position" \
    || notok "zero-byte file rows: $empty_rows"
[ "$(field 07-comment-line.md 5)" = "Heading after a comment line" ] && ok "frontmatter comment line is not the title" || notok "title=$(field 07-comment-line.md 5)"
[ "$(field 12-fenced-heading.md 5)" = "Real heading" ] && ok "heading fallback skips fenced code" || notok "title=$(field 12-fenced-heading.md 5)"

# ---- Sorted output whatever the argument order ----
shuffled=$(bash "$AUTORUN" --frontmatter-rows "$fx/12-fenced-heading.md" "$fx/03-single-quoted.md" "$fx/01-inline-comment.md")
order=$(printf '%s\n' "$shuffled" | awk -F'\037' '{ n = split($1, a, "/"); printf "%s ", a[n] }')
[ "$order" = "01-inline-comment.md 03-single-quoted.md 12-fenced-heading.md " ] && ok "file list is sorted before parsing" || notok "order: $order"

# ---- Every awk variant present gives the same bytes ----
variants=0
for awk_bin in mawk gawk original-awk nawk bwk-awk /usr/bin/awk "busybox awk"; do
    # shellcheck disable=SC2086  # word-split "busybox awk" into command + arg
    set -- $awk_bin
    command -v "$1" >/dev/null 2>&1 || continue
    shim="$work/shim-$variants"
    mkdir -p "$shim"
    if [ $# -gt 1 ]; then
        printf '#!/bin/sh\nexec %s "$@"\n' "$awk_bin" > "$shim/awk"
    else
        printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v "$1")" > "$shim/awk"
    fi
    chmod +x "$shim/awk"
    variant_rows=$(PATH="$shim:$PATH" bash "$AUTORUN" --frontmatter-rows "${fixture_files[@]}" "${repo_docs[@]}")
    variants=$((variants + 1))
    [ "$variant_rows" = "$rows_default" ] && ok "awk variant '$awk_bin' matches" || notok "awk variant '$awk_bin' differs: $(diff <(printf '%s\n' "$rows_default") <(printf '%s\n' "$variant_rows") | head -6)"
done
[ "$variants" -gt 0 ] && ok "$variants awk variant(s) exercised" || notok "no awk variant found"

# ---- Unknown flags exit 2 ----
bash "$AUTORUN" --bogus >/dev/null 2>"$work/err"
rc=$?
[ "$rc" -eq 2 ] && grep -q '^usage:' "$work/err" && ok "unknown flag exits 2 with usage" || notok "--bogus exited $rc"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
