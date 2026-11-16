#!/usr/bin/env bash
# Workflow Capture Survey — read-only collector for session-workflow-capture.
#
# Two modes:
#   session (default)  Lists the Claude Code Workflow-tool runs of one session:
#                      the scripts the harness persisted under
#                      <projects>/<slug>/<session-id>/workflows/scripts/, each
#                      run's agent counts from its journal.jsonl, and whether a
#                      script matches a saved (.claude/workflows, ~/.claude/workflows)
#                      or plugin-bundled (*/skills/*/workflows/*.js) workflow.
#   --usage            Counts Workflow-tool calls across recent session
#                      transcripts: inline script vs scriptPath vs a saved or
#                      plugin workflow invoked by name, and which names ran.
#                      Run it on the machine that holds the session history.
#
# READ-ONLY by contract. The script extracts and counts; whether a workflow is
# a reusable pattern, and where an issue about it belongs, stays with the
# invoking skill (.claude/rules/offload-to-deterministic-substrate.md).
#
# Emits KEY=VALUE sections (.claude/rules/structured-script-output.md) and is
# exit-0 on empty (.claude/rules/parallel-safe-queries.md). A missing projects
# dir or session yields TRANSCRIPT_AVAILABLE=false + STATUS=SKIP, the same
# degradation distill-survey.sh uses, so the skill falls back to reading the
# conversation.
#
# Usage:
#   bash workflow-capture-survey.sh --session-id <id> [--project-dir <path>]
#       [--home-dir <path>] [--summary]
#   bash workflow-capture-survey.sh --usage [--window-sessions N]
#       [--all-projects] [--project-dir <path>] [--home-dir <path>]
#
# On-disk layout read (Claude Code 2.1.325):
#   <projects>/<slug>/<session-id>.jsonl                      main transcript
#   <projects>/<slug>/<session-id>/workflows/scripts/<slug>-<runId>.js
#   <projects>/<slug>/<session-id>/subagents/workflows/<runId>/journal.jsonl
#     journal lines: {"type":"started",...} per agent spawned,
#                    {"type":"result",...}  per agent that returned
#   Workflow tool_use input keys: script | scriptPath | name, resumeFromRunId, args
#   Workflow toolUseResult keys:  runId, scriptPath, workflowName, transcriptDir,
#     status (the launch status, e.g. async_launched, not the run's outcome)
set -uo pipefail

project_dir=""
home_dir=""
session_id=""
mode="session"
summary_mode=false
window_sessions=50
all_projects=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="${2:-}"; shift 2 ;;
    --home-dir) home_dir="${2:-}"; shift 2 ;;
    --session-id) session_id="${2:-}"; shift 2 ;;
    --usage) mode="usage"; shift ;;
    --summary) summary_mode=true; shift ;;
    --window-sessions) window_sessions="${2:-50}"; shift 2 ;;
    --all-projects) all_projects=true; shift ;;
    *) shift ;;
  esac
done

: "${project_dir:=$(pwd)}"
: "${home_dir:=$HOME}"
case "$window_sessions" in ''|*[!0-9]*) window_sessions=50 ;; esac

# Test seams: override where transcripts, the plugin cache and the plugin
# install registry live.
projects_dir="${WORKFLOW_CAPTURE_PROJECTS_DIR:-${home_dir}/.claude/projects}"
plugin_cache="${WORKFLOW_CAPTURE_PLUGIN_CACHE:-${home_dir}/.claude/plugins/cache}"
plugin_registry="${WORKFLOW_CAPTURE_PLUGIN_REGISTRY:-${home_dir}/.claude/plugins/installed_plugins.json}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_KNOWN=60
MAX_RUNS=40
MAX_NAMES=25

have() { command -v "$1" >/dev/null 2>&1; }

file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

file_hash() {
  if have sha256sum; then sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  elif have shasum; then shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
  else cksum "$1" 2>/dev/null | cut -d' ' -f1
  fi
}

# Single-line value: no newlines, no `=`-ambiguity issues for KEY=VALUE readers.
one_line() { tr '\n\r\t' '   ' <<<"$1" | sed 's/[[:space:]]\{2,\}/ /g; s/^ //; s/ $//'; }

# meta.<field> from the `export const meta = {...}` literal. The harness names
# a workflow by meta.name, never by its filename. Single and double quotes are
# tried separately so an apostrophe inside a double-quoted value survives.
meta_field() {
  local wf_file="$1" field="$2" blk hit
  # Joined onto one line: a value often sits on the line after its key.
  blk=$(sed -n '/export[[:space:]]\{1,\}const[[:space:]]\{1,\}meta/,/^}/p' "$wf_file" 2>/dev/null | tr '\n' ' ')
  [ -n "$blk" ] || return 0
  hit=$(grep -oE "(^|[^A-Za-z0-9_])${field}[[:space:]]*:[[:space:]]*'[^']*'" <<<"$blk")
  if [ -z "$hit" ]; then
    hit=$(grep -oE "(^|[^A-Za-z0-9_])${field}[[:space:]]*:[[:space:]]*\"[^\"]*\"" <<<"$blk")
  fi
  hit=${hit%%$'\n'*}
  [ -n "$hit" ] || return 0
  hit=${hit#*:}
  hit=$(sed -E "s/^[[:space:]]*['\"]//; s/['\"]$//" <<<"$hit")
  # '|' delimits the KNOWN_n and RUN_n_MATCH values, so it never survives here.
  hit=${hit//|//}
  one_line "$hit"
}

# The host of a git remote or repository URL, lowercased.
url_host() {
  sed -E 's#^git\+##; s#^[a-z+]+://##; s#^[^@/]*@##; s#[:/].*$##' <<<"$1" | tr '[:upper:]' '[:lower:]'
}

# owner/name of a GitHub remote or repository URL; empty for any other host,
# because `gh issue create -R owner/name` resolves against GitHub and would file
# into whatever repo holds that name there (a GitLab subgroup path would also
# be cut to the wrong repo). GH_HOST names a GitHub Enterprise host.
repo_slug() {
  local u="$1" host
  [ -n "$u" ] || return 0
  host=$(url_host "$u")
  case "$host" in github.com|"$(tr '[:upper:]' '[:lower:]' <<<"${GH_HOST:-github.com}")") ;; *) return 0 ;; esac
  u=$(sed -E 's#^git\+##; s#^[a-z+]+://[^/]+/##; s#^[^@/]*@[^:]+:##; s#\.git$##; s#/$##' <<<"$u")
  case "$u" in */*) printf '%s' "$(cut -d/ -f1 <<<"$u")/$(cut -d/ -f2 <<<"$u")" ;; esac
}

# The repository a plugin.json names (a string, or an object with .url).
plugin_repo() {
  local manifest="$1" raw=""
  [ -f "$manifest" ] || return 0
  if have jq; then
    raw=$(jq -r 'if (.repository | type) == "object" then (.repository.url // "") else (.repository // "") end' "$manifest" 2>/dev/null)
  else
    raw=$(grep -oE '"repository"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" | sed -E 's/.*"([^"]*)"$/\1/')
  fi
  [ -n "$raw" ] && repo_slug "$raw"
}

# Where an issue about a known workflow belongs: the repository of the plugin
# that ships it, the calling repo for a project-saved one, nothing for user scope.
owning_repo() { # scope path
  case "$1" in
    project) printf '%s' "$calling_repo" ;;
    user) ;;
    bundled) plugin_repo "${2%%/skills/*}/.claude-plugin/plugin.json" ;;
    plugin) plugin_repo "${2%/workflows/*}/.claude-plugin/plugin.json" ;;
  esac
}

count_calls() { # file fn — call sites of fn( not preceded by an identifier char or '.'
  local n
  n=$(grep -oE "(^|[^A-Za-z0-9_.])$2\(" "$1" 2>/dev/null | wc -l)
  echo $((n + 0))
}

calling_repo="" calling_remote_url=""
if have git; then
  calling_remote_url=$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)
  if [ -z "$calling_remote_url" ]; then
    remotes=$(git -C "$project_dir" remote 2>/dev/null || true)
    first_remote=${remotes%%$'\n'*}
    [ -n "$first_remote" ] && calling_remote_url=$(git -C "$project_dir" remote get-url "$first_remote" 2>/dev/null || true)
  fi
  calling_repo=$(repo_slug "$calling_remote_url")
fi
# The tracker for generic captures: the repository session-plugin itself ships
# from, read from its own manifest so a fork files into the fork.
plugins_repo_default=$(plugin_repo "${script_dir}/../.claude-plugin/plugin.json")

# workflow_capture_repo: in plugin settings frontmatter overrides the default.
settings_repo() {
  [ -f "$1" ] || return 0
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
       /^workflow_capture_repo:/ { s = $0; sub(/^workflow_capture_repo:[[:space:]]*/, "", s); print s; exit }' "$1" \
    | sed -E "s/^[\"']//; s/[\"'][[:space:]]*$//; s/[[:space:]]+$//"
}
plugins_repo="" plugins_repo_source=""
for src in project:"$project_dir/.claude/session-plugin.local.md" user:"$home_dir/.claude/session-plugin.local.md"; do
  plugins_repo=$(settings_repo "${src#*:}")
  if [ -n "$plugins_repo" ]; then plugins_repo_source="settings-${src%%:*}"; break; fi
done
if [ -z "$plugins_repo" ] && [ -n "$plugins_repo_default" ]; then
  plugins_repo="$plugins_repo_default"; plugins_repo_source="manifest"
fi

emit_repos() {
  echo "CALLING_REPO=${calling_repo:-unknown}"
  echo "CALLING_REPO_HOST=$([ -n "$calling_remote_url" ] && url_host "$calling_remote_url" || echo none)"
  echo "PLUGINS_REPO=${plugins_repo:-unknown}"
  echo "PLUGINS_REPO_SOURCE=${plugins_repo_source:-none}"
}

# ---------------------------------------------------------------------------
# Known workflows: saved (project/user), plugin-registered and plugin-bundled.
# Each row: scope<TAB>name<TAB>hash<TAB>path
# ---------------------------------------------------------------------------
known_rows=""
add_known() { # scope file
  local nm stem
  nm=$(meta_field "$2" name)
  if [ -z "$nm" ]; then
    # No meta.name: the harness would skip this file as saved or plugin
    # workflow, but a bundled template without meta can still be adapted, so
    # keep it under its filename stem for byte and name matching.
    stem=$(basename "$2" .js); nm="${stem%.workflow}"
  fi
  known_rows+="$1"$'\t'"$nm"$'\t'"$(file_hash "$2")"$'\t'"$2"$'\n'
}

# The plugin directories Claude Code loads, one per installed plugin. The cache
# keeps every version ever installed, so scanning it whole counted each
# template once per old version (226 rows for about 20 templates on a
# long-lived machine). installed_plugins.json names each plugin's installPath
# per scope; a project entry for this project wins over the user entry.
# Without a readable registry, the newest cached version of each plugin
# stands in.
plugin_roots() {
  local out="" d newest
  if [ -f "$plugin_registry" ] && have jq; then
    out=$(jq -r --arg pd "$project_dir" '
      (.plugins // {}) | to_entries[] | .value
      | ( [ .[]? | select((.scope == "project" or .scope == "local")
                          and (.projectPath // "") != ""
                          and ($pd == .projectPath or ($pd | startswith(.projectPath + "/")))) ][0].installPath
          // [ .[]? | select(.scope == "user") ][0].installPath
          // empty )' "$plugin_registry" 2>/dev/null | sort -u)
  fi
  if [ -n "$out" ]; then printf '%s\n' "$out"; return 0; fi
  [ -d "$plugin_cache" ] || return 0
  # Cache layout: <cache>/<marketplace>/<plugin>/<version>/
  for d in "$plugin_cache"/*/*/; do
    [ -d "$d" ] || continue
    newest=$(find "$d" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort -V | tail -n 1)
    [ -n "$newest" ] && printf '%s\n' "${d%/}/$newest"
  done
}

collect_known() {
  local f top="" root
  for f in "$project_dir"/.claude/workflows/*.js; do [ -f "$f" ] && add_known project "$f"; done
  if have git; then top=$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true); fi
  if [ -n "$top" ] && [ "$top" != "$project_dir" ]; then
    for f in "$top"/.claude/workflows/*.js; do [ -f "$f" ] && add_known project "$f"; done
  fi
  for f in "$home_dir"/.claude/workflows/*.js; do [ -f "$f" ] && add_known user "$f"; done
  while IFS= read -r root; do
    if [ -z "$root" ] || [ ! -d "$root" ]; then continue; fi
    for f in "$root"/workflows/*.js; do [ -f "$f" ] && add_known plugin "$f"; done
    while IFS= read -r f; do [ -n "$f" ] && add_known bundled "$f"; done < <(
      find "$root/skills" -mindepth 3 -maxdepth 3 -type f -name '*.js' -path '*/workflows/*' 2>/dev/null | sort)
  done < <(plugin_roots)
  # A plugin source checkout as the project (a marketplace repo).
  while IFS= read -r f; do [ -n "$f" ] && add_known bundled "$f"; done < <(
    find "$project_dir" -maxdepth 5 -type f -name '*.workflow.js' -path '*/skills/*/workflows/*' \
      -not -path '*/.claude/worktrees/*' -not -path '*/node_modules/*' 2>/dev/null | sort)
}

# match_known <hash> <name> -> "verbatim|<scope>:<name>", "adapted|<scope>:<name>" or "none|"
# Scope priority: a project-saved copy is the repo's own; a plugin or bundled
# original beats a user-scope copy of it, so friction reaches the plugin's repo.
match_known() {
  local h="$1" nm="$2" scope kname khash kpath want
  for want in project plugin bundled user; do
    while IFS=$'\t' read -r scope kname khash kpath; do
      [ "$scope" = "$want" ] || continue
      if [ "$khash" = "$h" ]; then echo "verbatim|${scope}:${kname}"; return; fi
    done <<<"$known_rows"
  done
  if [ -n "$nm" ]; then
    for want in project plugin bundled user; do
      while IFS=$'\t' read -r scope kname khash kpath; do
        [ "$scope" = "$want" ] || continue
        if [ "$kname" = "$nm" ]; then echo "adapted|${scope}:${kname}"; return; fi
      done <<<"$known_rows"
    done
  fi
  echo "none|"
}

# Distinct names per scope: a plugin source checkout and its installed copy
# carry the same template, and count once.
count_scope() { awk -F'\t' -v s="$1" '$1 == s && !seen[$2]++ { n++ } END { print n + 0 }' <<<"$known_rows"; }

emit_known() {
  local n_proj n_user n_plug n_bund
  n_proj=$(count_scope project)
  n_user=$(count_scope user)
  n_plug=$(count_scope plugin)
  n_bund=$(count_scope bundled)
  echo "=== KNOWN WORKFLOWS ==="
  echo "SAVED_PROJECT_COUNT=${n_proj:-0}"
  echo "SAVED_USER_COUNT=${n_user:-0}"
  echo "PLUGIN_REGISTERED_COUNT=${n_plug:-0}"
  echo "BUNDLED_TEMPLATE_COUNT=${n_bund:-0}"
  if [ "$summary_mode" = false ]; then
    local i=0 scope kname khash kpath
    while IFS=$'\t' read -r scope kname khash kpath; do
      [ -n "$scope" ] || continue
      i=$((i + 1))
      if [ "$i" -gt "$MAX_KNOWN" ]; then echo "KNOWN_TRUNCATED=true"; break; fi
      echo "KNOWN_${i}=${scope}|${kname}|$(owning_repo "$scope" "$kpath")|${kpath}"
    done < <(awk -F'\t' '!seen[$1 FS $2]++' <<<"$known_rows")
  fi
  echo "=== END KNOWN WORKFLOWS ==="
}

# ---------------------------------------------------------------------------
# Usage mode
# ---------------------------------------------------------------------------
usage_mode() {
  local slug_dirs=() d slug
  echo "=== WORKFLOW USAGE ==="
  if ! have jq; then
    echo "TRANSCRIPT_AVAILABLE=false"; echo "SKIP_REASON=jq not installed"; echo "STATUS=SKIP"; echo "ISSUE_COUNT=0"
    echo "=== END WORKFLOW USAGE ==="; return 0
  fi
  if [ ! -d "$projects_dir" ]; then
    echo "TRANSCRIPT_AVAILABLE=false"; echo "SKIP_REASON=no projects dir"; echo "STATUS=SKIP"; echo "ISSUE_COUNT=0"
    echo "=== END WORKFLOW USAGE ==="; return 0
  fi
  if [ "$all_projects" = true ]; then
    for d in "$projects_dir"/*/; do [ -d "$d" ] && slug_dirs+=("${d%/}"); done
  else
    slug=$(printf '%s' "$project_dir" | sed 's/[^A-Za-z0-9]/-/g')
    [ -d "$projects_dir/$slug" ] && slug_dirs+=("$projects_dir/$slug")
  fi
  if [ "${#slug_dirs[@]}" -eq 0 ]; then
    echo "TRANSCRIPT_AVAILABLE=false"; echo "SKIP_REASON=no transcripts for this project (try --all-projects)"; echo "STATUS=SKIP"; echo "ISSUE_COUNT=0"
    echo "=== END WORKFLOW USAGE ==="; return 0
  fi

  local files tsv f
  files=$(for d in "${slug_dirs[@]}"; do
            for f in "$d"/*.jsonl; do [ -f "$f" ] && printf '%s\t%s\n' "$(file_mtime "$f")" "$f"; done
          done | sort -rn | head -n "$window_sessions" | cut -f2-)
  # One jq pass per transcript: a `call` row per Workflow tool_use, a `result`
  # row per Workflow tool result that carries a runId.
  tsv=""
  local scanned=0 with_wf=0 out
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    scanned=$((scanned + 1))
    # -R + fromjson?: a truncated or corrupt line is skipped, not fatal.
    out=$(jq -rR 'fromjson? // empty |
      if .type == "assistant" then
        (.message.content[]? | select(type == "object" and .type == "tool_use" and .name == "Workflow")
         | ["call",
            (if (.input.name // "") != "" then "name"
             elif (.input.scriptPath // "") != "" then "scriptPath"
             else "inline" end),
            (.input.name // "-"),
            (if (.input.resumeFromRunId // "") != "" then "resume" else "fresh" end)] | @tsv)
      elif (.toolUseResult | type) == "object" and (.toolUseResult.runId // "") != "" then
        ["result", (.toolUseResult.workflowName // "-")] | @tsv
      else empty end' "$f" 2>/dev/null)
    if [ -n "$out" ]; then with_wf=$((with_wf + 1)); tsv+="$out"$'\n'; fi
  done <<<"$files"

  local calls inline spath byname resumes known_hits=0 wn cnt
  calls=$(grep -c $'^call\t' <<<"$tsv" || true)
  inline=$(grep -c $'^call\tinline\t' <<<"$tsv" || true)
  spath=$(grep -c $'^call\tscriptPath\t' <<<"$tsv" || true)
  byname=$(grep -c $'^call\tname\t' <<<"$tsv" || true)
  resumes=$(grep -c $'\tresume$' <<<"$tsv" || true)

  echo "TRANSCRIPT_AVAILABLE=true"
  echo "PROJECT_SCOPE=$([ "$all_projects" = true ] && echo all || echo current)"
  echo "SESSIONS_SCANNED=${scanned}"
  echo "SESSIONS_WITH_WORKFLOW=${with_wf}"
  echo "WORKFLOW_CALLS=${calls:-0}"
  echo "CALLS_INLINE=${inline:-0}"
  echo "CALLS_SCRIPT_PATH=${spath:-0}"
  echo "CALLS_BY_NAME=${byname:-0}"
  echo "CALLS_RESUME=${resumes:-0}"

  collect_known
  local i=0
  while read -r cnt wn; do
    [ -n "${wn:-}" ] || continue
    i=$((i + 1)); [ "$i" -le "$MAX_NAMES" ] || { echo "NAMED_TRUNCATED=true"; break; }
    echo "NAMED_${i}=${wn}|${cnt}"
  done < <(awk -F'\t' '$1=="call" && $2=="name" {print $3}' <<<"$tsv" | sort | uniq -c | sort -rn)
  echo "NAMED_COUNT=${i}"
  i=0
  while read -r cnt wn; do
    [ -n "${wn:-}" ] || continue
    if WCS_N="$wn" awk -F'\t' '$2==ENVIRON["WCS_N"] {f=1} END {exit !f}' <<<"$known_rows"; then known_hits=$((known_hits + cnt)); fi
    i=$((i + 1)); [ "$i" -le "$MAX_NAMES" ] || { echo "RUN_NAME_TRUNCATED=true"; break; }
    echo "RUN_NAME_${i}=${wn}|${cnt}"
  done < <(awk -F'\t' '$1=="result" {print $2}' <<<"$tsv" | sort | uniq -c | sort -rn)
  echo "RUN_NAME_COUNT=${i}"
  echo "RUNS_MATCHING_KNOWN_NAME=${known_hits}"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END WORKFLOW USAGE ==="
  emit_known
}

# ---------------------------------------------------------------------------
# Session mode
# ---------------------------------------------------------------------------
session_mode() {
  local transcript="" session_dir="" skip_reason="" d
  if [ -z "$session_id" ]; then
    skip_reason="no --session-id"
  elif [ ! -d "$projects_dir" ]; then
    skip_reason="no projects dir"
  else
    # The transcript and the session dir are found independently, the
    # current project's slug first, so a session split across slugs keeps both.
    local own_slug slug_order=()
    own_slug="$projects_dir/$(printf '%s' "$project_dir" | sed 's/[^A-Za-z0-9]/-/g')/"
    [ -d "$own_slug" ] && slug_order+=("$own_slug")
    for d in "$projects_dir"/*/; do [ -d "$d" ] && [ "$d" != "$own_slug" ] && slug_order+=("$d"); done
    for d in "${slug_order[@]+"${slug_order[@]}"}"; do
      [ -z "$session_dir" ] && [ -d "${d}${session_id}" ] && session_dir="${d}${session_id}"
      [ -z "$transcript" ] && [ -f "${d}${session_id}.jsonl" ] && transcript="${d}${session_id}.jsonl"
    done
    [ -n "$session_dir$transcript" ] || skip_reason="session not found under projects dir"
  fi

  echo "=== WORKFLOW CAPTURE SURVEY ==="
  echo "MODE=session"
  echo "SESSION_ID=${session_id}"
  if [ -n "$skip_reason" ]; then
    echo "TRANSCRIPT_AVAILABLE=false"
    echo "SKIP_REASON=${skip_reason}"
    echo "=== END WORKFLOW CAPTURE SURVEY ==="
    echo "=== SUMMARY ==="
    echo "RUN_COUNT=0"; echo "WORKFLOW_COUNT=0"
    echo "CAPTURE_CANDIDATE_COUNT=0"; echo "FRICTION_SIGNAL_COUNT=0"
    echo "STATUS=SKIP"; echo "ISSUE_COUNT=0"
    echo "=== END SUMMARY ==="
    return 0
  fi
  echo "TRANSCRIPT_AVAILABLE=true"
  emit_repos
  echo "SESSION_DIR=${session_dir}"
  echo "TRANSCRIPT=${transcript}"
  echo "=== END WORKFLOW CAPTURE SURVEY ==="

  collect_known

  # Transcript facts per runId: mode (inline|scriptPath|name) and resume flag.
  # Joined on tool_use_id so a background launch's later notification does not
  # need to be parsed.
  local calls_by_run=""
  if [ -n "$transcript" ] && have jq; then
    calls_by_run=$(jq -rRn '[inputs | fromjson? // empty] |
      ( [ .[] | select(.type == "assistant") | .message.content[]?
          | select(type == "object" and .type == "tool_use" and .name == "Workflow")
          | {key: .id, value: {
              mode: (if (.input.name // "") != "" then "name"
                     elif (.input.scriptPath // "") != "" then "scriptPath" else "inline" end),
              resume: ((.input.resumeFromRunId // "") != "") } } ] | from_entries ) as $calls
      | .[] | select((.toolUseResult | type) == "object" and (.toolUseResult.runId // "") != "")
      | ([.message.content[]? | select(type == "object" and .type == "tool_result") | .tool_use_id][0]) as $tid
      | [ .toolUseResult.runId,
          ($calls[$tid].mode // "unknown"),
          (if ($calls[$tid].resume // false) then "true" else "false" end),
          (.toolUseResult.workflowName // "") ] | @tsv' "$transcript" 2>/dev/null)
  fi

  # Runs: the persisted scripts are ground truth; the transcript enriches them.
  local scripts_dir="${session_dir}/workflows/scripts"
  local run_rows="" f base run_id wf_name h m_kind m_ref r_mode r_resume spawned returned jdir
  if [ -n "$session_dir" ] && [ -d "$scripts_dir" ]; then
    while IFS= read -r f; do
      [ -f "$f" ] || continue
      base=$(basename "$f" .js)
      run_id=""
      if [[ "$base" =~ -(wf_[A-Za-z0-9-]+)$ ]]; then run_id="${BASH_REMATCH[1]}"; fi
      wf_name=$(meta_field "$f" name)
      h=$(file_hash "$f")
      # Without meta.name, group by content: unrelated unnamed scripts share
      # the harness's fallback name and would read as one rerun workflow.
      [ -n "$wf_name" ] || wf_name="unnamed-${h:0:8}"
      IFS='|' read -r m_kind m_ref <<<"$(match_known "$h" "$wf_name")"
      r_mode="unknown"; r_resume="false"
      if [ -n "$run_id" ] && [ -n "$calls_by_run" ]; then
        local row
        row=$(WCS_R="$run_id" awk -F'\t' '$1==ENVIRON["WCS_R"] {print; exit}' <<<"$calls_by_run")
        if [ -n "$row" ]; then
          r_mode=$(cut -f2 <<<"$row"); r_resume=$(cut -f3 <<<"$row")
        fi
      fi
      # A run started by name executes a saved/plugin workflow as written.
      if [ "$r_mode" = "name" ] && [ "$m_kind" != "verbatim" ]; then m_kind="verbatim"; fi
      spawned=0; returned=0
      jdir="${session_dir}/subagents/workflows/${run_id}"
      if [ -n "$run_id" ] && [ -f "$jdir/journal.jsonl" ]; then
        spawned=$(grep -c '"type":"started"' "$jdir/journal.jsonl" || true)
        returned=$(grep -c '"type":"result"' "$jdir/journal.jsonl" || true)
      fi
      run_rows+="$(file_mtime "$f")"$'\t'"${run_id:--}"$'\t'"${wf_name:-unnamed}"$'\t'"$r_mode"$'\t'"$r_resume"$'\t'"${spawned:-0}"$'\t'"${returned:-0}"$'\t'"$m_kind"$'\t'"${m_ref:--}"$'\t'"$(count_calls "$f" agent)"$'\t'"$(count_calls "$f" phase)"$'\t'"$f"$'\n'
    done < <(find "$scripts_dir" -maxdepth 1 -type f -name '*.js' 2>/dev/null)
  fi
  run_rows=$(sort -n <<<"$run_rows" | sed '/^$/d')

  local run_count=0
  [ -n "$run_rows" ] && run_count=$(wc -l <<<"$run_rows")
  run_count=$((run_count + 0))

  if [ "$summary_mode" = false ]; then
    echo "=== SESSION RUNS ==="
    echo "RUN_COUNT=${run_count}"
    local i=0 mt rid nm rm rr sp rt mk mr ac pc sp_path
    while IFS=$'\t' read -r mt rid nm rm rr sp rt mk mr ac pc sp_path; do
      [ -n "${mt:-}" ] || continue
      i=$((i + 1))
      if [ "$i" -gt "$MAX_RUNS" ]; then echo "RUNS_TRUNCATED=true"; break; fi
      echo "RUN_${i}_RUN_ID=${rid}"
      echo "RUN_${i}_NAME=${nm}"
      echo "RUN_${i}_MODE=${rm}"
      echo "RUN_${i}_RESUME=${rr}"
      echo "RUN_${i}_AGENTS_SPAWNED=${sp}"
      echo "RUN_${i}_AGENTS_RETURNED=${rt}"
      echo "RUN_${i}_MATCH=${mk}|${mr}"
      echo "RUN_${i}_SCRIPT=${sp_path}"
    done <<<"$run_rows"
    echo "=== END SESSION RUNS ==="
  fi

  # Group runs by workflow name: the latest script stands for the workflow.
  local names wf_count=0 candidates=0 friction=0
  names=$(cut -f3 <<<"$run_rows" | sed '/^$/d' | awk '!seen[$0]++')
  [ "$summary_mode" = false ] && echo "=== SESSION WORKFLOWS ==="
  local j=0 nm grp runs last kinds origin unfinished resumed latest_script ac pc ref signals match_repo
  while IFS= read -r nm; do
    [ -n "$nm" ] || continue
    j=$((j + 1))
    grp=$(WCS_N="$nm" awk -F'\t' '$3==ENVIRON["WCS_N"]' <<<"$run_rows")
    runs=$(wc -l <<<"$grp"); runs=$((runs + 0))
    last=$(tail -n 1 <<<"$grp")
    kinds=$(cut -f8 <<<"$grp" | sort -u | tr '\n' ' ')
    # Origin: authored if no run matched a known workflow, verbatim if every
    # run did byte-for-byte (or by name), adapted otherwise.
    case "$kinds" in
      "verbatim ") origin="verbatim" ;;
      "none ") origin="authored" ;;
      *) origin="adapted" ;;
    esac
    unfinished=$(awk -F'\t' '{u += ($6 - $7)} END {print u + 0}' <<<"$grp")
    resumed=$(awk -F'\t' '$5=="true" {r++} END {print r + 0}' <<<"$grp")
    latest_script=$(cut -f12 <<<"$last")
    ac=$(cut -f10 <<<"$last"); pc=$(cut -f11 <<<"$last")
    ref=$(awk -F'\t' '$9!="-" {print $9; exit}' <<<"$grp")
    match_repo=""
    if [ -n "$ref" ]; then
      local kp
      kp=$(WCS_S="${ref%%:*}" WCS_N="${ref#*:}" awk -F'\t' '$1==ENVIRON["WCS_S"] && $2==ENVIRON["WCS_N"] {print $4; exit}' <<<"$known_rows")
      match_repo=$(owning_repo "${ref%%:*}" "$kp")
    fi
    signals=""
    [ "$runs" -gt 1 ] && signals+="reran "
    [ "$unfinished" -gt 0 ] && signals+="unfinished_agents "
    [ "$resumed" -gt 0 ] && signals+="resumed "
    [ "$origin" = "adapted" ] && signals+="adapted_known "
    signals="${signals% }"
    case "$origin" in authored|adapted) candidates=$((candidates + 1)) ;; esac
    [ -n "$signals" ] && friction=$((friction + 1))
    wf_count=$j
    if [ "$summary_mode" = false ]; then
      echo "WORKFLOW_${j}_NAME=${nm}"
      echo "WORKFLOW_${j}_RUNS=${runs}"
      echo "WORKFLOW_${j}_ORIGIN=${origin}"
      echo "WORKFLOW_${j}_MATCH=${ref:-none}"
      echo "WORKFLOW_${j}_MATCH_REPO=${match_repo:-none}"
      echo "WORKFLOW_${j}_AGENT_SITES=${ac}"
      echo "WORKFLOW_${j}_PHASE_CALLS=${pc}"
      echo "WORKFLOW_${j}_UNFINISHED_AGENTS=${unfinished}"
      echo "WORKFLOW_${j}_SIGNALS=${signals:-none}"
      echo "WORKFLOW_${j}_SCRIPT=${latest_script}"
    fi
  done <<<"$names"
  if [ "$summary_mode" = false ]; then
    echo "WORKFLOW_COUNT=${wf_count}"
    echo "=== END SESSION WORKFLOWS ==="
    emit_known
  fi

  echo "=== SUMMARY ==="
  echo "RUN_COUNT=${run_count}"
  echo "WORKFLOW_COUNT=${wf_count}"
  echo "CAPTURE_CANDIDATE_COUNT=${candidates}"
  echo "FRICTION_SIGNAL_COUNT=${friction}"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END SUMMARY ==="
}

if [ "$mode" = "usage" ]; then usage_mode; else session_mode; fi
exit 0
