#!/usr/bin/env bash
# Regression test for emit-legibility-prompt.sh (Slice 1: legibility gate).
#
# Per .claude/rules/regression-testing.md, the prompt-emitter ships with a test
# proving: (a) a valid plugin/skill resolves to an absolute SKILL.md path and
# emits the cold-reader prompt with the verdict tokens, (b) a malformed argument
# is rejected with STATUS=ERROR, (c) a missing SKILL.md is rejected with
# STATUS=ERROR, and (d) the emitted prompt carries the QUESTIONS/HESITATIONS
# headings and the clear|needs-revision verdict that Step-3 triage consumes.
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
emitter="$(dirname "$script_dir")/../skills/evaluate-legibility/scripts/emit-legibility-prompt.sh"

fail_count=0
pass_count=0

check() {
  # check <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (expected '$2', got '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

contains() {
  # contains <description> <haystack> <needle>
  if printf '%s' "$2" | grep -qF -- "$3"; then
    pass_count=$((pass_count + 1))
  else
    echo "FAIL: $1 (output missing '$3')" >&2
    fail_count=$((fail_count + 1))
  fi
}

field() {
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2
}

# Build a throwaway repo with one well-formed skill.
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT
mkdir -p "$tmp_root/demo-plugin/skills/demo-skill"
cat > "$tmp_root/demo-plugin/skills/demo-skill/SKILL.md" <<'EOF'
---
name: demo-skill
description: Demo. Use when testing the legibility emitter.
---

# /demo:demo-skill

## Execution

Run the thing.
EOF

echo "=== TEST: valid plugin/skill resolves and emits prompt ==="
good_out="$("$emitter" --plugin-skill demo-plugin/demo-skill --repo-root "$tmp_root")"
check "good: status" "OK" "$(field "$good_out" STATUS)"
check "good: issue count" "0" "$(field "$good_out" ISSUE_COUNT)"
check "good: plugin" "demo-plugin" "$(field "$good_out" PLUGIN)"
check "good: skill" "demo-skill" "$(field "$good_out" SKILL)"
# SKILL_PATH must be absolute.
skill_path="$(field "$good_out" SKILL_PATH)"
case "$skill_path" in
  /*) pass_count=$((pass_count + 1)) ;;
  *) echo "FAIL: SKILL_PATH not absolute ('$skill_path')" >&2; fail_count=$((fail_count + 1)) ;;
esac
# Prompt block carries the cold-reader schema tokens.
contains "good: prompt has QUESTIONS" "$good_out" "QUESTIONS"
contains "good: prompt has HESITATIONS" "$good_out" "HESITATIONS"
# shellcheck disable=SC2016  # literal backticks are the needle, not command substitution
contains "good: prompt has clear|needs-revision verdict" "$good_out" '`clear` | `needs-revision`'
contains "good: prompt asks WHEN to invoke" "$good_out" "WHEN to invoke"
contains "good: prompt asks FIRST concrete action" "$good_out" "FIRST concrete action"
contains "good: emits PROMPT block delimiters" "$good_out" "=== PROMPT ==="

echo "=== TEST: malformed argument is rejected ==="
bad_arg_out="$("$emitter" --plugin-skill no-slash-here --repo-root "$tmp_root")"
check "bad-arg: status" "ERROR" "$(field "$bad_arg_out" STATUS)"
"$emitter" --plugin-skill no-slash-here --repo-root "$tmp_root" >/dev/null
check "bad-arg: exit code" "1" "$?"

echo "=== TEST: missing argument is rejected ==="
missing_arg_out="$("$emitter" --repo-root "$tmp_root")"
check "missing-arg: status" "ERROR" "$(field "$missing_arg_out" STATUS)"

echo "=== TEST: missing SKILL.md is rejected ==="
missing_out="$("$emitter" --plugin-skill demo-plugin/nonexistent --repo-root "$tmp_root")"
check "missing-skill: status" "ERROR" "$(field "$missing_out" STATUS)"
"$emitter" --plugin-skill demo-plugin/nonexistent --repo-root "$tmp_root" >/dev/null
check "missing-skill: exit code" "1" "$?"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
