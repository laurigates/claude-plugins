#!/usr/bin/env bash
# shellcheck disable=SC2016  # jq expressions use $ for variable references, not shell expansion
set -euo pipefail

# Plugin compliance checker - validates plugin structure and metadata
# Usage: ./scripts/plugin-compliance-check.sh [plugin1 plugin2 ...]
# If no args provided, auto-detects all *-plugin directories

# Change to repository root
cd "$(dirname "$0")/.." || exit 1

# Auto-detect plugins if no args provided
if [ $# -eq 0 ]; then
  PLUGINS=()
  while IFS= read -r -d '' dir; do
    PLUGINS+=("$(basename "$dir")")
  done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 | sort -z)
else
  PLUGINS=("$@")
fi

if [ ${#PLUGINS[@]} -eq 0 ]; then
  echo "No plugins found"
  exit 0
fi

# Status tracking
issues=()
recommendations=()
overall_failed=false

# Results arrays (parallel indexed with PLUGINS)
results_json=()
results_frontmatter=()
results_body=()
results_marketplace=()
results_release=()
results_bash=()
results_desc=()
results_when_to_use=()
results_overall=()

# Helper: extract YAML frontmatter field
extract_field() {
  local file="$1"
  local field="$2"
  head -50 "$file" 2>/dev/null | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' || echo ""
}

# Convert status code to symbol
to_symbol() {
  case $1 in
    0) echo "✅" ;;
    1) echo "⚠️" ;;
    *) echo "❌" ;;
  esac
}

# Check 1: plugin.json required fields
check_plugin_json() {
  local plugin="$1"
  local json_file="${plugin}/.claude-plugin/plugin.json"

  if [ ! -f "$json_file" ]; then
    issues+=("❌ ${plugin}: Missing .claude-plugin/plugin.json")
    return 2
  fi

  local plugin_name
  plugin_name=$(jq -r '.name // ""' "$json_file" 2>/dev/null)

  if [ -z "$plugin_name" ]; then
    issues+=("❌ ${plugin}: plugin.json missing required 'name' field")
    return 2
  fi

  if [ "$plugin_name" != "$plugin" ]; then
    issues+=("❌ ${plugin}: plugin.json name '${plugin_name}' doesn't match directory '${plugin}'")
    return 2
  fi

  if ! echo "$plugin_name" | grep -qE '^[a-z][a-z0-9-]*$'; then
    issues+=("❌ ${plugin}: plugin.json name '${plugin_name}' not in kebab-case format")
    return 2
  fi

  local missing_recommended=()
  local version description keywords
  version=$(jq -r '.version // ""' "$json_file" 2>/dev/null)
  description=$(jq -r '.description // ""' "$json_file" 2>/dev/null)
  keywords=$(jq -r '.keywords // [] | length' "$json_file" 2>/dev/null || echo "0")

  [ -z "$version" ] && missing_recommended+=("version")
  [ -z "$description" ] && missing_recommended+=("description")
  [ "$keywords" = "0" ] && missing_recommended+=("keywords")

  if [ ${#missing_recommended[@]} -gt 0 ]; then
    recommendations+=("⚠️ ${plugin}: plugin.json missing recommended fields: ${missing_recommended[*]}")
    return 1
  fi

  return 0
}

# Check 2: Skill frontmatter completeness
check_skill_frontmatter() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local skill_files=()
  while IFS= read -r -d '' f; do
    skill_files+=("$f")
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if [ ${#skill_files[@]} -eq 0 ]; then
    return 0
  fi

  local has_errors=false
  local has_warnings=false

  for skill_file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    local fm_name fm_description fm_allowed_tools
    fm_name=$(extract_field "$skill_file" "name")
    fm_description=$(extract_field "$skill_file" "description")
    fm_allowed_tools=$(extract_field "$skill_file" "allowed-tools")

    local missing_required=()
    [ -z "$fm_name" ] && missing_required+=("name")
    [ -z "$fm_description" ] && missing_required+=("description")
    [ -z "$fm_allowed_tools" ] && missing_required+=("allowed-tools")

    if [ ${#missing_required[@]} -gt 0 ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md missing required fields: ${missing_required[*]}")
      has_errors=true
      continue
    fi

    local fm_model fm_created fm_modified fm_reviewed
    fm_model=$(extract_field "$skill_file" "model")
    fm_created=$(extract_field "$skill_file" "created")
    fm_modified=$(extract_field "$skill_file" "modified")
    fm_reviewed=$(extract_field "$skill_file" "reviewed")

    local missing_recommended=()
    # Note: `model` may be set to `opus` or `sonnet` at the extremes; haiku is
    # disallowed for any skill (see check below). See
    # .claude/rules/skill-development.md ("Model Selection") for policy.
    [ -z "$fm_created" ] && missing_recommended+=("created")
    [ -z "$fm_modified" ] && missing_recommended+=("modified")
    [ -z "$fm_reviewed" ] && missing_recommended+=("reviewed")

    local fm_args fm_argument_hint
    fm_args=$(extract_field "$skill_file" "args")
    fm_argument_hint=$(extract_field "$skill_file" "argument-hint")

    if [ -n "$fm_args" ] && [ -z "$fm_argument_hint" ]; then
      missing_recommended+=("argument-hint (args present)")
    elif [ -z "$fm_args" ] && [ -n "$fm_argument_hint" ]; then
      missing_recommended+=("args (argument-hint present)")
    fi

    if [ ${#missing_recommended[@]} -gt 0 ]; then
      recommendations+=("⚠️ ${plugin}/${skill_name}: SKILL.md missing recommended fields: ${missing_recommended[*]}")
      has_warnings=true
    fi

    # Regression: model: haiku breaks AskUserQuestion (PR #879) and the cost
    # savings vs Sonnet do not justify the quality risk for non-interactive
    # skills either. Sonnet is the floor — see .claude/rules/skill-development.md.
    if [ "$fm_model" = "haiku" ]; then
      issues+=("❌ ${plugin}/${skill_name}: model: haiku is disallowed — use sonnet (floor) or opus")
      has_errors=true
    fi
  done

  if $has_errors; then
    return 2
  elif $has_warnings; then
    return 1
  fi

  return 0
}

# Check 3: Skill body integrity
# Regression: git-pr-feedback had 'name: fieldname' + '---' entries scattered in body,
# which render as accidental setext H2 headings in markdown (PR #799).
check_skill_body() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local has_errors=false

  while IFS= read -r -d '' skill_file; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    # Detect YAML-key lines immediately followed by '---' outside the frontmatter.
    # In CommonMark, "key: value\n---" creates a setext H2 heading — clearly unintended.
    # Use awk: skip the opening frontmatter block (first ---...--- pair), then flag hits.
    # Also skip content inside triple-backtick code fences to avoid false positives.
    local bad_lines
    bad_lines=$(awk '
      /^---$/ && fm_count < 2 { fm_count++; prev = ""; next }
      fm_count >= 2 {
        if (/^```/) { in_code = !in_code }
        if (!in_code && prev ~ /^[a-z][a-z-]*:/ && /^---$/) {
          print NR ": " prev
        }
        prev = $0
        next
      }
      { prev = $0 }
    ' "$skill_file")

    if [ -n "$bad_lines" ]; then
      while IFS= read -r hit; do
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md body has YAML-key+separator (accidental H2 heading) at line ${hit}")
      done <<< "$bad_lines"
      has_errors=true
    fi

    # Regression: blueprint rule-writing skills must reference the configurable
    # output path (`generated_rules_path`) rather than hardcoding `.claude/rules/`.
    # See issue #1043: hardcoded paths collide with hand-authored rules in the
    # parent .claude/rules/ directory.
    if [ "$skill_name" = "blueprint-generate-rules" ] || [ "$skill_name" = "blueprint-derive-rules" ]; then
      if ! grep -q "generated_rules_path" "$skill_file"; then
        issues+=("❌ ${plugin}/${skill_name}: SKILL.md must reference 'generated_rules_path' to honour configurable output directory (issue #1043)")
        has_errors=true
      fi
    fi

    # Regression: taskwarrior plugin skill examples must use underscores or
    # camelCase in tag names — never hyphens. Taskwarrior parses
    # `+blocked-on-merge` as `+blocked` AND `-on-merge` (mid-token exclude
    # filter), silently swallowing the tag. See issue #1237.
    # task-add/SKILL.md is allowed to use hyphenated forms inside the
    # documented "Tag naming gotcha" section as counter-examples.
    if [ "$plugin" = "taskwarrior-plugin" ] && [ "$skill_name" != "task-add" ]; then
      local tw_bad_tags
      tw_bad_tags=$(grep -nE '\+[a-z]+-[a-z]+' "$skill_file" 2>/dev/null || true)
      if [ -n "$tw_bad_tags" ]; then
        while IFS= read -r hit; do
          issues+=("❌ ${plugin}/${skill_name}: SKILL.md uses hyphenated taskwarrior tag — use underscore/camelCase (issue #1237): ${hit}")
        done <<< "$tw_bad_tags"
        has_errors=true
      fi
    fi
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  # Regression: task-add/SKILL.md must keep the "Tag naming gotcha" callout
  # so the parser quirk stays documented. See issue #1237.
  if [ "$plugin" = "taskwarrior-plugin" ] && [ -f "${skills_dir}/task-add/SKILL.md" ]; then
    if ! grep -q "Tag naming gotcha" "${skills_dir}/task-add/SKILL.md"; then
      issues+=("❌ ${plugin}/task-add: SKILL.md must contain the 'Tag naming gotcha' section explaining the hyphen parser quirk (issue #1237)")
      has_errors=true
    fi
  fi

  if $has_errors; then
    return 2
  fi

  return 0
}

# Check 4: marketplace.json entry
check_marketplace() {
  local plugin="$1"
  local marketplace_file=".claude-plugin/marketplace.json"

  if [ ! -f "$marketplace_file" ]; then
    issues+=("❌ ${plugin}: Missing .claude-plugin/marketplace.json")
    return 2
  fi

  local entry
  entry=$(jq --arg plugin "$plugin" '.plugins[] | select(.name == $plugin)' "$marketplace_file" 2>/dev/null)

  if [ -z "$entry" ]; then
    issues+=("❌ ${plugin}: No entry in marketplace.json")
    return 2
  fi

  local mp_name mp_source mp_description mp_version
  mp_name=$(echo "$entry" | jq -r '.name // ""')
  mp_source=$(echo "$entry" | jq -r '.source // ""')
  mp_description=$(echo "$entry" | jq -r '.description // ""')
  mp_version=$(echo "$entry" | jq -r '.version // ""')

  local missing_fields=()
  [ -z "$mp_name" ] && missing_fields+=("name")
  [ -z "$mp_source" ] && missing_fields+=("source")
  [ -z "$mp_description" ] && missing_fields+=("description")
  [ -z "$mp_version" ] && missing_fields+=("version")

  local expected_source="./${plugin}"
  if [ -n "$mp_source" ] && [ "$mp_source" != "$expected_source" ]; then
    missing_fields+=("source (expected '${expected_source}', got '${mp_source}')")
  fi

  if [ ${#missing_fields[@]} -gt 0 ]; then
    recommendations+=("⚠️ ${plugin}: marketplace.json entry issues: ${missing_fields[*]}")
    return 1
  fi

  return 0
}

# Check 5: release-please config
check_release_config() {
  local plugin="$1"
  local config_file="release-please-config.json"
  local manifest_file=".release-please-manifest.json"

  local has_errors=false

  if [ ! -f "$config_file" ]; then
    issues+=("❌ ${plugin}: Missing release-please-config.json")
    has_errors=true
  else
    local config_entry
    config_entry=$(jq --arg plugin "$plugin" '.packages[$plugin]' "$config_file" 2>/dev/null)
    if [ "$config_entry" = "null" ] || [ -z "$config_entry" ]; then
      issues+=("❌ ${plugin}: Not in release-please-config.json packages")
      has_errors=true
    fi
  fi

  if [ ! -f "$manifest_file" ]; then
    issues+=("❌ ${plugin}: Missing .release-please-manifest.json")
    has_errors=true
  else
    local manifest_entry
    manifest_entry=$(jq --arg plugin "$plugin" '.[$plugin]' "$manifest_file" 2>/dev/null)
    if [ "$manifest_entry" = "null" ] || [ -z "$manifest_entry" ]; then
      issues+=("❌ ${plugin}: Not in .release-please-manifest.json")
      has_errors=true
    fi
  fi

  if $has_errors; then
    return 2
  fi

  return 0
}

# Check 6: Shell utility patterns without scripts
# Regression: health-check used Bash(test *), Bash(jq *) etc. causing ~20 individual
# approval prompts. Skills with shell utility patterns should use standalone scripts.
check_bash_patterns() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local skill_files=()
  while IFS= read -r -d '' f; do
    skill_files+=("$f")
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if [ ${#skill_files[@]} -eq 0 ]; then
    return 0
  fi

  # Shell utilities that indicate inline scripting (not primary CLI tools)
  # shellcheck disable=SC2034  # documents the canonical list; loop below enumerates
  local shell_utils="test|jq|head|tail|cat|cp|mkdir|chmod|wc|date|ls|find"
  local has_warnings=false

  for skill_file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    local fm_allowed_tools
    fm_allowed_tools=$(extract_field "$skill_file" "allowed-tools")
    [ -z "$fm_allowed_tools" ] && continue

    # Count shell utility Bash patterns
    local util_count=0
    local util_list=""
    for util in test jq head tail cat cp mkdir chmod wc date; do
      if echo "$fm_allowed_tools" | grep -qE "Bash\(${util} "; then
        util_count=$((util_count + 1))
        util_list="${util_list:+${util_list}, }${util}"
      fi
    done

    # Warn if 3+ shell utility patterns and no scripts/ directory
    if [ "$util_count" -ge 3 ]; then
      local scripts_dir
      scripts_dir="$(dirname "$skill_file")/scripts"
      if [ ! -d "$scripts_dir" ]; then
        recommendations+=("⚠️ ${plugin}/${skill_name}: ${util_count} shell utility Bash patterns (${util_list}) — consider consolidating into scripts/ with Bash(bash *)")
        has_warnings=true
      fi
    fi
  done

  if $has_warnings; then
    return 1
  fi

  return 0
}

# Check 7: Skill description quality for auto-invocation
# Regression: skills whose description lacks a "Use when..." trigger clause are
# not matched by Claude's auto-invocation heuristic, so they rarely fire without
# explicit user instruction. See .claude/rules/skill-quality.md "Description
# Quality" checklist. Delegates to scripts/audit-skill-descriptions.py which
# handles multi-line YAML block scalars correctly.
check_skill_descriptions() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local audit_script="scripts/audit-skill-descriptions.py"
  if [ ! -f "$audit_script" ] || ! command -v python3 >/dev/null 2>&1; then
    return 0
  fi

  local audit_json
  if ! audit_json=$(python3 "$audit_script" --plugin "$plugin" --json 2>/dev/null); then
    return 0
  fi

  local has_errors=false
  local has_warnings=false

  while IFS=$'\t' read -r category skill_path auto; do
    [ -z "$category" ] && continue
    local skill_slug
    skill_slug=$(basename "$(dirname "$skill_path")")
    case "$category" in
      MISSING|EMPTY)
        issues+=("❌ ${plugin}/${skill_slug}: description is ${category} — Claude cannot auto-invoke this skill")
        has_errors=true
        ;;
      NO_TRIGGER)
        if [ "$auto" = "true" ]; then
          recommendations+=("⚠️ ${plugin}/${skill_slug}: description lacks a \"Use when...\" trigger clause — Claude may not auto-invoke this skill (see .claude/rules/skill-quality.md)")
          has_warnings=true
        fi
        ;;
    esac
  done < <(echo "$audit_json" | jq -r '.[] | select(.category != "OK") | [.category, .path, (.auto_invokable | tostring)] | @tsv')

  if $has_errors; then
    return 2
  elif $has_warnings; then
    return 1
  fi
  return 0
}

# Check 8: "When to Use This Skill" section presence
# Regression: Wave 3 issue draining (umbrella issue #1156) swept every plugin's
# skills to comply with .claude/rules/skill-quality.md (lines 27-38), which
# requires every SKILL.md to have a `## When to Use This Skill` heading
# immediately followed by a markdown table. This check keeps the tree compliant.
check_skill_when_to_use() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local skill_files=()
  while IFS= read -r -d '' f; do
    skill_files+=("$f")
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

  if [ ${#skill_files[@]} -eq 0 ]; then
    return 0
  fi

  local has_errors=false

  for skill_file in "${skill_files[@]}"; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")

    # Find the heading line number (exact match, anchored).
    local heading_line
    heading_line=$(grep -n '^## When to Use This Skill$' "$skill_file" | head -1 | cut -d: -f1)

    if [ -z "$heading_line" ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md missing '## When to Use This Skill' heading (see .claude/rules/skill-quality.md)")
      has_errors=true
      continue
    fi

    # Look for a markdown table row (line starting with '|') within ~10 lines
    # after the heading. The blank line and the table header both count as
    # acceptable interleaving — we only need the first '|' to appear by then.
    local window_start=$((heading_line + 1))
    local window_end=$((heading_line + 10))
    local table_line
    table_line=$(awk -v start="$window_start" -v end="$window_end" \
      'NR >= start && NR <= end && /^\|/ { print NR; exit }' "$skill_file")

    if [ -z "$table_line" ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md '## When to Use This Skill' heading at line ${heading_line} not followed by a markdown table within 10 lines")
      has_errors=true
    fi
  done

  if $has_errors; then
    return 2
  fi

  return 0
}

# Main check loop
for i in "${!PLUGINS[@]}"; do
  plugin="${PLUGINS[$i]}"

  if [ ! -d "$plugin" ]; then
    issues+=("❌ ${plugin}: Directory not found")
    results_json+=("❌")
    results_frontmatter+=("❌")
    results_body+=("❌")
    results_marketplace+=("❌")
    results_release+=("❌")
    results_bash+=("❌")
    results_desc+=("❌")
    results_when_to_use+=("❌")
    results_overall+=("❌")
    overall_failed=true
    continue
  fi

  # Run checks (capture exit codes without triggering set -e)
  json_status=0; check_plugin_json "$plugin" || json_status=$?
  frontmatter_status=0; check_skill_frontmatter "$plugin" || frontmatter_status=$?
  body_status=0; check_skill_body "$plugin" || body_status=$?
  marketplace_status=0; check_marketplace "$plugin" || marketplace_status=$?
  release_status=0; check_release_config "$plugin" || release_status=$?
  bash_status=0; check_bash_patterns "$plugin" || bash_status=$?
  desc_status=0; check_skill_descriptions "$plugin" || desc_status=$?
  when_to_use_status=0; check_skill_when_to_use "$plugin" || when_to_use_status=$?

  results_json+=("$(to_symbol $json_status)")
  results_frontmatter+=("$(to_symbol $frontmatter_status)")
  results_body+=("$(to_symbol $body_status)")
  results_marketplace+=("$(to_symbol $marketplace_status)")
  results_release+=("$(to_symbol $release_status)")
  results_bash+=("$(to_symbol $bash_status)")
  results_desc+=("$(to_symbol $desc_status)")
  results_when_to_use+=("$(to_symbol $when_to_use_status)")

  # Overall: ❌ if any ❌, ⚠️ if any ⚠️, ✅ if all ✅
  plugin_overall="✅"
  for status in $json_status $frontmatter_status $body_status $marketplace_status $release_status $bash_status $desc_status $when_to_use_status; do
    if [ "$status" -ge 2 ]; then
      plugin_overall="❌"
      overall_failed=true
      break
    elif [ "$status" -eq 1 ]; then
      plugin_overall="⚠️"
    fi
  done
  results_overall+=("$plugin_overall")
done

# Output report
echo "## Plugin Compliance Review"
echo ""
echo "| Plugin | plugin.json | Frontmatter | Body | Marketplace | Release Config | Bash Patterns | Descriptions | When-to-Use | Overall |"
echo "|--------|-------------|-------------|------|-------------|----------------|---------------|--------------|-------------|---------|"

for i in "${!PLUGINS[@]}"; do
  echo "| ${PLUGINS[$i]} | ${results_json[$i]} | ${results_frontmatter[$i]} | ${results_body[$i]} | ${results_marketplace[$i]} | ${results_release[$i]} | ${results_bash[$i]} | ${results_desc[$i]} | ${results_when_to_use[$i]} | ${results_overall[$i]} |"
done

echo ""

# Issues section
if [ ${#issues[@]} -gt 0 ]; then
  echo "### Issues Found"
  echo ""
  for issue in "${issues[@]}"; do
    echo "- $issue"
  done
  echo ""
fi

# Recommendations section
if [ ${#recommendations[@]} -gt 0 ]; then
  echo "### Recommendations"
  echo ""
  for rec in "${recommendations[@]}"; do
    echo "- $rec"
  done
  echo ""
fi

if $overall_failed; then
  exit 1
fi

exit 0
