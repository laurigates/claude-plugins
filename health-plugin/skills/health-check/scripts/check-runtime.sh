#!/usr/bin/env bash
# Check Runtime State (~/.claude.json)
# Audits the harness runtime state file for stale entries:
#   - projects[] keys pointing at deleted directories
#   - githubRepoPaths[*] entries referencing deleted worktrees
#   - disabledMcpServers[] referencing servers no longer in mcpServers
#   - duplicate / non-canonical MCP naming (bare vs plugin:scope:name)
#   - legacy per-project `history` arrays (prompt history now lives in
#     ~/.claude/history.jsonl; leftovers only inflate ~/.claude.json)
# Also measures ~/.claude/history.jsonl, which the cleanupPeriodDays sweep
# does NOT prune (outside the HIPAA configuration), and resolves the
# effective cleanupPeriodDays — an invalid value pauses the retention sweep.
#
# Read-only audit. Does not write to ~/.claude.json. Prints suggested
# follow-up jq invocations the operator can run after closing other
# Claude Code sessions (the harness rewrites this file during sessions).
#
# Usage: bash check-runtime.sh --home-dir <path> --project-dir <path>
#          [--history-warn-mb N] [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
verbose_mode=false
history_warn_mb=50

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --history-warn-mb) history_warn_mb="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"
[[ "$history_warn_mb" =~ ^[0-9]+$ ]] || history_warn_mb=50

# shellcheck disable=SC1091  # sibling lib; resolved relative to this script at runtime
source "$(dirname "${BASH_SOURCE[0]}")/lib/retention.sh"

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

# 5. Legacy per-project prompt history ---------------------------------------
# Older releases stored prompt history as projects[<path>].history arrays.
# Current releases append to ~/.claude/history.jsonl instead, so these arrays
# are dead weight. INFO only: dropping them is optional and loses nothing the
# harness still reads.
legacy_history_entries=$(jq -r '[.projects // {} | .[] | (.history // []) | length] | add // 0' "$runtime_file" 2>/dev/null || echo "0")
legacy_history_projects=$(jq -r '[.projects // {} | .[] | select((.history // []) | length > 0)] | length' "$runtime_file" 2>/dev/null || echo "0")
legacy_history_bytes=$(jq -c '[.projects // {} | .[] | (.history // [])]' "$runtime_file" 2>/dev/null | wc -c | tr -d ' ')
[ "$legacy_history_entries" -eq 0 ] && legacy_history_bytes=0

echo "LEGACY_PROJECT_HISTORY_ENTRIES=${legacy_history_entries}"
echo "LEGACY_PROJECT_HISTORY_PROJECTS=${legacy_history_projects}"
echo "LEGACY_PROJECT_HISTORY_BYTES=${legacy_history_bytes}"

info_list=""
if [ "$legacy_history_entries" -gt 0 ]; then
  info_list="${info_list}  - SEVERITY=INFO TYPE=legacy_project_history COUNT=${legacy_history_entries} BYTES=${legacy_history_bytes} MSG=projects[].history arrays predate ~/.claude/history.jsonl; safe to drop\n"
fi

# 6. Prompt history file (~/.claude/history.jsonl) ---------------------------
# Not covered by the cleanupPeriodDays sweep (except under the HIPAA
# configuration), so it grows until deleted or filtered by `claude purge`.
history_file="${home_dir}/.claude/history.jsonl"
history_dead_entries=0
history_dead_projects=""
if [ -f "$history_file" ]; then
  history_bytes=$(wc -c <"$history_file" | tr -d ' ')
  history_entries=$(grep -c "" "$history_file" 2>/dev/null || true)
  history_malformed=$(jq -R -r 'fromjson? // "MALFORMED" | if type == "string" then . else empty end' "$history_file" 2>/dev/null | grep -c '^MALFORMED$' || true)
  echo "HISTORY_JSONL_EXISTS=true"
  echo "HISTORY_JSONL_BYTES=${history_bytes}"
  echo "HISTORY_JSONL_ENTRIES=${history_entries}"
  echo "HISTORY_JSONL_MALFORMED=${history_malformed:-0}"

  # Entries per project path; a path whose directory is gone is purgeable.
  while IFS=$'\t' read -r hist_count hist_project; do
    [ -z "$hist_project" ] && continue
    if [ ! -d "$hist_project" ]; then
      history_dead_entries=$((history_dead_entries + hist_count))
      history_dead_projects="${history_dead_projects}${hist_project}\n"
      if [ "$verbose_mode" = true ]; then
        info_list="${info_list}  - SEVERITY=INFO TYPE=history_dead_project PATH=${hist_project} COUNT=${hist_count}\n"
      fi
    fi
  done < <(jq -R -r 'fromjson? | objects | .project // empty | strings' "$history_file" 2>/dev/null \
             | sort | uniq -c | awk '{c=$1; sub(/^ *[0-9]+ /, ""); print c "\t" $0}')
  echo "HISTORY_JSONL_DEAD_PROJECT_ENTRIES=${history_dead_entries}"

  if [ "$history_dead_entries" -gt 0 ] && [ "$verbose_mode" = false ]; then
    info_list="${info_list}  - SEVERITY=INFO TYPE=history_dead_projects COUNT=${history_dead_entries} MSG=history.jsonl prompts recorded for deleted project directories (use --verbose to list)\n"
  fi
  if [ "${history_malformed:-0}" -gt 0 ]; then
    info_list="${info_list}  - SEVERITY=INFO TYPE=history_malformed COUNT=${history_malformed} MSG=history.jsonl lines that are not valid JSON (skipped by the harness)\n"
  fi
  if [ "$history_bytes" -gt $((history_warn_mb * 1024 * 1024)) ]; then
    issue_count=$((issue_count + 1))
    [ "$check_status" = "OK" ] && check_status="WARN"
    issues_list="${issues_list}  - SEVERITY=WARN TYPE=history_large BYTES=${history_bytes} THRESHOLD_MB=${history_warn_mb} MSG=history.jsonl exceeds threshold; cleanupPeriodDays does not prune it\n"
  fi
else
  echo "HISTORY_JSONL_EXISTS=false"
fi
echo "HISTORY_JSONL_SWEPT=false"

# 7. Retention setting (cleanupPeriodDays) -----------------------------------
resolve_cleanup_period "$home_dir" "$project_dir"
echo "CLEANUP_PERIOD_DAYS=${CLEANUP_PERIOD_DAYS}"
echo "CLEANUP_PERIOD_SOURCE=${CLEANUP_PERIOD_SOURCE}"
echo "CLEANUP_PERIOD_VALID=${CLEANUP_PERIOD_VALID}"
if [ "$CLEANUP_PERIOD_VALID" = false ]; then
  issue_count=$((issue_count + 1))
  check_status="ERROR"
  issues_list="${issues_list}  - SEVERITY=ERROR TYPE=invalid_cleanup_period SOURCE=${CLEANUP_PERIOD_SOURCE} VALUE=${CLEANUP_PERIOD_RAW} MSG=cleanupPeriodDays must be a whole number >= 1; an invalid explicit value pauses the retention sweep (use 3650 for long retention)\n"
fi

# Suggested cleanup (read-only audit; the operator runs these manually) -----
if [ "$issue_count" -gt 0 ] || [ "$legacy_history_entries" -gt 0 ] || [ "$history_dead_entries" -gt 0 ]; then
  echo "CLEANUP_SUGGESTED=true"
  echo "CLEANUP_NOTE=Close other Claude Code sessions before editing ~/.claude.json (the harness rewrites this file on session end). Suggested jq filters:"
  if [ "$projects_dead" -gt 0 ]; then
    echo "  CLEANUP_PROJECTS=claude purge <dead-path> --dry-run  # per dead project (use --verbose to list); also removes its transcripts and history.jsonl lines. Before v2.1.288: claude project purge"
  fi
  if [ "$gh_paths_dead" -gt 0 ]; then
    echo "  CLEANUP_GH_PATHS=Run a shell loop that filters .githubRepoPaths through 'test -d' before writing back to a temp file"
  fi
  if [ "$orphaned_disabled" -gt 0 ]; then
    echo "  CLEANUP_DISABLED_MCP=jq '.projects |= map_values(.disabledMcpServers |= map(select(. as \$n | (input_filename | .mcpServers | has(\$n)))))' ~/.claude.json  # adapt to your shell"
  fi
  if [ "$legacy_history_entries" -gt 0 ]; then
    echo "  CLEANUP_LEGACY_HISTORY=jq '.projects |= map_values(del(.history))' ~/.claude.json  # or: python3 prune-claude-config.py --drop-legacy-history"
  fi
  if [ "$history_dead_entries" -gt 0 ]; then
    echo "  CLEANUP_HISTORY_JSONL=claude purge <dead-path> --dry-run  # filters that project's lines out of history.jsonl"
  fi
else
  echo "CLEANUP_SUGGESTED=false"
fi

echo "STATUS=${check_status}"
echo "ISSUE_COUNT=${issue_count}"
if [ -n "$issues_list" ] || [ -n "$info_list" ]; then
  echo "ISSUES:"
  echo -e "${issues_list}${info_list}" | sed '/^$/d'
fi
echo "FIX_SUPPORTED=false"
echo "=== END RUNTIME STATE ==="
[ "$check_status" = "ERROR" ] && exit 1
exit 0
