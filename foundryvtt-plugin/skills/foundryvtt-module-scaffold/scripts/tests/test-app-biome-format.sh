#!/usr/bin/env bash
# test-app-biome-format.sh — the app variant's src/app.ts passes the generated
# repo's own biome gate at every module-id length (#2746).
#
# The emitted biome.json sets lineWidth 100, and biome collapses a wrapped
# signature onto one line whenever it fits. The `#onRefresh` handler used to be
# written wrapped, so a short class name (foundryvtt-ab -> AbApp) made biome
# want it on one line and `just check` failed out of the box, while a long one
# (RenderOnDemandApp) exceeded 100 columns and passed. The fix is a signature
# short enough to fit on one line for any realistic id.
#
# Two layers:
#   1. STATIC, runs everywhere: the emitted `#onRefresh` signature is a single
#      line, in both scaffold.py's output and the cargo-generate template.
#   2. BIOME, runs when the pinned biome can be fetched: `biome check
#      src/app.ts` over a short-id and a long-id app scaffold. SKIPs (exit 0,
#      a `SKIP:` line) when bunx/npx, biome, or the network is unavailable.
#
# Requires python3; SKIPs cleanly when it is unavailable.

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="${SCRIPT_DIR}/../../scaffold.py"
TEMPLATE_APP="${SCRIPT_DIR}/../../../../templates/foundryvtt-module/src/app.ts"

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

if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available" >&2
    exit 0
fi
if [ ! -f "$SCAFFOLD" ]; then
    echo "FAIL: scaffold.py not found at $SCAFFOLD" >&2
    exit 1
fi

WORK=$(mktemp -d) || { echo "FAIL: mktemp failed" >&2; exit 1; }
if [ -z "$WORK" ] || [ ! -d "$WORK" ]; then
    echo "FAIL: bad sandbox dir" >&2
    exit 1
fi
trap 'rm -rf "$WORK"' EXIT

# Short id -> 5-char class name; long id -> a class name whose old wrapped
# signature exceeded 100 columns. Between them they cover both sides of the
# line-width boundary the old form straddled.
NAMES=(foundryvtt-ab foundryvtt-render-on-demand)

# signature_shape <file> -> single-line | wrapped | missing
signature_shape() {
    local line
    line="$(grep -m1 'static async #onRefresh(' "$1" 2>/dev/null)"
    if [ -z "$line" ]; then
        echo missing
    elif [[ "$line" == *"): Promise<void> {" ]]; then
        echo single-line
    else
        echo wrapped
    fi
}

echo "=== STATIC: #onRefresh signature is one line ==="

for name in "${NAMES[@]}"; do
    mkdir -p "${WORK}/${name}"
    if ! python3 "$SCAFFOLD" --name "$name" --display "Probe" --desc "x" \
        --variant app --dir "${WORK}/${name}" >"${WORK}/${name}.log" 2>&1; then
        check "${name}: app variant scaffolds" "ok" "failed"
        tail -5 "${WORK}/${name}.log" >&2
        continue
    fi
    app="${WORK}/${name}/${name}/src/app.ts"
    check "${name}: emitted #onRefresh signature" "single-line" "$(signature_shape "$app")"
    # The handler is wired as an action; dropping it would also "fix" the format.
    check "${name}: refresh action still wired" "yes" \
        "$(grep -q 'refresh: [A-Za-z]*App\.#onRefresh,' "$app" && echo yes || echo no)"
done

if [ -f "$TEMPLATE_APP" ]; then
    check "cargo-generate template #onRefresh signature" "single-line" "$(signature_shape "$TEMPLATE_APP")"
else
    check "cargo-generate template ships src/app.ts" "present" "absent"
fi

echo "=== BIOME: pinned biome check src/app.ts ==="

BIOME_VERSION="$(sed -n 's/^BIOME_VERSION = "\([^"]*\)".*/\1/p' "$SCAFFOLD")"
check "BIOME_VERSION is readable from scaffold.py" "yes" "$([ -n "$BIOME_VERSION" ] && echo yes || echo no)"

runner=()
if command -v bunx >/dev/null 2>&1; then
    runner=(bunx --bun "@biomejs/biome@${BIOME_VERSION}")
elif command -v npx >/dev/null 2>&1; then
    runner=(npx --yes "@biomejs/biome@${BIOME_VERSION}")
fi

biome_ready=no
if [ "${#runner[@]}" -eq 0 ]; then
    echo "SKIP: biome half — neither bunx nor npx is available" >&2
elif [ -z "$BIOME_VERSION" ]; then
    echo "SKIP: biome half — BIOME_VERSION not found" >&2
elif ! (cd "$WORK" && timeout 180 "${runner[@]}" --version >"${WORK}/biome-version.log" 2>&1); then
    echo "SKIP: biome half — @biomejs/biome@${BIOME_VERSION} could not be fetched or run (offline?)" >&2
else
    biome_ready=yes
fi

if [ "$biome_ready" = yes ]; then
    for name in "${NAMES[@]}"; do
        module_dir="${WORK}/${name}/${name}"
        [ -f "${module_dir}/src/app.ts" ] || continue
        rc=0
        (cd "$module_dir" && timeout 180 "${runner[@]}" check src/app.ts) \
            >"${WORK}/${name}-biome.log" 2>&1 || rc=$?
        check "${name}: biome ${BIOME_VERSION} check src/app.ts exits 0" "0" "$rc"
        [ "$rc" -eq 0 ] || tail -20 "${WORK}/${name}-biome.log" >&2
    done
fi

echo "=== SUMMARY ==="
echo "PASS_COUNT=${pass}"
echo "FAIL_COUNT=${fail}"
if [ "$fail" -eq 0 ]; then
    echo "STATUS=OK"
    exit 0
fi
echo "STATUS=FAIL"
exit 1
