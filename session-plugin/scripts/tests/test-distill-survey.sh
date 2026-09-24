#!/usr/bin/env bash
# Regression tests for distill-survey.sh — the read-only distill collector.
# Covers: churn exclusion, cross-session recurrence, commit-bracketing,
# just-coverage exclusion, exact HOT_FILES, .claude/worktrees prune, SKIP on
# empty/missing, --summary shape, the RULE_HINTS_FROM_TOOLING denial signal,
# and (TEST N, #2683) argument stability + compound-line exclusion.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="$SCRIPT_DIR/../distill-survey.sh"
# The pi harness exports PI_SESSION_FILE into bash calls; keep the suite hermetic.
unset PI_SESSION_FILE

pass=0
fail=0
check() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -e "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "  expected to find: $needle"
  fi
}
check_absent() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -e "$needle"; then
    fail=$((fail + 1))
    echo "FAIL: $label (unexpected: $needle)"
  else
    pass=$((pass + 1))
  fi
}

SANDBOX="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
[ -n "$SANDBOX" ] || { echo "empty sandbox path"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

SID="11111111-1111-1111-1111-111111111111"
PROJECTS="$SANDBOX/projects"
SLUG="$PROJECTS/-proj-slug"
mkdir -p "$SLUG"

# Project dir with a justfile so the just-coverage branch runs.
PROJ="$SANDBOX/proj"
mkdir -p "$PROJ"
printf 'deploy:\n\thelm upgrade myrel ./chart\n' > "$PROJ/justfile"

# just stub (test seam) — emits a dump whose recipe name AND body command are
# used to exclude session commands as already-covered. JUST_ARGV_LOG records
# argv. An unknown call FAILS, loudly (#2569): answering it with a clean exit
# would let a new call in the collector pass unexercised.
STUB="$SANDBOX/stub"
mkdir -p "$STUB"
cat > "$STUB/just" <<'JUSTSTUB'
#!/usr/bin/env bash
if [ -n "${JUST_ARGV_LOG:-}" ]; then printf '%s\n' "$*" >> "$JUST_ARGV_LOG"; fi
case "$*" in
  *"--dump"*) echo '{"recipes":{"deploy":{"body":[["helm upgrade myrel ./chart"]]}}}' ;;
  *) echo "just stub: unexpected argv: $*" >&2; exit 1 ;;
esac
JUSTSTUB
chmod +x "$STUB/just"

# --- Current session transcript ---------------------------------------------
bash_line() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$(jq -Rn --arg c "$1" '$c')"; }
{
  bash_line 'git status'                       # churn, before commit
  bash_line 'terraform apply -auto-approve'    # recurs across sessions → candidate
  bash_line 'kubectl apply -f deploy/'         # bracketed but <path> never repeats → dropped (#2683)
  bash_line 'docker compose up -d'             # bracketed + fully literal → candidate
  bash_line 'helm upgrade myrel ./chart'       # covered by recipe body → excluded
  bash_line 'git commit -m "ship it"'          # commit delimiter
  bash_line 'just deploy'                       # covered by recipe name → excluded
  # HOT file: three edits of the same file
  printf '{"toolUseResult":{"filePath":"/repo/config.yaml","type":"update"}}\n'
  printf '{"toolUseResult":{"filePath":"/repo/config.yaml","type":"update"}}\n'
  printf '{"toolUseResult":{"filePath":"/repo/config.yaml","type":"update"}}\n'
  # a one-off file write (below the ≥3 threshold)
  printf '{"toolUseResult":{"filePath":"/repo/main.tf","type":"create"}}\n'
  # repeated permission denials
  printf '{"toolDenialKind":"user-rejected"}\n'
  printf '{"toolDenialKind":"user-rejected"}\n'
} > "$SLUG/$SID.jsonl"

# --- A SEPARATE older session in the same project dir -----------------------
bash_line 'terraform apply -auto-approve' > "$SLUG/22222222-2222-2222-2222-222222222222.jsonl"

run() {
  DISTILL_SURVEY_PROJECTS_DIR="$PROJECTS" DISTILL_SURVEY_JUST_BIN="$STUB/just" \
    bash "$COLLECTOR" --session-id "$SID" --project-dir "$PROJ" "$@"
}

# --- TEST A: meta + availability --------------------------------------------
export JUST_ARGV_LOG="$SANDBOX/just-argv.log"
: > "$JUST_ARGV_LOG"
out=$(run)
# The one call the collector makes reached a real arm of the stub, and nothing
# else was asked: with the fallthrough failing, a new call would also be red.
if [ "$(cat "$JUST_ARGV_LOG")" = "--dump --dump-format json" ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); echo "FAIL: A: exactly one just call, the recipe dump (got: $(tr '\n' '|' < "$JUST_ARGV_LOG"))"
fi
unset JUST_ARGV_LOG
if "$STUB/just" --list >/dev/null 2>&1; then
  fail=$((fail + 1)); echo "FAIL: A: the just stub fails an unknown call instead of answering it"
else
  pass=$((pass + 1))
fi
check "A: transcript available" "$out" "TRANSCRIPT_AVAILABLE=true"
check "A: both sessions scanned" "$out" "SESSIONS_SCANNED=2"
check "A: just dump consumed" "$out" "JUST_AVAILABLE=true"
check "A: meta STATUS OK" "$out" "$(printf '=== SESSION_META ===')"

# --- TEST B: recipe candidates ----------------------------------------------
cand=$(printf '%s' "$out" | sed -n '/=== RECIPE_CANDIDATES ===/,/=== END RECIPE_CANDIDATES ===/p')
check "B: cross-session recurring command surfaces" "$cand" "terraform apply -auto-approve"
check "B: recurrence count is 2" "$cand" "_SESSIONS=2"
check "B: commit-bracketed command surfaces" "$cand" "docker compose up -d"
check "B: bracketed flag set" "$cand" "_BRACKETED=yes"
check "B: literal shapes are labelled stable" "$cand" "_STABLE_ARGS=literal"
check_absent "B: bracketed shape with a never-repeated <path> excluded (#2683)" "$cand" "kubectl apply -f <path>"
check "B: novel tokens emitted" "$cand" "NOVEL_TOKENS=terraform,apply"
check "B: concrete _FIRST example preserved" "$cand" "_FIRST=terraform apply -auto-approve"
check_absent "B: churn (git status) excluded" "$cand" "git status"
check_absent "B: just-recipe-name command excluded" "$cand" "just deploy"
check_absent "B: just-recipe-body command excluded" "$cand" "helm upgrade myrel"

# --- TEST C: hot files (exact filePath, ≥3) ---------------------------------
hot=$(printf '%s' "$out" | sed -n '/=== HOT_FILES ===/,/=== END HOT_FILES ===/p')
check "C: hot file surfaced from exact filePath" "$hot" "HOT_1_FILE=/repo/config.yaml"
check "C: hot file total is 3" "$hot" "HOT_1_TOTAL=3"
check "C: edit op breakdown" "$hot" "HOT_1_EDITS=3"
check_absent "C: below-threshold file not surfaced" "$hot" "main.tf"

# --- TEST D: commit intervals (no n-gram, just grouping) --------------------
ci=$(printf '%s' "$out" | sed -n '/=== COMMIT_INTERVALS ===/,/=== END COMMIT_INTERVALS ===/p')
check "D: first interval ended by commit" "$ci" "INTERVAL_1_ENDED_BY=commit"
check "D: commit interval carries the bracketed cmds" "$ci" "kubectl apply -f <path>"
check_absent "D: churn excluded from interval grouping" "$ci" "git status"

# --- TEST E: command digest --------------------------------------------------
dg=$(printf '%s' "$out" | sed -n '/=== COMMAND_DIGEST ===/,/=== END COMMAND_DIGEST ===/p')
check "E: digest lists normalized commands" "$dg" "helm upgrade myrel <path>"

# --- TEST F: rule hints from repeated denials -------------------------------
rh=$(printf '%s' "$out" | sed -n '/=== RULE_HINTS_FROM_TOOLING ===/,/=== END RULE_HINTS_FROM_TOOLING ===/p')
check "F: repeated denial raises the mechanical rule signal" "$rh" "RULES_SIGNAL=denials"
check "F: per-kind denial count" "$rh" "DENIAL_user-rejected=2"

# --- TEST G: --summary shape -------------------------------------------------
sm=$(run --summary)
check "G: summary header" "$sm" "=== DISTILL SURVEY SUMMARY ==="
check "G: recipe candidate count" "$sm" "RECIPE_CANDIDATE_COUNT=2"
check "G: hot file count" "$sm" "HOT_FILE_COUNT=1"
check "G: process signal present" "$sm" "PROCESS_SIGNAL="
check "G: available flag" "$sm" "TRANSCRIPT_AVAILABLE=true"
check_absent "G: summary omits full candidate detail" "$sm" "CANDIDATE_1="

# --- TEST H: SKIP on empty projects dir -------------------------------------
EMPTY="$SANDBOX/empty-projects"
mkdir -p "$EMPTY"
out=$(DISTILL_SURVEY_PROJECTS_DIR="$EMPTY" bash "$COLLECTOR" --session-id "$SID" --project-dir "$PROJ")
rc=$?
check "H: exits 0 on empty projects dir" "$rc" "0"
check "H: transcript unavailable" "$out" "TRANSCRIPT_AVAILABLE=false"
check "H: STATUS SKIP" "$out" "STATUS=SKIP"
check "H: zeroed recipe section" "$out" "$(printf '=== RECIPE_CANDIDATES ===\nCOUNT=0')"

# --- TEST I: SKIP when no --session-id --------------------------------------
out=$(DISTILL_SURVEY_PROJECTS_DIR="$PROJECTS" bash "$COLLECTOR" --project-dir "$PROJ")
check "I: no session id → unavailable" "$out" "TRANSCRIPT_AVAILABLE=false"

# --- TEST J: .claude/worktrees copies are pruned (#1492/#1548) ---------------
# A transcript for our session id living ONLY under a .claude/worktrees path
# must be pruned by the finder → the session is not found → SKIP.
WT_PROJECTS="$SANDBOX/wt-projects"
mkdir -p "$WT_PROJECTS/-x/.claude/worktrees/w"
cp "$SLUG/$SID.jsonl" "$WT_PROJECTS/-x/.claude/worktrees/w/$SID.jsonl"
out=$(DISTILL_SURVEY_PROJECTS_DIR="$WT_PROJECTS" bash "$COLLECTOR" --session-id "$SID" --project-dir "$PROJ")
check "J: worktree-only transcript pruned → unavailable" "$out" "TRANSCRIPT_AVAILABLE=false"
check_absent "J: no .claude/worktrees path leaks into output" "$out" ".claude/worktrees"

# --- TEST K: format key on the Claude Code path ------------------------------
out=$(run)
check "K: Claude transcript reports its format" "$out" "TRANSCRIPT_FORMAT=claude-code"
check "K: summary reports the format" "$(run --summary)" "TRANSCRIPT_FORMAT=claude-code"

# --- pi fixture: the same logical session as the Claude fixture above ---------
# Shapes verified against real pi 0.84.1 session files (read-only) and
# dist/core/session-manager.js: line-1 {"type":"session",...,"parentSession"?},
# then {"type":"message","message":{role,...}} entries; assistant content items
# {"type":"toolCall","id","name","arguments"}; results
# {"role":"toolResult","toolCallId","toolName","isError"}. Content is synthetic.
PI_ID="01a0aaaa-0000-7000-8000-000000000001"
PI_DIR="$SANDBOX/pi-sessions/--repo--"
mkdir -p "$PI_DIR"
pi_header_line() {  # $1 = id, $2 = optional parentSession path
  if [ -n "${2:-}" ]; then
    jq -cn --arg id "$1" --arg p "$2" '{type:"session",version:3,id:$id,timestamp:"2026-01-02T00:00:00.000Z",cwd:"/repo",parentSession:$p}'
  else
    jq -cn --arg id "$1" '{type:"session",version:3,id:$id,timestamp:"2026-01-02T00:00:00.000Z",cwd:"/repo"}'
  fi
}
pi_call() {  # $1 = call id, $2 = tool name, $3 = arguments JSON
  jq -cn --arg id "$1" --arg n "$2" --argjson a "$3" \
    '{type:"message",id:("m-"+$id),parentId:null,timestamp:"2026-01-02T00:00:01.000Z",message:{role:"assistant",content:[{type:"toolCall",id:$id,name:$n,arguments:$a}]}}'
}
pi_result() {  # $1 = call id, $2 = tool name, $3 = isError (true|false)
  jq -cn --arg id "$1" --arg n "$2" --argjson e "$3" \
    '{type:"message",id:("r-"+$id),parentId:("m-"+$id),timestamp:"2026-01-02T00:00:02.000Z",message:{role:"toolResult",toolCallId:$id,toolName:$n,content:[{type:"text",text:"ok"}],isError:$e}}'
}
pi_bash() { pi_call "$1" bash "$(jq -cn --arg c "$2" '{command:$c}')"; pi_result "$1" bash false; }
pi_edit() { pi_call "$1" edit "$(jq -cn --arg p "$2" '{path:$p,edits:[{oldText:"a",newText:"b"}]}')"; pi_result "$1" edit "$3"; }
{
  pi_header_line "$PI_ID"
  pi_bash c1 'git status'
  pi_bash c2 'terraform apply -auto-approve'
  pi_bash c3 'kubectl apply -f deploy/'
  pi_bash c3b 'docker compose up -d'
  pi_bash c4 'helm upgrade myrel ./chart'
  pi_bash c5 'git commit -m "ship it"'
  pi_bash c6 'just deploy'
  pi_edit e1 /repo/config.yaml false
  pi_edit e2 /repo/config.yaml false
  pi_edit e3 /repo/config.yaml false
  pi_edit e4 /repo/config.yaml true   # pi records failed edits too — must not count
  pi_call w1 write "$(jq -cn '{path:"/repo/main.tf",content:"x"}')"; pi_result w1 write false
} > "$PI_DIR/2026-01-02T00-00-00-000Z_${PI_ID}.jsonl"
# A SEPARATE older top-level pi session in the same directory.
{ pi_header_line "01a0aaaa-0000-7000-8000-000000000002"; pi_bash c1 'terraform apply -auto-approve'; } \
  > "$PI_DIR/2026-01-01T00-00-00-000Z_01a0aaaa-0000-7000-8000-000000000002.jsonl"
# A subagent/fork sibling (parentSession set) — must stay out of the window.
{ pi_header_line "01a0aaaa-0000-7000-8000-000000000003" "$PI_DIR/2026-01-02T00-00-00-000Z_${PI_ID}.jsonl"
  pi_bash c1 'kubectl apply -f deploy/'; } \
  > "$PI_DIR/2026-01-02T00-00-01-000Z_01a0aaaa-0000-7000-8000-000000000003.jsonl"
PI_FILE="$PI_DIR/2026-01-02T00-00-00-000Z_${PI_ID}.jsonl"
NO_CLAUDE="$SANDBOX/no-claude-projects"
mkdir -p "$NO_CLAUDE"

run_pi() {
  DISTILL_SURVEY_PROJECTS_DIR="$NO_CLAUDE" DISTILL_SURVEY_JUST_BIN="$STUB/just" PI_SESSION_FILE="$PI_FILE" \
    bash "$COLLECTOR" --project-dir "$PROJ" "$@"
}

# --- TEST L: pi transcript — groups B, C, F, G parity -------------------------
out=$(run_pi)
check "L: pi transcript available" "$out" "TRANSCRIPT_AVAILABLE=true"
check "L: pi format reported" "$out" "TRANSCRIPT_FORMAT=pi"
check "L: session id taken from the pi header" "$out" "SESSION_ID=${PI_ID}"
check "L: parentSession sibling excluded from the window" "$out" "SESSIONS_SCANNED=2"
cand=$(printf '%s' "$out" | sed -n '/=== RECIPE_CANDIDATES ===/,/=== END RECIPE_CANDIDATES ===/p')
check "L/B: candidate count matches Claude fixture" "$cand" "COUNT=2"
check "L/B: cross-session recurring command surfaces" "$cand" "CANDIDATE_1=terraform apply -auto-approve"
check "L/B: recurrence count is 2" "$cand" "CANDIDATE_1_SESSIONS=2"
check "L/B: commit-bracketed command surfaces" "$cand" "CANDIDATE_2=docker compose up -d"
check_absent "L/B: bracketed shape with a never-repeated <path> excluded (#2683)" "$cand" "kubectl apply -f <path>"
check "L/B: bracketed-only command not counted in the child session" "$cand" "CANDIDATE_2_SESSIONS=1"
check "L/B: bracketed flag set" "$cand" "CANDIDATE_2_BRACKETED=yes"
check "L/B: novel tokens emitted" "$cand" "NOVEL_TOKENS=terraform,apply"
check "L/B: concrete _FIRST example preserved" "$cand" "_FIRST=terraform apply -auto-approve"
check_absent "L/B: churn (git status) excluded" "$cand" "git status"
check_absent "L/B: just-recipe-name command excluded" "$cand" "just deploy"
check_absent "L/B: just-recipe-body command excluded" "$cand" "helm upgrade myrel"
hot=$(printf '%s' "$out" | sed -n '/=== HOT_FILES ===/,/=== END HOT_FILES ===/p')
check "L/C: hot file surfaced from arguments.path" "$hot" "HOT_1_FILE=/repo/config.yaml"
check "L/C: failed edit excluded, total is 3" "$hot" "HOT_1_TOTAL=3"
check "L/C: edit op breakdown" "$hot" "HOT_1_EDITS=3"
check_absent "L/C: below-threshold file not surfaced" "$hot" "main.tf"
rh=$(printf '%s' "$out" | sed -n '/=== RULE_HINTS_FROM_TOOLING ===/,/=== END RULE_HINTS_FROM_TOOLING ===/p')
check "L/F: no denial signal from pi" "$rh" "RULES_SIGNAL=none_mechanical"
check "L/F: pi marks rule hints as unrecorded" "$rh" "RULE_HINTS_RECORDED=false"
check_absent "L/F: no per-kind denial lines" "$rh" "DENIAL_user"
sm=$(run_pi --summary)
check "L/G: recipe candidate count" "$sm" "RECIPE_CANDIDATE_COUNT=2"
check "L/G: hot file count" "$sm" "HOT_FILE_COUNT=1"
check "L/G: available flag" "$sm" "TRANSCRIPT_AVAILABLE=true"
check "L/G: format in summary" "$sm" "TRANSCRIPT_FORMAT=pi"

# --- TEST M: pi guards ---------------------------------------------------------
# M1: a pi-shaped file under the Claude projects dir is not read as Claude.
PI_IN_CLAUDE="$SANDBOX/pi-in-claude/-slug"
mkdir -p "$PI_IN_CLAUDE"
cp "$PI_FILE" "$PI_IN_CLAUDE/$SID.jsonl"
out=$(DISTILL_SURVEY_PROJECTS_DIR="$SANDBOX/pi-in-claude" bash "$COLLECTOR" --session-id "$SID" --project-dir "$PROJ")
check "M1: pi file under Claude projects dir → unavailable" "$out" "TRANSCRIPT_AVAILABLE=false"
check_absent "M1: never reported as a Claude transcript" "$out" "TRANSCRIPT_FORMAT=claude-code"
# M1 guard integrity: the same Claude lookup with PI_SESSION_FILE set falls back to pi.
out=$(DISTILL_SURVEY_PROJECTS_DIR="$SANDBOX/pi-in-claude" PI_SESSION_FILE="$PI_FILE" \
  bash "$COLLECTOR" --session-id "$SID" --project-dir "$PROJ")
check "M1: rejected Claude match still falls back to PI_SESSION_FILE" "$out" "TRANSCRIPT_FORMAT=pi"
# M2: PI_SESSION_FILE pointing at a non-pi (Claude-shaped) file SKIPs.
out=$(DISTILL_SURVEY_PROJECTS_DIR="$NO_CLAUDE" PI_SESSION_FILE="$SLUG/$SID.jsonl" \
  bash "$COLLECTOR" --project-dir "$PROJ")
check "M2: non-pi PI_SESSION_FILE → unavailable" "$out" "TRANSCRIPT_AVAILABLE=false"
check "M2: STATUS SKIP" "$out" "STATUS=SKIP"
# M3: PI_SESSION_FILE naming a missing file SKIPs and exits 0.
out=$(DISTILL_SURVEY_PROJECTS_DIR="$NO_CLAUDE" PI_SESSION_FILE="$SANDBOX/nope.jsonl" \
  bash "$COLLECTOR" --project-dir "$PROJ")
rc=$?
check "M3: missing PI_SESSION_FILE exits 0" "$rc" "0"
check "M3: missing PI_SESSION_FILE → unavailable" "$out" "TRANSCRIPT_AVAILABLE=false"
# M4: the Claude transcript wins when both are present.
out=$(PI_SESSION_FILE="$PI_FILE" run)
check "M4: Claude lookup stays authoritative over PI_SESSION_FILE" "$out" "TRANSCRIPT_FORMAT=claude-code"
check "M4: Claude denial signal still present" "$out" "DENIAL_user-rejected=2"

# --- TEST N: argument stability + compound-line exclusion (#2683) -------------
# A shape whose whole reusable payload sits in placeholders that never repeat is
# a one-off wearing a recurrence count — it must not be a candidate. Every
# negative below is PAIRED with a positive so the filter cannot silently
# over-filter into "drop anything with a placeholder".
N_PROJECTS="$SANDBOX/n-projects"
N_SLUG="$N_PROJECTS/-n-slug"
N_PROJ="$SANDBOX/n-proj"
mkdir -p "$N_SLUG" "$N_PROJ"
cp "$PROJ/justfile" "$N_PROJ/justfile"
N_SID="33333333-3333-3333-3333-333333333333"
{
  bash_line "gh api repos/a/b/rulesets/1 --jq '.rules'"   # <path>/<str> never repeat
  bash_line "sed -n '1,50p' docs/stable.md"               # <path> DOES repeat below
  bash_line "git show abc123:docs/x.md | sed -n '1,20p'"  # pipeline, args never repeat
  bash_line 'until [ "pending" = "" ]; do sleep 20; done; echo done; gh pr checks 42 --watch'
  bash_line 'npm run build:prod'                          # fully literal, bracketed
  bash_line 'gh pr create --title="docs: first one"'      # placeholder EMBEDDED in a flag
  bash_line 'ruff check --output-format=concise'          # same --flag= idiom, but literal
  bash_line "rsync -a 'a,b' src/alpha/ dst/beta/ node_modules/"   # 4 stable args, one with a comma
  bash_line 'git commit -m "wip"'                         # commit delimiter
} > "$N_SLUG/$N_SID.jsonl"
{
  bash_line "gh api repos/c/d/pulls/2 --jq '.title'"
  bash_line "sed -n '5,9p' docs/stable.md"                # same path, different range
  bash_line "git show def456:docs/y.md | sed -n '1,30p'"
  bash_line 'gh pr create --title="docs: second one"'
  bash_line "rsync -a 'a,b' src/alpha/ dst/beta/ node_modules/"
} > "$N_SLUG/44444444-4444-4444-4444-444444444444.jsonl"
{
  bash_line "gh api repos/e/f/issues/9 --jq '.body'"
  bash_line 'gh pr create --title="docs: third one"'
} > "$N_SLUG/55555555-5555-5555-5555-555555555555.jsonl"

run_n() {
  DISTILL_SURVEY_PROJECTS_DIR="$N_PROJECTS" DISTILL_SURVEY_JUST_BIN="$STUB/just" \
    bash "$COLLECTOR" --session-id "$N_SID" --project-dir "$N_PROJ" "$@"
}
nout=$(run_n)
ncand=$(printf '%s' "$nout" | sed -n '/=== RECIPE_CANDIDATES ===/,/=== END RECIPE_CANDIDATES ===/p')
check "N: all three sessions are in the window" "$nout" "SESSIONS_SCANNED=3"
# Negatives — the exact shapes the issue named.
check_absent "N: placeholder-only shape over unrelated sessions dropped" "$ncand" "gh api <path> --jq <str>"
check_absent "N: pipeline whose args never repeat dropped" "$ncand" "git show <path> | sed -n <str>"
check_absent "N: compound wait-loop dropped" "$ncand" "until ["
check_absent "N: nothing of the compound line survives" "$ncand" "gh pr checks"
# A placeholder EMBEDDED in a flag (`--title="..."`) is still a placeholder: three
# unrelated PR titles over three sessions must not collapse into one candidate,
# and must never be mislabelled `_STABLE_ARGS=literal`.
check_absent "N: embedded --flag=<str> over unrelated sessions dropped" "$ncand" "--title=<str>"
check_absent "N: embedded-placeholder shape never reaches a candidate" "$ncand" "gh pr create"
# Positives — the counter-assertions that pin the filter against over-reach.
check "N: placeholder shape WITH a repeated concrete arg survives" "$ncand" "sed -n <str> <path>"
check "N: the repeated concrete arg is reported" "$ncand" "_STABLE_ARGS=docs/stable.md"
check "N: fully literal bracketed command survives" "$ncand" "npm run build:prod"
check "N: literal shape labelled as stable-by-construction" "$ncand" "_STABLE_ARGS=literal"
check "N: a LITERAL --flag=value shape is not collateral damage" "$ncand" "ruff check --output-format=concise"
# _STABLE_ARGS is sorted (deterministic KEY=VALUE output) and capped at three
# ENTRIES — a concrete value containing a comma must not truncate the list.
check "N: stable args are sorted and capped by entry, not by comma count" "$ncand" \
  "_STABLE_ARGS='a,b',dst/beta/,node_modules/"
check "N: only the four stable shapes remain" "$ncand" "COUNT=4"
check "N: summary count agrees with the digest" "$(run_n --summary)" "RECIPE_CANDIDATE_COUNT=4"

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
