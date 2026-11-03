#!/usr/bin/env bash
# test-sync-evaluate-skill-workflow.sh — regression tests for the
# evaluate-plugin SessionStart hook that keeps the registered copy of the
# evaluate-skill workflow in step with the bundled template (issue #2829).
#
# evaluate-plugin-batch resolves evaluate-skill BY NAME, which needs a copy in
# ~/.claude/workflows/. That copy used to be a manual install step and drifted
# after every edit to the bundled file. These tests pin:
#   1. target missing         → copied, byte-identical, hook silent, exit 0
#   2. target identical       → untouched (mtime unchanged)
#   3. target drifted         → overwritten with the bundled file
#   4. target unwritable      → exit 0, silent (fail-open)
#   5. bundled file missing   → exit 0, nothing created
#   6. CLAUDE_PLUGIN_ROOT unset → falls back to the hook's own plugin dir
#   7. naming                 → bundled meta.name equals the installed basename
#   8. manifest               → hook registered on SessionStart, timeout < 60 s
#
# Every case runs with HOME pointed at a temp directory, so the real
# ~/.claude/workflows is never read or written.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/sync-evaluate-skill-workflow.sh"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MANIFEST="${PLUGIN_DIR}/.claude-plugin/plugin.json"
BUNDLED="${PLUGIN_DIR}/skills/evaluate-skill/workflows/evaluate-skill.workflow.js"
REL="skills/evaluate-skill/workflows/evaluate-skill.workflow.js"

pass=0
fail=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

WORK="$(mktemp -d)"
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "mktemp failed" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

mtime_of() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo ""
}

# make_plugin <dir> <content> — a fake plugin root holding a bundled template.
make_plugin() {
    mkdir -p "$1/$(dirname "$REL")"
    printf '%s\n' "$2" > "$1/$REL"
}

# run_hook <home> <plugin-root|-> — runs the hook; sets RC, OUT (stdout+stderr).
# A plugin root of "-" runs with CLAUDE_PLUGIN_ROOT unset.
run_hook() {
    local home="$1" root="$2"
    if [ "$root" = "-" ]; then
        OUT=$(printf '{}' | env -u CLAUDE_PLUGIN_ROOT HOME="$home" bash "$HOOK" 2>&1)
    else
        OUT=$(printf '{}' | HOME="$home" CLAUDE_PLUGIN_ROOT="$root" bash "$HOOK" 2>&1)
    fi
    RC=$?
}

PLUGIN="${WORK}/plugin"
make_plugin "$PLUGIN" "export const meta = { name: 'evaluate-skill' } // v2"

# 1. target missing → copied
H1="${WORK}/home1"
mkdir -p "$H1"
run_hook "$H1" "$PLUGIN"
check "1 missing: exit 0" "0" "$RC"
check "1 missing: silent" "" "$OUT"
if cmp -s "$PLUGIN/$REL" "$H1/.claude/workflows/evaluate-skill.workflow.js"; then
    check "1 missing: copied byte-identical" "ok" "ok"
else
    check "1 missing: copied byte-identical" "ok" "differs-or-absent"
fi

# 2. target identical → untouched
touch -d '2020-01-01 00:00:00' "$H1/.claude/workflows/evaluate-skill.workflow.js"
before=$(mtime_of "$H1/.claude/workflows/evaluate-skill.workflow.js")
run_hook "$H1" "$PLUGIN"
after=$(mtime_of "$H1/.claude/workflows/evaluate-skill.workflow.js")
check "2 identical: exit 0" "0" "$RC"
check "2 identical: silent" "" "$OUT"
check "2 identical: mtime unchanged" "$before" "$after"

# 3. target drifted → overwritten
H3="${WORK}/home3"
mkdir -p "$H3/.claude/workflows"
printf 'stale copy\n' > "$H3/.claude/workflows/evaluate-skill.workflow.js"
run_hook "$H3" "$PLUGIN"
check "3 drifted: exit 0" "0" "$RC"
check "3 drifted: silent" "" "$OUT"
if cmp -s "$PLUGIN/$REL" "$H3/.claude/workflows/evaluate-skill.workflow.js"; then
    check "3 drifted: overwritten" "ok" "ok"
else
    check "3 drifted: overwritten" "ok" "still-stale"
fi
leftovers=$(find "$H3/.claude/workflows" -mindepth 1 -not -name 'evaluate-skill.workflow.js' | wc -l | tr -d ' ')
check "3 drifted: no temp file left behind" "0" "$leftovers"

# 4. target unwritable → fail-open. A regular file where the workflows
# directory should be defeats mkdir even as root (chmod would not).
H4="${WORK}/home4"
mkdir -p "$H4/.claude"
printf 'not a dir\n' > "$H4/.claude/workflows"
run_hook "$H4" "$PLUGIN"
check "4 unwritable: exit 0" "0" "$RC"
check "4 unwritable: silent" "" "$OUT"

# 5. bundled file missing → no-op
H5="${WORK}/home5"
mkdir -p "$H5" "${WORK}/empty-plugin"
run_hook "$H5" "${WORK}/empty-plugin"
check "5 no source: exit 0" "0" "$RC"
check "5 no source: silent" "" "$OUT"
check "5 no source: nothing created" "absent" "$([ -e "$H5/.claude" ] && echo present || echo absent)"

# 6. CLAUDE_PLUGIN_ROOT unset → the hook's own plugin dir (the real template)
H6="${WORK}/home6"
mkdir -p "$H6"
run_hook "$H6" "-"
check "6 default root: exit 0" "0" "$RC"
if cmp -s "$BUNDLED" "$H6/.claude/workflows/evaluate-skill.workflow.js"; then
    check "6 default root: real template copied" "ok" "ok"
else
    check "6 default root: real template copied" "ok" "differs-or-absent"
fi

# 7. the bundled template's meta.name matches the installed basename, which is
# what workflow('evaluate-skill', …) in evaluate-plugin-batch resolves.
meta_name=$(sed -n "s/^[[:space:]]*name:[[:space:]]*'\([^']*\)',\{0,1\}[[:space:]]*$/\1/p" "$BUNDLED" | head -n 1)
check "7 meta.name equals installed basename" "evaluate-skill" "$meta_name"
check "7 hook installs that basename" "1" \
    "$(grep -c '^DEST=.*/evaluate-skill\.workflow\.js"$' "$HOOK" 2>/dev/null || echo 0)"

# 8. manifest registration
if command -v jq >/dev/null 2>&1; then
    timeout_val=$(jq -r '.hooks.SessionStart[].hooks[]
        | select(.command | contains("sync-evaluate-skill-workflow.sh")) | .timeout' "$MANIFEST")
    check "8 registered on SessionStart" "1" "$(printf '%s\n' "$timeout_val" | grep -c .)"
    if [ -n "$timeout_val" ] && [ "$timeout_val" -lt 60 ] 2>/dev/null; then
        check "8 timeout is in seconds (< 60)" "ok" "ok"
    else
        check "8 timeout is in seconds (< 60)" "< 60" "$timeout_val"
    fi
else
    echo "SKIP: jq not available (manifest assertions)" >&2
fi

printf 'PASS=%s FAIL=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
