#!/usr/bin/env bash
# test-evaluate-drift-probe.sh — regression tests for the evaluate-plugin
# SessionStart drift probe (issue #3073).
#
# The probe used to run an unguarded `find "$DRIFT_CWD" -maxdepth 5 …` on every
# SessionStart, in any directory, and its `-not -path '*/node_modules/*'`
# filters still descended the excluded trees. These tests pin:
#   1. non-plugin tree        → no-op (empty findings), even with a stale
#                               eval-results/ decoy the old find would report
#   2. non-plugin tree        → the search never runs (no node_modules opened)
#   3. plugin-shaped tree     → a stale eval-results/ is still reported (count 1),
#                               and a decoy under node_modules/ is not counted
#   4. plugin-shaped tree     → node_modules/ is pruned, not descended
#   5. fresh eval-results     → no finding
#   6. marker variants        → `*/skills` at depth 1, or a root `skills/`, opens
#                               the gate on their own
#   7. plugin.json timeout    → SessionStart timeout is in seconds (< 60)
#
# Assertions 2 and 4 trace the probe's directory opens with strace; they SKIP
# when strace is unavailable or ptrace is denied.

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="${SCRIPT_DIR}/evaluate-drift-probe.sh"
MANIFEST="${SCRIPT_DIR}/../.claude-plugin/plugin.json"

pass=0
fail=0
skip=0
check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
    fi
}

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not available" >&2
    exit 0
fi

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

SIGNALS="${WORK}/signals"
mkdir -p "$SIGNALS"

# strace usable? (ptrace may be denied in some sandboxes)
HAVE_STRACE=0
if command -v strace >/dev/null 2>&1 \
    && strace -f -qq -e trace=openat -o "${WORK}/strace-probe.txt" true >/dev/null 2>&1; then
    HAVE_STRACE=1
fi

# make_skill <root> <relative-skill-dir> <stale|fresh>
make_skill() {
    local dir="$1/$2"
    mkdir -p "${dir}/eval-results"
    printf -- '---\nname: s\n---\n' > "${dir}/SKILL.md"
    printf '{}\n' > "${dir}/eval-results/benchmark.json"
    if [ "$3" = "stale" ]; then
        touch -d '2020-01-01 00:00:00' "${dir}/eval-results/benchmark.json"
    else
        touch -d '2020-01-01 00:00:00' "${dir}/SKILL.md"
    fi
}

# run_probe <sid> <cwd> [trace-file] — runs the probe, prints the findings count
# from its signal file ("missing" if the probe wrote none).
run_probe() {
    local sid="$1" cwd="$2" trace="${3:-}"
    local input
    input=$(jq -n -c --arg sid "$sid" --arg cwd "$cwd" '{session_id: $sid, cwd: $cwd}')
    if [ -n "$trace" ]; then
        printf '%s' "$input" | CLAUDE_DRIFT_SIGNALS_DIR="$SIGNALS" \
            strace -f -qq -e trace=openat -o "$trace" bash "$PROBE" >/dev/null 2>&1
    else
        printf '%s' "$input" | CLAUDE_DRIFT_SIGNALS_DIR="$SIGNALS" \
            bash "$PROBE" >/dev/null 2>&1
    fi
    local f="${SIGNALS}/${sid}/evaluate-plugin.json"
    if [ -f "$f" ]; then
        jq -r '.findings | length' "$f"
    else
        echo missing
    fi
}

# --- 1/2. Non-plugin deep tree ---------------------------------------------
PLAIN="${WORK}/plain"
# A decoy 6 levels deep under node_modules, and a shallow one the old
# unguarded find would have reported as stale.
make_skill "$PLAIN" "node_modules/a/b/c/d/e/pkg" stale
make_skill "$PLAIN" "docs/notes" stale
check "non-plugin tree: no-op with empty findings" "0" "$(run_probe plain "$PLAIN")"

if [ "$HAVE_STRACE" -eq 1 ]; then
    run_probe plain-trace "$PLAIN" "${WORK}/trace-plain.txt" >/dev/null
    check "non-plugin tree: node_modules never opened" "0" \
        "$(grep -c 'node_modules' "${WORK}/trace-plain.txt")"
else
    skip=$((skip + 1))
fi

# --- 3/4. Plugin-shaped tree -------------------------------------------------
PLUG="${WORK}/plug"
mkdir -p "${PLUG}/.claude-plugin"
make_skill "$PLUG" "demo-plugin/skills/demo" stale
make_skill "$PLUG" "node_modules/pkg/skills/decoy" stale
check "plugin tree: stale eval-results reported once" "1" "$(run_probe plug "$PLUG")"
check "plugin tree: finding kind" "eval_results_stale" \
    "$(jq -r '.findings[0].kind' "${SIGNALS}/plug/evaluate-plugin.json")"

if [ "$HAVE_STRACE" -eq 1 ]; then
    run_probe plug-trace "$PLUG" "${WORK}/trace-plug.txt" >/dev/null
    check "plugin tree: node_modules pruned, not descended" "0" \
        "$(grep -c 'node_modules/' "${WORK}/trace-plug.txt")"
else
    skip=$((skip + 1))
fi

# --- 5. Fresh results --------------------------------------------------------
FRESH="${WORK}/fresh"
mkdir -p "${FRESH}/.claude-plugin"
make_skill "$FRESH" "demo-plugin/skills/demo" fresh
check "fresh eval-results: no finding" "0" "$(run_probe fresh "$FRESH")"

# --- 6. Marker variants ------------------------------------------------------
DEPTH1="${WORK}/depth1"
make_skill "$DEPTH1" "demo-plugin/skills/demo" stale
check "depth-1 */skills opens the gate" "1" "$(run_probe depth1 "$DEPTH1")"

ROOTSKILLS="${WORK}/rootskills"
make_skill "$ROOTSKILLS" "skills/demo" stale
check "root skills/ opens the gate" "1" "$(run_probe rootskills "$ROOTSKILLS")"

# --- 7. Timeout units --------------------------------------------------------
timeout_val=$(jq -r '.hooks.SessionStart[].hooks[]
    | select(.command | contains("evaluate-drift-probe.sh")) | .timeout' "$MANIFEST")
if [ -n "$timeout_val" ] && [ "$timeout_val" -lt 60 ] 2>/dev/null; then
    check "SessionStart timeout is in seconds" "ok" "ok"
else
    check "SessionStart timeout is in seconds (< 60)" "< 60" "$timeout_val"
fi

printf 'evaluate-drift-probe: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
