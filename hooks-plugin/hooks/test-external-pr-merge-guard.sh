#!/usr/bin/env bash
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
case "$args" in
  "api user --jq .login")
      [ -n "${STUB_NO_ME:-}" ] && exit 1
      printf '%s\n' "${STUB_ME-laurigates}" ;;
  "repo view --json nameWithOwner"*)
      printf '%s\n' "${STUB_SLUG-laurigates/claude-plugins}" ;;
  *"--json number,title,author,url"*)
      [ -n "${STUB_VIEW_FAIL:-}" ] && exit 1
      # Real `gh pr view '$n'` cannot resolve an unexpanded shell variable —
      # model that, or the loop case would look resolvable and the test would
      # assert against the wrong denial path.
      case "$args" in *'$'*) exit 1 ;; esac
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

echo "== non-merge commands are untouched =="
ck "git status"            ALLOW "$(run "$(bash_json 'git status')")"
ck "gh pr view"            ALLOW "$(run "$(bash_json 'gh pr view 42')")"
ck "gh pr list"            ALLOW "$(run "$(bash_json 'gh pr list --json number')")"
ck "gh pr create"          ALLOW "$(run "$(bash_json 'gh pr create --title x')")"
ck "unrelated tool"        ALLOW "$(run '{"tool_name":"Read","tool_input":{"file_path":"/x"}}')"

echo "== trusted authors merge freely =="
ck "own PR"  ALLOW "$(STUB_AUTHOR=laurigates run "$(bash_json 'gh pr merge 42 --squash')")"
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

echo "== a flag VALUE is not mistaken for the PR selector =="
# Without the value-flag skip list, `--subject "feat: x"` would be read as the
# selector, checking the wrong PR (or none) and letting the merge through.
ck "--subject with a value"  DENY "$(run "$(bash_json 'gh pr merge --squash --subject "feat: x" 2231')")"
ck "-b with a value"         DENY "$(run "$(bash_json 'gh pr merge --squash -b "body text" 2231')")"

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
