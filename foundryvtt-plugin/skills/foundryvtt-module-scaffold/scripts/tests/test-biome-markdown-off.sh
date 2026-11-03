#!/usr/bin/env bash
# test-biome-markdown-off.sh — a generated module's biome config keeps biome's
# Markdown formatter and linter off, so `biome check .` passes out of the box
# (#3374).
#
# Biome 2.6 turned on a Markdown formatter by default. The emitted biome.json
# sets `files.includes: ["**"]`, so the formatter reached the generated
# CLAUDE.md and wanted its Layout table column-padded. The padding depends on
# the module id, so no template text can satisfy it; the formatter also
# mangles YAML frontmatter (.claude/rules/biome-markdown.md). The fix is the
# `"markdown": { "formatter": { "enabled": false }, "linter": { "enabled":
# false } }` block, in scaffold.py's BIOME_JSON and the cargo-generate template.
#
# Two layers:
#   1. STATIC, runs everywhere: the biome.json emitted for every variant
#      (basic/app/libwrapper), and the cargo-generate template's biome.json,
#      parse as JSON with markdown.formatter.enabled and
#      markdown.linter.enabled both false.
#   2. BIOME, runs when the pinned biome can be fetched: `biome check .` over
#      each generated variant. SKIPs (exit 0, a `SKIP:` line) when bunx/npx,
#      biome, or the network is unavailable.
#
# Requires python3; SKIPs cleanly when it is unavailable.

set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="${SCRIPT_DIR}/../../scaffold.py"
TEMPLATE_BIOME="${SCRIPT_DIR}/../../../../templates/foundryvtt-module/biome.json"

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

# markdown_state <biome.json> -> "formatter=<v> linter=<v>" (or "unparseable")
markdown_state() {
    python3 -I - "$1" <<'PY' 2>/dev/null || echo unparseable
import json, sys
cfg = json.load(open(sys.argv[1]))
md = cfg.get("markdown", {})
fmt = md.get("formatter", {}).get("enabled", "unset")
lint = md.get("linter", {}).get("enabled", "unset")
print(f"formatter={str(fmt).lower()} linter={str(lint).lower()}")
PY
}

# A long id: the CLAUDE.md Layout table column width grows with it.
NAME=foundryvtt-probe-longname
VARIANTS=(basic app libwrapper)

echo "=== STATIC: biome.json disables Markdown ==="

for variant in "${VARIANTS[@]}"; do
    dir="${WORK}/${variant}"
    mkdir -p "$dir"
    if ! python3 "$SCAFFOLD" --name "$NAME" --display "Probe Module" --desc "Probe" \
        --variant "$variant" --dir "$dir" >"${dir}.log" 2>&1; then
        check "${variant}: scaffolds" "ok" "failed"
        tail -5 "${dir}.log" >&2
        continue
    fi
    check "${variant}: emitted biome.json markdown block" "formatter=false linter=false" \
        "$(markdown_state "${dir}/${NAME}/biome.json")"
done

if [ -f "$TEMPLATE_BIOME" ]; then
    check "cargo-generate template biome.json markdown block" "formatter=false linter=false" \
        "$(markdown_state "$TEMPLATE_BIOME")"
else
    check "cargo-generate template ships biome.json" "present" "absent"
fi

echo "=== BIOME: pinned biome check . ==="

BIOME_VERSION="$(sed -n 's/^BIOME_VERSION = "\([^"]*\)".*/\1/p' "$SCAFFOLD")"
check "BIOME_VERSION is readable from scaffold.py" "yes" "$([ -n "$BIOME_VERSION" ] && echo yes || echo no)"

runner=()
if command -v bunx >/dev/null 2>&1; then
    runner=(bunx --bun "@biomejs/biome@${BIOME_VERSION}")
elif command -v npx >/dev/null 2>&1; then
    runner=(npx --yes "@biomejs/biome@${BIOME_VERSION}")
fi

# GNU `timeout` is absent on stock macOS (coreutils ships it as `gtimeout`).
to=()
if command -v timeout >/dev/null 2>&1; then
    to=(timeout 180)
elif command -v gtimeout >/dev/null 2>&1; then
    to=(gtimeout 180)
fi

biome_ready=no
if [ "${#runner[@]}" -eq 0 ]; then
    echo "SKIP: biome half — neither bunx nor npx is available" >&2
elif [ -z "$BIOME_VERSION" ]; then
    echo "SKIP: biome half — BIOME_VERSION not found" >&2
elif ! (cd "$WORK" && "${to[@]}" "${runner[@]}" --version >"${WORK}/biome-version.log" 2>&1); then
    echo "SKIP: biome half — @biomejs/biome@${BIOME_VERSION} could not be fetched or run (offline?)" >&2
else
    biome_ready=yes
fi

if [ "$biome_ready" = yes ]; then
    for variant in "${VARIANTS[@]}"; do
        module_dir="${WORK}/${variant}/${NAME}"
        [ -f "${module_dir}/biome.json" ] || continue
        rc=0
        (cd "$module_dir" && "${to[@]}" "${runner[@]}" check .) \
            >"${WORK}/${variant}-biome.log" 2>&1 || rc=$?
        check "${variant}: biome ${BIOME_VERSION} check . exits 0" "0" "$rc"
        [ "$rc" -eq 0 ] || tail -20 "${WORK}/${variant}-biome.log" >&2
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
