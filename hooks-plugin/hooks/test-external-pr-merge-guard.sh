#!/usr/bin/env bash
# shellcheck disable=SC2016  # file-level: fixture commands are single-quoted ON PURPOSE — they must reach the hook as the literal text `gh pr merge`, $(gh pr merge), $T. Expanding them would destroy the test.
# Regression tests for external-pr-merge-guard.sh
#
# Verifies the hook denies merges of PRs authored by anyone other than the
# authenticated user or a bot, allows the trusted cases silently, and fails
# CLOSED when authorship cannot be established.
#
# The hook contract: emit
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",...}}
# on stdout and exit 0 to block; exit 0 with no output to allow.
#
# `gh` is stubbed on PATH so the tests are hermetic — no network, no real repo.
# The stub is driven by STUB_* env vars, mirroring the four author shapes that
# actually occur in the wild:
#   own login          → trusted
#   app/<name>         + is_bot true   → trusted  (`gh pr view` bot rendering)
#   <name>[bot]        + is_bot false  → trusted  (search-API bot rendering)
#   anyone else                        → DENIED
#
# Run: bash hooks-plugin/hooks/test-external-pr-merge-guard.sh
# Exit 0 = all tests pass, Exit 1 = failures
set -euo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/external-pr-merge-guard.sh"
PASS=0
FAIL=0

TMPDIR=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 1; }
# Guard the rm -rf target explicitly: an empty TMPDIR would make the trap
# resolve to the CWD in a shared checkout (see check-git-sandbox-guards.sh).
if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
    echo "bad TMPDIR" >&2
    exit 1
fi
trap 'rm -rf "$TMPDIR"' EXIT

# ---- gh stub -------------------------------------------------------------
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
args="$*"
# When STUB_LOG is set, record every invocation. Tests that must prove WHICH PR
# the hook looked up (the greedy-match case) assert on this log — the verdict
# alone cannot distinguish "checked PR 2231" from "checked PR 999", since the
# stub answers for any selector.
if [ -n "${STUB_LOG:-}" ]; then printf '%s\n' "$args" >> "$STUB_LOG"; fi
# Per-repository mode (issue #2872). When STUB_REPO_AUTHORS is set
# ("owner/repo=author ..."), the stub resolves the repository the way real gh
# does — the --repo value, else the `origin` remote of the git repo at the
# CURRENT DIRECTORY — and answers with that repository's PR author. A repository
# with no entry, or a directory with no remote, has no such PR, so the lookup
# fails exactly as `gh pr view` does there. This is what lets the suite prove
# WHICH directory the hook resolved a cd-prefixed merge in.
STUB_RESOLVED=""
if [ -n "${STUB_REPO_AUTHORS:-}" ]; then
    prev=""
    for a in "$@"; do
        [ "$prev" = "--repo" ] && STUB_RESOLVED="$a"
        prev="$a"
    done
    if [ -z "$STUB_RESOLVED" ]; then
        url=$(env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="${STUB_CEILING:-}" \
              git config --get remote.origin.url 2>/dev/null || true)
        STUB_RESOLVED=$(printf '%s' "$url" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
    fi
    if [ -n "${STUB_LOG:-}" ]; then printf 'resolved repo=%s cwd=%s\n' "$STUB_RESOLVED" "$PWD" >> "$STUB_LOG"; fi
fi
case "$args" in
  "api user --jq .login")
      [ -n "${STUB_NO_ME:-}" ] && exit 1
      printf '%s\n' "${STUB_ME-laurigates}" ;;
  "repo view --json nameWithOwner"*)
      if [ -n "${STUB_REPO_AUTHORS:-}" ]; then [ -n "$STUB_RESOLVED" ] || exit 1; printf '%s\n' "$STUB_RESOLVED"
      else printf '%s\n' "${STUB_SLUG-laurigates/claude-plugins}"; fi ;;
  *"--json number,title,author,url"*)
      [ -n "${STUB_VIEW_FAIL:-}" ] && exit 1
      # Real `gh pr view '$n'` cannot resolve an unexpanded shell variable —
      # model that, or the loop case would look resolvable and the test would
      # assert against the wrong denial path.
      case "$args" in *'$'*) exit 1 ;; esac
      if [ -n "${STUB_REPO_AUTHORS:-}" ]; then
          author=""
          for pair in $STUB_REPO_AUTHORS; do
              case "$pair" in "$STUB_RESOLVED="*) author="${pair#*=}" ;; esac
          done
          { [ -n "$STUB_RESOLVED" ] && [ -n "$author" ]; } || exit 1
          printf '%s\t%s\t%s\t%s\t%s\n' 5 "$author" false "a title" "https://example.invalid/pr"
          exit 0
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "${STUB_NUM-42}" "${STUB_AUTHOR-laurigates}" \
        "${STUB_ISBOT-false}" "${STUB_TITLE-a title}" "https://example.invalid/pr" ;;
  *"pulls/"*"--jq .author_association")
      printf '%s\n' "${STUB_ASSOC-FIRST_TIME_CONTRIBUTOR}" ;;
  *"--json files"*)
      printf '%s\n' ${STUB_FILES-.github/workflows/x.yml} ;;
  *) echo "gh stub: unhandled: $args" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMPDIR/bin/gh"

# ---- harness -------------------------------------------------------------
# run <json> → prints "DENY"/"ALLOW" and sets $LAST_VERDICT + $LAST_REASON.
#
# NOTE: the globals only survive when `run` is called DIRECTLY. Calling it as
# "$(run ...)" spawns a subshell, so any assertion on $LAST_REASON afterwards
# would read a stale value from an earlier direct call — which silently passed
# the wrong test. Assertions on the reason text therefore call `run` directly
# and read $LAST_VERDICT instead of capturing stdout.
LAST_REASON=""
LAST_VERDICT=""
run() {
    local json="$1" out
    out=$(printf '%s' "$json" | PATH="$TMPDIR/bin:$PATH" bash "$HOOK" 2>/dev/null || true)
    LAST_REASON=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null || true)
    if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then LAST_VERDICT=DENY; else LAST_VERDICT=ALLOW; fi
    echo "$LAST_VERDICT"
}

bash_json() { printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$TMPDIR" "$(printf '%s' "$1" | jq -Rs .)"; }

ck() { # ck <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; PASS=$((PASS + 1))
    else printf '  FAIL %s — expected %s got %s\n' "$1" "$2" "$3"; FAIL=$((FAIL + 1)); fi
}
ck_reason() { # ck_reason <desc> <substring>
    case "$LAST_REASON" in
        *"$2"*) printf '  ok   %s\n' "$1"; PASS=$((PASS + 1)) ;;
        *) printf '  FAIL %s — reason lacked %s\n' "$1" "$2"; FAIL=$((FAIL + 1)) ;;
    esac
}
# ck_lookup <desc> <command> <selector the hook must have resolved>
# Asserts DENY *and* that the hook looked the PR up by the selector the command
# actually merges. The verdict alone is a weak assertion for these cases: the
# stub answers for any selector, so a change that stopped understanding a whole
# selector SHAPE (branch name, URL) would flip to ALLOW silently while every
# numeric-selector assertion stayed green. The log pins the semantics.
ck_lookup() {
    local desc="$1" cmd="$2" want="$3" log="$TMPDIR/lookup.log"
    : > "$log"
    STUB_LOG="$log" run "$(bash_json "$cmd")" >/dev/null
    unset STUB_LOG
    ck "$desc" DENY "$LAST_VERDICT"
    if grep -qF "pr view $want " "$log"; then
        printf '  ok   %s — resolved to %s\n' "$desc" "$want"; PASS=$((PASS + 1))
    else
        printf '  FAIL %s — the hook never looked up %s\n' "$desc" "$want"; FAIL=$((FAIL + 1))
    fi
}

echo "== non-merge commands are untouched =="
ck "git status"            ALLOW "$(run "$(bash_json 'git status')")"
ck "gh pr view"            ALLOW "$(run "$(bash_json 'gh pr view 42')")"
ck "gh pr list"            ALLOW "$(run "$(bash_json 'gh pr list --json number')")"
ck "gh pr create"          ALLOW "$(run "$(bash_json 'gh pr create --title x')")"
ck "unrelated tool"        ALLOW "$(run '{"tool_name":"Read","tool_input":{"file_path":"/x"}}')"

echo "== trusted authors merge freely =="
ck "own PR"  ALLOW "$(STUB_AUTHOR=laurigates run "$(bash_json 'gh pr merge 42 --squash')")"
# Case C (issue #2449): fully literal selector AND literal --repo must still
# be permitted silently — the fix must not regress the non-denial path.
ck "own PR, literal --repo (case C)" ALLOW \
   "$(STUB_AUTHOR=laurigates run "$(bash_json 'gh pr merge 123 --repo laurigates/claude-plugins --squash')")"
export STUB_AUTHOR='app/laurigates-release-please' STUB_ISBOT=true
ck "bot, gh-pr-view rendering (app/, is_bot true)" ALLOW "$(run "$(bash_json 'gh pr merge 42 --squash')")"
export STUB_AUTHOR='dependabot[bot]' STUB_ISBOT=false
ck "bot, search rendering ([bot], is_bot false)"   ALLOW "$(run "$(bash_json 'gh pr merge 42 --squash')")"
unset STUB_AUTHOR STUB_ISBOT

echo "== external author is denied on every merge route =="
export STUB_AUTHOR=joshua-trustabl STUB_NUM=2231 STUB_TITLE='Add Trustabl security scanning to CI'
ck "gh pr merge <n>"                  DENY "$(run "$(bash_json 'gh pr merge 2231 --squash --delete-branch')")"
ck "flags before the number"          DENY "$(run "$(bash_json 'gh pr merge --squash 2231')")"
ck "no number (current branch PR)"    DENY "$(run "$(bash_json 'gh pr merge --squash')")"
ck "--repo form"                      DENY "$(run "$(bash_json 'gh pr merge 2231 --repo laurigates/claude-plugins --squash')")"
ck "--repo=OWNER/REPO form"           DENY "$(run "$(bash_json 'gh pr merge 2231 --repo=laurigates/claude-plugins --squash')")"
ck "inside a compound command"        DENY "$(run "$(bash_json 'cd /tmp && gh pr merge 2231 --squash && echo done')")"
ck "gh api PUT .../merge"             DENY "$(run "$(bash_json 'gh api -X PUT repos/laurigates/claude-plugins/pulls/2231/merge')")"
ck "MCP merge_pull_request"           DENY "$(run '{"tool_name":"mcp__github__merge_pull_request","cwd":"'"$TMPDIR"'","tool_input":{"owner":"laurigates","repo":"claude-plugins","pullNumber":2231}}')"
ck "--admin does not bypass"          DENY "$(run "$(bash_json 'gh pr merge 2231 --admin --squash')")"

echo "== a leading literal 'cd <dir> &&' is where the PR is resolved (issue #2872) =="
# The compound-command case above (`cd /tmp && gh pr merge 2231`) is the shape
# issue #2872 is about. The hook used to resolve the PR in the SESSION cwd and
# ignore the cd, so in a multi-repo workspace a self-authored PR in the cd
# target was denied ("could not read the PR's author") whenever the session
# repo had no PR with that number. These cases use REAL git repositories with
# configured remotes, and the stub resolves the repository from the directory
# gh runs in, so each verdict proves which repository was checked.
#
#   session  acme/session  no PRs (lookup fails, as in the issue)
#   own      acme/own      PR authored by you
#   ext      acme/ext      PR authored by an external contributor
#   plain    (no git)      lookup fails
WS="$TMPDIR/ws"
mkdir -p "$WS"
if [ ! -d "$WS" ]; then echo "bad workspace dir" >&2; exit 1; fi
mk_repo() { # mk_repo <dir> <owner/repo>
    local dir="$1" slug="$2"
    # Never let an empty path reach git: `git -C ""` falls back to the CWD,
    # which is the real checkout (scripts/check-git-sandbox-guards.sh).
    if [ -z "$dir" ] || [ -z "$slug" ]; then echo "mk_repo: empty argument" >&2; exit 1; fi
    mkdir -p "$dir"
    if [ ! -d "$dir" ]; then echo "mk_repo: $dir was not created" >&2; exit 1; fi
    env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" init -q
    env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" remote add origin "https://github.com/$slug.git"
}
mk_repo "$WS/session" acme/session
mk_repo "$WS/own"     acme/own
mk_repo "$WS/ext"     acme/ext
mkdir -p "$WS/plain" "$WS/ext/sub"
# own/l/.. is `own` logically but `ext` physically (cd -P, `set -o physical`).
ln -s ../ext/sub "$WS/own/l"
export STUB_REPO_AUTHORS="acme/own=laurigates acme/ext=joshua-trustabl"
export STUB_CEILING="$TMPDIR"

bash_json_in() { # bash_json_in <cwd> <command>
    printf '{"tool_name":"Bash","cwd":"%s","tool_input":{"command":%s}}' "$1" "$(printf '%s' "$2" | jq -Rs .)"
}
# run_hook_in <hook> <cwd> <command> → DENY/ALLOW (no globals; safe in $( )).
# HOME is the workspace, so `cd ~/own` names a fixture repo.
run_hook_in() {
    local out
    out=$(bash_json_in "$2" "$3" | HOME="$WS" PATH="$TMPDIR/bin:$PATH" bash "$1" 2>/dev/null || true)
    if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo DENY; else echo ALLOW; fi
}

# The corpus. Tab-separated: session cwd key (`.` = the workspace root, not a
# repo), expected verdict now, the verdict of the hook BEFORE this fix (frozen;
# re-checked live below when the pre-fix hook is in the clone), a tag, and the
# command. @WS@ → the workspace, @NL@ → a newline.
#   FLIP     old DENY → new ALLOW. Only legal for the exact literal-cd&& shape
#            whose cd target holds a self-authored PR (asserted below).
#   NEWDENY  old ALLOW → new DENY: the merge really runs in an external repo.
#   -        unchanged. Every fallback shape is listed twice where it can be:
#            from `session` into `own` (stays DENY) and from `own` into `ext`
#            (stays ALLOW) — the second proves the cd was ignored, not honoured.
CORPUS=$(cat <<'CORPUS'
session	ALLOW	DENY	FLIP	cd @WS@/own && gh pr merge 2506 --squash --delete-branch
session	ALLOW	DENY	FLIP	cd ../own && gh pr merge 5
session	ALLOW	DENY	FLIP	cd ./../own && gh pr merge 5
session	ALLOW	DENY	FLIP	cd ~/own && gh pr merge 5 --squash
session	ALLOW	DENY	FLIP	  cd @WS@/own&&gh pr merge 5
session	ALLOW	DENY	FLIP	cd @WS@/own/ && gh pr merge 5 && echo done
own	DENY	ALLOW	NEWDENY	cd @WS@/ext && gh pr merge 5
own	DENY	ALLOW	NEWDENY	cd ../ext && gh pr merge 5 --squash
own	DENY	ALLOW	NEWDENY	cd @WS@/plain && gh pr merge 5
own	DENY	ALLOW	NEWDENY	cd ~ && gh pr merge 5
session	DENY	DENY	-	gh pr merge 5
own	ALLOW	ALLOW	-	gh pr merge 5
ext	DENY	DENY	-	gh pr merge 5
session	DENY	DENY	-	cd @WS@/ext && gh pr merge 5
ext	DENY	DENY	-	cd . && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own; gh pr merge 5
own	ALLOW	ALLOW	-	cd @WS@/ext; gh pr merge 5
session	DENY	DENY	-	cd @WS@/own || exit 1; gh pr merge 5
session	DENY	DENY	-	cd @WS@/nope || cd @WS@/own && gh pr merge 5
session	DENY	DENY	-	cd -P @WS@/own && gh pr merge 5
own	ALLOW	ALLOW	-	cd -P @WS@/ext && gh pr merge 5
session	DENY	DENY	-	cd -L @WS@/own && gh pr merge 5
session	DENY	DENY	-	cd -- @WS@/own && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own @WS@/ext && gh pr merge 5
session	DENY	DENY	-	cd "@WS@/own" && gh pr merge 5
own	ALLOW	ALLOW	-	cd "@WS@/ext" && gh pr merge 5
session	DENY	DENY	-	cd '@WS@/own' && gh pr merge 5
session	DENY	DENY	-	cd $D && gh pr merge 5
session	DENY	DENY	-	cd @WS@/ow? && gh pr merge 5
session	DENY	DENY	-	cd @WS@/o* && gh pr merge 5
session	DENY	DENY	-	cd @WS@/{own,x} && gh pr merge 5
session	DENY	DENY	-	cd `echo @WS@/own` && gh pr merge 5
session	DENY	DENY	-	cd $(echo @WS@/own) && gh pr merge 5
session	DENY	DENY	-	cd ~root && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own/l/.. && gh pr merge 5
own	ALLOW	ALLOW	-	cd @WS@/own/l/.. && gh pr merge 5
.	DENY	DENY	-	cd own && gh pr merge 5
session	DENY	DENY	-	cd @WS@/nope && gh pr merge 5
own	ALLOW	ALLOW	-	cd @WS@/nope && gh pr merge 5
session	DENY	DENY	-	pushd @WS@/own && gh pr merge 5
own	ALLOW	ALLOW	-	pushd @WS@/ext && gh pr merge 5
session	DENY	DENY	-	\cd @WS@/own && gh pr merge 5
session	DENY	DENY	-	command cd @WS@/own && gh pr merge 5
session	DENY	DENY	-	true && cd @WS@/own && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && cd . && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && pushd . && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && gh pr merge 5 && popd
session	DENY	DENY	-	cd @WS@/own && GH_REPO=acme/ext gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && gh pr merge 5 && export GH_REPO=x
session	DENY	DENY	-	cd @WS@/own && env -C @WS@/ext gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && sudo gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && echo hi && gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && gh pr merge 5; gh pr merge 6
session	DENY	DENY	-	cd @WS@/own &&@NL@gh pr merge 5
session	DENY	DENY	-	cd @WS@/own & gh pr merge 5
session	DENY	DENY	-	cd @WS@/own | gh pr merge 5
session	DENY	DENY	-	cd @WS@/own && gh pr merge $N
session	DENY	DENY	-	cd @WS@/own && gh pr merge 5 -R acme/ext
session	ALLOW	ALLOW	-	cd @WS@/ext && gh pr merge 5 -R acme/own
CORPUS
)

expand_ws() { local s="$1"; s="${s//@WS@/$WS}"; printf '%s' "${s//@NL@/$'\n'}"; }

# The repository a FLIP row's leading cd lands in, resolved by a real `cd`.
flip_target_repo() { # flip_target_repo <cwd> <cd operand>
    local w="$2"
    case "$w" in \~) w="$WS" ;; \~/*) w="$WS/${w#\~/}" ;; esac
    ( cd "$1" 2>/dev/null && cd "$w" 2>/dev/null \
      && env -u GIT_DIR -u GIT_WORK_TREE GIT_CEILING_DIRECTORIES="$TMPDIR" git config --get remote.origin.url ) || true
}
FLIP_RE='^[[:space:]]*cd[[:blank:]]+([^[:space:]&;|]+)[[:blank:]]*&&[[:blank:]]*gh[[:blank:]]+pr[[:blank:]]+merge([[:blank:]]|$)'

CORPUS_N=0
while IFS=$'\t' read -r cwdk want old tag cmd; do
    [ -n "$cwdk" ] || continue
    CORPUS_N=$((CORPUS_N + 1))
    cmd=$(expand_ws "$cmd")
    ck "[$cwdk] ${cmd//$'\n'/'\n'}" "$want" "$(run_hook_in "$HOOK" "$WS/$cwdk" "$cmd")"
    # The frozen columns must be consistent with the tag, so a row cannot
    # quietly reclassify an old DENY as an acceptable ALLOW.
    if [ "$old" = DENY ] && [ "$want" != DENY ]; then
        if [ "$tag" != FLIP ]; then
            printf '  FAIL corpus row un-guards an old DENY without a FLIP tag: %s\n' "$cmd"; FAIL=$((FAIL + 1))
        elif ! [[ "$cmd" =~ $FLIP_RE ]] \
             || [ "$(flip_target_repo "$WS/$cwdk" "${BASH_REMATCH[1]}")" != "https://github.com/acme/own.git" ]; then
            printf '  FAIL FLIP row is not a literal cd&& into a self-authored repo: %s\n' "$cmd"; FAIL=$((FAIL + 1))
        fi
    fi
done <<< "$CORPUS"

echo "== the issue repro is looked up in the cd target, and the deny names the cause =="
WS_LOG="$TMPDIR/ws.log"
: > "$WS_LOG"
STUB_LOG="$WS_LOG" HOME="$WS" run "$(bash_json_in "$WS/session" "cd $WS/own && gh pr merge 2506 --squash --delete-branch")" >/dev/null
unset STUB_LOG
ck "issue #2872 repro allowed" ALLOW "$LAST_VERDICT"
if grep -qF "cwd=$WS/own" "$WS_LOG" && ! grep -qF "cwd=$WS/session" "$WS_LOG"; then
    printf '  ok   the PR was looked up in the cd target, not the session cwd\n'; PASS=$((PASS + 1))
else
    printf '  FAIL the PR was not looked up (only) in the cd target\n'; FAIL=$((FAIL + 1))
fi
# Fix 2: a failed lookup with no --repo names the directory it resolved the
# repository from, and the -R remedy — not just "bad PR number or no network".
run "$(bash_json_in "$WS/session" "gh pr merge 2506 --squash")" >/dev/null
ck "no such PR in the session repo"         DENY "$LAST_VERDICT"
ck_reason "still fails closed"              "Cannot verify"
ck_reason "names the directory it looked in" "$WS/session"
ck_reason "suggests naming the repository"  "-R OWNER/REPO"
# A fallback shape is still looked up in the session cwd, and says so.
run "$(bash_json_in "$WS/session" "cd $WS/own; gh pr merge 2506")" >/dev/null
ck "fallback shape, no such PR in session"  DENY "$LAST_VERDICT"
ck_reason "names the session directory"     "$WS/session"
ck_reason "suggests -R for the fallback"    "-R OWNER/REPO"

echo "== differential: every merge the pre-fix hook denied is still denied =="
# Frozen columns can drift from what the old hook really did, so when the
# pre-fix hook is in this clone, run it over the same corpus and compare.
# Shallow CI clones may not have it; the frozen column (asserted above) is the
# fallback, and this section says so instead of passing vacuously.
BASE_HOOK="$TMPDIR/baseline-hook.sh"
BASE_REF=785b0d9802399823dffcda7cfb86f883e2524584
if git -C "$(dirname "$HOOK")" show "$BASE_REF:./external-pr-merge-guard.sh" > "$BASE_HOOK" 2>/dev/null \
   && [ -s "$BASE_HOOK" ]; then
    DIFF_DENIES=0
    while IFS=$'\t' read -r cwdk want old tag cmd; do
        [ -n "$cwdk" ] || continue
        cmd=$(expand_ws "$cmd")
        got_old=$(run_hook_in "$BASE_HOOK" "$WS/$cwdk" "$cmd")
        ck "baseline matches the frozen column: [$cwdk] ${cmd//$'\n'/'\n'}" "$old" "$got_old"
        if [ "$got_old" = DENY ]; then
            DIFF_DENIES=$((DIFF_DENIES + 1))
            got_new=$(run_hook_in "$HOOK" "$WS/$cwdk" "$cmd")
            if [ "$got_new" != DENY ] && [ "$tag" != FLIP ]; then
                printf '  FAIL old hook denied, new hook allows (untagged): %s\n' "$cmd"; FAIL=$((FAIL + 1))
            fi
        fi
    done <<< "$CORPUS"
    if [ "$DIFF_DENIES" -gt 0 ]; then
        printf '  ok   differential is not vacuous: the baseline denied %s of %s cases\n' "$DIFF_DENIES" "$CORPUS_N"; PASS=$((PASS + 1))
    else
        printf '  FAIL differential is vacuous: the baseline denied nothing\n'; FAIL=$((FAIL + 1))
    fi
else
    printf '  NOTE pre-fix baseline %s not in this clone — relying on the frozen old column\n' "${BASE_REF:0:9}"
fi
unset STUB_REPO_AUTHORS STUB_CEILING

echo "== a flag VALUE is not mistaken for the PR selector =="
# Without the value-flag skip list, `--subject "feat: x"` would be read as the
# selector, checking the wrong PR (or none) and letting the merge through.
ck "--subject with a value"  DENY "$(run "$(bash_json 'gh pr merge --squash --subject "feat: x" 2231')")"
ck "-b with a value"         DENY "$(run "$(bash_json 'gh pr merge --squash -b "body text" 2231')")"

echo "== a MENTION of the phrase is not an invocation (#2307) =="
# The guard used to grep the RAW command text, so any command whose text merely
# contained "gh pr merge" was treated as a merge: a bare `echo`, and a real
# `gh pr create` whose --body heredoc quoted the phrase (the agent then retitled
# the user-visible PR to get past the guard).
#
# STUB_AUTHOR is still the external author here, so ANY detection yields a
# denial — ALLOW is therefore proof that the text was not read as a merge
# command, not an artefact of a trusted author.
HEREDOC_CMD=$(cat <<'CMD'
gh pr create --title "Fix the merge guard" --body "$(cat <<'EOF'
This PR narrows the guard.
Before it, `gh pr merge` anywhere in the text was denied.
EOF
)"
CMD
)
BARE_HEREDOC_CMD=$(cat <<'CMD'
gh pr create --body-file - <<'EOF'
Reviewers: do not gh pr merge 5 until CI is green.
EOF
CMD
)
ck "echo, phrase unquoted in prose" ALLOW \
   "$(run "$(bash_json 'echo docs: this sentence mentions gh pr merge')")"
ck "echo, phrase double-quoted"     ALLOW \
   "$(run "$(bash_json 'echo "docs: this sentence mentions gh pr merge"')")"
ck "echo, phrase single-quoted"     ALLOW \
   "$(run "$(bash_json "echo 'see gh pr merge 999 for details'")")"
ck "phrase in a --body value"       ALLOW \
   "$(run "$(bash_json 'gh pr create --title x --body "run gh pr merge 5 once CI is green"')")"
ck "phrase in a \$(cat <<EOF) body" ALLOW "$(run "$(bash_json "$HEREDOC_CMD")")"
ck "phrase in a bare heredoc"       ALLOW "$(run "$(bash_json "$BARE_HEREDOC_CMD")")"
ck "api route quoted inside prose"  ALLOW \
   "$(run "$(bash_json 'gh pr comment 1 --body "never run gh api repos/o/r/pulls/9/merge"')")"
# The api-route half of the prefilter is the issue's own headline complaint: a
# SEARCH for the route, or an echo of it, is not a call to it. Only a command
# word that can actually reach the REST API (gh, curl, wget, …) counts.
ck "rg searching for the route"     ALLOW \
   "$(run "$(bash_json 'rg repos/laurigates/claude-plugins/pulls/2231/merge docs/')")"
ck "echo of the route, bare"        ALLOW \
   "$(run "$(bash_json 'echo repos/laurigates/claude-plugins/pulls/2231/merge')")"
ck "echo of the route, quoted"      ALLOW \
   "$(run "$(bash_json 'echo "repos/laurigates/claude-plugins/pulls/2231/merge"')")"
ck "grep -c over a log of routes"   ALLOW \
   "$(run "$(bash_json 'grep -c repos/o/r/pulls/9/merge audit.log')")"

echo "== a real merge is still detected in every command position =="
ck "after &&"                       DENY \
   "$(run "$(bash_json 'echo "note: gh pr merge is gated" && gh pr merge 2231 --squash')")"
ck "after a newline"                DENY "$(run "$(bash_json 'echo hi
gh pr merge 2231 --squash')")"
ck "after a ; sequence"             DENY "$(run "$(bash_json 'echo hi; gh pr merge 2231 --squash')")"
ck "inside a subshell"              DENY "$(run "$(bash_json '(gh pr merge 2231 --squash)')")"
ck "wrapped in bash -c"             DENY "$(run "$(bash_json "bash -c 'gh pr merge 2231 --squash'")")"
ck "wrapped in eval"                DENY "$(run "$(bash_json 'eval "gh pr merge 2231 --squash"')")"
# Command wrappers still run the merge, so command position must see past them.
ck "behind timeout <duration>"      DENY "$(run "$(bash_json 'timeout 60 gh pr merge 2231 --squash')")"
ck "behind timeout with flags"      DENY "$(run "$(bash_json 'timeout -k 5s 60 gh pr merge 2231')")"
ck "behind env with an assignment"  DENY "$(run "$(bash_json 'env GH_TOKEN=x gh pr merge 2231')")"
ck "backgrounded with &"            DENY "$(run "$(bash_json 'nohup gh pr merge 2231 --squash &')")"
# ...but a wrapper NAMED in prose is still prose.
ck "wrapper named inside an echo"   ALLOW "$(run "$(bash_json 'echo timeout 60 gh pr merge 2231')")"
ck "wrapper around a prose echo"    ALLOW "$(run "$(bash_json 'timeout 60 echo "gh pr merge 2231"')")"
ck "quoted PR number"               DENY "$(run "$(bash_json 'gh pr merge "2231" --repo "laurigates/claude-plugins"')")"
ck "api route as a quoted argument" DENY \
   "$(run "$(bash_json 'gh api -X PUT "repos/laurigates/claude-plugins/pulls/2231/merge"')")"
# Fail-closed survives: a plausible selector whose author cannot be read is
# still denied. This is the property the narrowing must not have weakened.
ck "plausible selector, author unreadable" DENY \
   "$(STUB_VIEW_FAIL=1 run "$(bash_json 'gh pr merge 123 --squash')")"
# The command word is established structurally by the time the selector is read,
# so an argument that does not look like a selector does not un-make the merge.
# Allowing it would be a fail-OPEN on a real `gh pr merge` invocation.
ck "argument that is not selector-shaped" DENY \
   "$(run "$(bash_json 'gh pr merge --unknown-flag "not: a selector"')")"
# Bash strips redirections before gh sees argv, so these really do merge — the
# tokeniser must not read `2>/dev/null` or `<` as the PR selector and give up.
ck "redirection before the selector"  DENY "$(run "$(bash_json 'gh pr merge 2>/dev/null 2231 --squash')")"
ck "output redirect before selector"  DENY "$(run "$(bash_json 'gh pr merge >merge.log 2231 --squash')")"
ck "bulk merge fed by stdin"          DENY "$(run "$(bash_json 'xargs -n1 gh pr merge < prs.txt')")"
# Legacy command substitution is a command position too. Its $( ) twin was only
# ever caught because `(` happens to split statements.
ck "inside backticks, assigned"       DENY "$(run "$(bash_json 'X=`gh pr merge 2231`')")"
ck "inside backticks, as an argument" DENY "$(run "$(bash_json 'echo `gh pr merge 2231`')")"
ck "inside \$( ) substitution"        DENY "$(run "$(bash_json 'result=$(gh pr merge 2231)')")"

echo "== a bare backtick VALUE truncates the statement, unlike a WRAPPING one (issue #2449) =="
# A backtick used to compute a --repo/-R value (or the selector itself) is NOT
# the same as backticks wrapping the WHOLE invocation (denied above via clean
# selector extraction, since the wrapping backtick delimits the statement
# boundary, not a mid-argument value). Before this fix, a value-position
# backtick silently truncated the statement and dropped everything after it —
# so the hook went on to query `gh pr view` for the WRONG PR/repo (empty
# selector reads as "current branch", empty repo reads as "cwd"), which could
# resolve successfully and ALLOW while the real, substituted target was never
# checked. The regression assertion is therefore not just DENY but that
# `gh pr view` was never even called — a bare DENY here could still hide a
# wrong-target lookup underneath it.
BT_LOG="$TMPDIR/backtick.log"
: > "$BT_LOG"
STUB_LOG="$BT_LOG" run "$(bash_json 'gh pr merge 464 -R `echo owner/repo` --squash')" >/dev/null
unset STUB_LOG
ck "backtick VALUE in --repo/-R"      DENY "$LAST_VERDICT"
ck_reason "explains the truncation"   "backtick"
if grep -q '^pr view' "$BT_LOG"; then
    printf '  FAIL backtick-in-repo truncation still queried gh pr view (wrong-target lookup)\n'; FAIL=$((FAIL + 1))
else
    printf '  ok   backtick-in-repo truncation denied before any gh pr view lookup\n'; PASS=$((PASS + 1))
fi

: > "$BT_LOG"
STUB_LOG="$BT_LOG" run "$(bash_json 'gh pr merge `echo 464` --repo owner/repo --squash')" >/dev/null
unset STUB_LOG
ck "backtick VALUE as the selector"   DENY "$LAST_VERDICT"
if grep -q '^pr view' "$BT_LOG"; then
    printf '  FAIL backtick-selector truncation still queried gh pr view (wrong-target lookup)\n'; FAIL=$((FAIL + 1))
else
    printf '  ok   backtick-selector truncation denied before any gh pr view lookup\n'; PASS=$((PASS + 1))
fi

echo "== a wrapper that RUNS the merge does not hide it =="
# Wrapper flags that take a SEPARATE value push the command word past the point
# a flags-only stripper reaches; a wrapper executes whatever follows it.
ck "sudo -u <user>"                DENY "$(run "$(bash_json 'sudo -u ci gh pr merge 2231 --squash')")"
ck "sudo -H -u <user>"             DENY "$(run "$(bash_json 'sudo -H -u ci gh pr merge 2231')")"
ck "env -C <dir>"                  DENY "$(run "$(bash_json 'env -C /tmp gh pr merge 2231 --squash')")"
ck "env -u <var>"                  DENY "$(run "$(bash_json 'env -u GH_TOKEN gh pr merge 2231')")"
ck "find -exec"                    DENY "$(run "$(bash_json 'find . -name "*.txt" -exec gh pr merge 2231 --squash \;')")"
ck "parallel"                      DENY "$(run "$(bash_json 'parallel gh pr merge ::: 2231')")"
ck "watch -n5"                     DENY "$(run "$(bash_json 'watch -n5 gh pr merge 2231')")"
ck "script -q /dev/null"           DENY "$(run "$(bash_json 'script -q /dev/null gh pr merge 2231')")"
ck "uv run --with"                 DENY "$(run "$(bash_json 'uv run --with x gh pr merge 2231')")"
# A wrapper in front of a shell invoker must not lose the "this string is script
# text" property — the effective command word is `bash`, not `sudo`.
ck "sudo in front of bash -c"      DENY "$(run "$(bash_json 'sudo -u ci bash -c "gh pr merge 2231"')")"
ck "nix-shell --run"               DENY "$(run "$(bash_json 'nix-shell -p gh --run "gh pr merge 2231"')")"
# Operators INSIDE nested script text separate statements there too.
ck "second statement inside bash -c" DENY "$(run "$(bash_json "bash -c 'echo hi; gh pr merge 2231'")")"
# A heredoc fed to a shell is script text, exactly like `bash -c "…"`.
ck "heredoc fed to bash"           DENY "$(run "$(bash_json 'bash <<EOF
gh pr merge 2231 --squash
EOF')")"
ck "heredoc fed to bash -s"        DENY "$(run "$(bash_json "bash -s <<'EOF'
gh pr merge 2231 --squash
EOF")")"
# ...but a wrapper in front of a prose-producing command is still prose, and a
# heredoc fed to something that is NOT a shell is still a document.
ck "wrapper in front of an echo"   ALLOW "$(run "$(bash_json 'sudo -u ci echo "gh pr merge 2231"')")"
ck "heredoc fed to cat"            ALLOW "$(run "$(bash_json 'cat <<EOF
remember to gh pr merge 2231 once CI is green
EOF')")"

echo "== every SELECTOR SHAPE gh accepts is still checked =="
# gh pr merge takes a number, a URL, or a head-branch name. The branch name is
# chosen by the external contributor — the very party this guard defends
# against — so a shape whitelist narrower than a legal git ref would let them
# turn the guard off by naming their branch `_wip`.
ck_lookup "numeric selector"        'gh pr merge 2231 --squash'          '2231'
ck_lookup "branch selector"         'gh pr merge feat/my-branch --squash' 'feat/my-branch'
ck_lookup "branch, leading _"       'gh pr merge _wip --squash'           '_wip'
ck_lookup "branch with a comma"     'gh pr merge feat/a,b --squash'       'feat/a,b'
ck_lookup "branch with a percent"   'gh pr merge feat/100%-done --squash' 'feat/100%-done'
ck_lookup "URL selector"            'gh pr merge https://github.com/laurigates/claude-plugins/pull/2231 --squash' \
                                    'https://github.com/laurigates/claude-plugins/pull/2231'

echo "== the api merge route is checked however it is called =="
# gh api and curl reach the same PUT .../pulls/N/merge endpoint. curl had no
# assertion at all, so scoping the route check to `gh` would have gone unnoticed.
ck_lookup "gh api -X PUT"    'gh api -X PUT repos/laurigates/claude-plugins/pulls/2231/merge' '2231'
ck_lookup "curl -X PUT"      'curl -X PUT https://api.github.com/repos/laurigates/claude-plugins/pulls/2231/merge' '2231'
ck_lookup "curl with a token header" \
   'curl -H "Authorization: bearer $T" -X PUT https://api.github.com/repos/laurigates/claude-plugins/pulls/2231/merge' '2231'
ck_lookup "wrapped curl"     'sudo -u ci curl -X PUT https://api.github.com/repos/laurigates/claude-plugins/pulls/2231/merge' '2231'

echo "== the FIRST merge wins, not the LAST mention =="
# The selector used to be taken after a GREEDY `.*`, so it anchored on the last
# occurrence of the phrase: trailing prose hijacked the selector and the hook
# checked (and reported on) the wrong PR. The verdict alone cannot catch this —
# the stub answers for any selector — so assert on which PR was looked up.
GREEDY_LOG="$TMPDIR/greedy.log"
: > "$GREEDY_LOG"
STUB_LOG="$GREEDY_LOG" run \
  "$(bash_json 'gh pr merge 2231 --squash && echo "note: gh pr merge 999 was the earlier plan"')" >/dev/null
unset STUB_LOG
ck "still denied" DENY "$LAST_VERDICT"
if grep -q 'pr view 2231 ' "$GREEDY_LOG"; then
    printf '  ok   the real merge selector (2231) was checked\n'; PASS=$((PASS + 1))
else
    printf '  FAIL the real merge selector (2231) was never checked\n'; FAIL=$((FAIL + 1))
fi
if grep -q '999' "$GREEDY_LOG"; then
    printf '  FAIL the trailing prose selector (999) was checked instead\n'; FAIL=$((FAIL + 1))
else
    printf '  ok   the trailing prose selector (999) was not checked\n'; PASS=$((PASS + 1))
fi

echo "== the denial carries what a reviewer needs =="
run "$(bash_json 'gh pr merge 2231 --squash')" >/dev/null
ck_reason "names the author"          "joshua-trustabl"
ck_reason "names you"                 "laurigates"
ck_reason "shows the association"     "FIRST_TIME_CONTRIBUTOR"
ck_reason "flags the CI path"         "CI executes this"
ck_reason "gives the human route"     "ghsq -x"
ck_reason "forbids self-serve bypass" "only honored from the operator"

echo "== executable-path flagging =="
STUB_FILES='README.md' run "$(bash_json 'gh pr merge 2231 --squash')" >/dev/null
case "$LAST_REASON" in
    *"EXECUTE"*) printf '  FAIL benign paths must not be flagged as executing\n'; FAIL=$((FAIL + 1)) ;;
    *) printf '  ok   benign paths not flagged as executing\n'; PASS=$((PASS + 1)) ;;
esac
STUB_FILES='hooks-plugin/hooks/x.sh' run "$(bash_json 'gh pr merge 2231 --squash')" >/dev/null
ck_reason "shell path flagged" "hooks-plugin/hooks/x.sh"

echo "== fails CLOSED when authorship cannot be established =="
# `run` called directly (not in $()) so $LAST_REASON survives for ck_reason.
STUB_VIEW_FAIL=1 run "$(bash_json 'gh pr merge 2231 --squash')" >/dev/null
ck "gh pr view fails"                      DENY "$LAST_VERDICT"
ck_reason "explains the unverifiable case" "Cannot verify"
ck "gh api user fails"     DENY "$(STUB_NO_ME=1 run "$(bash_json 'gh pr merge 2231 --squash')")"
# shellcheck disable=SC2016  # the literal $n must reach the hook unexpanded
run "$(bash_json 'for n in 1 2; do gh pr merge $n --squash; done')" >/dev/null
ck "shell-variable selector"         DENY "$LAST_VERDICT"
ck_reason "explains the loop case"   "shell variable"
# Case A (issue #2449): a LITERAL PR number but a shell-variable --repo/-R.
# `gh pr view` can't resolve `-R $R` either, but the old code switched only on
# $PR_SELECTOR (literal "464" here) and fell into the generic "bad PR number,
# wrong repo, or no network" branch — plausible-sounding but wrong, and its
# retry hint echoed the unexpanded `$R` straight back at the caller.
# shellcheck disable=SC2016  # the literal $R must reach the hook unexpanded
run "$(bash_json 'gh pr merge 464 -R $R --squash --delete-branch')" >/dev/null
ck "shell-variable --repo (case A)"        DENY "$LAST_VERDICT"
ck_reason "explains the repo case"         "shell variable"
case "$LAST_REASON" in
    *'bad PR number, wrong repo, or no network'*)
        printf '  FAIL case A got the generic "bad PR number" message, not the shell-variable one\n'
        FAIL=$((FAIL + 1)) ;;
    *) printf '  ok   case A did not get the generic message\n'; PASS=$((PASS + 1)) ;;
esac
# The old generic branch's retry hint was a literal copy-pasteable command —
# `gh pr view ${PR_SELECTOR:-} ${PR_REPO:+--repo $PR_REPO}` — which, given a
# variable --repo, rendered as `gh pr view 464 --repo $R`: a command that, run
# literally, still references an unexpanded (and out-of-scope) $R. The WHAT
# header ("Refusing to merge $R#464: ...") legitimately echoes the caller's
# text for identification — only a *suggested command* containing the raw
# variable is the bug this checks for.
case "$LAST_REASON" in
    *'--repo $R'*|*'gh pr view'*'$R'*)
        printf '  FAIL case A retry hint echoes the unexpanded $R as a runnable command\n'; FAIL=$((FAIL + 1)) ;;
    *) printf '  ok   case A retry hint does not echo unexpanded $R as a runnable command\n'; PASS=$((PASS + 1)) ;;
esac
unset STUB_AUTHOR STUB_NUM STUB_TITLE

echo "== operator escape hatch =="
out=$(printf '%s' "$(bash_json 'gh pr merge 2231 --squash')" \
      | STUB_AUTHOR=joshua-trustabl CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 \
        PATH="$TMPDIR/bin:$PATH" bash "$HOOK" 2>/dev/null || true)
if [ -z "$out" ]; then printf '  ok   env toggle disables the guard\n'; PASS=$((PASS + 1))
else printf '  FAIL env toggle did not disable the guard\n'; FAIL=$((FAIL + 1)); fi
# An INLINE prefix must NOT work — that is an agent self-serving the bypass.
ck "inline prefix does not bypass" DENY \
   "$(STUB_AUTHOR=joshua-trustabl run "$(bash_json 'CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 gh pr merge 2231 --squash')")"

echo
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
