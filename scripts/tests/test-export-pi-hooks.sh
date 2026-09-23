#!/usr/bin/env bash
# test-export-pi-hooks.sh — regression tests for
# scripts/generate-pi-hook-extension.py (issue #2634).
#
# Mirrors test-export-opencode-hooks.sh (a)-(d):
#   (a) every script the generated extension references is copied beside it,
#   (b) blocking semantics survive (exit 2 / JSON deny -> { block: true, reason }),
#   (c) no literal ${CLAUDE_PLUGIN_ROOT} reaches executable code,
#   (d) prompt/agent hooks and events pi lacks are skipped, not broken.
# Plus the pi-specific invariants:
#   - a plugin that declares hooks ONLY inline in .claude-plugin/plugin.json is
#     projected (hooks-plugin holds the safety guards and has no hooks.json),
#   - a missing script fails OPEN at run time,
#   - nudge-class hooks are skipped by name (the safety allowlist),
#   - SessionStart consumers (drift-aggregator) run after the probes they read.
#
# The generated index.ts is plain JavaScript by design, so it is EXECUTED here
# under node with a stub `pi` object — the assertions are on what the handlers
# return, not on the generated text.
set -uo pipefail

test_script_dir="$(cd "$(dirname "$0")" && pwd)"
test_repo_root="$(cd "$test_script_dir/../.." && pwd)"
test_generator="$test_repo_root/scripts/generate-pi-hook-extension.py"

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP: node not available — the generated extension cannot be executed"
    exit 0
fi

pass=0
fail=0

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $label"
    fi
}

check_not() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        fail=$((fail + 1))
        echo "FAIL: $label"
    else
        pass=$((pass + 1))
    fi
}

# jq_is <label> <json> <jq-filter>: the filter must evaluate to true.
jq_is() {
    local label="$1" json="$2" filter="$3"
    if jq -e "$filter" >/dev/null 2>&1 <<<"$json"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $label"
        echo "      got: $(printf '%s' "$json" | cut -c1-300)"
    fi
}

# An operator's opt-out must not turn the real-hook assertions into no-ops.
unset CLAUDE_HOOKS_DISABLE_SECRET_PROTECTION

test_tmp="$(mktemp -d)"
if [ -z "$test_tmp" ] || [ ! -d "$test_tmp" ]; then echo "FAIL: mktemp"; exit 1; fi
trap 'rm -rf "$test_tmp"' EXIT

# drive <ext_dir> <mode> <spec-json>: import the generated extension with a stub
# pi and invoke one handler. Prints the handler's observable result as JSON.
write_driver() {
    local ext_dir="$1"
    cp "$ext_dir/index.ts" "$ext_dir/index.test.mjs"
    cat > "$ext_dir/driver.mjs" <<'JS'
import ext from "./index.test.mjs";
const handlers = {};
const sent = [];
ext({ on: (ev, fn) => { handlers[ev] = fn; }, sendMessage: (m, o) => sent.push({ m, o }) });
const [, , mode, raw] = process.argv;
const spec = JSON.parse(raw ?? "{}");
const ctx = {
  cwd: spec.cwd,
  hasUI: Boolean(spec.hasUI),
  ui: { confirm: async () => Boolean(spec.confirm) },
  sessionManager: { getSessionId: () => spec.sid ?? "pi-test-sid" },
};
let out;
if (mode === "handlers") {
  out = Object.keys(handlers).sort();
} else if (mode === "tool_call") {
  const ev = { toolName: spec.toolName, toolCallId: "t1", input: spec.input };
  const r = handlers.tool_call ? await handlers.tool_call(ev, ctx) : undefined;
  out = { result: r ?? null, input: ev.input };
} else if (mode === "tool_result") {
  const ev = { toolName: spec.toolName, toolCallId: "t1", input: spec.input,
               content: spec.content, isError: false };
  const r = handlers.tool_result ? await handlers.tool_result(ev, ctx) : undefined;
  out = { result: r ?? null };
} else if (mode === "session_start") {
  if (handlers.session_start) await handlers.session_start({ reason: spec.reason ?? "startup" }, ctx);
  out = { sent };
}
console.log(JSON.stringify(out));
JS
}

drive() {
    node "$1/driver.mjs" "$2" "$3" 2>/dev/null
}

# --- Fixture suite -----------------------------------------------------------
fx="$test_tmp/fixture-root"
work="$test_tmp/work"
signals="$test_tmp/signals"
mkdir -p "$fx" "$work" "$signals"

# hooks-plugin: hooks declared ONLY inline in plugin.json (no hooks.json).
mkdir -p "$fx/hooks-plugin/.claude-plugin" "$fx/hooks-plugin/hooks/lib"
cat > "$fx/hooks-plugin/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "hooks-plugin",
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/branch-protection.sh", "timeout": 5},
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/repo-deletion-safety.sh", "timeout": 5}
      ]},
      {"matcher": "Read|Edit|Write|Bash", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/secret-protection.sh", "timeout": 5}
      ]},
      {"matcher": "Workflow", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/external-pr-merge-guard.sh"}
      ]}
    ],
    "PostToolUse": [
      {"matcher": "Write|Edit|Bash", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/prose-house-style-nudge.sh"}
      ]}
    ],
    "SessionStart": [
      {"matcher": "", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/drift-aggregator.sh", "timeout": 5}
      ]}
    ],
    "Stop": [
      {"matcher": "", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/prose-house-style-nudge.sh"}
      ]}
    ],
    "SubagentStop": [
      {"matcher": "", "hooks": [{"type": "prompt", "prompt": "judge the subagent"}]}
    ]
  }
}
JSON
cat > "$fx/hooks-plugin/hooks/branch-protection.sh" <<'SH'
#!/usr/bin/env bash
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in *DANGER*) echo "BLOCKED-BY-FIXTURE: $cmd" >&2; exit 2 ;; esac
exit 0
SH
cat > "$fx/hooks-plugin/hooks/repo-deletion-safety.sh" <<'SH'
#!/usr/bin/env bash
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in *FAILOPEN*) echo "should never run once deleted" >&2; exit 2 ;; esac
exit 0
SH
cat > "$fx/hooks-plugin/hooks/secret-protection.sh" <<'SH'
#!/usr/bin/env bash
input=$(cat)
fp=$(jq -r '.tool_input.file_path // empty' <<<"$input")
tool=$(jq -r '.tool_name' <<<"$input")
case "$fp" in
  *.env) jq -nc --arg r "DENY-$tool:$fp" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
esac
new=$(jq -r '.tool_input.new_string // empty' <<<"$input")
case "$new" in *SECRET-TOKEN*) echo "edit carries a secret" >&2; exit 2 ;; esac
exit 0
SH
cat > "$fx/hooks-plugin/hooks/external-pr-merge-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fx/hooks-plugin/hooks/prose-house-style-nudge.sh" <<'SH'
#!/usr/bin/env bash
echo "style nudge" >&2
exit 2
SH
cat > "$fx/hooks-plugin/hooks/lib/drift-protocol.sh" <<'SH'
#!/usr/bin/env bash
drift_write() { mkdir -p "$1"; printf '%s' "$2" > "$1/git.txt"; }
SH
cat > "$fx/hooks-plugin/hooks/drift-aggregator.sh" <<'SH'
#!/usr/bin/env bash
sid=$(jq -r '.session_id')
got=$(cat "$DRIFT_TEST_SIGNALS/$sid/git.txt" 2>/dev/null || echo MISSING)
jq -nc --arg c "AGG:$got" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
SH

# git-plugin: hooks.json, plus a plugin.json POINTER that must not double-read.
mkdir -p "$fx/git-plugin/.claude-plugin" "$fx/git-plugin/hooks"
printf '%s\n' '{"name": "git-plugin", "hooks": "./hooks.json"}' \
    > "$fx/git-plugin/.claude-plugin/plugin.json"
cat > "$fx/git-plugin/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/check-branch-sync-on-push.sh", "timeout": 5}
      ]},
      {"matcher": "mcp__github__create_pull_request", "hooks": [
        {"type": "prompt", "prompt": "check closing keywords"}
      ]}
    ],
    "SessionStart": [
      {"matcher": "", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/git-drift-probe.sh", "timeout": 5}
      ]}
    ]
  }
}
JSON
cat > "$fx/git-plugin/hooks/check-branch-sync-on-push.sh" <<'SH'
#!/usr/bin/env bash
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in *"git push"*)
  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"ASK-branch-behind"}}' ;;
esac
exit 0
SH
# The probe sleeps before writing, so an aggregator that ran concurrently with
# it (rather than after it) would read MISSING.
cat > "$fx/git-plugin/hooks/git-drift-probe.sh" <<'SH'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../../hooks-plugin/hooks/lib/drift-protocol.sh"
sid=$(jq -r '.session_id')
sleep 0.4
drift_write "$DRIFT_TEST_SIGNALS/$sid" "probe-ran:$CLAUDE_PLUGIN_ROOT"
SH

# kubernetes-plugin: inline hooks; the dry-run injector returns updatedInput.
mkdir -p "$fx/kubernetes-plugin/.claude-plugin" "$fx/kubernetes-plugin/hooks"
cat > "$fx/kubernetes-plugin/.claude-plugin/plugin.json" <<'JSON'
{"name": "kubernetes-plugin", "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [
  {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/inject-kubectl-dry-run.sh"}
]}]}}
JSON
cat > "$fx/kubernetes-plugin/hooks/inject-kubectl-dry-run.sh" <<'SH'
#!/usr/bin/env bash
cmd=$(jq -r '.tool_input.command // empty')
case "$cmd" in "kubectl apply"*)
  jq -nc --arg c "$cmd --dry-run=client" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"allow",updatedInput:{command:$c}}}' ;;
esac
exit 0
SH

# extra-plugin: a PostToolUse note hook, admitted only through --allow, plus the
# skip classes a manifest can carry.
mkdir -p "$fx/extra-plugin/hooks"
cat > "$fx/extra-plugin/hooks.json" <<'JSON'
{
  "hooks": {
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/note.sh"},
        {"type": "command", "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/oddball.py"},
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/missing.sh"}
      ]},
      {"matcher": "Write(docs/adrs/**)", "hooks": [
        {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/note.sh", "timeout": 3000}
      ]}
    ],
    "PreCompact": [
      {"matcher": "auto", "hooks": [{"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/note.sh"}]}
    ]
  }
}
JSON
cat > "$fx/extra-plugin/hooks/note.sh" <<'SH'
#!/usr/bin/env bash
echo "NOTE-FROM-POST-HOOK" >&2
exit 2
SH

out="$test_tmp/out"
report="$(python3 "$test_generator" "$fx" "$out" \
    --allow extra-plugin/note.sh --allow extra-plugin/missing.sh)"
gen_rc=$?
check "fixture: generator exits 0" test "$gen_rc" -eq 0
ext="$out/extensions/plugin-hooks"
check "fixture: extension emitted" test -f "$ext/index.ts"
check "fixture: STATUS=OK" grep -qx 'STATUS=OK' <<<"$report"

# Inline plugin.json manifests are discovered (the hooks.json-only glob is the defect).
check "fixture: inline-only hooks-plugin discovered" \
    grep -q '^PLUGIN=hooks-plugin SOURCES=plugin.json EXPORTED=4 ' <<<"$report"
check "fixture: inline-only kubernetes-plugin discovered" \
    grep -q '^PLUGIN=kubernetes-plugin SOURCES=plugin.json EXPORTED=1 ' <<<"$report"
check "fixture: plugin.json pointer to hooks.json is not read twice" \
    grep -q '^PLUGIN=git-plugin SOURCES=hooks.json EXPORTED=2 ' <<<"$report"
check "fixture: INLINE_MANIFESTS counts both inline plugins" \
    grep -qx 'INLINE_MANIFESTS=2' <<<"$report"

# Nudges are skipped by name — and are absent from executable code.
check "fixture: nudge skipped by name (PostToolUse)" \
    grep -q 'SKIP event=PostToolUse matcher=Write|Edit|Bash type=command script=prose-house-style-nudge.sh reason=not in the pi safety allowlist' <<<"$report"
check_not "fixture: nudge script not copied" \
    test -e "$ext/hook-scripts/hooks-plugin/hooks/prose-house-style-nudge.sh"
check_not "fixture: nudge absent from executable code" \
    bash -c "grep -vE '^\s*//' '$ext/index.ts' | grep -q 'prose-house-style-nudge'"

# (d) skip classes are reported, not broken.
check "fixture: prompt hook skipped" \
    grep -q 'type=prompt script=- reason=pi has no model-evaluation hook' <<<"$report"
check "fixture: Stop event skipped with its script named" \
    grep -q 'SKIP event=Stop matcher="" type=command script=prose-house-style-nudge.sh reason=no pi equivalent for this event' <<<"$report"
check "fixture: PreCompact skipped" \
    grep -q 'SKIP event=PreCompact .*reason=no pi equivalent for this event' <<<"$report"
check "fixture: tool pi lacks (Workflow) skipped" \
    grep -q 'script=external-pr-merge-guard.sh reason=no pi tool for matcher: Workflow' <<<"$report"
check "fixture: unparseable command skipped" \
    grep -q 'reason=unparseable command: python3' <<<"$report"
check "fixture: missing script skipped at generation time" \
    grep -q 'script=missing.sh reason=referenced script missing: hooks/missing.sh' <<<"$report"

# (a) every referenced script resolves; the cross-plugin lib the probe sources is copied.
while read -r ref; do
    check "fixture: referenced script resolves: $ref" test -f "$ext/hook-scripts/$ref"
done < <(grep -vE '^\s*//' "$ext/index.ts" \
    | tr -d '\n ' | grep -oE '"plugin":"[^"]+","script":"[^"]+"' \
    | sed -E 's/"plugin":"([^"]+)","script":"([^"]+)"/\1\/hooks\/\2/' | sort -u)
check "fixture: cross-plugin hooks/lib copied" \
    test -f "$ext/hook-scripts/hooks-plugin/hooks/lib/drift-protocol.sh"
check "fixture: path-glob matcher compiled" \
    grep -q '"pathRe": "\^docs/adrs/\.\*\$"' "$ext/index.ts"
check "fixture: ms-intended timeout normalized to seconds" \
    grep -qE '"timeout": 3,?$' "$ext/index.ts"

# (c) no placeholder in executable code.
check_not "fixture: no literal CLAUDE_PLUGIN_ROOT placeholder in code" \
    bash -c "grep -vE '^\s*//' '$ext/index.ts' | grep -qF '\${CLAUDE_PLUGIN_ROOT}'"

write_driver "$ext"
export DRIFT_TEST_SIGNALS="$signals"

r="$(drive "$ext" handlers '{}')"
jq_is "fixture: registers tool_call, tool_result, session_start" "$r" \
    '. == ["session_start","tool_call","tool_result"]'

# (b) exit 2 -> { block: true, reason: <stderr> }.
r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"bash\",\"input\":{\"command\":\"echo DANGER\"}}")"
jq_is "fixture: PreToolUse exit 2 blocks" "$r" '.result.block == true'
jq_is "fixture: block reason is the hook's stderr" "$r" \
    '.result.reason == "BLOCKED-BY-FIXTURE: echo DANGER"'

r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"bash\",\"input\":{\"command\":\"echo fine\"}}")"
jq_is "fixture: benign bash call is allowed" "$r" '.result == null'

# (b) JSON deny -> block; pi `path` becomes an absolute Claude `file_path`.
r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"read\",\"input\":{\"path\":\"conf/.env\"}}")"
jq_is "fixture: JSON permissionDecision deny blocks" "$r" '.result.block == true'
jq_is "fixture: read maps to Read with an absolute file_path" "$r" \
    ".result.reason == \"DENY-Read:$work/conf/.env\""
r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"read\",\"input\":{\"path\":\"README.md\"}}")"
jq_is "fixture: non-secret read is allowed" "$r" '.result == null'

# pi edits[] reach content-scanning hooks as Claude's new_string.
r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"edit\",\"input\":{\"path\":\"a.txt\",\"edits\":[{\"oldText\":\"x\",\"newText\":\"y\"},{\"oldText\":\"p\",\"newText\":\"SECRET-TOKEN\"}]}}")"
jq_is "fixture: second of several pi edits is scanned" "$r" \
    '.result.block == true and .result.reason == "edit carries a secret"'

# JSON ask: blocked without a UI, confirm() decides with one.
ask="\"cwd\":\"$work\",\"toolName\":\"bash\",\"input\":{\"command\":\"git push origin feat\"}"
r="$(drive "$ext" tool_call "{$ask}")"
jq_is "fixture: ask without a UI blocks and says why" "$r" \
    '.result.block == true and (.result.reason | test("ASK-branch-behind")) and (.result.reason | test("no interactive UI"))'
r="$(drive "$ext" tool_call "{$ask,\"hasUI\":true,\"confirm\":true}")"
jq_is "fixture: ask confirmed in the UI is allowed" "$r" '.result == null'
r="$(drive "$ext" tool_call "{$ask,\"hasUI\":true,\"confirm\":false}")"
jq_is "fixture: ask declined in the UI blocks" "$r" \
    '.result.block == true and (.result.reason | startswith("Declined:"))'

# updatedInput rewrites the bash command pi is about to run.
r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"bash\",\"input\":{\"command\":\"kubectl apply -f x.yaml\"}}")"
jq_is "fixture: updatedInput.command applied to the bash call" "$r" \
    '.result == null and .input.command == "kubectl apply -f x.yaml --dry-run=client"'

# PostToolUse -> tool_result: the note is appended, the original content kept.
r="$(drive "$ext" tool_result "{\"cwd\":\"$work\",\"toolName\":\"bash\",\"input\":{\"command\":\"ls\"},\"content\":[{\"type\":\"text\",\"text\":\"orig\"}]}")"
jq_is "fixture: PostToolUse note appended to the tool result" "$r" \
    '.result.content[0].text == "orig" and (.result.content[1].text | test("NOTE-FROM-POST-HOOK"))'
r="$(drive "$ext" tool_result "{\"cwd\":\"$work\",\"toolName\":\"read\",\"input\":{\"path\":\"x\"},\"content\":[{\"type\":\"text\",\"text\":\"orig\"}]}")"
jq_is "fixture: tool_result leaves a non-matching tool untouched" "$r" '.result == null'

# SessionStart -> session_start: the aggregator runs after the probe it reads,
# the probe reached its cross-plugin lib, and the context is queued, not sent now.
r="$(drive "$ext" session_start "{\"cwd\":\"$work\",\"sid\":\"sid-1\"}")"
jq_is "fixture: SessionStart context delivered via sendMessage" "$r" '(.sent | length) == 1'
jq_is "fixture: drift-aggregator ran after the probe it consumes" "$r" \
    '.sent[0].m.content | test("^AGG:probe-ran:")'
jq_is "fixture: probe saw CLAUDE_PLUGIN_ROOT at its copied plugin dir" "$r" \
    '.sent[0].m.content | test("hook-scripts/git-plugin$")'
jq_is "fixture: context queued for the next turn" "$r" '.sent[0].o.deliverAs == "nextTurn"'

# A script missing at RUN time fails open.
rm -f "$ext/hook-scripts/hooks-plugin/hooks/repo-deletion-safety.sh"
r="$(drive "$ext" tool_call "{\"cwd\":\"$work\",\"toolName\":\"bash\",\"input\":{\"command\":\"echo FAILOPEN\"}}")"
jq_is "fixture: missing script at run time fails open" "$r" '.result == null'

# --- CLI contract ------------------------------------------------------------
python3 "$test_generator" "$fx" "$test_tmp/x" --bogus >/dev/null 2>&1
check "cli: unknown argument exits 2" test "$?" -eq 2
mkdir -p "$test_tmp/foreign/extensions/plugin-hooks"
echo "// someone else's extension" > "$test_tmp/foreign/extensions/plugin-hooks/index.ts"
foreign="$(python3 "$test_generator" "$fx" "$test_tmp/foreign")"
check "cli: refuses to overwrite a non-generated extension dir" \
    grep -q 'TYPE=foreign_output_dir' <<<"$foreign"
check "cli: foreign dir left intact" \
    grep -q "someone else's extension" "$test_tmp/foreign/extensions/plugin-hooks/index.ts"
mkdir -p "$test_tmp/bare/lonely-plugin"
bare="$(python3 "$test_generator" "$test_tmp/bare" "$test_tmp/bare-out")"
check "cli: plugin dirs with no manifest is nothing_scanned" \
    grep -q 'TYPE=nothing_scanned' <<<"$bare"

# --- Real-repo suite -----------------------------------------------------------
repo_out="$test_tmp/repo-out"
repo_report="$(python3 "$test_generator" "$test_repo_root" "$repo_out")" || {
    echo "FAIL: generator exited non-zero on repo"
    echo "$repo_report" | tail -20
    exit 1
}
rext="$repo_out/extensions/plugin-hooks"
check "repo: STATUS=OK" grep -qx 'STATUS=OK' <<<"$repo_report"
check "repo: hooks-plugin projected from inline plugin.json" \
    grep -qE '^PLUGIN=hooks-plugin SOURCES=plugin.json EXPORTED=[1-9]' <<<"$repo_report"
check "repo: kubernetes-plugin projected from inline plugin.json" \
    grep -qE '^PLUGIN=kubernetes-plugin SOURCES=plugin.json EXPORTED=[1-9]' <<<"$repo_report"
for key in hooks-plugin/branch-protection.sh hooks-plugin/secret-protection.sh \
    hooks-plugin/repo-deletion-safety.sh hooks-plugin/external-pr-merge-guard.sh \
    git-plugin/check-branch-sync-on-push.sh git-plugin/git-drift-probe.sh \
    git-plugin/validate-pr-issue-links.sh; do
    check "repo: safety hook exported: $key" \
        test -f "$rext/hook-scripts/${key%%/*}/hooks/${key#*/}"
done
for nudge in bash-antipatterns-teach.sh prose-house-style-nudge.sh \
    code-quality-preflight-cue.sh blueprint-structural-cue.sh session-spinup-nudge.sh; do
    check "repo: nudge skipped by name: $nudge" \
        grep -q "script=$nudge reason=not in the pi safety allowlist" <<<"$repo_report"
    check_not "repo: nudge absent from code: $nudge" \
        bash -c "grep -vE '^\s*//' '$rext/index.ts' | grep -qF '$nudge'"
done
while read -r ref; do
    check "repo: referenced script resolves: $ref" test -f "$rext/hook-scripts/$ref"
done < <(grep -vE '^\s*//' "$rext/index.ts" \
    | tr -d '\n ' | grep -oE '"plugin":"[^"]+","script":"[^"]+"' \
    | sed -E 's/"plugin":"([^"]+)","script":"([^"]+)"/\1\/hooks\/\2/' | sort -u)
check_not "repo: no literal CLAUDE_PLUGIN_ROOT placeholder in code" \
    bash -c "grep -vE '^\s*//' '$rext/index.ts' | grep -qF '\${CLAUDE_PLUGIN_ROOT}'"

cp "$rext/index.ts" "$test_tmp/syntax-check.mjs"
check "repo: extension parses as ESM" node --check "$test_tmp/syntax-check.mjs"

write_driver "$rext"
r="$(drive "$rext" handlers '{}')"
jq_is "repo: registers tool_call and session_start" "$r" \
    'index("tool_call") != null and index("session_start") != null'

# End to end through the REAL secret-protection.sh: pi's read of a .env is
# blocked, and a plain file read is not (the control that keeps this honest).
repo_work="$test_tmp/repo-work"
mkdir -p "$repo_work"
r="$(drive "$rext" tool_call "{\"cwd\":\"$repo_work\",\"toolName\":\"read\",\"input\":{\"path\":\".env\"}}")"
jq_is "repo: real secret-protection blocks pi's read of .env" "$r" \
    '.result.block == true and (.result.reason | test("BLOCKED: Access to .env"))'
r="$(drive "$rext" tool_call "{\"cwd\":\"$repo_work\",\"toolName\":\"read\",\"input\":{\"path\":\"notes.md\"}}")"
jq_is "repo: real hooks allow a plain read" "$r" '.result == null'

echo ""
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: pi hook-extension export regression tests passed"
