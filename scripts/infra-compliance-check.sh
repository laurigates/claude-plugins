#!/usr/bin/env bash
set -euo pipefail

# Infrastructure Compliance Check Script
# Performs registry sync, workflow health, version consistency, skill coverage, and security checks
# Usage: ./scripts/infra-compliance-check.sh

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CURRENT_MONTH=$(date "+%Y-%m")

# Scoring
registry_total=0; registry_pass=0
workflow_total=0; workflow_pass=0
version_total=0; version_pass=0
skill_total=0; skill_pass=0
security_total=0; security_pass=0

# Results storage
registry_rows=()
orphan_entries=()
workflow_rows=()
version_rows=()
skill_rows=()
security_rows=()
recommendations=()

total_skills_count=0

##########
# 1. Registry 4-File Sync
##########

plugin_dirs=()
while IFS= read -r -d '' dir; do
  plugin_dirs+=("$(basename "$dir")")
done < <(find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0 | sort -z)

for plugin in "${plugin_dirs[@]}"; do
  has_json="❌"; has_market="❌"; has_config="❌"; has_manifest="❌"

  if [ -f "${plugin}/.claude-plugin/plugin.json" ]; then
    pj_name=$(jq -r '.name // ""' "${plugin}/.claude-plugin/plugin.json" 2>/dev/null)
    [ -n "$pj_name" ] && has_json="✅"
  fi

  if [ -f ".claude-plugin/marketplace.json" ]; then
    mp_entry=$(jq --arg p "$plugin" '.plugins[] | select(.name == $p)' .claude-plugin/marketplace.json 2>/dev/null)
    [ -n "$mp_entry" ] && has_market="✅"
  fi

  if [ -f "release-please-config.json" ]; then
    rp_entry=$(jq --arg p "$plugin" '.packages[$p]' release-please-config.json 2>/dev/null)
    [ "$rp_entry" != "null" ] && [ -n "$rp_entry" ] && has_config="✅"
  fi

  if [ -f ".release-please-manifest.json" ]; then
    rm_entry=$(jq --arg p "$plugin" '.[$p]' .release-please-manifest.json 2>/dev/null)
    [ "$rm_entry" != "null" ] && [ -n "$rm_entry" ] && has_manifest="✅"
  fi

  ((registry_total += 4))
  [ "$has_json" = "✅" ] && ((registry_pass++)) || true
  [ "$has_market" = "✅" ] && ((registry_pass++)) || true
  [ "$has_config" = "✅" ] && ((registry_pass++)) || true
  [ "$has_manifest" = "✅" ] && ((registry_pass++)) || true

  row_status="✅"
  for s in "$has_json" "$has_market" "$has_config" "$has_manifest"; do
    [ "$s" = "❌" ] && row_status="❌" && break
  done

  registry_rows+=("$plugin | $has_json | $has_market | $has_config | $has_manifest | $row_status")
done

# Orphaned entries
if [ -f ".claude-plugin/marketplace.json" ]; then
  while IFS= read -r mp_name; do
    [ ! -d "$mp_name" ] && orphan_entries+=("marketplace.json: '$mp_name' (no directory)")
  done < <(jq -r '.plugins[].name' .claude-plugin/marketplace.json 2>/dev/null)
fi

if [ -f "release-please-config.json" ]; then
  while IFS= read -r rp_name; do
    [ ! -d "$rp_name" ] && orphan_entries+=("release-please-config.json: '$rp_name' (no directory)")
  done < <(jq -r '.packages | keys[]' release-please-config.json 2>/dev/null)
fi

##########
# 2. Workflow Health
##########

while IFS= read -r -d '' wf; do
  wf_name=$(basename "$wf")

  checkout_ver="N/A"
  if grep -q 'actions/checkout@' "$wf" 2>/dev/null; then
    checkout_ver=$(grep -m1 -oE 'actions/checkout@[^ "]+' "$wf" | sed 's/actions\/checkout@//')
  fi
  checkout_ok="✅"
  if [ "$checkout_ver" != "N/A" ] && [ "$checkout_ver" != "v4" ]; then
    checkout_ok="⚠️"
  fi

  claude_ver="N/A"
  if grep -q 'anthropics/claude-code-action@' "$wf" 2>/dev/null; then
    claude_ver=$(grep -m1 -oE 'anthropics/claude-code-action@[^ "]+' "$wf" | sed 's/anthropics\/claude-code-action@//')
  fi
  claude_ok="✅"
  if [ "$claude_ver" != "N/A" ] && [ "$claude_ver" != "v1" ]; then
    claude_ok="⚠️"
  fi

  perms_ok="✅"
  if grep -q 'write-all' "$wf" 2>/dev/null; then
    perms_ok="⚠️"
  fi

  filters_ok="✅"
  if grep -q 'pull_request:' "$wf" 2>/dev/null; then
    if ! grep -q 'paths:' "$wf" 2>/dev/null; then
      filters_ok="⚠️"
    fi
  else
    filters_ok="N/A"
  fi

  # Count checks
  checks=("$checkout_ok" "$claude_ok" "$perms_ok" "$filters_ok")
  for c in "${checks[@]}"; do
    [ "$c" != "N/A" ] && ((workflow_total++)) || true
    [ "$c" = "✅" ] && ((workflow_pass++)) || true
  done

  row_status="✅"
  for s in "${checks[@]}"; do
    [ "$s" = "⚠️" ] && row_status="⚠️"
    [ "$s" = "❌" ] && row_status="❌" && break
  done

  workflow_rows+=("$wf_name | ${checkout_ver} | ${claude_ver} | $perms_ok | $filters_ok | $row_status")
done < <(find .github/workflows -maxdepth 1 -name '*.yml' -print0 2>/dev/null | sort -z)

##########
# 3. Version Consistency
##########

for plugin in "${plugin_dirs[@]}"; do
  ((version_total++))

  pj_ver="N/A"; mf_ver="N/A"; mp_ver="N/A"

  [ -f "${plugin}/.claude-plugin/plugin.json" ] && \
    pj_ver=$(jq -r '.version // "N/A"' "${plugin}/.claude-plugin/plugin.json" 2>/dev/null)
  [ -f ".release-please-manifest.json" ] && \
    mf_ver=$(jq -r --arg p "$plugin" '.[$p] // "N/A"' .release-please-manifest.json 2>/dev/null)
  [ -f ".claude-plugin/marketplace.json" ] && \
    mp_ver=$(jq -r --arg p "$plugin" '(.plugins[] | select(.name == $p) | .version) // "N/A"' .claude-plugin/marketplace.json 2>/dev/null)

  match="✅"
  vers=()
  [ "$pj_ver" != "N/A" ] && vers+=("$pj_ver")
  [ "$mf_ver" != "N/A" ] && vers+=("$mf_ver")
  [ "$mp_ver" != "N/A" ] && vers+=("$mp_ver")

  if [ ${#vers[@]} -ge 2 ]; then
    first="${vers[0]}"
    for v in "${vers[@]}"; do
      [ "$v" != "$first" ] && match="❌" && break
    done
  fi

  [ "$match" = "✅" ] && ((version_pass++)) || true
  version_rows+=("$plugin | $pj_ver | $mf_ver | $mp_ver | $match")
done

##########
# 4. Skill Coverage
##########

for plugin in "${plugin_dirs[@]}"; do
  ((skill_total++))

  sc=0
  [ -d "${plugin}/skills" ] && \
    sc=$(find "${plugin}/skills" -type f \( -iname "SKILL.md" -o -iname "skill.md" \) 2>/dev/null | wc -l | tr -d ' ')

  total_skills_count=$((total_skills_count + sc))
  has_skills="✅"
  [ "$sc" -eq 0 ] && has_skills="❌"
  [ "$has_skills" = "✅" ] && ((skill_pass++)) || true

  skill_rows+=("$plugin | $sc | $has_skills")
done

avg_skills="N/A"
[ "$skill_total" -gt 0 ] && avg_skills=$(echo "scale=1; $total_skills_count / $skill_total" | bc 2>/dev/null || echo "N/A")

##########
# 5. Security Posture
##########

while IFS= read -r -d '' wf; do
  wf_name=$(basename "$wf")
  ((security_total++))

  if grep -qiE '(ghp_|gho_|github_pat_|sk-|Bearer [A-Za-z0-9])' "$wf" 2>/dev/null; then
    security_rows+=("🔴 | $wf_name | Token pattern detected")
  elif grep -qiE '(token|key|secret|password)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9+/=]{20,}' "$wf" 2>/dev/null; then
    security_rows+=("🔴 | $wf_name | Potential hardcoded secret")
  else
    ((security_pass++)) || true
  fi
done < <(find .github/workflows -maxdepth 1 -name '*.yml' -print0 2>/dev/null | sort -z)

# Broad Bash permissions in skills
while IFS= read -r -d '' skill_file; do
  at_field=$(head -50 "$skill_file" 2>/dev/null | grep -m1 "^allowed-tools:" | sed 's/^[^:]*:[[:space:]]*//' || echo "")
  if echo "$at_field" | grep -qE '(^|,\s*)Bash(\s*,|$)' 2>/dev/null; then
    ((security_total++))
    security_rows+=("🟡 | ${skill_file#./} | Broad Bash permission (no command pattern)")
  fi
done < <(find . -path '*/skills/*' \( -iname "SKILL.md" -o -iname "skill.md" \) -print0 2>/dev/null)

##########
# Scoring
##########

calc_score() {
  local pass=$1 total=$2 weight=$3
  [ "$total" -eq 0 ] && echo "$weight" && return
  echo "$(( (pass * weight) / total ))"
}

score_registry=$(calc_score $registry_pass $registry_total 25)
score_workflow=$(calc_score $workflow_pass $workflow_total 25)
score_version=$(calc_score $version_pass $version_total 20)
score_skill=$(calc_score $skill_pass $skill_total 15)
score_security=$(calc_score $security_pass $security_total 15)
overall_score=$((score_registry + score_workflow + score_version + score_skill + score_security))

##########
# Output
##########

echo "## Infrastructure Compliance Dashboard: $CURRENT_MONTH"
echo ""
echo "### Overall Score: ${overall_score}/100"
echo ""

echo "### Registry Consistency"
echo "| Plugin | plugin.json | marketplace | release-config | manifest | Status |"
echo "|--------|-------------|-------------|----------------|----------|--------|"
for row in "${registry_rows[@]}"; do
  echo "| $row |"
done
echo ""

if [ ${#orphan_entries[@]} -gt 0 ]; then
  echo "**Orphaned entries:**"
  for entry in "${orphan_entries[@]}"; do
    echo "- $entry"
  done
  echo ""
fi

echo "### Workflow Health"
echo "| Workflow | Checkout | Claude Action | Permissions | Filters | Status |"
echo "|----------|----------|---------------|-------------|---------|--------|"
for row in "${workflow_rows[@]}"; do
  echo "| $row |"
done
echo ""

echo "### Version Consistency"
echo "| Plugin | plugin.json | manifest | marketplace | Match? |"
echo "|--------|-------------|----------|-------------|--------|"
for row in "${version_rows[@]}"; do
  echo "| $row |"
done
echo ""

echo "### Skill Coverage"
echo "| Plugin | Skills | Has Skills? |"
echo "|--------|--------|-------------|"
for row in "${skill_rows[@]}"; do
  echo "| $row |"
done
echo ""
echo "Total: ${#plugin_dirs[@]} plugins, $total_skills_count skills (avg ${avg_skills} skills/plugin)"
echo ""

echo "### Security Findings"
if [ ${#security_rows[@]} -gt 0 ]; then
  echo "| Severity | File | Finding |"
  echo "|----------|------|---------|"
  for row in "${security_rows[@]}"; do
    echo "| $row |"
  done
else
  echo "No security issues found."
fi
echo ""

echo "### Recommendations"
[ "$registry_pass" -lt "$registry_total" ] && echo "- Fix registry sync issues — ensure all plugins are in all 4 config files"
[ "$workflow_pass" -lt "$workflow_total" ] && echo "- Update workflow action versions and add path filters where missing"
[ "$version_pass" -lt "$version_total" ] && echo "- Resolve version mismatches across plugin.json, manifest, and marketplace"
[ "$skill_pass" -lt "$skill_total" ] && echo "- Add skills to plugins with 0 skills or consider removing empty plugins"
[ ${#security_rows[@]} -gt 0 ] && echo "- Address security findings — review flagged files"
if [ "$overall_score" -ge 95 ]; then
  echo "- All checks passed! Infrastructure is in good health."
fi
echo ""

echo "### Score Breakdown"
echo "| Category | Weight | Score | Details |"
echo "|----------|--------|-------|---------|"
echo "| Registry sync | 25% | ${score_registry}/25 | ${registry_pass}/${registry_total} checks passed |"
echo "| Workflow health | 25% | ${score_workflow}/25 | ${workflow_pass}/${workflow_total} checks passed |"
echo "| Version consistency | 20% | ${score_version}/20 | ${version_pass}/${version_total} plugins consistent |"
echo "| Skill coverage | 15% | ${score_skill}/15 | ${skill_pass}/${skill_total} plugins have skills |"
echo "| Security posture | 15% | ${score_security}/15 | ${security_pass}/${security_total} files clean |"
