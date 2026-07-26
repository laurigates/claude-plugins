#!/usr/bin/env bash
# get-validation-config.sh — read the manifest `validation` block (issues #2128, #2129).
#
# ONE config surface, two consumers. The tracker-integrity check (#2128) needs
# repo status vocabulary / doc globs / excluded basenames; the ADR collision
# guard (#2129) needs the *list* of ADR directories. Both read from this single
# `validation` block rather than inventing a second mechanism (per the owner
# comments on both issues).
#
# The block is purely ADDITIVE — an absent block, an absent manifest, absent jq,
# or a malformed value all degrade to the documented defaults and STILL exit 0
# (parallel-safe per .claude/rules/parallel-safe-queries.md). Existing repos are
# therefore unaffected.
#
#   "validation": {
#     "status_vocabulary": {
#       "done": ["complete"],
#       "unfinished": ["draft", "proposed", "ready", "in_progress"]
#     },
#     "exclude_basenames": ["README.md"],
#     "doc_globs": ["docs/prds/*.md", "docs/prps/*.md", "docs/adrs/*.md"],
#     "adr_dirs": ["docs/adrs", "docs/adr"]
#   }
#
# ── BOUNDARY: `status_vocabulary` does NOT redefine the FEATURE status enum ────
#
# blueprint-plugin/schemas/feature-tracker.schema.json owns the canonical
# feature-record status enum, and it is exactly:
#
#     not_started  in_progress  partial  complete  blocked
#
# That enum is a plugin-owned SCHEMA INVARIANT. It is emitted here verbatim as
# CANONICAL_FEATURE_STATUSES purely so consumers stop re-hardcoding it — it is
# never read from the manifest and a repo cannot extend or override it.
#
# `status_vocabulary` governs something different: DOCUMENT FRONTMATTER statuses
# (`status: Draft` in a PRD/PRP/ADR) — which of those read as *done* vs
# *unfinished* when comparing a document against the features it cites. Those
# are a repo CONVENTION (one repo writes `ready`, another `approved`), so they
# belong in config. Schema invariant vs repo convention: different questions,
# deliberately different ownership.
#
# The one concession to real-world drift: when a consumer reports FEATURE-status
# drift it MAY consult the union
#
#     CANONICAL_FEATURE_STATUSES ∪ STATUS_DONE ∪ STATUS_UNFINISHED
#
# as an ADDITIONAL *tolerated* set. A feature status outside the canonical enum
# but inside that union (a repo writing `completed` where the schema says
# `complete`) is reported as a WARN naming the canonical spelling, instead of a
# hard ERROR. A status outside the union entirely stays an ERROR. This keeps the
# schema authoritative while letting a drifting repo see an actionable message.
#
# ── OUTPUT CONTRACT (load-bearing — two sibling scripts consume it) ────────────
#
# Structured KEY=VALUE per .claude/rules/structured-script-output.md. List-valued
# keys use a single TAB (0x09) as the element delimiter, NOT a space: a glob or
# path may legitimately contain a space (`docs/my prds/*.md`), so space-joining
# would silently corrupt it. Elements containing a tab, newline, or carriage
# return are dropped when read from the manifest, so the delimiter can never
# appear inside an element.
#
# Every key below is emitted on EVERY run (defaults included), so a consumer's
# `grep -m1` always matches and never trips `set -e`.
#
#   Read a list-valued key into a bash array — the supported idiom, verbatim:
#
#     cfg="$(bash "$SCRIPT_DIR/get-validation-config.sh" --project-dir "$project_dir")"
#     line="$(printf '%s\n' "$cfg" | grep -m1 '^ADR_DIRS=')"
#     IFS=$'\t' read -r -a adr_dirs <<<"${line#ADR_DIRS=}"
#
#   Read a scalar key:
#
#     line="$(printf '%s\n' "$cfg" | grep -m1 '^SOURCE=')"
#     cfg_source="${line#SOURCE=}"
#
# An explicitly-configured empty array (`"exclude_basenames": []`) emits an empty
# value; `IFS=$'\t' read -r -a` then yields a zero-length array, which is correct.
#
#   Keys:
#     STATUS_DONE                 TAB-list — doc frontmatter statuses meaning done
#     STATUS_UNFINISHED           TAB-list — doc frontmatter statuses meaning unfinished
#     EXCLUDE_BASENAMES           TAB-list — basenames to skip when sweeping docs
#     DOC_GLOBS                   TAB-list — globs enumerating requirement docs
#     ADR_DIRS                    TAB-list — ADR directories, in precedence order
#     CANONICAL_FEATURE_STATUSES  TAB-list — the schema enum (never configurable)
#     CONFIGURED_KEYS             TAB-list — which keys above came from the manifest
#                                 (empty = every value is a default)
#     SOURCE                      none                            (no manifest found)
#                                 <manifest>:no_jq                (manifest present, jq absent)
#                                 <manifest>:no_validation_block  (no usable `validation` object)
#                                 <manifest>                      (block read; see CONFIGURED_KEYS)
#     STATUS=OK  ISSUE_COUNT=0    always — this is a config reader, not a validator
#
# ADR_DIRS defaults to `docs/adrs` then `docs/adr`, preserving check-adr-numbers.sh's
# existing single-directory resolution order, so #2129 loses nothing without config.
#
# Usage: get-validation-config.sh [--project-dir DIR]

set -u

# Defaults. TAB-joined, matching the emitted contract.
DEF_STATUS_DONE=$'complete'
DEF_STATUS_UNFINISHED=$'draft\tproposed\tready\tin_progress'
DEF_EXCLUDE_BASENAMES=$'README.md'
DEF_DOC_GLOBS=$'docs/prds/*.md\tdocs/prps/*.md\tdocs/adrs/*.md'
DEF_ADR_DIRS=$'docs/adrs\tdocs/adr'

# The feature-tracker.schema.json enum. Constant — see the BOUNDARY note above.
CANONICAL_FEATURE_STATUSES=$'not_started\tin_progress\tpartial\tcomplete\tblocked'

project_dir="."
while [ $# -gt 0 ]; do
    case "$1" in
        --project-dir)
            project_dir="${2:-.}"
            shift 2
            ;;
        --project-dir=*)
            project_dir="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

STATUS_DONE="$DEF_STATUS_DONE"
STATUS_UNFINISHED="$DEF_STATUS_UNFINISHED"
EXCLUDE_BASENAMES="$DEF_EXCLUDE_BASENAMES"
DOC_GLOBS="$DEF_DOC_GLOBS"
ADR_DIRS="$DEF_ADR_DIRS"
CONFIGURED_KEYS=""

emit() {
    # emit <source>
    printf '=== BLUEPRINT VALIDATION CONFIG ===\n'
    printf 'STATUS_DONE=%s\n' "$STATUS_DONE"
    printf 'STATUS_UNFINISHED=%s\n' "$STATUS_UNFINISHED"
    printf 'EXCLUDE_BASENAMES=%s\n' "$EXCLUDE_BASENAMES"
    printf 'DOC_GLOBS=%s\n' "$DOC_GLOBS"
    printf 'ADR_DIRS=%s\n' "$ADR_DIRS"
    printf 'CANONICAL_FEATURE_STATUSES=%s\n' "$CANONICAL_FEATURE_STATUSES"
    printf 'CONFIGURED_KEYS=%s\n' "$CONFIGURED_KEYS"
    printf 'SOURCE=%s\n' "$1"
    printf 'STATUS=OK\n'
    printf 'ISSUE_COUNT=0\n'
    printf '=== END BLUEPRINT VALIDATION CONFIG ===\n'
    exit 0
}

# Same resolution order as get-automation-config.sh.
manifest=""
if [ -f "${project_dir}/docs/blueprint/manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/manifest.json"
elif [ -f "${project_dir}/docs/blueprint/.manifest.json" ]; then
    manifest="${project_dir}/docs/blueprint/.manifest.json"
fi

if [ -z "$manifest" ]; then
    emit none
fi

if ! command -v jq >/dev/null 2>&1; then
    emit "${manifest}:no_jq"
fi

# A `validation` value that is not an object (absent, null, string, array) is
# indistinguishable from "no config" for our purposes — and guarding it here
# means the per-key readers below can index it safely.
if ! jq -e '(.validation | type) == "object"' "$manifest" >/dev/null 2>&1; then
    emit "${manifest}:no_validation_block"
fi

# resolve <VAR_NAME> <jq-path>
#
# Sets VAR_NAME from the manifest when the value at <jq-path> is a JSON array
# (an explicit [] counts as configured), otherwise leaves the default in place.
# Non-string elements and elements containing the TAB delimiter (or a newline /
# CR) are dropped so the emitted contract stays parseable.
resolve() {
    local r_var="$1" r_path="$2" r_val
    jq -e "($r_path | type) == \"array\"" "$manifest" >/dev/null 2>&1 || return 0
    r_val="$(jq -r "[ $r_path[] | select(type == \"string\") | select(test(\"[\\t\\n\\r]\") | not) ] | join(\"\\t\")" "$manifest" 2>/dev/null)" || return 0
    declare -g "$r_var=$r_val"
    CONFIGURED_KEYS="${CONFIGURED_KEYS}${CONFIGURED_KEYS:+$'\t'}${r_var}"
    return 0
}

resolve STATUS_DONE '.validation.status_vocabulary.done'
resolve STATUS_UNFINISHED '.validation.status_vocabulary.unfinished'
resolve EXCLUDE_BASENAMES '.validation.exclude_basenames'
resolve DOC_GLOBS '.validation.doc_globs'
resolve ADR_DIRS '.validation.adr_dirs'

emit "$manifest"
