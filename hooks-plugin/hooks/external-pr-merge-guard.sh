#!/usr/bin/env bash
# PreToolUse hook — refuses to let an agent merge a PR authored by someone other
# than the repo operator or a known bot.
#
# Why this exists: a public repo attracts drive-by PRs, and the merge tooling
# (both the human `ghsq`/`ghrb` wrappers and an agent's `gh pr merge`) is built
# for bulk-merging your OWN and bots' PRs. A stranger's PR riding that bulk
# reflex is merged code you never read — and PRs that add a workflow, a hook, or
# a shell script execute on merge. Vetting an external contribution is a human
# judgement call, so the agent path is closed and pointed at the human one.
#
# Behavior:
#   - `gh pr merge`, `gh api -X PUT .../pulls/N/merge`, and the GitHub MCP
#     merge_pull_request tool are checked.
#   - Author == the authenticated user, or a bot → allowed silently.
#   - Anyone else → denied, with the author, the association, and which touched
#     paths execute, plus the human command to run instead.
#   - Author cannot be determined (network, an unresolvable `$var` selector in a
#     loop, a bad PR number) → denied. "Can't verify" is not "safe".
#   - Any command that is not a merge → allowed, immediately.
#
# Deliberately does NOT defer to permission mode "auto" (unlike
# branch-protection.sh). Auto mode's classifier models destructive-git and
# protected-branch risk; it has no notion of PR *authorship trust*, so deferring
# would not be avoiding a double-gate, it would be leaving the gap open.
#
# Toggle: a human operator can export CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1
# in their shell environment. The toggle is only honored when set in the process
# environment — inline prefixes like
# `CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 gh pr merge 5` on the command line
# are intentionally NOT honored, so agents cannot self-serve the bypass.
#
# Matches: Bash, mcp__github__merge_pull_request
# Detects: gh pr merge / gh api PUT pulls/N/merge / MCP merge_pull_request
# Allows: your own PRs, bot PRs (release-please, renovate, dependabot, …), and
#         every non-merge command

set -euo pipefail

# Human-operator escape hatch: only honored from the process environment.
[ "${CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE:-}" = "1" ] && exit 0

command -v gh >/dev/null 2>&1 || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

deny() {
  local reason="$1" json_reason
  json_reason=$(printf '%s' "$reason" | jq -Rs .)
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$json_reason"
  exit 0
}

# ---------------------------------------------------------------------------
# Work out which PR (if any) this tool call would merge.
#   PR_SELECTOR — number / URL / branch, or empty to mean "current branch's PR"
#   PR_REPO     — OWNER/REPO, or empty for the repo at the cwd
# ---------------------------------------------------------------------------
PR_SELECTOR=""
PR_REPO=""

case "$TOOL_NAME" in
  mcp__github__merge_pull_request)
    PR_SELECTOR=$(printf '%s' "$INPUT" | jq -r '.tool_input.pullNumber // .tool_input.pull_number // empty')
    OWNER=$(printf '%s' "$INPUT" | jq -r '.tool_input.owner // empty')
    REPO=$(printf '%s' "$INPUT" | jq -r '.tool_input.repo // empty')
    [ -n "$OWNER" ] && [ -n "$REPO" ] && PR_REPO="$OWNER/$REPO"
    ;;
  Bash)
    COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
    [ -z "$COMMAND" ] && exit 0

    # Fast bail-out: the overwhelming majority of Bash calls are not merges.
    # Allow leading `VAR=value` assignments so an inline-bypass attempt is still
    # recognised as a merge rather than slipping past this filter.
    if ! printf '%s' "$COMMAND" | grep -Eq 'gh[[:space:]]+pr[[:space:]]+merge|pulls/[^/[:space:]]+/merge'; then
      exit 0
    fi

    # `gh api ... repos/O/R/pulls/N/merge` (any method; PUT is the merge verb,
    # but a bare `gh api <path>` on that route also merges via POST-less PUT
    # default in some wrappers, so don't gate on the method).
    API_PATH=$(printf '%s' "$COMMAND" | grep -oE 'repos/[^/[:space:]]+/[^/[:space:]]+/pulls/[0-9]+/merge' | head -1 || true)
    if [ -n "$API_PATH" ]; then
      PR_REPO=$(printf '%s' "$API_PATH" | awk -F/ '{print $2"/"$3}')
      PR_SELECTOR=$(printf '%s' "$API_PATH" | awk -F/ '{print $5}')
    else
      # Isolate the `gh pr merge` invocation: take everything after the literal
      # `merge`, stopping at the first shell operator so a trailing `&& echo ok`
      # cannot be mistaken for the PR selector.
      SEGMENT=$(printf '%s' "$COMMAND" \
        | sed -n 's/.*gh[[:space:]]\{1,\}pr[[:space:]]\{1,\}merge[[:space:]]*//p' \
        | sed 's/[;&|].*//' || true)

      # First positional token, skipping flags AND the values of the flags that
      # take one. Without the skip list, `gh pr merge --subject "feat: x" 5`
      # would read `feat:` as the PR selector and check the wrong (or no) PR.
      PR_SELECTOR=$(printf '%s\n' "$SEGMENT" | awk '
        BEGIN { split("-b --body -F --body-file -m --match-head-commit -R --repo -s --subject --author-email -t --title", v, " ")
                for (i in v) valued[v[i]] = 1 }
        { for (i = 1; i <= NF; i++) {
            if (skip)              { skip = 0; continue }
            if ($i ~ /^-/)         { if ($i in valued) skip = 1; continue }
            print $i; exit
        } }')
      # --repo/-R may appear either as a separate token or as --repo=OWNER/REPO.
      PR_REPO=$(printf '%s\n' "$SEGMENT" | awk '
        { for (i = 1; i <= NF; i++) {
            if (($i == "-R" || $i == "--repo") && (i + 1) <= NF) { print $(i+1); exit }
            if ($i ~ /^--repo=/) { sub(/^--repo=/, "", $i); print $i; exit }
        } }')
    fi
    ;;
  *)
    exit 0
    ;;
esac

# ---------------------------------------------------------------------------
# Resolve the author and classify.
# ---------------------------------------------------------------------------
# Every gh lookup below must run in the directory the tool call targets, so a
# `gh pr merge` with no --repo resolves the repo the agent is actually in. cd
# once here rather than wrapping each call in `cd "$GH_DIR" && gh … || true`,
# which folds a cd failure into the same `|| true` as a gh failure (SC2015).
GH_DIR="${HOOK_CWD:-.}"
[ -d "$GH_DIR" ] || GH_DIR="."
cd "$GH_DIR" || exit 0

ME=$(gh api user --jq '.login' 2>/dev/null || true)

VIEW_ARGS=()
[ -n "$PR_SELECTOR" ] && VIEW_ARGS+=("$PR_SELECTOR")
[ -n "$PR_REPO" ] && VIEW_ARGS+=(--repo "$PR_REPO")

META=$(gh pr view "${VIEW_ARGS[@]}" \
        --json number,title,author,url \
        --jq '[(.number|tostring), .author.login, (.author.is_bot|tostring), .title, .url] | @tsv' \
        </dev/null 2>/dev/null || true)

WHAT="${PR_REPO:+$PR_REPO}${PR_SELECTOR:+#$PR_SELECTOR}"
[ -z "$WHAT" ] && WHAT="the current branch's PR"

if [ -z "$META" ]; then
  case "$PR_SELECTOR" in
    *'$'*|*'`'*)
      deny "Refusing to merge ${WHAT}: the PR selector is a shell variable, so this hook cannot tell whose PR it is. Merges of PRs authored by anyone other than the repo owner or a bot are not permitted from an agent. Resolve the PR numbers first (gh pr list --json number,author) and merge them one literal number at a time — each will be checked individually." ;;
    *)
      deny "Refusing to merge ${WHAT}: could not read the PR's author (gh pr view returned nothing — bad PR number, wrong repo, or no network). 'Cannot verify' is not 'safe', so this is denied rather than allowed. Check the PR exists and is reachable (gh pr view ${PR_SELECTOR:-} ${PR_REPO:+--repo $PR_REPO}), then retry." ;;
  esac
fi

IFS=$'\t' read -r PR_NUM AUTHOR IS_BOT TITLE URL <<< "$META"

if [ -z "$ME" ]; then
  deny "Refusing to merge ${PR_REPO:-this repo}#${PR_NUM} (\"${TITLE}\"): could not determine the authenticated GitHub user (gh api user failed), so authorship cannot be checked against you. Denied rather than guessed. Fix gh auth (gh auth status) and retry."
fi

# A bot author renders differently depending on which gh subcommand produced it:
# `gh pr view` gives is_bot=true with login "app/<name>"; the search API gives
# is_bot=false with a "<name>[bot]" login. Accept every spelling — missing one
# would flag release-please/renovate/dependabot as strangers and make this guard
# noise that gets disabled.
IS_TRUSTED=0
[ "$AUTHOR" = "$ME" ] && IS_TRUSTED=1
[ "$IS_BOT" = "true" ] && IS_TRUSTED=1
case "$AUTHOR" in *'[bot]'|app/*) IS_TRUSTED=1 ;; esac

[ "$IS_TRUSTED" = "1" ] && exit 0

# ---------------------------------------------------------------------------
# External author — build a denial that carries the facts a reviewer needs.
# ---------------------------------------------------------------------------
SLUG="$PR_REPO"
if [ -z "$SLUG" ]; then
  SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

ASSOC=""
if [ -n "$SLUG" ]; then
  ASSOC=$(gh api "repos/$SLUG/pulls/$PR_NUM" --jq '.author_association' </dev/null 2>/dev/null || true)
fi

# Which touched paths actually execute something? That is the difference between
# "a typo fix" and "code that runs in CI or on the operator's machine".
RISKY=$(gh pr view "${VIEW_ARGS[@]}" --json files --jq '.files[].path' </dev/null 2>/dev/null \
  | awk '
      /^\.github\/(workflows|actions)\// { print "    " $0 "  (CI executes this)"; next }
      /\.(sh|bash|zsh)$/                 { print "    " $0 "  (shell)"; next }
      /(^|\/)hooks\//                    { print "    " $0 "  (hook — runs on the operator machine)"; next }
      /(^|\/)\.claude\//                 { print "    " $0 "  (Claude Code config / permissions)"; next }
      /^(package\.json|pyproject\.toml|Cargo\.toml|mise\.toml|[jJ]ustfile|Makefile|Dockerfile|\.pre-commit-config\.yaml)$/ { print "    " $0 "  (build / tooling entry point)"; next }
    ' || true)

REASON="Refusing to merge ${SLUG:-this repo}#${PR_NUM} — it was written by someone else.

  PR       ${SLUG:-?}#${PR_NUM}  \"${TITLE}\"
  author   ${AUTHOR}${ASSOC:+  (${ASSOC})}
  you      ${ME}
  ${URL}"

if [ -n "$RISKY" ]; then
  REASON="${REASON}

  This PR touches paths that EXECUTE:
${RISKY}"
fi

REASON="${REASON}

Vetting an outside contribution is a human judgement call, so an agent does not merge it. Do this instead:
  1. Review it and report what it actually changes — read the diff (gh pr diff ${PR_NUM}${SLUG:+ --repo $SLUG}), and for any added CI action or dependency, say where the code comes from, whether the ref is pinned to a commit SHA or a mutable tag, and what it downloads or sends at runtime.
  2. Leave the merge to the user: 'ghsq -x' shows external PRs and requires a typed confirmation, or 'gh pr merge ${PR_NUM}${SLUG:+ --repo $SLUG} --squash --delete-branch' run by them.

Do not retry with different flags or a different merge route — this hook checks them all. Do not prefix CLAUDE_HOOKS_DISABLE_EXTERNAL_PR_MERGE=1 onto the command; it is only honored from the operator's own shell environment. See .claude/rules/handling-blocked-hooks.md."

deny "$REASON"
