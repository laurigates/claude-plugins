#!/usr/bin/env bash
# Regression tests for workflow-capture-survey.sh — the read-only collector
# behind session-plugin:session-workflow-capture.
#
# Covers: run listing from persisted scripts, mode join from the transcript
# (inline / scriptPath / name / resume), journal agent counts, origin
# classification (authored / adapted / verbatim, incl. a meta-less template
# matched by bytes), meta.name parsing (single-line meta, double quotes with an
# apostrophe), signals, owning-repo lookup from a plugin manifest, the calling
# repo from git, the plugins-repo settings override, SKIP on a missing session,
# --summary shape, and --usage counts.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR="$SCRIPT_DIR/../workflow-capture-survey.sh"
# Keep git hermetic: an inherited GIT_DIR would point every git call elsewhere (#1745).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR

pass=0
fail=0
check() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qxF -e "$needle" <<<"$haystack"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $label"
    echo "  expected line: $needle"
  fi
}
check_absent() {
  local label="$1" haystack="$2" needle="$3"
  if grep -qF -e "$needle" <<<"$haystack"; then
    fail=$((fail + 1))
    echo "FAIL: $label (unexpected: $needle)"
  else
    pass=$((pass + 1))
  fi
}
value_of() { grep -m1 "^$2=" <<<"$1" | cut -d= -f2-; }

SANDBOX="$(mktemp -d)" || { echo "mktemp failed"; exit 1; }
[ -n "$SANDBOX" ] || { echo "empty sandbox path"; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

HOME_DIR="$SANDBOX/home"
PROJECTS="$HOME_DIR/.claude/projects"
CACHE="$HOME_DIR/.claude/plugins/cache"
PROJ="$SANDBOX/proj"
SID="22222222-2222-2222-2222-222222222222"
SLUG_DIR="$PROJECTS/-sandbox-proj"
SESS="$SLUG_DIR/$SID"
mkdir -p "$SESS/workflows/scripts" "$PROJ/.claude/workflows" "$HOME_DIR/.claude/workflows"

# Calling repo: a git repo whose origin names me/proj.
git -C "$PROJ" init -q
git -C "$PROJ" remote add origin git@github.com:me/proj.git

# --- known workflows ---------------------------------------------------------
cat > "$PROJ/.claude/workflows/saved.workflow.js" <<'EOF'
export const meta = {
  name: 'saved-flow',
  description: 'A project-saved workflow',
}
const r = await agent('do it', {})
return r
EOF
cat > "$HOME_DIR/.claude/workflows/user.js" <<'EOF'
export const meta = { name: 'user-flow', description: 'User scope' }
return await agent('x', {})
EOF
TPL_ROOT="$CACHE/mkt/plug/1.0.0"
mkdir -p "$TPL_ROOT/.claude-plugin" "$TPL_ROOT/skills/s/workflows"
printf '{"name":"plug","repository":"https://github.com/acme/plugs"}\n' > "$TPL_ROOT/.claude-plugin/plugin.json"
cat > "$TPL_ROOT/skills/s/workflows/tpl.workflow.js" <<'EOF'
export const meta = {
  name: 'tpl',
  description: 'Bundled template',
  phases: [{ title: 'Fan', detail: 'one agent per item' }],
}
phase('Fan')
const out = await parallel(args.items.slice(0, 8).map(i => () => agent(`work ${i}`, {})))
return out
EOF
# A bundled template with no meta block at all (test-analyze's shape).
cat > "$TPL_ROOT/skills/s/workflows/nometa.workflow.js" <<'EOF'
// no meta here
return await agent('only', {})
EOF

# --- session runs --------------------------------------------------------------
# Run 1+2: an authored workflow run twice; run 2 leaves an agent unfinished.
cat > "$SESS/workflows/scripts/fresh-flow-wf_aaaa1111-001.js" <<'EOF'
export const meta = {
  name: 'fresh-flow',
  description: 'Authored in session',
  phases: [{ title: 'A' }, { title: 'B' }],
}
phase('A')
const a = await agent('one', {})
phase('B')
const b = await agent('two', {})
const c = await agent('three', {})
return [a, b, c]
EOF
cp "$SESS/workflows/scripts/fresh-flow-wf_aaaa1111-001.js" "$SESS/workflows/scripts/fresh-flow-wf_aaaa2222-002.js"
printf '\n// tweak\n' >> "$SESS/workflows/scripts/fresh-flow-wf_aaaa2222-002.js"
touch -t 202601010000.01 "$SESS/workflows/scripts/fresh-flow-wf_aaaa1111-001.js"
touch -t 202601010000.02 "$SESS/workflows/scripts/fresh-flow-wf_aaaa2222-002.js"
# Run 3: the bundled template, adapted (same meta.name, different bytes).
sed 's/slice(0, 8)/slice(0, 4)/' "$TPL_ROOT/skills/s/workflows/tpl.workflow.js" > "$SESS/workflows/scripts/tpl-wf_bbbb3333-003.js"
touch -t 202601010000.03 "$SESS/workflows/scripts/tpl-wf_bbbb3333-003.js"
# Run 4: the project-saved workflow run by name (persisted bytes identical).
cp "$PROJ/.claude/workflows/saved.workflow.js" "$SESS/workflows/scripts/saved-flow-wf_cccc4444-004.js"
touch -t 202601010000.04 "$SESS/workflows/scripts/saved-flow-wf_cccc4444-004.js"
# Run 5: the meta-less template pasted inline unchanged.
cp "$TPL_ROOT/skills/s/workflows/nometa.workflow.js" "$SESS/workflows/scripts/workflow-wf_dddd5555-005.js"
touch -t 202601010000.05 "$SESS/workflows/scripts/workflow-wf_dddd5555-005.js"
# Run 6: single-line meta, double quotes with an apostrophe.
cat > "$SESS/workflows/scripts/dq-flow-wf_eeee6666-006.js" <<'EOF'
export const meta = { name: "dq-flow", description: "Don't panic" }
return await agent('x', {})
EOF
touch -t 202601010000.06 "$SESS/workflows/scripts/dq-flow-wf_eeee6666-006.js"

journal() { # runId started returned
  local d="$SESS/subagents/workflows/$1" i
  mkdir -p "$d"
  { echo '{"type":"launched"}'
    for i in $(seq 1 "$2"); do printf '{"type":"started","key":"k%s","agentId":"a%s"}\n' "$i" "$i"; done
    for i in $(seq 1 "$3"); do printf '{"type":"result","key":"k%s","agentId":"a%s"}\n' "$i" "$i"; done
  } > "$d/journal.jsonl"
}
journal wf_aaaa1111-001 3 3
journal wf_aaaa2222-002 3 2
journal wf_bbbb3333-003 4 4

# Main transcript: tool_use + result per run (run 6 has no transcript record).
tu() { # id input-json
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"%s","name":"Workflow","input":%s}]}}\n' "$1" "$2"
}
tr_() { # id runId workflowName
  printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"%s","content":"ok"}]},"toolUseResult":{"status":"async_launched","runId":"%s","workflowName":"%s"}}\n' "$1" "$2" "$3"
}
{
  tu t1 '{"script":"export const meta = {}","args":{}}'; tr_ t1 wf_aaaa1111-001 fresh-flow
  tu t2 '{"scriptPath":"/x/fresh-flow-wf_aaaa1111-001.js","resumeFromRunId":"wf_aaaa1111-001"}'; tr_ t2 wf_aaaa2222-002 fresh-flow
  tu t3 '{"script":"..."}'; tr_ t3 wf_bbbb3333-003 tpl
  tu t4 '{"name":"saved-flow"}'; tr_ t4 wf_cccc4444-004 saved-flow
  tu t5 '{"script":"..."}'; tr_ t5 wf_dddd5555-005 workflow
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"no tool"}]}}\n'
} > "$SLUG_DIR/$SID.jsonl"

run() { WORKFLOW_CAPTURE_PROJECTS_DIR="$PROJECTS" WORKFLOW_CAPTURE_PLUGIN_CACHE="$CACHE" \
          bash "$COLLECTOR" --home-dir "$HOME_DIR" --project-dir "$PROJ" "$@"; }

# === TEST A: full session listing ==================================================
OUT=$(run --session-id "$SID"); rc=$?
check "A exit 0" "rc=$rc" "rc=0"
check "A transcript found" "$OUT" "TRANSCRIPT_AVAILABLE=true"
check "A calling repo from git remote" "$OUT" "CALLING_REPO=me/proj"
check "A run count" "$OUT" "RUN_COUNT=6"
check "A run 1 mode inline" "$OUT" "RUN_1_MODE=inline"
check "A run 2 mode scriptPath" "$OUT" "RUN_2_MODE=scriptPath"
check "A run 2 resume" "$OUT" "RUN_2_RESUME=true"
check "A run 2 spawned" "$OUT" "RUN_2_AGENTS_SPAWNED=3"
check "A run 2 returned" "$OUT" "RUN_2_AGENTS_RETURNED=2"
check "A run 4 mode name" "$OUT" "RUN_4_MODE=name"
check "A run 4 verbatim saved" "$OUT" "RUN_4_MATCH=verbatim|project:saved-flow"
check "A run 6 no transcript record" "$OUT" "RUN_6_MODE=unknown"
check "A workflow count" "$OUT" "WORKFLOW_COUNT=5"
check "A fresh-flow name" "$OUT" "WORKFLOW_1_NAME=fresh-flow"
check "A fresh-flow runs" "$OUT" "WORKFLOW_1_RUNS=2"
check "A fresh-flow authored" "$OUT" "WORKFLOW_1_ORIGIN=authored"
check "A fresh-flow signals" "$OUT" "WORKFLOW_1_SIGNALS=reran unfinished_agents resumed"
check "A fresh-flow agent sites" "$OUT" "WORKFLOW_1_AGENT_SITES=3"
check "A fresh-flow phase calls" "$OUT" "WORKFLOW_1_PHASE_CALLS=2"
check "A tpl adapted" "$OUT" "WORKFLOW_2_ORIGIN=adapted"
check "A tpl match" "$OUT" "WORKFLOW_2_MATCH=bundled:tpl"
check "A tpl owning repo from plugin.json" "$OUT" "WORKFLOW_2_MATCH_REPO=acme/plugs"
check "A tpl signal" "$OUT" "WORKFLOW_2_SIGNALS=adapted_known"
check "A saved verbatim" "$OUT" "WORKFLOW_3_ORIGIN=verbatim"
check "A saved owning repo is calling repo" "$OUT" "WORKFLOW_3_MATCH_REPO=me/proj"
check "A meta-less template matched by bytes" "$OUT" "WORKFLOW_4_MATCH=bundled:nometa"
check "A meta-less template verbatim" "$OUT" "WORKFLOW_4_ORIGIN=verbatim"
check "A single-line double-quoted meta" "$OUT" "WORKFLOW_5_NAME=dq-flow"
check "A capture candidates (fresh-flow, tpl, dq-flow)" "$OUT" "CAPTURE_CANDIDATE_COUNT=3"
check "A friction signals (fresh-flow, tpl)" "$OUT" "FRICTION_SIGNAL_COUNT=2"
check "A known user scope" "$OUT" "SAVED_USER_COUNT=1"
check "A known project scope" "$OUT" "SAVED_PROJECT_COUNT=1"
check "A known bundled" "$OUT" "BUNDLED_TEMPLATE_COUNT=2"
check "A plugins repo from own manifest" "$OUT" "PLUGINS_REPO_SOURCE=manifest"
check "A status" "$OUT" "STATUS=OK"

# === TEST B: settings override for the plugins repo ===================================
printf -- '---\nworkflow_capture_repo: "me/my-plugins"\n---\nbody\n' > "$PROJ/.claude/session-plugin.local.md"
OUT=$(run --session-id "$SID" --summary)
check "B settings repo" "$OUT" "PLUGINS_REPO=me/my-plugins"
check "B settings source" "$OUT" "PLUGINS_REPO_SOURCE=settings-project"
check_absent "B --summary omits runs" "$OUT" "=== SESSION RUNS ==="
check_absent "B --summary omits known list" "$OUT" "KNOWN_1="
check "B --summary keeps counts" "$OUT" "CAPTURE_CANDIDATE_COUNT=3"
rm -f "$PROJ/.claude/session-plugin.local.md"
printf -- '---\njournal: none\nworkflow_capture_repo: me/user-plugins\n---\n' > "$HOME_DIR/.claude/session-plugin.local.md"
OUT=$(run --session-id "$SID" --summary)
check "B user settings source" "$OUT" "PLUGINS_REPO_SOURCE=settings-user"
check "B user settings repo" "$OUT" "PLUGINS_REPO=me/user-plugins"
rm -f "$HOME_DIR/.claude/session-plugin.local.md"

# === TEST C: SKIP paths ===============================================================
OUT=$(run --session-id 99999999-9999-9999-9999-999999999999); rc=$?
check "C unknown session exit 0" "rc=$rc" "rc=0"
check "C unknown session skip" "$OUT" "STATUS=SKIP"
check "C unknown session unavailable" "$OUT" "TRANSCRIPT_AVAILABLE=false"
check "C unknown session zero candidates" "$OUT" "CAPTURE_CANDIDATE_COUNT=0"
OUT=$(run); rc=$?
check "C no session id skip" "$OUT" "SKIP_REASON=no --session-id"
check "C no session id exit 0" "rc=$rc" "rc=0"
OUT=$(WORKFLOW_CAPTURE_PROJECTS_DIR="$SANDBOX/none" bash "$COLLECTOR" --session-id "$SID" --home-dir "$HOME_DIR" --project-dir "$PROJ")
check "C no projects dir skip" "$OUT" "SKIP_REASON=no projects dir"

# === TEST D: --usage =================================================================
# The current project's slug is derived from --project-dir.
USAGE_SLUG="$PROJECTS/$(printf '%s' "$PROJ" | sed 's/[^A-Za-z0-9]/-/g')"
mkdir -p "$USAGE_SLUG"
cp "$SLUG_DIR/$SID.jsonl" "$USAGE_SLUG/$SID.jsonl"
OUT=$(run --usage); rc=$?
check "D exit 0" "rc=$rc" "rc=0"
check "D sessions scanned" "$OUT" "SESSIONS_SCANNED=1"
check "D calls" "$OUT" "WORKFLOW_CALLS=5"
check "D inline" "$OUT" "CALLS_INLINE=3"
check "D scriptPath" "$OUT" "CALLS_SCRIPT_PATH=1"
check "D by name" "$OUT" "CALLS_BY_NAME=1"
check "D resume" "$OUT" "CALLS_RESUME=1"
check "D named" "$OUT" "NAMED_1=saved-flow|1"
check "D run name top" "$OUT" "RUN_NAME_1=fresh-flow|2"
check "D runs matching a known name (tpl, saved-flow)" "$OUT" "RUNS_MATCHING_KNOWN_NAME=2"
check "D current scope" "$OUT" "PROJECT_SCOPE=current"
# --all-projects also reads the -sandbox-proj slug.
OUT=$(run --usage --all-projects)
check "D all projects" "$OUT" "SESSIONS_SCANNED=2"
check "D all projects calls" "$OUT" "WORKFLOW_CALLS=10"
OUT=$(run --usage --all-projects --window-sessions 1)
check "D window caps sessions" "$OUT" "SESSIONS_SCANNED=1"
OUT=$(WORKFLOW_CAPTURE_PROJECTS_DIR="$SANDBOX/none" bash "$COLLECTOR" --usage --home-dir "$HOME_DIR" --project-dir "$PROJ")
check "D usage skip without projects dir" "$OUT" "STATUS=SKIP"

# === TEST E: review hardening ========================================================
P2="$SANDBOX/p2"; H2="$SANDBOX/h2"; PR2="$H2/.claude/projects"; C2="$H2/.claude/plugins/cache"
SID2="33333333-3333-3333-3333-333333333333"
mkdir -p "$P2" "$H2/.claude/workflows" "$PR2/-slug-a" "$PR2/-slug-b/$SID2/workflows/scripts" "$C2"
git -C "$P2" init -q
run2() { WORKFLOW_CAPTURE_PROJECTS_DIR="$PR2" WORKFLOW_CAPTURE_PLUGIN_CACHE="$C2" \
           bash "$COLLECTOR" --home-dir "$H2" --project-dir "$P2" "$@"; }

# Calling repo: GitHub only; other hosts and GitLab subgroups are unknown.
git -C "$P2" remote add origin ssh://git@git.corp.example:2222/team/svc.git
OUT=$(run2 --session-id "$SID2" --summary)
check "E non-GitHub origin is unknown" "$OUT" "CALLING_REPO=unknown"
check "E non-GitHub host reported" "$OUT" "CALLING_REPO_HOST=git.corp.example"
git -C "$P2" remote set-url origin https://gitlab.com/group/sub/repo.git
OUT=$(run2 --session-id "$SID2" --summary)
check "E GitLab subgroup is unknown" "$OUT" "CALLING_REPO=unknown"
OUT=$(GH_HOST=gitlab.com run2 --session-id "$SID2" --summary)
check "E GH_HOST names an enterprise host" "$OUT" "CALLING_REPO=group/sub"
git -C "$P2" remote remove origin
git -C "$P2" remote add upstream https://github.com/acme/app.git
OUT=$(run2 --session-id "$SID2" --summary)
check "E first remote stands in for origin" "$OUT" "CALLING_REPO=acme/app"

# Split session: the transcript in one slug, the session dir in another.
SC="$PR2/-slug-b/$SID2/workflows/scripts"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"u1","name":"Workflow","input":{"name":"saved2"}}]}}\n' > "$PR2/-slug-a/$SID2.jsonl"
printf 'NOT JSON {{{\n' >> "$PR2/-slug-a/$SID2.jsonl"
printf '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"u1","content":"ok"}]},"toolUseResult":{"runId":"wf_ffff0001-001","workflowName":"saved2"}}\n' >> "$PR2/-slug-a/$SID2.jsonl"
# By name, but the persisted bytes differ from the saved file: still verbatim.
printf "export const meta = { name: 'saved2', description: 'x' }\nreturn await agent('a', {})\n" > "$H2/.claude/workflows/saved2.js"
printf "export const meta = { name: 'saved2', description: 'x' }\n// harness-added line\nreturn await agent('a', {})\n" > "$SC/saved2-wf_ffff0001-001.js"
touch -t 202601010000.01 "$SC/saved2-wf_ffff0001-001.js"
OUT=$(run2 --session-id "$SID2")
check "E split session keeps the transcript" "$OUT" "RUN_1_MODE=name"
check "E malformed line does not drop the join" "$OUT" "RUN_1_RUN_ID=wf_ffff0001-001"
check "E by-name run with other bytes is verbatim" "$OUT" "WORKFLOW_1_ORIGIN=verbatim"

# A user-scope copy of a bundled template: the bundled original wins the match.
TR="$C2/mkt/plug/2.0.0"; mkdir -p "$TR/.claude-plugin" "$TR/skills/s/workflows"
printf '{"name":"plug","repository":{"url":"git+https://github.com/acme/plugs.git"}}\n' > "$TR/.claude-plugin/plugin.json"
printf "export const meta = { name: 'tpl2', description: 'x' }\nreturn await agent('t', {})\n" > "$TR/skills/s/workflows/tpl2.workflow.js"
cp "$TR/skills/s/workflows/tpl2.workflow.js" "$H2/.claude/workflows/tpl2.js"
cp "$TR/skills/s/workflows/tpl2.workflow.js" "$SC/tpl2-wf_ffff0002-002.js"
touch -t 202601010000.02 "$SC/tpl2-wf_ffff0002-002.js"
# Two unrelated scripts without meta: two workflows, no false rerun.
printf "return await agent('one', {})\n" > "$SC/workflow-wf_ffff0003-003.js"
printf "return await agent('two', {})\n" > "$SC/workflow-wf_ffff0004-004.js"
touch -t 202601010000.03 "$SC/workflow-wf_ffff0003-003.js"
touch -t 202601010000.04 "$SC/workflow-wf_ffff0004-004.js"
# A name with a backslash still groups with itself.
printf "export const meta = { name: 'scan\\\\tpaths', description: 'x' }\nreturn await agent('s', {})\n" > "$SC/scan-wf_ffff0005-005.js"
touch -t 202601010000.05 "$SC/scan-wf_ffff0005-005.js"
OUT=$(run2 --session-id "$SID2")
check "E bundled beats a user copy" "$OUT" "WORKFLOW_2_MATCH=bundled:tpl2"
check "E plugin repo from an object repository url" "$OUT" "WORKFLOW_2_MATCH_REPO=acme/plugs"
check "E unnamed scripts stay apart" "$OUT" "WORKFLOW_COUNT=5"
check_absent "E no false rerun for unnamed scripts" "$OUT" "SIGNALS=reran"
check "E backslash name groups with itself" "$OUT" "WORKFLOW_5_AGENT_SITES=1"

# --usage skips the corrupt line and counts the rest; ISSUE_COUNT is present.
OUT=$(run2 --usage --all-projects)
check "E usage counts past a corrupt line" "$OUT" "CALLS_BY_NAME=1"
check "E usage emits ISSUE_COUNT" "$OUT" "ISSUE_COUNT=0"

echo ""
echo "workflow-capture-survey: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
