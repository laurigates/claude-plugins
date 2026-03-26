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

# MCP configuration sources
mcp_sources=(
  "${home_dir}/.mcp.json"
  "${project_dir}/.mcp.json"
)

echo "MCP_SOURCES:"
for mcp_file in "${mcp_sources[@]}"; do
  if [ -f "$mcp_file" ]; then
    echo "  - FILE=${mcp_file} EXISTS=true"

    # Validate JSON
    json_error=$(jq empty "$mcp_file" 2>&1)
    if [ $? -ne 0 ]; then
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
      server_count=$((server_count + 1))

      server_command=$(jq -r ".mcpServers[\"${server_name}\"].command // \"\"" "$mcp_file" 2>/dev/null)
      server_args=$(jq -r ".mcpServers[\"${server_name}\"].args // [] | join(\" \")" "$mcp_file" 2>/dev/null)

      if [ "$verbose_mode" = true ]; then
        echo "  SERVER: name=${server_name} command=${server_command} args=${server_args}"
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
