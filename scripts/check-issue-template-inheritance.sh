#!/usr/bin/env bash
# Verify a repo-local .github/ISSUE_TEMPLATE directory carries everything the
# inherited org-wide directory used to provide.
#
# Background: GitHub's default community health files are per-FILE for most
# types, but issue templates are inherited as a DIRECTORY. From
# https://docs.github.com/en/communities/setting-up-your-project-for-healthy-contributions/creating-a-default-community-health-file:
#
#   "if a repository defines valid issue templates or issue template
#    configuration in its own `.github/ISSUE_TEMPLATE` folder, none of the
#    contents of the default `.github/ISSUE_TEMPLATE` folder will be used."
#
# So adding a bare config.yml here suppresses laurigates/.github's Bug Report
# template, its Feature Request template AND its Security contact link. Nothing
# reports that: the org files still exist, the diff shows one added file, and CI
# has no view of the rendered chooser. The only symptom is a "New issue" page
# that quietly stopped offering two templates (#2568).
#
# This guard asserts the four things a local directory has to keep true:
#   1. it contains at least one issue template, not just configuration
#   2. it carries a config.yml at all — templates alone suppress the org config
#   3. that config re-declares the org-wide Security contact link
#   4. that config still carries the Q&A diversion the directory exists for
#
# Links are matched against the config with whole-line comments stripped, so a
# URL surviving only in prose cannot stand in for a live contact link.
#
# A repo with NO local directory is fully inherited and reports OK — there is
# nothing to suppress, so a guard that errored there would be red on arrival in
# every repo that never opted in.
#
# Usage:
#   bash scripts/check-issue-template-inheritance.sh [--project-dir <path>]
#
# Exit codes:
#   0 - OK (compliant, or no local directory)
#   1 - one or more findings
#   2 - usage / environment error
set -uo pipefail

# The link the org config.yml declares. A local config suppresses that file, so
# this URL has to be re-declared here or the private-reporting route disappears.
SECURITY_URL="https://github.com/laurigates/.github/blob/main/SECURITY.md"
# The diversion this directory was created for (#2568).
QA_URL="https://github.com/laurigates/claude-plugins/discussions/categories/q-a"

PROJECT_DIR=""

usage() {
  echo "Usage: check-issue-template-inheritance.sh [--project-dir DIR]" >&2
}

# An unknown argument is REJECTED, never swallowed (#2057): a silently-ignored
# flag turns a gate into a no-op that still exits 0.
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir)
      if [ -z "${2:-}" ] || [ ! -d "${2:-}" ]; then
        echo "check-issue-template-inheritance.sh: --project-dir requires a directory" >&2
        exit 2
      fi
      PROJECT_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "check-issue-template-inheritance.sh: unknown argument: $1" >&2
      usage
      exit 2 ;;
  esac
done

if [ -z "$PROJECT_DIR" ]; then
  PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

TEMPLATE_DIR="$PROJECT_DIR/.github/ISSUE_TEMPLATE"
CONFIG="$TEMPLATE_DIR/config.yml"
[ -f "$CONFIG" ] || CONFIG="$TEMPLATE_DIR/config.yaml"

issues=()

add_issue() {
  issues+=("  - SEVERITY=ERROR TYPE=$1 MSG=$2")
}

echo "=== ISSUE TEMPLATE INHERITANCE ==="

if [ ! -d "$TEMPLATE_DIR" ]; then
  # No local directory: the org-wide default applies in full.
  echo "LOCAL_DIR=absent"
  echo "TEMPLATE_COUNT=0"
  echo "CONFIG_PRESENT=false"
  echo "SECURITY_LINK=n/a"
  echo "QA_LINK=n/a"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END ISSUE TEMPLATE INHERITANCE ==="
  exit 0
fi

# Every template file in the directory EXCEPT the configuration. GitHub counts
# a directory holding only config.yml as "defines issue template configuration",
# which is enough to suppress the inherited directory.
template_count=0
while IFS= read -r entry; do
  base="$(basename "$entry")"
  case "$base" in
    config.yml|config.yaml) continue ;;
  esac
  template_count=$((template_count + 1))
done < <(find "$TEMPLATE_DIR" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.md' \) 2>/dev/null)

config_present=false
security_link=missing
qa_link=missing
if [ -f "$CONFIG" ]; then
  config_present=true
  # Whole-line comments are stripped first: a URL surviving only in a comment
  # is documentation, not a contact link, and matching it would let a config
  # whose contact_links were deleted pass while the chooser offers nothing.
  # A here-string, never a pipe into `grep -q` — an early-closing reader trips
  # SIGPIPE under `pipefail` (#1744).
  config_body="$(grep -v '^[[:space:]]*#' "$CONFIG" 2>/dev/null)"
  grep -qF "$SECURITY_URL" <<<"$config_body" && security_link=present
  grep -qF "$QA_URL" <<<"$config_body" && qa_link=present
else
  security_link=n/a
  qa_link=n/a
fi

if [ "$template_count" -eq 0 ]; then
  add_issue "templates_suppressed" \
    ".github/ISSUE_TEMPLATE exists but holds no template — the inherited Bug Report and Feature Request templates are suppressed; copy them in beside config.yml"
fi

# Templates alone are enough to suppress the inherited directory, and that
# directory is where the org's own config.yml lives — so a local directory with
# no config drops the Security contact link with nothing replacing it.
if [ "$config_present" = "false" ]; then
  add_issue "config_suppressed" \
    ".github/ISSUE_TEMPLATE exists with no config.yml — the org config, and with it the Security contact link, is suppressed and unreplaced"
fi

if [ "$config_present" = "true" ] && [ "$security_link" = "missing" ]; then
  add_issue "security_link_dropped" \
    "config.yml suppresses the org config, so it must re-declare $SECURITY_URL"
fi

if [ "$config_present" = "true" ] && [ "$qa_link" = "missing" ]; then
  add_issue "qa_link_dropped" \
    "the Q&A diversion this directory exists for is gone — re-add $QA_URL or close #2568 deliberately"
fi

echo "LOCAL_DIR=present"
echo "TEMPLATE_COUNT=$template_count"
echo "CONFIG_PRESENT=$config_present"
echo "SECURITY_LINK=$security_link"
echo "QA_LINK=$qa_link"
if [ ${#issues[@]} -gt 0 ]; then
  echo "STATUS=ERROR"
else
  echo "STATUS=OK"
fi
echo "ISSUE_COUNT=${#issues[@]}"
if [ ${#issues[@]} -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END ISSUE TEMPLATE INHERITANCE ==="

[ ${#issues[@]} -eq 0 ] || exit 1
exit 0
