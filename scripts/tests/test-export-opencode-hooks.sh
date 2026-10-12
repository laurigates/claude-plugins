#!/usr/bin/env bash
# SC2015: the mktemp guard's `A && B || C` is deliberate (C is the failure path).
# SC2016: fixture patterns match a literal ${CLAUDE_PLUGIN_ROOT}, unexpanded.
# shellcheck disable=SC2015,SC2016
# test-export-opencode-hooks.sh — regression tests for
# scripts/generate-opencode-hook-plugins.py (issue #1605).
#
# Guards the OpenCode hooks-export acceptance criteria:
#   (a) every generated plugins/<plugin>-hooks.js resolves its referenced
#       scripts (they are copied under hook-scripts/<plugin>/hooks/),
#   (b) blocking semantics are preserved (exit 2 / JSON deny -> throw),
#   (c) no literal ${CLAUDE_PLUGIN_ROOT} survives into generated JS
#       (the rulesync failure mode this generator replaces),
#   (d) prompt/agent hooks and unsupported events are skipped, not broken.
set -uo pipefail

test_script_dir="$(cd "$(dirname "$0")" && pwd)"
test_repo_root="$(cd "$test_script_dir/../.." && pwd)"
test_generator="$test_repo_root/scripts/generate-opencode-hook-plugins.py"

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

test_tmp="$(mktemp -d)"
[ -n "$test_tmp" ] && [ -d "$test_tmp" ] || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$test_tmp"' EXIT

# --- Fixture suite: synthetic plugin covering every skip class ------------
fixture_root="$test_tmp/fixture-root"
mkdir -p "$fixture_root/synthetic-plugin/hooks"
cat > "$fixture_root/synthetic-plugin/hooks/guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fixture_root/synthetic-plugin/hooks/cue.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
# Commands use the quoted `bash "${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"` form that
# `claude plugin validate` requires (2.1.281+); the Write(docs/adrs/**) entry
# deliberately keeps the legacy unquoted form to prove back-compat, and one
# unbalanced-quote command must be skipped as unparseable.
cat > "$fixture_root/synthetic-plugin/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh\"", "timeout": 10},
          {"type": "prompt", "prompt": "evaluate something", "timeout": 15},
          {"type": "command", "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/oddball.py"},
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh"}
        ]
      },
      {
        "matcher": "Write(docs/adrs/**)",
        "hooks": [
          {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh", "timeout": 3000}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/missing.sh\""}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/cue.sh\"", "timeout": 5}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/cue.sh\""}
        ]
      }
    ]
  }
}
JSON

# Issue #2724: hooks declared INLINE in .claude-plugin/plugin.json (an object
# under "hooks", events directly beneath it) with no hooks.json at all. The old
# `*-plugin/hooks.json` glob never saw these plugins, so they were absent from
# HOOK_PLUGINS_SCANNED rather than reported.
mkdir -p "$fixture_root/inline-plugin/.claude-plugin" "$fixture_root/inline-plugin/hooks"
cat > "$fixture_root/inline-plugin/hooks/inline-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fixture_root/inline-plugin/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "inline-plugin",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/inline-guard.sh\"", "timeout": 5}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/inline-guard.sh\""}
        ]
      }
    ]
  }
}
JSON
# A "./hooks.json" pointer must be read exactly once (not once as the bare
# hooks.json and again through the pointer).
mkdir -p "$fixture_root/pointer-plugin/.claude-plugin" "$fixture_root/pointer-plugin/hooks"
cat > "$fixture_root/pointer-plugin/hooks/pointed.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$fixture_root/pointer-plugin/.claude-plugin/plugin.json" <<'JSON'
{"name": "pointer-plugin", "hooks": "./hooks.json"}
JSON
cat > "$fixture_root/pointer-plugin/hooks.json" <<'JSON'
{"hooks": {"PostToolUse": [{"matcher": "Write", "hooks": [
  {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/pointed.sh\""}
]}]}}
JSON
# A plugin.json with no hooks key is not a hook plugin and is not scanned.
mkdir -p "$fixture_root/nohooks-plugin/.claude-plugin"
echo '{"name": "nohooks-plugin"}' > "$fixture_root/nohooks-plugin/.claude-plugin/plugin.json"

# PR #3046 review: a hook script's transitive dependencies — a `lib/` it
# sources and a sibling helper it runs from its own hooks dir — must ship with
# it, or the hook silently no-ops under OpenCode (both fail open).
mkdir -p "$fixture_root/libuser-plugin/hooks/lib"
cat > "$fixture_root/libuser-plugin/hooks/uses-lib.sh" <<'SH'
#!/usr/bin/env bash
. "$(dirname "$0")/lib/x.sh" 2>/dev/null || exit 0
python3 "$(dirname "$0")/helper.py"
SH
echo 'x_fn() { :; }' > "$fixture_root/libuser-plugin/hooks/lib/x.sh"
echo 'print("ok")' > "$fixture_root/libuser-plugin/hooks/helper.py"
echo 'unreferenced' > "$fixture_root/libuser-plugin/hooks/unrelated.py"
cat > "$fixture_root/libuser-plugin/hooks.json" <<'JSON'
{"hooks": {"PreToolUse": [{"matcher": "Bash|SlashCommand", "hooks": [
  {"type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/uses-lib.sh\""}
]}]}}
JSON
# A malformed plugin.json must be reported, not abort the whole export.
mkdir -p "$fixture_root/broken-plugin/.claude-plugin"
echo '{"name": "broken-plugin", "hooks": ' > "$fixture_root/broken-plugin/.claude-plugin/plugin.json"
# A hooks pointer escaping the plugin dir is skipped with a reason; a pointer
# to a missing file is reported rather than dropped silently.
mkdir -p "$fixture_root/escape-plugin/.claude-plugin"
cat > "$fixture_root/escape-plugin/.claude-plugin/plugin.json" <<'JSON'
{"name": "escape-plugin", "hooks": ["../synthetic-plugin/hooks.json", "./gone.json"]}
JSON

fixture_out="$test_tmp/fixture-out"
fixture_report="$(python3 "$test_generator" "$fixture_root" "$fixture_out")" || {
    echo "FAIL: generator exited non-zero on fixture"
    echo "$fixture_report"
    exit 1
}

fixture_js="$fixture_out/plugins/synthetic-plugin-hooks.js"
check "fixture: JS emitted" test -f "$fixture_js"
check "fixture: exported command hooks counted" \
    grep -q "PLUGIN=synthetic-plugin JS=plugins/synthetic-plugin-hooks.js EXPORTED=3 SKIPPED=5" <<<"$fixture_report"
check "fixture: prompt hook skipped with reason" \
    grep -q "type=prompt reason=OpenCode has no model-evaluation hook" <<<"$fixture_report"
check "fixture: unparseable command skipped" \
    grep -q "reason=unparseable command: python3" <<<"$fixture_report"
check "fixture: unbalanced-quote command skipped" \
    grep -q 'reason=unparseable command: bash "${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh$' <<<"$fixture_report"
check "fixture: missing script skipped" \
    grep -q "reason=referenced script missing: hooks/missing.sh" <<<"$fixture_report"
check "fixture: SessionStart skipped" \
    grep -q "SKIP event=SessionStart" <<<"$fixture_report"
check "fixture: referenced scripts copied" \
    test -f "$fixture_out/hook-scripts/synthetic-plugin/hooks/guard.sh"
check "fixture: unreferenced missing script not copied" \
    bash -c "! test -e '$fixture_out/hook-scripts/synthetic-plugin/hooks/missing.sh'"
check "fixture: path-glob matcher compiled" \
    grep -q '"pathRe": "\^docs/adrs/\.\*\$"' "$fixture_js"
check "fixture: ms-intended timeout normalized to seconds" \
    grep -q '"timeout": 3' "$fixture_js"
# The skip-report header comment may cite skipped commands verbatim; the
# invariant is that no placeholder reaches executable (non-comment) code.
check_not "fixture: no literal CLAUDE_PLUGIN_ROOT placeholder in JS code" \
    bash -c "grep -vE '^\s*//' '$fixture_js' | grep -qF '\${CLAUDE_PLUGIN_ROOT}'"
check "fixture: blocking preserved (throw on exit 2 / deny)" \
    grep -q "throw new Error" "$fixture_js"
check "fixture: fail-open marker present" \
    grep -q "Fail open" "$fixture_js"

# Issue #2724: inline plugin.json hooks are discovered and exported.
inline_js="$fixture_out/plugins/inline-plugin-hooks.js"
check "inline: JS emitted for plugin.json-inline hooks" test -f "$inline_js"
check "inline: tool hook exported, SessionStart skipped" \
    grep -q "PLUGIN=inline-plugin JS=plugins/inline-plugin-hooks.js EXPORTED=1 SKIPPED=1" <<<"$fixture_report"
check "inline: source reported as plugin.json" \
    grep -q "PLUGIN=inline-plugin .* SOURCE=plugin.json" <<<"$fixture_report"
check "inline: referenced script copied" \
    test -f "$fixture_out/hook-scripts/inline-plugin/hooks/inline-guard.sh"
check "inline: JS header cites plugin.json as source" \
    grep -q "Source: inline-plugin/.claude-plugin/plugin.json" "$inline_js"
check "pointer: ./hooks.json pointer read exactly once" \
    grep -q "PLUGIN=pointer-plugin JS=plugins/pointer-plugin-hooks.js EXPORTED=1 SKIPPED=0 SOURCE=hooks.json$" <<<"$fixture_report"
check_not "nohooks: plugin.json without hooks is not scanned" \
    grep -q "PLUGIN=nohooks-plugin" <<<"$fixture_report"
check "fixture: scanned count includes inline + pointer + lib plugins" \
    grep -qx "HOOK_PLUGINS_SCANNED=4" <<<"$fixture_report"
check "fixture: generated count includes inline + pointer + lib plugins" \
    grep -qx "HOOK_PLUGINS_GENERATED=4" <<<"$fixture_report"

# PR #3046 review: transitive dependencies are copied, unreferenced files are not.
check "lib: sourced lib/x.sh copied" \
    test -f "$fixture_out/hook-scripts/libuser-plugin/hooks/lib/x.sh"
check "lib: sibling helper.py copied" \
    test -f "$fixture_out/hook-scripts/libuser-plugin/hooks/helper.py"
check_not "lib: unreferenced sibling not copied" \
    test -e "$fixture_out/hook-scripts/libuser-plugin/hooks/unrelated.py"
check "lib: copied lib and helper reported" \
    grep -q "PLUGIN=libuser-plugin .*LIBS=libuser-plugin HELPERS=helper.py" <<<"$fixture_report"
# Malformed plugin.json: reported loudly, export continues (STATUS still printed).
check "parse-error: malformed plugin.json reported" \
    grep -q "^PLUGIN=broken-plugin PARSE-ERROR=.claude-plugin/plugin.json: " <<<"$fixture_report"
check "parse-error: export continues to the summary (STATUS=WARN)" \
    grep -qx "STATUS=WARN" <<<"$fixture_report"
check "parse-error: counted in summary" \
    grep -qx "PARSE_ERRORS=1" <<<"$fixture_report"
check "pointer: escaping pointer skipped with reason" \
    grep -q "^PLUGIN=escape-plugin POINTER-SKIP=../synthetic-plugin/hooks.json reason=escapes plugin dir" <<<"$fixture_report"
check "pointer: missing pointer target reported" \
    grep -q "^PLUGIN=escape-plugin POINTER-SKIP=./gone.json reason=file not found" <<<"$fixture_report"
# Unmapped bare tool names (no OpenCode equivalent) still pass through, but the
# dead entry is reported as a NOTE (stdout and JS header) instead of silently.
check "unmapped: SlashCommand alternative noted on stdout" \
    grep -qF "NOTE event=PreToolUse matcher=Bash|SlashCommand reason=no OpenCode tool named SlashCommand (entry kept, never matches)" <<<"$fixture_report"
check "unmapped: SlashCommand note in JS header" \
    grep -qF "// Notes:" "$fixture_out/plugins/libuser-plugin-hooks.js"
check_not "unmapped: mapped-only matcher produces no NOTE" \
    grep -q "NOTE event=PreToolUse matcher=Bash reason" <<<"$fixture_report"

# --- Real-repo suite -------------------------------------------------------
repo_out="$test_tmp/repo-out"
repo_report="$(python3 "$test_generator" "$test_repo_root" "$repo_out")" || {
    echo "FAIL: generator exited non-zero on repo"
    echo "$repo_report"
    exit 1
}

# hooks-plugin, feedback-plugin and kubernetes-plugin declare their tool hooks
# inline in .claude-plugin/plugin.json (issue #2724).
for plugin in git-plugin terraform-plugin blueprint-plugin code-quality-plugin \
    hooks-plugin feedback-plugin kubernetes-plugin; do
    check "repo: $plugin hooks JS generated" test -f "$repo_out/plugins/$plugin-hooks.js"
done
# PreCompact-only / SessionStart-only plugins must not emit an empty JS plugin.
check_not "repo: agent-patterns-plugin (PreCompact-only) emits no JS" \
    test -e "$repo_out/plugins/agent-patterns-plugin-hooks.js"
check_not "repo: codebase-attributes-plugin (SessionStart-only) emits no JS" \
    test -e "$repo_out/plugins/codebase-attributes-plugin-hooks.js"
# Inline SessionStart/Stop-only plugins are scanned (reported) but emit no JS.
check "repo: inline SessionStart-only session-plugin is scanned" \
    grep -q "^PLUGIN=session-plugin JS=- EXPORTED=0" <<<"$repo_report"
check_not "repo: session-plugin (SessionStart/Stop-only) emits no JS" \
    test -e "$repo_out/plugins/session-plugin-hooks.js"

# Acceptance criterion (a): every script a generated JS references resolves.
while IFS=: read -r js script; do
    plugin_name="$(basename "$js" | sed 's/-hooks\.js$//')"
    check "repo: $plugin_name references resolvable script $script" \
        test -f "$repo_out/hook-scripts/$plugin_name/hooks/$script"
done < <(grep -o '"script": "[^"]*"' "$repo_out"/plugins/*.js \
    | sed 's/"script": "//; s/"$//')

# PR #3046 review: hooks-plugin's transitive dependencies ship with it —
# bash-antipatterns-teach.sh sources lib/command-views.sh, and
# workflow-scale-guard.sh runs workflow-scale-estimate.py (which itself loads
# lib/workflow-scale-parse.cjs and the vendored parser).
hp_out="$repo_out/hook-scripts/hooks-plugin/hooks"
check "repo: hooks-plugin lib/command-views.sh copied" test -f "$hp_out/lib/command-views.sh"
check "repo: hooks-plugin workflow-scale-estimate.py copied" test -f "$hp_out/workflow-scale-estimate.py"
check "repo: hooks-plugin lib/workflow-scale-parse.cjs copied" test -f "$hp_out/lib/workflow-scale-parse.cjs"
check "repo: no parse errors on the real repo" grep -qx "PARSE_ERRORS=0" <<<"$repo_report"

# The prompt-type PR-issue-link hook must not leak into the git plugin's
# executable code (the skip-report comment legitimately cites its matcher).
check_not "repo: prompt hook (create_pull_request) not exported" \
    bash -c "grep -vE '^\s*//' '$repo_out/plugins/git-plugin-hooks.js' | grep -q 'create_pull_request'"
check "repo: git-plugin prompt hook reported as skipped" \
    grep -q "matcher=mcp__github__create_pull_request type=prompt" <<<"$repo_report"

for js in "$repo_out"/plugins/*.js; do
    check_not "repo: $(basename "$js") has no literal CLAUDE_PLUGIN_ROOT placeholder in code" \
        bash -c "grep -vE '^\s*//' '$js' | grep -qF '\${CLAUDE_PLUGIN_ROOT}'"
done

# Acceptance criterion (b): generated JS is valid ESM (node treats .mjs as ESM).
if command -v node >/dev/null 2>&1; then
    for js in "$fixture_js" "$repo_out"/plugins/*.js; do
        cp "$js" "$test_tmp/syntax-check.mjs"
        check "syntax: $(basename "$js") parses as ESM" \
            node --check "$test_tmp/syntax-check.mjs"
    done
fi

echo ""
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] || exit 1
echo "OK: OpenCode hooks export regression tests passed"
