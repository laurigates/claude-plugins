#!/usr/bin/env bash
# Skill Script Opportunity Analyzer
# Scans all plugin skills and identifies candidates for supporting scripts.
# Usage: bash analyze-skills.sh [repo-root] [plugin-name] [--funnel]
#
# Default mode evaluates: bash block count, workflow phases, context-gathering
# patterns, existing scripts, and skill size. Outputs structured recommendations.
#
# --funnel mode (ADR-0016 deterministic pre-filter, issue #1551): bins every
# script-less skill into SKIP_* / LLM_STRONG / LLM_WEAK so a downstream LLM pass
# is reserved for the residue instead of fanning out over every skill. Emits the
# structured-script-output.md KEY=VALUE / STATUS= / ISSUE_COUNT= contract so an
# orchestrating workflow can read the verdict, not the computation. Cheap signals
# (mechanically detectable from SKILL.md, per ADR-0016 lines 86-114):
#   STRONG  -> >=2 data-processing pipes (jq/grep/awk/wc/cut/sort/uniq),
#              an extraction verb in name/description, OR analyzer_score >= 24
#              (the v1 selection cutoff). Procedure worth an LLM verify pass.
#   SKIP_INTERACTIVE -> AskUserQuestion/multiSelect and no strong signal (judgment).
#   SKIP_REFERENCE   -> "Use when mentioning/referencing X" knowledge-skill prose.
#   SKIP_NOPROC      -> <3 shell code blocks (no embedded procedure to extract).
#   WEAK    -> has procedure but only a weak signal; an optional LLM classify pass.
# STRONG signals win over SKIP signals: a confirmed candidate can carry a descoped
# AskUserQuestion confirmation step (every v1 candidate did), so an interactive
# step never by itself disqualifies a procedural skill.

set -uo pipefail

# --- arg parsing: --funnel may appear in any position --------------------------
FUNNEL_MODE=0
positional=()
for arg in "$@"; do
  case "$arg" in
    --funnel) FUNNEL_MODE=1 ;;
    *) positional+=("$arg") ;;
  esac
done
REPO_ROOT="${positional[0]:-.}"
SPECIFIC_PLUGIN="${positional[1]:-}"

# Extraction verbs (word-stems) whose presence in a skill name/description signals
# deterministic, rule-comparison intent (ADR-0016 "Candidate task types").
FUNNEL_VERB_RE='audit|validat|check|scan|detect|count|verif|lint|inspect'
# Data-processing pipe targets: a SKILL.md piping into >=2 of these is parsing
# logic begging to be a script.
FUNNEL_PIPE_RE='\|[[:space:]]*(jq|grep|awk|wc|cut|sort|uniq)'
# Reference/knowledge-skill description shape -> not an extraction target.
FUNNEL_REF_RE='[Uu]se when.*(mention|referenc|working with)'
# analyzer_score at or above this is treated as a strong candidate on its own
# (the v1 campaign filed everything scoring >= 24; the tail scores 0-23).
FUNNEL_STRONG_SCORE=24

# Find all skills
if [ -n "$SPECIFIC_PLUGIN" ]; then
  skill_dirs=$(find "$REPO_ROOT/$SPECIFIC_PLUGIN/skills" -name "SKILL.md" -o -name "skill.md" 2>/dev/null)
else
  # Prune .claude/worktrees/ — each linked worktree is a full repo clone, so an
  # unpruned walk enumerates the skill tree N+1 times (slow + inflated counts).
  # Mirrors the #1492 fix in scripts/check-version-pin-coverage.sh (issue #1548).
  skill_dirs=$(find "$REPO_ROOT" -path '*/.claude/worktrees/*' -prune -o \
    \( -path "*-plugin/skills/*/SKILL.md" -o -path "*-plugin/skills/*/skill.md" \) -print 2>/dev/null | sort)
fi

# --- per-skill metric + funnel-signal computation -----------------------------
# Echoes: <bash_blocks> <bash_commands> <phases> <context_patterns> <line_count>
#         <score> <ask> <data_pipes> <verb_hit> <ref_style>
compute_skill_signals() {
  local skill_file="$1"
  local skill_name; skill_name=$(basename "$(dirname "$skill_file")")
  local line_count bash_blocks bash_commands phases context_patterns score
  local ask data_pipes verb_hit ref_style frontmatter

  line_count=$(wc -l < "$skill_file" | tr -dc '0-9'); : "${line_count:=0}"
  # Shell-ish fenced blocks (bash/sh/shell/console), broader than ```bash alone —
  # the cleanest v1 candidates (code-dep-audit, github-actions-finops) used ```sh.
  bash_blocks=$(grep -cE '^```(bash|sh|shell|console)' "$skill_file" 2>/dev/null | tr -dc '0-9'); : "${bash_blocks:=0}"
  bash_commands=$(grep -cE "^\s*(git |npm |bun |cargo |pip |pytest|ruff |black |eslint|biome |kubectl |helm |docker |terraform |gh |find |grep |ls |cat |head |jq |yq )" "$skill_file" 2>/dev/null | tr -dc '0-9'); : "${bash_commands:=0}"
  phases=$(grep -cE "^###? Phase|^###? Step" "$skill_file" 2>/dev/null | tr -dc '0-9'); : "${phases:=0}"
  context_patterns=$(grep -cE "(git status|git diff|git log|gh pr|gh issue|git branch)" "$skill_file" 2>/dev/null | tr -dc '0-9'); : "${context_patterns:=0}"

  score=0
  [ "$bash_blocks" -ge 5 ] && score=$((score + bash_blocks))
  [ "$bash_commands" -ge 8 ] && score=$((score + bash_commands / 2))
  [ "$phases" -ge 3 ] && score=$((score + phases * 2))
  [ "$context_patterns" -ge 4 ] && score=$((score + context_patterns))
  [ "$line_count" -ge 200 ] && score=$((score + 3))

  # Funnel signals.
  ask=$(grep -cE 'AskUserQuestion|multiSelect' "$skill_file" 2>/dev/null | tr -dc '0-9'); : "${ask:=0}"
  data_pipes=$(grep -cE "$FUNNEL_PIPE_RE" "$skill_file" 2>/dev/null | tr -dc '0-9'); : "${data_pipes:=0}"
  # verb_hit scans the skill NAME only — a skill *named* *-audit/-validate/-check
  # is deterministic-intent and precise. (Scanning the description instead fires
  # on ~200 skills, because nearly every description prose contains "check",
  # "validate", "detect"; the name is the precise signal.)
  verb_hit=0
  printf '%s' "$skill_name" | grep -qiE "($FUNNEL_VERB_RE)" && verb_hit=1
  # ref_style scans the frontmatter description — awk, not head/sed (planning-shell
  # portability, ADR-0016 environment note).
  frontmatter=$(awk 'NR==1&&/^---/{f=1;next} f&&/^---/{exit} f{print}' "$skill_file" 2>/dev/null)
  ref_style=0
  printf '%s' "$frontmatter" | grep -qE "$FUNNEL_REF_RE" && ref_style=1

  echo "$bash_blocks $bash_commands $phases $context_patterns $line_count $score $ask $data_pipes $verb_hit $ref_style"
}

# --- funnel mode: bin every script-less skill, emit a KEY=VALUE rollup ---------
if [ "$FUNNEL_MODE" -eq 1 ]; then
  f_total=0; f_with_scripts=0; f_scriptless=0
  f_strong=0; f_weak=0
  f_skip_interactive=0; f_skip_reference=0; f_skip_noproc=0

  echo "=== DETERMINISTIC FUNNEL ==="
  for skill_file in $skill_dirs; do
    skill_dir=$(dirname "$skill_file")
    skill_name=$(basename "$skill_dir")
    plugin_name=$(echo "$skill_dir" | grep -oE "[^/]*-plugin/" | tail -1 | tr -d '/')
    f_total=$((f_total + 1))

    if [ -d "$skill_dir/scripts" ]; then
      f_with_scripts=$((f_with_scripts + 1))
      # Already optimized — ADR-0016 "already ships scripts -> audit-only" gate.
      echo "VERDICT	HAS_SCRIPTS	$plugin_name	$skill_name	score=-	signals=already-extracted	$skill_file"
      continue
    fi
    f_scriptless=$((f_scriptless + 1))

    read -r bash_blocks bash_commands phases context_patterns line_count score ask data_pipes verb_hit ref_style \
      < <(compute_skill_signals "$skill_file")

    # Precedence (first match wins):
    #   1. STRONG — high-signal procedure worth an LLM verify pass. Strong signals
    #      win over every skip: a candidate may carry a descoped AskUserQuestion
    #      step (every v1 candidate did), so an interactive step never disqualifies.
    #   2. WEAK — has a real procedure (>=3 shell blocks) but only a weak signal;
    #      ranked ABOVE the skips so a procedural-but-interactive skill is routed
    #      to the optional LLM classify pass, never silently skipped.
    #   3-5. SKIP bands — no extractable procedure (reference prose / interactive
    #      judgment / no shell blocks).
    strong_reason=""
    [ "$data_pipes" -ge 2 ] && strong_reason="pipes:$data_pipes"
    [ "$verb_hit" -eq 1 ] && strong_reason="${strong_reason:+$strong_reason,}verb-in-name"
    [ "$score" -ge "$FUNNEL_STRONG_SCORE" ] && strong_reason="${strong_reason:+$strong_reason,}score:$score"

    if [ -n "$strong_reason" ]; then
      verdict=LLM_STRONG; f_strong=$((f_strong + 1)); signals="$strong_reason"
    elif [ "$bash_blocks" -ge 3 ]; then
      verdict=LLM_WEAK; f_weak=$((f_weak + 1)); signals="bash_blocks:$bash_blocks,pipes:$data_pipes,ask:$ask"
    elif [ "$ref_style" -eq 1 ]; then
      verdict=SKIP_REFERENCE; f_skip_reference=$((f_skip_reference + 1)); signals="reference-desc"
    elif [ "$ask" -ge 1 ]; then
      verdict=SKIP_INTERACTIVE; f_skip_interactive=$((f_skip_interactive + 1)); signals="ask:$ask,bash_blocks:$bash_blocks"
    else
      verdict=SKIP_NOPROC; f_skip_noproc=$((f_skip_noproc + 1)); signals="bash_blocks:$bash_blocks"
    fi
    echo "VERDICT	$verdict	$plugin_name	$skill_name	score=$score	signals=$signals	$skill_file"
  done

  f_skip_total=$((f_skip_interactive + f_skip_reference + f_skip_noproc))
  f_residue=$((f_strong + f_weak))
  echo "TOTAL_SKILLS=$f_total"
  echo "WITH_SCRIPTS=$f_with_scripts"
  echo "SCRIPTLESS=$f_scriptless"
  echo "SKIP_INTERACTIVE=$f_skip_interactive"
  echo "SKIP_REFERENCE=$f_skip_reference"
  echo "SKIP_NOPROC=$f_skip_noproc"
  echo "SKIP_TOTAL=$f_skip_total"
  echo "LLM_STRONG=$f_strong"
  echo "LLM_WEAK=$f_weak"
  echo "LLM_RESIDUE=$f_residue"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=$f_residue"
  echo "=== END DETERMINISTIC FUNNEL ==="
  exit 0
fi

echo "=== SKILL SCRIPT ANALYSIS ==="
echo ""

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
    scripts=$(find "$skill_dir/scripts" -type f -exec basename {} \; 2>/dev/null | tr '\n' ', ')
    scripts=${scripts%,}
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
