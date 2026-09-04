#!/usr/bin/env bash
# Regression test for scripts/check-issue-template-inheritance.sh (#2568).
#
# SEMANTIC, not syntactic: every case EXECUTES the guard against a planted
# fixture tree, because a grep of the script for "config.yml" would pass against
# a checker that had stopped reading the directory at all.
#
# Both polarities are asserted throughout. A guard that flagged every local
# ISSUE_TEMPLATE directory would satisfy the three ERROR cases while being
# useless, and one that never fired would satisfy the two clean cases — so the
# compliant fixture and the real repo must both come back OK with non-vacuous
# counters (TEMPLATE_COUNT=2, both links present).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CHECKER="$REPO_ROOT/scripts/check-issue-template-inheritance.sh"

SECURITY_URL="https://github.com/laurigates/.github/blob/main/SECURITY.md"
QA_URL="https://github.com/laurigates/claude-plugins/discussions/categories/q-a"

passed=0
failed=0

ok() { printf 'PASS: %s\n' "$1"; passed=$((passed + 1)); }
ko() { printf 'FAIL: %s\n' "$1"; failed=$((failed + 1)); }

assert_contains() { # haystack needle label
  case "$1" in
    *"$2"*) ok "$3" ;;
    *) ko "$3 (missing: $2)" ;;
  esac
}

assert_lacks() { # haystack needle label
  case "$1" in
    *"$2"*) ko "$3 (unexpectedly present: $2)" ;;
    *) ok "$3" ;;
  esac
}

assert_eq() { # actual expected label
  if [ "$1" = "$2" ]; then ok "$3"; else ko "$3 (got '$1', wanted '$2')"; fi
}

TMP_ROOT="$(mktemp -d)"
if [ -z "$TMP_ROOT" ] || [ ! -d "$TMP_ROOT" ]; then
  echo "FAIL: could not create a sandbox directory" >&2
  exit 1
fi
trap 'rm -rf "$TMP_ROOT"' EXIT

write_config() { # dir  extra-links...
  local dir="$1"; shift
  {
    echo "blank_issues_enabled: false"
    echo "contact_links:"
    local url
    for url in "$@"; do
      echo "  - name: A link"
      echo "    url: $url"
      echo "    about: whatever"
    done
  } > "$dir/config.yml"
}

write_template() { # path name
  {
    echo "name: $2"
    echo "description: fixture template"
    echo "body:"
    echo "  - type: markdown"
    echo "    attributes:"
    echo "      value: fixture"
  } > "$1"
}

# --- CASE A: compliant directory (the shape this PR ships) -------------------
A="$TMP_ROOT/a"; mkdir -p "$A/.github/ISSUE_TEMPLATE"
write_config "$A/.github/ISSUE_TEMPLATE" "$SECURITY_URL" "$QA_URL"
write_template "$A/.github/ISSUE_TEMPLATE/1-bug-report.yml" "Bug Report"
write_template "$A/.github/ISSUE_TEMPLATE/2-feature-request.yml" "Feature Request"
out_a="$(bash "$CHECKER" --project-dir "$A" 2>&1)"; rc_a=$?
assert_eq "$rc_a" "0" "A: compliant directory exits 0"
assert_contains "$out_a" "STATUS=OK" "A: compliant directory is OK"
# Guard integrity: without these the clean verdict could come from a checker
# that never opened the directory.
assert_contains "$out_a" "TEMPLATE_COUNT=2" "A: both templates counted"
assert_contains "$out_a" "SECURITY_LINK=present" "A: security link seen"
assert_contains "$out_a" "QA_LINK=present" "A: Q&A link seen"
assert_contains "$out_a" "ISSUE_COUNT=0" "A: no findings"

# --- CASE B: config-only directory (the #2568 hazard) ------------------------
B="$TMP_ROOT/b"; mkdir -p "$B/.github/ISSUE_TEMPLATE"
write_config "$B/.github/ISSUE_TEMPLATE" "$SECURITY_URL" "$QA_URL"
out_b="$(bash "$CHECKER" --project-dir "$B" 2>&1)"; rc_b=$?
assert_eq "$rc_b" "1" "B: config-only directory exits 1"
assert_contains "$out_b" "templates_suppressed" "B: suppression is named"
assert_contains "$out_b" "TEMPLATE_COUNT=0" "B: zero templates reported"
# The links are fine here, so the finding must be attributable to the templates
# alone rather than to a checker that flags every local directory.
assert_lacks "$out_b" "security_link_dropped" "B: security link not falsely flagged"
assert_lacks "$out_b" "qa_link_dropped" "B: Q&A link not falsely flagged"

# --- CASE C: templates present, security link dropped ------------------------
C="$TMP_ROOT/c"; mkdir -p "$C/.github/ISSUE_TEMPLATE"
write_config "$C/.github/ISSUE_TEMPLATE" "$QA_URL"
write_template "$C/.github/ISSUE_TEMPLATE/1-bug-report.yml" "Bug Report"
out_c="$(bash "$CHECKER" --project-dir "$C" 2>&1)"; rc_c=$?
assert_eq "$rc_c" "1" "C: dropped security link exits 1"
assert_contains "$out_c" "security_link_dropped" "C: security link finding raised"
assert_contains "$out_c" "SECURITY_LINK=missing" "C: security link reported missing"
assert_lacks "$out_c" "templates_suppressed" "C: templates not falsely flagged"
assert_lacks "$out_c" "qa_link_dropped" "C: Q&A link not falsely flagged"

# --- CASE D: templates present, Q&A diversion dropped ------------------------
D="$TMP_ROOT/d"; mkdir -p "$D/.github/ISSUE_TEMPLATE"
write_config "$D/.github/ISSUE_TEMPLATE" "$SECURITY_URL"
write_template "$D/.github/ISSUE_TEMPLATE/1-bug-report.yml" "Bug Report"
out_d="$(bash "$CHECKER" --project-dir "$D" 2>&1)"; rc_d=$?
assert_eq "$rc_d" "1" "D: dropped Q&A link exits 1"
assert_contains "$out_d" "qa_link_dropped" "D: Q&A finding raised"
assert_lacks "$out_d" "security_link_dropped" "D: security link not falsely flagged"

# --- CASE E: no local directory at all (fully inherited) ---------------------
# The common case in every other repo. A guard that errored here would be red on
# arrival and switched off, so this case carries as much weight as CASE B.
E="$TMP_ROOT/e"; mkdir -p "$E/.github"
out_e="$(bash "$CHECKER" --project-dir "$E" 2>&1)"; rc_e=$?
assert_eq "$rc_e" "0" "E: no local directory exits 0"
assert_contains "$out_e" "LOCAL_DIR=absent" "E: absence reported"
assert_contains "$out_e" "STATUS=OK" "E: absence is OK"
assert_contains "$out_e" "ISSUE_COUNT=0" "E: absence raises nothing"

# --- CASE F: markdown templates count too ------------------------------------
F="$TMP_ROOT/f"; mkdir -p "$F/.github/ISSUE_TEMPLATE"
write_config "$F/.github/ISSUE_TEMPLATE" "$SECURITY_URL" "$QA_URL"
printf -- '---\nname: Legacy\nabout: markdown form\n---\n\nBody\n' \
  > "$F/.github/ISSUE_TEMPLATE/legacy.md"
out_f="$(bash "$CHECKER" --project-dir "$F" 2>&1)"; rc_f=$?
assert_eq "$rc_f" "0" "F: markdown template satisfies the directory"
assert_contains "$out_f" "TEMPLATE_COUNT=1" "F: markdown template counted"

# --- CASE I: templates but no config — the org config is suppressed too ------
# Templates ALONE suppress the inherited directory, and the org's own config.yml
# lives in it, so deleting the local config does not hand the Security link back
# to the org copy: it drops it. Reported by the external review of this change.
I="$TMP_ROOT/i"; mkdir -p "$I/.github/ISSUE_TEMPLATE"
write_template "$I/.github/ISSUE_TEMPLATE/1-bug-report.yml" "Bug Report"
write_template "$I/.github/ISSUE_TEMPLATE/2-feature-request.yml" "Feature Request"
out_i="$(bash "$CHECKER" --project-dir "$I" 2>&1)"; rc_i=$?
assert_eq "$rc_i" "1" "I: config-less directory exits 1"
assert_contains "$out_i" "config_suppressed" "I: suppressed org config is named"
assert_contains "$out_i" "CONFIG_PRESENT=false" "I: config absence reported"
# Attributable: the templates are fine, so only the config finding may fire.
assert_lacks "$out_i" "templates_suppressed" "I: templates not falsely flagged"
assert_contains "$out_i" "TEMPLATE_COUNT=2" "I: both templates still counted"

# --- CASE J: a URL surviving only in a comment is not a contact link ---------
# grep over the raw file would report both links present for a config whose
# contact_links block had been deleted. Reported by the external review.
J="$TMP_ROOT/j"; mkdir -p "$J/.github/ISSUE_TEMPLATE"
{
  echo "# Security reporting lives at $SECURITY_URL"
  echo "# Questions belong in $QA_URL"
  echo "blank_issues_enabled: false"
} > "$J/.github/ISSUE_TEMPLATE/config.yml"
write_template "$J/.github/ISSUE_TEMPLATE/1-bug-report.yml" "Bug Report"
out_j="$(bash "$CHECKER" --project-dir "$J" 2>&1)"; rc_j=$?
assert_eq "$rc_j" "1" "J: commented-out links exit 1"
assert_contains "$out_j" "SECURITY_LINK=missing" "J: commented security URL is not a link"
assert_contains "$out_j" "QA_LINK=missing" "J: commented Q&A URL is not a link"
assert_contains "$out_j" "security_link_dropped" "J: security finding raised"
assert_contains "$out_j" "qa_link_dropped" "J: Q&A finding raised"
# Guard integrity: the same URLs on real `url:` lines must still read present,
# so the comment strip cannot degrade into never matching anything.
K="$TMP_ROOT/k"; mkdir -p "$K/.github/ISSUE_TEMPLATE"
{
  echo "# A leading comment block, as the shipped config.yml carries."
  echo "blank_issues_enabled: false"
  echo "contact_links:"
  echo "  - name: Security Vulnerability"
  echo "    url: $SECURITY_URL"
  echo "    about: private reporting"
  echo "  - name: Question or Discussion"
  echo "    url: $QA_URL"
  echo "    about: ask here"
} > "$K/.github/ISSUE_TEMPLATE/config.yml"
write_template "$K/.github/ISSUE_TEMPLATE/1-bug-report.yml" "Bug Report"
out_k="$(bash "$CHECKER" --project-dir "$K" 2>&1)"; rc_k=$?
assert_eq "$rc_k" "0" "K: commented config with real links exits 0"
assert_contains "$out_k" "SECURITY_LINK=present" "K: real security link still matched"
assert_contains "$out_k" "QA_LINK=present" "K: real Q&A link still matched"

# --- CASE G: unknown argument is rejected, not swallowed (#2057) -------------
out_g="$(bash "$CHECKER" --projekt-dir "$A" 2>&1)"; rc_g=$?
assert_eq "$rc_g" "2" "G: unknown argument exits 2"
assert_contains "$out_g" "unknown argument" "G: the bad flag is named"
assert_lacks "$out_g" "ISSUE TEMPLATE INHERITANCE" "G: nothing is scanned"

# --- CASE H: the real repository is compliant --------------------------------
out_h="$(bash "$CHECKER" --project-dir "$REPO_ROOT" 2>&1)"; rc_h=$?
assert_eq "$rc_h" "0" "H: this repo passes"
assert_contains "$out_h" "STATUS=OK" "H: this repo is OK"
# Non-vacuity: this repo really does carry both templates and both links, so a
# checker reading nothing cannot satisfy the assertion above.
assert_contains "$out_h" "TEMPLATE_COUNT=2" "H: this repo carries two templates"
assert_contains "$out_h" "SECURITY_LINK=present" "H: this repo keeps the security link"
assert_contains "$out_h" "QA_LINK=present" "H: this repo carries the Q&A link"

echo
echo "Passed: $passed, Failed: $failed"
[ "$failed" -eq 0 ]
