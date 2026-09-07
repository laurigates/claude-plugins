#!/usr/bin/env bash
# PreToolUse hook: steer an unconditional force push to an open PR's branch
# toward --force-with-lease.
#
# Installed as the deliverable for the friction-learner push:branch-has-open-pr
# cluster. Inspects Bash commands on stdin; if the command force-pushes
# *unconditionally* (`--force` / `-f` / a leading `+` refspec) to a branch that
# already has an open PR, and the last commit message does not carry
# `[force-push-ok]`, it denies the call and tells the model to use
# `--force-with-lease` instead.
#
# Why deny rather than ask
# ------------------------
# `permissionDecision: "ask"` renders a confirmation prompt for the *human*: the
# model never sees permissionDecisionReason, and a "No" reaches the agent as a
# bare permission denial that ends its turn. `deny` is the agent-facing channel
# — the reason is fed back as tool feedback, so the model reads the remedy and
# retries on its own. Since the remedy here is mechanical (swap one flag), the
# decision belongs to the agent and no human needs to be in the loop.
#
# Why --force-with-lease passes silently
# --------------------------------------
# The lease *is* the check this hook used to ask a human to perform: git refuses
# the push when the remote ref moved since the last fetch, so a force-with-lease
# cannot silently discard commits pushed to the PR by a reviewer, a bot, or a
# coworker agent. Prompting on top of it gates nothing.
#
# A plain (fast-forward) push to an open PR is the normal workflow — adding
# commits to a PR is what a PR is for — so it passes silently too. An earlier
# version gated every push and never inspected --force at all, treating a
# history rewrite and a fast-forward identically; that fired on nearly every
# push while doing no safety work. See `.claude/rules/hook-block-vs-nudge.md`
# for the litigation test this applies.
#
# Usage: configured under hooks.PreToolUse.matcher="Bash" in plugin.json.

set -uo pipefail

input_json=$(cat)

tool_name=$(printf '%s' "$input_json" | jq -r '.tool_name // empty')
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

command=$(printf '%s' "$input_json" | jq -r '.tool_input.command // empty')

# A push is frequently one statement of a compound command (`git push … 2>&1 |
# tail -5 && git rev-parse HEAD`). Split on statement separators and keep the
# first `git push` segment, so positional parsing below sees only its own args.
push_segment=""
while IFS= read -r segment; do
  if printf '%s' "$segment" | grep -Eq '^[[:space:]]*git[[:space:]]+push([[:space:]]|$)'; then
    push_segment="$segment"
    break
  fi
done <<< "$(
  # Pure-bash separator normalisation: BSD sed emits a literal 'n' for \n in a
  # s/// replacement, so `sed -E 's/\|/\n/'` would corrupt this on macOS.
  # Two-char operators first, so the leftover single '|' is a real pipe.
  norm="${command//&&/$'\n'}"
  norm="${norm//||/$'\n'}"
  norm="${norm//;/$'\n'}"
  printf '%s' "${norm//|/$'\n'}"
)"

if [ -z "$push_segment" ]; then
  exit 0
fi

# shellcheck disable=SC2162
read -ra tokens <<< "$push_segment"

# Classify the force spelling before any `gh` call, so a non-force push pays
# nothing. `--force-with-lease` / `--force-if-includes` are conditional and
# safe; bare `--force`, a short bundle containing `f` (`-f`, `-fu`, `-uf`), and
# a leading `+` on a refspec all overwrite unconditionally.
is_unconditional_force=0
for tok in "${tokens[@]}"; do
  case "$tok" in
    --force-with-lease|--force-with-lease=*|--force-if-includes|--force-if-includes=*)
      ;;
    --force)
      is_unconditional_force=1
      ;;
    --*)
      ;;
    -*f*)
      is_unconditional_force=1
      ;;
    +*)
      is_unconditional_force=1
      ;;
  esac
done

if [ "$is_unconditional_force" -eq 0 ]; then
  exit 0
fi

# Resolve the target branch from the positional arguments. `git push [remote]
# [refspec...]`: first positional is the remote, second the refspec. Skip flags
# and shell redirections — enumerating known flags instead would let an unlisted
# one (`-f`) be mistaken for the branch name.
positionals=()
for tok in "${tokens[@]}"; do
  case "$tok" in
    git|push) continue ;;
    -*) continue ;;
    *'>'*|*'<'*|'&'*) continue ;;
    *) positionals+=("$tok") ;;
  esac
done

target_branch=""
if [ "${#positionals[@]}" -ge 2 ]; then
  refspec="${positionals[1]}"
  refspec="${refspec#+}"          # force marker, already classified above
  target_branch="${refspec#*:}"   # destination side; whole token when unqualified
  target_branch="${target_branch#refs/heads/}"
fi

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

# Escape hatch for a deliberate unconditional overwrite. Deliberately keyed on
# the commit message rather than the command: the model cannot set it without
# rewriting a commit, so it stays a human decision
# (`.claude/rules/handling-blocked-hooks.md` — do not self-serve a bypass).
last_commit_msg=$(git log -1 --pretty=%B 2>/dev/null || echo "")
if printf '%s' "$last_commit_msg" | grep -q '\[force-push-ok\]'; then
  exit 0
fi

# Addressed to the model: with permissionDecision "deny" this string comes back
# as tool feedback, so it names the remedy rather than asking a question.
reason="Unconditional force push to '${target_branch}', which has open PR #${open_pr}. This overwrites any commit pushed to the branch since your last fetch (reviewer suggestion, CI auto-fix, coworker agent) with no way to recover it from the remote. Re-run with --force-with-lease instead: it performs the same rewrite but refuses if the remote ref moved. If the lease then fails, fetch and inspect what landed rather than forcing over it."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
