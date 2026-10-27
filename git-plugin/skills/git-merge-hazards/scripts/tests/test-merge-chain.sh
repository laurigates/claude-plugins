#!/usr/bin/env bash
# test-merge-chain.sh — behaviour test for scripts/merge-chain.sh.
#
# Runs the real script against a stub `gh` on PATH that keeps per-PR state in
# JSON files, so every STATUS the script can emit is driven end to end:
# MERGED, SKIPPED (merged, closed, stranger, release-please, Renovate),
# CONFLICT (update-branch and DIRTY), CI_RED (failed check, timeout),
# GUARD_LATE_COMMIT, DENIED (merge 403, BLOCKED) and the fail-closed ERROR.
#
# Regressions pinned here:
#   - the merge is pinned with the FULL 40-character head SHA. GitHub rejects a
#     short one ("Could not coerce value to GitObjectID"); the stub does the
#     same, and a control proves the stub enforces it.
#   - a failed commit-list read stops the PR instead of reading as "no late
#     commits" (the first version of the §6 guard silently did nothing).
#   - a stopping status ends the chain: no later PR is updated or merged.
#
# Needs bash and jq.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN="${SCRIPT_DIR}/../merge-chain.sh"
SKILL_DIR="${SCRIPT_DIR}/../.."
REPO_ROOT="$(cd "${SKILL_DIR}/../../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/check-structured-output-contract.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed"
  exit 0
fi

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "  ok  $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
expect_line() { # expect_line <desc> <output> <exact line>
  if grep -qxF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing line: $3)" "$2"; fi
}
expect_no() { # expect_no <desc> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then bad "$1 (unexpected match: $3)" "$2"; else ok "$1"; fi
}
expect_has() { # expect_has <desc> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (no match: $3)" "$2"; fi
}

T=$(mktemp -d) || { echo "mktemp failed" >&2; exit 1; }
if [ -z "$T" ] || [ ! -d "$T" ]; then echo "bad temp dir" >&2; exit 1; fi
T=$(cd -P -- "$T" && pwd -P) || { echo "cannot resolve" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/state"

# ---- stub gh ----------------------------------------------------------------
cat >"$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh for test-merge-chain.sh. State: $STUB_STATE/pr-<n>.json.
echo "STUB_GH $*" >>"$STUB_LOG"
f() { echo "$STUB_STATE/pr-$1.json"; }
save() { local tmp; tmp=$(mktemp); jq "$2" "$(f "$1")" >"$tmp" && mv "$tmp" "$(f "$1")"; }
case "$1 $2" in
  "api user")
    [ -n "${STUB_SELF_FAIL:-}" ] && { echo "HTTP 401: Bad credentials" >&2; exit 1; }
    echo "${STUB_SELF:-me}"; exit 0 ;;
  "pr view")
    n="$3"; [ -f "$(f "$n")" ] || { echo "no pull requests found" >&2; exit 1; }
    if [[ " $* " == *commits* ]] && [ "$(jq -r '._fail_commits_read // false' "$(f "$n")")" = true ]; then
      echo "HTTP 502: Bad Gateway" >&2; exit 1
    fi
    jq 'with_entries(select(.key | startswith("_") | not))' "$(f "$n")"; exit 0 ;;
  "pr update-branch")
    n="$3"; beh=$(jq -r '._update // "ok"' "$(f "$n")")
    case "$beh" in
      conflict) echo "X Cannot update PR branch due to conflicts" >&2; exit 1 ;;
      denied) echo "HTTP 403: Resource not accessible by integration" >&2; exit 1 ;;
      noop) echo "✓ PR branch already up to date"; exit 0 ;;
    esac
    new=$(printf 'a%039d' "$n")
    save "$n" ".headRefOid = \"$new\"
      | .mergeStateStatus = (._ms_after // \"CLEAN\")
      | .commits += [{oid: \"$new\", committedDate: \"2026-10-27T09:00:00Z\", messageHeadline: \"Merge branch 'main' into \(.headRefName)\"}]"
    if [ "$(jq -r '._late // false' "$(f "$n")")" = true ]; then
      late=$(printf 'c%039d' "$n")
      save "$n" ".headRefOid = \"$late\"
        | .commits += [{oid: \"$late\", committedDate: \"2026-10-27T09:05:00Z\", messageHeadline: \"style: bot auto-fix\"}]"
    fi
    echo "✓ PR branch updated"; exit 0 ;;
  "pr merge")
    n="$3"; sha=""; prev=""
    for a in "$@"; do [ "$prev" = "--match-head-commit" ] && sha="$a"; prev="$a"; done
    if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      echo "GraphQL: Could not coerce value \"$sha\" to GitObjectID (mergePullRequest.input.expectedHeadOid)" >&2; exit 1
    fi
    if [ "$sha" != "$(jq -r .headRefOid "$(f "$n")")" ]; then
      echo "Head branch was modified. Review and try the merge again." >&2; exit 1
    fi
    case "$(jq -r '._merge // "ok"' "$(f "$n")")" in
      denied) echo "HTTP 403: Resource not accessible by integration" >&2; exit 1 ;;
    esac
    save "$n" ".state = \"MERGED\" | .mergeCommit = {oid: \"$(printf 'e%039d' "$n")\"}"
    exit 0 ;;
esac
echo "stub gh: unhandled: $*" >&2
exit 64
STUB
chmod +x "$T/bin/gh"

export PATH="$T/bin:$PATH"
export STUB_STATE="$T/state" STUB_LOG="$T/gh.log" STUB_SELF=me
export MERGE_CHAIN_POLL_SECONDS=0

# mkpr <n> [jq-overrides]
mkpr() {
  jq -n --argjson n "$1" --arg oid "$(printf 'f%039d' "$1")" '{
      number: $n, state: "OPEN", isDraft: false,
      author: {login: "me", is_bot: false},
      headRefName: "feat/x-\($n)", headRefOid: $oid,
      mergeStateStatus: "BEHIND",
      statusCheckRollup: [{__typename: "CheckRun", name: "test", status: "COMPLETED", conclusion: "SUCCESS"}],
      commits: [{oid: "f0", committedDate: "2026-10-27T06:00:00Z", messageHeadline: "feat: work"}],
      mergeCommit: null
    }' | jq "${2:-.}" >"$STUB_STATE/pr-$1.json"
}

TS=2026-10-27T08:00:00Z
run_chain() { # run_chain <prs> [extra args]; sets OUT, RC
  : >"$STUB_LOG"
  local prs="$1"; shift
  OUT=$(bash "$CHAIN" --repo o/r --prs "$prs" --review-ts "$TS" "$@" 2>&1); RC=$?
  LOG=$(cat "$STUB_LOG")
}
summary() { sed -n '/^=== MERGE CHAIN ===$/,/^=== END MERGE CHAIN ===$/p' <<<"$OUT"; }
section() { sed -n "/^=== PR $1 ===\$/,/^=== END PR $1 ===\$/p" <<<"$OUT"; }
validate_summary() { # validate_summary <desc>
  [ -f "$VALIDATOR" ] || { ok "$1 (validator absent, skipped)"; return; }
  local v
  if v=$(summary | bash "$VALIDATOR" --validate - 2>&1); then ok "$1"; else bad "$1" "$v"; fi
}

# ---- 0. the stub is the gh in use, and it enforces the full-SHA rule --------
echo "stub"
if [ "$(command -v gh)" = "$T/bin/gh" ] && [ -x "$T/bin/gh" ]; then ok "gh resolves to the executable stub"; else bad "gh resolves to $(command -v gh)"; fi
mkpr 900 '.mergeStateStatus = "CLEAN"'
ctl=$(gh pr merge 900 -R o/r --squash --match-head-commit f0000000 2>&1); ctl_rc=$?
if [ "$ctl_rc" -ne 0 ] && grep -q 'Could not coerce value' <<<"$ctl"; then ok "control: stub rejects a short SHA like GitHub"; else bad "control: stub accepted a short SHA" "$ctl"; fi

# ---- 1. happy chain: self PR, bot PR, already-merged PR --------------------
echo "MERGED / SKIPPED chain"
mkpr 101
mkpr 102 '.author = {login: "app/some-bot", is_bot: true}'
mkpr 103 '.state = "MERGED"'
run_chain 101,102,103 --fetch-dir "$T/no-such-clone"
expect_line "exit 0 when nothing stopped" "$RC" "0"
expect_line "#101 merged" "$(section 101)" "STATUS=MERGED"
expect_line "#101 reports its merge commit" "$(section 101)" "MERGE_COMMIT=e000000000000000000000000000000000000101"
expect_line "#102 (bot author) merged" "$(section 102)" "STATUS=MERGED"
expect_line "#103 already merged is skipped" "$(section 103)" "STATUS=SKIPPED"
expect_has "merge pinned to the FULL 40-char updated head" "$LOG" "^STUB_GH pr merge 101 -R o/r --squash --delete-branch --match-head-commit a000000000000000000000000000000000000101$"
expect_no "no merge call for the already-merged PR" "$LOG" "pr merge 103"
expect_line "summary STATUS=WARN for a skip" "$(summary)" "STATUS=WARN"
expect_line "summary MERGED list" "$(summary)" "MERGED=101,102"
expect_line "nothing remains" "$(summary)" "REMAINING="
expect_line "a failed fetch is reported, not fatal" "$(section 101)" "FETCH=failed"
validate_summary "WARN summary passes the structured-output validator"

mkpr 104
run_chain 104
expect_line "single clean PR: STATUS=OK" "$(summary)" "STATUS=OK"
expect_no "OK summary has no REASON" "$(summary)" "^REASON="
validate_summary "OK summary passes the structured-output validator"

# ---- 2. SKIPPED: stranger, release-please, Renovate, closed ----------------
echo "SKIPPED"
mkpr 111 '.author = {login: "stranger", is_bot: false}'
mkpr 112 '.author = {login: "app/example-release-please", is_bot: true} | .headRefName = "release-please--branches--main"'
mkpr 113 '.author = {login: "app/renovate", is_bot: true} | .headRefName = "renovate/foo-1.x"'
mkpr 114 '.state = "CLOSED"'
mkpr 115
run_chain 111,112,113,114,115
expect_has "stranger skipped as non_self_author" "$(section 111)" "^REASON=non_self_author: author 'stranger'"
expect_has "release-please skipped" "$(section 112)" "^REASON=release_please:"
expect_has "renovate skipped" "$(section 113)" "^REASON=renovate:"
expect_has "closed skipped" "$(section 114)" "^REASON=closed:"
expect_no "a skipped PR is never updated or merged" "$LOG" "pr (update-branch|merge) 11[1-4] "
expect_line "the chain continues past skips" "$(section 115)" "STATUS=MERGED"
expect_line "summary lists skips" "$(summary)" "SKIPPED=111,112,113,114"
expect_line "four skip rows" "$(summary)" "ISSUE_COUNT=4"
validate_summary "multi-skip summary passes the validator"

# ---- 3. CONFLICT ------------------------------------------------------------
echo "CONFLICT"
mkpr 201 '._update = "conflict"'
mkpr 202
run_chain 201,202
expect_line "update-branch conflict -> CONFLICT" "$(section 201)" "STATUS=CONFLICT"
expect_line "exit 1 when the chain stops" "$RC" "1"
expect_no "the next PR is not touched" "$LOG" "202"
expect_line "REMAINING starts at the stopped PR" "$(summary)" "REMAINING=201,202"
expect_line "STOPPED_AT names it" "$(summary)" "STOPPED_AT=201"
expect_has "summary REASON names the conflict" "$(summary)" "^REASON=CONFLICT: #201 update_branch_conflict"
validate_summary "ERROR summary passes the validator"

mkpr 203 '._update = "noop" | .mergeStateStatus = "DIRTY"'
run_chain 203
expect_has "DIRTY mergeStateStatus -> CONFLICT" "$(section 203)" "^STATUS=CONFLICT$"
expect_no "no merge on DIRTY" "$LOG" "pr merge"

# ---- 4. CI_RED --------------------------------------------------------------
echo "CI_RED"
mkpr 301 '.statusCheckRollup = [{__typename: "CheckRun", name: "lint", status: "COMPLETED", conclusion: "FAILURE"},
                                {__typename: "StatusContext", context: "ci/legacy", state: "SUCCESS"}]'
mkpr 302
run_chain 301,302
expect_line "failed check -> CI_RED" "$(section 301)" "STATUS=CI_RED"
expect_has "REASON names the failed check" "$(section 301)" "^REASON=check_failed: lint$"
expect_no "no merge, next PR untouched" "$LOG" "pr merge|302"

mkpr 303 '.statusCheckRollup = [{__typename: "CheckRun", name: "slow", status: "IN_PROGRESS", conclusion: null}]'
run_chain 303 --timeout 0
expect_has "pending forever -> CI_RED ci_timeout" "$(section 303)" "^REASON=ci_timeout:"

mkpr 304 '.statusCheckRollup = [{__typename: "StatusContext", context: "ci/legacy", state: "ERROR"}]'
run_chain 304
expect_has "failed StatusContext -> CI_RED" "$(section 304)" "^REASON=check_failed: ci/legacy$"

# ---- 5. GUARD_LATE_COMMIT ---------------------------------------------------
echo "GUARD_LATE_COMMIT"
mkpr 401 '._late = true'
run_chain 401
expect_line "bot commit after review -> GUARD_LATE_COMMIT" "$(section 401)" "STATUS=GUARD_LATE_COMMIT"
expect_has "REASON names the late commit" "$(section 401)" "^REASON=late_commits: c0000000 style: bot auto-fix$"
expect_no "no merge when the guard fires" "$LOG" "pr merge"

mkpr 402 '.commits += [{oid: "d1", committedDate: "2026-10-27T07:59:59Z", messageHeadline: "fix: reviewed"}]'
run_chain 402
expect_line "a commit before the review timestamp merges" "$(section 402)" "STATUS=MERGED"

# ---- 6. DENIED --------------------------------------------------------------
echo "DENIED"
mkpr 501 '._merge = "denied"'
mkpr 502
run_chain 501,502
expect_line "merge 403 -> DENIED" "$(section 501)" "STATUS=DENIED"
expect_line "exactly one merge attempt, no retry" "$(grep -c 'pr merge 501' <<<"$LOG")" "1"
expect_no "no --admin route" "$LOG" "--admin"
expect_line "chain stops at the denial" "$(summary)" "REMAINING=501,502"

mkpr 503 '._ms_after = "BLOCKED"'
run_chain 503
expect_has "green but BLOCKED -> DENIED" "$(section 503)" "^REASON=blocked_by_protection:"

# ---- 7. fail closed ---------------------------------------------------------
echo "fail closed"
mkpr 601 '._fail_commits_read = true'
run_chain 601
expect_line "unreadable commit list -> ERROR, not clean" "$(section 601)" "STATUS=ERROR"
expect_no "no merge after a failed guard read" "$LOG" "pr merge"

mkpr 602
export STUB_SELF_FAIL=1
run_chain 602
unset STUB_SELF_FAIL
expect_has "unknown self -> ERROR before any PR" "$(summary)" "^REASON=ERROR: #602 self_unknown"
expect_no "no PR touched without a self login" "$LOG" "pr (view|update-branch|merge)"

# ---- 8. usage ---------------------------------------------------------------
echo "usage"
: >"$STUB_LOG"
OUT=$(bash "$CHAIN" --repo o/r --prs 1 2>&1); RC=$?
expect_line "missing --review-ts exits 2" "$RC" "2"
OUT=$(bash "$CHAIN" --repo o/r --prs 1 --review-ts 2026-10-27 2>&1); RC=$?
expect_line "date-only --review-ts exits 2" "$RC" "2"
OUT=$(bash "$CHAIN" --repo o/r --prs 1 --review-ts 2>&1); RC=$?
expect_line "flag without a value exits 2" "$RC" "2"
OUT=$(bash "$CHAIN" --repo o/r --prs '#1,x' --review-ts "$TS" 2>&1); RC=$?
expect_line "non-numeric PR exits 2" "$RC" "2"

# ---- 9. the skill points at the script --------------------------------------
echo "skill"
if grep -q 'scripts/merge-chain.sh' "$SKILL_DIR/SKILL.md"; then ok "SKILL.md names scripts/merge-chain.sh"; else bad "SKILL.md does not name scripts/merge-chain.sh"; fi

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
