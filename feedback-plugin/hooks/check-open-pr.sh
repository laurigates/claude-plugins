#!/usr/bin/env bash
# PreToolUse hook: warn before pushing to a branch that has an open PR.
#
# Installed as the deliverable for the friction-learner push:branch-has-open-pr
# cluster. Inspects Bash commands on stdin; if the command is `git push` against
# a branch that already has an open PR (and the last commit message does not
# contain `[force-push-ok]`), emits a PreToolUse JSON response asking the user
# to confirm before the push proceeds.
#
# Usage: configured under hooks.PreToolUse.matcher="Bash" in plugin.json.

set -uo pipefail

input_json=$(cat)

tool_name=$(printf '%s' "$input_json" | jq -r '.tool_name // empty')
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(printf '%s' "$input_json" | jq -r '.tool_input.command // empty')
if ! printf '%s' "$command" | grep -Eq '^[[:space:]]*git[[:space:]]+push\b'; then
  exit 0
fi

# Resolve target branch. A push command may include an explicit refspec like
# `git push origin feature/foo` or `git push origin HEAD:feature/foo`. Extract
# the destination side of any refspec; fall back to the current branch.
target_branch=""
# shellcheck disable=SC2162
read -ra tokens <<< "$command"
for ((i = 0; i < ${#tokens[@]}; i++)); do
  tok="${tokens[i]}"
  case "$tok" in
    git|push|-u|--set-upstream|--force|--force-with-lease|--force-with-lease=*|--tags|--follow-tags|--no-verify|--quiet|-q|--verbose|-v|--dry-run|-n|--atomic|--porcelain)
      continue
      ;;
    origin|upstream|--*)
      continue
      ;;
    *:*)
      target_branch="${tok#*:}"
      break
      ;;
    *)
      target_branch="$tok"
      break
      ;;
  esac
done

if [ -z "$target_branch" ]; then
  target_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
fi

if [ -z "$target_branch" ] || [ "$target_branch" = "HEAD" ]; then
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  exit 0
fi

open_pr=$(gh pr list --head "$target_branch" --state open --json number \
            --jq '.[0].number // empty' 2>/dev/null || echo "")
if [ -z "$open_pr" ]; then
  exit 0
fi

last_commit_msg=$(git log -1 --pretty=%B 2>/dev/null || echo "")
if printf '%s' "$last_commit_msg" | grep -q '\[force-push-ok\]'; then
  exit 0
fi

reason="Branch '${target_branch}' has open PR #${open_pr}. Confirm push is intended, or add [force-push-ok] to the commit message to skip this check."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $reason
  }
}'
exit 0
