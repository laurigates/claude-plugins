#!/usr/bin/env bash
# Check Usage Telemetry (~/.claude/projects/*/*.jsonl)
# Mines local session transcripts for skill- and agent-invocation recency to surface:
#   - never-fired skills : enabled skills with zero invocations in any transcript
#   - dormant skills     : skills whose most-recent invocation is older than the window
#   - never-fired agents : enabled plugin agents never spawned via the Agent/Task tool
#   - dormant agents     : agents whose most-recent invocation is older than the window
#
# Read-only audit. Local-leaning by design: session history is local and
# long-lived, so a fresh clone (remote/web sandbox) has little or no history.
# When history is insufficient the script emits STATUS=SKIP rather than
# reporting every enabled skill as "never fired".
#
# Inventory (what counts as "enabled"):
#   Default (INVENTORY_SOURCE=registry): the plugin registry. For every plugin
#   in <plugins>/installed_plugins.json, take the install record that applies
#   to --project-dir (local, then project scope with a matching projectPath,
#   else user scope), keep it when enabledPlugins (user < project < local
#   settings, per key) does not set it to false (an absent entry falls back to
#   the manifest's defaultEnabled, default true), and enumerate skills/agents
#   only under that record's installPath. The plugin cache keeps one directory
#   per installed version (old ones linger 14 days with .orphaned_at), and it
#   holds disabled plugins too, so a recursive scan of <plugins>/ counts every
#   version of every plugin: 5,756 "enabled" skills on a ~420-skill marketplace
#   (measured 2026-11-10).
#   Legacy (--skills-dir <path>, INVENTORY_SOURCE=skills-dir): every SKILL.md
#   and agents/*.md under <path>, deduplicated by name.
#
# Matching is exact. A skill is keyed <plugin>:<name> (the plugin's manifest
# name; <name> is the skill directory, and a frontmatter `name:` adds a second
# key) and answers to: <plugin>:<name>, the bare <name>, and the short
# directory-prefixed forms <ns>:<name> / <ns>:<rest> for a plugin named
# <ns>-plugin and a skill directory <ns>-<rest>. A bare token marks every skill
# with that exact name (ADR-0018's bias toward "fired", limited to exact name
# equality). The former substring fallback is gone: it marked `review` fired
# whenever `code-review` fired.
#
# Implements ADR-0018. Output follows .claude/rules/structured-script-output.md.
#
# Usage: bash check-usage.sh --home-dir <path> --project-dir <path> \
#          [--window-days N] [--plugins-dir <path>] [--skills-dir <path>] \
#          [--min-transcripts N] [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
skills_dir=""
plugins_dir=""
window_days=30
min_transcripts=2
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --skills-dir) skills_dir="$2"; shift 2 ;;
    --plugins-dir) plugins_dir="$2"; shift 2 ;;
    --window-days) window_days="$2"; shift 2 ;;
    --min-transcripts) min_transcripts="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"
# The plugins root is ~/.claude/plugins unless CLAUDE_CODE_PLUGIN_CACHE_DIR
# moves it (code.claude.com/docs/en/plugins/loading § Find plugins on disk).
: "${plugins_dir:=${CLAUDE_CODE_PLUGIN_CACHE_DIR:-${home_dir}/.claude/plugins}}"

# shellcheck disable=SC1091  # sibling lib; resolved relative to this script at runtime
source "$(dirname "${BASH_SOURCE[0]}")/lib/retention.sh"

echo "=== USAGE TELEMETRY ==="

usage_issue_count=0
usage_status="OK"
usage_issues=""
usage_reason=""

# Record the first finding as REASON (`<TYPE>: <MSG>`, one line, <=180 chars).
note_reason() {
  [ -n "$usage_reason" ] && return 0
  local reason_text="$1: $2"
  reason_text="${reason_text//$'\n'/ }"
  usage_reason="${reason_text:0:180}"
}

# Emit REASON= with the "(+N more)" tail; only called on a non-OK status.
emit_reason() {
  local more=$(( $1 - 1 ))
  if [ "$more" -gt 0 ]; then
    echo "REASON=${usage_reason} (+${more} more)"
  else
    echo "REASON=${usage_reason}"
  fi
}

# jq is required (shared convention with sibling check-*.sh scripts).
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "REASON=missing_tool: jq is required but not installed"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END USAGE TELEMETRY ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"
echo "WINDOW_DAYS=${window_days}"

# Transcripts older than cleanupPeriodDays are deleted by the retention sweep,
# so a dormancy window wider than retention cannot see the older invocations:
# a skill last used before the cutoff reads as never-fired, not dormant.
resolve_cleanup_period "$home_dir" "$project_dir"
echo "RETENTION_DAYS=${CLEANUP_PERIOD_DAYS}"
retention_note=""
if [ "$window_days" -gt "$CLEANUP_PERIOD_DAYS" ] 2>/dev/null; then
  retention_note="  - SEVERITY=INFO TYPE=window_exceeds_retention WINDOW_DAYS=${window_days} RETENTION_DAYS=${CLEANUP_PERIOD_DAYS} MSG=transcripts older than cleanupPeriodDays are swept; never-fired counts include skills used before the cutoff\n"
fi

projects_dir="${home_dir}/.claude/projects"

work_dir="$(mktemp -d 2>/dev/null || true)"
if [ -z "$work_dir" ] || [ ! -d "$work_dir" ]; then
  echo "STATUS=ERROR"
  echo "REASON=no_tmpdir: mktemp -d failed; cannot stage the transcript scan"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=no_tmpdir MSG=mktemp -d failed; cannot stage the transcript scan"
  echo "=== END USAGE TELEMETRY ==="
  exit 1
fi
trap 'rm -rf "$work_dir"' EXIT

# --- Gather transcripts (prune .claude/worktrees clones, per #1492/#1548) -----
transcript_list="${work_dir}/transcripts.list"
: > "$transcript_list"
if [ -d "$projects_dir" ]; then
  find "$projects_dir" -path '*/.claude/worktrees/*' -prune -o \
    -type f -name '*.jsonl' -print0 2>/dev/null > "$transcript_list"
fi
transcripts_scanned=$(tr -cd '\0' < "$transcript_list" | wc -c | tr -d ' ')
echo "TRANSCRIPTS_SCANNED=${transcripts_scanned}"

# --- SKIP when history is insufficient (fresh clone / remote sandbox) ---------
if [ ! -d "$projects_dir" ] || [ "$transcripts_scanned" -lt "$min_transcripts" ]; then
  skip_msg="fewer than ${min_transcripts} session transcripts under ${projects_dir} (usage telemetry needs a long-running local install; skipped)"
  echo "HISTORY_AVAILABLE=false"
  echo "STATUS=SKIP"
  echo "REASON=insufficient_history: ${skip_msg:0:160}"
  echo "ISSUE_COUNT=0"
  echo "ISSUES:"
  echo "  - SEVERITY=INFO TYPE=insufficient_history MSG=${skip_msg}"
  echo "FIX_SUPPORTED=false"
  echo "=== END USAGE TELEMETRY ==="
  exit 0
fi
echo "HISTORY_AVAILABLE=true"

now_epoch=$(date +%s)
window_cutoff=$((now_epoch - window_days * 86400))

# --- Parse transcripts in one pass -------------------------------------------
# File mtimes come from one batched stat; tool_use events from one jq -R stream
# per xargs batch (fromjson? skips a corrupt line without losing the rest of the
# batch), run in parallel into per-process files; one awk joins and aggregates.
mtime_tsv="${work_dir}/mtimes.tsv"
# Sentinel first line: the awk join below reads this file as NR == FNR, which
# would swallow the event stream if every stat failed and the file were empty.
printf '0\t\n' > "$mtime_tsv"
if stat -c '%Y' "$projects_dir" >/dev/null 2>&1; then
  xargs -0 stat -c $'%Y\t%n' < "$transcript_list" >> "$mtime_tsv" 2>/dev/null   # GNU
else
  xargs -0 stat -f $'%m\t%N' < "$transcript_list" >> "$mtime_tsv" 2>/dev/null   # BSD/macOS
fi

# Emits "<file>\t<S|A|T>\t<token>" per tool_use: S=Skill, A=Agent/Task, T=other.
# The filter text is passed verbatim to jq in the xargs children.
# shellcheck disable=SC2089,SC2090
USAGE_JQ_FILTER='
  fromjson? | select(type == "object" and .type == "assistant")
  | (.message.content? // []) | if type == "array" then .[] else empty end
  | select(type == "object" and .type == "tool_use")
  | if .name == "Skill" then
      "S\t" + ((.input.skill // .input.command // .input.name // "") | tostring | gsub("[\t\r\n]"; " "))
    elif (.name == "Agent" or .name == "Task") then
      "A\t" + ((.input.subagent_type // "") | tostring | gsub("[\t\r\n]"; " "))
    else "T\t" end
  | input_filename + "\t" + .'
USAGE_EVENTS_DIR="${work_dir}/events"
mkdir -p "$USAGE_EVENTS_DIR"
# shellcheck disable=SC2090
export USAGE_JQ_FILTER USAGE_EVENTS_DIR
scan_jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
[[ "$scan_jobs" =~ ^[0-9]+$ ]] || scan_jobs=2
[ "$scan_jobs" -gt 4 ] && scan_jobs=4
[ "$scan_jobs" -lt 1 ] && scan_jobs=1
# shellcheck disable=SC2016  # $1.. are expanded by the inner bash, not here
xargs -0 -n 64 -P "$scan_jobs" bash -c \
  'jq -R -r "$USAGE_JQ_FILTER" "$@" > "$(mktemp "$USAGE_EVENTS_DIR/ev.XXXXXX")" 2>/dev/null; exit 0' _ \
  < "$transcript_list"

# Aggregate: TOTAL\t<n>, then <S|A>\t<token>\t<count>\t<max mtime>.
# A leading '/' on a token is dropped; an empty token still counts as a tool_use.
agg_tsv="${work_dir}/agg.tsv"
find "$USAGE_EVENTS_DIR" -type f -name 'ev.*' -print0 \
  | xargs -0 cat 2>/dev/null \
  | awk -F'\t' '
      NR == FNR { mt[$2] = $1 + 0; next }
      {
        total++
        if ($2 != "S" && $2 != "A") next
        tok = $3; sub(/^\//, "", tok)
        if (tok == "") next
        k = $2 "\t" tok
        cnt[k]++
        m = mt[$1] + 0
        if (m > last[k]) last[k] = m
      }
      END {
        print "TOTAL\t" (total + 0)
        for (k in cnt) print k "\t" cnt[k] "\t" (last[k] + 0)
      }' "$mtime_tsv" - > "$agg_tsv"

total_tool_use=0
# fired_last[token] / agent_flast[token] = most-recent transcript mtime; read
# through namerefs in resolve_hits below.
# shellcheck disable=SC2034
declare -A fired_last=() agent_flast=()
while IFS=$'\t' read -r agg_kind agg_tok _agg_n agg_m; do
  # shellcheck disable=SC2034  # both maps are read through namerefs
  case "$agg_kind" in
    TOTAL) total_tool_use="$agg_tok" ;;
    S) fired_last["$agg_tok"]="$agg_m" ;;
    A) agent_flast["$agg_tok"]="$agg_m" ;;
  esac
done < "$agg_tsv"

echo "TOOL_USE_EVENTS=${total_tool_use}"

# --- Schema-drift sentinel ----------------------------------------------------
# A populated history with zero detectable tool_use events almost certainly
# means the transcript JSON shape changed under us, not that the user ran no
# tools across many sessions. Guarded by min_transcripts to avoid the
# genuine chat-only false positive on a tiny install.
if [ "$total_tool_use" -eq 0 ]; then
  drift_msg="${transcripts_scanned} transcripts scanned but zero tool_use events parsed; transcript JSON shape may have changed (parser needs review)"
  echo "SCHEMA_DRIFT_SUSPECTED=true"
  echo "STATUS=WARN"
  echo "REASON=schema_drift: ${drift_msg:0:166}"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=schema_drift MSG=${drift_msg}"
  echo "FIX_SUPPORTED=false"
  echo "=== END USAGE TELEMETRY ==="
  exit 0
fi
echo "SCHEMA_DRIFT_SUSPECTED=false"

# --- Inventory ----------------------------------------------------------------
# skill_keys / agent_keys: canonical inventory keys (deduplicated).
# skill_alias[token] / agent_alias[token]: space-separated canonical keys the
# token names (written and read through namerefs).
# shellcheck disable=SC2034
declare -A skill_seen=() agent_seen=() skill_alias=() agent_alias=()
declare -a skill_keys=() agent_keys=()
plugins_enabled=0

add_alias() {  # $1 = alias map name, $2 = token, $3 = canonical key
  local -n alias_map="$1"
  case " ${alias_map[$2]-} " in
    *" $3 "*) ;;
    *) alias_map["$2"]="${alias_map[$2]-}${alias_map[$2]:+ }$3" ;;
  esac
}

# Register one skill. $1 = plugin name ("" in legacy mode), $2 = directory name,
# $3 = frontmatter name ("" when unset).
register_skill() {
  local plug="$1" sdir="$2" fm="$3" key ns form
  if [ -n "$plug" ]; then key="${plug}:${sdir}"; else key="$sdir"; fi
  if [ -z "${skill_seen[$key]+x}" ]; then
    skill_seen["$key"]=1
    skill_keys+=("$key")
  fi
  for form in "$sdir" ${fm:+"$fm"}; do
    add_alias skill_alias "$form" "$key"
    [ -n "$plug" ] || continue
    add_alias skill_alias "${plug}:${form}" "$key"
    if [[ "$plug" == *-plugin ]]; then
      ns="${plug%-plugin}"
      add_alias skill_alias "${ns}:${form}" "$key"
      [[ "$form" == "${ns}-"* ]] && add_alias skill_alias "${ns}:${form#"${ns}"-}" "$key"
    fi
  done
}

# Register one agent. $1 = plugin name ("" in legacy mode), $2 = scoped name
# below the plugin (subfolders joined with ':'), $3 = frontmatter name.
register_agent() {
  local plug="$1" scoped="$2" fm="$3" key leaf
  if [ -n "$fm" ]; then
    case "$scoped" in *:*) scoped="${scoped%:*}:${fm}" ;; *) scoped="$fm" ;; esac
  fi
  if [ -n "$plug" ]; then key="${plug}:${scoped}"; else key="$scoped"; fi
  if [ -z "${agent_seen[$key]+x}" ]; then
    agent_seen["$key"]=1
    agent_keys+=("$key")
  fi
  leaf="${scoped##*:}"
  add_alias agent_alias "$key" "$key"
  add_alias agent_alias "$scoped" "$key"
  add_alias agent_alias "$leaf" "$key"
}

# Print "<file>\t<frontmatter name>" for each file whose leading frontmatter
# block sets name:. One awk pass over the whole file list.
frontmatter_names() {  # reads NUL-separated paths on stdin
  # shellcheck disable=SC2016  # awk program, not shell
  xargs -0 awk '
    FNR == 1 { infm = ($0 ~ /^---[[:space:]]*$/); done = 0; next }
    done { next }
    infm && /^---[[:space:]]*$/ { done = 1; next }
    infm && /^name:/ {
      v = $0; sub(/^name:[[:space:]]*/, "", v); sub(/[[:space:]]+$/, "", v)
      gsub(/^["'"'"']|["'"'"']$/, "", v)
      if (v != "") print FILENAME "\t" v
      done = 1
    }' 2>/dev/null
}

inventory_source="registry"
inventory_where="${plugins_dir}/installed_plugins.json"
# Fields are separated by \037 (unit separator): `read` collapses runs of IFS
# whitespace, so a tab would swallow the empty legacy-mode plugin field.
list_sep=$'\037'
skill_list="${work_dir}/skills.list"   # <plugin>\037<skill dir>\037<SKILL.md path>
agent_list="${work_dir}/agents.list"   # <plugin>\037<scoped name>\037<agent .md path>
: > "$skill_list"; : > "$agent_list"

if [ -n "$skills_dir" ]; then
  # Legacy filesystem inventory: names only, deduplicated.
  inventory_source="skills-dir"
  inventory_where="$skills_dir"
  if [ -d "$skills_dir" ]; then
    find "$skills_dir" -path '*/.claude/worktrees/*' -prune -o \
      -type f \( -name 'SKILL.md' -o -name 'skill.md' \) -print 2>/dev/null \
      | while IFS= read -r smd; do
          printf '\037%s\037%s\n' "$(basename "$(dirname "$smd")")" "$smd"
        done >> "$skill_list"
    find "$skills_dir" -path '*/.claude/worktrees/*' -prune -o \
      -path '*/agents/*.md' -type f -print 2>/dev/null \
      | while IFS= read -r amd; do
          printf '\037%s\037%s\n' "$(basename "$amd" .md)" "$amd"
        done >> "$agent_list"
  fi
else
  # Registry inventory. enabledPlugins merges per key, user < project < local.
  merged_enabled=$(
    for settings_file in "${home_dir}/.claude/settings.json" \
                         "${project_dir}/.claude/settings.json" \
                         "${project_dir}/.claude/settings.local.json"; do
      if [ -f "$settings_file" ]; then
        jq -c '(.enabledPlugins // {}) | if type == "object" then . else {} end' \
          "$settings_file" 2>/dev/null || echo '{}'
      fi
    done | jq -cs 'add // {}' 2>/dev/null
  )
  [ -n "$merged_enabled" ] || merged_enabled='{}'

  registry_rows=""
  if [ -f "$inventory_where" ]; then
    registry_rows=$(jq -r --arg pd "$project_dir" --argjson en "$merged_enabled" '
      (.plugins // {}) | to_entries[]
      | .key as $id
      | (.value | if type == "array" then . else [.] end) as $recs
      | ( [ $recs[] | select(type == "object" and .scope == "local" and .projectPath == $pd) ][0]
          // [ $recs[] | select(type == "object" and .scope == "project" and .projectPath == $pd) ][0]
          // [ $recs[] | select(type == "object" and .scope == "user") ][0] ) as $rec
      | select($rec != null and ($rec.installPath | type) == "string" and $rec.installPath != "")
      | ($en[$id]) as $state
      | select($state != false)
      | [$id, $rec.installPath, (if $state == true then "explicit" else "default" end)]
      | @tsv' "$inventory_where" 2>/dev/null)
  fi

  while IFS=$'\t' read -r plugin_id install_path enable_state; do
    { [ -n "$plugin_id" ] && [ -d "$install_path" ]; } || continue
    manifest="${install_path}/.claude-plugin/plugin.json"
    plugin_name="${plugin_id%@*}"
    manifest_skills=""; manifest_agents=""; has_skills_key=false; has_agents_key=false
    if [ -f "$manifest" ]; then
      manifest_rows=$(jq -r '
        "NAME\t" + ((.name // "") | tostring),
        "DEFAULT\t" + (if .defaultEnabled == false then "false" else "true" end),
        (if has("skills") then "SKEY\t1" else empty end),
        (if has("agents") then "AKEY\t1" else empty end),
        ((.skills // []) | if type == "array" then .[] else . end | select(type == "string") | "SKILLS\t" + .),
        ((.agents // []) | if type == "array" then .[] else . end | select(type == "string") | "AGENTS\t" + .)
      ' "$manifest" 2>/dev/null)
      default_enabled=true
      while IFS=$'\t' read -r mkind mval; do
        case "$mkind" in
          NAME) [ -n "$mval" ] && plugin_name="$mval" ;;
          DEFAULT) default_enabled="$mval" ;;
          SKEY) has_skills_key=true ;;
          AKEY) has_agents_key=true ;;
          SKILLS) manifest_skills="${manifest_skills}${mval}"$'\n' ;;
          AGENTS) manifest_agents="${manifest_agents}${mval}"$'\n' ;;
        esac
      done <<<"$manifest_rows"
      # An absent enabledPlugins entry falls back to the manifest default.
      [ "$enable_state" = "default" ] && [ "$default_enabled" = "false" ] && continue
    fi
    plugins_enabled=$((plugins_enabled + 1))

    # Skills: default skills/ plus each manifest `skills` directory (adds).
    skill_roots="${install_path}/skills"$'\n'
    while IFS= read -r mpath; do
      [ -n "$mpath" ] || continue
      mpath="${mpath#./}"
      skill_roots="${skill_roots}${install_path}/${mpath}"$'\n'
    done <<<"$manifest_skills"
    while IFS= read -r sroot; do
      { [ -n "$sroot" ] && [ -d "$sroot" ]; } || continue
      sroot="${sroot%/}"
      if [ -f "${sroot}/SKILL.md" ] && [ "$sroot" != "${install_path}/skills" ]; then
        printf '%s\037%s\037%s\n' "$plugin_name" "$(basename "$sroot")" "${sroot}/SKILL.md" >> "$skill_list"
        continue
      fi
      for smd in "$sroot"/*/SKILL.md "$sroot"/*/skill.md; do
        [ -f "$smd" ] || continue
        printf '%s\037%s\037%s\n' "$plugin_name" "$(basename "$(dirname "$smd")")" "$smd" >> "$skill_list"
      done
    done <<<"$skill_roots"
    # A root SKILL.md loads as one skill only when there is no skills/ and no key.
    if [ ! -d "${install_path}/skills" ] && [ "$has_skills_key" = false ] && [ -f "${install_path}/SKILL.md" ]; then
      printf '%s\037%s\037%s\n' "$plugin_name" "$plugin_name" "${install_path}/SKILL.md" >> "$skill_list"
    fi

    # Agents: the manifest `agents` key replaces the agents/ scan, and a file
    # listed there loads without subfolder names.
    if [ "$has_agents_key" = true ]; then
      while IFS= read -r mpath; do
        [ -n "$mpath" ] || continue
        mpath="${install_path}/${mpath#./}"
        [ -f "$mpath" ] || continue
        printf '%s\037%s\037%s\n' "$plugin_name" "$(basename "$mpath" .md)" "$mpath" >> "$agent_list"
      done <<<"$manifest_agents"
    elif [ -d "${install_path}/agents" ]; then
      find "${install_path}/agents" -type f -name '*.md' -print 2>/dev/null \
        | while IFS= read -r amd; do
            rel="${amd#"${install_path}/agents/"}"
            rel="${rel%.md}"
            printf '%s\037%s\037%s\n' "$plugin_name" "${rel//\//:}" "$amd"
          done >> "$agent_list"
    fi
  done <<<"$registry_rows"
fi

# Frontmatter names for every listed file, in one awk pass.
declare -A fm_name=()
fm_tsv="${work_dir}/fm.tsv"
cut -d "$list_sep" -f3 "$skill_list" "$agent_list" | tr '\n' '\0' | frontmatter_names > "$fm_tsv"
while IFS=$'\t' read -r fm_file fm_val; do
  [ -n "$fm_file" ] && fm_name["$fm_file"]="$fm_val"
done < "$fm_tsv"

while IFS="$list_sep" read -r inv_plugin inv_name inv_file; do
  [ -n "$inv_name" ] || continue
  register_skill "$inv_plugin" "$inv_name" "${fm_name[$inv_file]-}"
done < "$skill_list"
while IFS="$list_sep" read -r inv_plugin inv_name inv_file; do
  [ -n "$inv_name" ] || continue
  if [ -n "$inv_plugin" ]; then
    register_agent "$inv_plugin" "$inv_name" "${fm_name[$inv_file]-}"
  else
    register_agent "" "$inv_name" ""   # legacy: filename basename, as before
  fi
done < "$agent_list"

echo "INVENTORY_SOURCE=${inventory_source}"
[ "$inventory_source" = "registry" ] && echo "PLUGINS_ENABLED=${plugins_enabled}"

skills_enabled=${#skill_keys[@]}
echo "SKILLS_ENABLED=${skills_enabled}"

# --- Match fired tokens to inventory keys (exact) ------------------------------
# hit_last[key] = most-recent mtime of any token that names the key.
# A namespaced token whose namespace is no plugin we know falls back to its
# last segment in legacy mode only, where plugin names are unknown.
resolve_hits() {  # $1 = alias map, $2 = fired-last map, $3 = output map
  local -n r_alias="$1" r_last="$2" r_hit="$3"
  local tok keys key m
  for tok in "${!r_last[@]}"; do
    keys="${r_alias[$tok]-}"
    if [ -z "$keys" ] && [ "$inventory_source" = "skills-dir" ] && [[ "$tok" == *:* ]]; then
      keys="${r_alias[${tok##*:}]-}"
    fi
    [ -n "$keys" ] || continue
    m="${r_last[$tok]}"
    for key in $keys; do
      if [ -z "${r_hit[$key]+x}" ] || [ "$m" -gt "${r_hit[$key]}" ]; then
        r_hit["$key"]="$m"
      fi
    done
  done
}

declare -A skill_hit=() agent_hit=()
resolve_hits skill_alias fired_last skill_hit
resolve_hits agent_alias agent_flast agent_hit

skills_fired=0
skills_never=0
skills_dormant=0
never_list=""
dormant_list=""
for sk in "${skill_keys[@]}"; do
  if [ -n "${skill_hit[$sk]+x}" ]; then
    skills_fired=$((skills_fired + 1))
    if [ "${skill_hit[$sk]:-0}" -lt "$window_cutoff" ]; then
      skills_dormant=$((skills_dormant + 1))
      dormant_list="${dormant_list}${sk} "
    fi
  else
    skills_never=$((skills_never + 1))
    never_list="${never_list}${sk} "
  fi
done

echo "SKILLS_FIRED=${skills_fired}"
echo "SKILLS_NEVER_FIRED=${skills_never}"
echo "SKILLS_DORMANT=${skills_dormant}"

agents_enabled=${#agent_keys[@]}
echo "AGENTS_ENABLED=${agents_enabled}"

agents_fired=0
agents_never=0
agents_dormant=0
agent_never_list=""
agent_dormant_list=""
for ag in "${agent_keys[@]}"; do
  if [ -n "${agent_hit[$ag]+x}" ]; then
    agents_fired=$((agents_fired + 1))
    if [ "${agent_hit[$ag]:-0}" -lt "$window_cutoff" ]; then
      agents_dormant=$((agents_dormant + 1))
      agent_dormant_list="${agent_dormant_list}${ag} "
    fi
  else
    agents_never=$((agents_never + 1))
    agent_never_list="${agent_never_list}${ag} "
  fi
done

echo "AGENTS_FIRED=${agents_fired}"
echo "AGENTS_NEVER_FIRED=${agents_never}"
echo "AGENTS_DORMANT=${agents_dormant}"

# --- Roll up issues (advisory; read-only audit) -------------------------------
add_warn() {  # $1 = TYPE, $2 = detail fields, $3 = reason message
  usage_issues="${usage_issues}  - SEVERITY=WARN TYPE=$1 $2\n"
  usage_issue_count=$((usage_issue_count + 1))
  usage_status="WARN"
  note_reason "$1" "$3"
}

if [ "$skills_enabled" -eq 0 ]; then
  no_inv_msg="no enabled plugin skills resolved from ${inventory_where} (cannot compute never-fired without an inventory)"
  add_warn no_skill_inventory "MSG=${no_inv_msg}" "$no_inv_msg"
fi

if [ "$skills_never" -gt 0 ]; then
  msg="enabled skills with zero invocations in history (advisory review candidates; use --verbose to list)"
  if [ "$verbose_mode" = true ]; then
    add_warn never_fired "COUNT=${skills_never} SKILLS=${never_list% }" "COUNT=${skills_never} ${msg}"
  else
    add_warn never_fired "COUNT=${skills_never} MSG=${msg}" "COUNT=${skills_never} ${msg}"
  fi
fi

if [ "$skills_dormant" -gt 0 ]; then
  msg="skills not invoked in ${window_days}+ days (advisory; use --verbose to list)"
  if [ "$verbose_mode" = true ]; then
    add_warn dormant "COUNT=${skills_dormant} SKILLS=${dormant_list% }" "COUNT=${skills_dormant} ${msg}"
  else
    add_warn dormant "COUNT=${skills_dormant} MSG=${msg}" "COUNT=${skills_dormant} ${msg}"
  fi
fi

if [ "$agents_never" -gt 0 ]; then
  msg="enabled plugin agents never spawned in history (advisory review candidates; use --verbose to list)"
  if [ "$verbose_mode" = true ]; then
    add_warn agent_never_fired "COUNT=${agents_never} AGENTS=${agent_never_list% }" "COUNT=${agents_never} ${msg}"
  else
    add_warn agent_never_fired "COUNT=${agents_never} MSG=${msg}" "COUNT=${agents_never} ${msg}"
  fi
fi

if [ "$agents_dormant" -gt 0 ]; then
  msg="agents not invoked in ${window_days}+ days (advisory; use --verbose to list)"
  if [ "$verbose_mode" = true ]; then
    add_warn agent_dormant "COUNT=${agents_dormant} AGENTS=${agent_dormant_list% }" "COUNT=${agents_dormant} ${msg}"
  else
    add_warn agent_dormant "COUNT=${agents_dormant} MSG=${msg}" "COUNT=${agents_dormant} ${msg}"
  fi
fi

echo "STATUS=${usage_status}"
[ "$usage_status" != "OK" ] && emit_reason "$usage_issue_count"
echo "ISSUE_COUNT=${usage_issue_count}"
usage_issues="${usage_issues}${retention_note}"
if [ -n "$usage_issues" ]; then
  echo "ISSUES:"
  echo -e "$usage_issues" | sed '/^$/d'
fi
echo "FIX_SUPPORTED=false"
echo "=== END USAGE TELEMETRY ==="
