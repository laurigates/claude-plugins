#!/usr/bin/env bash
# Regression tests for distill-survey.sh — the read-only distill collector.
# Covers: churn exclusion, cross-session recurrence, commit-bracketing,
# just-coverage exclusion, exact HOT_FILES, .claude/worktrees prune, SKIP on
# empty/missing, --summary shape, and the RULE_HINTS_FROM_TOOLING denial signal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="$SCRIPT_DIR/../distill-survey.sh"

pass=0
fail=0
check() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "  expected to find: $needle"
  fi
}
check_absent() {
  local label="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF "$needle"; then
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
# used to exclude session commands as already-covered.
STUB="$SANDBOX/stub"
mkdir -p "$STUB"
cat > "$STUB/just" <<'JUSTSTUB'
#!/usr/bin/env bash
case "$*" in
  *"--dump"*) echo '{"recipes":{"deploy":{"body":[["helm upgrade myrel ./chart"]]}}}' ;;
  *) exit 0 ;;
esac
JUSTSTUB
chmod +x "$STUB/just"

# --- Current session transcript ---------------------------------------------
bash_line() { printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":%s}}]}}\n' "$(jq -Rn --arg c "$1" '$c')"; }
{
  bash_line 'git status'                       # churn, before commit
  bash_line 'terraform apply -auto-approve'    # recurs across sessions → candidate
  bash_line 'kubectl apply -f deploy/'         # bracketed → candidate
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
out=$(run)
check "A: transcript available" "$out" "TRANSCRIPT_AVAILABLE=true"
check "A: both sessions scanned" "$out" "SESSIONS_SCANNED=2"
check "A: just dump consumed" "$out" "JUST_AVAILABLE=true"
check "A: meta STATUS OK" "$out" "$(printf '=== SESSION_META ===')"

# --- TEST B: recipe candidates ----------------------------------------------
cand=$(printf '%s' "$out" | sed -n '/=== RECIPE_CANDIDATES ===/,/=== END RECIPE_CANDIDATES ===/p')
check "B: cross-session recurring command surfaces" "$cand" "terraform apply -auto-approve"
check "B: recurrence count is 2" "$cand" "_SESSIONS=2"
check "B: commit-bracketed command surfaces" "$cand" "kubectl apply -f <path>"
check "B: bracketed flag set" "$cand" "_BRACKETED=yes"
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

echo "---"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
