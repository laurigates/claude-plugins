#!/usr/bin/env bash
set -euo pipefail

# Plugin compliance checker - validates plugin structure and metadata
# Usage: ./scripts/plugin-compliance-check.sh [plugin1 plugin2 ...]
# If no args provided, auto-detects all *-plugin directories

# Change to repository root
cd "$(dirname "$0")/.."

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
results_size=()
results_marketplace=()
results_release=()
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
    [ -z "$fm_model" ] && missing_recommended+=("model")
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
  done

  if $has_errors; then
    return 2
  elif $has_warnings; then
    return 1
  fi

  return 0
}

# Check 3: Skill size
check_skill_size() {
  local plugin="$1"
  local skills_dir="${plugin}/skills"

  if [ ! -d "$skills_dir" ]; then
    return 0
  fi

  local has_errors=false

  while IFS= read -r -d '' skill_file; do
    local skill_name
    skill_name=$(basename "$(dirname "$skill_file")")
    local line_count
    line_count=$(wc -l < "$skill_file")

    if [ "$line_count" -gt 500 ]; then
      issues+=("❌ ${plugin}/${skill_name}: SKILL.md has ${line_count} lines (max 500)")
      has_errors=true
    fi
  done < <(find "$skills_dir" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

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

# Main check loop
for i in "${!PLUGINS[@]}"; do
  plugin="${PLUGINS[$i]}"

  # Skip .claude-plugin - it's the root metadata directory, not a plugin
  if [ "$plugin" = ".claude-plugin" ]; then
    continue
  fi

  if [ ! -d "$plugin" ]; then
    issues+=("❌ ${plugin}: Directory not found")
    results_json+=("❌")
    results_frontmatter+=("❌")
    results_size+=("❌")
    results_marketplace+=("❌")
    results_release+=("❌")
    results_overall+=("❌")
    overall_failed=true
    continue
  fi

  # Run checks (capture exit codes without triggering set -e)
  json_status=0; check_plugin_json "$plugin" || json_status=$?
  frontmatter_status=0; check_skill_frontmatter "$plugin" || frontmatter_status=$?
  size_status=0; check_skill_size "$plugin" || size_status=$?
  marketplace_status=0; check_marketplace "$plugin" || marketplace_status=$?
  release_status=0; check_release_config "$plugin" || release_status=$?

  results_json+=("$(to_symbol $json_status)")
  results_frontmatter+=("$(to_symbol $frontmatter_status)")
  results_size+=("$(to_symbol $size_status)")
  results_marketplace+=("$(to_symbol $marketplace_status)")
  results_release+=("$(to_symbol $release_status)")

  # Overall: ❌ if any ❌, ⚠️ if any ⚠️, ✅ if all ✅
  plugin_overall="✅"
  for status in $json_status $frontmatter_status $size_status $marketplace_status $release_status; do
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
echo "| Plugin | plugin.json | Frontmatter | Size | Marketplace | Release Config | Overall |"
echo "|--------|-------------|-------------|------|-------------|----------------|---------|"

for i in "${!PLUGINS[@]}"; do
  echo "| ${PLUGINS[$i]} | ${results_json[$i]} | ${results_frontmatter[$i]} | ${results_size[$i]} | ${results_marketplace[$i]} | ${results_release[$i]} | ${results_overall[$i]} |"
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
