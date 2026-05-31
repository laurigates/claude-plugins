#!/usr/bin/env bash
# Audit top-level documentation maps for mechanical drift (Layer 1 of #1460).
#
# Two zero-false-positive checks:
#   1. RULES INDEX  — every .claude/rules/*.md appears in the CLAUDE.md Rules
#      table, and every table entry exists on disk (bidirectional).
#   2. PLUGIN MAPS  — the plugin set agrees across marketplace.json,
#      release-please-config.json, .release-please-manifest.json, the *-plugin
#      directories on disk, and docs/PLUGIN-MAP.md.
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md) so scheduled-audits can roll it up.
#
# Usage:
#   check-docs-index.sh [--project-dir <path>] [--issue-body] [--strict]
#
#   --project-dir   Repo root to audit (default: git toplevel, else cwd)
#   --issue-body    Emit a markdown issue body (empty when clean) instead of the
#                   structured section — for the scheduled-audits workflow
#   --strict        Exit 1 when drift is found (default: always exit 0)
set -uo pipefail

proj_dir=""
emit_issue_body=false
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --issue-body) emit_issue_body=true; shift ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

claude_md="$proj_dir/CLAUDE.md"
rules_dir="$proj_dir/.claude/rules"
marketplace="$proj_dir/.claude-plugin/marketplace.json"
rp_config="$proj_dir/release-please-config.json"
rp_manifest="$proj_dir/.release-please-manifest.json"
plugin_map="$proj_dir/docs/PLUGIN-MAP.md"

issue_count=0
declare -a issues=()

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

# --- Check 1: rules index vs disk ---------------------------------------------
rules_on_disk="$(find "$rules_dir" -maxdepth 1 -name '*.md' -type f 2>/dev/null \
  | sed "s#$rules_dir/##" | sort)"
rules_in_table="$(grep -oE '\.claude/rules/[a-z0-9-]+\.md' "$claude_md" 2>/dev/null \
  | sed 's#.claude/rules/##' | sort -u)"

missing_from_table="$(comm -23 <(printf '%s\n' "$rules_on_disk") <(printf '%s\n' "$rules_in_table"))"
missing_from_disk="$(comm -13 <(printf '%s\n' "$rules_on_disk") <(printf '%s\n' "$rules_in_table"))"

while IFS= read -r rule; do
  [ -n "$rule" ] && add_issue WARN rule_not_indexed "$rule exists but is absent from the CLAUDE.md Rules table"
done <<< "$missing_from_table"

while IFS= read -r rule; do
  [ -n "$rule" ] && add_issue ERROR rule_table_dangling "CLAUDE.md Rules table lists $rule but no such file exists"
done <<< "$missing_from_disk"

rules_disk_count="$(printf '%s\n' "$rules_on_disk" | grep -c . || true)"
rules_table_count="$(printf '%s\n' "$rules_in_table" | grep -c . || true)"

# --- Check 2: plugin maps agree -----------------------------------------------
mkt_set="$(jq -r '.plugins[].name' "$marketplace" 2>/dev/null | sort)"
rp_set="$(jq -r '.packages | keys[]' "$rp_config" 2>/dev/null | grep -v '^\.$' | sort)"
manifest_set="$(jq -r 'keys[]' "$rp_manifest" 2>/dev/null | grep -v '^\.$' | sort)"
disk_set="$(find "$proj_dir" -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' 2>/dev/null \
  | sed "s#$proj_dir/##" | sort)"

compare_sets() {
  # compare_sets <label-a> <set-a> <label-b> <set-b>
  local only_a only_b
  only_a="$(comm -23 <(printf '%s\n' "$2") <(printf '%s\n' "$4"))"
  only_b="$(comm -13 <(printf '%s\n' "$2") <(printf '%s\n' "$4"))"
  while IFS= read -r p; do
    [ -n "$p" ] && add_issue ERROR plugin_map_drift "$p in $1 but missing from $3"
  done <<< "$only_a"
  while IFS= read -r p; do
    [ -n "$p" ] && add_issue ERROR plugin_map_drift "$p in $3 but missing from $1"
  done <<< "$only_b"
}

compare_sets "marketplace.json" "$mkt_set" "release-please-config.json" "$rp_set"
compare_sets "marketplace.json" "$mkt_set" ".release-please-manifest.json" "$manifest_set"
compare_sets "marketplace.json" "$mkt_set" "plugin dirs on disk" "$disk_set"

# PLUGIN-MAP.md is prose, so check presence (substring) rather than exact set.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  grep -q "$p" "$plugin_map" 2>/dev/null || add_issue WARN plugin_map_missing "$p not mentioned in docs/PLUGIN-MAP.md"
done <<< "$mkt_set"

mkt_count="$(printf '%s\n' "$mkt_set" | grep -c . || true)"

# --- Status -------------------------------------------------------------------
overall_status="OK"
exit_severity=0
for line in "${issues[@]}"; do
  case "$line" in
    *SEVERITY=ERROR*) overall_status="ERROR"; exit_severity=1 ;;
  esac
done
if [ "$overall_status" = "OK" ] && [ "$issue_count" -gt 0 ]; then
  overall_status="WARN"
fi

# --- Output -------------------------------------------------------------------
if [ "$emit_issue_body" = true ]; then
  if [ "$issue_count" -gt 0 ]; then
    echo "## Top-level documentation drift (Layer 1)"
    echo ""
    echo "\`scripts/check-docs-index.sh\` found $issue_count mechanical drift issue(s)."
    echo ""
    echo "| Severity | Type | Detail |"
    echo "|----------|------|--------|"
    for line in "${issues[@]}"; do
      sev="$(printf '%s' "$line" | sed -n 's/.*SEVERITY=\([A-Z]*\).*/\1/p')"
      typ="$(printf '%s' "$line" | sed -n 's/.*TYPE=\([a-z_]*\).*/\1/p')"
      msg="$(printf '%s' "$line" | sed -n 's/.*MSG=//p')"
      echo "| $sev | \`$typ\` | $msg |"
    done
    echo ""
    echo "See \`.claude/rules\` and the Plugin Lifecycle section of CLAUDE.md. Tracked under the recurring Layer 1 audit (#1460)."
  fi
else
  echo "=== DOCS INDEX AUDIT ==="
  echo "RULES_ON_DISK=$rules_disk_count"
  echo "RULES_IN_TABLE=$rules_table_count"
  echo "MARKETPLACE_PLUGINS=$mkt_count"
  echo "STATUS=$overall_status"
  echo "ISSUE_COUNT=$issue_count"
  if [ "$issue_count" -gt 0 ]; then
    echo "ISSUES:"
    printf '%s\n' "${issues[@]}"
  fi
  echo "=== END DOCS INDEX AUDIT ==="
fi

if [ "$strict" = true ]; then
  exit "$exit_severity"
fi
exit 0
