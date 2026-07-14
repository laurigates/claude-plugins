#!/usr/bin/env bash
# Distill Survey — read-only collector for session-distill (the distill-side
# analogue of session-survey.sh). Mines the local session-transcript JSONL for
# RECIPE CANDIDATES, HOT FILES, and COMMAND / COMMIT groupings so the LLM judges
# instead of re-reading the whole conversation and re-running `just --dump` from
# memory.
#
# READ-ONLY by contract: extraction only. All writes and all *judgment*
# (naming a sequence, deciding a rule) stay in the invoking skill — the script
# emits a digest + groupings; it never infers a process or a rule.
#
# Emits structured KEY=VALUE sections (see .claude/rules/structured-script-output.md)
# and is exit-0 on empty (.claude/rules/parallel-safe-queries.md).
#
# Usage:
#   bash distill-survey.sh --session-id <id> [--project-dir <path>]
#       [--home-dir <path>] [--window-sessions N] [--window-days N]
#       [--min-sessions N] [--summary]
#
# Signals (why these, not raw within-session frequency):
#   - cross-session recurrence: a novel command recurring across SEPARATE
#     sessions is a durable workflow, not TDD/debug thrash
#   - commit-bracketing: commands in the interval terminated by `git commit`
#     are a completed unit of work
#   - novelty vs `just --dump`: don't propose a recipe that already exists
#
# Graceful degradation (mirrors health-plugin's check-usage.sh): projects dir
# missing / this session's transcript not found / fewer than --min-sessions
# transcripts → TRANSCRIPT_AVAILABLE=false + STATUS=SKIP + zeroed sections, so
# session-distill falls back to its LLM-re-read behaviour.
set -u

project_dir=""
home_dir=""
session_id=""
window_sessions=10
window_days=""
min_sessions=1
summary_mode=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) project_dir="$2"; shift 2 ;;
    --home-dir) home_dir="$2"; shift 2 ;;
    --session-id) session_id="$2"; shift 2 ;;
    --window-sessions) window_sessions="$2"; shift 2 ;;
    --window-days) window_days="$2"; shift 2 ;;
    --min-sessions) min_sessions="$2"; shift 2 ;;
    --summary) summary_mode=true; shift ;;
    --verbose) shift ;;
    *) shift ;;
  esac
done

: "${project_dir:=$(pwd)}"
: "${home_dir:=$HOME}"

# Test seams — override the transcripts dir and the `just` binary so tests can
# stub them (mirrors session-survey.sh's SESSION_SURVEY_*_BIN convention).
projects_dir="${DISTILL_SURVEY_PROJECTS_DIR:-${home_dir}/.claude/projects}"
just_bin="${DISTILL_SURVEY_JUST_BIN:-just}"

# Output caps (never silent — a TRUNCATED= line is emitted when a cap bites).
MAX_CANDIDATES=40
MAX_DIGEST=50
MAX_INTERVALS=25
MAX_INTERVAL_CMDS=20
MAX_HOTFILES=30

have() { command -v "$1" >/dev/null 2>&1; }

file_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# ---------------------------------------------------------------------------
# Project name (mechanical): git repo-root basename, else project_dir basename.
# ---------------------------------------------------------------------------
project=""
if have git && git -C "$project_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  root=$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || echo "")
  [ -n "$root" ] && project=$(basename "$root")
fi
[ -n "$project" ] || project=$(basename "$project_dir")

# ---------------------------------------------------------------------------
# Locate this session's transcript, then its project dir (all sessions of this
# project share one slug dir). Prune .claude/worktrees clones (#1492/#1548).
# ---------------------------------------------------------------------------
session_file=""
if [ -n "$session_id" ] && [ -d "$projects_dir" ] && have jq; then
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    session_file="$cand"; break
  done < <(find "$projects_dir" -path '*/.claude/worktrees/*' -prune -o \
             -type f -name "${session_id}.jsonl" -print 2>/dev/null)
fi

session_dir=""
[ -n "$session_file" ] && session_dir=$(dirname "$session_file")

# Window transcripts (same project dir), newest first by mtime.
declare -a WINDOW_FILES=()
sessions_scanned=0
if [ -n "$session_dir" ]; then
  declare -a all_tx=()
  while IFS= read -r f; do
    [ -n "$f" ] && all_tx+=("$f")
  done < <(find "$session_dir" -maxdepth 1 -type f -name '*.jsonl' -print 2>/dev/null)
  sessions_scanned=${#all_tx[@]}
  # decorate-sort-undecorate by mtime desc
  declare -a sorted=()
  while IFS= read -r f; do
    [ -n "$f" ] && sorted+=("$f")
  done < <(
    for f in "${all_tx[@]}"; do printf '%s\t%s\n' "$(file_mtime "$f")" "$f"; done | sort -rn | cut -f2-
  )
  if [ -n "$window_days" ]; then
    cutoff=$(( $(date +%s) - window_days * 86400 ))
    for f in "${sorted[@]}"; do
      [ "$(file_mtime "$f")" -ge "$cutoff" ] 2>/dev/null && WINDOW_FILES+=("$f")
    done
  else
    n=0
    for f in "${sorted[@]}"; do
      WINDOW_FILES+=("$f"); n=$((n + 1))
      [ "$n" -ge "$window_sessions" ] && break
    done
  fi
  # Always include the current session even if the window filter excluded it.
  found=false
  for f in "${WINDOW_FILES[@]:-}"; do [ "$f" = "$session_file" ] && found=true; done
  [ "$found" = false ] && WINDOW_FILES+=("$session_file")
fi

# ---------------------------------------------------------------------------
# Availability gate.
# ---------------------------------------------------------------------------
available=true
skip_reason=""
if ! have jq; then available=false; skip_reason="jq not installed"; fi
if [ -z "$session_id" ]; then available=false; skip_reason="no --session-id given"; fi
if [ ! -d "$projects_dir" ]; then available=false; skip_reason="projects dir absent (${projects_dir})"; fi
if [ -z "$session_file" ]; then available=false; skip_reason="this session's transcript not found under ${projects_dir}"; fi
if [ "$available" = true ] && [ "$sessions_scanned" -lt "$min_sessions" ]; then
  available=false; skip_reason="fewer than ${min_sessions} transcripts in the project dir"
fi

window_desc="sessions=${window_sessions}"
[ -n "$window_days" ] && window_desc="days=${window_days}"

emit_skip() {
  if [ "$summary_mode" = true ]; then
    echo "=== DISTILL SURVEY SUMMARY ==="
    echo "PROJECT=${project}"
    echo "SESSION_ID=${session_id}"
    echo "TRANSCRIPT_AVAILABLE=false"
    echo "RECIPE_CANDIDATE_COUNT=0"
    echo "HOT_FILE_COUNT=0"
    echo "PROCESS_SIGNAL=0"
    echo "STATUS=SKIP"
    echo "ISSUE_COUNT=0"
    echo "=== END DISTILL SURVEY SUMMARY ==="
    return
  fi
  echo "=== SESSION_META ==="
  echo "PROJECT=${project}"
  echo "SESSION_ID=${session_id}"
  echo "TRANSCRIPT_AVAILABLE=false"
  echo "SESSIONS_SCANNED=${sessions_scanned}"
  echo "WINDOW=${window_desc}"
  echo "SKIP_REASON=${skip_reason}"
  echo "STATUS=SKIP"
  echo "ISSUE_COUNT=0"
  echo "=== END SESSION_META ==="
  for sec in RECIPE_CANDIDATES HOT_FILES COMMIT_INTERVALS COMMAND_DIGEST; do
    echo "=== ${sec} ==="
    echo "COUNT=0"
    echo "STATUS=SKIP"
    echo "=== END ${sec} ==="
  done
  echo "=== RULE_HINTS_FROM_TOOLING ==="
  echo "RULES_SIGNAL=none_mechanical"
  echo "STATUS=SKIP"
  echo "=== END RULE_HINTS_FROM_TOOLING ==="
}

if [ "$available" = false ]; then
  emit_skip
  exit 0
fi

# ---------------------------------------------------------------------------
# Extraction + normalization.
#
# extract_norm_raw <file> emits, one per line, "<normalized>\t<raw>" for every
# Bash command in the transcript, in order. Normalization is deliberately lossy
# (quoted strings → <str>, path-tokens → <path>, bare numbers → <n>); the raw
# example is preserved so the LLM can refine.
# ---------------------------------------------------------------------------
extract_norm_raw() {
  jq -r '
    select(.type=="assistant")
    | .message.content[]?
    | select(.type=="tool_use" and .name=="Bash")
    | (.input.command // "")
    | select(. != "")
    | gsub("[\r\n]+"; " ")
  ' "$1" 2>/dev/null | awk '
    BEGIN { sq = sprintf("%c", 39) }   # single quote, portably (no \x27)
    {
      raw = $0
      work = $0
      gsub(/"[^"]*"/, "<str>", work)
      gsub(sq "[^" sq "]*" sq, "<str>", work)
      n = split(work, t, /[ \t]+/)
      out = ""
      for (i = 1; i <= n; i++) {
        tok = t[i]
        if (tok == "") continue
        if (tok ~ /\//) tok = "<path>"
        else if (tok ~ /^[0-9]+(\.[0-9]+)?$/) tok = "<n>"
        out = (out == "" ? tok : out " " tok)
      }
      if (out == "") next
      print out "\t" raw
    }'
}

is_commit() { case "$1" in *"git commit"*) return 0 ;; *) return 1 ;; esac; }

# Churn denylist (fixed by design): base command OR its first subcommand token.
CHURN_DENYLIST=" status diff log test build ls cd pwd cat "
is_churn() {
  local n="$1" first second rest
  first=${n%% *}
  rest=${n#* }
  if [ "$rest" = "$n" ]; then second=""; else second=${rest%% *}; fi
  case "$CHURN_DENYLIST" in *" $first "*|*" $second "*) return 0 ;; esac
  return 1
}

novel_tokens() {
  local -a toks; read -ra toks <<< "$1"
  local out="" tok
  for tok in "${toks[@]}"; do
    case "$tok" in "<str>"|"<path>"|"<n>") continue ;; esac
    out="${out:+$out,}$tok"
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# Window pass — per-session distinct normalized-command sets → cross-session
# recurrence counts, plus a first-raw example per normalized command.
# ---------------------------------------------------------------------------
declare -A win_sessions=()   # norm -> distinct-file count
declare -A win_first=()      # norm -> first raw example seen anywhere in window
for f in "${WINDOW_FILES[@]}"; do
  declare -A seen_here=()
  while IFS=$'\t' read -r norm raw; do
    [ -n "$norm" ] || continue
    [ -n "${win_first[$norm]+x}" ] || win_first["$norm"]="$raw"
    if [ -z "${seen_here[$norm]+x}" ]; then
      seen_here["$norm"]=1
      win_sessions["$norm"]=$(( ${win_sessions[$norm]:-0} + 1 ))
    fi
  done < <(extract_norm_raw "$f")
  unset seen_here
done

# ---------------------------------------------------------------------------
# This-session pass — ordered arrays for digest / commit intervals / bracket.
# ---------------------------------------------------------------------------
declare -a RAW=() NORM=()
while IFS=$'\t' read -r norm raw; do
  [ -n "$norm" ] || continue
  NORM+=("$norm"); RAW+=("$raw")
done < <(extract_norm_raw "$session_file")

total_cmds=${#NORM[@]}

# Ordered-unique + this-session counts.
declare -A sess_count=()
declare -a sess_order=()
for norm in "${NORM[@]:-}"; do
  [ -n "$norm" ] || continue
  if [ -z "${sess_count[$norm]+x}" ]; then sess_order+=("$norm"); fi
  sess_count["$norm"]=$(( ${sess_count[$norm]:-0} + 1 ))
done
unique_cmds=${#sess_order[@]}

# Commit intervals + commit-bracketed set (any command in an interval that is
# terminated by a git commit — a completed unit of work).
last_commit_idx=-1
for ((i = 0; i < total_cmds; i++)); do
  is_commit "${RAW[$i]}" && last_commit_idx=$i
done
declare -A bracketed=()
if [ "$last_commit_idx" -ge 0 ]; then
  for ((i = 0; i <= last_commit_idx; i++)); do
    is_commit "${RAW[$i]}" && continue   # the delimiter itself isn't a candidate
    bracketed["${NORM[$i]}"]=1
  done
fi

# ---------------------------------------------------------------------------
# `just --dump` coverage set (novelty vs existing recipes).
# ---------------------------------------------------------------------------
declare -A covered=()
just_available=false
just_recipe_count=0
has_justfile=false
for jf in justfile Justfile "$project_dir/justfile" "$project_dir/Justfile"; do
  [ -f "$jf" ] && has_justfile=true && break
done
if [ "$has_justfile" = true ] && have "$just_bin"; then
  just_dump=$( (cd "$project_dir" && "$just_bin" --dump --dump-format json) 2>/dev/null || echo "")
  if [ -n "$just_dump" ]; then
    just_available=true
    # recipe names → "just <name>" covered
    while IFS= read -r rname; do
      [ -n "$rname" ] || continue
      just_recipe_count=$((just_recipe_count + 1))
      covered["just $rname"]=1
    done < <(printf '%s' "$just_dump" | jq -r '.recipes | keys[]?' 2>/dev/null)
    # recipe body lines → normalized covered commands
    while IFS=$'\t' read -r norm _raw; do
      [ -n "$norm" ] || continue
      covered["$norm"]=1
    done < <(
      printf '%s' "$just_dump" \
        | jq -r '.recipes[]?.body[]? | map(if type=="string" then . else (.text // "") end) | join("")' 2>/dev/null \
        | awk '
            BEGIN { sq = sprintf("%c", 39) }
            {
              raw = $0; work = $0
              gsub(/"[^"]*"/, "<str>", work)
              gsub(sq "[^" sq "]*" sq, "<str>", work)
              n = split(work, t, /[ \t]+/); out = ""
              for (i = 1; i <= n; i++) { tok = t[i]; if (tok == "") continue
                if (tok ~ /\//) tok = "<path>"; else if (tok ~ /^[0-9]+(\.[0-9]+)?$/) tok = "<n>"
                out = (out == "" ? tok : out " " tok) }
              if (out != "") print out "\t" raw
            }'
    )
  fi
fi

# ---------------------------------------------------------------------------
# Build RECIPE_CANDIDATES.
# ---------------------------------------------------------------------------
declare -a cand_lines=()   # sortkey<TAB>norm<TAB>sessions<TAB>bracket
for norm in "${sess_order[@]:-}"; do
  [ -n "$norm" ] || continue
  is_churn "$norm" && continue
  [ -n "${covered[$norm]+x}" ] && continue
  sess_n=${win_sessions[$norm]:-1}
  brk=no; [ -n "${bracketed[$norm]+x}" ] && brk=yes
  if [ "$sess_n" -ge 2 ] || [ "$brk" = yes ]; then
    printf -v key '%03d%03d' "$sess_n" "${sess_count[$norm]:-0}"
    cand_lines+=("${key}"$'\t'"${norm}"$'\t'"${sess_n}"$'\t'"${brk}")
  fi
done

# ---------------------------------------------------------------------------
# HOT_FILES — files Edit/Write'd ≥3× this session (exact filePath).
# op: create→write, update→edit.
# ---------------------------------------------------------------------------
declare -A hot_total=() hot_edit=() hot_write=()
declare -a hot_order=()
while IFS=$'\t' read -r fpath op; do
  [ -n "$fpath" ] || continue
  case "$op" in update) k="edit" ;; create) k="write" ;; *) k="write" ;; esac
  if [ -z "${hot_total[$fpath]+x}" ]; then hot_order+=("$fpath"); fi
  hot_total["$fpath"]=$(( ${hot_total[$fpath]:-0} + 1 ))
  if [ "$k" = edit ]; then hot_edit["$fpath"]=$(( ${hot_edit[$fpath]:-0} + 1 ))
  else hot_write["$fpath"]=$(( ${hot_write[$fpath]:-0} + 1 )); fi
done < <(
  jq -r '
    select(.toolUseResult != null)
    | .toolUseResult
    | select(type == "object")
    | select(.filePath != null)
    | [.filePath, (.type // "write")] | @tsv
  ' "$session_file" 2>/dev/null
)

# ---------------------------------------------------------------------------
# RULE_HINTS_FROM_TOOLING — repeated permission/auth denials only.
# ---------------------------------------------------------------------------
declare -A denial_count=()
declare -a denial_order=()
while IFS= read -r kind; do
  [ -n "$kind" ] || continue
  if [ -z "${denial_count[$kind]+x}" ]; then denial_order+=("$kind"); fi
  denial_count["$kind"]=$(( ${denial_count[$kind]:-0} + 1 ))
done < <(jq -r 'select(.toolDenialKind != null) | .toolDenialKind' "$session_file" 2>/dev/null)

max_denial=0
for kind in "${denial_order[@]:-}"; do
  [ -n "$kind" ] || continue
  [ "${denial_count[$kind]}" -gt "$max_denial" ] && max_denial=${denial_count[$kind]}
done

# process signal = commit-terminated intervals with ≥3 distinct non-churn cmds
process_signal=0

# ---------------------------------------------------------------------------
# Summary mode.
# ---------------------------------------------------------------------------
if [ "$summary_mode" = true ]; then
  # count qualifying intervals (mirrors the COMMIT_INTERVALS emit below)
  cur=0; declare -A cur_seen=()
  for ((i = 0; i < total_cmds; i++)); do
    if is_commit "${RAW[$i]}"; then
      [ "$cur" -ge 3 ] && process_signal=$((process_signal + 1))
      cur=0; unset cur_seen; declare -A cur_seen=()
    else
      n="${NORM[$i]}"
      if ! is_churn "$n" && [ -z "${cur_seen[$n]+x}" ]; then cur_seen["$n"]=1; cur=$((cur + 1)); fi
    fi
  done
  hot_count=0
  for f in "${hot_order[@]:-}"; do [ -n "$f" ] && [ "${hot_total[$f]}" -ge 3 ] && hot_count=$((hot_count + 1)); done
  echo "=== DISTILL SURVEY SUMMARY ==="
  echo "PROJECT=${project}"
  echo "SESSION_ID=${session_id}"
  echo "TRANSCRIPT_AVAILABLE=true"
  echo "RECIPE_CANDIDATE_COUNT=${#cand_lines[@]}"
  echo "HOT_FILE_COUNT=${hot_count}"
  echo "PROCESS_SIGNAL=${process_signal}"
  echo "STATUS=OK"
  echo "ISSUE_COUNT=0"
  echo "=== END DISTILL SURVEY SUMMARY ==="
  exit 0
fi

# ---------------------------------------------------------------------------
# Full digest.
# ---------------------------------------------------------------------------
echo "=== SESSION_META ==="
echo "PROJECT=${project}"
echo "SESSION_ID=${session_id}"
echo "TRANSCRIPT_AVAILABLE=true"
echo "SESSIONS_SCANNED=${sessions_scanned}"
echo "WINDOW=${window_desc}"
echo "JUST_AVAILABLE=${just_available}"
echo "JUST_RECIPE_COUNT=${just_recipe_count}"
echo "TOTAL_BASH_CMDS=${total_cmds}"
echo "UNIQUE_BASH_CMDS=${unique_cmds}"
echo "STATUS=OK"
echo "ISSUE_COUNT=0"
echo "=== END SESSION_META ==="

echo "=== RECIPE_CANDIDATES ==="
echo "COUNT=${#cand_lines[@]}"
idx=0
if [ "${#cand_lines[@]}" -gt 0 ]; then
  while IFS=$'\t' read -r _key norm sess_n brk; do
    idx=$((idx + 1))
    [ "$idx" -gt "$MAX_CANDIDATES" ] && { echo "TRUNCATED=${#cand_lines[@]} candidates, showing ${MAX_CANDIDATES}"; break; }
    echo "CANDIDATE_${idx}=${norm}"
    echo "CANDIDATE_${idx}_SESSIONS=${sess_n}"
    echo "CANDIDATE_${idx}_BRACKETED=${brk}"
    echo "CANDIDATE_${idx}_NOVEL_TOKENS=$(novel_tokens "$norm")"
    echo "CANDIDATE_${idx}_FIRST=${win_first[$norm]:-}"
  done < <(printf '%s\n' "${cand_lines[@]}" | sort -rn)
fi
echo "STATUS=OK"
echo "=== END RECIPE_CANDIDATES ==="

echo "=== HOT_FILES ==="
hot_count=0
declare -a hot_emit=()
for f in "${hot_order[@]:-}"; do
  [ -n "$f" ] || continue
  [ "${hot_total[$f]}" -ge 3 ] || continue
  hot_emit+=("${hot_total[$f]}"$'\t'"$f")
done
echo "COUNT=${#hot_emit[@]}"
idx=0
if [ "${#hot_emit[@]}" -gt 0 ]; then
  while IFS=$'\t' read -r tot f; do
    idx=$((idx + 1))
    [ "$idx" -gt "$MAX_HOTFILES" ] && { echo "TRUNCATED=${#hot_emit[@]} hot files, showing ${MAX_HOTFILES}"; break; }
    echo "HOT_${idx}_FILE=${f}"
    echo "HOT_${idx}_TOTAL=${tot}"
    echo "HOT_${idx}_EDITS=${hot_edit[$f]:-0}"
    echo "HOT_${idx}_WRITES=${hot_write[$f]:-0}"
  done < <(printf '%s\n' "${hot_emit[@]}" | sort -rn)
fi
echo "STATUS=OK"
echo "=== END HOT_FILES ==="

echo "=== COMMIT_INTERVALS ==="
interval=0
declare -a cur_cmds=()
declare -A cur_seen=()
emit_interval() {  # $1 = ended_by
  interval=$((interval + 1))
  local joined="" c count=0 truncated=""
  for c in "${cur_cmds[@]:-}"; do
    [ -n "$c" ] || continue
    count=$((count + 1))
    [ "$count" -gt "$MAX_INTERVAL_CMDS" ] && { truncated=" (+more)"; break; }
    joined="${joined:+$joined | }$c"
  done
  echo "INTERVAL_${interval}_ENDED_BY=$1"
  echo "INTERVAL_${interval}_CMD_COUNT=${#cur_cmds[@]}"
  echo "INTERVAL_${interval}_CMDS=${joined}${truncated}"
  [ "$1" = commit ] && [ "${#cur_cmds[@]}" -ge 3 ] && process_signal=$((process_signal + 1))
}
for ((i = 0; i < total_cmds; i++)); do
  [ "$interval" -ge "$MAX_INTERVALS" ] && { echo "TRUNCATED=more than ${MAX_INTERVALS} commit intervals"; break; }
  n="${NORM[$i]}"
  if is_commit "${RAW[$i]}"; then
    emit_interval commit
    cur_cmds=(); unset cur_seen; declare -A cur_seen=()
  else
    if is_churn "$n"; then continue; fi
    if [ -z "${cur_seen[$n]+x}" ]; then cur_seen["$n"]=1; cur_cmds+=("$n"); fi
  fi
done
# trailing (open) interval, if it has content and we didn't truncate
if [ "$interval" -lt "$MAX_INTERVALS" ] && [ "${#cur_cmds[@]}" -gt 0 ]; then
  emit_interval none
fi
echo "INTERVAL_COUNT=${interval}"
echo "PROCESS_SIGNAL=${process_signal}"
echo "STATUS=OK"
echo "=== END COMMIT_INTERVALS ==="

echo "=== COMMAND_DIGEST ==="
echo "COUNT=${unique_cmds}"
idx=0
for norm in "${sess_order[@]:-}"; do
  [ -n "$norm" ] || continue
  idx=$((idx + 1))
  if [ "$idx" -gt "$MAX_DIGEST" ]; then echo "TRUNCATED=${unique_cmds} unique commands, showing ${MAX_DIGEST}"; break; fi
  echo "CMD_${idx}=${norm}"
  echo "CMD_${idx}_COUNT=${sess_count[$norm]}"
done
echo "STATUS=OK"
echo "=== END COMMAND_DIGEST ==="

echo "=== RULE_HINTS_FROM_TOOLING ==="
total_denials=0
for kind in "${denial_order[@]:-}"; do [ -n "$kind" ] && total_denials=$((total_denials + denial_count[$kind])); done
if [ "$max_denial" -ge 2 ]; then
  echo "RULES_SIGNAL=denials"
else
  echo "RULES_SIGNAL=none_mechanical"
fi
echo "DENIAL_TOTAL=${total_denials}"
for kind in "${denial_order[@]:-}"; do
  [ -n "$kind" ] || continue
  echo "DENIAL_${kind}=${denial_count[$kind]}"
done
echo "STATUS=OK"
echo "=== END RULE_HINTS_FROM_TOOLING ==="
