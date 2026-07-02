#!/usr/bin/env bash
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
cat > "$fixture_root/synthetic-plugin/hooks.json" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh", "timeout": 10},
          {"type": "prompt", "prompt": "evaluate something", "timeout": 15},
          {"type": "command", "command": "python3 ${CLAUDE_PLUGIN_ROOT}/hooks/oddball.py"}
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
          {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/missing.sh"}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/cue.sh", "timeout": 5}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/cue.sh"}
        ]
      }
    ]
  }
}
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
    grep -q "PLUGIN=synthetic-plugin JS=plugins/synthetic-plugin-hooks.js EXPORTED=3 SKIPPED=4" <<<"$fixture_report"
check "fixture: prompt hook skipped with reason" \
    grep -q "type=prompt reason=OpenCode has no model-evaluation hook" <<<"$fixture_report"
check "fixture: unparseable command skipped" \
    grep -q "reason=unparseable command: python3" <<<"$fixture_report"
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

# --- Real-repo suite -------------------------------------------------------
repo_out="$test_tmp/repo-out"
repo_report="$(python3 "$test_generator" "$test_repo_root" "$repo_out")" || {
    echo "FAIL: generator exited non-zero on repo"
    echo "$repo_report"
    exit 1
}

for plugin in git-plugin terraform-plugin blueprint-plugin code-quality-plugin; do
    check "repo: $plugin hooks JS generated" test -f "$repo_out/plugins/$plugin-hooks.js"
done
# PreCompact-only / SessionStart-only plugins must not emit an empty JS plugin.
check_not "repo: agent-patterns-plugin (PreCompact-only) emits no JS" \
    test -e "$repo_out/plugins/agent-patterns-plugin-hooks.js"
check_not "repo: codebase-attributes-plugin (SessionStart-only) emits no JS" \
    test -e "$repo_out/plugins/codebase-attributes-plugin-hooks.js"

# Acceptance criterion (a): every script a generated JS references resolves.
while IFS=: read -r js script; do
    plugin_name="$(basename "$js" | sed 's/-hooks\.js$//')"
    check "repo: $plugin_name references resolvable script $script" \
        test -f "$repo_out/hook-scripts/$plugin_name/hooks/$script"
done < <(grep -o '"script": "[^"]*"' "$repo_out"/plugins/*.js \
    | sed 's/"script": "//; s/"$//')

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
