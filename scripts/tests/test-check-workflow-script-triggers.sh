#!/usr/bin/env bash
# Regression test for scripts/check-workflow-script-triggers.sh (issue #2219,
# mechanism 1: "a guard's own change does not trigger the workflow that runs it").
#
# The load-bearing case is B: it replays the VERBATIM pre-#2258 `paths:` filter
# from plugin-pr-checks.yml against a `scripts/check-*.sh` invocation and requires
# the guard to flag it. Without that, every "clean" assertion here would also pass
# against a checker that parses nothing.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-workflow-script-triggers.sh"

pass_count=0
fail_count=0

assert() {
  if [ "$2" = "true" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1" >&2
    fail_count=$((fail_count + 1))
  fi
}

is_true() { [ "$1" = "true" ] && echo true || echo false; }
contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

fx="$(mktemp -d)"
[ -n "$fx" ] || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$fx"' EXIT

mkwf() { mkdir -p "$1/.github/workflows"; }

# --- TEST A: the real repo is clean ------------------------------------------
echo "=== TEST A: real repo has no unreachable script invocations ==="
out="$(bash "$checker" --strict 2>&1)"; rc=$?
assert "real repo exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "real repo STATUS=OK" "$(contains "$out" 'STATUS=OK')"
# Guard integrity: the run must actually have INSPECTED workflows. A checker that
# silently found nothing would also print STATUS=OK.
assert "real repo scanned a non-zero number of workflows" \
  "$([ "$(contains "$out" 'WORKFLOWS_SCANNED=0')" = false ] && echo true || echo false)"
assert "real repo is not marked SCANNED_EMPTY" "$(contains "$out" 'SCANNED_EMPTY=false')"

# --- TEST B: the verbatim pre-#2258 defect is caught -------------------------
echo "=== TEST B: pre-#2258 paths: filter orphaning a .sh guard is ERROR ==="
b="$fx/b"; mkwf "$b"
cat > "$b/.github/workflows/plugin-pr-checks.yml" <<'EOF'
name: "Plugin: PR checks"
on:
  pull_request:
    types: [opened, synchronize, reopened]
    paths:
      - '*-plugin/**'
      - '.claude-plugin/marketplace.json'
      - '**/skills/**'
      - '.github/workflows/**'
      - '**/*.py'
      - 'ruff.toml'
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - name: Check every plugin agent runs on opus
        run: bash scripts/check-agent-model.sh
      - name: Check looping skills keep an independent stop condition
        run: bash scripts/check-loop-integrity.sh --strict
EOF
out="$(bash "$checker" --project-dir "$b" --strict 2>&1)"; rc=$?
assert "orphaned .sh guard exits 1 under --strict" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "orphaned .sh guard reports STATUS=ERROR" "$(contains "$out" 'STATUS=ERROR')"
assert "orphaned .sh guard is named" "$(contains "$out" 'SCRIPT=scripts/check-agent-model.sh')"
assert "second orphaned .sh guard is named" "$(contains "$out" 'SCRIPT=scripts/check-loop-integrity.sh')"
assert "orphaned .sh guard uses the unreachable_script type" "$(contains "$out" 'unreachable_script')"
# Without --strict the finding is still reported, but the run does not fail.
out="$(bash "$checker" --project-dir "$b" 2>&1)"; rc=$?
assert "non-strict run still exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "non-strict run still reports the finding" "$(contains "$out" 'ERROR_COUNT=2')"

# --- TEST C: `**/*.py` really does cover a .py under scripts/ ----------------
# This is the subtlety that made the original bug hard to see: the filter DID
# cover Python under scripts/, so the list looked complete. Only `.sh` fell through.
echo "=== TEST C: a .py script under the same filter is reachable ==="
c="$fx/c"; mkwf "$c"
cat > "$c/.github/workflows/py.yml" <<'EOF'
on:
  pull_request:
    paths:
      - '**/*.py'
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: python3 scripts/check-context-engineering.py --strict
EOF
out="$(bash "$checker" --project-dir "$c" --strict 2>&1)"; rc=$?
assert "a .py invocation under **/*.py exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "a .py invocation under **/*.py is not flagged" \
  "$([ "$(contains "$out" 'unreachable_script')" = false ] && echo true || echo false)"
assert "the .py invocation was actually counted" "$(contains "$out" 'PATH_FILTERED_INVOCATIONS=1')"

# --- TEST D: an explicit scripts/** filter makes the guard reachable ---------
echo "=== TEST D: adding scripts/** resolves the finding ==="
d="$fx/d"; mkwf "$d"
cat > "$d/.github/workflows/ok.yml" <<'EOF'
on:
  pull_request:
    paths:
      - '*-plugin/**'
      - 'scripts/**'
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: bash scripts/check-agent-model.sh
EOF
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "scripts/** filter exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "scripts/** filter reports STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "scripts/** invocation was counted, not skipped" "$(contains "$out" 'PATH_FILTERED_INVOCATIONS=1')"

# --- TEST E: no paths: filter at all is the current repo shape --------------
# #2258 removed the filter entirely so the context always REPORTS. Nothing can be
# orphaned, and such invocations are deliberately not counted as path-filtered.
echo "=== TEST E: a workflow with no paths: filter is never flagged ==="
e="$fx/e"; mkwf "$e"
cat > "$e/.github/workflows/nofilter.yml" <<'EOF'
on:
  pull_request:
    types: [opened, synchronize, reopened]
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: bash scripts/check-agent-model.sh
EOF
out="$(bash "$checker" --project-dir "$e" --strict 2>&1)"; rc=$?
assert "no-filter workflow exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "no-filter workflow reports STATUS=OK" "$(contains "$out" 'STATUS=OK')"
assert "no-filter workflow counts zero path-filtered invocations" "$(contains "$out" 'PATH_FILTERED_INVOCATIONS=0')"

# --- TEST F: a push-only paths: filter is not a pull_request gate ------------
echo "=== TEST F: a push-only paths: filter is ignored ==="
f="$fx/f"; mkwf "$f"
cat > "$f/.github/workflows/pushonly.yml" <<'EOF'
on:
  push:
    paths:
      - '*-plugin/**'
jobs:
  j:
    runs-on: ubuntu-latest
    steps:
      - run: bash scripts/check-agent-model.sh
EOF
out="$(bash "$checker" --project-dir "$f" --strict 2>&1)"; rc=$?
assert "push-only filter exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "push-only filter is not flagged" \
  "$([ "$(contains "$out" 'unreachable_script')" = false ] && echo true || echo false)"

# --- TEST G: argument handling ----------------------------------------------
echo "=== TEST G: an unknown argument is rejected, not swallowed (#2057) ==="
out="$(bash "$checker" --strictt 2>&1)"; rc=$?
assert "unknown argument exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
assert "unknown argument is named" "$(contains "$out" 'unknown argument')"
assert "unknown argument prints usage" "$(contains "$out" 'Usage:')"
assert "unknown argument scans nothing" \
  "$([ "$(contains "$out" 'WORKFLOWS_SCANNED')" = false ] && echo true || echo false)"

# --- TEST H: an empty corpus stays green ------------------------------------
# A checker that errors on a repo with no workflows gets disabled.
echo "=== TEST H: no workflow dir reports SCANNED_EMPTY and exits 0 ==="
h="$fx/h"; mkdir -p "$h"
out="$(bash "$checker" --project-dir "$h" --strict 2>&1)"; rc=$?
assert "no workflow dir exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "no workflow dir marks SCANNED_EMPTY=true" "$(contains "$out" 'SCANNED_EMPTY=true')"

echo ""
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
