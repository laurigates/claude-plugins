#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail`: pass/fail both exit 0
# Self-test for scripts/check-description-discriminators.py (issue #2244).
#
# SEMANTIC, not syntactic: every case EXECUTES the checker against planted
# audit JSON and pin files and asserts on its structured output. The negative
# controls carry equal weight: a satisfied pin set must report OK with a
# non-zero PINS_CHECKED, so "no findings" cannot pass against a checker that
# read nothing, and a stale pin or an empty pin file must be an ERROR rather
# than a clean run.
#
# Usage: bash scripts/tests/test-check-description-discriminators.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
checker="$repo_root/scripts/check-description-discriminators.py"
contract="$repo_root/scripts/check-structured-output-contract.sh"

fixture="$(mktemp -d "${TMPDIR:-/tmp}/desc-discriminators-XXXXXX")"
[ -n "$fixture" ] && [ -d "$fixture" ] || { echo "FAIL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$fixture"' EXIT

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); }
fail() { FAILED=$((FAILED + 1)); echo "FAIL: $1" >&2; }

# Whole-line match, so `ISSUE_COUNT=1` is not satisfied by `ISSUE_COUNT=12`.
has_line() { grep -qxF -- "$2" <<<"$1"; }
has_text() { grep -qF -- "$2" <<<"$1"; }

run() {
  # $1 = audit JSON, $2 = pin file
  OUT="$(python3 "$checker" --input "$1" --pins "$2" 2>&1)"
  RC=$?
}

validate() {
  # The output block must satisfy the structured-output contract, REASON=
  # provenance included.
  if bash "$contract" --validate - <<<"$OUT" >/dev/null 2>&1; then pass; else fail "$1: output fails --validate"; fi
}

# A description whose discriminating phrase sits past the audit's 120-char
# preview, so only a checker reading description_full can see it.
long_tail="Local commits only: stage the changes, write a conventional message, run pre-commit, and create the commit. Use when the user says commit. Pushing is git-push."

cat > "$fixture/audit.json" <<EOF
[
  {"path": "p/skills/a/SKILL.md", "description": "preview", "description_full": "$long_tail"},
  {"path": "p/skills/b/SKILL.md", "description": "preview", "description_full": "PR title only: the subject line. Use when fixing the title of a PR."}
]
EOF

tab=$'\t'

# --- A: every pin satisfied -> OK, and the pins were really checked ---------
printf '%s\n' \
  "# comment lines and blanks are skipped" \
  "" \
  "p/skills/a/SKILL.md${tab}require${tab}^Local commits only${tab}scope limit leads" \
  "p/skills/a/SKILL.md${tab}require${tab}pushing is git-push${tab}case-insensitive, past the 120-char preview" \
  "p/skills/b/SKILL.md${tab}forbid${tab}creating PRs${tab}sibling trigger" \
  > "$fixture/ok.tsv"
run "$fixture/audit.json" "$fixture/ok.tsv"
[ "$RC" -eq 0 ] && pass || fail "A: satisfied pins should exit 0 (got $RC)"
has_line "$OUT" "STATUS=OK" && pass || fail "A: STATUS=OK expected"
has_line "$OUT" "PINS_CHECKED=3" && pass || fail "A: PINS_CHECKED=3 expected (non-vacuous)"
has_line "$OUT" "ISSUE_COUNT=0" && pass || fail "A: ISSUE_COUNT=0 expected"
has_text "$OUT" "REASON=" && fail "A: REASON= must not appear on OK" || pass
validate "A"

# --- B: a required phrase is missing -> ERROR missing_discriminator ---------
printf '%s\n' "p/skills/b/SKILL.md${tab}require${tab}^Local commits only${tab}wrong skill" > "$fixture/missing.tsv"
run "$fixture/audit.json" "$fixture/missing.tsv"
[ "$RC" -eq 1 ] && pass || fail "B: missing discriminator should exit 1 (got $RC)"
has_line "$OUT" "STATUS=ERROR" && pass || fail "B: STATUS=ERROR expected"
has_text "$OUT" "TYPE=missing_discriminator" && pass || fail "B: missing_discriminator expected"
has_text "$OUT" "REASON=missing_discriminator: p/skills/b/SKILL.md" && pass || fail "B: REASON names the skill"
validate "B"

# --- C: a forbidden sibling trigger is present -> ERROR sibling_trigger -----
printf '%s\n' "p/skills/b/SKILL.md${tab}forbid${tab}title of a PR${tab}planted" > "$fixture/forbid.tsv"
run "$fixture/audit.json" "$fixture/forbid.tsv"
[ "$RC" -eq 1 ] && pass || fail "C: forbidden phrase should exit 1 (got $RC)"
has_text "$OUT" "TYPE=sibling_trigger" && pass || fail "C: sibling_trigger expected"
validate "C"

# --- D: a pin naming a skill the audit lacks -> ERROR stale_pin -------------
printf '%s\n' "p/skills/gone/SKILL.md${tab}require${tab}x${tab}renamed skill" > "$fixture/stale.tsv"
run "$fixture/audit.json" "$fixture/stale.tsv"
[ "$RC" -eq 1 ] && pass || fail "D: stale pin should exit 1 (got $RC)"
has_text "$OUT" "TYPE=stale_pin" && pass || fail "D: stale_pin expected"
has_line "$OUT" "PINS_CHECKED=0" && pass || fail "D: a stale pin is not counted as checked"
validate "D"

# --- E: preview-only input -> ERROR, never a silent pass --------------------
cat > "$fixture/preview.json" <<'EOF'
[{"path": "p/skills/a/SKILL.md", "description": "Local commits only..."}]
EOF
run "$fixture/preview.json" "$fixture/ok.tsv"
[ "$RC" -eq 1 ] && pass || fail "E: preview-only input should exit 1 (got $RC)"
has_text "$OUT" "TYPE=malformed_input" && pass || fail "E: malformed_input expected"
validate "E"

# --- F: an empty pin file -> ERROR nothing_scanned --------------------------
printf '# only a comment\n' > "$fixture/empty.tsv"
run "$fixture/audit.json" "$fixture/empty.tsv"
[ "$RC" -eq 1 ] && pass || fail "F: empty pin file should exit 1 (got $RC)"
has_text "$OUT" "TYPE=nothing_scanned" && pass || fail "F: nothing_scanned expected"
validate "F"

# --- G: malformed pin lines -> ERROR malformed_pin, one row each -------------
printf '%s\n' \
  "p/skills/a/SKILL.md${tab}require${tab}only three fields" \
  "p/skills/a/SKILL.md${tab}must${tab}x${tab}bad mode" \
  "p/skills/a/SKILL.md${tab}require${tab}([unclosed${tab}bad regex" \
  > "$fixture/malformed.tsv"
run "$fixture/audit.json" "$fixture/malformed.tsv"
[ "$RC" -eq 1 ] && pass || fail "G: malformed pins should exit 1 (got $RC)"
[ "$(grep -c 'TYPE=malformed_pin' <<<"$OUT")" -eq 3 ] && pass || fail "G: three malformed_pin rows expected"
has_line "$OUT" "ISSUE_COUNT=3" && pass || fail "G: ISSUE_COUNT=3 expected"
validate "G"

# --- H: non-JSON input -> ERROR malformed_input -----------------------------
printf 'not json\n' > "$fixture/bad.json"
run "$fixture/bad.json" "$fixture/ok.tsv"
[ "$RC" -eq 1 ] && pass || fail "H: non-JSON input should exit 1 (got $RC)"
has_text "$OUT" "TYPE=malformed_input" && pass || fail "H: malformed_input expected"

# --- I: the shipped pins hold on the shipped corpus --------------------------
OUT="$(python3 "$checker" 2>&1)"
RC=$?
[ "$RC" -eq 0 ] && pass || { fail "I: shipped pins should hold on this tree (got $RC)"; echo "$OUT" >&2; }
has_line "$OUT" "STATUS=OK" && pass || fail "I: STATUS=OK expected on the shipped tree"
grep -qE '^PINS_CHECKED=[1-9][0-9]*$' <<<"$OUT" && pass || fail "I: shipped run must check at least one pin"

echo "PASSED=$PASSED FAILED=$FAILED"
[ "$FAILED" -eq 0 ] || exit 1
echo "PASS: test-check-description-discriminators ($PASSED assertions)"
