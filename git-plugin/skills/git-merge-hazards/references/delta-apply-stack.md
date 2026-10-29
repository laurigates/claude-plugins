# Delta-Apply: Land a Child's Own Diff on `main`

Detail for the delta-apply bullet in [§2 of SKILL.md](../SKILL.md#2-merging-a-stacked-base-auto-closes-the-child-pr).
Open this file when a PR shows `CONFLICTING` against `main` after another PR it
shares files with was squash-merged, and no force-push is wanted.

The route rebuilds the child as `main` plus the child's own diff, records the
result as a merge commit whose first parent is the reviewed head, and pushes it
as a fast-forward. Only lines that both the child and `main` changed can
conflict, so every conflict left is a genuine overlap.

## When to use it instead of Case A/B

[no-force-push-stack.md](no-force-push-stack.md) merges `main` into the child
and resolves conflicts to the child's side. That is lossless only when the child
contains its base's final head, which its Classify step checks. Two shapes fail
that check:

- **The child forked from an older head of its base.** The base gained commits
  after the fork, and its squash carries them to `main`. Where a later base
  commit edits a line an earlier one also edited, the merge conflicts in a file
  the child never touched after its fork, and the child's side of that conflict
  is the older base text. Taking it reverts the base's later commit, and the
  child-tip gates do not see the loss.
- **An independent PR touches files that a just-merged PR also changed.** There
  is no base and no squash to classify.

Delta-apply handles both, and it also handles the shape Case A/B covers: when
the child contains its base's final head, it produces the result Case B
produces, and checks it with one comparison.

> 2026-10-21 (`laurigates/mcu-tinkering-lab`, a 4-PR stack plus 2 independent
> PRs, squash-only, `deleteBranchOnMerge` on): #819 was built on #818's final
> head, and resolving every conflict to its side was lossless. #822 forked from
> #819 before #819 gained later commits. Its merge with `main` conflicted in 9
> files that #822 never changed after the fork, and taking #822's side there
> would have reverted those commits. Delta-apply landed all six PRs without a
> force-push.

## Pick the fork point

The patch must be the PR's own diff, so the fork point is the base side of the
PR's three-dot diff:

| PR | Fork point |
|---|---|
| Independent (based on `main`) | `git merge-base <child-head> origin/main` |
| Stacked, base already squash-merged | `git merge-base <child-head> <base-pre-squash-tip>` |

For a stacked child that merged its base's last head into itself,
`git merge-base --is-ancestor <base-head> <child-head>` succeeds and the second
row returns that head. For a child that forked from an older base head, it
returns the older head, which is what keeps the base's later commits out of the
patch. Record `<base-pre-squash-tip>` before the base merges, as the Record step
in [no-force-push-stack.md](no-force-push-stack.md#record-before-merging-the-base)
does: the branch is deleted on merge.

Retarget a stacked child to `main` before its base merges (§2's ordering).

## The route

Set `child_head` to the reviewed head as a full 40-hex SHA copied from command
output (`gh pr view <n> --json headRefOid`), and `fork` from the table. Run the
block in one shell call, from the repository, with a fresh `<dir>` and a patch
path outside it:

```bash
set -e
: "${child_head:?}" "${fork:?}"
git fetch -q origin main
main=$(git rev-parse origin/main)
git worktree add --detach <dir> "$main"
git diff --no-ext-diff --no-color --no-textconv --ignore-submodules=none --submodule=short --binary "$fork" "$child_head" > <patch>
git -C <dir> apply --3way --index <patch>       # a conflict exits non-zero and leaves markers
pid() { git -C <dir> patch-id --stable | cut -d' ' -f1; }
ours=$(git -C <dir> diff --no-ext-diff --no-color --no-textconv --ignore-submodules=none --submodule=short -U0 --cached "$main" | pid)
theirs=$(git -C <dir> diff --no-ext-diff --no-color --no-textconv --ignore-submodules=none --submodule=short -U0 "$fork" "$child_head" | pid)
[ "$ours" = "$theirs" ]
```

The diff flags are the ones Classify uses, written out because zsh does not
word-split an unquoted variable. They serve the same purpose there: an operator's
`diff.external`, `color.ui=always` or a textconv driver would rewrite the patch.
`--binary` writes full blob IDs, which `--3way` needs to find each preimage.

The last line is the check. Its two sides are the result's diff against `main`
and the child's own diff, and equal patch-ids mean the same added and removed
lines in the same files. `-U0` matters: patch-id hashes context lines, so with
the default three lines of context a `main` edit near one of the child's hunks
changes the hash although the child's change landed intact. A match proves the
result is `main` plus exactly the child's diff. Like Classify's content lines, it
is blind to a line moved within a file.

When `apply` reports `Applied patch to '<file>' with conflicts`, `set -e` stops
the block there. Resolve each marked file by hand, since these are lines both
sides changed, then `git -C <dir> add -- <file>`. A hand resolution changes the result's diff by
construction, so the patch-id check no longer holds and the project's gates
carry the verification.

> In the same session, every stacked PR passed the patch-id check (one at 36
> files) without a hand resolution. #821 (independent) needed two additive
> unions, a justfile recipe block and a test's allowed-module list, and #820 one,
> a SKILL.md paragraph both sides extended. The test suites verified those three.

## Commit, push, merge

Run the project's gates in `<dir>` first. Then build the merge commit with the
reviewed head as first parent, so the push is a fast-forward and needs no force:

```bash
set -e
T=$(git -C <dir> write-tree)
C=$(git commit-tree "$T" -p "$child_head" -p "$main" -m "Merge origin/main into <child>")
git push origin "${C}:refs/heads/<child>"
```

Brace the variable: unbraced, zsh reads the `:r` of `refs/` as a history
modifier and sends a mangled refspec. The full table is in
[stacked-chain-push.md](stacked-chain-push.md).

Wait for CI with the rollup gate in [stacked-chain-push.md](stacked-chain-push.md),
with `sha` set to `$C`, run the guard in [serial-merge-chain.md](serial-merge-chain.md),
then merge pinned to the pushed head:

```bash
gh pr merge <n> -R <owner>/<repo> --squash --delete-branch --match-head-commit "$C"
```

`--match-head-commit` compares the full SHA. In the session, a SHA retyped from
its 8-character prefix came out wrong, and the merge refused it with `Head
branch was modified`. Copy SHAs from command output, or keep them in variables
within one shell call.

Remove the worktree with `git worktree remove <dir>` once the push succeeds.

## If the push is rejected

A bot can push to the child between the read and the push. In the session,
`auto-resolve-conflicts.yml` (`github-actions[bot]`) pushed its own merge of
`main` into one child, and the push failed as non-fast-forward. Compare trees,
not diffs, with `C` set to the pushed SHA:

```bash
git fetch -q origin <child>
[ "$(git rev-parse "${C}^{tree}")" = "$(git rev-parse "origin/<child>^{tree}")" ]
```

Equal trees mean the bot's head carries exactly the verified content. Merge
pinned to the bot's head (`--match-head-commit` with `git rev-parse origin/<child>`),
after the [serial-merge-chain.md](serial-merge-chain.md) guard. That guard
refuses the bot's merge commit too: a workflow's commit carries the bot's own
committer, not `noreply@github.com`, so only the equal-tree check clears it.
Take the guard's review timestamp after that check. A different tree means the
bot changed content: start again from the new head.

## Why these merges squash

Each child carries the merge commit this recipe creates, and rule 4 of the
merge-method decision rule sends any branch with a merge commit to squash
(`github-pr-title` → [merge-strategies.md](../../github-pr-title/merge-strategies.md)).
The repo also had merge commits disabled (`mergeCommitAllowed: false`), so the
stack could not be merged top-down with merge commits. Squashing each PR in
turn keeps one conventional commit per PR on `main`, which is what
release-please reads.
