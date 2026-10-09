#!/usr/bin/env bash
# test-bun-pin.sh — regression test: every generated setup-bun step reads the
# pack's .bun-version.
#
# Packs commit web/dist and CI diffs it against a fresh `bun run build`. The
# template's setup-bun steps were unpinned, so the runner took the latest bun;
# 1.4.2 renamed bundled identifiers vs 1.3.14 (`idx2` -> `idx`) and the
# typecheck-build job went red on every PR across the fleet (2026-10). This
# test EXECUTES the generator for every variant and asserts:
#   1. .bun-version exists and holds a plain x.y.z version
#   2. each setup-bun step in each generated workflow carries
#      `bun-version-file: .bun-version` and no inline `bun-version:`
#      (setup-bun prefers the inline input, which would reintroduce the drift)
#   3. the workflows contain at least one setup-bun step (paired positive:
#      without it, (2) is "every step in an empty set is pinned")
#   4. .comfyignore lists .bun-version, so it stays out of the registry tarball
#      (tests/test_publish_hygiene.py fails on an unclassified top-level file)
#
# Requires python3; SKIPs cleanly when it is unavailable.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAFFOLD="${SCRIPT_DIR}/../../scaffold.py"

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

WORK="$(mktemp -d)"
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Prints "<steps> <pinned> <inline>" for one workflow file: setup-bun steps,
# those whose `with:` block sets bun-version-file: .bun-version, and those
# setting an inline bun-version. A step is the `uses:` line up to the next
# line at or below its own indentation that is not part of its `with:` block.
count_steps() {
    python3 - "$1" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
steps = pinned = inline = 0
for i, line in enumerate(lines):
    m = re.match(r"^(\s*)(?:- )?uses: oven-sh/setup-bun@", line)
    if not m:
        continue
    steps += 1
    indent = len(m.group(1))
    for nxt in lines[i + 1:]:
        if nxt.strip() and len(nxt) - len(nxt.lstrip()) <= indent and not nxt.strip().startswith("with:"):
            break
        s = nxt.strip()
        if s == "bun-version-file: .bun-version":
            pinned += 1
        elif s.startswith("bun-version:"):
            inline += 1
print(steps, pinned, inline)
PY
}

for variant in frontend backend gesture shim; do
    name="comfyui-bunpin-${variant}"
    python3 "$SCAFFOLD" --name "$name" --display "Bunpin ${variant}" \
        --desc "x" --variant "$variant" --dir "$WORK" >/dev/null 2>&1
    P="$WORK/$name"

    ver="$(tr -d '\n' < "$P/.bun-version" 2>/dev/null || echo MISSING)"
    if printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        check "$variant: .bun-version holds x.y.z" "ok" "ok"
    else
        check "$variant: .bun-version holds x.y.z" "ok" "$ver"
    fi

    total=0
    for wf in "$P"/.github/workflows/*.yml; do
        read -r steps pinned inline < <(count_steps "$wf")
        total=$((total + steps))
        check "$variant: $(basename "$wf") setup-bun steps all read .bun-version" "$steps" "$pinned"
        check "$variant: $(basename "$wf") has no inline bun-version" "0" "$inline"
    done
    if [ "$total" -gt 0 ]; then
        check "$variant: generated workflows contain setup-bun steps" "yes" "yes"
    else
        check "$variant: generated workflows contain setup-bun steps" "yes" "no"
    fi

    if grep -qx '\.bun-version' "$P/.comfyignore"; then
        check "$variant: .comfyignore lists .bun-version" "present" "present"
    else
        check "$variant: .comfyignore lists .bun-version" "present" "absent"
    fi
done

echo
echo "test-bun-pin.sh: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
