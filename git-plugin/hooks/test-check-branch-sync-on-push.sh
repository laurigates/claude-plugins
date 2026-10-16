#!/usr/bin/env bash
# shellcheck disable=SC2016  # fixtures are the LITERAL, unexpanded command text a hook receives
# Regression tests for check-branch-sync-on-push.sh
#
# Run: bash git-plugin/hooks/test-check-branch-sync-on-push.sh
# Exit 0 = all tests pass, Exit 1 = failures
#
# The hook always exits 0 and signals a nudge by emitting a PreToolUse
# permissionDecision:"ask" JSON envelope on stdout. Tests assert on that
# stdout (decision + presence/absence) rather than exit codes. gh is mocked.
set -uo pipefail

# Neutralize any inherited git context before building sandbox repos (issues #1745, #3080).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_COMMON_DIR GIT_NAMESPACE GIT_PREFIX

HOOK="$(dirname "$0")/check-branch-sync-on-push.sh"
PASS=0
FAIL=0

TMPDIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
MOCK_BIN=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TMPDIR" "$MOCK_BIN"' EXIT

# ── Repo with a feature branch tracking origin ────────────────────────────────
git -C "$TMPDIR" init -q
git -C "$TMPDIR" config commit.gpgsign false
git -C "$TMPDIR" config user.email "test@test.com"
git -C "$TMPDIR" config user.name "Test"
git -C "$TMPDIR" commit --allow-empty -m "initial" -q
git -C "$TMPDIR" branch -m main 2>/dev/null || git -C "$TMPDIR" checkout -b main -q
git -C "$TMPDIR" checkout -b feature -q
git -C "$TMPDIR" commit --allow-empty -m "feat: work" -q

# Stand up origin as a clone so origin/feature is a real remote-tracking ref.
ORIGIN="$TMPDIR/origin.git"
git -C "$TMPDIR" remote add origin "$ORIGIN" 2>/dev/null || true
git init -q --bare "$ORIGIN"
git -C "$TMPDIR" push -q origin main feature 2>/dev/null || true
git -C "$TMPDIR" fetch -q origin 2>/dev/null || true

# Mock gh: `gh pr view ...` prints $MOCK_PR_JSON.
cat >"$MOCK_BIN/gh" <<'MOCK_EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
    [ -n "${MOCK_PR_JSON:-}" ] && printf '%s' "$MOCK_PR_JSON"
    exit 0
fi
exit 0
MOCK_EOF
chmod +x "$MOCK_BIN/gh"

make_json() {
    local cmd="$1" cwd="${2:-$TMPDIR}"
    jq -n --arg cmd "$cmd" --arg cwd "$cwd" --arg sid "test-$RANDOM-$RANDOM" \
        '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd,"session_id":$sid}'
}

# Run the hook and capture stdout. MOCK_PR_JSON / PATH must be exported onto the
# hook process (the gh mock the hook invokes reads MOCK_PR_JSON), not the printf.
run_hook() { printf '%s' "$1" | PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="${MOCK_PR_JSON:-}" bash "$HOOK" 2>/dev/null; }

assert_decision() {
    local desc="$1" expected="$2" json="$3"
    local out decision
    out=$(run_hook "$json")
    if [ -z "$out" ]; then
        decision="none"
    else
        decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse_error")
    fi
    if [ "$decision" = "$expected" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (expected %s, got %s)\n" "$desc" "$expected" "$decision"; FAIL=$((FAIL + 1))
    fi
}

# Decision + reason assertion in ONE hook invocation. The hook caches per
# session+branch, so a second run with the same payload is silent — the reason
# must therefore be checked from the same call that checks the decision.
# Args: desc, expected_decision, must_contain (or ""), must_not_contain (or ""), json
assert_case() {
    local desc="$1" expected="$2" needle="$3" absent="$4" json="$5"
    local out decision reason ok=1 detail=""
    out=$(run_hook "$json")
    if [ -z "$out" ]; then
        decision="none"; reason=""
    else
        decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo "parse_error")
        reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null || echo "")
    fi
    if [ "$decision" != "$expected" ]; then ok=0; detail="decision=$decision want=$expected"; fi
    if [ -n "$needle" ]; then
        case "$reason" in *"$needle"*) ;; *) ok=0; detail="$detail; missing '$needle'" ;; esac
    fi
    if [ -n "$absent" ]; then
        case "$reason" in *"$absent"*) ok=0; detail="$detail; unexpected '$absent'" ;; esac
    fi
    if [ "$ok" = "1" ]; then
        printf "  PASS: %s\n" "$desc"; PASS=$((PASS + 1))
    else
        printf "  FAIL: %s (%s | reason=%s)\n" "$desc" "$detail" "${reason:-<empty>}"; FAIL=$((FAIL + 1))
    fi
}

echo "=== check-branch-sync-on-push hook tests ==="

# ── Guard clauses ─────────────────────────────────────────────────────────────
echo ""
echo "guard clauses (no nudge):"
MOCK_PR_JSON=""
assert_decision "non-git command passes through" none "$(make_json "ls -la")"
assert_decision "git status passes through" none "$(make_json "git status")"
assert_decision "git log passes through" none "$(make_json "git log")"
assert_decision "empty command passes through" none '{"tool_name":"Bash","tool_input":{"command":""},"cwd":"/tmp","session_id":"x"}'
assert_decision "non-repo cwd passes through" none "$(make_json "git commit -m x" "/tmp")"

# ── Default branch is never nudged ────────────────────────────────────────────
echo ""
echo "default branch exclusion:"
git -C "$TMPDIR" checkout main -q
MOCK_PR_JSON=$(jq -n '{number:9,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/9"}')
assert_decision "commit on main is not nudged" none "$(make_json "git commit -m x")"
git -C "$TMPDIR" checkout feature -q

# ── In-sync feature branch with an open PR → no nudge ─────────────────────────
echo ""
echo "in-sync branch (no nudge):"
MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,url:"https://x/7"}')
assert_decision "in-sync + open PR → allow (commit)" none "$(make_json "git commit -m x")"
assert_decision "in-sync + open PR → allow (push)" none "$(make_json "git push origin feature")"

# ── Merged PR → ask ───────────────────────────────────────────────────────────
echo ""
echo "merged / closed PR (ask):"
MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/7"}')
assert_decision "merged PR → ask before commit" ask "$(make_json "git commit -m more")"
MOCK_PR_JSON=$(jq -n '{number:7,state:"CLOSED",mergedAt:null,url:"https://x/7"}')
assert_decision "closed PR → ask before push" ask "$(make_json "git push origin feature")"

# ── Behind upstream → ask ─────────────────────────────────────────────────────
echo ""
echo "behind upstream (ask):"
# Push an extra commit to origin/feature from a second clone so local is behind.
CLONE2=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
git clone -q "$ORIGIN" "$CLONE2" 2>/dev/null
git -C "$CLONE2" config user.email "o@o.com"; git -C "$CLONE2" config user.name "Other"
git -C "$CLONE2" checkout -q feature 2>/dev/null || git -C "$CLONE2" checkout -q -b feature origin/feature
git -C "$CLONE2" commit --allow-empty -m "other: drift" -q
git -C "$CLONE2" push -q origin feature
MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,url:"https://x/7"}')
assert_decision "behind origin → ask before commit" ask "$(make_json "git commit -m mine")"

# ── #2672: lease-pinned force-push after a rebase must NOT read as "behind" ───
echo ""
echo "lease-pinned force-push (#2672):"
git -C "$TMPDIR" fetch -q origin 2>/dev/null || true
ORIGIN_TIP=$(git -C "$TMPDIR" rev-parse refs/remotes/origin/feature)
ORIGIN_TIP_SHORT=${ORIGIN_TIP:0:7}
LOCAL_TIP=$(git -C "$TMPDIR" rev-parse HEAD)
MOCK_PR_JSON=$(jq -n '{number:7,state:"OPEN",mergedAt:null,url:"https://x/7"}')

# 1. Explicit lease whose (abbreviated) SHA is the fetched origin tip → silent.
assert_case "lease-pinned force-push matching origin tip → no nudge" none "" "" \
    "$(make_json "git push --force-with-lease=feature:${ORIGIN_TIP_SHORT} origin \"${LOCAL_TIP}:refs/heads/feature\"")"

# 2. Stale lease (a coworker pushed after the lease was taken) → still nudges.
assert_case "stale lease SHA → still nudges" ask "expected after a rebase" "git pull --rebase" \
    "$(make_json "git push --force-with-lease=feature:${LOCAL_TIP} origin \"${LOCAL_TIP}:refs/heads/feature\"")"

# 3. Lease naming a DIFFERENT branch → not self-verifying for this push.
assert_case "lease pinned to another branch → still nudges" ask "expected after a rebase" "" \
    "$(make_json "git push --force-with-lease=other:${ORIGIN_TIP_SHORT} origin feature")"

# 4. Bare --force-with-lease leases against the tracking ref this hook's own
#    fetch just advanced, so it must NOT suppress.
assert_case "bare --force-with-lease → still nudges" ask "expected after a rebase" "" \
    "$(make_json "git push --force-with-lease origin feature")"

# 5. Force-push with no lease → reworded message, no 'git pull --rebase' advice.
assert_case "force-push while behind → rebase wording, no pull advice" ask "expected after a rebase" "git pull --rebase" \
    "$(make_json "git push --force origin feature")"

# 6. Plain push keeps the original coworker-push wording verbatim.
assert_case "plain push while behind → keeps 'someone … pushed' wording" ask "someone (a teammate, another agent, or a CI auto-fix) pushed" "" \
    "$(make_json "git push origin feature")"
assert_case "plain push while behind → keeps 'git pull --rebase' advice" ask "git pull --rebase" "" \
    "$(make_json "git push origin feature")"

# Refspec-parser robustness: a flag before the remote, and a HEAD: source.
assert_case "git push -u origin feature → resolves feature" ask "Branch 'feature'" "" \
    "$(make_json "git push -u origin feature")"
assert_case "git push origin HEAD:feature → resolves feature" ask "Branch 'feature'" "" \
    "$(make_json "git push origin HEAD:feature")"

# ── #2672 repair: an unresolvable refspec destination must fall back to HEAD ───
# The hook sees the command as WRITTEN, so a substituted/variable branch name
# arrives as raw source text. Adopting it verbatim silenced the hook entirely.
echo ""
echo "unparseable refspec destination falls back to HEAD (#2672):"

# 10. This repo's own documented primary push idiom (git-push/SKILL.md).
# shellcheck disable=SC2016  # the literal, UNEXPANDED $(...) is the fixture
assert_case "push \$(git branch --show-current) → falls back to HEAD, names feature" ask "Branch 'feature'" "Branch '\$(git'" \
    "$(make_json 'git push -u origin $(git branch --show-current)')"

# 11. An unexpanded variable destination.
# shellcheck disable=SC2016  # the literal, UNEXPANDED $BRANCH is the fixture
assert_case "push \"\$BRANCH\" → falls back to HEAD, names feature" ask "Branch 'feature'" "Branch '\$BRANCH'" \
    "$(make_json 'git push origin "$BRANCH"')"

# 12. Multi-refspec push: ambiguous, so HEAD (feature) is the safer base — the
#     first-token-wins parse would resolve `main` and exit at the exclusion.
assert_case "push origin main feature → falls back to HEAD, names feature" ask "Branch 'feature'" "Branch 'main'" \
    "$(make_json "git push origin main feature")"

# ── #2672: the refspec destination, not HEAD, is what gets evaluated ──────────
echo ""
echo "refspec destination resolution (#2672):"
MOCK_PR_JSON=$(jq -n '{number:99,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/99"}')
git -C "$TMPDIR" checkout main -q

# 7. push-by-SHA from the default branch: today's HEAD-based hook exits at the
#    main/master exclusion and says nothing. It must evaluate `feature`.
assert_case "push <sha>:refs/heads/feature from main → nudges about feature" ask "Branch 'feature'" "" \
    "$(make_json "git push --force-with-lease origin \"${LOCAL_TIP}:refs/heads/feature\"")"

# 8. push-by-SHA from an unrelated branch must not name that branch.
git -C "$TMPDIR" checkout -q -b other 2>/dev/null || git -C "$TMPDIR" checkout -q other
assert_case "push <sha>:refs/heads/feature from 'other' → names feature, not other" ask "Branch 'feature'" "Branch 'other'" \
    "$(make_json "git push origin \"${LOCAL_TIP}:refs/heads/feature\"")"

# 9. A refspec destination of main still hits the default-branch exclusion.
git -C "$TMPDIR" checkout feature -q
assert_case "push <sha>:refs/heads/main is excluded (default branch)" none "" "" \
    "$(make_json "git push --force origin \"${LOCAL_TIP}:refs/heads/main\"")"

rm -rf "$CLONE2"

# ── git -C <worktree> routing (#1389) ─────────────────────────────────────────
echo ""
echo "git -C worktree routing (#1389):"
# Orchestrator cwd is /tmp (not a repo), but command targets the repo via -C.
MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/7"}')
assert_decision "git -C <repo> commit reads the worktree branch, not cwd" ask \
    "$(jq -n --arg cmd "git -C $TMPDIR commit -m more" --arg sid "wt-$RANDOM" \
        '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":"/tmp","session_id":$sid}')"

# ── Cache: second call within TTL is silent even with a nudge-worthy state ────
echo ""
echo "cache (second call within TTL is silent):"
SID="cache-$RANDOM-$RANDOM"
CACHE_JSON=$(jq -n --arg cmd "git commit -m x" --arg cwd "$TMPDIR" --arg sid "$SID" \
    '{"tool_name":"Bash","tool_input":{"command":$cmd},"cwd":$cwd,"session_id":$sid}')
MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/7"}')
first=$(run_hook "$CACHE_JSON")
second=$(run_hook "$CACHE_JSON")
first_d=$(printf '%s' "$first" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none)
if [ "$first_d" = "ask" ] && [ -z "$second" ]; then
    printf "  PASS: first call asks, second call (cached) is silent\n"; PASS=$((PASS + 1))
else
    printf "  FAIL: cache behaviour (first=%s second=%s)\n" "$first_d" "${second:-empty}"; FAIL=$((FAIL + 1))
fi

# ── Parsed trigger: a mention is not a commit/push (issue #2737) ──────────────
# The trigger used to be `git(-C …)? (commit|push)` over the raw command, so a
# quoted argument, heredoc body or comment that merely MENTIONS one fired the
# nudge. It is now decided on parsed command nodes. Every row runs against a
# MERGED PR, so "none" proves the trigger stayed quiet, not a later guard.
#
# Then a GENERATED spelling probe must all nudge, and a DIFFERENTIAL runs the
# same set through the pre-fix hook (`git show <PREFIX_SHA>:…`): a spelling the
# old hook nudged on that the new one does not fails the suite.
echo ""
echo "parsed trigger: quoted/heredoc mentions do not nudge (#2737):"
PREFIX_SHA=716345bf213793134a30bec2ff68761946aee38d
HOOK_REL=git-plugin/hooks/check-branch-sync-on-push.sh
MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/7"}')

have_parser() {
    [ "${CLAUDE_HOOKS_PARSED_TRIGGER_NO_ASTGREP:-}" = 1 ] && return 1
    command -v ast-grep >/dev/null 2>&1 && return 0
    command -v sg >/dev/null 2>&1 && sg --version 2>/dev/null | grep -qi '^ast-grep'
}

# $1 = hook path, $2 = command → "ask" or "none" (fresh session id per call).
sync_verdict() {
    local out
    out=$(make_json "$2" | PATH="$MOCK_BIN:$PATH" MOCK_PR_JSON="$MOCK_PR_JSON" bash "$1" 2>/dev/null)
    if [ -z "$out" ]; then echo none; else
        printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo parse_error
    fi
}

if ! have_parser; then
    printf "  SKIP: parsed-trigger rows, spelling probe and differential (ast-grep not installed)\n"
else
    assert_decision "gh issue comment --body mentioning git push" none \
        "$(make_json 'gh issue comment 1 --body "run git push later"')"
    assert_decision "git log --grep mentioning git commit" none \
        "$(make_json 'git log --oneline --grep "then git commit"')"
    assert_decision "single-quoted echo of a push" none \
        "$(make_json "echo 'cd repo && git push origin feature'")"
    assert_decision "heredoc body line starting with git commit" none \
        "$(make_json "$(printf '%s\n' "cat > notes.md <<'EOF'" 'git commit -m x' 'EOF')")"
    assert_decision "trailing comment mentioning git push" none \
        "$(make_json 'git status # then git push origin feature')"
    assert_decision "real commit whose message mentions gh pr create" ask \
        "$(make_json 'git commit -m "gh pr create next"')"
    # The old raw match also set IS_PUSH from the quoted mention, parsed `main"`
    # as the refspec destination and exited at the default-branch exclusion —
    # silencing the nudge for a real commit on a merged branch.
    assert_case "commit message mentioning 'git push origin main' still evaluates HEAD" ask "Branch 'feature'" "" \
        "$(make_json 'git commit -m "before git push origin main"')"
    assert_decision "cd x && git push nudges" ask "$(make_json "cd $TMPDIR && git push origin feature")"
    assert_decision "git -C <dir> push nudges" ask "$(make_json "git -C $TMPDIR push origin feature")"
    assert_decision "bash -c with a quoted commit script nudges" ask "$(make_json "bash -c 'git commit -m x'")"
    assert_decision "FOO=1 git commit nudges" ask "$(make_json "GIT_TRACE=0 git commit -m x")"

    echo ""
    echo "generated spelling probe + differential vs pre-fix hook (#2737):"
    BASES=("git commit -m x" "git commit --amend --no-edit" "git push" "git push origin feature"
        "git --no-pager commit -m x" "git -c core.askPass=true push origin feature"
        "/usr/bin/git push origin feature" "git -C $TMPDIR commit -m x")
    WRAPPERS=("" "env X=1 " "X=1 " "timeout 5 " "sudo " "command " "nice -n 5 " "nohup " "exec " "time ")
    CONTEXTS=('X' 'cd . && X' 'true; X' 'X; true' 'true && X' 'false || X' 'X || true'
        'X 2>&1 | tail -1' 'for d in 1; do X; done' 'if true; then X; fi' '( X )' '{ X; }'
        $'echo start\nX' 'out=$(X)' 'echo "$(X)"' "bash -c 'X'" "sh -c 'cd . && X'" 'X &'
        'git add a.txt && X' 'gh issue comment 1 --body "pushing now" && X')
    SPELLINGS=()
    for b in "${BASES[@]}"; do
        for w in "${WRAPPERS[@]}"; do SPELLINGS+=("$w$b"); done
    done
    for b in "git commit -m x" "git push origin feature" "git -C $TMPDIR push"; do
        for c in "${CONTEXTS[@]}"; do SPELLINGS+=("${c%%X*}$b${c#*X}"); done
    done

    BASELINE=""
    if git -C "$(dirname "$0")" cat-file -e "$PREFIX_SHA:$HOOK_REL" 2>/dev/null; then
        BASELINE="$MOCK_BIN/baseline-hook.sh"
        git -C "$(dirname "$0")" show "$PREFIX_SHA:$HOOK_REL" >"$BASELINE"
    fi
    missed=0
    lost=0
    base_hits=0
    for s in "${SPELLINGS[@]}"; do
        new=$(sync_verdict "$HOOK" "$s")
        if [ "$new" != ask ]; then
            missed=$((missed + 1))
            printf "  FAIL: spelling probe must nudge (got %s): %s\n" "$new" "$s"
        fi
        if [ -n "$BASELINE" ] && [ "$(sync_verdict "$BASELINE" "$s")" = ask ]; then
            base_hits=$((base_hits + 1))
            if [ "$new" != ask ]; then lost=$((lost + 1)); fi
        fi
    done
    if [ "$missed" -eq 0 ]; then
        printf "  PASS: all %d generated spellings nudge\n" "${#SPELLINGS[@]}"; PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
    if [ -z "$BASELINE" ]; then
        printf "  SKIP: differential vs pre-fix hook (commit %s not in this clone)\n" "$PREFIX_SHA"
    elif [ "$base_hits" -lt 40 ]; then
        printf "  FAIL: differential is vacuous (baseline nudged on only %d)\n" "$base_hits"; FAIL=$((FAIL + 1))
    elif [ "$lost" -eq 0 ]; then
        printf "  PASS: differential: baseline nudges on %d of %d, none lost\n" "$base_hits" "${#SPELLINGS[@]}"; PASS=$((PASS + 1))
    else
        printf "  FAIL: differential: %d spelling(s) the pre-fix hook nudged on are silent\n" "$lost"; FAIL=$((FAIL + 1))
    fi
fi

# ── Opt-out env var ───────────────────────────────────────────────────────────
echo ""
echo "opt-out:"
MOCK_PR_JSON=$(jq -n '{number:7,state:"MERGED",mergedAt:"2026-01-01T00:00:00Z",url:"https://x/7"}')
out=$(PATH="$MOCK_BIN:$PATH" CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1 MOCK_PR_JSON="$MOCK_PR_JSON" \
    printf '%s' "$(make_json "git commit -m x")" | PATH="$MOCK_BIN:$PATH" CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1 bash "$HOOK" 2>/dev/null)
if [ -z "$out" ]; then
    printf "  PASS: CLAUDE_HOOKS_DISABLE_BRANCH_SYNC=1 silences the nudge\n"; PASS=$((PASS + 1))
else
    printf "  FAIL: opt-out still emitted output\n"; FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
