#!/usr/bin/env bash
# PreToolUse hook for Bash tool - blocks `gh pr merge` with the wrong method
#
# Runs scripts/pr-merge-method.py (the rebase-vs-squash rule table in
# skills/github-pr-title/merge-strategies.md) for each `gh pr merge` in the
# command. When the command's --squash/--rebase/--merge disagrees with the
# script's METHOD, it blocks with the reason and the corrected command.
#
# Why a block and not a nudge (.claude/rules/hook-block-vs-nudge.md): a merge
# writes the default branch, and the method cannot be changed afterwards —
# squashing a multi-concern PR, or rebasing one full of fixups, is permanent.
# The block is never a dead end: the corrected command is in the message, and a
# human-applied `merge:squash` / `merge:rebase` label overrides the rule (the
# script reports it as METHOD with OVERRIDE=<label>).
#
# Fail-open: no python3, no gh, an unreadable PR, or STATUS=ERROR from the
# script all exit 0. This hook enforces a convention on top of a merge the user
# already asked for; it must not stop that merge because GitHub is unreachable.
#
# Not covered: `gh api -X PUT …/pulls/N/merge` and the MCP merge tool. Both are
# rare in agent sessions and are already gated by hooks-plugin's
# external-pr-merge-guard.sh.
#
# PR_MERGE_METHOD_CMD overrides the decision command (tests point it at a stub).

set -euo pipefail

block() {
    echo "$1" >&2
    exit 2
}

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$COMMAND" ] || exit 0

# Cheap prefilter: every merge invocation spells both words.
if ! grep -q 'gh' <<<"$COMMAND" || ! grep -q 'merge' <<<"$COMMAND"; then exit 0; fi

SEP=$'\001'
HITS=()  # one SOH-terminated argument list per `gh pr merge`, -R first when given
PC_LIB_MISSING=0
# shellcheck source=git-plugin/hooks/lib/parsed-commands.sh
. "$(dirname "$0")/lib/parsed-commands.sh" 2>/dev/null || PC_LIB_MISSING=1
if [ "$PC_LIB_MISSING" = 0 ] && pc_scan "$COMMAND"; then
    pc_find_gh_pr_merge || exit 0
    for k in "${!PC_HIT_ARGS[@]}"; do
        pre=""
        [ -z "${PC_HIT_C[k]}" ] || pre="-R${SEP}${PC_HIT_C[k]}${SEP}"
        HITS+=("${pre}${PC_HIT_ARGS[k]}")
    done
else
    # No parser: split each `gh pr merge …` segment on whitespace, up to the next
    # shell separator. Quoted values with spaces (--body "…") may mis-split, but
    # only the method flag, -R and the selector are read.
    while IFS= read -r seg; do
        [ -n "$seg" ] || continue
        HITS+=("$(printf '%s\n' "$seg" | tr -s ' \t' '\n' | tr -d "\"'" | tr '\n' "$SEP")")
    done < <(printf '%s' "$COMMAND" | perl -ne '
        while (/(?:^|[\s;&|(])gh\s+pr\s+((?:-R\s+\S+\s+)?merge\b[^;&|\n]*)/g) {
            my $s = $1; $s =~ s/^(-R\s+\S+\s+)?merge\s*/$1/; print "$s\n";
        }' 2>/dev/null || true)
fi
[ "${#HITS[@]}" -gt 0 ] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0
DECIDE=${PR_MERGE_METHOD_CMD:-"$(dirname "$0")/../scripts/pr-merge-method.py"}

for hit in "${HITS[@]}"; do
    repo="" sel="" flag=""
    args=()
    while IFS= read -r -d "$SEP" a; do args+=("$a"); done <<<"$hit"
    i=0
    while [ "$i" -lt "${#args[@]}" ]; do
        a=${args[i]}
        case $a in
            -s | --squash) flag=squash ;;
            -r | --rebase) flag=rebase ;;
            -m | --merge) flag=merge ;;
            --disable-auto) flag="" && break ;;
            -R | --repo) repo=${args[i + 1]:-} && i=$((i + 1)) ;;
            --repo=*) repo=${a#--repo=} ;;
            -b | --body | -F | --body-file | -t | --subject | -A | --author-email | --match-head-commit)
                i=$((i + 1)) ;;
            -*) ;;
            *) [ -n "$sel" ] || sel=$a ;;
        esac
        i=$((i + 1))
    done
    # No method flag: gh prompts (or errors without a TTY); nothing to compare.
    [ -n "$flag" ] || continue

    dargs=()
    [ -z "$repo" ] || dargs+=(--repo "$repo")
    [ -z "$sel" ] || dargs+=(--pr "$sel")
    out=$(cd "${CWD:-.}" 2>/dev/null && "$DECIDE" ${dargs[@]+"${dargs[@]}"} 2>/dev/null) || continue
    method=$(sed -n 's/^METHOD=//p' <<<"$out")
    case $method in rebase | squash) ;; *) continue ;; esac
    [ "$flag" != "$method" ] || continue

    pr=$(sed -n 's/^PR=//p' <<<"$out")
    number=${pr##*#}
    reason=$(sed -n 's/^REASON=//p' <<<"$out")
    detail=$(sed -n 's/^DETAIL=//p' <<<"$out")
    override=$(sed -n 's/^OVERRIDE=//p' <<<"$out")
    lint=$(sed -n 's/^BODY_LINT=//p' <<<"$out")
    fixed=$(printf '%s' "$COMMAND" | perl -pe "s/(?<=\\s)(--squash|--rebase|--merge|-s|-r|-m)(?=\\s|\$)/--$method/")
    note=""
    if [ "$method" = squash ] && [ "${lint:-0}" != 0 ]; then
        note="
The squash body is the PR body (squash_merge_commit_message=PR_BODY), and it has
$lint lint finding(s): $(grep '^LINT_' <<<"$out" | tr '\n' ' ' || true)
Fix it with gh pr edit $number --body-file <file> before merging."
    fi
    if [ "$override" != none ]; then
        why="the $override label on $pr overrides the rule table"
    else
        why="rule: $reason — $detail"
    fi
    escape="If the user explicitly asked for --$flag, label the PR to record that choice,
then re-run the original command:
  gh pr edit $number${repo:+ -R $repo} --add-label merge:$flag"
    # Merge commits have no override label: the rollout disables them per repo.
    [ "$flag" != merge ] || escape="Merge commits are not one of the two methods; there is no label for them."
    block "MERGE METHOD: $pr should be merged with --$method, not --$flag.
$why

Run instead:
  $fixed
$note
$escape
Rule table: git-plugin/skills/github-pr-title/merge-strategies.md"
done
exit 0
