#!/usr/bin/env bash
# Inspect a skill's eval setup: check for SKILL.md and evals.json,
# count eval cases, and optionally pretty-print evals.json.
#
# Usage:
#   inspect_eval.sh --plugin <plugin-name> --skill <skill-name> [--print-evals]
#   inspect_eval.sh --plugin-dir <path>  # list all skills in plugin
#
# Output: KEY=value lines + optional JSON dump under === EVALS === header.

set -uo pipefail

plugin_name=""
skill_name=""
plugin_dir=""
print_evals=false

while [ $# -gt 0 ]; do
  case "$1" in
    --plugin) plugin_name="$2"; shift 2 ;;
    --skill) skill_name="$2"; shift 2 ;;
    --plugin-dir) plugin_dir="$2"; shift 2 ;;
    --print-evals) print_evals=true; shift ;;
    *) shift ;;
  esac
done

echo "=== INSPECT EVAL ==="

# Mode 1: list all skills in a plugin
if [ -n "$plugin_dir" ]; then
  if [ ! -d "$plugin_dir/skills" ]; then
    echo "SKILLS_DIR_EXISTS=false"
    echo "STATUS=ERROR"
    exit 1
  fi
  echo "SKILLS_DIR_EXISTS=true"

  skill_count=$(find "$plugin_dir/skills" -maxdepth 3 -name "SKILL.md" | wc -l | tr -d ' ')
  evals_count=$(find "$plugin_dir/skills" -maxdepth 3 -name "evals.json" | wc -l | tr -d ' ')

  echo "SKILL_COUNT=$skill_count"
  echo "EVALS_COUNT=$evals_count"

  echo "=== SKILLS ==="
  find "$plugin_dir/skills" -maxdepth 3 -name "SKILL.md" -print | sort
  echo "=== EVALS ==="
  find "$plugin_dir/skills" -maxdepth 3 -name "evals.json" -print | sort
  exit 0
fi

# Mode 2: inspect one specific skill
if [ -z "$plugin_name" ] || [ -z "$skill_name" ]; then
  echo "ERROR: provide --plugin and --skill, or --plugin-dir" >&2
  exit 1
fi

skill_md="$plugin_name/skills/$skill_name/SKILL.md"
evals_json="$plugin_name/skills/$skill_name/evals.json"

skill_md_exists=false
evals_json_exists=false
num_cases=0

if [ -f "$skill_md" ]; then
  skill_md_exists=true
fi

if [ -f "$evals_json" ]; then
  evals_json_exists=true
  num_cases=$(jq '.cases | length' "$evals_json" 2>/dev/null || echo 0)
fi

echo "SKILL_MD=$skill_md"
echo "SKILL_MD_EXISTS=$skill_md_exists"
echo "EVALS_JSON=$evals_json"
echo "EVALS_JSON_EXISTS=$evals_json_exists"
echo "NUM_CASES=$num_cases"

if [ "$print_evals" = true ] && [ "$evals_json_exists" = true ]; then
  echo "=== EVALS ==="
  jq '.' "$evals_json"
fi
