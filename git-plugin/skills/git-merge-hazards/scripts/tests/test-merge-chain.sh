#!/usr/bin/env bash
# test-merge-chain.sh — behaviour test for scripts/merge-chain.sh.
#
# Runs the real script against a stub `gh` on PATH that keeps per-PR state in
# JSON files, so every STATUS the script can emit is driven end to end:
# MERGED, SKIPPED (merged, closed, draft, stranger, release-please, Renovate),
# CONFLICT (update-branch and DIRTY), CI_RED (failed check, timeout, UNSTABLE),
# GUARD_LATE_COMMIT, DENIED (merge 403, BLOCKED) and the fail-closed ERROR.
#
# The §6 guard reads the commit list through `gh api graphql` (the parent count
# decides what a merge commit is), and the merge method comes from a stub
# standing in for pr-merge-method.py (MERGE_CHAIN_METHOD_CMD).
#
# Regressions pinned here:
#   - the merge is pinned with the FULL 40-character head SHA. GitHub rejects a
#     short one ("Could not coerce value to GitObjectID"); the stub does the
#     same, and a control proves the stub enforces it.
#   - a failed commit-list read stops the PR instead of reading as "no late
#     commits" (the first version of the §6 guard silently did nothing).
#   - a stopping status ends the chain: no later PR is updated or merged.
#   - a single-parent commit whose subject starts with "Merge" is not exempt
#     from the guard, and neither is a two-parent merge committed by anyone but
#     GitHub (noreply@github.com): a conflict agent's merge of main is new code.
#   - a head that moves after CI settled stops the PR (head_moved).
#   - an unevaluable check rollup is ERROR, not "no failed checks".
#   - CI is settled only after two agreeing reads, and an empty rollup only
#     after MC_MIN_EMPTY_POLLS reads; UNSTABLE is CI_RED; a draft is skipped.
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
    # _rollup_seq: the check rollup each successive checks read returns; the
    # last one sticks. Only reads that ask for statusCheckRollup consume it.
    fields=""; prev=""
    for a in "$@"; do [ "$prev" = "--json" ] && fields="$a"; prev="$a"; done
    if [[ "$fields" == *statusCheckRollup* ]] && [ "$(jq '(._rollup_seq // []) | length' "$(f "$n")")" -gt 0 ]; then
      save "$n" '.statusCheckRollup = ._rollup_seq[0] | ._rollup_seq = ._rollup_seq[1:]'
    fi
    jq 'with_entries(select(.key | startswith("_") | not))' "$(f "$n")"; exit 0 ;;
  "api graphql")
    n=""; for a in "$@"; do case "$a" in number=*) n="${a#number=}" ;; esac; done
    [ -f "$(f "$n")" ] || { echo "GraphQL: Could not resolve to a PullRequest" >&2; exit 1; }
    if [ "$(jq -r '._fail_commits_read // false' "$(f "$n")")" = true ]; then
      echo "HTTP 502: Bad Gateway" >&2; exit 1
    fi
    # _move_on_guard_read: a merge commit lands between CI settling and this read.
    if [ "$(jq -r '._move_on_guard_read // false' "$(f "$n")")" = true ]; then
      moved=$(printf 'b%039d' "$n")
      save "$n" "._move_on_guard_read = false | .headRefOid = \"$moved\"
        | .commits += [{oid: \"$moved\", committedDate: \"2026-10-27T09:10:00Z\", messageHeadline: \"Merge branch 'main' into \\(.headRefName)\", parents: 2, committer: \"noreply@github.com\"}]"
    fi
    jq '{data: {repository: {pullRequest: {headRefOid,
          commits: {totalCount: ((.commits | length) + (._extra_commits // 0)),
                    nodes: [.commits[] | {commit: {oid, committedDate, messageHeadline,
                      parents: (if .parents == "absent" then null else {totalCount: (.parents // 1)} end),
                      committer: (if .committer == "absent" then null else {email: (.committer // "me@example.com")} end)}}]}}}}}' "$(f "$n")"
    exit 0 ;;
  "pr update-branch")
    n="$3"; beh=$(jq -r '._update // "ok"' "$(f "$n")")
    case "$beh" in
      conflict) echo "X Cannot update PR branch due to conflicts" >&2; exit 1 ;;
      denied) echo "HTTP 403: Resource not accessible by integration" >&2; exit 1 ;;
      noop) echo "✓ PR branch already up to date"; exit 0 ;;
    esac
    new=$(printf 'a%039d' "$n")
    # _ms_seq: mergeStateStatus after each successive update, then _ms_after.
    save "$n" ".headRefOid = \"$new\"
      | .mergeStateStatus = (if (._ms_seq // []) | length > 0 then ._ms_seq[0] else (._ms_after // \"CLEAN\") end)
      | ._ms_seq = ((._ms_seq // [])[1:])
      | .commits += [{oid: \"$new\", committedDate: \"2026-10-27T09:00:00Z\", messageHeadline: \"Merge branch 'main' into \(.headRefName)\", parents: 2, committer: \"noreply@github.com\"}]"
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
      queued) exit 0 ;;   # accepted, but the PR stays OPEN (merge queue)
    esac
    save "$n" ".state = \"MERGED\" | .mergeCommit = {oid: \"$(printf 'e%039d' "$n")\"}"
    exit 0 ;;
esac
echo "stub gh: unhandled: $*" >&2
exit 64
STUB
chmod +x "$T/bin/gh"

# Stub for pr-merge-method.py: METHOD= from the PR's _method (default squash).
cat >"$T/bin/method-stub" <<'STUB'
#!/usr/bin/env bash
echo "STUB_METHOD $*" >>"$STUB_LOG"
n=""; prev=""
for a in "$@"; do [ "$prev" = "--pr" ] && n="$a"; prev="$a"; done
m=$(jq -r '._method // "squash"' "$STUB_STATE/pr-$n.json")
if [ "$m" = fail ]; then
  printf '%s\n' "=== PR MERGE METHOD ===" "STATUS=ERROR" "REASON=fetch_failed: gh api failed" "=== END PR MERGE METHOD ==="
  exit 1
fi
printf '%s\n' "=== PR MERGE METHOD ===" "METHOD=$m" "STATUS=OK" "=== END PR MERGE METHOD ==="
STUB
chmod +x "$T/bin/method-stub"

export PATH="$T/bin:$PATH"
export STUB_STATE="$T/state" STUB_LOG="$T/gh.log" STUB_SELF=me
export MERGE_CHAIN_POLL_SECONDS=0
export MERGE_CHAIN_METHOD_CMD="$T/bin/method-stub"

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

# The method comes from pr-merge-method.py, asked after update-branch (which
# adds the merge commit that rule 4 squashes); --method overrides it.
mkpr 105 '._method = "rebase"'
run_chain 105
expect_line "#105 merged" "$(section 105)" "STATUS=MERGED"
expect_has "the per-PR METHOD= is the merge flag" "$LOG" "^STUB_GH pr merge 105 -R o/r --rebase --delete-branch --match-head-commit a000000000000000000000000000000000000105$"
expect_line "method asked after update-branch, before the merge" \
  "$(grep -oE 'update-branch 105|STUB_METHOD --repo o/r --pr 105|pr merge 105' <<<"$LOG" | tr '\n' '|')" \
  "update-branch 105|STUB_METHOD --repo o/r --pr 105|pr merge 105|"
mkpr 106 '._method = "rebase"'
run_chain 106 --method merge
expect_has "--method overrides the per-PR method" "$LOG" "^STUB_GH pr merge 106 -R o/r --merge "
expect_no "--method skips pr-merge-method.py" "$LOG" "STUB_METHOD"
if [ -x "$SKILL_DIR/../../scripts/pr-merge-method.py" ]; then ok "default method command git-plugin/scripts/pr-merge-method.py exists and is executable"; else bad "git-plugin/scripts/pr-merge-method.py missing or not executable"; fi

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

mkpr 116 '.isDraft = true'
run_chain 116
expect_has "draft skipped" "$(section 116)" "^REASON=draft:"
expect_no "a draft is never updated or merged" "$LOG" "pr (update-branch|merge) 116"

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

# A skip before the stop: the summary REASON must name the stop, not the skip.
mkpr 204 '.author = {login: "stranger", is_bot: false}'
mkpr 205 '._update = "conflict"'
run_chain 204,205
expect_has "summary REASON names the stopping PR, not the earlier skip" "$(summary)" "^REASON=CONFLICT: #205 update_branch_conflict.* \\(\\+1 more\\)$"
expect_line "skip and stop both counted" "$(summary)" "ISSUE_COUNT=2"

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
expect_line "HEAD_SHA is the post-update head whose checks failed" "$(section 301)" "HEAD_SHA=a000000000000000000000000000000000000301"

mkpr 303 '.statusCheckRollup = [{__typename: "CheckRun", name: "slow", status: "IN_PROGRESS", conclusion: null}]'
run_chain 303 --timeout 0
expect_has "pending forever -> CI_RED ci_timeout" "$(section 303)" "^REASON=ci_timeout:"

mkpr 304 '.statusCheckRollup = [{__typename: "StatusContext", context: "ci/legacy", state: "ERROR"}]'
run_chain 304
expect_has "failed StatusContext -> CI_RED" "$(section 304)" "^REASON=check_failed: ci/legacy$"

mkpr 305 '.statusCheckRollup = ["not-a-check"]'
run_chain 305 --timeout 0
expect_line "unevaluable check rollup -> ERROR" "$(section 305)" "STATUS=ERROR"
expect_has "REASON says the checks could not be read" "$(section 305)" "^REASON=read_failed: could not evaluate"
# Only the failed-check read breaks here (join() cannot join an object), so the
# pending read says "nothing pending"; without a fallback the PR would merge.
mkpr 308 '.statusCheckRollup = [{__typename: "CheckRun", name: {bad: 1}, status: "COMPLETED", conclusion: "FAILURE"}]'
run_chain 308
expect_line "unevaluable failed-check read -> ERROR" "$(section 308)" "REASON=read_failed: could not evaluate failed status checks"
expect_no "no merge over an unread failed check" "$LOG" "pr merge"

mkpr 309 '._ms_after = "UNSTABLE"'
run_chain 309
expect_line "UNSTABLE -> CI_RED" "$(section 309)" "STATUS=CI_RED"
expect_has "REASON=unstable" "$(section 309)" "^REASON=unstable:"
expect_no "no merge over UNSTABLE" "$LOG" "pr merge"

# CI is settled only when two consecutive reads agree: here the first read is
# all green and the second shows a check that registered late and failed.
mkpr 310 '._rollup_seq = [[{__typename: "CheckRun", name: "test", status: "COMPLETED", conclusion: "SUCCESS"}],
                          [{__typename: "CheckRun", name: "test", status: "COMPLETED", conclusion: "SUCCESS"},
                           {__typename: "CheckRun", name: "late", status: "COMPLETED", conclusion: "FAILURE"}]]'
run_chain 310
expect_line "a check that appears on the second read -> CI_RED" "$(section 310)" "STATUS=CI_RED"
expect_has "REASON names the late check" "$(section 310)" "^REASON=check_failed: late$"
expect_no "no merge on one green read" "$LOG" "pr merge"

# Zero checks: wait MC_MIN_EMPTY_POLLS (3) reads before believing the repo has
# no CI, so a check that registers on the third read is still seen.
mkpr 311 '.statusCheckRollup = [] | ._rollup_seq = [[], [],
                          [{__typename: "CheckRun", name: "slow-start", status: "COMPLETED", conclusion: "FAILURE"}]]'
run_chain 311
expect_line "a check registering on read 3 after two empty reads -> CI_RED" "$(section 311)" "STATUS=CI_RED"
expect_no "no merge before the empty-poll wait ends" "$LOG" "pr merge"
mkpr 312 '.statusCheckRollup = []'
run_chain 312
expect_line "no checks at all merges after the wait" "$(section 312)" "STATUS=MERGED"
expect_line "four checks reads: three to trust the empty set, one to agree" \
  "$(grep -c 'pr view 312 .*statusCheckRollup' <<<"$LOG")" "4"

# BEHIND after CI settled: update again, at most MC_MAX_UPDATES (3) times.
mkpr 306 '._ms_seq = ["BEHIND"]'
run_chain 306
expect_line "BEHIND once, then CLEAN -> merged" "$(section 306)" "STATUS=MERGED"
expect_line "two update-branch calls" "$(grep -c 'pr update-branch 306' <<<"$LOG")" "2"
mkpr 307 '._ms_after = "BEHIND"'
run_chain 307
expect_line "always BEHIND -> CI_RED" "$(section 307)" "STATUS=CI_RED"
expect_line "REASON=still_behind after three updates" "$(section 307)" "REASON=still_behind: base moved during CI 3 times"
expect_line "exactly three update-branch calls" "$(grep -c 'pr update-branch 307' <<<"$LOG")" "3"
expect_no "no merge while still behind" "$LOG" "pr merge"

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

mkpr 403 '.commits += [{oid: "d2", committedDate: "2026-10-27T08:30:00Z", messageHeadline: "Merge the reviewed fix", parents: 1}]'
run_chain 403
expect_line "a single-parent 'Merge…' subject is not exempt" "$(section 403)" "STATUS=GUARD_LATE_COMMIT"
expect_has "REASON names it" "$(section 403)" "^REASON=late_commits: d2 Merge the reviewed fix$"

mkpr 404 '.commits += [{oid: "d3", committedDate: "2026-10-27T08:30:00Z", messageHeadline: "Merge branch main", parents: "absent"}]'
run_chain 404
expect_line "an unreadable parent count is not a merge commit" "$(section 404)" "STATUS=GUARD_LATE_COMMIT"

# A two-parent merge is exempt only when GitHub committed it (update-branch).
# A conflict agent that merges main into the branch commits it itself, and its
# resolution is unreviewed code.
mkpr 407 '.commits += [{oid: "d4", committedDate: "2026-10-27T08:30:00Z", messageHeadline: "Merge branch main into feat/x-407", parents: 2, committer: "agent@example.com"}]'
run_chain 407
expect_line "a late two-parent merge by another committer -> GUARD_LATE_COMMIT" "$(section 407)" "STATUS=GUARD_LATE_COMMIT"
expect_has "REASON names the agent's merge" "$(section 407)" "^REASON=late_commits: d4 Merge branch main into feat/x-407$"
expect_no "no merge over an agent's merge commit" "$LOG" "pr merge"
mkpr 408 '.commits += [{oid: "d5", committedDate: "2026-10-27T08:30:00Z", messageHeadline: "Merge branch main", parents: 2, committer: "absent"}]'
run_chain 408
expect_line "a two-parent merge with no readable committer is not exempt" "$(section 408)" "STATUS=GUARD_LATE_COMMIT"

mkpr 405 '._move_on_guard_read = true'
run_chain 405
expect_line "head moved after CI settled -> GUARD_LATE_COMMIT" "$(section 405)" "STATUS=GUARD_LATE_COMMIT"
expect_line "REASON=head_moved, naming both heads" "$(section 405)" "REASON=head_moved: head changed from a0000000 to b0000000 after CI settled"
expect_line "HEAD_SHA is the moved head" "$(section 405)" "HEAD_SHA=b000000000000000000000000000000000000405"
expect_no "no merge when the head moved" "$LOG" "pr merge"

mkpr 406 '._extra_commits = 1'
run_chain 406
expect_has "commits past the read window -> ERROR" "$(section 406)" "^REASON=commits_truncated:"
expect_no "no merge over unread commits" "$LOG" "pr merge"

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
expect_line "green but BLOCKED -> DENIED" "$(section 503)" "STATUS=DENIED"
expect_has "REASON names branch protection" "$(section 503)" "^REASON=blocked_by_protection:"

# ---- 7. fail closed ---------------------------------------------------------
echo "fail closed"
mkpr 601 '._fail_commits_read = true'
run_chain 601
expect_line "unreadable commit list -> ERROR, not clean" "$(section 601)" "STATUS=ERROR"
expect_no "no merge after a failed guard read" "$LOG" "pr merge"

mkpr 603 '._merge = "queued"'
run_chain 603
expect_line "merge exits 0 but the PR stays OPEN -> ERROR" "$(section 603)" "STATUS=ERROR"
expect_has "REASON=not_merged_after_merge" "$(section 603)" "^REASON=not_merged_after_merge:"

mkpr 604 '._method = "fail"'
run_chain 604
expect_line "unresolvable merge method -> ERROR" "$(section 604)" "STATUS=ERROR"
expect_line "REASON carries the method script's reason" "$(section 604)" "REASON=method_unresolved: fetch_failed: gh api failed"
expect_no "no merge without a method" "$LOG" "pr merge"

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
OUT=$(MERGE_CHAIN_METHOD_CMD="$T/no-such-method-cmd" bash "$CHAIN" --repo o/r --prs 1 --review-ts "$TS" 2>&1); RC=$?
expect_line "no --method and no method command exits 2" "$RC" "2"

# ---- 9. the skill points at the script --------------------------------------
echo "skill"
if grep -q 'scripts/merge-chain.sh' "$SKILL_DIR/SKILL.md"; then ok "SKILL.md names scripts/merge-chain.sh"; else bad "SKILL.md does not name scripts/merge-chain.sh"; fi
# external-pr-trust forbids helpers that hide a PR number from the merge guard;
# it must say why this script is not one, or the two skills contradict.
TRUST="$SKILL_DIR/../external-pr-trust/SKILL.md"
if grep -q 'scripts/merge-chain.sh' "$TRUST"; then ok "external-pr-trust explains merge-chain.sh"; else bad "external-pr-trust does not name scripts/merge-chain.sh"; fi
# The guard, not this script, is the authority: the hook must recognise the script.
GUARD="$SKILL_DIR/../../../hooks-plugin/hooks/external-pr-merge-guard.sh"
if [ ! -f "$GUARD" ] || grep -q 'merge-chain' "$GUARD"; then ok "external-pr-merge-guard recognises merge-chain.sh (or is absent in this tree)"; else bad "external-pr-merge-guard does not recognise merge-chain.sh"; fi

# ---- 10. the docs state the script's exemption (#3254) ----------------------
# The docs once exempted any commit whose subject starts with "Merge" and told
# readers to refuse "any non-merge commit". The script exempts only a commit
# with 2+ parents AND committer noreply@github.com, so a conflict agent's own
# merge of main is refused. Run the hand-run snippet itself, not a grep of it.
echo "docs"
SMC="$SKILL_DIR/references/serial-merge-chain.md"
stale=$(grep -rlE 'startswith\("Merge"\)|any non-merge commit|a non-merge commit after review' \
  "$SKILL_DIR/SKILL.md" "$SKILL_DIR/references" 2>/dev/null)
if [ -z "$stale" ]; then ok "no doc restates the subject-'Merge' / non-merge exemption"; else bad "stale exemption wording in: $stale"; fi
mkdir -p "$T/snip/bin"
awk '/^## The guard/{g=1} g&&/^```bash/{f=1;next} f&&/^```/{exit} f' "$SMC" |
  sed 's/^START=.*/START=2026-10-27T08:00:00Z/' >"$T/snip/guard.sh"
if bash -n "$T/snip/guard.sh" 2>/dev/null && [ -s "$T/snip/guard.sh" ]; then ok "the serial-merge-chain.md guard snippet parses"; else bad "the serial-merge-chain.md guard snippet is missing or does not parse"; fi
cat >"$T/snip/bin/gh" <<'SNIPSTUB'
#!/usr/bin/env bash
if [ "$1 $2" = "api graphql" ]; then cat "$SNIP_JSON"; exit 0; fi
echo "MERGED_BY_SNIPPET"
SNIPSTUB
chmod +x "$T/snip/bin/gh"
snip_run() { # snip_run <parents> <committer email>: one commit after START
  printf '{"data":{"repository":{"pullRequest":{"headRefOid":"%s","commits":{"totalCount":1,"nodes":[{"commit":{"oid":"d5d5d5d5d5","committedDate":"2026-10-27T09:00:00Z","messageHeadline":"Merge branch main into feat/x","parents":{"totalCount":%s},"committer":{"email":"%s"}}}]}}}}}' \
    "$(printf 'a%.0s' $(seq 40))" "$1" "$2" >"$T/snip/pr.json"
  PATH="$T/snip/bin:$PATH" SNIP_JSON="$T/snip/pr.json" owner=o name=r n=9 \
    bash "$T/snip/guard.sh" 2>&1 | tail -n 1
}
expect_line "snippet: GitHub's update-branch merge is exempt" "$(snip_run 2 noreply@github.com)" "MERGED_BY_SNIPPET"
expect_has "snippet: an agent's own merge of main is refused" "$(snip_run 2 agent@example.com)" "^STOP #9: unverified commits: d5d5d5d5 Merge branch main"
expect_has "snippet: a single-parent 'Merge …' commit is refused" "$(snip_run 1 noreply@github.com)" "^STOP #9: unverified commits:"

echo
echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
