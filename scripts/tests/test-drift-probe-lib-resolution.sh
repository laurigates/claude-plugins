#!/usr/bin/env bash
# Regression test: every SessionStart drift probe finds hooks-plugin's
# drift-protocol.sh in the layout Claude Code actually installs plugins in.
#
# The bug: probes looked only for ${SCRIPT_DIR}/../../hooks-plugin/hooks/lib,
# which exists in a claude-plugins checkout. Installed plugins live at
# ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/, so that path
# resolved inside <plugin>/, both fallbacks were absent too, and every probe
# exited 0 before running a single check. Nothing failed; drift was simply
# never reported.
#
# SEMANTIC, not syntactic: each probe is copied into a fake cache tree and
# executed. The planted drift-protocol.sh is a sentinel that records which copy
# was sourced, so the assertion is "the probe sourced the library from the
# highest cached hooks-plugin version", not "the file mentions cache/".
# Controls: the same tree without hooks-plugin must produce no sentinel, and
# the real library must still drive one probe end to end.
#
# Run: bash scripts/tests/test-drift-probe-lib-resolution.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REAL_LIB="$REPO_ROOT/hooks-plugin/hooks/lib/drift-protocol.sh"
MIN_PROBES=8

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
EMPTY_HOME="$TMP_ROOT/home"
mkdir -p "$EMPTY_HOME"

# Every hook that calls drift_init sources the library, so every one of them
# must carry the resolver. Discovered, not listed, so a new probe is covered.
PROBES=()
while IFS= read -r f; do
    PROBES+=("$f")
done < <(cd "$REPO_ROOT" && grep -l '^drift_init ' -- *-plugin/hooks/*.sh 2>/dev/null | sort)

echo "--- denominator ---"
if [ "${#PROBES[@]}" -ge "$MIN_PROBES" ]; then
    pass "found ${#PROBES[@]} drift probes (>= $MIN_PROBES)"
else
    fail "found ${#PROBES[@]} drift probes, expected >= $MIN_PROBES: ${PROBES[*]:-none}"
fi

resolver_block() {
    awk '/^# >>> drift-protocol resolver >>>$/ {on=1} on {print} /^# <<< drift-protocol resolver <<<$/ {on=0}' "$1"
}

echo "--- resolver block is byte-identical ---"
REF_PROBE="${PROBES[0]:-}"
REF_BLOCK="$( [ -n "$REF_PROBE" ] && resolver_block "$REPO_ROOT/$REF_PROBE")"
if [ -z "$REF_BLOCK" ]; then
    fail "$REF_PROBE has no '# >>> drift-protocol resolver >>>' block"
fi
for probe in "${PROBES[@]}"; do
    block="$(resolver_block "$REPO_ROOT/$probe")"
    if [ -z "$block" ]; then
        fail "$probe: no resolver block"
    elif [ "$block" != "$REF_BLOCK" ]; then
        fail "$probe: resolver block differs from $REF_PROBE"
    else
        pass "$probe: resolver block matches"
    fi
done

# A sentinel library: records which copy was sourced, then stops the probe so
# nothing past the lookup runs.
plant_sentinel_lib() {
    # plant_sentinel_lib <lib-dir> <label>
    mkdir -p "$1"
    cat > "$1/drift-protocol.sh" <<EOF
printf '%s\n' "$2" > "\$SENTINEL_FILE"
exit 0
EOF
}

run_probe() {
    # run_probe <probe-path> <plugin-root> <sentinel-file>
    ( cd "$TMP_ROOT" && printf '{"session_id":"t","cwd":"%s"}' "$TMP_ROOT" |
        HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$2" SENTINEL_FILE="$3" \
        CLAUDE_DRIFT_SIGNALS_DIR="$TMP_ROOT/signals" bash "$1" >/dev/null 2>&1 )
}

for probe in "${PROBES[@]}"; do
    plugin="${probe%%/*}"
    name="$(basename "$probe")"

    echo "--- $probe ---"

    # (a) marketplace cache layout, three hooks-plugin versions: sort -V must
    # pick 2.12.4; a lexical sort would pick 2.9.0.
    cache="$TMP_ROOT/cache-$plugin-$name/mkt"
    root="$cache/$plugin/9.9.9"
    mkdir -p "$root/hooks"
    cp "$REPO_ROOT/$probe" "$root/hooks/$name"
    for v in 2.9.0 2.12.4 2.10.1; do
        plant_sentinel_lib "$cache/hooks-plugin/$v/hooks/lib" "cache-$v"
    done
    sentinel="$TMP_ROOT/sentinel-cache-$plugin-$name"
    run_probe "$root/hooks/$name" "$root" "$sentinel"
    got="$(cat "$sentinel" 2>/dev/null || echo none)"
    if [ "$got" = "cache-2.12.4" ]; then
        pass "cache layout: sourced hooks-plugin 2.12.4"
    else
        fail "cache layout: expected cache-2.12.4, got $got"
    fi

    # (a') same, with CLAUDE_PLUGIN_ROOT unset — SCRIPT_DIR alone must suffice.
    rm -f "$sentinel"
    run_probe "$root/hooks/$name" "" "$sentinel"
    got="$(cat "$sentinel" 2>/dev/null || echo none)"
    if [ "$got" = "cache-2.12.4" ]; then
        pass "cache layout without CLAUDE_PLUGIN_ROOT: sourced 2.12.4"
    else
        fail "cache layout without CLAUDE_PLUGIN_ROOT: got $got"
    fi

    # (b) control — no hooks-plugin anywhere: the probe must stay a silent
    # no-op, and the sentinel must not exist (proves (a) can fail).
    rm -rf "$cache/hooks-plugin"
    rm -f "$sentinel"
    run_probe "$root/hooks/$name" "$root" "$sentinel"
    rc=$?
    if [ ! -e "$sentinel" ] && [ "$rc" -eq 0 ]; then
        pass "control: no hooks-plugin -> no library sourced, exit 0"
    else
        fail "control: expected no sentinel and rc 0, got sentinel=$([ -e "$sentinel" ] && echo yes || echo no) rc=$rc"
    fi

    # (c) flat checkout layout still wins first.
    flat="$TMP_ROOT/flat-$plugin-$name"
    mkdir -p "$flat/$plugin/hooks"
    cp "$REPO_ROOT/$probe" "$flat/$plugin/hooks/$name"
    plant_sentinel_lib "$flat/hooks-plugin/hooks/lib" "flat"
    sentinel="$TMP_ROOT/sentinel-flat-$plugin-$name"
    run_probe "$flat/$plugin/hooks/$name" "$flat/$plugin" "$sentinel"
    got="$(cat "$sentinel" 2>/dev/null || echo none)"
    if [ "$got" = "flat" ]; then
        pass "flat layout: sourced the sibling hooks-plugin"
    else
        fail "flat layout: expected flat, got $got"
    fi
done

# (d) end to end with the real library: an installed blueprint-drift-probe
# writes its signal file. Before the fix this directory stayed empty.
echo "--- end to end: real drift-protocol.sh in the cache layout ---"
e2e="$TMP_ROOT/e2e/mkt"
mkdir -p "$e2e/blueprint-plugin/9.9.9/hooks" "$e2e/hooks-plugin/2.12.4/hooks/lib" \
         "$TMP_ROOT/e2e-project/docs/blueprint"
cp "$REPO_ROOT/blueprint-plugin/hooks/blueprint-drift-probe.sh" "$e2e/blueprint-plugin/9.9.9/hooks/"
cp "$REAL_LIB" "$e2e/hooks-plugin/2.12.4/hooks/lib/drift-protocol.sh"
printf '{"format_version":"3.4.0"}\n' > "$TMP_ROOT/e2e-project/docs/blueprint/manifest.json"
signals="$TMP_ROOT/e2e-signals"
( cd "$TMP_ROOT/e2e-project" &&
  printf '{"session_id":"e2e","cwd":"%s"}' "$TMP_ROOT/e2e-project" |
  HOME="$EMPTY_HOME" CLAUDE_PLUGIN_ROOT="$e2e/blueprint-plugin/9.9.9" \
  CLAUDE_DRIFT_SIGNALS_DIR="$signals" \
  bash "$e2e/blueprint-plugin/9.9.9/hooks/blueprint-drift-probe.sh" >/dev/null 2>&1 )
signal_file="$(find "$signals" -name 'blueprint-plugin.json' 2>/dev/null | head -1)"
if [ -n "$signal_file" ] && grep -q '"plugin":"blueprint-plugin"' "$signal_file"; then
    pass "real library: signal file written ($signal_file)"
else
    fail "real library: no blueprint-plugin.json under $signals"
fi

echo
echo "=== DRIFT PROBE LIB RESOLUTION ==="
echo "PROBES=${#PROBES[@]}"
echo "PASSED=$PASS"
echo "FAILED=$FAIL"
if [ "$FAIL" -eq 0 ]; then
    echo "STATUS=OK"
    echo "=== END DRIFT PROBE LIB RESOLUTION ==="
    exit 0
fi
echo "STATUS=ERROR"
echo "=== END DRIFT PROBE LIB RESOLUTION ==="
exit 1
