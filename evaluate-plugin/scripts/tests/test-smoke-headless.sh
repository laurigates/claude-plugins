#!/usr/bin/env bash
# Offline regression test for tests/live/smoke-headless.sh, the EVAL_LIVE=1
# smoke. It drives the REAL smoke end to end (apply_fixture.sh ->
# rollout_headless.sh -> parse_trace.py -> grade_deterministic.py, and
# run_trigger_evals.py) with fixtures/fake-claude.sh first on PATH as `claude`,
# so no call here reaches the network or spends money.
#
# What this pins:
#   (a) without EVAL_LIVE=1 the smoke is a no-op: SKIPPED=true, STATUS=OK, exit 0
#   (b) routing is REPORTED, not asserted: a with-skill rollout that never
#       invokes git-plugin:git-commit (haiku's live behaviour at n=1 on
#       2026-10-05) and a trigger run with recall 0 give STATUS=WARN, exit 0,
#       WITH_SKILL_ROUTED=false, FAILED=0 and a REASON naming `unrouted`
#   (c) the baseline invariant stays an ASSERTION: a baseline rollout that
#       invokes git-commit is STATUS=ERROR, exit 1 (the paired true positive)
#   (d) every key is a valid uppercase KEY (no `WITH-SKILL_*` from ${config^^}),
#       and the block passes check-structured-output-contract.sh --validate
#   (e) the smoke never writes git-commit's checked-out
#       eval-results/triggers.json: it passes --no-copy to run_trigger_evals.py,
#       so these fake-claude runs cannot overwrite a genuine trigger result
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
fixtures="$script_dir/fixtures"
smoke="$script_dir/live/smoke-headless.sh"
fake="$fixtures/fake-claude.sh"
repo_root="$(cd "$script_dir/../../.." && pwd -P)"
contract="$repo_root/scripts/check-structured-output-contract.sh"

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

field() {
  # field <output> <KEY>  -> prints the value after KEY= (first match)
  printf '%s\n' "$1" | grep -m1 "^$2=" | cut -d= -f2-
}

for tool in jq python3 git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not on PATH"; exit 0; }
done

# Neutralise inherited git context (#1745): apply_fixture.sh runs git in a
# mktemp workdir, and a leaked GIT_DIR must not redirect it at this checkout.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX
unset EVAL_ALLOW_UNCAPPED EVAL_PARSE_TRACE ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN

sandbox="$(mktemp -d)"
[ -n "$sandbox" ] || { echo "FAIL: mktemp -d returned empty" >&2; exit 1; }
[ -d "$sandbox" ] || { echo "FAIL: mktemp -d dir missing" >&2; exit 1; }
trap 'rm -rf "$sandbox"' EXIT
sandbox="$(cd "$sandbox" && pwd -P)"
case "$sandbox" in
  "$repo_root"/*) echo "SKIP: TMPDIR is inside the repo; the smoke refuses that"; exit 0 ;;
esac

bin="$sandbox/bin"
mkdir -p "$bin"

# (e) fingerprint the real skill's trigger-result copy before any smoke run.
real_copy="$repo_root/git-plugin/skills/git-commit/eval-results/triggers.json"
fingerprint() {
  if [ -e "$real_copy" ]; then
    { cksum <"$real_copy"; stat -c '%Y' "$real_copy" 2>/dev/null || stat -f '%m' "$real_copy"; } | tr '\n' ' '
  else
    echo absent
  fi
}
copy_before="$(fingerprint)"
export CLAUDE_CODE_SESSION_ID="parent-session-smoke-0000"

# make_claude KEY=VAL...  -> (re)write the `claude` wrapper with baked env.
make_claude() {
  {
    echo '#!/usr/bin/env bash'
    for kv in "$@"; do printf 'export %q\n' "$kv"; done
    printf 'exec bash %q "$@"\n' "$fake"
  } >"$bin/claude"
  chmod +x "$bin/claude"
}

run_smoke() {  # run_smoke [ENV=VAL...] -> sets out, rc
  out="$(env "$@" TMPDIR="$sandbox" PATH="$bin:$PATH" bash "$smoke" 2>"$sandbox/stderr.txt")"
  rc=$?
}

# A stream that answers without ever calling Skill: init, one text turn, result
# (the shape of haiku's live gc-007 run, which committed directly).
unrouted="$sandbox/stream-unrouted.jsonl"
jq -c 'select((.type == "system" and .subtype == "init")
              or (.type == "assistant" and .message.id == "msg_c07")
              or .type == "result")' "$fixtures/stream-skill-commit.jsonl" >"$unrouted"
check "unrouted fixture has no Skill call" "0" \
  "$(jq -s '[.[] | select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Skill")] | length' "$unrouted")"

# ---- (a) not live: a no-op ---------------------------------------------------
make_claude "FAKE_CLAUDE_FIXTURE=$unrouted"
run_smoke -u EVAL_LIVE
check "(a) no EVAL_LIVE: exit 0" "0" "$rc"
check "(a) no EVAL_LIVE: SKIPPED" "true" "$(field "$out" SKIPPED)"
check "(a) no EVAL_LIVE: STATUS=OK" "OK" "$(field "$out" STATUS)"

# ---- (b) unrouted with-skill + recall 0 triggers -> WARN, not a failure -----
make_claude "FAKE_CLAUDE_FIXTURE=$unrouted"
run_smoke EVAL_LIVE=1
check "(b) unrouted: exit 0" "0" "$rc"
check "(b) unrouted: STATUS=WARN" "WARN" "$(field "$out" STATUS)"
check "(b) unrouted: FAILED=0" "0" "$(field "$out" FAILED)"
check "(b) unrouted: WITH_SKILL_ROUTED=false" "false" "$(field "$out" WITH_SKILL_ROUTED)"
check "(b) unrouted: BASELINE_ROUTED=false" "false" "$(field "$out" BASELINE_ROUTED)"
check "(b) unrouted: trigger runner WARNed" "WARN" "$(field "$out" TRIGGERS_STATUS)"
check "(b) unrouted: REASON names unrouted first" "yes" \
  "$(field "$out" REASON | grep -q '^unrouted: ' && echo yes || echo no)"
check "(b) unrouted: two WARN issues" "2" "$(field "$out" WARNED)"
check "(b) unrouted: trigger_threshold issue listed" "yes" \
  "$(grep -q '^  - SEVERITY=WARN TYPE=trigger_threshold ' <<<"$out" && echo yes || echo no)"
check "(b) unrouted: plumbing still graded (HARNESS_DEFERRED=0 asserted)" "yes" \
  "$( [ "$(field "$out" PASSED)" -gt 0 ] 2>/dev/null && echo yes || echo no)"
if [ "$rc" -ne 0 ]; then
  echo "--- smoke stderr (b) ---" >&2; cat "$sandbox/stderr.txt" >&2
fi

# ---- (d) key shape + structured-output contract -----------------------------
check "(d) no hyphenated keys" "0" \
  "$(printf '%s\n' "$out" | grep -cE '^[A-Za-z]+-[A-Za-z_-]*=' || true)"
check "(d) WITH_SKILL_* keys present" "yes" \
  "$(grep -q '^WITH_SKILL_STATUS=' <<<"$out" && echo yes || echo no)"
if [ -f "$contract" ]; then
  block="$(printf '%s\n' "$out" | sed -n '/^=== LIVE HEADLESS SMOKE ===$/,/^=== END LIVE HEADLESS SMOKE ===$/p')"
  printf '%s\n' "$block" | bash "$contract" --validate - >"$sandbox/contract.txt" 2>&1
  check "(d) WARN block passes the structured-output contract" "0" "$?"
fi

# ---- (c) baseline that invokes git-commit -> ERROR (assertion kept) ---------
make_claude "FAKE_CLAUDE_FIXTURE=$fixtures/stream-skill-commit.jsonl"
run_smoke EVAL_LIVE=1
check "(c) routed baseline: exit 1" "1" "$rc"
check "(c) routed baseline: STATUS=ERROR" "ERROR" "$(field "$out" STATUS)"
check "(c) routed baseline: WITH_SKILL_ROUTED=true" "true" "$(field "$out" WITH_SKILL_ROUTED)"
check "(c) routed baseline: baseline assertion failed" "yes" \
  "$(grep -q '^  - SEVERITY=ERROR TYPE=assertion MSG=baseline: git-commit cannot be invoked' <<<"$out" && echo yes || echo no)"
check "(c) routed baseline: no unrouted WARN" "no" \
  "$(grep -q 'TYPE=unrouted' <<<"$out" && echo yes || echo no)"
if [ -f "$contract" ]; then
  block="$(printf '%s\n' "$out" | sed -n '/^=== LIVE HEADLESS SMOKE ===$/,/^=== END LIVE HEADLESS SMOKE ===$/p')"
  printf '%s\n' "$block" | bash "$contract" --validate - >"$sandbox/contract.txt" 2>&1
  check "(d) ERROR block passes the structured-output contract" "0" "$?"
fi

# ---- (e) the checkout's eval-results copy was never touched -----------------
check "(e) smoke passed --no-copy to the trigger runner" "none" "$(field "$out" TRIGGERS_COPY)"
check "(e) git-commit eval-results/triggers.json untouched" "$copy_before" "$(fingerprint)"

echo ""
echo "=== SUMMARY ==="
echo "PASSED=$pass_count"
echo "FAILED=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  echo "STATUS=FAIL"
  exit 1
fi
echo "STATUS=OK"
