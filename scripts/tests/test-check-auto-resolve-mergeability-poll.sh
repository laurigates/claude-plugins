#!/usr/bin/env bash
# Regression test for scripts/check-auto-resolve-mergeability-poll.sh
# (the #1786 mergeability-race fix: auto-resolve-conflicts.yml must poll until
#  each PR's mergeability settles, not read `mergeable` once after the push).
#
# Guards:
#   A. the real repo stays clean — the fixed workflow polls, exit 0
#   B. a fixture with a bounded UNKNOWN poll (UNKNOWN + sleep + DEADLINE) exits 0
#   C. a single-read fixture (no UNKNOWN handling, no sleep) exits 1 and reports
#      no_unknown_poll — the exact regression
#   D. a fixture that inspects UNKNOWN but never waits exits 1 (no_wait)
#   E. an UNBOUNDED poll (UNKNOWN + sleep, no deadline) exits 1 (unbounded_poll)
#   F. a missing workflow file exits 1 (missing_workflow)
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
checker="$repo_root/scripts/check-auto-resolve-mergeability-poll.sh"

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

contains() { printf '%s' "$1" | grep -q -- "$2" && echo true || echo false; }

# write_workflow <project-dir> <find-step-run-body>
write_workflow() {
  mkdir -p "$1/.github/workflows"
  cat > "$1/.github/workflows/auto-resolve-conflicts.yml" <<EOF
name: "PR: Auto-resolve conflicts"
on: { push: { branches: [main] }, workflow_dispatch: {} }
jobs:
  find-conflicts:
    runs-on: ubuntu-latest
    steps:
      - name: Find conflicting PRs
        run: |
$2
EOF
}

tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# A. Real repo
out="$("$checker" --project-dir "$repo_root" 2>&1)"; rc=$?
assert "A: real repo exits 0" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "A: real repo STATUS=OK" "$(contains "$out" "STATUS=OK")"

# B. Bounded UNKNOWN poll → clean
d="$tmp_root/good"
write_workflow "$d" '          DEADLINE=$(( $(date +%s) + 120 ))
          while :; do
            LIST=$(gh pr list --state open --json number,mergeable)
            U=$(echo "$LIST" | jq "[.[] | select(.mergeable == \"UNKNOWN\")] | length")
            { [ "$U" -eq 0 ] || [ "$(date +%s)" -ge "$DEADLINE" ]; } && break
            sleep 8
          done'
out="$("$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "B: bounded poll exits 0" "$([ "$rc" -eq 0 ] && echo true || echo false)"
assert "B: bounded poll STATUS=OK" "$(contains "$out" "STATUS=OK")"

# C. Single-read regression → fail
d="$tmp_root/single"
write_workflow "$d" '          PRS=$(gh pr list --state open --json number,mergeable --jq "[.[] | select(.mergeable == \"CONFLICTING\")]")'
out="$("$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "C: single-read exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "C: single-read reports no_unknown_poll" "$(contains "$out" "no_unknown_poll")"
assert "C: single-read reports no_wait" "$(contains "$out" "no_wait")"

# D. Inspects UNKNOWN but never waits → fail no_wait
d="$tmp_root/nowait"
write_workflow "$d" '          DEADLINE=$(( $(date +%s) + 120 ))
          U=$(gh pr list --json mergeable --jq "[.[] | select(.mergeable == \"UNKNOWN\")] | length")'
out="$("$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "D: no-wait exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "D: no-wait reports no_wait" "$(contains "$out" "no_wait")"

# E. Unbounded poll → fail unbounded_poll
d="$tmp_root/unbounded"
write_workflow "$d" '          while :; do
            U=$(gh pr list --json mergeable --jq "[.[] | select(.mergeable == \"UNKNOWN\")] | length")
            [ "$U" -eq 0 ] && break
            sleep 8
          done'
out="$("$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "E: unbounded exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "E: unbounded reports unbounded_poll" "$(contains "$out" "unbounded_poll")"

# F. Missing workflow → fail
d="$tmp_root/empty"
mkdir -p "$d"
out="$("$checker" --project-dir "$d" 2>&1)"; rc=$?
assert "F: missing workflow exits 1" "$([ "$rc" -eq 1 ] && echo true || echo false)"
assert "F: missing workflow reports missing_workflow" "$(contains "$out" "missing_workflow")"

echo ""
echo "=== test-check-auto-resolve-mergeability-poll: $pass_count passed, $fail_count failed ==="
[ "$fail_count" -eq 0 ]
