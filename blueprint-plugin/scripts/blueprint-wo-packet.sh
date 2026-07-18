#!/usr/bin/env bash
# blueprint-wo-packet.sh — reconstruct + validate a work-order packet from a
# GitHub issue body (ADR-0020 autonomy level 3, blueprint-wo-execute.yml).
#
# The WO packet carrier for level-3 execution is the ISSUE BODY, not a local
# file: `docs/blueprint/work-orders/*.md` are gitignored and absent in CI. When
# a human relabels a `work-order-draft` proposal to `work-order-approved`, the
# execute workflow feeds the issue body (untrusted run context) to this script.
#
# SECURITY (see .claude/rules/github-actions-security.md): the issue body is
# UNTRUSTED. The workflow binds github.event.issue.body to an env var, writes it
# to a FILE, and passes the file PATH here — it is never interpolated into a
# `run:` line. This script only PARSES the file; it never executes any content
# from it. The structured output below carries booleans/counts only, never raw
# body text, so an issue body cannot inject KEY=VALUE lines a downstream shell
# would misparse. The extracted packet is written to --out for the executing
# agent to read as a FILE (again, not interpolated into a prompt).
#
# Required packet sections (an executable, independently-verifiable WO):
#   ## Objective          — what to accomplish
#   ## TDD Requirements    — the tests to write first
#   ## Success Criteria    — what the independent verifier checks (alias:
#                            ## Acceptance Criteria)
# A packet missing any required section is invalid (STATUS=ERROR, exit 1) so the
# workflow refuses to execute an underspecified order.
#
# Output follows .claude/rules/structured-script-output.md.
# Exit 0 on OK/WARN, 1 on ERROR (parallel-safe).
#
# Usage: blueprint-wo-packet.sh --body-file PATH [--out PATH]

set -u

body_file=""
out_file=""

while [ $# -gt 0 ]; do
    case "$1" in
        --body-file) body_file="${2:-}"; shift 2 ;;
        --out)       out_file="${2:-}"; shift 2 ;;
        *)           shift ;;
    esac
done

section_open() { printf '=== BLUEPRINT WO PACKET ===\n'; }
section_close() { printf '=== END BLUEPRINT WO PACKET ===\n'; }

finish() {
    # finish <status> <issue_count>
    printf 'STATUS=%s\n' "$1"
    printf 'ISSUE_COUNT=%s\n' "$2"
    section_close
    [ "$1" = "ERROR" ] && exit 1
    exit 0
}

section_open
printf 'BODY_FILE=%s\n' "${body_file:-}"

if [ -z "$body_file" ] || [ ! -f "$body_file" ]; then
    printf 'PACKET_VALID=false\n'
    printf 'REASON=no_body_file\n'
    printf 'MISSING_SECTIONS=objective,tdd,success-criteria\n'
    finish ERROR 1
fi

# Extract the text of one markdown "## <name>" section (case-insensitive match
# on the heading), stopping at the next "## " heading. Fenced code blocks inside
# a section are preserved verbatim. Pure parsing — nothing is evaluated.
extract_section() {
    # extract_section <file> <heading-regex>
    awk -v want="$2" '
        BEGIN { IGNORECASE = 1; grab = 0 }
        /^```/ { fence = !fence }
        /^##[[:space:]]/ && !fence {
            if ($0 ~ ("^##[[:space:]]+(" want ")[[:space:]]*$")) { grab = 1; next }
            else if (grab) { grab = 0 }
        }
        grab { print }
    ' "$1"
}

# Extract an h3 "### <name>" subsection, stopping at the next h2 OR h3 heading.
# Required Files lives as "### Required Files" under "## Context".
extract_h3_section() {
    # extract_h3_section <file> <heading-regex>
    awk -v want="$2" '
        BEGIN { IGNORECASE = 1; grab = 0 }
        /^```/ { fence = !fence }
        /^###?[[:space:]]/ && !fence {
            if ($0 ~ ("^###[[:space:]]+(" want ")[[:space:]]*$")) { grab = 1; next }
            else if (grab) { grab = 0 }
        }
        grab { print }
    ' "$1"
}

objective_txt="$(extract_section "$body_file" 'Objective')"
tdd_txt="$(extract_section "$body_file" 'TDD Requirements|Test-Driven Requirements')"
success_txt="$(extract_section "$body_file" 'Success Criteria|Acceptance Criteria')"
files_txt="$(extract_h3_section "$body_file" 'Required Files')"

has_objective=false; [ -n "$(printf '%s' "$objective_txt" | tr -d '[:space:]')" ] && has_objective=true
has_tdd=false;       [ -n "$(printf '%s' "$tdd_txt" | tr -d '[:space:]')" ] && has_tdd=true
has_success=false;   [ -n "$(printf '%s' "$success_txt" | tr -d '[:space:]')" ] && has_success=true

printf 'HAS_OBJECTIVE=%s\n' "$has_objective"
printf 'HAS_TDD=%s\n' "$has_tdd"
printf 'HAS_SUCCESS_CRITERIA=%s\n' "$has_success"

# Count bullet-list entries under Required Files (files needed for the task).
file_count=$(printf '%s\n' "$files_txt" | grep -cE '^[[:space:]]*[-*][[:space:]]' || true)
printf 'FILE_COUNT=%s\n' "$file_count"

# WO id: emit ONLY if it matches the safe WO-NNN shape (sanitize untrusted body).
wo_id=$(grep -m1 -oE 'WO-[0-9]{1,6}' "$body_file" 2>/dev/null || true)
printf 'WO_ID=%s\n' "${wo_id:-none}"

missing=""
[ "$has_objective" = true ] || missing="${missing:+$missing,}objective"
[ "$has_tdd" = true ]       || missing="${missing:+$missing,}tdd"
[ "$has_success" = true ]   || missing="${missing:+$missing,}success-criteria"
printf 'MISSING_SECTIONS=%s\n' "$missing"

if [ -n "$missing" ]; then
    printf 'PACKET_VALID=false\n'
    finish ERROR 1
fi

printf 'PACKET_VALID=true\n'

# Write the validated packet (verbatim body) for the executing agent to read as
# a file. We echo the body unchanged — the agent consumes it as untrusted task
# content it must implement, not as instructions to the harness.
if [ -n "$out_file" ]; then
    if cat "$body_file" > "$out_file" 2>/dev/null; then
        printf 'OUT_FILE=%s\n' "$out_file"
    else
        printf 'OUT_FILE=write_failed\n'
        finish WARN 1
    fi
fi

finish OK 0
