#!/usr/bin/env bash
# Regression tests for workflow-run-tally.sh — the after-the-fact tally of one
# finished Workflow run (or every run in a session) from its local subagent
# transcripts. Every fixture here is synthetic: real transcripts carry prompts
# and must never be committed.
#
# Every test EXECUTES the tally against a fixture projects tree, on the
# WORKFLOW_RUN_TALLY_PROJECTS_DIR seam or --projects-dir. Case A pins the
# last-wins usage dedupe by behaviour: the first-wins and sum-all mutations must
# each turn it red, so the rule is checked by output, not by grepping source.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TALLY="${WORKFLOW_RUN_TALLY_UNDER_TEST:-$SCRIPT_DIR/../workflow-run-tally.sh}"

T=$(mktemp -d)
[ -n "$T" ] || exit 1
trap 'rm -rf "$T"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { fail=$((fail + 1)); echo "FAIL: $1"; }

# expect_eq LABEL EXPECTED ACTUAL
expect_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi
}
# expect_line LABEL LINE TEXT — whole-line match
expect_line() {
  if grep -qxF -- "$2" <<<"$3"; then ok "$1"; else bad "$1 (no line '$2')"; fi
}
# expect_match LABEL ERE TEXT
expect_match() {
  if grep -qE -- "$2" <<<"$3"; then ok "$1"; else bad "$1 (no line matching /$2/)"; fi
}

# field TEXT KEY — value of the first KEY=... line (exact key, so
# AGENTS_STARTED never matches AGENTS_STARTED_X)
field() {
  awk -v k="$2" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' <<<"$1"
}

# run_field RUN KEY TEXT — KEY's value inside the block for RUN. Session mode
# prints one block per run, so the first KEY= line of the text is not enough.
run_field() {
  awk -v r="$1" -v k="$2" '
    $0 == "WORKFLOW_RUN=" r { in_run = 1; next }
    in_run && index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' <<<"$3"
}

# sess_field KEY TEXT — KEY's value inside the WORKFLOW SESSION TALLY block
sess_field() {
  awk -v k="$1" '
    $0 == "=== WORKFLOW SESSION TALLY ===" { in_s = 1; next }
    $0 == "=== END WORKFLOW SESSION TALLY ===" { in_s = 0 }
    in_s && index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' <<<"$2"
}

# tally_env PROJECTS TARGET — run the tally on the env seam; sets OUT and RC
tally_env() {
  OUT=$(WORKFLOW_RUN_TALLY_PROJECTS_DIR="$1" bash "$TALLY" "$2" 2>&1)
  RC=$?
}

# mk_run PROJECTS SESSION RUN — create and echo one run directory
mk_run() {
  local d="$1/-synthetic-project/$2/subagents/workflows/$3"
  mkdir -p "$d" && printf '%s' "$d"
}

# asst MSG_ID INPUT OUTPUT CACHE_WRITE CACHE_READ — one assistant usage line
asst() {
  jq -cn --arg id "$1" --argjson i "$2" --argjson o "$3" --argjson cw "$4" --argjson cr "$5" '
    {type: "assistant", uuid: ("u-" + $id + "-" + ($o | tostring)),
     message: {id: $id, role: "assistant", usage: {
       input_tokens: $i, output_tokens: $o,
       cache_creation_input_tokens: $cw, cache_read_input_tokens: $cr,
       cache_creation: {ephemeral_5m_input_tokens: $cw, ephemeral_1h_input_tokens: 0}}}}'
}

# prompt_line — a non-usage user line, as real transcripts open with one
prompt_line() {
  printf '%s' '{"type":"user","uuid":"u-prompt","message":{"role":"user","content":"synthetic prompt"}}'
}

# write_agent DIR AGENT_ID LINE... — write agent-<id>.jsonl
write_agent() {
  local dir="$1" id="$2"
  shift 2
  printf '%s\n' "$@" > "$dir/agent-$id.jsonl"
}

# --- A: last-wins dedupe. m1 is written on two lines with a grown output_tokens.
echo "--- A: last-wins usage dedupe"
PROJ_A="$T/projA"
RUN_A=$(mk_run "$PROJ_A" S-A wf_aaaa-0001)
write_agent "$RUN_A" a1 "$(prompt_line)" \
  "$(asst m1 3 5 100 1000)" \
  "$(asst m1 3 40 100 1000)" \
  "$(asst m2 4 10 200 2000)"
naive=$(jq -R -n '[inputs | fromjson? | select(.type == "assistant") | .message.usage.output_tokens] | add' "$RUN_A/agent-a1.jsonl")
expect_eq "A: fixture's naive sum of every line is 55, so the dedupe is exercised" 55 "$naive"
tally_env "$PROJ_A" wf_aaaa-0001
expect_eq "A: exit 0" 0 "$RC"
expect_eq "A: TOKENS_OUTPUT is last-wins (40 + 10)" 50 "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "A: TOKENS_INPUT (3 + 4)" 7 "$(field "$OUT" TOKENS_INPUT)"
expect_eq "A: TOKENS_CACHE_WRITE (100 + 200)" 300 "$(field "$OUT" TOKENS_CACHE_WRITE)"
expect_eq "A: TOKENS_CACHE_READ (1000 + 2000)" 3000 "$(field "$OUT" TOKENS_CACHE_READ)"
expect_eq "A: MESSAGES_COUNTED is 2" 2 "$(field "$OUT" MESSAGES_COUNTED)"
expect_eq "A: DUPLICATE_LINES_DROPPED is 1" 1 "$(field "$OUT" DUPLICATE_LINES_DROPPED)"
expect_eq "A: no journal, so AGENTS_STARTED falls back to the transcript count" 1 "$(field "$OUT" AGENTS_STARTED)"
expect_eq "A: STATUS is OK" OK "$(field "$OUT" STATUS)"
expect_line "A: header line" "=== WORKFLOW RUN TALLY ===" "$OUT"
expect_line "A: END line" "=== END WORKFLOW RUN TALLY ===" "$OUT"

# --- B: journal counts. 3 started, 2 result: one agent still in flight, still OK.
echo "--- B: journal in-flight count"
PROJ_B="$T/projB"
RUN_B=$(mk_run "$PROJ_B" S-B wf_bbbb-0001)
write_agent "$RUN_B" b1 "$(prompt_line)" "$(asst x1 1 10 0 0)"
write_agent "$RUN_B" b2 "$(prompt_line)" "$(asst x2 1 20 0 0)"
write_agent "$RUN_B" b3 "$(prompt_line)" "$(asst x3 1 30 0 0)"
printf '%s\n' \
  '{"type":"launched"}' \
  '{"type":"started","agentId":"b1"}' \
  '{"type":"started","agentId":"b2"}' \
  '{"type":"started","agentId":"b3"}' \
  '{"type":"result","agentId":"b1"}' \
  '{"type":"result","agentId":"b2"}' > "$RUN_B/journal.jsonl"
tally_env "$PROJ_B" wf_bbbb-0001
expect_eq "B: AGENTS_STARTED is the journal's started count (3)" 3 "$(field "$OUT" AGENTS_STARTED)"
expect_eq "B: AGENTS_WITH_RESULT is 2" 2 "$(field "$OUT" AGENTS_WITH_RESULT)"
expect_eq "B: AGENTS_IN_FLIGHT is 1" 1 "$(field "$OUT" AGENTS_IN_FLIGHT)"
expect_eq "B: a live run stays STATUS=OK" OK "$(field "$OUT" STATUS)"
expect_eq "B: exit 0" 0 "$RC"

# --- C: unknown run id is an ERROR, even when the projects dir exists.
echo "--- C: unknown run id"
tally_env "$PROJ_B" wf_nope-9999
expect_eq "C: exit 1" 1 "$RC"
expect_eq "C: STATUS=ERROR" ERROR "$(field "$OUT" STATUS)"
expect_match "C: REASON is run_not_found with its message" "^REASON=run_not_found: no transcripts for wf_nope-9999 " "$OUT"
reason_val=$(field "$OUT" REASON)
if [ "${#reason_val}" -le 200 ]; then ok "C: REASON stays within 200 characters"; else bad "C: REASON stays within 200 characters (${#reason_val})"; fi
expect_match "C: note names the cleanupPeriodDays retention" "cleanupPeriodDays" "$OUT"

# --- D: a session id resolves to every wf_ dir in it, one block per run. The
# second run is what a first-run-only tally drops (five runs in #2670).
echo "--- D: session id resolution"
PROJ_D="$T/projD"
RUN_D=$(mk_run "$PROJ_D" sess-d-0001 wf_dddd-0001)
write_agent "$RUN_D" d1 "$(prompt_line)" "$(asst y1 1 6 0 0)"
RUN_D2=$(mk_run "$PROJ_D" sess-d-0001 wf_dddd-0002)
write_agent "$RUN_D2" d2 "$(prompt_line)" "$(asst y2 1 8 0 0)"
tally_env "$PROJ_D" sess-d-0001
expect_eq "D: exit 0" 0 "$RC"
expect_line "D: first run of the session is tallied" "WORKFLOW_RUN=wf_dddd-0001" "$OUT"
expect_line "D: second run of the session is tallied too" "WORKFLOW_RUN=wf_dddd-0002" "$OUT"
expect_line "D: resolved session" "SESSION=sess-d-0001" "$OUT"
expect_eq "D: one block per run in the session (2)" 2 "$(grep -c '^=== WORKFLOW RUN TALLY ===$' <<<"$OUT")"
expect_eq "D: first run's TOKENS_OUTPUT is its own (6)" 6 "$(run_field wf_dddd-0001 TOKENS_OUTPUT "$OUT")"
expect_eq "D: second run's TOKENS_OUTPUT is its own (8)" 8 "$(run_field wf_dddd-0002 TOKENS_OUTPUT "$OUT")"
mkdir -p "$PROJ_D/-synthetic-project/sess-d-empty"
printf '%s\n' "$(prompt_line)" > "$PROJ_D/-synthetic-project/sess-d-empty/session.jsonl"
tally_env "$PROJ_D" sess-d-empty
expect_eq "D: a session with no wf_ dirs is run_not_found" 1 "$RC"
expect_match "D: that case reports REASON=run_not_found with its message" "^REASON=run_not_found: " "$OUT"

# --- E: an agent with no usage line is a WARN, excluded from TOTALS, never 0.
echo "--- E: agent with no usage line"
PROJ_E="$T/projE"
RUN_E1=$(mk_run "$PROJ_E" S-E wf_eeee-0001)
write_agent "$RUN_E1" e1 "$(prompt_line)" "$(asst y2 1 7 0 0)"
write_agent "$RUN_E1" e2 "$(prompt_line)"
tally_env "$PROJ_E" wf_eeee-0001
expect_eq "E1: exit 0 on WARN" 0 "$RC"
expect_eq "E1: STATUS=WARN" WARN "$(field "$OUT" STATUS)"
expect_eq "E1: the usage-bearing agent still totals (7)" 7 "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "E1: AGENTS_TRANSCRIPTS counts both agents" 2 "$(field "$OUT" AGENTS_TRANSCRIPTS)"
expect_eq "E1: one issue for the empty transcript" 1 "$(field "$OUT" ISSUE_COUNT)"
expect_match "E1: the issue is TYPE=no_usage" "TYPE=no_usage" "$OUT"
expect_match "E1: REASON names no_usage" "^REASON=no_usage: " "$OUT"
RUN_E2=$(mk_run "$PROJ_E" S-E2 wf_ffff-0001)
write_agent "$RUN_E2" f1 "$(prompt_line)"
tally_env "$PROJ_E" wf_ffff-0001
expect_eq "E2: no agent yields usage, so TOKENS_OUTPUT is unknown, not 0" unknown "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "E2: TOKENS_INPUT is unknown, not 0" unknown "$(field "$OUT" TOKENS_INPUT)"
expect_eq "E2: STATUS=WARN" WARN "$(field "$OUT" STATUS)"

# --- F: cache_creation.ephemeral_* sums to the top-level figure; no double count.
echo "--- F: ephemeral split is not double counted"
PROJ_F="$T/projF"
RUN_F=$(mk_run "$PROJ_F" S-F wf_ffff-0002)
jq -cn '{type: "assistant", uuid: "u-split", message: {id: "s1", role: "assistant", usage: {
  input_tokens: 1, output_tokens: 1, cache_creation_input_tokens: 500, cache_read_input_tokens: 0,
  cache_creation: {ephemeral_5m_input_tokens: 300, ephemeral_1h_input_tokens: 200}}}}' \
  > "$RUN_F/agent-g1.jsonl"
tally_env "$PROJ_F" wf_ffff-0002
expect_eq "F: TOKENS_CACHE_WRITE is the top-level 500, not 1000" 500 "$(field "$OUT" TOKENS_CACHE_WRITE)"

# --- G: no journal: started falls back to transcripts; journal fields unknown.
echo "--- G: no journal fallback"
PROJ_G="$T/projG"
RUN_G=$(mk_run "$PROJ_G" S-G wf_gggg-0001)
write_agent "$RUN_G" g1 "$(asst z1 1 2 0 0)"
write_agent "$RUN_G" g2 "$(asst z2 1 3 0 0)"
tally_env "$PROJ_G" wf_gggg-0001
expect_eq "G: AGENTS_STARTED falls back to the transcript count (2)" 2 "$(field "$OUT" AGENTS_STARTED)"
expect_eq "G: AGENTS_WITH_RESULT is unknown, not 0" unknown "$(field "$OUT" AGENTS_WITH_RESULT)"
expect_eq "G: AGENTS_IN_FLIGHT is unknown, not 0" unknown "$(field "$OUT" AGENTS_IN_FLIGHT)"
expect_eq "G: STATUS=OK" OK "$(field "$OUT" STATUS)"
expect_eq "G: TOKENS_OUTPUT (2 + 3)" 5 "$(field "$OUT" TOKENS_OUTPUT)"

# --- H: --projects-dir overrides the env seam; usage errors exit 2.
echo "--- H: flag precedence and usage errors"
OUT=$(WORKFLOW_RUN_TALLY_PROJECTS_DIR="$T/nowhere" bash "$TALLY" wf_gggg-0001 --projects-dir "$PROJ_G" 2>&1)
RC=$?
expect_eq "H: --projects-dir beats WORKFLOW_RUN_TALLY_PROJECTS_DIR" 2 "$(field "$OUT" AGENTS_STARTED)"
expect_eq "H: flag run exits 0" 0 "$RC"
bash "$TALLY" >/dev/null 2>&1
expect_eq "H: no arguments is a usage error (exit 2)" 2 "$?"
bash "$TALLY" wf_gggg-0001 --bogus >/dev/null 2>&1
expect_eq "H: unknown flag is a usage error (exit 2)" 2 "$?"
bash "$TALLY" '../escape' >/dev/null 2>&1
expect_eq "H: a path-like target is a usage error (exit 2)" 2 "$?"

# --- I: a live transcript whose last line is half-written still tallies.
echo "--- I: partial trailing line"
PROJ_I="$T/projI"
RUN_I=$(mk_run "$PROJ_I" S-I wf_iiii-0001)
printf '%s\n%s\n' "$(asst h1 1 9 0 0)" '{"type":"assi' > "$RUN_I/agent-h1.jsonl"
tally_env "$PROJ_I" wf_iiii-0001
expect_eq "I: the complete usage line still counts (9)" 9 "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "I: a half-written line does not make the run ERROR" OK "$(field "$OUT" STATUS)"

# --- J: the journal and the transcripts disagree. TOKENS_* cover only the
# transcripts that were read, so the run is a WARN, never a silent undercount.
echo "--- J: journal started count vs transcripts"
PROJ_J="$T/projJ"
RUN_J=$(mk_run "$PROJ_J" S-J wf_jjjj-0001)
write_agent "$RUN_J" j1 "$(prompt_line)" "$(asst p1 1 4 0 0)"
printf '%s\n' \
  '{"type":"launched"}' \
  '{"type":"started","agentId":"j1"}' \
  '{"type":"started","agentId":"j2"}' \
  '{"type":"started","agentId":"j3"}' \
  '{"type":"result","agentId":"j1"}' \
  '{"type":"result","agentId":"j2"}' \
  '{"type":"result","agentId":"j3"}' > "$RUN_J/journal.jsonl"
tally_env "$PROJ_J" wf_jjjj-0001
expect_eq "J: exit 0 on WARN" 0 "$RC"
expect_eq "J: AGENTS_STARTED is the journal's 3" 3 "$(field "$OUT" AGENTS_STARTED)"
expect_eq "J: AGENTS_TRANSCRIPTS is 1" 1 "$(field "$OUT" AGENTS_TRANSCRIPTS)"
expect_eq "J: TOKENS_OUTPUT covers the one transcript read (4)" 4 "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "J: STATUS=WARN, not a silent OK" WARN "$(field "$OUT" STATUS)"
expect_match "J: the issue is TYPE=transcripts_missing" "TYPE=transcripts_missing" "$OUT"
expect_match "J: REASON names transcripts_missing" "^REASON=transcripts_missing: " "$OUT"
expect_match "J: the message says the journal outnumbers the transcripts read" "journal started 3 agent\(s\) but only 1 transcript" "$OUT"

# --- K: a journal that shows zero agents started proves zero tokens, so a run
# that launched nothing is OK with 0, not unknown. A run dir with no journal and
# no transcripts is still unknown: a missing run is never read as zero.
echo "--- K: a run that launched no agents"
PROJ_K="$T/projK"
RUN_K=$(mk_run "$PROJ_K" S-K wf_kkkk-0001)
printf '%s\n' '{"type":"launched"}' > "$RUN_K/journal.jsonl"
tally_env "$PROJ_K" wf_kkkk-0001
expect_eq "K: exit 0" 0 "$RC"
expect_eq "K: AGENTS_STARTED is 0" 0 "$(field "$OUT" AGENTS_STARTED)"
expect_eq "K: TOKENS_INPUT is 0, not unknown" 0 "$(field "$OUT" TOKENS_INPUT)"
expect_eq "K: TOKENS_OUTPUT is 0, not unknown" 0 "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "K: TOKENS_CACHE_READ is 0, not unknown" 0 "$(field "$OUT" TOKENS_CACHE_READ)"
expect_eq "K: STATUS=OK, a launch with no agents is not a WARN" OK "$(field "$OUT" STATUS)"
expect_eq "K: ISSUE_COUNT is 0" 0 "$(field "$OUT" ISSUE_COUNT)"
mk_run "$PROJ_K" S-K2 wf_kkkk-0002 >/dev/null
tally_env "$PROJ_K" wf_kkkk-0002
expect_eq "K2: an empty run dir with no journal keeps TOKENS_OUTPUT unknown" unknown "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "K2: AGENTS_STARTED is unknown, not 0, with no journal and no transcript" unknown "$(field "$OUT" AGENTS_STARTED)"
expect_eq "K2: and is a WARN, not a silent OK" WARN "$(field "$OUT" STATUS)"
expect_match "K2: the issue is TYPE=no_transcripts" "TYPE=no_transcripts" "$OUT"

# inflight_run PROJECTS SESSION RUN [SUMMARY_STATUS] — three agents started, one
# result, usage on each. A summary file is written only when SUMMARY_STATUS is given.
inflight_run() {
  local d
  d=$(mk_run "$1" "$2" "$3")
  write_agent "$d" l1 "$(prompt_line)" "$(asst k1 1 5 0 0)"
  write_agent "$d" l2 "$(prompt_line)" "$(asst k2 1 6 0 0)"
  write_agent "$d" l3 "$(prompt_line)" "$(asst k3 1 7 0 0)"
  printf '%s\n' \
    '{"type":"launched"}' \
    '{"type":"started","agentId":"l1"}' \
    '{"type":"started","agentId":"l2"}' \
    '{"type":"started","agentId":"l3"}' \
    '{"type":"result","agentId":"l1"}' > "$d/journal.jsonl"
  if [ -n "${4:-}" ]; then
    mkdir -p "$1/-synthetic-project/$2/workflows"
    printf '{"status":"%s"}\n' "$4" > "$1/-synthetic-project/$2/workflows/$3.json"
  fi
}

# --- L: a finished run (harness summary status not running) that left agents with
# no result is a WARN. A live run (summary says running) and a run with no summary
# stay OK, since their in-flight agents are not yet a finding.
echo "--- L: started-without-result on a finished run"
PROJ_L="$T/projL"
inflight_run "$PROJ_L" S-L wf_llll-0001 killed
inflight_run "$PROJ_L" S-L2 wf_llll-0002 running
inflight_run "$PROJ_L" S-L3 wf_llll-0003
tally_env "$PROJ_L" wf_llll-0001
expect_eq "L1: exit 0 on WARN" 0 "$RC"
expect_eq "L1: AGENTS_IN_FLIGHT is still reported (2)" 2 "$(field "$OUT" AGENTS_IN_FLIGHT)"
expect_eq "L1: a killed run with agents left unfinished is STATUS=WARN, not OK" WARN "$(field "$OUT" STATUS)"
expect_match "L1: the issue is TYPE=agents_without_result" "TYPE=agents_without_result" "$OUT"
expect_match "L1: REASON names agents_without_result" "^REASON=agents_without_result: " "$OUT"
tally_env "$PROJ_L" wf_llll-0002
expect_eq "L2: a running summary keeps the live run STATUS=OK" OK "$(field "$OUT" STATUS)"
expect_eq "L2: a running summary keeps AGENTS_IN_FLIGHT at 2" 2 "$(field "$OUT" AGENTS_IN_FLIGHT)"
tally_env "$PROJ_L" wf_llll-0003
expect_eq "L3: with no summary the run keeps the current STATUS=OK" OK "$(field "$OUT" STATUS)"
expect_eq "L3: with no summary AGENTS_IN_FLIGHT is still 2" 2 "$(field "$OUT" AGENTS_IN_FLIGHT)"

# --- M: more results than started. The in-flight count clamps to 0, and the
# mismatch is a WARN rather than a silent clamp. The raw result count still prints.
echo "--- M: result count exceeds started count"
PROJ_M="$T/projM"
RUN_M=$(mk_run "$PROJ_M" S-M wf_mmmm-0001)
write_agent "$RUN_M" m1 "$(prompt_line)" "$(asst q1 1 2 0 0)"
printf '%s\n' \
  '{"type":"launched"}' \
  '{"type":"started","agentId":"m1"}' \
  '{"type":"result","agentId":"m1"}' \
  '{"type":"result","agentId":"m2"}' > "$RUN_M/journal.jsonl"
tally_env "$PROJ_M" wf_mmmm-0001
expect_eq "M: exit 0 on WARN" 0 "$RC"
expect_eq "M: AGENTS_IN_FLIGHT is clamped to 0, never negative" 0 "$(field "$OUT" AGENTS_IN_FLIGHT)"
expect_eq "M: AGENTS_WITH_RESULT keeps the journal's raw count (2)" 2 "$(field "$OUT" AGENTS_WITH_RESULT)"
expect_eq "M: STATUS=WARN for a result count above the started count" WARN "$(field "$OUT" STATUS)"
expect_match "M: the issue is TYPE=result_exceeds_started" "TYPE=result_exceeds_started" "$OUT"
expect_match "M: REASON names result_exceeds_started" "^REASON=result_exceeds_started: " "$OUT"

# --- N: a journal with no parseable JSON line is unknown, never a started count of
# 0 with STATUS=OK. A launched line is what proves a zero-agent run.
echo "--- N: journal with no parseable line"
PROJ_N="$T/projN"
RUN_N1=$(mk_run "$PROJ_N" S-N wf_nnnn-0001)
printf '%s\n' 'garbage' '{"type":"sta' > "$RUN_N1/journal.jsonl"
tally_env "$PROJ_N" wf_nnnn-0001
expect_eq "N1: exit 0 on WARN" 0 "$RC"
expect_eq "N1: AGENTS_STARTED is unknown, not 0" unknown "$(field "$OUT" AGENTS_STARTED)"
expect_eq "N1: AGENTS_IN_FLIGHT is unknown" unknown "$(field "$OUT" AGENTS_IN_FLIGHT)"
expect_eq "N1: STATUS=WARN, never OK" WARN "$(field "$OUT" STATUS)"
expect_match "N1: the issue is TYPE=journal_unreadable" "TYPE=journal_unreadable" "$OUT"
RUN_N2=$(mk_run "$PROJ_N" S-N wf_nnnn-0002)
: > "$RUN_N2/journal.jsonl"
tally_env "$PROJ_N" wf_nnnn-0002
expect_eq "N2: an empty journal is AGENTS_STARTED unknown, not 0" unknown "$(field "$OUT" AGENTS_STARTED)"
expect_eq "N2: an empty journal is STATUS=WARN" WARN "$(field "$OUT" STATUS)"

# --- O: a non-integer usage value is a WARN for its own transcript only. The loop keeps
# going: the integer transcript still totals, and no arithmetic error reaches the output.
echo "--- O: non-integer usage value"
PROJ_O="$T/projO"
RUN_O=$(mk_run "$PROJ_O" S-O wf_oooo-0001)
write_agent "$RUN_O" o1 "$(prompt_line)" \
  '{"type":"assistant","uuid":"u-frac","message":{"id":"f1","role":"assistant","usage":{"input_tokens":1,"output_tokens":2.5,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
write_agent "$RUN_O" o2 "$(prompt_line)" "$(asst g1 1 4 0 0)"
tally_env "$PROJ_O" wf_oooo-0001
expect_eq "O: exit 0, not a silent abort" 0 "$RC"
expect_match "O: the fractional transcript is TYPE=transcript_unreadable" "TYPE=transcript_unreadable" "$OUT"
expect_eq "O: STATUS=WARN" WARN "$(field "$OUT" STATUS)"
expect_eq "O: TOKENS_OUTPUT covers only the integer transcript (4)" 4 "$(field "$OUT" TOKENS_OUTPUT)"
expect_eq "O: AGENTS_TRANSCRIPTS still counts both files" 2 "$(field "$OUT" AGENTS_TRANSCRIPTS)"
expect_eq "O: no bash arithmetic error reaches the output" 0 "$(grep -c 'syntax error' <<<"$OUT")"

# --- P: more transcripts than the journal started. TOKENS_* sum every transcript, so the
# message must say the journal is short, not that the totals cover fewer agents.
echo "--- P: transcripts exceed the journal's started count"
PROJ_P="$T/projP"
RUN_P=$(mk_run "$PROJ_P" S-P wf_pppp-0001)
write_agent "$RUN_P" p1 "$(prompt_line)" "$(asst r1 1 3 0 0)"
write_agent "$RUN_P" p2 "$(prompt_line)" "$(asst r2 1 5 0 0)"
printf '%s\n' '{"type":"launched"}' '{"type":"started","agentId":"p1"}' '{"type":"result","agentId":"p1"}' > "$RUN_P/journal.jsonl"
tally_env "$PROJ_P" wf_pppp-0001
expect_eq "P: exit 0 on WARN" 0 "$RC"
expect_eq "P: STATUS=WARN" WARN "$(field "$OUT" STATUS)"
expect_eq "P: TOKENS_OUTPUT includes both transcripts (3 + 5)" 8 "$(field "$OUT" TOKENS_OUTPUT)"
expect_match "P: the issue is TYPE=transcripts_extra" "TYPE=transcripts_extra" "$OUT"
expect_match "P: the message says the journal started fewer agents than transcripts" "but the journal started only 1 agent" "$OUT"
expect_match "P: REASON names transcripts_extra" "^REASON=transcripts_extra: " "$OUT"

# --- Q: session mode adds one WORKFLOW SESSION TALLY block after the per-run blocks,
# summing across runs. An unknown value in any run makes that total unknown, and the
# worst run STATUS is the session STATUS.
echo "--- Q: session tally block"
PROJ_Q="$T/projQ"
RUN_Q1=$(mk_run "$PROJ_Q" sess-q-0001 wf_qqqq-0001)
write_agent "$RUN_Q1" q1 "$(prompt_line)" "$(asst s1 1 3 10 20)"
RUN_Q2=$(mk_run "$PROJ_Q" sess-q-0001 wf_qqqq-0002)
write_agent "$RUN_Q2" q2 "$(prompt_line)" "$(asst s2 2 5 30 40)"
write_agent "$RUN_Q2" q3 "$(prompt_line)" "$(asst s3 1 1 1 1)"
tally_env "$PROJ_Q" sess-q-0001
expect_eq "Q1: exit 0" 0 "$RC"
expect_eq "Q1: one session block" 1 "$(grep -c '^=== WORKFLOW SESSION TALLY ===$' <<<"$OUT")"
expect_eq "Q1: the session block comes last" "=== END WORKFLOW SESSION TALLY ===" "$(tail -n 1 <<<"$OUT")"
expect_eq "Q1: RUNS is 2" 2 "$(sess_field RUNS "$OUT")"
expect_eq "Q1: AGENTS_STARTED sums the runs (1 + 2)" 3 "$(sess_field AGENTS_STARTED "$OUT")"
expect_eq "Q1: TOKENS_INPUT sums the runs (1 + 2 + 1)" 4 "$(sess_field TOKENS_INPUT "$OUT")"
expect_eq "Q1: TOKENS_OUTPUT sums the runs (3 + 5 + 1)" 9 "$(sess_field TOKENS_OUTPUT "$OUT")"
expect_eq "Q1: TOKENS_CACHE_WRITE sums the runs (10 + 30 + 1)" 41 "$(sess_field TOKENS_CACHE_WRITE "$OUT")"
expect_eq "Q1: TOKENS_CACHE_READ sums the runs (20 + 40 + 1)" 61 "$(sess_field TOKENS_CACHE_READ "$OUT")"
expect_eq "Q1: all runs OK, so the session is STATUS=OK" OK "$(sess_field STATUS "$OUT")"
RUN_Q3=$(mk_run "$PROJ_Q" sess-q-0002 wf_qqqq-0003)
write_agent "$RUN_Q3" q4 "$(prompt_line)"
RUN_Q4=$(mk_run "$PROJ_Q" sess-q-0002 wf_qqqq-0004)
write_agent "$RUN_Q4" q5 "$(prompt_line)" "$(asst s5 1 6 0 0)"
tally_env "$PROJ_Q" sess-q-0002
expect_eq "Q2: a run with no usage makes the session STATUS=WARN" WARN "$(sess_field STATUS "$OUT")"
expect_eq "Q2: that run's tokens make the session total unknown" unknown "$(sess_field TOKENS_OUTPUT "$OUT")"
expect_eq "Q2: AGENTS_STARTED still sums (1 + 1)" 2 "$(sess_field AGENTS_STARTED "$OUT")"
expect_eq "Q2: the session ISSUE_COUNT is one row per warning run" 1 "$(sess_field ISSUE_COUNT "$OUT")"
expect_match "Q2: the session REASON names the warning run" "^run_warn: wf_qqqq-0003: " "$(sess_field REASON "$OUT")"

echo "PASS=$pass FAIL=$fail"
if [ "$fail" -eq 0 ]; then exit 0; fi
exit 1
