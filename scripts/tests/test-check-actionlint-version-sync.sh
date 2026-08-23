#!/usr/bin/env bash
# Regression test for scripts/check-actionlint-version-sync.sh.
#
# The bug this guards: actionlint is pinned in TWO places -- the pre-commit
# `rev:` and the `go install ...@vX.Y.Z` step in plugin-pr-checks.yml -- and the
# only thing holding them together was a comment reading "Keep in sync with the
# actionlint CI step". When they drift, CI rejects a workflow the local hook
# just approved, and the failure reads as a mystery because pre-commit passed.
# ruff already earned a dedicated guard here for exactly this shape; actionlint
# had none.
#
# The load-bearing cases are B and C: B replays real skew and requires the guard
# to flag it; C replays an unpinned CI install. Without them, every "clean"
# assertion would also pass against a guard that parses nothing -- which is why
# TEST A additionally asserts the guard actually FOUND a pin rather than
# silently scanning zero files.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-actionlint-version-sync.sh"

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

# mkrepo <name> <precommit-rev> <ci-install-line>
mkrepo() {
  local d="$fx/$1"
  mkdir -p "$d/.github/workflows"
  cat > "$d/.pre-commit-config.yaml" <<EOF
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.14.6
    hooks:
      - id: ruff
  - repo: https://github.com/rhysd/actionlint
    rev: $2
    hooks:
      - id: actionlint
EOF
  cat > "$d/.github/workflows/plugin-pr-checks.yml" <<EOF
name: "Plugin: PR checks"
on: pull_request
jobs:
  compliance:
    runs-on: ubuntu-latest
    steps:
      - name: Install actionlint
        run: |
          $3
          echo "\$(go env GOPATH)/bin" >> "\$GITHUB_PATH"
EOF
  printf '%s' "$d"
}

# --- TEST A: the real repo ---------------------------------------------------
echo "=== TEST A: real repo pins agree ==="
out="$(bash "$checker" --strict 2>&1)"; rc=$?
assert "A exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "A STATUS=OK" "$(contains "$out" 'STATUS=OK')"
# Guard integrity: a checker that found no install site would also print OK.
assert "A actually found a CI pin" \
  "$([ "$(contains "$out" 'CI_PIN_COUNT=0')" = false ] && echo true || echo false)"
assert "A is not SCANNED_EMPTY" "$(contains "$out" 'SCANNED_EMPTY=false')"
assert "A read a pre-commit rev" \
  "$([ "$(contains "$out" 'PRECOMMIT_REV=none')" = false ] && echo true || echo false)"

# --- TEST B: version skew (the real failure) ---------------------------------
echo "=== TEST B: skew between pre-commit rev and CI pin is flagged ==="
d="$(mkrepo b 'v1.7.12' 'go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.11')"
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "B exits 1 under --strict" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "B STATUS=FAIL" "$(contains "$out" 'STATUS=FAIL')"
assert "B names the skew type" "$(contains "$out" 'TYPE=actionlint_version_skew')"
assert "B reports both versions" \
  "$([ "$(contains "$out" 'v1.7.11')" = true ] && [ "$(contains "$out" 'v1.7.12')" = true ] && echo true || echo false)"

# --- TEST C: unpinned CI install ---------------------------------------------
echo "=== TEST C: an unpinned CI install is flagged ==="
d="$(mkrepo c 'v1.7.12' 'go install github.com/rhysd/actionlint/cmd/actionlint@latest')"
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "C exits 1" "$(is_true "$([ $rc -eq 1 ] && echo true)")"
assert "C names the unpinned type" "$(contains "$out" 'TYPE=unpinned_ci_actionlint')"

# --- TEST D: agreement is really compared, not assumed ------------------------
echo "=== TEST D: matching versions pass ==="
d="$(mkrepo d 'v1.7.12' 'go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.12')"
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "D exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "D STATUS=OK" "$(contains "$out" 'STATUS=OK')"

# --- TEST E: `v` prefix is normalised ----------------------------------------
echo "=== TEST E: a bare X.Y.Z CI pin compares equal to vX.Y.Z ==="
d="$(mkrepo e 'v1.7.12' 'go install github.com/rhysd/actionlint/cmd/actionlint@1.7.12')"
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "E exits 0 (no false skew on the v prefix)" "$(is_true "$([ $rc -eq 0 ] && echo true)")"

# --- TEST F: --strict gates the exit code ------------------------------------
echo "=== TEST F: skew is reported but non-fatal without --strict ==="
d="$(mkrepo f 'v1.7.12' 'go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.11')"
out="$(bash "$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "F exits 0 without --strict" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "F still reports STATUS=FAIL" "$(contains "$out" 'STATUS=FAIL')"

# --- TEST G: guard integrity on an empty tree --------------------------------
echo "=== TEST G: a tree with no actionlint install is marked SCANNED_EMPTY ==="
d="$fx/g"; mkdir -p "$d/.github/workflows"
printf 'repos: []\n' > "$d/.pre-commit-config.yaml"
printf 'name: x\non: push\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo hi\n' \
  > "$d/.github/workflows/w.yml"
out="$(bash "$checker" --project-dir "$d" --strict 2>&1)"; rc=$?
assert "G exits 0" "$(is_true "$([ $rc -eq 0 ] && echo true)")"
assert "G is marked SCANNED_EMPTY" "$(contains "$out" 'SCANNED_EMPTY=true')"

# --- TEST H: unknown argument is rejected, never swallowed -------------------
echo "=== TEST H: unknown argument exits 2 ==="
out="$(bash "$checker" --not-a-real-flag 2>&1)"; rc=$?
assert "H exits 2" "$(is_true "$([ $rc -eq 2 ] && echo true)")"
assert "H names the offending flag" "$(contains "$out" 'unknown argument')"

echo ""
echo "=== RESULTS ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
