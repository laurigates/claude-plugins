#!/usr/bin/env bash
# Check MCP Server Configuration
# Validates MCP servers from .mcp.json and settings files.
# Usage: bash check-mcp.sh --home-dir <path> --project-dir <path> [--verbose]

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

echo "=== MCP SERVERS ==="

issue_count=0
check_status="OK"
issues_list=""
server_count=0
# Newline-separated "<server name>\t<nearest .mcp.json>" records, used to count
# each unique server once and to name the file that shadows an outer duplicate.
seen_servers=""

# Check jq availability
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END MCP SERVERS ==="
  exit 1
fi

# MCP configuration sources.
#
# Claude Code also loads .mcp.json from directories ABOVE the project (observed
# behaviour, undocumented upstream — issue #2666), so a repo inside a workspace
# whose servers live in the workspace root used to report SERVER_COUNT=0 /
# STATUS=N_A. Walk from --project-dir upward, including every ancestor's
# .mcp.json, and stop after --home-dir or the filesystem root. The list is
# NEAREST-FIRST so a nearer definition of a server name shadows an outer one,
# and every server is reported with the file it came from (file=) so the output
# stays correct and auditable under either upstream behaviour.
resolve_dir() {
  local candidate="$1"
  (cd "$candidate" 2>/dev/null && pwd -P) || printf '%s' "$candidate"
}

home_resolved="$(resolve_dir "$home_dir")"
project_resolved="$(resolve_dir "$project_dir")"

mcp_sources=()
seen_sources=""

add_mcp_source() {
  local candidate="$1"
  case "${seen_sources}" in
    *"|${candidate}|"*) return 0 ;;
  esac
  seen_sources="${seen_sources}|${candidate}|"
  mcp_sources+=("$candidate")
}

walk_dir="$project_resolved"
walk_depth=0
while [ "$walk_depth" -lt 64 ]; do
  add_mcp_source "${walk_dir}/.mcp.json"
  walk_depth=$((walk_depth + 1))
  [ "$walk_dir" = "$home_resolved" ] && break
  [ "$walk_dir" = "/" ] && break
  parent_dir="$(dirname "$walk_dir")"
  [ "$parent_dir" = "$walk_dir" ] && break
  walk_dir="$parent_dir"
done

# --home-dir is not always an ancestor of --project-dir; keep the home-level
# source covered either way (de-duplicated when the walk already reached it).
add_mcp_source "${home_resolved}/.mcp.json"

echo "MCP_SOURCE_COUNT=${#mcp_sources[@]}"
echo "MCP_SOURCES:"
for mcp_file in "${mcp_sources[@]}"; do
  if [ -f "$mcp_file" ]; then
    echo "  - FILE=${mcp_file} EXISTS=true"

    # Validate JSON
    if ! json_error=$(jq empty "$mcp_file" 2>&1); then
      echo "    VALID=false ERROR=${json_error}"
      issues_list="${issues_list}  - SEVERITY=ERROR TYPE=invalid_json FILE=${mcp_file} MSG=${json_error}\n"
      issue_count=$((issue_count + 1))
      check_status="ERROR"
      continue
    fi

    # List servers
    server_keys=$(jq -r '.mcpServers // {} | keys[]' "$mcp_file" 2>/dev/null)
    while IFS= read -r server_name; do
      [ -z "$server_name" ] && continue

      # The same server name may appear at several levels of the walk. Sources
      # are nearest-first, so the first sighting wins: count it once, attribute
      # it to the nearest file, and report the outer copy as shadowed rather
      # than silently double-counting it.
      shadowed_by="$(printf '%s' "$seen_servers" \
        | awk -F '\t' -v want="$server_name" '$1 == want { print $2; exit }')"
      if [ -n "$shadowed_by" ]; then
        echo "  SERVER_SHADOWED: name=${server_name} file=${mcp_file} shadowed_by=${shadowed_by}"
        continue
      fi
      seen_servers="${seen_servers}${server_name}"$'\t'"${mcp_file}"$'\n'
      server_count=$((server_count + 1))

      server_command=$(jq -r ".mcpServers[\"${server_name}\"].command // \"\"" "$mcp_file" 2>/dev/null)
      server_args=$(jq -r ".mcpServers[\"${server_name}\"].args // [] | join(\" \")" "$mcp_file" 2>/dev/null)

      if [ "$verbose_mode" = true ]; then
        echo "  SERVER: name=${server_name} file=${mcp_file} command=${server_command} args=${server_args}"
      else
        echo "  SERVER: name=${server_name} file=${mcp_file}"
      fi

      # Validate command exists
      if [ -n "$server_command" ]; then
        if ! command -v "$server_command" >/dev/null 2>&1; then
          issues_list="${issues_list}  - SEVERITY=WARN TYPE=missing_command SERVER=${server_name} COMMAND=${server_command} FILE=${mcp_file}\n"
          issue_count=$((issue_count + 1))
          [ "$check_status" = "OK" ] && check_status="WARN"
        fi
      fi

      # Check for required environment variables
      env_keys=$(jq -r ".mcpServers[\"${server_name}\"].env // {} | keys[]" "$mcp_file" 2>/dev/null)
      while IFS= read -r env_key; do
        [ -z "$env_key" ] && continue
        env_value=$(jq -r ".mcpServers[\"${server_name}\"].env[\"${env_key}\"]" "$mcp_file" 2>/dev/null)
        # Check if env var is empty or references an unset variable
        if [ -z "$env_value" ] || [ "$env_value" = "null" ]; then
          if [ -z "${!env_key:-}" ]; then
            issues_list="${issues_list}  - SEVERITY=WARN TYPE=missing_env SERVER=${server_name} VAR=${env_key} FILE=${mcp_file}\n"
            issue_count=$((issue_count + 1))
            [ "$check_status" = "OK" ] && check_status="WARN"
          fi
        fi
      done <<< "$env_keys"
    done <<< "$server_keys"
  else
    echo "  - FILE=${mcp_file} EXISTS=false"
  fi
done

# Check settings files for enabledMcpjsonServers
settings_files=(
  "${home_dir}/.claude/settings.json"
  "${project_dir}/.claude/settings.json"
)

for settings_file in "${settings_files[@]}"; do
  if [ -f "$settings_file" ]; then
    mcp_enabled=$(jq -r '.enabledMcpjsonServers // {} | length' "$settings_file" 2>/dev/null || echo "0")
    if [ "$mcp_enabled" -gt 0 ]; then
      echo "ENABLED_MCP_SERVERS_IN=$(basename "$(dirname "$settings_file")")/$(basename "$settings_file") COUNT=${mcp_enabled}"
      if [ "$verbose_mode" = true ]; then
        jq -r '.enabledMcpjsonServers // {} | to_entries[] | "  ENABLED: \(.key)=\(.value)"' "$settings_file" 2>/dev/null
      fi
    fi
  fi
done

if [ "$server_count" -eq 0 ]; then
  echo "MCP_CONFIGURED=false"
  check_status="N_A"
else
  echo "MCP_CONFIGURED=true"
fi

echo "SERVER_COUNT=${server_count}"
echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "=== END MCP SERVERS ==="
