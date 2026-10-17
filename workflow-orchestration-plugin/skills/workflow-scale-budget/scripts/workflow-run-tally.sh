#!/usr/bin/env bash
# Tally one finished Workflow run (or every run in a session) from its local
# subagent transcripts: agents spawned, and tokens by class.
#
# Substrate: <projects>/<slug>/<session>/subagents/workflows/<wf_run>/ holds one
# agent-<id>.jsonl transcript per agent and a journal.jsonl whose launched /
# started / result lines are keyed by agentId. The harness also writes a run
# summary at <projects>/<slug>/<session>/workflows/<wf_run>.json. This script reads
# only its `status` field, to tell a finished run from a live one. It never reads
# totalTokens: that is roughly each agent's final context size, not spend, so the
# transcript sum below stays the cost figure.
#
# Usage:
#   workflow-run-tally.sh <wf_run_id | session_id> [--projects-dir DIR]
#
# DIR defaults to $WORKFLOW_RUN_TALLY_PROJECTS_DIR, then $HOME/.claude/projects.
# A run id resolves to <DIR>/*/*/subagents/workflows/<run>; a session id resolves
# to every <DIR>/*/<session>/subagents/workflows/wf_* directory, one block each,
# then one session total (see the output notes below).
#
# Usage dedupe (the load-bearing step): one API message is written as several
# assistant lines sharing message.id, and output_tokens grows across them. The
# LAST line per (agent file, message.id) is kept. Summing every line overstates
# cache tokens severalfold, so the dedupe is not optional.
#
# Output follows .claude/rules/structured-script-output.md: one
# "=== WORKFLOW RUN TALLY ===" block per run. For a session id, one
# "=== WORKFLOW SESSION TALLY ===" block follows the run blocks: AGENTS_STARTED and
# TOKENS_* summed over the runs (unknown if any run's value is unknown), RUNS, and
# the worst run STATUS. Exit 0 on OK or WARN, 1 on ERROR (no run found), 2 on a
# usage error.
#
# A live run is not an error: agents still in flight keep STATUS=OK. A summary that
# says the run has finished (killed, failed, completed) turns agents with no result
# into a WARN (agents_without_result). An agent transcript with no usage line yet,
# or with a non-integer usage value, is a WARN, excluded from TOKENS_* and never
# counted as zero. A journal whose started count differs from the transcripts found
# is a WARN in either direction: fewer transcripts than started means TOKENS_* cover
# fewer agents; more transcripts means the journal is short. A journal result count
# above its started count is a WARN too (result_exceeds_started). A journal with no
# parseable JSON line is unknown, never a started count of zero. A parseable journal
# that shows no agent started proves zero tokens, so that run is OK.
set -uo pipefail
shopt -s nullglob

usage() {
  echo "usage: workflow-run-tally.sh <wf_run_id | session_id> [--projects-dir DIR]" >&2
  exit 2
}

target=""
projects_dir="${WORKFLOW_RUN_TALLY_PROJECTS_DIR:-${HOME:-}/.claude/projects}"
while [ $# -gt 0 ]; do
  case "$1" in
    --projects-dir)
      [ $# -ge 2 ] || usage
      projects_dir="$2"
      shift 2
      ;;
    -*) usage ;;
    *)
      [ -z "$target" ] || usage
      target="$1"
      shift
      ;;
  esac
done
[ -n "$target" ] || usage
case "$target" in
  *[!A-Za-z0-9_-]*)
    echo "workflow-run-tally: target must be a run or session id ([A-Za-z0-9_-]+): $target" >&2
    exit 2
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  echo "workflow-run-tally: jq is required" >&2
  exit 1
fi

# One transcript -> one TSV row: lines, distinct messages, input_tokens,
# output_tokens, cache_creation_input_tokens, cache_read_input_tokens. Lines
# that do not parse are skipped, since a live run may be mid-write on its last
# line. The reduce assignment overwrites per message id, and inputs arrive in
# file order, so the last line for each message id is the one kept.
# The top-level cache fields are read, never cache_creation.ephemeral_*, which
# already sum to the top-level figure.
# shellcheck disable=SC2016  # a jq program: $l and $k are jq variables, not shell
USAGE_JQ='
  reduce (inputs
          | fromjson?
          | select(type == "object" and .type == "assistant"
                   and ((.message.usage // null) | type) == "object")) as $l
    ({lines: 0, msgs: {}};
     ($l.message.id // $l.uuid // ("no-id-" + ((.lines + 1) | tostring))) as $k
     | .lines += 1
     | .msgs[$k] = $l.message.usage)
  | [ .lines,
      (.msgs | length),
      ([.msgs[] | (.input_tokens // 0)] | add // 0),
      ([.msgs[] | (.output_tokens // 0)] | add // 0),
      ([.msgs[] | (.cache_creation_input_tokens // 0)] | add // 0),
      ([.msgs[] | (.cache_read_input_tokens // 0)] | add // 0) ]
  | @tsv'

issue_sev=()
issue_type=()
issue_msg=()
# Per-run figures for the session tally, appended by tally_run in run order.
sess_names=()
sess_status=()
sess_reason=()
sess_started=()
sess_in=()
sess_out=()
sess_cw=()
sess_cr=()

add_issue() { # SEVERITY TYPE MSG
  issue_sev+=("$1")
  issue_type+=("$2")
  issue_msg+=("$3")
}

# reason_for SEVERITY — the REASON value: the first finding at that severity as
# "<TYPE>: <MSG>", cut to 180 characters, plus " (+N more)" when others follow.
reason_for() {
  local want="$1" i first="" more=0 text
  for i in "${!issue_sev[@]}"; do
    [ "${issue_sev[$i]}" = "$want" ] || continue
    if [ -z "$first" ]; then
      first="${issue_type[$i]}: ${issue_msg[$i]}"
    else
      more=$((more + 1))
    fi
  done
  text="${first:0:180}"
  if [ "$more" -gt 0 ]; then text="$text (+$more more)"; fi
  printf '%s' "$text"
}

# print_issues — one ISSUES row per recorded finding of the current block.
print_issues() {
  local i
  for i in "${!issue_sev[@]}"; do
    echo "  - SEVERITY=${issue_sev[$i]} TYPE=${issue_type[$i]} MSG=${issue_msg[$i]}"
  done
}

# is_count VALUE... — succeeds only when every VALUE is a non-negative integer.
is_count() {
  local v
  for v in "$@"; do
    [[ $v =~ ^[0-9]+$ ]] || return 1
  done
}

# sum_values VALUE... — the sum of the integer VALUEs, or unknown if any is unknown.
sum_values() {
  local v total=0
  for v in "$@"; do
    if [ "$v" = unknown ]; then
      echo unknown
      return 0
    fi
    total=$((total + v))
  done
  echo "$total"
}

# tally_run RUN_DIR — print one structured block for a found run, and keep its
# figures for the session tally.
tally_run() {
  local run_dir="$1"
  local run_name session_dir session_name
  run_name=$(basename "$run_dir")
  session_dir=$(dirname "$(dirname "$(dirname "$run_dir")")")
  session_name=$(basename "$session_dir")

  issue_sev=()
  issue_type=()
  issue_msg=()

  # Journal: started / result line counts. Missing or unreadable -> unknown. A journal
  # with no parseable JSON object line is unknown too, so an empty or all-garbage file
  # never reads as "no agent started".
  local journal="$run_dir/journal.jsonl" j_row j_lines="" j_started="" j_result=""
  if [ -f "$journal" ]; then
    if j_row=$(jq -r -R -n '
        [inputs | fromjson? | select(type == "object") | .type] as $t
        | [($t | length),
           ($t | map(select(. == "started")) | length),
           ($t | map(select(. == "result")) | length)]
        | @tsv' "$journal" 2>/dev/null); then
      IFS=$'\t' read -r j_lines j_started j_result <<<"$j_row"
      if [ "${j_lines:-0}" -eq 0 ]; then
        j_started=""
        j_result=""
        add_issue WARN journal_unreadable "journal.jsonl has no parseable JSON line; journal fields print unknown"
      fi
    else
      add_issue WARN journal_unreadable "journal.jsonl could not be parsed; journal fields print unknown"
    fi
  fi

  # Transcripts: one usage row per agent, deduplicated per message id.
  local -a transcripts=( "$run_dir"/agent-*.jsonl )
  local agents_transcripts=${#transcripts[@]}
  local agents_usage=0 msgs=0 dups=0 tok_in=0 tok_out=0 tok_cw=0 tok_cr=0
  local f base row lines distinct i o cw cr
  for f in "${transcripts[@]}"; do
    base=$(basename "$f")
    if ! row=$(jq -r -R -n "$USAGE_JQ" "$f" 2>/dev/null); then
      add_issue WARN transcript_unreadable "$base could not be read; excluded from TOKENS_*"
      continue
    fi
    IFS=$'\t' read -r lines distinct i o cw cr <<<"$row"
    # A fractional or otherwise non-integer usage value must not reach the arithmetic
    # below: bash aborts the run mid-loop with exit 0 and prints no block.
    if ! is_count "$lines" "$distinct" "$i" "$o" "$cw" "$cr"; then
      add_issue WARN transcript_unreadable "$base has a non-integer usage value; excluded from TOKENS_*"
      continue
    fi
    if [ "$lines" -eq 0 ]; then
      add_issue WARN no_usage "$base has no assistant usage line; excluded from TOKENS_* (not counted as 0)"
      continue
    fi
    agents_usage=$((agents_usage + 1))
    msgs=$((msgs + distinct))
    dups=$((dups + lines - distinct))
    tok_in=$((tok_in + i))
    tok_out=$((tok_out + o))
    tok_cw=$((tok_cw + cw))
    tok_cr=$((tok_cr + cr))
  done
  # A readable journal that shows no agent started proves zero tokens, so that run is
  # OK. Without such a journal, no transcripts means unknown, never a silent zero.
  local journal_zero=false
  if [ -n "$j_started" ] && [ "$j_started" -eq 0 ]; then journal_zero=true; fi
  if [ "$agents_transcripts" -eq 0 ] && [ "$journal_zero" = false ]; then
    add_issue WARN no_transcripts "no agent-*.jsonl transcripts in this run directory; tokens print unknown"
  fi
  # The journal counts agents the harness launched; the transcripts are the agents
  # whose usage was read. A mismatch is a WARN in either direction, so TOKENS_* are
  # never silently read as covering the wrong set of agents.
  if [ -n "$j_started" ] && [ "$j_started" -gt "$agents_transcripts" ]; then
    add_issue WARN transcripts_missing "journal started $j_started agent(s) but only $agents_transcripts transcript(s) were found; TOKENS_* sum those transcripts, so they cover fewer agents than started"
  elif [ -n "$j_started" ] && [ "$j_started" -lt "$agents_transcripts" ]; then
    add_issue WARN transcripts_extra "$agents_transcripts transcript(s) were found but the journal started only $j_started agent(s); TOKENS_* sum every transcript, so the journal may be incomplete"
  fi

  # Without a readable journal, AGENTS_STARTED falls back to the transcripts found,
  # and is unknown when there are none: a run with nothing to count is not a zero.
  local out_started out_result out_inflight
  if [ -n "$j_started" ]; then
    out_started=$j_started
    out_result=$j_result
    out_inflight=$((j_started - j_result))
    if [ "$out_inflight" -lt 0 ]; then
      out_inflight=0
      add_issue WARN result_exceeds_started "journal shows $j_result results for $j_started started agents; AGENTS_IN_FLIGHT is clamped to 0"
    fi
  else
    if [ "$agents_transcripts" -gt 0 ]; then out_started=$agents_transcripts; else out_started=unknown; fi
    out_result=unknown
    out_inflight=unknown
  fi

  # A finished run has no agents in flight. The harness summary, when present, says
  # whether the run is still running; started agents with no result under a finished
  # status are a WARN. No summary, or one with no readable status, keeps the current
  # behaviour: the in-flight count is reported and the run stays OK.
  local summary="$session_dir/workflows/$run_name.json" run_state=""
  if [ -n "$j_started" ] && [ "$out_inflight" -gt 0 ] && [ -f "$summary" ]; then
    run_state=$(jq -r '.status // empty' "$summary" 2>/dev/null)
    if [ -n "$run_state" ] && [ "$run_state" != running ]; then
      add_issue WARN agents_without_result "$out_inflight started agent(s) have no result, and the run's summary status is $run_state"
    fi
  fi

  local out_in=unknown out_out=unknown out_cw=unknown out_cr=unknown
  if [ "$agents_usage" -gt 0 ]; then
    out_in=$tok_in
    out_out=$tok_out
    out_cw=$tok_cw
    out_cr=$tok_cr
  elif [ "$journal_zero" = true ] && [ "$agents_transcripts" -eq 0 ]; then
    # The journal proves no agent launched, so zero tokens is the known value.
    out_in=0
    out_out=0
    out_cw=0
    out_cr=0
  fi

  local run_status=OK
  if [ "${#issue_sev[@]}" -gt 0 ]; then run_status=WARN; fi
  sess_names+=("$run_name")
  sess_status+=("$run_status")
  sess_reason+=("$(reason_for WARN)")
  sess_started+=("$out_started")
  sess_in+=("$out_in")
  sess_out+=("$out_out")
  sess_cw+=("$out_cw")
  sess_cr+=("$out_cr")

  echo "=== WORKFLOW RUN TALLY ==="
  echo "WORKFLOW_RUN=$run_name"
  echo "SESSION=$session_name"
  echo "AGENTS_STARTED=$out_started"
  echo "AGENTS_WITH_RESULT=$out_result"
  echo "AGENTS_IN_FLIGHT=$out_inflight"
  echo "AGENTS_TRANSCRIPTS=$agents_transcripts"
  echo "MESSAGES_COUNTED=$msgs"
  echo "DUPLICATE_LINES_DROPPED=$dups"
  echo "TOKENS_INPUT=$out_in"
  echo "TOKENS_OUTPUT=$out_out"
  echo "TOKENS_CACHE_WRITE=$out_cw"
  echo "TOKENS_CACHE_READ=$out_cr"
  echo "STATUS=$run_status"
  if [ "$run_status" != OK ]; then echo "REASON=$(reason_for WARN)"; fi
  echo "ISSUE_COUNT=${#issue_sev[@]}"
  if [ "${#issue_sev[@]}" -gt 0 ]; then
    echo "ISSUES:"
    print_issues
  fi
  echo "=== END WORKFLOW RUN TALLY ==="
}

# emit_not_found TARGET — the ERROR block when nothing matches. Every numeric field
# prints unknown, so a rollup never reads a missing run as zero agents.
emit_not_found() {
  local target_id="$1" run_label=none session_label=none key
  case "$target_id" in
    wf_*) run_label=$target_id ;;
    *) session_label=$target_id ;;
  esac
  issue_sev=()
  issue_type=()
  issue_msg=()
  add_issue ERROR run_not_found "no transcripts for $target_id under $projects_dir; transcripts are deleted after cleanupPeriodDays (default 30)"
  echo "=== WORKFLOW RUN TALLY ==="
  echo "WORKFLOW_RUN=$run_label"
  echo "SESSION=$session_label"
  for key in AGENTS_STARTED AGENTS_WITH_RESULT AGENTS_IN_FLIGHT AGENTS_TRANSCRIPTS \
             MESSAGES_COUNTED DUPLICATE_LINES_DROPPED TOKENS_INPUT TOKENS_OUTPUT \
             TOKENS_CACHE_WRITE TOKENS_CACHE_READ; do
    echo "$key=unknown"
  done
  echo "STATUS=ERROR"
  # REASON is "<TYPE>: <MSG>", like a WARN reason. The full message also sits in
  # ISSUES, where it is not cut to the REASON length.
  echo "REASON=$(reason_for ERROR)"
  echo "ISSUE_COUNT=${#issue_sev[@]}"
  echo "ISSUES:"
  print_issues
  echo "=== END WORKFLOW RUN TALLY ==="
}

# tally_session SESSION_ID — the session total after the run blocks: AGENTS_STARTED
# and TOKENS_* summed over the runs, RUNS, and the worst run STATUS. Every run found
# here is OK or WARN (a missing run is the ERROR block), so the worst status is WARN
# when any run is not OK, and each such run is one ISSUES row.
tally_session() {
  local sess_id="$1" k worst=OK
  issue_sev=()
  issue_type=()
  issue_msg=()
  for k in "${!sess_status[@]}"; do
    if [ "${sess_status[$k]}" != OK ]; then
      worst=WARN
      add_issue WARN run_warn "${sess_names[$k]}: ${sess_reason[$k]}"
    fi
  done
  echo "=== WORKFLOW SESSION TALLY ==="
  echo "SESSION=$sess_id"
  echo "RUNS=${#sess_names[@]}"
  echo "AGENTS_STARTED=$(sum_values "${sess_started[@]}")"
  echo "TOKENS_INPUT=$(sum_values "${sess_in[@]}")"
  echo "TOKENS_OUTPUT=$(sum_values "${sess_out[@]}")"
  echo "TOKENS_CACHE_WRITE=$(sum_values "${sess_cw[@]}")"
  echo "TOKENS_CACHE_READ=$(sum_values "${sess_cr[@]}")"
  echo "STATUS=$worst"
  if [ "$worst" != OK ]; then echo "REASON=$(reason_for WARN)"; fi
  echo "ISSUE_COUNT=${#issue_sev[@]}"
  if [ "${#issue_sev[@]}" -gt 0 ]; then
    echo "ISSUES:"
    print_issues
  fi
  echo "=== END WORKFLOW SESSION TALLY ==="
}

case "$target" in
  wf_*) run_dirs=( "$projects_dir"/*/*/subagents/workflows/"$target" ) ;;
  *)    run_dirs=( "$projects_dir"/*/"$target"/subagents/workflows/wf_* ) ;;
esac

found=()
for d in "${run_dirs[@]}"; do
  if [ -d "$d" ]; then found+=("$d"); fi
done

if [ "${#found[@]}" -eq 0 ]; then
  emit_not_found "$target"
  exit 1
fi

for d in "${found[@]}"; do
  tally_run "$d"
done
# A session id also gets one session total after its run blocks.
case "$target" in
  wf_*) ;;
  *) tally_session "$target" ;;
esac
exit 0
