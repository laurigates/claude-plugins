#!/usr/bin/env bash
# Regression test for scripts/check-ruff-version-sync.sh.
#
# Pins the guard's three cases against hermetic fixtures:
#   A) matching pins            -> STATUS=OK,    exit 0 under --strict
#   B) skewed pins              -> version_skew, exit 1 under --strict
#   C) unpinned `uvx ruff`      -> unpinned_ci_ruff, exit 1 under --strict
#   D) the real repo is in sync -> STATUS=OK
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-ruff-version-sync.sh"

pass=0
fail=0

check() {
  # check <label> <condition-description> <actual> <expected-substring>
  local label="$1" actual="$2" expected="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "  FAIL: $label (expected to contain: $expected)"
    echo "        got: $actual"
  fi
}

make_fixture() {
  # make_fixture <dir> <precommit-rev> <ci-ruff-invocation>
  local dir="$1" rev="$2" ci="$3"
  mkdir -p "$dir/.github/workflows"
  cat > "$dir/.pre-commit-config.yaml" <<EOF
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: $rev
    hooks:
      - id: ruff-check
      - id: ruff-format
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
EOF
  cat > "$dir/.github/workflows/plugin-pr-checks.yml" <<EOF
name: "Plugin: PR checks"
jobs:
  compliance:
    steps:
      - name: Lint Python with ruff
        run: $ci check .
EOF
}

tmp_root="$(mktemp -d)"
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "FAIL: could not create temp dir" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

# --- A) matching pins -------------------------------------------------------
make_fixture "$tmp_root/match" "v0.15.8" "uvx ruff@0.15.8"
out="$(bash "$GUARD" --project-dir "$tmp_root/match" --strict 2>&1)"
rc=$?
check "matching pins -> OK" "$out" "STATUS=OK"
check "matching pins -> exit 0" "$rc" "0"

# --- B) skewed pins ---------------------------------------------------------
make_fixture "$tmp_root/skew" "v0.4.8" "uvx ruff@0.15.8"
out="$(bash "$GUARD" --project-dir "$tmp_root/skew" --strict 2>&1)"
rc=$?
check "skewed pins -> ERROR" "$out" "STATUS=ERROR"
check "skewed pins -> version_skew" "$out" "TYPE=version_skew"
check "skewed pins -> exit 1" "$rc" "1"

# --- C) unpinned CI invocation ---------------------------------------------
make_fixture "$tmp_root/unpinned" "v0.15.8" "uvx ruff"
out="$(bash "$GUARD" --project-dir "$tmp_root/unpinned" --strict 2>&1)"
rc=$?
check "unpinned CI ruff -> ERROR" "$out" "TYPE=unpinned_ci_ruff"
check "unpinned CI ruff -> exit 1" "$rc" "1"

# --- D) the real repo is in sync -------------------------------------------
out="$(bash "$GUARD" --project-dir "$REPO_ROOT" --strict 2>&1)"
rc=$?
check "real repo -> OK" "$out" "STATUS=OK"
check "real repo -> exit 0" "$rc" "0"

echo "=== RUFF VERSION SYNC GUARD TESTS ==="
echo "PASS=$pass"
echo "FAIL=$fail"
if [ "$fail" -gt 0 ]; then
  echo "STATUS=ERROR"
  echo "=== END RUFF VERSION SYNC GUARD TESTS ==="
  exit 1
fi
echo "STATUS=OK"
echo "=== END RUFF VERSION SYNC GUARD TESTS ==="
exit 0
