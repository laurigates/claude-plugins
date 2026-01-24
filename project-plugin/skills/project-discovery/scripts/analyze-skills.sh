#!/usr/bin/env bash
# Skill Script Opportunity Analyzer
# Scans all plugin skills and identifies candidates for supporting scripts.
# Usage: bash analyze-skills.sh [plugin-name]
#
# Evaluates: bash block count, workflow phases, context-gathering patterns,
# existing scripts, and skill size. Outputs structured recommendations.

set -uo pipefail

REPO_ROOT="${1:-.}"
SPECIFIC_PLUGIN="${2:-}"

echo "=== SKILL SCRIPT ANALYSIS ==="
echo ""

# Find all skills
if [ -n "$SPECIFIC_PLUGIN" ]; then
  skill_dirs=$(find "$REPO_ROOT/$SPECIFIC_PLUGIN/skills" -name "SKILL.md" -o -name "skill.md" 2>/dev/null)
else
  skill_dirs=$(find "$REPO_ROOT" -path "*-plugin/skills/*/SKILL.md" -o -path "*-plugin/skills/*/skill.md" 2>/dev/null | sort)
fi

total_skills=0
with_scripts=0
candidates=0

echo "--- CURRENT SCRIPT COVERAGE ---"
echo ""

# Report skills that already have scripts
for skill_file in $skill_dirs; do
  skill_dir=$(dirname "$skill_file")
  skill_name=$(basename "$skill_dir")
  plugin_name=$(echo "$skill_dir" | grep -oE "[^/]*-plugin/" | tail -1 | tr -d '/')

  total_skills=$((total_skills + 1))

  if [ -d "$skill_dir/scripts" ]; then
    with_scripts=$((with_scripts + 1))
    script_count=$(find "$skill_dir/scripts" -type f 2>/dev/null | wc -l | tr -d ' ')
    scripts=$(find "$skill_dir/scripts" -type f -exec basename {} \; 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    echo "  HAS_SCRIPTS: $plugin_name/$skill_name ($script_count: $scripts)"
  fi
done

echo ""
echo "COVERAGE: $with_scripts/$total_skills skills have scripts"
echo ""

# Analyze candidates
echo "--- CANDIDATES FOR SCRIPTS ---"
echo ""

for skill_file in $skill_dirs; do
  skill_dir=$(dirname "$skill_file")
  skill_name=$(basename "$skill_dir")
  plugin_name=$(echo "$skill_dir" | grep -oE "[^/]*-plugin/" | tail -1 | tr -d '/')

  # Skip skills that already have scripts
  [ -d "$skill_dir/scripts" ] && continue

  # Metrics (tr -d ' ' ensures clean integers)
  line_count=$(wc -l < "$skill_file" | tr -d ' ')
  bash_blocks=$(grep -c '```bash' "$skill_file" 2>/dev/null || true)
  bash_blocks=${bash_blocks:-0}
  bash_commands=$(grep -cE "^\s*(git |npm |bun |cargo |pip |pytest|ruff |black |eslint|biome |kubectl |helm |docker |terraform |gh |find |grep |ls |cat |head |jq |yq )" "$skill_file" 2>/dev/null || true)
  bash_commands=${bash_commands:-0}
  phases=$(grep -cE "^###? Phase|^###? Step" "$skill_file" 2>/dev/null || true)
  phases=${phases:-0}
  workflow_sections=$(grep -cE "^## .*(Workflow|Process|Pipeline|Execution)" "$skill_file" 2>/dev/null || true)
  workflow_sections=${workflow_sections:-0}
  context_patterns=$(grep -cE "(git status|git diff|git log|gh pr|gh issue|git branch)" "$skill_file" 2>/dev/null || true)
  context_patterns=${context_patterns:-0}

  # Ensure clean integers
  bash_blocks=$(echo "$bash_blocks" | tr -dc '0-9')
  bash_commands=$(echo "$bash_commands" | tr -dc '0-9')
  phases=$(echo "$phases" | tr -dc '0-9')
  context_patterns=$(echo "$context_patterns" | tr -dc '0-9')
  line_count=$(echo "$line_count" | tr -dc '0-9')
  : "${bash_blocks:=0}" "${bash_commands:=0}" "${phases:=0}" "${context_patterns:=0}" "${line_count:=0}"

  # Score: higher = better candidate for script extraction
  score=0
  reasons=""

  # Many bash blocks = repetitive commands that could be consolidated
  if [ "$bash_blocks" -ge 5 ]; then
    score=$((score + bash_blocks))
    reasons="${reasons}bash_blocks($bash_blocks) "
  fi

  # Many individual commands = token-heavy execution
  if [ "$bash_commands" -ge 8 ]; then
    score=$((score + bash_commands / 2))
    reasons="${reasons}commands($bash_commands) "
  fi

  # Multi-phase workflow = consolidation opportunity
  if [ "$phases" -ge 3 ]; then
    score=$((score + phases * 2))
    reasons="${reasons}phases($phases) "
  fi

  # Context-gathering patterns = single-script opportunity
  if [ "$context_patterns" -ge 4 ]; then
    score=$((score + context_patterns))
    reasons="${reasons}context_gathering($context_patterns) "
  fi

  # Large skill file = likely has extractable logic
  if [ "$line_count" -ge 200 ]; then
    score=$((score + 3))
    reasons="${reasons}large(${line_count}L) "
  fi

  # Report if score is meaningful
  if [ "$score" -ge 8 ]; then
    candidates=$((candidates + 1))

    # Determine script type recommendation
    script_type="utility"
    [ "$context_patterns" -ge 4 ] && script_type="context-gather"
    [ "$phases" -ge 3 ] && script_type="workflow"
    [ "$bash_commands" -ge 10 ] && script_type="multi-tool"

    echo "  CANDIDATE: $plugin_name/$skill_name"
    echo "    SCORE: $score"
    echo "    TYPE: $script_type"
    echo "    METRICS: ${line_count}L, ${bash_blocks} bash blocks, ${bash_commands} commands, ${phases} phases"
    echo "    REASONS: $reasons"
    echo ""
  fi
done

echo "--- SUMMARY ---"
echo "TOTAL_SKILLS=$total_skills"
echo "WITH_SCRIPTS=$with_scripts"
echo "CANDIDATES=$candidates"
echo ""

# Suggest script types
echo "--- SCRIPT TYPE GUIDE ---"
echo "  context-gather: Consolidates multiple read-only commands into structured output"
echo "  workflow: Replaces multi-phase process with single execution"
echo "  multi-tool: Auto-detects tools/environment and runs appropriate commands"
echo "  utility: General-purpose helper for repetitive operations"

echo ""
echo "=== ANALYSIS COMPLETE ==="
