#!/usr/bin/env bash
# Check Runtime State (~/.claude.json)
# Audits the harness runtime state file for stale entries:
#   - projects[] keys pointing at deleted directories
#   - githubRepoPaths[*] entries referencing deleted worktrees
#   - disabledMcpServers[] referencing servers no longer in mcpServers
#   - duplicate / non-canonical MCP naming (bare vs plugin:scope:name)
#
# Read-only audit. Does not write to ~/.claude.json. Prints suggested
# follow-up jq invocations the operator can run after closing other
# Claude Code sessions (the harness rewrites this file during sessions).
#
# Usage: bash check-runtime.sh --home-dir <path> --project-dir <path> [--verbose]

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

echo "=== RUNTIME STATE ==="

runtime_file="${home_dir}/.claude.json"
issue_count=0
check_status="OK"
issues_list=""

# Check jq availability (shared convention with sibling scripts)
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END RUNTIME STATE ==="
  exit 1
fi

# Check runtime file exists
if [ ! -f "$runtime_file" ]; then
  echo "RUNTIME_EXISTS=false"
  echo "RUNTIME_PATH=${runtime_file}"
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=missing_runtime MSG=~/.claude.json not found (no sessions recorded yet)"
  echo "=== END RUNTIME STATE ==="
  exit 0
fi

echo "RUNTIME_EXISTS=true"
echo "RUNTIME_PATH=${runtime_file}"

# Validate JSON syntax
json_error=$(jq empty "$runtime_file" 2>&1)
jq_rc=$?
if [ $jq_rc -ne 0 ]; then
  echo "RUNTIME_VALID=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=invalid_json FILE=${runtime_file} MSG=${json_error}"
  echo "=== END RUNTIME STATE ==="
  exit 1
fi
echo "RUNTIME_VALID=true"

# File size in bytes (informational; correlates with cruft accumulation)
runtime_size=$(wc -c <"$runtime_file" | tr -d ' ')
echo "RUNTIME_SIZE_BYTES=${runtime_size}"

# 1. Dead projects[] entries -------------------------------------------------
projects_total=0
projects_dead=0
dead_projects=""

if jq -e 'has("projects")' "$runtime_file" >/dev/null 2>&1; then
  projects_total=$(jq -r '.projects // {} | length' "$runtime_file" 2>/dev/null || echo "0")
  # Each key in .projects is an absolute directory path
  while IFS= read -r project_path; do
    [ -z "$project_path" ] && continue
    if [ ! -d "$project_path" ]; then
      projects_dead=$((projects_dead + 1))
      dead_projects="${dead_projects}${project_path}\n"
      if [ "$verbose_mode" = true ]; then
        issues_list="${issues_list}  - SEVERITY=WARN TYPE=dead_project PATH=${project_path}\n"
      fi
    fi
  done < <(jq -r '.projects // {} | keys[]' "$runtime_file" 2>/dev/null)
fi

echo "PROJECTS_TOTAL=${projects_total}"
echo "PROJECTS_DEAD=${projects_dead}"

if [ "$projects_dead" -gt 0 ]; then
  issue_count=$((issue_count + projects_dead))
  [ "$check_status" = "OK" ] && check_status="WARN"
  if [ "$verbose_mode" = false ]; then
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=dead_projects COUNT=${projects_dead} MSG=projects[] keys pointing at deleted directories (use --verbose to list)\n"
  fi
fi

# 2. Dead githubRepoPaths[*] entries ----------------------------------------
gh_paths_total=0
gh_paths_dead=0

if jq -e 'has("githubRepoPaths")' "$runtime_file" >/dev/null 2>&1; then
  # githubRepoPaths shape: { "<repo>": ["/path1", "/path2", ...], ... }
  # OR a flat array of paths. Handle both.
  gh_kind=$(jq -r '.githubRepoPaths | type' "$runtime_file" 2>/dev/null)
  case "$gh_kind" in
    object)
      gh_paths_total=$(jq -r '[.githubRepoPaths // {} | .[] | .[]?] | length' "$runtime_file" 2>/dev/null || echo "0")
      while IFS= read -r gh_path; do
        [ -z "$gh_path" ] && continue
        if [ ! -d "$gh_path" ]; then
          gh_paths_dead=$((gh_paths_dead + 1))
          if [ "$verbose_mode" = true ]; then
            issues_list="${issues_list}  - SEVERITY=WARN TYPE=dead_gh_path PATH=${gh_path}\n"
          fi
        fi
      done < <(jq -r '[.githubRepoPaths // {} | .[] | .[]?] | .[]' "$runtime_file" 2>/dev/null)
      ;;
    array)
      gh_paths_total=$(jq -r '.githubRepoPaths | length' "$runtime_file" 2>/dev/null || echo "0")
      while IFS= read -r gh_path; do
        [ -z "$gh_path" ] && continue
        if [ ! -d "$gh_path" ]; then
          gh_paths_dead=$((gh_paths_dead + 1))
          if [ "$verbose_mode" = true ]; then
            issues_list="${issues_list}  - SEVERITY=WARN TYPE=dead_gh_path PATH=${gh_path}\n"
          fi
        fi
      done < <(jq -r '.githubRepoPaths[]' "$runtime_file" 2>/dev/null)
      ;;
  esac
fi

echo "GH_PATHS_TOTAL=${gh_paths_total}"
echo "GH_PATHS_DEAD=${gh_paths_dead}"

if [ "$gh_paths_dead" -gt 0 ]; then
  issue_count=$((issue_count + gh_paths_dead))
  [ "$check_status" = "OK" ] && check_status="WARN"
  if [ "$verbose_mode" = false ]; then
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=dead_gh_paths COUNT=${gh_paths_dead} MSG=githubRepoPaths entries referencing deleted directories (use --verbose to list)\n"
  fi
fi

# 3. Orphaned disabledMcpServers --------------------------------------------
# Global mcpServers keys form the "live" set. Per-project disabledMcpServers
# entries that name a server not in the live set are orphans.
orphaned_disabled=0

if jq -e 'has("projects") and has("mcpServers")' "$runtime_file" >/dev/null 2>&1; then
  # Build space-separated list of live server names
  live_servers=$(jq -r '.mcpServers // {} | keys[]' "$runtime_file" 2>/dev/null | tr '\n' ' ')

  # Walk projects[]/disabledMcpServers[]
  while IFS=$'\t' read -r project_path disabled_name; do
    [ -z "$disabled_name" ] && continue
    # Membership test: is disabled_name in live_servers?
    case " ${live_servers} " in
      *" ${disabled_name} "*) ;;
      *)
        orphaned_disabled=$((orphaned_disabled + 1))
        if [ "$verbose_mode" = true ]; then
          issues_list="${issues_list}  - SEVERITY=WARN TYPE=orphan_disabled_mcp PROJECT=${project_path} SERVER=${disabled_name}\n"
        fi
        ;;
    esac
  done < <(jq -r '
    .projects // {}
    | to_entries[]
    | . as $p
    | (.value.disabledMcpServers // [])[]
    | [$p.key, .] | @tsv
  ' "$runtime_file" 2>/dev/null)
fi

echo "ORPHAN_DISABLED_MCP=${orphaned_disabled}"

if [ "$orphaned_disabled" -gt 0 ]; then
  issue_count=$((issue_count + orphaned_disabled))
  [ "$check_status" = "OK" ] && check_status="WARN"
  if [ "$verbose_mode" = false ]; then
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=orphan_disabled_mcp COUNT=${orphaned_disabled} MSG=disabledMcpServers refer to servers no longer in global mcpServers (use --verbose to list)\n"
  fi
fi

# 4. Duplicate / non-canonical MCP names ------------------------------------
# When both "foo" and "plugin:<scope>:foo" appear across mcpServers /
# disabledMcpServers, the bare form is a migration artifact.
duplicate_mcp=0

if jq -e 'has("mcpServers") or has("projects")' "$runtime_file" >/dev/null 2>&1; then
  # Collect every MCP name referenced anywhere, dedupe.
  all_names=$(jq -r '
    [
      (.mcpServers // {} | keys[]),
      (.projects // {} | .[] | (.mcpServers // {} | keys[])?),
      (.projects // {} | .[] | (.disabledMcpServers // [])[]?)
    ] | unique | .[]
  ' "$runtime_file" 2>/dev/null)

  # For every "plugin:<scope>:<name>", if the bare "<name>" also appears,
  # flag the bare form as a duplicate.
  while IFS= read -r mcp_name; do
    [ -z "$mcp_name" ] && continue
    case "$mcp_name" in
      plugin:*:*)
        bare="${mcp_name##*:}"
        if echo "$all_names" | grep -qxF "$bare"; then
          duplicate_mcp=$((duplicate_mcp + 1))
          if [ "$verbose_mode" = true ]; then
            issues_list="${issues_list}  - SEVERITY=WARN TYPE=duplicate_mcp BARE=${bare} NAMESPACED=${mcp_name}\n"
          fi
        fi
        ;;
    esac
  done <<< "$all_names"
fi

echo "DUPLICATE_MCP=${duplicate_mcp}"

if [ "$duplicate_mcp" -gt 0 ]; then
  issue_count=$((issue_count + duplicate_mcp))
  [ "$check_status" = "OK" ] && check_status="WARN"
  if [ "$verbose_mode" = false ]; then
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=duplicate_mcp COUNT=${duplicate_mcp} MSG=bare MCP names coexist with plugin:scope:name form (migration artifact; use --verbose to list)\n"
  fi
fi

# Suggested cleanup (read-only audit; the operator runs these manually) -----
if [ "$issue_count" -gt 0 ]; then
  echo "CLEANUP_SUGGESTED=true"
  echo "CLEANUP_NOTE=Close other Claude Code sessions before editing ~/.claude.json (the harness rewrites this file on session end). Suggested jq filters:"
  if [ "$projects_dead" -gt 0 ]; then
    echo "  CLEANUP_PROJECTS=jq 'reduce (.projects | keys[]) as \$k (.; if (\$k | test(\"^/\") and (\$k | @sh | \"test -d \" + . | @sh)) then . else del(.projects[\$k]) end)' ~/.claude.json  # preview first"
  fi
  if [ "$gh_paths_dead" -gt 0 ]; then
    echo "  CLEANUP_GH_PATHS=Run a shell loop that filters .githubRepoPaths through 'test -d' before writing back to a temp file"
  fi
  if [ "$orphaned_disabled" -gt 0 ]; then
    echo "  CLEANUP_DISABLED_MCP=jq '.projects |= map_values(.disabledMcpServers |= map(select(. as \$n | (input_filename | .mcpServers | has(\$n)))))' ~/.claude.json  # adapt to your shell"
  fi
else
  echo "CLEANUP_SUGGESTED=false"
fi

echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ]; then
  echo "ISSUES:"
  echo -e "$issues_list" | sed '/^$/d'
fi
echo "FIX_SUPPORTED=false"
echo "=== END RUNTIME STATE ==="
