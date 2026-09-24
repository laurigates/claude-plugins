#!/usr/bin/env bash
# Regression test for prepare_run.sh — the eval run directory must be staged
# OUTSIDE any `skills/` directory (issue #2667).
#
# WHY IT MATTERS
# Path-scoped rules load whole into an agent's context the moment it touches a
# file matching their `paths:` glob. Fourteen rules in this repo are scoped to
# `**/skills/**`. prepare_run.sh used to stage every run at
# `<skill-dir>/eval-results/<runs|baseline>/…`, i.e. INSIDE `**/skills/**`, so
# an eval subagent writing its transcript there pulled all of those rules in —
# the 2026-09 golden-set sweep's haiku arm died on HTTP 400 "Prompt is too long"
# before executing anything.
#
# What this pins:
#   (a) RUN_DIR has no `skills` path component below the repo root, for both the
#       with-skill and the --baseline configs
#   (b) RUN_DIR is ABSOLUTE even when --skill-dir is relative (the header always
#       promised it; a relative path breaks the moment the caller changes cwd)
#   (c) the run dir and a well-formed manifest.json actually exist
#   (d) two skills never share a run dir (staging moved from per-skill to a
#       shared root, so collisions are a new risk this must rule out)
#   (e) EVAL_RUNS_ROOT is honoured, and pointing it INSIDE a skills/ dir is
#       refused loudly with nothing created
#   (f) missing required args still exit 1
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prepare="$(dirname "$script_dir")/prepare_run.sh"

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
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2-
}

# A path is "under skills" when any component below the repo root is `skills`.
# This is the property the path-scoped `**/skills/**` glob tests.
under_skills() {
  local path="$1" root="$2" rel
  rel="${path#"$root"/}"
  case "/$rel/" in
    */skills/*) echo true ;;
    *) echo false ;;
  esac
}

# Neutralise inherited git context (#1745): an exported GIT_DIR/GIT_WORK_TREE
# would make the fixture's `git init` target the real shared .git.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
unset EVAL_RUNS_ROOT

sandbox="$(mktemp -d)"
# Guard the empty-mktemp vector (#1692): `git -C ""` falls back to the CWD.
[ -n "$sandbox" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
[ -d "$sandbox" ] || { echo "FAIL: mktemp -d dir missing" >&2; exit 1; }
trap 'rm -rf "$sandbox"' EXIT
# Resolve symlinks (macOS /var -> /private/var) so prefix comparisons are exact.
sandbox="$(cd "$sandbox" && pwd -P)"

repo="$sandbox/repo"
mkdir -p "$repo/demo-plugin/skills/demo-skill" "$repo/demo-plugin/skills/other-skill"
printf -- '---\nname: demo-skill\n---\n' >"$repo/demo-plugin/skills/demo-skill/SKILL.md"
printf -- '---\nname: other-skill\n---\n' >"$repo/demo-plugin/skills/other-skill/SKILL.md"
git -C "$repo" init -q
# Fixture validity: the skill dir itself IS under skills/, so a prepare_run that
# returned it (or anything beneath it) would be caught by under_skills.
check "fixture: the skill dir is itself under skills/" "true" \
  "$(under_skills "$repo/demo-plugin/skills/demo-skill/x" "$repo")"

echo "=== TEST: with-skill run dir is staged outside skills/ ==="
out="$(cd "$repo" && bash "$prepare" --skill-dir demo-plugin/skills/demo-skill --eval-id e1 --run 1)"
check "with-skill: exit 0" "0" "$?"
run_dir="$(field "$out" RUN_DIR)"
manifest="$(field "$out" MANIFEST)"
check "(a) with-skill RUN_DIR is not under skills/" "false" "$(under_skills "$run_dir" "$repo")"
case "$run_dir" in
  /*) check "(b) RUN_DIR is absolute for a relative --skill-dir" "absolute" "absolute" ;;
  *) check "(b) RUN_DIR is absolute for a relative --skill-dir" "absolute" "$run_dir" ;;
esac
case "$run_dir" in
  "$repo"/*) check "RUN_DIR stays inside the repo (tmp/ convention)" "inside" "inside" ;;
  *) check "RUN_DIR stays inside the repo (tmp/ convention)" "inside" "$run_dir" ;;
esac
check "(c) run dir exists" "true" "$([ -d "$run_dir" ] && echo true || echo false)"
check "(c) manifest exists" "true" "$([ -f "$manifest" ] && echo true || echo false)"
check "(c) manifest records the eval id" "e1" "$(jq -r .eval_id "$manifest" 2>/dev/null)"
check "(c) manifest records baseline=false" "false" "$(jq -r .baseline "$manifest" 2>/dev/null)"
check "nothing was created inside the skill dir" "" \
  "$(find "$repo/demo-plugin/skills" -mindepth 2 -not -name SKILL.md -print -quit)"

echo "=== TEST: baseline run dir is staged outside skills/ too ==="
bout="$(cd "$repo" && bash "$prepare" --skill-dir demo-plugin/skills/demo-skill --eval-id e1 --run 1 --baseline)"
brun="$(field "$bout" RUN_DIR)"
check "(a) baseline RUN_DIR is not under skills/" "false" "$(under_skills "$brun" "$repo")"
check "baseline and with-skill dirs differ" "differ" "$([ "$brun" != "$run_dir" ] && echo differ || echo same)"
check "(c) baseline manifest records baseline=true" "true" "$(jq -r .baseline "$(field "$bout" MANIFEST)" 2>/dev/null)"

echo "=== TEST: an absolute --skill-dir from another cwd lands in the same place ==="
aout="$(cd "$sandbox" && bash "$prepare" --skill-dir "$repo/demo-plugin/skills/demo-skill" --eval-id e1 --run 1)"
check "absolute --skill-dir resolves to the same RUN_DIR" "$run_dir" "$(field "$aout" RUN_DIR)"

echo "=== TEST: two skills never share a run dir ==="
oout="$(cd "$repo" && bash "$prepare" --skill-dir demo-plugin/skills/other-skill --eval-id e1 --run 1)"
orun="$(field "$oout" RUN_DIR)"
check "(d) same eval id + run in two skills -> distinct dirs" "differ" \
  "$([ -n "$orun" ] && [ "$orun" != "$run_dir" ] && echo differ || echo same)"
check "(a) second skill RUN_DIR is not under skills/ either" "false" "$(under_skills "$orun" "$repo")"

echo "=== TEST: EVAL_RUNS_ROOT is honoured ==="
custom="$sandbox/custom-runs"
cout="$(cd "$repo" && EVAL_RUNS_ROOT="$custom" bash "$prepare" --skill-dir demo-plugin/skills/demo-skill --eval-id e2 --run 3)"
crun="$(field "$cout" RUN_DIR)"
case "$crun" in
  "$custom"/*) check "(e) RUN_DIR is under EVAL_RUNS_ROOT" "under" "under" ;;
  *) check "(e) RUN_DIR is under EVAL_RUNS_ROOT" "under" "$crun" ;;
esac

echo "=== TEST: EVAL_RUNS_ROOT inside a skills/ dir is refused ==="
bad="$repo/demo-plugin/skills/demo-skill/runs-here"
(cd "$repo" && EVAL_RUNS_ROOT="$bad" bash "$prepare" --skill-dir demo-plugin/skills/demo-skill --eval-id e3 --run 1 >/dev/null 2>&1)
check "(e) a skills/-scoped EVAL_RUNS_ROOT exits non-zero" "1" "$?"
check "(e) and creates nothing" "false" "$([ -e "$bad" ] && echo true || echo false)"

echo "=== TEST: missing required args still exit 1 ==="
(cd "$repo" && bash "$prepare" --skill-dir demo-plugin/skills/demo-skill >/dev/null 2>&1)
check "(f) missing --eval-id/--run exits 1" "1" "$?"

echo ""
echo "PASS=$pass_count FAIL=$fail_count"
[ "$fail_count" -eq 0 ]
