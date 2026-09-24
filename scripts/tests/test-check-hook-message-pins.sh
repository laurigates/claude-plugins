#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016,SC1003  # `cond && pass || fail` is deliberate; single-quoted fixture text is written verbatim, not expanded
# Regression test for scripts/check-hook-message-pins.sh (issue #2715).
#
# Every assertion EXECUTES the guard against a planted fixture tree (or the real
# repo, case m) and reads its KEY=VALUE verdict. Case (a) replays the pre-#2715
# suite shape verbatim: an assert_exit that runs the hook with
# `>/dev/null 2>&1`, and a run_hook that keeps stdout but sends stderr, where
# block() writes, to /dev/null.
#
# Run: bash scripts/tests/test-check-hook-message-pins.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/scripts/check-hook-message-pins.sh"

PASS=0
FAIL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

TMP_ROOT="$(mktemp -d)"
[ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMP_ROOT"' EXIT

run_guard() { bash "$GUARD" --project-dir "$1" 2>&1; }
field() { grep -m1 -E "^$2=" <<<"$1" | cut -d= -f2-; }
has() { grep -qF -- "$2" <<<"$1"; }

# expect NAME OUT RC WANT_RC KEY=VALUE...
expect() {
  local name="$1" out="$2" rc="$3" want_rc="$4" kv key val
  shift 4
  if [ "$rc" -ne "$want_rc" ]; then
    fail "$name: expected exit $want_rc, got $rc"
    printf '%s\n' "$out" | sed 's/^/    /'
    return
  fi
  for kv in "$@"; do
    key="${kv%%=*}" val="${kv#*=}"
    if [ "$(field "$out" "$key")" != "$val" ]; then
      fail "$name: expected $key=$val, got $key=$(field "$out" "$key")"
      printf '%s\n' "$out" | sed 's/^/    /'
      return
    fi
  done
  pass "$name"
}

# A blocking hook with one uniquely tagged message (the kubectl shape).
write_kubectl_hook() { # $1 = hooks dir
  mkdir -p "$1"
  cat > "$1/ctx.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
block() {
    echo "$1" >&2
    exit 2
}
INPUT=$(cat)
if echo "$INPUT" | grep -q kubectl; then
    block "KUBECTL SAFETY: Missing --context flag.

  kubectl --context=CONTEXT_NAME <command>"
fi
exit 0
EOF
}

# The pre-#2715 suite, verbatim in shape: exit code only, stderr discarded.
write_prefix_suite() { # $1 = hooks dir
  cat > "$1/test-ctx.sh" <<'EOF'
#!/usr/bin/env bash
HOOK="$(dirname "$0")/ctx.sh"
run_hook() {
    local json="$1"
    printf '%s' "$json" | bash "$HOOK" 2>/dev/null
}
assert_exit() {
    local desc="$1" expected="$2" json="$3" actual exit_code=0
    actual=$(run_hook "$json"; echo "$?") || true
    printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1 || exit_code=$?
    [ "$exit_code" -eq "$expected" ]
}
assert_exit "kubectl without --context is blocked" 2 '{"tool_input":{"command":"kubectl get pods"}}'
EOF
}

# The fixed suite: stderr captured and the headline asserted.
write_fixed_suite() { # $1 = hooks dir
  write_prefix_suite "$1"
  cat >> "$1/test-ctx.sh" <<'EOF'
assert_stderr_contains() {
    local desc="$1" needle="$2" json="$3" out
    out=$(printf '%s' "$json" | bash "$HOOK" 2>&1 >/dev/null || true)
    grep -qF -- "$needle" <<<"$out"
}
assert_stderr_contains "names the flag" "KUBECTL SAFETY: Missing --context flag." '{"tool_input":{"command":"kubectl get pods"}}'
EOF
}

# --- (a) the pre-#2715 suite shape is reported on both rules ---
echo "--- Test (a): exit-code-only suite ERRORs (output_never_captured + message_unpinned) ---"
TREE="$TMP_ROOT/a"
write_kubectl_hook "$TREE/k-plugin/hooks"
write_prefix_suite "$TREE/k-plugin/hooks"
OUT="$(run_guard "$TREE")"; RC=$?
expect "(a) verdict" "$OUT" "$RC" 1 STATUS=ERROR ISSUE_COUNT=2 SUITES_SCANNED=1 BLOCKING_SUITES=1 MESSAGES_CHECKED=1
case "$(field "$OUT" REASON)" in
  "output_never_captured: "?*) pass "(a) REASON= names the first finding" ;;
  *) fail "(a) expected REASON=output_never_captured: ..., got REASON=$(field "$OUT" REASON)" ;;
esac
has "$OUT" "TYPE=output_never_captured SUITE=k-plugin/hooks/test-ctx.sh" \
  && pass "(a) names the suite that never captures stderr" \
  || fail "(a) expected output_never_captured for k-plugin/hooks/test-ctx.sh: $OUT"
has "$OUT" 'TYPE=message_unpinned SUITE=k-plugin/hooks/test-ctx.sh HOOK=k-plugin/hooks/ctx.sh:9 TAG="KUBECTL SAFETY:"' \
  && pass "(a) names the unpinned message by hook line and tag" \
  || fail "(a) expected message_unpinned at ctx.sh:9 with TAG=\"KUBECTL SAFETY:\": $OUT"
has "$OUT" 'grep -qF "KUBECTL SAFETY: Missing --context flag."' \
  && pass "(a) the finding carries a copy-pasteable assertion for the headline" \
  || fail "(a) expected the headline in the suggested assertion: $OUT"

# --- (b) the fixed suite passes; a nested worktree copy is not scanned ---
echo "--- Test (b): capturing suite that asserts the headline is clean ---"
TREE="$TMP_ROOT/b"
write_kubectl_hook "$TREE/k-plugin/hooks"
write_fixed_suite "$TREE/k-plugin/hooks"
# A sibling agent worktree inside the checkout holding the BROKEN suite must not
# be judged as part of this tree (fixed-depth discovery).
write_kubectl_hook "$TREE/.claude/worktrees/agent-y/k-plugin/hooks"
write_prefix_suite "$TREE/.claude/worktrees/agent-y/k-plugin/hooks"
OUT="$(run_guard "$TREE")"; RC=$?
expect "(b) verdict" "$OUT" "$RC" 0 STATUS=OK ISSUE_COUNT=0 SUITES_SCANNED=1 BLOCKING_SUITES=1 BLOCK_MESSAGES=1 MESSAGES_CHECKED=1 MESSAGES_UNCHECKED=0
has "$OUT" "REASON=" && fail "(b) REASON= must not appear on the OK path" || pass "(b) no REASON= on the OK path"

# --- (c) per-message: one of two unique tags unpinned ---
echo "--- Test (c): each uniquely tagged message must be pinned, not just one ---"
TREE="$TMP_ROOT/c"
mkdir -p "$TREE/k-plugin/hooks"
cat > "$TREE/k-plugin/hooks/ctx.sh" <<'EOF'
#!/usr/bin/env bash
block() { echo "$1" >&2; exit 2; }
case "$(cat)" in
  *kubectl*) block "KUBECTL SAFETY: Missing --context flag." ;;
  *helm*)
    block "HELM SAFETY: Missing --kube-context flag."
    ;;
esac
EOF
write_fixed_suite "$TREE/k-plugin/hooks"
OUT="$(run_guard "$TREE")"; RC=$?
expect "(c) verdict" "$OUT" "$RC" 1 STATUS=ERROR ISSUE_COUNT=1 BLOCK_MESSAGES=2 MESSAGES_CHECKED=2
has "$OUT" 'TAG="HELM SAFETY:"' && ! has "$OUT" 'TAG="KUBECTL SAFETY:"' && ! has "$OUT" output_never_captured \
  && pass "(c) flags only the unpinned HELM message; the pinned one and the capture pass" \
  || fail "(c) expected exactly the HELM SAFETY: finding: $OUT"

# --- (d) a tag mentioned only in comments is not a pin ---
echo "--- Test (d): a headline tag in a comment does not count ---"
TREE="$TMP_ROOT/d"
write_kubectl_hook "$TREE/k-plugin/hooks"
write_prefix_suite "$TREE/k-plugin/hooks"
cat >> "$TREE/k-plugin/hooks/test-ctx.sh" <<'EOF'
# TODO: assert "KUBECTL SAFETY: Missing --context flag."
    # indented comment: KUBECTL SAFETY: is the headline
out=$(printf '%s' '{}' | bash "$HOOK" 2>&1 || true)
EOF
OUT="$(run_guard "$TREE")"; RC=$?
expect "(d) verdict" "$OUT" "$RC" 1 STATUS=ERROR ISSUE_COUNT=1
has "$OUT" 'TYPE=message_unpinned' && ! has "$OUT" output_never_captured \
  && pass "(d) capture is seen, the commented-only tag is still unpinned" \
  || fail "(d) expected message_unpinned only: $OUT"

# --- (e) shared headline tags are reported unchecked, never claimed ---
echo "--- Test (e): messages sharing a tag are counted UNCHECKED, not passed as covered ---"
TREE="$TMP_ROOT/e"
mkdir -p "$TREE/s-plugin/hooks"
cat > "$TREE/s-plugin/hooks/style.sh" <<'EOF'
#!/usr/bin/env bash
block() { echo "$1" >&2; exit 2; }
IN=$(cat)
case "$IN" in *awk*) block "REMINDER: Use the Edit tool instead of 'awk'." ;; esac
case "$IN" in *sed*) block "REMINDER: Use the Edit tool instead of 'sed -i'." ;; esac
case "$IN" in *env*) block "$ENV_MSG" ;; esac
EOF
cat > "$TREE/s-plugin/hooks/test-style.sh" <<'EOF'
#!/usr/bin/env bash
HOOK="$(dirname "$0")/style.sh"
out=$(printf '%s' 'awk' | bash "$HOOK" 2>&1 >/dev/null || true)
grep -qF "Edit tool" <<<"$out"
EOF
OUT="$(run_guard "$TREE")"; RC=$?
expect "(e) verdict" "$OUT" "$RC" 0 STATUS=OK BLOCK_MESSAGES=3 MESSAGES_CHECKED=0 MESSAGES_UNCHECKED=3
has "$OUT" "SUITE=s-plugin/hooks/test-style.sh HOOK=s-plugin/hooks/style.sh MESSAGES=3 REASON=headline_tag_shared_or_absent" \
  && pass "(e) the unchecked messages are itemised per suite" \
  || fail "(e) expected an UNCHECKED row for test-style.sh: $OUT"

# --- (f) discarding redirects are not captures ---
echo "--- Test (f): >/dev/null 2>&1, &>/dev/null, 2>/dev/null, and an unread 2>&1 || true do not count ---"
TREE="$TMP_ROOT/f"
write_kubectl_hook "$TREE/k-plugin/hooks"
cat > "$TREE/k-plugin/hooks/test-ctx.sh" <<'EOF'
#!/usr/bin/env bash
HOOK="$(dirname "$0")/ctx.sh"
a=$(printf '%s' '{}' | bash "$HOOK" >/dev/null 2>&1; echo $?)
b=$(printf '%s' '{}' | bash "$HOOK" &>/dev/null; echo $?)
c=$(printf '%s' '{}' | bash "$HOOK" 2>/dev/null)
printf '%s' '{}' | bash "$HOOK" 2>&1 || true
echo "KUBECTL SAFETY:"
EOF
OUT="$(run_guard "$TREE")"; RC=$?
expect "(f) verdict" "$OUT" "$RC" 1 STATUS=ERROR ISSUE_COUNT=1
has "$OUT" "TYPE=output_never_captured" \
  && pass "(f) all four non-capturing forms read as no capture" \
  || fail "(f) expected output_never_captured: $OUT"

# --- (g) accepted capture spellings ---
echo "--- Test (g): \${HOOK} piped to grep, a continued \$() line, and 2> to a file all count ---"
g_case() { # $1 = label, $2 = capture line(s)
  local tree="$TMP_ROOT/g-$1" out rc
  write_kubectl_hook "$tree/k-plugin/hooks"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'HOOK="$(dirname "$0")/ctx.sh"'
    printf '%s\n' "$2"
    printf '%s\n' 'grep -qF "KUBECTL SAFETY: Missing --context flag." <<<"$out"'
  } > "$tree/k-plugin/hooks/test-ctx.sh"
  out="$(run_guard "$tree")"; rc=$?
  expect "(g) $1" "$out" "$rc" 0 STATUS=OK ISSUE_COUNT=0 BLOCKING_SUITES=1
}
g_case pipe 'if printf "%s" "$j" | bash "${HOOK}" 2>&1 | grep -qF x; then :; fi'
g_case continued "$(printf '%s\n' 'out=$(printf "%s" "$j" \' '    | bash "$HOOK" 2>&1 >/dev/null || true)')"
g_case errfile 'printf "%s" "$j" | bash "$HOOK" 2>"$ERR_FILE" >/dev/null || true; out=$(cat "$ERR_FILE")'

# --- (h) a hook that never calls block "…" is not in scope ---
echo "--- Test (h): non-blocking hook with an exit-only suite is not a member ---"
TREE="$TMP_ROOT/h"
mkdir -p "$TREE/j-plugin/hooks"
cat > "$TREE/j-plugin/hooks/deny.sh" <<'EOF'
#!/usr/bin/env bash
jq -n '{hookSpecificOutput:{permissionDecision:"deny",permissionDecisionReason:"no"}}'
EOF
cat > "$TREE/j-plugin/hooks/test-deny.sh" <<'EOF'
#!/usr/bin/env bash
HOOK="$(dirname "$0")/deny.sh"
bash "$HOOK" >/dev/null 2>&1
EOF
OUT="$(run_guard "$TREE")"; RC=$?
expect "(h) verdict" "$OUT" "$RC" 0 STATUS=OK SUITES_SCANNED=1 BLOCKING_SUITES=0 BLOCK_MESSAGES=0

# --- (i) a suite with no paired hook is counted, not failed ---
echo "--- Test (i): unpaired suite is counted SUITES_UNPAIRED ---"
TREE="$TMP_ROOT/i"
mkdir -p "$TREE/u-plugin/hooks"
printf '%s\n' '#!/usr/bin/env bash' 'true' > "$TREE/u-plugin/hooks/test-orphan.sh"
OUT="$(run_guard "$TREE")"; RC=$?
expect "(i) verdict" "$OUT" "$RC" 0 STATUS=OK SUITES_SCANNED=1 SUITES_UNPAIRED=1 BLOCKING_SUITES=0

# --- (j) nothing found is an ERROR, never OK ---
echo "--- Test (j): an empty tree fails loudly (#2219) ---"
TREE="$TMP_ROOT/j"
mkdir -p "$TREE/scripts"
OUT="$(run_guard "$TREE")"; RC=$?
expect "(j) verdict" "$OUT" "$RC" 1 STATUS=ERROR SUITES_SCANNED=0
has "$OUT" "TYPE=nothing_scanned" && pass "(j) reports nothing_scanned" || fail "(j) expected nothing_scanned: $OUT"

# --- (k) a worktree-shaped root still scans ---
echo "--- Test (k): a root that is itself an agent worktree is scanned (#2219) ---"
TREE="$TMP_ROOT/repo/.claude/worktrees/agent-f00dcafe"
write_kubectl_hook "$TREE/k-plugin/hooks"
write_prefix_suite "$TREE/k-plugin/hooks"
OUT="$(run_guard "$TREE")"; RC=$?
expect "(k) verdict" "$OUT" "$RC" 1 STATUS=ERROR SUITES_SCANNED=1 BLOCKING_SUITES=1 ISSUE_COUNT=2

# --- (l) argument handling ---
echo "--- Test (l): an unknown argument exits 1 ---"
bash "$GUARD" --no-such-flag >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && pass "(l) unknown argument exits 1" || fail "(l) expected exit 1, got $RC"

# --- (m) the real repository is clean and the scan is non-vacuous ---
echo "--- Test (m): the repository's own hook suites pass ---"
OUT="$(run_guard "$REPO_ROOT")"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(field "$OUT" STATUS)" = "OK" ] \
   && [ "$(field "$OUT" SUITES_SCANNED)" -gt 0 ] \
   && [ "$(field "$OUT" BLOCKING_SUITES)" -gt 0 ] \
   && [ "$(field "$OUT" MESSAGES_CHECKED)" -gt 0 ]; then
  pass "(m) repo: STATUS=OK with SUITES_SCANNED=$(field "$OUT" SUITES_SCANNED) BLOCKING_SUITES=$(field "$OUT" BLOCKING_SUITES) MESSAGES_CHECKED=$(field "$OUT" MESSAGES_CHECKED)"
else
  fail "(m) repo run should be OK and non-vacuous (rc=$RC)"
  printf '%s\n' "$OUT" | sed 's/^/    /'
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
