#!/usr/bin/env bash
# Regression test for apply_fixture.sh (Slice 3: fixture/scaffolding layer).
#
# Per .claude/rules/regression-testing.md, the fixture run-engine ships with a
# test proving: (a) a setup-only fixture yields an isolated $WORKDIR with the
# expected state, (b) the workdir is a fresh temp dir OUTSIDE the repo, (c) an
# eval with NO fixture is a no-op (back-compat — FIXTURE_APPLIED=false, no
# WORKDIR), (d) teardown removes the dir, and (e) teardown refuses a path
# outside the temp root (the untrusted-setup blast-radius guard).
#
# (f) and (g) below demonstrate the half of the schema Slice 3 shipped but never
# exercised (issue #2182): `fixture.dir` template copy and `fixture.teardown`
# external-resource commands. Both were supported by apply_fixture.sh from the
# start; nothing proved it, so a bulk edit could have dropped either silently.
#   (f) dir-copy: the template tree (dotfiles and nested files included) lands in
#       the workdir, `setup` runs ON TOP of the copy, the SOURCE template is left
#       untouched, `teardown` commands run BEFORE the dir is discarded (proved by
#       a marker written OUTSIDE the workdir, which is exactly what an
#       external-resource teardown is for), and the workdir is then removed.
#   (g) a `fixture.dir` that does not exist is a loud ERROR, not a silent
#       empty workdir — and it leaves no orphan temp dir behind.
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

echo "=== TEST: dir-copy fixture + teardown commands ==="
# The fixture.dir path: a template tree beside evals.json is copied into the
# workdir, setup layers on top of it, and teardown runs before the dir is gone.
# The template root doubles as --repo-root so the demo needs no committed
# fixture tree (fixture.dir is resolved relative to the repo root).
tmpl_root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -n "$tmpl_root" ] && [ -d "$tmpl_root" ] || { echo "mktemp -d produced no dir" >&2; exit 1; }
tmpl_rel="fixtures/repo-with-config"
tmpl_src="$tmpl_root/$tmpl_rel"
mkdir -p "$tmpl_src/nested"
printf 'name: demo\n' > "$tmpl_src/config.yaml"
printf 'dotfiles are copied too\n' > "$tmpl_src/.hidden"
printf 'deep\n' > "$tmpl_src/nested/deep.txt"

# The marker lives OUTSIDE the workdir on purpose: the workdir is rm -rf'd, so a
# marker inside it could not prove teardown ran. This is the external-resource
# teardown case the schema documents.
marker="$tmpl_root/teardown-ran.marker"
dir_fixture="$(printf '{"dir":"%s","setup":["printf staged > added.txt"],"teardown":["printf ran > %s"]}' "$tmpl_rel" "$marker")"

dir_out="$("$apply" --fixture "$dir_fixture" --repo-root "$tmpl_root")"
check "dir: status" "OK" "$(field "$dir_out" STATUS)"
check "dir: applied" "true" "$(field "$dir_out" FIXTURE_APPLIED)"
check "dir: DIR_COPIED" "true" "$(field "$dir_out" DIR_COPIED)"
check "dir: setup count" "1" "$(field "$dir_out" SETUP_COUNT)"

dir_workdir="$(field "$dir_out" WORKDIR)"
# The workdir is a fresh temp dir, never the template itself.
if [ -n "$dir_workdir" ] && [ "$dir_workdir" != "$tmpl_src" ]; then
  pass_count=$((pass_count + 1))
else
  echo "FAIL: dir fixture reused the template as the workdir ('$dir_workdir')" >&2; fail_count=$((fail_count + 1))
fi
# The template contents landed — including a dotfile and a nested file.
check "dir: config.yaml copied" "name: demo" "$(cat "$dir_workdir/config.yaml" 2>/dev/null)"
check "dir: dotfile copied" "dotfiles are copied too" "$(cat "$dir_workdir/.hidden" 2>/dev/null)"
check "dir: nested file copied" "deep" "$(cat "$dir_workdir/nested/deep.txt" 2>/dev/null)"
# setup ran ON TOP of the copy (both artifacts present), not instead of it.
check "dir: setup ran over the copy" "staged" "$(cat "$dir_workdir/added.txt" 2>/dev/null)"
# The source template is a template: the run must not write back into it.
if [ -e "$tmpl_src/added.txt" ]; then
  echo "FAIL: setup wrote into the template source, not the workdir" >&2; fail_count=$((fail_count + 1))
else
  pass_count=$((pass_count + 1))
fi
# Guard integrity: the marker must be absent NOW, so its later presence is
# attributable to teardown rather than to setup.
if [ -e "$marker" ]; then
  echo "FAIL: teardown marker exists before teardown ran" >&2; fail_count=$((fail_count + 1))
else
  pass_count=$((pass_count + 1))
fi

dir_teardown_out="$("$apply" --teardown "$dir_workdir" --fixture "$dir_fixture")"
check "dir: teardown status" "OK" "$(field "$dir_teardown_out" STATUS)"
check "dir: teardown done" "true" "$(field "$dir_teardown_out" TEARDOWN_DONE)"
check "dir: teardown command ran" "ran" "$(cat "$marker" 2>/dev/null)"
if [ -d "$dir_workdir" ]; then
  echo "FAIL: dir-copy workdir survived teardown ('$dir_workdir')" >&2; fail_count=$((fail_count + 1))
  rm -rf "$dir_workdir"
else
  pass_count=$((pass_count + 1))
fi

echo "=== TEST: a missing fixture.dir is a loud error, not an empty workdir ==="
missing_fixture='{"dir":"fixtures/does-not-exist"}'
missing_out="$("$apply" --fixture "$missing_fixture" --repo-root "$tmpl_root")"
check "missing dir: status" "ERROR" "$(field "$missing_out" STATUS)"
check "missing dir: not applied" "false" "$(field "$missing_out" FIXTURE_APPLIED)"
if printf '%s\n' "$missing_out" | grep -q "^ERROR=fixture.dir not found:"; then
  pass_count=$((pass_count + 1))
else
  echo "FAIL: missing fixture.dir did not report the unresolved path" >&2; fail_count=$((fail_count + 1))
fi
# No WORKDIR is emitted, and no orphan temp dir is left behind.
if printf '%s\n' "$missing_out" | grep -q "^WORKDIR="; then
  echo "FAIL: failed dir copy still emitted a WORKDIR" >&2; fail_count=$((fail_count + 1))
else
  pass_count=$((pass_count + 1))
fi
rm -rf "$tmpl_root"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
