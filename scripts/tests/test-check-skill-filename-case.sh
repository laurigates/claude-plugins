#!/usr/bin/env bash
# shellcheck disable=SC2015  # file-level: `cmd && ok || ko` is deliberate; ok/ko only echo and cannot fail
# Regression test for scripts/check-skill-filename-case.sh.
#
# The guard reads `git ls-files`, so each case builds a throwaway git repo with
# a copy of the guard and asserts on its report:
#   A) every skill is SKILL.md          -> STATUS=OK, no REASON=, exit 0
#   B) a lowercase skill.md is tracked  -> STATUS=ERROR, REASON= names it, exit 1
#   C) both outputs satisfy check-structured-output-contract.sh --validate (#2760)
#   D) the real repo is clean
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-skill-filename-case.sh"
CONTRACT="$REPO_ROOT/scripts/check-structured-output-contract.sh"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "  PASS: $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL: $1"; }

WORK="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "bad sandbox dir" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# make_repo <dir> <skill-filename>: a git repo whose one skill uses that name.
make_repo() {
  local dir="$1" fname="$2"
  mkdir -p "$dir/scripts" "$dir/demo-plugin/skills/thing"
  cp "$GUARD" "$dir/scripts/"
  printf -- '---\nname: thing\n---\n' > "$dir/demo-plugin/skills/thing/$fname"
  env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" init -q
  env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" add -A
}

run_guard() { (cd "$1" && env -u GIT_DIR -u GIT_WORK_TREE bash scripts/check-skill-filename-case.sh 2>&1); }

make_repo "$WORK/good" "SKILL.md"
out_ok="$(run_guard "$WORK/good")"; rc_ok=$?
[ "$rc_ok" -eq 0 ] && ok "canonical SKILL.md exits 0" || ko "canonical SKILL.md exits 0 (got $rc_ok)"
grep -qx 'STATUS=OK' <<<"$out_ok" && ok "canonical SKILL.md is STATUS=OK" || ko "canonical SKILL.md is STATUS=OK"
grep -q '^REASON=' <<<"$out_ok" && ko "OK output must carry no REASON=" || ok "OK output carries no REASON="

make_repo "$WORK/bad" "skill.md"
out_bad="$(run_guard "$WORK/bad")"; rc_bad=$?
[ "$rc_bad" -eq 1 ] && ok "lowercase skill.md exits 1" || ko "lowercase skill.md exits 1 (got $rc_bad)"
grep -qx 'STATUS=ERROR' <<<"$out_bad" && ok "lowercase skill.md is STATUS=ERROR" || ko "lowercase skill.md is STATUS=ERROR"
if grep -qxF 'REASON=non_canonical_skill_filename: demo-plugin/skills/thing/skill.md: rename to SKILL.md (case-sensitive)' <<<"$out_bad"; then
  ok "ERROR output REASON= names the offender"
else
  ko "ERROR output REASON= names the offender"; echo "$out_bad"
fi

if printf '%s\n' "$out_ok" | bash "$CONTRACT" --validate - >/dev/null 2>&1; then
  ok "OK output satisfies the structured-output contract"
else ko "OK output rejected by --validate"; fi
if printf '%s\n' "$out_bad" | bash "$CONTRACT" --validate - >/dev/null 2>&1; then
  ok "ERROR output satisfies the structured-output contract"
else ko "ERROR output rejected by --validate"; fi

out_real="$(cd "$REPO_ROOT" && bash scripts/check-skill-filename-case.sh 2>&1)"
grep -qx 'STATUS=OK' <<<"$out_real" && ok "real repo is STATUS=OK" || ko "real repo is STATUS=OK"

echo "=== SKILL FILENAME CASE GUARD TESTS ==="
echo "PASS=$pass"
echo "FAIL=$fail"
if [ "$fail" -eq 0 ]; then
  echo "STATUS=OK"
  echo "=== END SKILL FILENAME CASE GUARD TESTS ==="
  exit 0
fi
echo "STATUS=ERROR"
echo "REASON=$fail assertion(s) failed"
echo "=== END SKILL FILENAME CASE GUARD TESTS ==="
exit 1
