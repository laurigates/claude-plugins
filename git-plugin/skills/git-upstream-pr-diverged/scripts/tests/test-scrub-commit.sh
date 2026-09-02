#!/usr/bin/env bash
# Regression test for scrub-commit.sh (issue: current model-family alternation
# missed Fable/Mythos trailers and the Claude-Session: line).
#
# Builds a scratch repo, commits messages carrying:
#   - Co-Authored-By: Claude Fable 5.1
#   - a body line "Reviewed with Claude Fable 5.1"
#   - Claude-Session: https://claude.ai/code/session_x
# and asserts `scrub-commit.sh --check` reports a violation for each, and
# reports OK after the commit is amended to a clean message.
#
# Fully offline. Exit 0 on success, non-zero on failure.

set -uo pipefail

# Neutralize any inherited git env per .claude/rules/agent-coworker-detection.md
# / issue #1745 — a leaked GIT_DIR/GIT_WORK_TREE would redirect these ops at
# the real checkout instead of the scratch sandbox.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scrub_script="${script_dir}/../scrub-commit.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "PASS: $1"
}

[ -f "$scrub_script" ] || fail "scrub-commit.sh not found at $scrub_script"

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] && [ -d "$sandbox" ] || fail "mktemp -d failed"
trap 'rm -rf "$sandbox"' EXIT

repo="$sandbox/repo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config commit.gpgsign false
echo "hello" >"$repo/file.txt"
git -C "$repo" add file.txt

commit_and_check() {
  local msg="$1" label="$2"
  git -C "$repo" commit -q --allow-empty -m "$msg"
  if (cd "$repo" && bash "$scrub_script" --check >/tmp/scrub-out.$$ 2>&1); then
    rm -f /tmp/scrub-out.$$
    fail "$label: expected --check to exit non-zero (violation), got exit 0"
  fi
  grep -qi "claude trailer" /tmp/scrub-out.$$ || {
    cat /tmp/scrub-out.$$
    rm -f /tmp/scrub-out.$$
    fail "$label: --check output did not report a Claude-trailer violation"
  }
  rm -f /tmp/scrub-out.$$
  pass "$label: --check reports a violation"
}

# Case 1: Co-Authored-By: Claude Fable 5.1
commit_and_check "$(printf 'fix: adjust widget\n\nCo-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>')" \
  "Co-Authored-By Claude Fable 5.1"

# Case 2: a body line "Reviewed with Claude Fable 5.1" (no trailer keyword)
commit_and_check "$(printf 'fix: adjust widget\n\nReviewed with Claude Fable 5.1 before submitting.')" \
  "body line 'Reviewed with Claude Fable 5.1'"

# Case 3: Claude-Session: trailer
commit_and_check "$(printf 'fix: adjust widget\n\nClaude-Session: https://claude.ai/code/session_x')" \
  "Claude-Session: trailer"

# Case 4: a clean message (no local issue refs, no Claude trailers) reports OK
git -C "$repo" commit -q --allow-empty --amend -m "fix: adjust widget without any fork-local trailers"
if (cd "$repo" && bash "$scrub_script" --check >/tmp/scrub-out.$$ 2>&1); then
  grep -qi "^OK" /tmp/scrub-out.$$ || {
    cat /tmp/scrub-out.$$
    rm -f /tmp/scrub-out.$$
    fail "clean message: --check exited 0 but did not print an OK line"
  }
  rm -f /tmp/scrub-out.$$
  pass "clean message: --check reports OK"
else
  cat /tmp/scrub-out.$$
  rm -f /tmp/scrub-out.$$
  fail "clean message: expected --check to exit 0, got non-zero"
fi

echo "All scrub-commit.sh tests passed."
exit 0
