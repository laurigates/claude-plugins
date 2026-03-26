#!/usr/bin/env bash
# Check Hooks Configuration
# Validates hook commands and timeouts from Claude Code settings files.
# Usage: bash check-hooks.sh --home-dir <path> --project-dir <path> [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"

echo "=== HOOKS CONFIGURATION ==="

issue_count=0
check_status="OK"
issues_list=""
total_hooks=0

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END HOOKS CONFIGURATION ==="
  exit 1
fi

# Settings files that may contain hooks
settings_files=(
  "${home_dir}/.claude/settings.json"
  "${project_dir}/.claude/settings.json"
  "${home_dir}/.claude/settings.local.json"
  "${project_dir}/.claude/settings.local.json"
)

for settings_file in "${settings_files[@]}"; do
  if [ ! -f "$settings_file" ]; then
    continue
  fi

  # Check if hooks key exists
  has_hooks=$(jq 'has("hooks")' "$settings_file" 2>/dev/null || echo "false")
  if [ "$has_hooks" != "true" ]; then
    continue
  fi

  # Get hook event names
  hook_events=$(jq -r '.hooks | keys[]' "$settings_file" 2>/dev/null)

  while IFS= read -r event_name; do
    [ -z "$event_name" ] && continue

    # Get hooks array for this event
    hook_count=$(jq -r ".hooks[\"${event_name}\"] | length" "$settings_file" 2>/dev/null || echo "0")

    for ((i=0; i<hook_count; i++)); do
      # Get hook entries for this event item
      entry_hooks=$(jq -r ".hooks[\"${event_name}\"][$i].hooks | length" "$settings_file" 2>/dev/null || echo "0")

      for ((j=0; j<entry_hooks; j++)); do
        total_hooks=$((total_hooks + 1))

        hook_type=$(jq -r ".hooks[\"${event_name}\"][$i].hooks[$j].type // \"unknown\"" "$settings_file" 2>/dev/null)
        hook_command=$(jq -r ".hooks[\"${event_name}\"][$i].hooks[$j].command // \"\"" "$settings_file" 2>/dev/null)
        hook_timeout=$(jq -r ".hooks[\"${event_name}\"][$i].hooks[$j].timeout // \"default\"" "$settings_file" 2>/dev/null)
        hook_matcher=$(jq -r ".hooks[\"${event_name}\"][$i].matcher // \"*\"" "$settings_file" 2>/dev/null)

        if [ "$verbose_mode" = true ]; then
          echo "HOOK: event=${event_name} matcher=${hook_matcher} type=${hook_type} timeout=${hook_timeout} file=${settings_file}"
          [ -n "$hook_command" ] && echo "  COMMAND=${hook_command}"
        fi

        # Validate command exists (for command-type hooks)
        if [ "$hook_type" = "command" ] && [ -n "$hook_command" ]; then
          # Extract the base tool from the command (first word)
          base_tool=$(echo "$hook_command" | awk '{print $1}' | sed 's/"//g')

          if [ "$base_tool" != "bash" ] && ! command -v "$base_tool" >/dev/null 2>&1; then
            # Check if it's a file path
            if [ ! -f "$base_tool" ]; then
              issues_list="${issues_list}  - SEVERITY=WARN TYPE=missing_command EVENT=${event_name} COMMAND=${base_tool} FILE=${settings_file}\n"
              issue_count=$((issue_count + 1))
              [ "$check_status" = "OK" ] && check_status="WARN"
            fi
          fi
        fi

        # Flag high timeouts (over 60 seconds)
        if [ "$hook_timeout" != "default" ] && [ "$hook_timeout" != "null" ]; then
          timeout_ms="${hook_timeout}"
          if [ "$timeout_ms" -gt 60000 ] 2>/dev/null; then
            issues_list="${issues_list}  - SEVERITY=WARN TYPE=high_timeout EVENT=${event_name} TIMEOUT=${timeout_ms}ms FILE=${settings_file}\n"
            issue_count=$((issue_count + 1))
            [ "$check_status" = "OK" ] && check_status="WARN"
          fi
        fi
      done
    done
  done <<< "$hook_events"
done

if [ "$total_hooks" -eq 0 ]; then
  echo "HOOKS_CONFIGURED=false"
  check_status="N_A"
else
  echo "HOOKS_CONFIGURED=true"
fi

echo "HOOK_COUNT=${total_hooks}"
echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "=== END HOOKS CONFIGURATION ==="
