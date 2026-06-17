#!/usr/bin/env bash
# Check Usage Telemetry (~/.claude/projects/*/*.jsonl)
# Mines local session transcripts for skill-invocation recency to surface:
#   - never-fired skills : enabled skills with zero invocations in any transcript
#   - dormant skills     : skills whose most-recent invocation is older than the window
#
# Read-only audit. Local-leaning by design: session history is local and
# long-lived, so a fresh clone (remote/web sandbox) has little or no history.
# When history is insufficient the script emits STATUS=SKIP rather than
# reporting every enabled skill as "never fired".
#
# Implements ADR-0018. Output follows .claude/rules/structured-script-output.md.
#
# Usage: bash check-usage.sh --home-dir <path> --project-dir <path> \
#          [--window-days N] [--skills-dir <path>] [--min-transcripts N] [--verbose]

set -uo pipefail

home_dir=""
project_dir=""
skills_dir=""
window_days=30
min_transcripts=2
verbose_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --home-dir) home_dir="$2"; shift 2 ;;
    --project-dir) project_dir="$2"; shift 2 ;;
    --skills-dir) skills_dir="$2"; shift 2 ;;
    --window-days) window_days="$2"; shift 2 ;;
    --min-transcripts) min_transcripts="$2"; shift 2 ;;
    --verbose) verbose_mode=true; shift ;;
    *) shift ;;
  esac
done

: "${home_dir:=$HOME}"
: "${project_dir:=$(pwd)}"
# Default skill inventory: installed plugins under the home Claude dir.
: "${skills_dir:=${home_dir}/.claude/plugins}"

echo "=== USAGE TELEMETRY ==="

usage_issue_count=0
usage_status="OK"
usage_issues=""

# jq is required (shared convention with sibling check-*.sh scripts).
if ! command -v jq >/dev/null 2>&1; then
  echo "JQ_AVAILABLE=false"
  echo "STATUS=ERROR"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=ERROR TYPE=missing_tool MSG=jq is required but not installed"
  echo "=== END USAGE TELEMETRY ==="
  exit 1
fi
echo "JQ_AVAILABLE=true"
echo "WINDOW_DAYS=${window_days}"

projects_dir="${home_dir}/.claude/projects"

# --- Gather transcripts (prune .claude/worktrees clones, per #1492/#1548) -----
declare -a transcript_files=()
if [ -d "$projects_dir" ]; then
  while IFS= read -r tfile; do
    [ -n "$tfile" ] && transcript_files+=("$tfile")
  done < <(find "$projects_dir" -path '*/.claude/worktrees/*' -prune -o \
             -type f -name '*.jsonl' -print 2>/dev/null)
fi

transcripts_scanned=${#transcript_files[@]}
echo "TRANSCRIPTS_SCANNED=${transcripts_scanned}"

# --- SKIP when history is insufficient (fresh clone / remote sandbox) ---------
if [ ! -d "$projects_dir" ] || [ "$transcripts_scanned" -lt "$min_transcripts" ]; then
  echo "HISTORY_AVAILABLE=false"
  echo "STATUS=SKIP"
  echo "ISSUE_COUNT=0"
  echo "ISSUES:"
  echo "  - SEVERITY=INFO TYPE=insufficient_history MSG=fewer than ${min_transcripts} session transcripts under ${projects_dir} (usage telemetry needs a long-running local install; skipped)"
  echo "FIX_SUPPORTED=false"
  echo "=== END USAGE TELEMETRY ==="
  exit 0
fi
echo "HISTORY_AVAILABLE=true"

now_epoch=$(date +%s)
window_cutoff=$((now_epoch - window_days * 86400))

# --- Parse transcripts: skill tokens (with file mtime) + total tool_use count -
# fired_last_seen[token]=max_mtime_epoch ; fired_count[token]=N
declare -A fired_last_seen=()
declare -A fired_count=()
declare -a fired_tokens=()   # raw tokens for loose substring fallback
total_tool_use=0

file_mtime() {
  # GNU then BSD stat.
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# Normalize an invocation token to a comparable skill key:
# strip a leading '/', then take the segment after the last ':' or '/'.
normalize_token() {
  local tok="$1"
  tok="${tok#/}"
  tok="${tok##*:}"
  tok="${tok##*/}"
  printf '%s' "$tok"
}

for tfile in "${transcript_files[@]}"; do
  mtime=$(file_mtime "$tfile")
  # One jq pass per file: emit "SKILL<TAB>token" and "TOOL" marker lines.
  while IFS=$'\t' read -r kind token; do
    if [ "$kind" = "TOOL" ]; then
      total_tool_use=$((total_tool_use + 1))
    elif [ "$kind" = "SKILL" ]; then
      total_tool_use=$((total_tool_use + 1))
      key=$(normalize_token "$token")
      [ -z "$key" ] && continue
      fired_count["$key"]=$(( ${fired_count["$key"]:-0} + 1 ))
      prev=${fired_last_seen["$key"]:-0}
      if [ "$mtime" -gt "$prev" ]; then
        fired_last_seen["$key"]=$mtime
      fi
      case " ${fired_tokens[*]-} " in
        *" ${key} "*) ;;
        *) fired_tokens+=("$key") ;;
      esac
    fi
  done < <(jq -rc '
    select(.type=="assistant")
    | .message.content[]?
    | select(.type=="tool_use")
    | if .name=="Skill"
      then "SKILL\t" + ((.input.skill // .input.command // .input.name // "") | tostring)
      else "TOOL\t" + (.name | tostring)
      end
  ' "$tfile" 2>/dev/null)
done

echo "TOOL_USE_EVENTS=${total_tool_use}"

# --- Schema-drift sentinel ----------------------------------------------------
# A populated history with zero detectable tool_use events almost certainly
# means the transcript JSON shape changed under us, not that the user ran no
# tools across many sessions. Guarded by min_transcripts to avoid the
# genuine chat-only false positive on a tiny install.
if [ "$total_tool_use" -eq 0 ]; then
  echo "SCHEMA_DRIFT_SUSPECTED=true"
  echo "STATUS=WARN"
  echo "ISSUE_COUNT=1"
  echo "ISSUES:"
  echo "  - SEVERITY=WARN TYPE=schema_drift MSG=${transcripts_scanned} transcripts scanned but zero tool_use events parsed; transcript JSON shape may have changed (parser needs review)"
  echo "FIX_SUPPORTED=false"
  echo "=== END USAGE TELEMETRY ==="
  exit 0
fi
echo "SCHEMA_DRIFT_SUSPECTED=false"

# --- Discover enabled skill inventory -----------------------------------------
declare -a enabled_skills=()
if [ -d "$skills_dir" ]; then
  while IFS= read -r smd; do
    [ -n "$smd" ] || continue
    sdir=$(dirname "$smd")
    enabled_skills+=("$(basename "$sdir")")
  done < <(find "$skills_dir" -path '*/.claude/worktrees/*' -prune -o \
             -type f \( -name 'SKILL.md' -o -name 'skill.md' \) -print 2>/dev/null)
fi

skills_enabled=${#enabled_skills[@]}
echo "SKILLS_ENABLED=${skills_enabled}"

# Build a lookup of fired keys for exact + substring matching.
skill_is_fired() {
  local sk="$1"
  # exact normalized-key hit
  if [ -n "${fired_last_seen[$sk]+x}" ]; then
    printf '%s' "${fired_last_seen[$sk]}"
    return 0
  fi
  # loose fallback: any fired token contained in the skill name or vice versa.
  # Bias toward "fired" so a never-fired list never over-reports (ADR-0018).
  local tok
  for tok in "${fired_tokens[@]}"; do
    case "$sk" in *"$tok"*) printf '%s' "${fired_last_seen[$tok]}"; return 0 ;; esac
    case "$tok" in *"$sk"*) printf '%s' "${fired_last_seen[$tok]}"; return 0 ;; esac
  done
  return 1
}

skills_fired=0
skills_never=0
skills_dormant=0
never_list=""
dormant_list=""

if [ "$skills_enabled" -gt 0 ]; then
  for sk in "${enabled_skills[@]}"; do
    if last_seen=$(skill_is_fired "$sk"); then
      skills_fired=$((skills_fired + 1))
      if [ "${last_seen:-0}" -lt "$window_cutoff" ]; then
        skills_dormant=$((skills_dormant + 1))
        dormant_list="${dormant_list}${sk} "
      fi
    else
      skills_never=$((skills_never + 1))
      never_list="${never_list}${sk} "
    fi
  done
fi

echo "SKILLS_FIRED=${skills_fired}"
echo "SKILLS_NEVER_FIRED=${skills_never}"
echo "SKILLS_DORMANT=${skills_dormant}"

# --- Roll up issues (advisory; read-only audit) -------------------------------
if [ "$skills_enabled" -eq 0 ]; then
  usage_issues="${usage_issues}  - SEVERITY=INFO TYPE=no_skill_inventory MSG=no SKILL.md files found under ${skills_dir} (cannot compute never-fired without an inventory)\n"
  [ "$usage_status" = "OK" ] && usage_status="WARN"
  usage_issue_count=$((usage_issue_count + 1))
fi

if [ "$skills_never" -gt 0 ]; then
  usage_issue_count=$((usage_issue_count + 1))
  [ "$usage_status" = "OK" ] && usage_status="WARN"
  if [ "$verbose_mode" = true ]; then
    usage_issues="${usage_issues}  - SEVERITY=WARN TYPE=never_fired COUNT=${skills_never} SKILLS=${never_list% }\n"
  else
    usage_issues="${usage_issues}  - SEVERITY=WARN TYPE=never_fired COUNT=${skills_never} MSG=enabled skills with zero invocations in history (advisory review candidates; use --verbose to list)\n"
  fi
fi

if [ "$skills_dormant" -gt 0 ]; then
  usage_issue_count=$((usage_issue_count + 1))
  [ "$usage_status" = "OK" ] && usage_status="WARN"
  if [ "$verbose_mode" = true ]; then
    usage_issues="${usage_issues}  - SEVERITY=WARN TYPE=dormant COUNT=${skills_dormant} SKILLS=${dormant_list% }\n"
  else
    usage_issues="${usage_issues}  - SEVERITY=WARN TYPE=dormant COUNT=${skills_dormant} MSG=skills not invoked in ${window_days}+ days (advisory; use --verbose to list)\n"
  fi
fi

echo "STATUS=${usage_status}"
echo "ISSUE_COUNT=${usage_issue_count}"
if [ -n "$usage_issues" ]; then
  echo "ISSUES:"
  echo -e "$usage_issues" | sed '/^$/d'
fi
echo "FIX_SUPPORTED=false"
echo "=== END USAGE TELEMETRY ==="
