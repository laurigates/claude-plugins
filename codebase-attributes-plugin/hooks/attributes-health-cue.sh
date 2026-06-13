#!/usr/bin/env bash
# SessionStart hook — surfaces codebase-attributes health severity so work
# routes through codebase-attributes-plugin:attributes-route / attributes-dashboard
# when .claude/attributes.json is present in the repo. Injects additionalContext
# (never blocks) and fires at most once per session_id.
#
# Fires only on source=startup|resume (silent on clear/compact — those are
# mid-session continuations), at most once per session_id.
set -uo pipefail

input=$(cat)

source_kind=$(jq -r '.source // empty' <<<"$input" 2>/dev/null || echo "")
case "$source_kind" in
    startup|resume) ;;
    *) exit 0 ;;
esac

session_id=$(jq -r '.session_id // empty' <<<"$input" 2>/dev/null || echo "")
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null || echo "")

[ -z "$session_id" ] && exit 0
[ -z "$cwd" ] && exit 0
[ ! -d "$cwd" ] && exit 0

# Resolve git repo root; fall back to cwd for non-git projects
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
else
    repo_root="$cwd"
fi

# Only fire when attributes data file exists — do not nag opt-out projects
attrs_file="$repo_root/.claude/attributes.json"
[ ! -f "$attrs_file" ] && exit 0

# At most one cue per session
# ATTRIBUTES_HEALTH_CUE_CACHE_DIR is a test seam — see test-attributes-health-cue.sh
state_dir="${ATTRIBUTES_HEALTH_CUE_CACHE_DIR:-$HOME/.cache/attributes-health-cue}"
mkdir -p "$state_dir"
state_file="$state_dir/$session_id"
[ -f "$state_file" ] && exit 0

# Extract worst severity and category from the attributes JSON
worst_severity=""
worst_category=""
if command -v jq >/dev/null 2>&1; then
    # Severity order: critical > high > medium > low
    for sev in critical high medium low; do
        cat_match=$(jq -r --arg s "$sev" \
            '[.attributes[]? | select(.severity == $s)] | first | .category // empty' \
            "$attrs_file" 2>/dev/null || echo "")
        if [ -n "$cat_match" ]; then
            worst_severity="$sev"
            worst_category="$cat_match"
            break
        fi
    done
fi

touch "$state_file"

if [ -n "$worst_severity" ] && [ -n "$worst_category" ]; then
    context="Codebase health data found (.claude/attributes.json): highest severity is ${worst_severity} in ${worst_category}. If the user is starting work on this repo, offer to run codebase-attributes-plugin:attributes-route to auto-remediate by severity, or codebase-attributes-plugin:attributes-dashboard for a health overview. Offer once — do not run unprompted."
else
    context="Codebase health data found (.claude/attributes.json). If the user is starting work on this repo, offer to run codebase-attributes-plugin:attributes-route to auto-remediate issues, or codebase-attributes-plugin:attributes-dashboard for a health overview. Offer once — do not run unprompted."
fi

jq -nc --arg c "$context" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
