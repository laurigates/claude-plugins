#!/usr/bin/env bash
# Regression tests for get-validation-config.sh — the shared `validation`
# manifest block read by the tracker-integrity check (#2128) and the ADR
# collision guard (#2129).
#
# Auto-discovered by scripts/run-skill-script-tests.sh via
# *-plugin/scripts/tests/test-*.sh.
#
# Pins the SEMANTIC contract two sibling scripts depend on:
#   - absent block / absent manifest / absent jq / malformed value -> defaults, exit 0
#   - ADR_DIRS default preserves check-adr-numbers.sh's docs/adrs-then-docs/adr order
#   - a configured block is echoed back, per-key (a partial block defaults the rest)
#   - CONFIGURED_KEYS names exactly the keys that came from the manifest
#   - list elements survive a SPACE (the reason the delimiter is a TAB, not a space)
#   - CANONICAL_FEATURE_STATUSES is the feature-tracker.schema.json enum and is
#     NOT overridable from the manifest (schema invariant vs repo convention)
set -u

# Neutralize inherited git context. No git ops here today, but the sandbox
# helpers below are the shape that gets extended into git fixtures (issue #1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="${SCRIPT_DIR}/../get-validation-config.sh"
BASH_BIN="$(command -v bash)"

pass=0
fail=0
ok()    { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
notok() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }

# Read a key's raw value out of a captured run (values may contain TABs).
get_key() { # <KEY> <output>
    local g_line
    g_line="$(printf '%s\n' "$2" | grep -m1 "^$1=")" || return 0
    printf '%s' "${g_line#"$1"=}"
}

# The documented consuming idiom, exercised for real so the test fails if the
# delimiter contract changes.
count_elems() { # <KEY> <output>
    local -a c_arr=()
    IFS=$'\t' read -r -a c_arr <<<"$(get_key "$1" "$2")"
    printf '%d' "${#c_arr[@]}"
}
elem() { # <KEY> <output> <0-based index>
    local -a e_arr=()
    IFS=$'\t' read -r -a e_arr <<<"$(get_key "$1" "$2")"
    printf '%s' "${e_arr[$3]:-}"
}

make_project() {
    local p_dir
    p_dir="$(mktemp -d)" || { echo "FATAL: mktemp failed" >&2; exit 1; }
    [ -n "$p_dir" ] || { echo "FATAL: empty mktemp dir" >&2; exit 1; }
    [ -d "$p_dir" ] || { echo "FATAL: mktemp dir missing" >&2; exit 1; }
    mkdir -p "$p_dir/docs/blueprint"
    printf '%s' "$p_dir"
}

DEF_ADR_DIRS=$'docs/adrs\tdocs/adr'
DEF_STATUS_DONE='complete'
DEF_STATUS_UNFINISHED=$'draft\tproposed\tready\tin_progress'
DEF_EXCLUDES='README.md'
DEF_DOC_GLOBS=$'docs/prds/*.md\tdocs/prps/*.md\tdocs/adrs/*.md'
CANON=$'not_started\tin_progress\tpartial\tcomplete\tblocked'

# ---- A: no manifest -> defaults, SOURCE=none, exit 0 -------------------------
proj="$(make_project)"
rm -rf "$proj/docs"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "A: exit 0 without manifest" || notok "A: exit $rc"
[ "$(get_key SOURCE "$out")" = "none" ] && ok "A: SOURCE=none" || notok "A: SOURCE=$(get_key SOURCE "$out")"
[ "$(get_key ADR_DIRS "$out")" = "$DEF_ADR_DIRS" ] && ok "A: ADR_DIRS default preserves docs/adrs then docs/adr" || notok "A: ADR_DIRS wrong"
[ "$(get_key STATUS_DONE "$out")" = "$DEF_STATUS_DONE" ] && ok "A: STATUS_DONE default" || notok "A: STATUS_DONE wrong"
[ "$(get_key STATUS_UNFINISHED "$out")" = "$DEF_STATUS_UNFINISHED" ] && ok "A: STATUS_UNFINISHED default" || notok "A: STATUS_UNFINISHED wrong"
[ "$(get_key EXCLUDE_BASENAMES "$out")" = "$DEF_EXCLUDES" ] && ok "A: EXCLUDE_BASENAMES default" || notok "A: EXCLUDE_BASENAMES wrong"
[ "$(get_key DOC_GLOBS "$out")" = "$DEF_DOC_GLOBS" ] && ok "A: DOC_GLOBS default" || notok "A: DOC_GLOBS wrong"
[ "$(get_key CANONICAL_FEATURE_STATUSES "$out")" = "$CANON" ] && ok "A: canonical feature enum emitted" || notok "A: canonical enum wrong"
[ -z "$(get_key CONFIGURED_KEYS "$out")" ] && ok "A: CONFIGURED_KEYS empty (all defaults)" || notok "A: CONFIGURED_KEYS not empty"
[ "$(get_key STATUS "$out")" = "OK" ] && ok "A: STATUS=OK" || notok "A: STATUS wrong"
[ "$(get_key ISSUE_COUNT "$out")" = "0" ] && ok "A: ISSUE_COUNT=0" || notok "A: ISSUE_COUNT wrong"
printf '%s\n' "$out" | grep -q '^=== BLUEPRINT VALIDATION CONFIG ===$' \
  && printf '%s\n' "$out" | grep -q '^=== END BLUEPRINT VALIDATION CONFIG ===$' \
  && ok "A: section delimiters present" || notok "A: section delimiters missing"
rm -rf "$proj"

# ---- B: manifest with no validation block -> defaults, exit 0 ----------------
proj="$(make_project)"
printf '{"format_version": "3.4.0"}\n' > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "B: exit 0 without validation block" || notok "B: exit $rc"
[ "$(get_key ADR_DIRS "$out")" = "$DEF_ADR_DIRS" ] && ok "B: ADR_DIRS defaulted" || notok "B: ADR_DIRS wrong"
[ "$(get_key STATUS_UNFINISHED "$out")" = "$DEF_STATUS_UNFINISHED" ] && ok "B: STATUS_UNFINISHED defaulted" || notok "B: STATUS_UNFINISHED wrong"
[ -z "$(get_key CONFIGURED_KEYS "$out")" ] && ok "B: CONFIGURED_KEYS empty" || notok "B: CONFIGURED_KEYS not empty"
case "$(get_key SOURCE "$out")" in
  *":no_validation_block") ok "B: SOURCE marks the absent block" ;;
  *) notok "B: SOURCE=$(get_key SOURCE "$out")" ;;
esac
# The hidden .manifest.json fallback resolves too.
rm -f "$proj/docs/blueprint/manifest.json"
printf '{"validation": {"adr_dirs": ["hidden/adrs"]}}\n' > "$proj/docs/blueprint/.manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"
[ "$(get_key ADR_DIRS "$out")" = "hidden/adrs" ] && ok "B: .manifest.json fallback resolved" || notok "B: .manifest.json fallback ignored"
rm -rf "$proj"

# ---- C: fully configured block -> every value echoed back --------------------
proj="$(make_project)"
cat > "$proj/docs/blueprint/manifest.json" <<'JSON'
{
  "validation": {
    "status_vocabulary": {
      "done": ["complete", "shipped"],
      "unfinished": ["draft", "proposed"]
    },
    "exclude_basenames": ["README.md", "TEMPLATE.md"],
    "doc_globs": ["docs/prds/*.md", "docs/specs/*.md"],
    "adr_dirs": ["docs/adrs", "docs/blueprint/adrs"]
  }
}
JSON
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "C: exit 0 on configured block" || notok "C: exit $rc"
[ "$(get_key STATUS_DONE "$out")" = $'complete\tshipped' ] && ok "C: STATUS_DONE configured" || notok "C: STATUS_DONE wrong"
[ "$(get_key STATUS_UNFINISHED "$out")" = $'draft\tproposed' ] && ok "C: STATUS_UNFINISHED configured" || notok "C: STATUS_UNFINISHED wrong"
[ "$(get_key EXCLUDE_BASENAMES "$out")" = $'README.md\tTEMPLATE.md' ] && ok "C: EXCLUDE_BASENAMES configured" || notok "C: EXCLUDE_BASENAMES wrong"
[ "$(get_key DOC_GLOBS "$out")" = $'docs/prds/*.md\tdocs/specs/*.md' ] && ok "C: DOC_GLOBS configured" || notok "C: DOC_GLOBS wrong"
[ "$(get_key ADR_DIRS "$out")" = $'docs/adrs\tdocs/blueprint/adrs' ] && ok "C: ADR_DIRS multi-directory configured (#2129)" || notok "C: ADR_DIRS wrong"
[ "$(count_elems ADR_DIRS "$out")" = "2" ] && ok "C: consuming idiom yields 2 ADR dirs" || notok "C: consuming idiom yielded $(count_elems ADR_DIRS "$out")"
[ "$(elem ADR_DIRS "$out" 1)" = "docs/blueprint/adrs" ] && ok "C: second ADR dir readable" || notok "C: second ADR dir wrong"
[ "$(get_key CONFIGURED_KEYS "$out")" = $'STATUS_DONE\tSTATUS_UNFINISHED\tEXCLUDE_BASENAMES\tDOC_GLOBS\tADR_DIRS' ] \
  && ok "C: CONFIGURED_KEYS lists all five" || notok "C: CONFIGURED_KEYS=$(get_key CONFIGURED_KEYS "$out")"
# The schema enum is NOT overridable — a manifest attempt must be ignored.
cat > "$proj/docs/blueprint/manifest.json" <<'JSON'
{"validation": {"canonical_feature_statuses": ["banana"], "status_vocabulary": {"done": ["shipped"]}}}
JSON
out="$(bash "$HELPER" --project-dir "$proj")"
[ "$(get_key CANONICAL_FEATURE_STATUSES "$out")" = "$CANON" ] \
  && ok "C: canonical feature enum not overridable from manifest" || notok "C: canonical enum was overridden"
rm -rf "$proj"

# ---- D: partial block -> that key configured, every other key defaulted -----
proj="$(make_project)"
printf '{"validation": {"adr_dirs": ["docs/adrs", "docs/blueprint/adrs", "docs/decisions"]}}\n' \
  > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "D: exit 0 on partial block" || notok "D: exit $rc"
[ "$(count_elems ADR_DIRS "$out")" = "3" ] && ok "D: ADR_DIRS configured (3 dirs)" || notok "D: ADR_DIRS wrong"
[ "$(get_key STATUS_DONE "$out")" = "$DEF_STATUS_DONE" ] && ok "D: STATUS_DONE still default" || notok "D: STATUS_DONE not defaulted"
[ "$(get_key STATUS_UNFINISHED "$out")" = "$DEF_STATUS_UNFINISHED" ] && ok "D: STATUS_UNFINISHED still default" || notok "D: STATUS_UNFINISHED not defaulted"
[ "$(get_key EXCLUDE_BASENAMES "$out")" = "$DEF_EXCLUDES" ] && ok "D: EXCLUDE_BASENAMES still default" || notok "D: EXCLUDE_BASENAMES not defaulted"
[ "$(get_key DOC_GLOBS "$out")" = "$DEF_DOC_GLOBS" ] && ok "D: DOC_GLOBS still default" || notok "D: DOC_GLOBS not defaulted"
[ "$(get_key CONFIGURED_KEYS "$out")" = "ADR_DIRS" ] && ok "D: CONFIGURED_KEYS names only ADR_DIRS" || notok "D: CONFIGURED_KEYS=$(get_key CONFIGURED_KEYS "$out")"
# An explicitly-empty array is a deliberate configuration, not a malformed value.
printf '{"validation": {"exclude_basenames": []}}\n' > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"
[ -z "$(get_key EXCLUDE_BASENAMES "$out")" ] && ok "D: explicit [] honored (no excludes)" || notok "D: explicit [] not honored"
[ "$(count_elems EXCLUDE_BASENAMES "$out")" = "0" ] && ok "D: explicit [] parses to 0 elements" || notok "D: explicit [] parsed to $(count_elems EXCLUDE_BASENAMES "$out")"
[ "$(get_key CONFIGURED_KEYS "$out")" = "EXCLUDE_BASENAMES" ] && ok "D: explicit [] counts as configured" || notok "D: explicit [] not marked configured"
rm -rf "$proj"

# ---- E: malformed values -> default for that key, exit 0, no crash ----------
proj="$(make_project)"
printf '{"validation": {"adr_dirs": "docs/adrs", "doc_globs": ["docs/ok/*.md"]}}\n' \
  > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "E: exit 0 on malformed adr_dirs (string)" || notok "E: exit $rc"
[ "$(get_key ADR_DIRS "$out")" = "$DEF_ADR_DIRS" ] && ok "E: malformed adr_dirs falls back to default" || notok "E: malformed adr_dirs leaked"
[ "$(get_key DOC_GLOBS "$out")" = "docs/ok/*.md" ] && ok "E: sibling key still configured" || notok "E: sibling key lost"
[ "$(get_key CONFIGURED_KEYS "$out")" = "DOC_GLOBS" ] && ok "E: CONFIGURED_KEYS omits the malformed key" || notok "E: CONFIGURED_KEYS=$(get_key CONFIGURED_KEYS "$out")"
[ "$(get_key STATUS "$out")" = "OK" ] && ok "E: STATUS=OK (reader, not validator)" || notok "E: STATUS wrong"
# validation itself not an object
printf '{"validation": "yes please"}\n' > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "E: exit 0 when validation is a string" || notok "E: exit $rc"
[ "$(get_key ADR_DIRS "$out")" = "$DEF_ADR_DIRS" ] && ok "E: string validation block -> defaults" || notok "E: string validation block leaked"
# status_vocabulary not an object
printf '{"validation": {"status_vocabulary": ["complete"]}}\n' > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "E: exit 0 when status_vocabulary is an array" || notok "E: exit $rc"
[ "$(get_key STATUS_DONE "$out")" = "$DEF_STATUS_DONE" ] && ok "E: array status_vocabulary -> defaults" || notok "E: array status_vocabulary leaked"
# non-string and delimiter-bearing elements are dropped, not emitted raw
printf '{"validation": {"adr_dirs": ["docs/adrs", 42, "bad\\tdir", null, "docs/adr2"]}}\n' \
  > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "E: exit 0 on mixed-type array" || notok "E: exit $rc"
[ "$(get_key ADR_DIRS "$out")" = $'docs/adrs\tdocs/adr2' ] && ok "E: non-string and TAB-bearing elements dropped" || notok "E: ADR_DIRS=$(get_key ADR_DIRS "$out")"
[ "$(count_elems ADR_DIRS "$out")" = "2" ] && ok "E: mixed array parses to 2 elements" || notok "E: mixed array parsed to $(count_elems ADR_DIRS "$out")"
# unparseable JSON
printf '{"validation": {' > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir "$proj" 2>/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "E: exit 0 on unparseable manifest" || notok "E: exit $rc"
[ "$(get_key ADR_DIRS "$out")" = "$DEF_ADR_DIRS" ] && ok "E: unparseable manifest -> defaults" || notok "E: unparseable manifest leaked"
rm -rf "$proj"

# ---- F: a list element containing a SPACE survives the round trip -----------
# This is the reason the delimiter is a TAB: a space-joined list would split
# "docs/my prds/*.md" into two bogus elements.
proj="$(make_project)"
cat > "$proj/docs/blueprint/manifest.json" <<'JSON'
{"validation": {"doc_globs": ["docs/my prds/*.md", "docs/prps/*.md"],
                "adr_dirs": ["docs/architecture decisions"]}}
JSON
out="$(bash "$HELPER" --project-dir "$proj")"
[ "$(count_elems DOC_GLOBS "$out")" = "2" ] && ok "F: space-bearing glob stays ONE element" || notok "F: space split the list into $(count_elems DOC_GLOBS "$out")"
[ "$(elem DOC_GLOBS "$out" 0)" = "docs/my prds/*.md" ] && ok "F: space-bearing glob round-trips intact" || notok "F: glob mangled: [$(elem DOC_GLOBS "$out" 0)]"
[ "$(count_elems ADR_DIRS "$out")" = "1" ] && ok "F: space-bearing ADR dir stays ONE element" || notok "F: ADR dir split into $(count_elems ADR_DIRS "$out")"
[ "$(elem ADR_DIRS "$out" 0)" = "docs/architecture decisions" ] && ok "F: space-bearing ADR dir round-trips intact" || notok "F: ADR dir mangled"
rm -rf "$proj"

# ---- G: jq unavailable -> defaults, exit 0, SOURCE marks the gap ------------
proj="$(make_project)"
printf '{"validation": {"adr_dirs": ["docs/never/read"]}}\n' > "$proj/docs/blueprint/manifest.json"
empty_bin="$proj/empty-bin"
mkdir -p "$empty_bin"
out="$(PATH="$empty_bin" "$BASH_BIN" "$HELPER" --project-dir "$proj")"; rc=$?
[ "$rc" -eq 0 ] && ok "G: exit 0 without jq" || notok "G: exit $rc"
[ "$(get_key ADR_DIRS "$out")" = "$DEF_ADR_DIRS" ] && ok "G: no jq -> ADR_DIRS default" || notok "G: no jq leaked config"
[ -z "$(get_key CONFIGURED_KEYS "$out")" ] && ok "G: no jq -> CONFIGURED_KEYS empty" || notok "G: no jq marked keys configured"
case "$(get_key SOURCE "$out")" in
  *":no_jq") ok "G: SOURCE marks the missing jq" ;;
  *) notok "G: SOURCE=$(get_key SOURCE "$out")" ;;
esac
[ "$(get_key STATUS "$out")" = "OK" ] && ok "G: STATUS=OK without jq" || notok "G: STATUS wrong"
rm -rf "$proj"

# ---- H: --project-dir=DIR form, and default cwd resolution ------------------
proj="$(make_project)"
printf '{"validation": {"adr_dirs": ["eq/form"]}}\n' > "$proj/docs/blueprint/manifest.json"
out="$(bash "$HELPER" --project-dir="$proj")"
[ "$(get_key ADR_DIRS "$out")" = "eq/form" ] && ok "H: --project-dir=DIR form accepted" || notok "H: --project-dir=DIR ignored"
out="$(cd "$proj" && bash "$HELPER")"
[ "$(get_key ADR_DIRS "$out")" = "eq/form" ] && ok "H: defaults to cwd" || notok "H: cwd default wrong"
rm -rf "$proj"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
