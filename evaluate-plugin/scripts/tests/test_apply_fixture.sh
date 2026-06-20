#!/usr/bin/env bash
# Regression test for apply_fixture.sh (Slice 3: fixture/scaffolding layer).
#
# Per .claude/rules/regression-testing.md, the fixture run-engine ships with a
# test proving: (a) a setup-only fixture yields an isolated $WORKDIR with the
# expected state, (b) the workdir is a fresh temp dir OUTSIDE the repo, (c) an
# eval with NO fixture is a no-op (back-compat — FIXTURE_APPLIED=false, no
# WORKDIR), (d) teardown removes the dir, and (e) teardown refuses a path
# outside the temp root (the untrusted-setup blast-radius guard).
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
apply="$(dirname "$script_dir")/apply_fixture.sh"
repo_root="$(cd "$(dirname "$script_dir")/../.." && pwd)"

fail_count=0
pass_count=0

check() {
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() {
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2
}

echo "=== TEST: setup-only fixture yields isolated staged-repo workdir ==="
# Mirrors the Slice-3 minimal increment: git init + a staged file, no dir copy.
setup_fixture='{"setup":["git init -q","printf hello > f.txt","git add f.txt"]}'
apply_out="$("$apply" --fixture "$setup_fixture" --repo-root "$repo_root")"
check "apply: status" "OK" "$(field "$apply_out" STATUS)"
check "apply: applied" "true" "$(field "$apply_out" FIXTURE_APPLIED)"
check "apply: dir not copied" "false" "$(field "$apply_out" DIR_COPIED)"
check "apply: setup count" "3" "$(field "$apply_out" SETUP_COUNT)"

workdir="$(field "$apply_out" WORKDIR)"
# (b) workdir is absolute and OUTSIDE the repo.
case "$workdir" in
  /*) pass_count=$((pass_count + 1)) ;;
  *) echo "FAIL: WORKDIR not absolute ('$workdir')" >&2; fail_count=$((fail_count + 1)) ;;
esac
case "$workdir" in
  "$repo_root"/*) echo "FAIL: WORKDIR is inside the repo ('$workdir')" >&2; fail_count=$((fail_count + 1)) ;;
  *) pass_count=$((pass_count + 1)) ;;
esac
# (a) the setup actually ran: a git repo with f.txt staged.
if [ -d "$workdir/.git" ]; then pass_count=$((pass_count + 1)); else echo "FAIL: workdir has no .git" >&2; fail_count=$((fail_count + 1)); fi
staged="$(cd "$workdir" && git diff --cached --name-only 2>/dev/null)"
check "apply: f.txt is staged" "f.txt" "$staged"

echo "=== TEST: no-fixture eval is a no-op (back-compat) ==="
noop_out="$("$apply" --repo-root "$repo_root")"
check "noop: applied" "false" "$(field "$noop_out" FIXTURE_APPLIED)"
check "noop: status" "OK" "$(field "$noop_out" STATUS)"
# No WORKDIR line at all.
if printf '%s\n' "$noop_out" | grep -q "^WORKDIR="; then
  echo "FAIL: no-fixture run emitted a WORKDIR" >&2; fail_count=$((fail_count + 1))
else
  pass_count=$((pass_count + 1))
fi
# Explicit empty-object fixture is also a no-op.
empty_out="$("$apply" --fixture '{}' --repo-root "$repo_root")"
check "empty: applied" "false" "$(field "$empty_out" FIXTURE_APPLIED)"

echo "=== TEST: teardown removes the workdir ==="
teardown_out="$("$apply" --teardown "$workdir")"
check "teardown: status" "OK" "$(field "$teardown_out" STATUS)"
check "teardown: done" "true" "$(field "$teardown_out" TEARDOWN_DONE)"
if [ -d "$workdir" ]; then
  echo "FAIL: workdir still exists after teardown ('$workdir')" >&2; fail_count=$((fail_count + 1))
  rm -rf "$workdir"
else
  pass_count=$((pass_count + 1))
fi

echo "=== TEST: teardown refuses a path outside the temp root ==="
guard_dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
mkdir -p "$repo_root/.git-fixture-probe-DO-NOT-REMOVE" 2>/dev/null || true
unsafe="$repo_root/.git-fixture-probe-DO-NOT-REMOVE"
guard_out="$("$apply" --teardown "$unsafe")"
check "guard: refuses outside temp" "ERROR" "$(field "$guard_out" STATUS)"
if [ -d "$unsafe" ]; then pass_count=$((pass_count + 1)); else echo "FAIL: guard removed an in-repo path!" >&2; fail_count=$((fail_count + 1)); fi
rmdir "$unsafe" 2>/dev/null || rm -rf "$unsafe"
rm -rf "$guard_dir"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
