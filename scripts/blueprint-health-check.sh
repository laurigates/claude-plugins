#!/usr/bin/env bash
set -euo pipefail

# Blueprint Health Check Script
# Performs comprehensive health checks on the claude-plugins repository
# Usage: ./scripts/blueprint-health-check.sh

# Configuration
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STALE_THRESHOLD_DAYS=90
# Above STALE_THRESHOLD_DAYS a skill counts toward the summary metric; only skills
# past ITEMISE_THRESHOLD_DAYS are itemised row-by-row. Everything between the two is
# reported as a `modified:`-date cohort instead, so one bulk date bump renders as one
# row rather than N findings (#2556).
ITEMISE_THRESHOLD_DAYS=180
CURRENT_DATE=$(date "+%Y-%m-%d")
CURRENT_TIMESTAMP=$(date "+%s")

# Initialize counters
total_plugins=0
total_skills=0
stale_skills=0
missing_plugin_json_fields=0
missing_frontmatter_fields=0

# Temporary storage for results.
# Use empty-assignment (arr=()) rather than `declare -a arr`: a `declare`d
# array with no element assigned is treated as unset under `set -u`, so a later
# "${#arr[@]}" / "${arr[@]}" on a still-empty array aborts the script (the
# frontmatter_issues_list case when a run has zero frontmatter issues).
stale_skills_list=()
plugin_compliance_list=()
frontmatter_issues_list=()

# Helper function: Extract YAML frontmatter field
extract_field() {
  local file="$1"
  local field="$2"
  head -50 "$file" 2>/dev/null | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || echo ""
}

# Helper function: Calculate days between dates
days_since_date() {
  local past_date="$1"

  # Try macOS date format first
  if date -j -f "%Y-%m-%d" "$past_date" "+%s" >/dev/null 2>&1; then
    local past_timestamp
    past_timestamp=$(date -j -f "%Y-%m-%d" "$past_date" "+%s")
  # Fallback to GNU date format
  elif date -d "$past_date" "+%s" >/dev/null 2>&1; then
    local past_timestamp
    past_timestamp=$(date -d "$past_date" "+%s")
  else
    echo "N/A"
    return
  fi

  local diff_seconds=$((CURRENT_TIMESTAMP - past_timestamp))
  local diff_days=$((diff_seconds / 86400))
  echo "$diff_days"
}

# 1. Find all plugins (directories ending in -plugin)
cd "$REPO_ROOT" || exit 1
while IFS= read -r -d '' plugin_dir; do
  plugin_name=$(basename "$plugin_dir")
  total_plugins=$((total_plugins+1))

  # Check plugin.json existence and validation
  plugin_json="$plugin_dir/.claude-plugin/plugin.json"
  has_plugin_json="✓"
  plugin_json_issues=""

  if [ -f "$plugin_json" ]; then
    # Validate required field: name
    json_name=$(jq -r '.name // ""' "$plugin_json" 2>/dev/null || echo "")
    if [ -z "$json_name" ]; then
      plugin_json_issues+="Missing 'name'. "
      missing_plugin_json_fields=$((missing_plugin_json_fields+1))
    elif [ "$json_name" != "$plugin_name" ]; then
      plugin_json_issues+="Name mismatch ('$json_name' vs '$plugin_name'). "
    fi

    # Check kebab-case format for name
    if [ -n "$json_name" ] && ! [[ "$json_name" =~ ^[a-z][a-z0-9-]*$ ]]; then
      plugin_json_issues+="Name not kebab-case. "
    fi

    # Check recommended fields
    for field in version description keywords; do
      value=$(jq -r ".$field // \"\"" "$plugin_json" 2>/dev/null || echo "")
      if [ -z "$value" ] || [ "$value" = "null" ]; then
        plugin_json_issues+="Missing '$field'. "
        missing_plugin_json_fields=$((missing_plugin_json_fields+1))
      fi
    done
  else
    has_plugin_json="✗"
    plugin_json_issues="File missing"
    missing_plugin_json_fields=$((missing_plugin_json_fields+1))
  fi

  # Check README.md existence
  readme="$plugin_dir/README.md"
  has_readme="✓"
  if [ ! -f "$readme" ]; then
    has_readme="✗"
  fi

  # 2. Find all skills in this plugin
  plugin_skill_count=0
  while IFS= read -r -d '' skill_file; do
    total_skills=$((total_skills+1))
    plugin_skill_count=$((plugin_skill_count+1))

    skill_name=$(basename "$(dirname "$skill_file")")

    # Extract frontmatter fields
    skill_name_field=$(extract_field "$skill_file" "name")
    skill_desc=$(extract_field "$skill_file" "description")
    skill_allowed_tools=$(extract_field "$skill_file" "allowed-tools")
    skill_created=$(extract_field "$skill_file" "created")
    skill_modified=$(extract_field "$skill_file" "modified")
    skill_reviewed=$(extract_field "$skill_file" "reviewed")

    # Check required frontmatter fields
    missing_required=""
    [ -z "$skill_name_field" ] && missing_required+="name, "
    [ -z "$skill_desc" ] && missing_required+="description, "
    [ -z "$skill_allowed_tools" ] && missing_required+="allowed-tools, "

    # Check recommended fields
    # Note: `model` is intentionally not checked. Skills should inherit the
    # user's active model by default — see .claude/rules/skill-development.md.
    missing_recommended=""
    [ -z "$skill_created" ] && missing_recommended+="created, "
    [ -z "$skill_modified" ] && missing_recommended+="modified, "
    [ -z "$skill_reviewed" ] && missing_recommended+="reviewed, "

    if [ -n "$missing_required" ]; then
      missing_required="${missing_required%, }"
      frontmatter_issues_list+=("$plugin_name | $skill_name | Required: $missing_required")
      missing_frontmatter_fields=$((missing_frontmatter_fields+1))
    fi

    if [ -n "$missing_recommended" ]; then
      missing_recommended="${missing_recommended%, }"
      frontmatter_issues_list+=("$plugin_name | $skill_name | Recommended: $missing_recommended")
    fi

    # Check skill staleness
    if [ -n "$skill_modified" ]; then
      days_stale=$(days_since_date "$skill_modified")
      if [ "$days_stale" != "N/A" ] && [ "$days_stale" -gt "$STALE_THRESHOLD_DAYS" ]; then
        stale_skills_list+=("$plugin_name | $skill_name | $skill_modified | $days_stale")
        stale_skills=$((stale_skills+1))
      fi
    fi
  done < <(find "$plugin_dir/skills" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null || true)

  # Store plugin compliance info
  plugin_compliance_list+=("$plugin_name | $has_plugin_json | $has_readme | $plugin_skill_count | ${plugin_json_issues:-OK}")

done < <(find . -maxdepth 1 -type d -name "*-plugin" -not -name ".claude-plugin" -print0 2>/dev/null || true)

# Derive the stale-skill cohorts and the itemised tail.
#
# `stale_skills_list` entries are "plugin | skill | date | days". A bulk
# `modified:` bump lands 100+ skills on a single date, and rendering that as N
# independent findings manufactures next month's report (#2556). So the >90d
# band is summarised one-row-per-date, and only the >ITEMISE_THRESHOLD_DAYS tail
# is itemised. Both are derived at runtime — never hardcoded.
stale_cohort_table=""
stale_tail_rows=""
stale_tail_count=0
stale_top_date=""
stale_top_count=0
if [ "$stale_skills" -gt 0 ]; then
  stale_cohort_counts=$(printf '%s\n' "${stale_skills_list[@]}" \
    | awk -F'|' '{gsub(/ /,"",$3); print $3}' | sort | uniq -c | sort -rn)
  stale_cohort_table=$(printf '%s\n' "$stale_cohort_counts" \
    | awk 'NF == 2 { printf "| %s | %s |\n", $2, $1 }')
  read -r stale_top_count stale_top_date <<<"$(printf '%s\n' "$stale_cohort_counts" \
    | awk 'NR == 1 { print $1, $2 }')" || true
  stale_tail_rows=$(printf '%s\n' "${stale_skills_list[@]}" \
    | awk -F'|' -v threshold="$ITEMISE_THRESHOLD_DAYS" \
        '{ days = $4; gsub(/[^0-9]/, "", days); if (days + 0 > threshold + 0) print }')
  if [ -n "$stale_tail_rows" ]; then
    stale_tail_count=$(printf '%s\n' "$stale_tail_rows" | grep -c '' || true)
  fi
fi

# Generate markdown report
echo "## Monthly Blueprint Health: $CURRENT_DATE"
echo ""
echo "### Summary"
echo "| Metric | Value |"
echo "|--------|-------|"
echo "| Total plugins | $total_plugins |"
echo "| Total skills | $total_skills |"
echo "| Stale skills (>90d since \`modified:\`) | $stale_skills |"
echo "| Missing plugin.json fields | $missing_plugin_json_fields |"
echo "| Missing frontmatter fields | $missing_frontmatter_fields |"
echo ""

if [ "$stale_skills" -gt 0 ]; then
  echo "### Stale Skills by \`modified:\` date"
  echo "| Date | Skills |"
  echo "|------|--------|"
  echo "$stale_cohort_table"
  echo ""
  echo "Skills sharing a \`modified:\` date were changed together — read a dominant"
  echo "date as one event, not as that many independent findings."
  echo ""

  if [ -n "$stale_tail_rows" ]; then
    echo "### Stale Skills (>$ITEMISE_THRESHOLD_DAYS days since modified)"
    echo "| Plugin | Skill | Last Modified | Days Stale |"
    echo "|--------|-------|---------------|------------|"
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      echo "| $entry |"
    done <<<"$stale_tail_rows"
    echo ""
  fi
fi

echo "### Plugin Compliance"
echo "| Plugin | plugin.json | README | Skills | Issues |"
echo "|--------|-------------|--------|--------|--------|"
for entry in "${plugin_compliance_list[@]}"; do
  echo "| $entry |"
done
echo ""

if [ "${#frontmatter_issues_list[@]}" -gt 0 ]; then
  echo "### Frontmatter Issues"
  echo "| Plugin | Skill | Missing Fields |"
  echo "|--------|-------|----------------|"
  for entry in "${frontmatter_issues_list[@]}"; do
    echo "| $entry |"
  done
  echo ""
fi

echo "### Recommendations"
if [ "$stale_skills" -gt 0 ]; then
  echo "- Review the $stale_tail_count skill(s) in the >${ITEMISE_THRESHOLD_DAYS}d tail against current upstream docs. The >${STALE_THRESHOLD_DAYS}d total ($stale_skills) is dominated by the $stale_top_date cohort ($stale_top_count skills sharing one \`modified:\` date) — treat that as one event, not $stale_skills findings."
fi
if [ "$missing_plugin_json_fields" -gt 0 ]; then
  echo "- Add missing plugin.json fields (name, version, description, keywords are recommended)"
fi
if [ "$missing_frontmatter_fields" -gt 0 ]; then
  echo "- Complete frontmatter in skills: required fields are \`name\`, \`description\`, \`allowed-tools\`"
fi
if [ "$stale_skills" -eq 0 ] && [ "$missing_plugin_json_fields" -eq 0 ] && [ "$missing_frontmatter_fields" -eq 0 ]; then
  echo "- All checks passed! Repository is in good health."
fi

# Explicit terminal exit — see the note in scripts/infra-compliance-check.sh.
# This file previously ended on a bare `if` whose exit status leaked into the
# script contract.
exit 0
