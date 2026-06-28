#!/usr/bin/env bash
# Regression test for scaffold.py's standalone-modal variant (issue #1806)
#
# Run: bash comfyui-plugin/skills/comfyui-node-scaffold/scripts/tests/test-standalone-modal.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# Covers issue #1806 (backend variant emits a per-widget intercept stub even
# for standalone-modal backend packs):
#   - `--variant backend` with NO `--widgets` emits a STANDALONE-modal
#     src/index.ts (registerExtension + commands/menuCommands + openShell that
#     opens openModalShell) — NOT the per-widget intercept vein (no
#     TARGET_WIDGETS / openPicker / enhanceNode / widget.onPointerDown).
#   - The standalone variant ships a jsdom modal-mount smoke test
#     (tests/js/index.test.js) that imports openShell and asserts the modal body
#     is populated.
#   - The heuristic does NOT over-fire: `--variant backend` WITH `--widgets`
#     still emits the widget-intercept stub (TARGET_WIDGETS present).
set -uo pipefail

SCAFFOLD="$(cd "$(dirname "$0")/../.." && pwd)/scaffold.py"
PASS=0
FAIL=0

WORK=$(mktemp -d)
[ -n "$WORK" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

assert_contains() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  else
    printf "  FAIL: %s (missing '%s' in %s)\n" "$desc" "$needle" "$file"; FAIL=$((FAIL + 1))
  fi
}

assert_absent() {
  local desc="$1" needle="$2" file="$3"
  if grep -qF -- "$needle" "$file"; then
    printf "  FAIL: %s (found '%s' in %s)\n" "$desc" "$needle" "$file"; FAIL=$((FAIL + 1))
  else
    printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
  fi
}

echo "=== TEST: backend + no --widgets -> standalone-modal skeleton (#1806) ==="
python3 "$SCAFFOLD" --name cn-standalone --display "CN Standalone" \
  --desc "manager" --variant backend --dir "$WORK" >/dev/null 2>&1 || {
  echo "  FAIL: scaffold.py exited non-zero"; FAIL=$((FAIL + 1))
}
SA_INDEX="$WORK/cn-standalone/src/index.ts"
SA_TEST="$WORK/cn-standalone/tests/js/index.test.js"

# Standalone index.ts: the modal-opening skeleton, not the per-widget vein.
assert_contains "standalone index.ts exports openShell" \
  "export function openShell" "$SA_INDEX"
assert_contains "standalone index.ts registers an extension" \
  "app.registerExtension(" "$SA_INDEX"
assert_contains "standalone index.ts registers a command" \
  "commands: [" "$SA_INDEX"
assert_contains "standalone index.ts opens the modal shell" \
  "openModalShell(" "$SA_INDEX"
# The per-widget intercept vein must be absent (the bug being fixed).
assert_absent "no TARGET_WIDGETS set in standalone index.ts" \
  "TARGET_WIDGETS = new Set" "$SA_INDEX"
assert_absent "no openPicker in standalone index.ts" \
  "function openPicker" "$SA_INDEX"
assert_absent "no enhanceNode in standalone index.ts" \
  "function enhanceNode" "$SA_INDEX"

# Standalone jsdom modal-mount smoke test.
assert_contains "standalone test runs under jsdom" \
  "@vitest-environment jsdom" "$SA_TEST"
assert_contains "standalone test imports openShell" \
  "openShell" "$SA_TEST"
assert_contains "standalone test asserts the modal body is populated" \
  "modal.bodyEl" "$SA_TEST"
assert_absent "standalone test does not use the widget helper" \
  "clampToTargets" "$SA_TEST"

echo ""
echo "=== TEST: backend + --widgets keeps the widget-intercept stub (#1806) ==="
python3 "$SCAFFOLD" --name cn-widget --display "CN Widget" \
  --desc "widget" --variant backend --widgets seed,steps --dir "$WORK" >/dev/null 2>&1 || {
  echo "  FAIL: scaffold.py exited non-zero"; FAIL=$((FAIL + 1))
}
W_INDEX="$WORK/cn-widget/src/index.ts"
W_TEST="$WORK/cn-widget/tests/js/index.test.js"
assert_contains "widget variant keeps TARGET_WIDGETS" \
  "TARGET_WIDGETS = new Set" "$W_INDEX"
assert_contains "widget variant keeps openPicker" \
  "function openPicker" "$W_INDEX"
assert_absent "widget variant is NOT the standalone skeleton" \
  "export function openShell" "$W_INDEX"
assert_contains "widget variant keeps the clampToTargets smoke test" \
  "clampToTargets" "$W_TEST"

echo ""
echo "PASS=$PASS"
echo "FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
