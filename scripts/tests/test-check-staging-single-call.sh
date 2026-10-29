#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures hold literal markdown backticks on purpose
# Regression test for scripts/check-staging-single-call.sh (issue #3042).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../check-staging-single-call.sh"
VALIDATE="$SCRIPT_DIR/../check-structured-output-contract.sh"

pass=0
fail=0
tmp_root="$(mktemp -d)" || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$tmp_root" ] || [ ! -d "$tmp_root" ]; then
  echo "mktemp returned no dir" >&2
  exit 1
fi
trap 'rm -rf "$tmp_root"' EXIT

SKILL_REL="git-plugin/skills/git-local-hazards/SKILL.md"

make_fixture() {
  local name="$1" body="$2"
  local root="$tmp_root/$name"
  mkdir -p "$root/$(dirname "$SKILL_REL")" "$root/.claude/rules"
  printf '%s\n' "$body" >"$root/$SKILL_REL"
  echo "$root"
}

GOOD_BODY='- **Rules**: run `git status --short` first, then ONE `git add -- A B C`, then `git commit` as a separate call.'
BAD_BODY='- **Rules**: one pathspec per `git add`, or only confirmed-present paths.
- **Check**: `git status --short` before committing.'

# assert <label> <expected-exit> <expected-type-or-empty> <root>
assert() {
  local label="$1" want_exit="$2" want_type="$3" root="$4" out got_exit
  out="$(bash "$CHECK" --root "$root")"
  got_exit=$?
  if [ "$got_exit" -ne "$want_exit" ]; then
    echo "FAIL: $label (exit $got_exit, want $want_exit)"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$want_type" ] && ! grep -qF "TYPE=$want_type" <<<"$out"; then
    echo "FAIL: $label (missing TYPE=$want_type)"
    fail=$((fail + 1))
    return
  fi
  if ! bash "$VALIDATE" --validate <<<"$out" >/dev/null; then
    echo "FAIL: $label (structured-output --validate rejected the block)"
    fail=$((fail + 1))
    return
  fi
  echo "PASS: $label"
  pass=$((pass + 1))
}

# A: the unfixed wording fails, naming the rule
assert "A: 'one pathspec per' fails" 1 one_pathspec_per "$(make_fixture a "$BAD_BODY")"

# B: the single-call wording passes
assert "B: single git add -- form passes" 0 "" "$(make_fixture b "$GOOD_BODY")"

# C: a reword that drops the prescribed form fails
assert "C: dropped replacement form fails" 1 single_call_form_missing "$(make_fixture c 'Stage files carefully.')"

# D: the phrase in a .claude/rules file also fails
root_d="$(make_fixture d "$GOOD_BODY")"
printf 'Use one pathspec per `git add`.\n' >"$root_d/.claude/rules/x.md"
assert "D: rule copy fails" 1 one_pathspec_per "$root_d"

# E: a release-please CHANGELOG.md naming the old wording is skipped
root_e="$(make_fixture e "$GOOD_BODY")"
printf '## 1.0.0 (2026-01-01)\n* drop one pathspec per git add\n' >"$root_e/git-plugin/CHANGELOG.md"
assert "E: CHANGELOG.md skipped" 0 "" "$root_e"

# F: plugin dir with no markdown is a misfired walk, not a clean pass
root_f="$tmp_root/f"
mkdir -p "$root_f/empty-plugin"
assert "F: zero markdown discovered fails" 1 nothing_scanned "$root_f"

echo "PASSED=$pass FAILED=$fail"
[ "$fail" -eq 0 ]
