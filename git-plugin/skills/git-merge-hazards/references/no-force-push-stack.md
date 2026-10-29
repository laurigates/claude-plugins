# No-Force Stacked Merges

Detail for the no-force alternative in [§2 of SKILL.md](../SKILL.md#2-merging-a-stacked-base-auto-closes-the-child-pr).
Open this file when a child PR builds only on its base and `main` may have moved
since the stack started.
When the child forked from an older head of its base, or the PR is independent
of any base, use [delta-apply-stack.md](delta-apply-stack.md) instead.

The route merges `main` into the child without a force-push. Its safety rests on
one classification. `-X ours` silently drops a change from `main` whenever that
change touches a line the child also edited, and the child-tip gate cannot see
the loss. So the route first decides whether `main` contributed anything the
child lacks, and only then picks the merge. Both Case A chains start with the
route guard, so they refuse unless `route` is `A`. The Case B block runs under
`set -e`. Every merge passes `--no-ff`, so an operator's `merge.ff=only` cannot make
one refuse. No chain pushes unless its gates hold.

The route squash-merges the base: Classify compares the one squash commit's
tree with the base's pre-squash tip. The child then carries a merge of `main`,
so it squashes too (rule 4 in `github-pr-title` →
[merge-strategies.md](../../github-pr-title/merge-strategies.md)). When the
merge-method script recommends rebase for the base, use the rebase path in
SKILL.md §2 instead of this route.

## Check the base first

Retargeting first strands the child on `main` when the base refuses to merge, so
read the base's state before starting the route:

```bash
gh pr view <base> --json state,mergeStateStatus,mergeable
```

| Field | Proceed on | Stop on |
|---|---|---|
| `state` | `OPEN` | any other value, including `MERGED` and `CLOSED` |
| `mergeable` | `MERGEABLE` | `CONFLICTING` |
| `mergeStateStatus` | `CLEAN`, `HAS_HOOKS`, `UNSTABLE` | `BEHIND`, `DIRTY`, `BLOCKED`, `DRAFT` |

GitHub computes `mergeable` and `mergeStateStatus` asynchronously. A field that
reads `UNKNOWN` is not a stop yet: re-read it after a short wait, at most three
times, then stop. A merged PR keeps reporting `UNKNOWN`, so the bound matters.

## Record before merging the base

Record the base's pre-squash tip and the child's approved head before anything can
push to the child. Read the tip first, then fetch it, then check that the local
object store holds it. Merging with `--delete-branch` removes the base branch, so
`pre` survives only as a local object. A push to the base between a fetch and a
read that followed it would leave `pre` absent locally:

```bash
pre=$(gh pr view <base> --json headRefOid --jq .headRefOid)
git fetch -q origin <base>
git cat-file -e "${pre}^{commit}"
reviewed_tip=$(gh pr view <child> --json headRefOid --jq .headRefOid)
gh pr edit <child> --base main
gh pr merge <base> --squash --delete-branch --match-head-commit "$pre"
squash=$(gh pr view <base> --json mergeCommit --jq .mergeCommit.oid)
```

If `cat-file` fails, stop before the merge. GitHub keeps the base PR's head as
`refs/pull/<base PR number>/head` after the branch is deleted, so
`git fetch origin pull/<base PR number>/head` recovers `pre` first.

Read `squash` after the merge: `mergeCommit` is null until then. The shell does
not keep variables between Bash calls. Print `pre`, `reviewed_tip` and `squash`,
and pass them to later calls as literal values. `tip` is set in the
[Re-read](#re-read-the-child-before-any-gate), which
runs in the same shell call as Classify and the Case block that reads it.
Do not re-read `reviewed_tip` later: a bot may have moved the child's head by
then, and the new read would record the bot's commit as the reviewed one.

## Re-read the child before any gate

Retargeting can trigger a bot push within minutes. In one observed stack,
`auto-resolve-conflicts.yml` (`github-actions[bot]`) merged an older `main` into
the child after `gh pr edit --base main`. Read the child head again before any
gate, and use the tip it returns for everything that follows:

```bash
git fetch -q origin main <child>
tip=$(git rev-parse "origin/<child>")
```

Then confirm the child is still an open PR, using the PR state rather than ancestry
(the authoritative signal in SKILL.md §1):

```bash
gh pr list --state all --head <child> --json number,state --jq 'sort_by(.number) | .[-1].state // empty'
```

A branch can have had several PRs, so the newest, by number, decides. Only `OPEN`
continues. A `MERGED` or `CLOSED` child is the stale-branch case: stop, and push
nothing to its branch.

## Classify

```bash
: "${pre:?}" "${squash:?}" "${reviewed_tip:?}" "${tip:?}"
ahead=$(git rev-list --count "${squash}..origin/main")
tree_squash=$(git rev-parse "${squash}^{tree}")
tree_pre=$(git rev-parse "${pre}^{tree}")
reviewed=$(git diff --no-ext-diff --no-color -U0 --ignore-submodules=none --submodule=short --no-textconv --output-indicator-new='>' --output-indicator-old='<' "${pre}...${reviewed_tip}" -- <source paths> | grep -E '^[<>]')
meta_of() { # meta_of <dir> <range...>: the raw listing of a change, one line per path
    git -C "$1" diff --no-ext-diff --no-color --ignore-submodules=none --no-textconv --no-renames --no-abbrev --raw --numstat "${@:2}" \
      | awk -F'\t' '
          /^:/ { split($1, f, " "); st[$2] = f[5] (f[2] != substr(f[1], 2) ? " modechange" : ""); bl[$2] = f[4]; ord[++n] = $2; next }
          $1 == "-" { bin[$3] = 1 }
          END { for (i = 1; i <= n; i++) { p = ord[i]; printf "%s %s", st[p], p; if (p in bin) printf " %s", bl[p]; print "" } }'
}
reviewed_meta=$(meta_of . "${pre}...${reviewed_tip}" -- <source paths>)
route=B
if [ "$ahead" -eq 0 ] && [ "$tree_squash" = "$tree_pre" ] \
  && git merge-base --is-ancestor "$squash" origin/main \
  && git merge-base --is-ancestor "$pre" "$tip" && [ "$tip" = "$reviewed_tip" ]; then
  route=A
fi
```

`route` is `A` only when all five hold: `ahead` is `0`, the two trees are equal,
`origin/main` contains the squash, the child tip contains the pre-squash tip, and
the child tip is still the reviewed head. Anything else is `B`. Each condition
closes a shape the others miss:

- A count of zero rules out a later change from `main`.
- Tree identity rules out a squash that carried more than the base.
- Containment of the squash rules out a stale `origin/main`. A read that lags
  behind the squash also gives `ahead` of `0`, so the count alone cannot tell
  "main gained nothing" from "main has not caught up yet". Case B's first check
  applies the same test.
- Ancestry rules out a base that moved after the child branched. The squash then
  carries base content the child never saw. `-X ours` keeps the child's side on
  the shared lines and drops that content, and the child-tip gate still passes.
- The unmoved-tip check rules out a bot commit that changed the baseline after
  review.

Run Classify in the same shell call as the block that uses it. `$route`,
`$reviewed`, `$reviewed_meta`, `$tip`, the tree SHAs and the `meta_of` function
do not persist between Bash calls. The block's first line stops it when a ref is
unset or empty, so no route is assigned from a missing SHA.

`reviewed` is the child's own change as the PR showed it at review time: the
diff from the merge-base of the pre-squash tip and the approved head, to that
head. GitHub's PR diff uses that baseline (`base...head`), so a `main` change the
base carried in, which the child never had, is not part of it. The approved head
comes from the Record block, so a bot commit cannot enter the baseline. The grep
keeps only the lines the indicators mark. `--output-indicator-new` and
`--output-indicator-old` print content lines with `>` and `<`, where a diff
prints `+` and `-`. A header keeps `+++` and `---`, so no header carries either
mark. So `^[<>]` keeps every content line, including markdown bullets and YAML
items, and no header. A removed line whose text starts with `-- a/` prints as
`<-- a/` and stays in the comparison. Case B step 4 compares against it.

Both content diffs pass `--no-ext-diff --no-color -U0`, then
`--ignore-submodules=none --submodule=short --no-textconv`. Porcelain `git diff`
honours the operator's `diff.external` (difftastic's documented setup) and
`color.ui=always`. Either one rewrites the output so the `^[<>]` filter matches
nothing on both sides, and step 4 would compare an empty string with an empty
string and pass, which lets a bot's unreviewed line through. A committed
`.gitmodules` with `ignore = all`, or `diff.ignoreSubmodules=all`, hides a
gitlink change from the diff, and `diff.submodule=log` prints one as a commit
log that the filter drops. `diff.<driver>.textconv` can rewrite text the same way.
The flags switch all of these off, for both content diffs and the raw listing.

The empty-diff gates compare tree SHAs, never diff output, so no setting that
changes a diff can make an empty change look empty. Each gate compares two trees
with `git rev-parse '^{tree}'`, or the resolved index with `git write-tree`.
`diff --quiet` is not used. A committed `ignore = all` hides a gitlink change
from `git diff --quiet`, even with `--no-ext-diff`, so a child that reverts the
base's submodule bump gets the bump re-applied by `-X ours` and pushed. A
`--quiet` diff that allows external drivers is also exposed to
`diff.trustExitCode` (git 2.46+) or `GIT_EXTERNAL_DIFF_TRUST_EXIT_CODE`, which
make it return the exit code of a `diff.external` helper.

`<source paths>` is the pathspec that both `reviewed` and step 4 compare over. Bind
it to the whole tree (`.`) unless the review was scoped to named paths. A narrower
set limits both comparisons to those paths, so a change to any other path passes
both of them unseen. Case B step 2's gates then carry the other paths, because
they compare the whole tree with the child.

The content lines are blind to four kinds of change, and the raw listing covers
the first three. A binary file prints `Binary files ... differ`, which begins
with neither `+` nor `-`. A mode-only change prints `old mode` and `new mode`
headers, and a rename prints `rename from` and
`rename to`. The filter drops every one of these, so the content comparison in step 4
passes a change made only of one of them. `reviewed_meta` records the same change as
a raw listing. `--raw` gives each path's status and mode, `--numstat` marks a binary
path with `-`, and `--no-renames` splits a rename into a delete and an add, so a
rename-only change shows on the side that made it. Each line is the status,
`modechange` where the mode differs, and the path. A binary path also carries its blob
SHA. A text path does not, on purpose: a clean merge of a `main` edit into the same
file changes that file's blob while leaving the child's own change exactly as reviewed,
so a blob comparison would refuse a valid route. A binary cannot merge that way, so its
blob is an exact check. Step 4 compares the listing against `reviewed_meta`, next to
the content lines.

The fourth kind is a line relocation within a file. A line the child added, which
a bot then moves elsewhere in the same file, prints as the same `>` line, so the
content lines do not change. The raw listing records only the file's status and
mode, which a move leaves alone, so nothing in the route sees the move. The guard
in [serial-merge-chain.md](serial-merge-chain.md) refuses any commit after
review other than GitHub's own update-branch merge, so it covers a non-merge relocation commit.

The recipes need git 2.38 or later, for `merge-tree --write-tree` in the Case A
prediction. That also covers the `--output-indicator-*` flags.

## Case A: main gained nothing beyond the squash

Use Case A only when `route` is `A`. Then `origin/main` adds only base content
that the child already holds, so `-X ours` changes nothing the child lacks. Both
Case A chains start with `[ "$route" = A ]`, so they refuse when `route` is `B` or
unset.

1. Try the plain fast-forward first. The prediction runs locally before anything
   is published: `git merge-tree --write-tree` must report a clean merge whose
   tree is the child's own tree, so the merge adds nothing and conflicts with
   nothing. This prediction is a positive-containment check: a match proves that
   `origin/main` adds nothing the child lacks, and a mismatch proves nothing, so
   the route falls to step 2, which verifies again. Only then does
   `gh pr update-branch` push a merge commit onto the child, a normal fast-forward
   that re-runs CI. The chain passes no `--rebase`, because a rebased update
   rewrites the child, which the post-update checks refuse. The chain then
   confirms that `origin/<child>` moved past `$tip` and that the update added no
   content:

   ```bash
   [ "$route" = A ] \
     && [ "$(git merge-tree --write-tree "$tip" origin/main)" = "$(git rev-parse "${tip}^{tree}")" ] \
     && gh pr update-branch <child> \
     && git fetch -q origin <child> \
     && new=$(git rev-parse "origin/<child>") \
     && git merge-base --is-ancestor "$tip" "$new" && [ "$new" != "$tip" ] \
     && [ "$(git rev-parse "${tip}^{tree}")" = "$(git rev-parse "${new}^{tree}")" ]
   ```

   When the prediction fails, `gh pr update-branch` is never called, and the
   route moves to step 2. If the chain got as far as `gh pr update-branch` and
   then failed, read `origin/<child>` before doing anything else. A moved branch
   means the update is already on the child. Stop there and report it, because
   undoing it takes a revert commit, which is for a person to decide. Use `$new`,
   not the pre-update tip, as the head the rollup gate in
   [stacked-chain-push.md](stacked-chain-push.md) reads.

2. Otherwise, merge in a detached worktree, verify, then push by full SHA:

   ```bash
   [ "$route" = A ] \
     && git worktree add --detach <dir> "$tip" \
     && git -C <dir> merge --no-ff --no-edit -X ours origin/main \
     && [ "$(git rev-parse "${tip}^{tree}")" = "$(git -C <dir> rev-parse 'HEAD^{tree}')" ] \
     && new=$(git -C <dir> rev-parse HEAD) \
     && git -C <dir> push origin "${new}:refs/heads/<child>"
   ```

   Step 2 also runs when step 1 did not finish: a conflict, a merge that adds
   content, or a refused update. `-X ours` takes the child's side only on
   conflicting hunks, so a `main` change the child never had still merges in. The
   tree gate against `$tip` refuses that merge, and nothing is pushed. If auto
   mode refuses `-X ours`, resolve the conflicted files one at a time as Case B
   step 2 does, commit, and run the same tree gate before the push.

## Case B: main moved beyond the squash

Case B covers every other route result. Its two preconditions stop the route
unless `origin/main` holds the squash and the squash tree equals the pre-squash
tree, and step 4 stops unless the child's own change matches the reviewed change
in both the content lines and the raw listing. An empty reviewed baseline also
stops step 4. Run Classify in the same shell call first, so `$reviewed`,
`$reviewed_meta`, `$tree_squash` and `$tree_pre` are set. The block runs with
`set -e` (its first line). Both preconditions run before `<dir>` exists, so a
stop there leaves nothing to clean up. A conflict that a later step cannot
resolve stops the route and stays in progress in `<dir>` for a person to read.
Use a fresh `<dir>` path.

```bash
set -e
git merge-base --is-ancestor "$squash" origin/main       # precondition: a stale origin/main stops here
[ "$tree_squash" = "$tree_pre" ]                         # precondition: tree identity, else stop
git worktree add --detach <dir> "$tip"
git -C <dir> merge --no-ff --no-edit "$pre"              # step 1: a conflict stops here
before=$(git -C <dir> rev-parse HEAD)
if git -C <dir> merge --no-ff --no-edit "$squash"; then  # step 2: a clean merge must add nothing
  [ "$(git -C <dir> rev-parse "${before}^{tree}")" = "$(git -C <dir> rev-parse 'HEAD^{tree}')" ]
else
  while IFS= read -r f; do                               # step 2: the child's side, one file at a time
    [ -n "$f" ] || continue
    if git -C <dir> checkout --ours -- "$f" 2>/dev/null; then
      git -C <dir> add -- "$f"
    else
      git -C <dir> rm -q -- "$f"                         # the child deleted it: no ours side to take
    fi
  done <<<"$(git -C <dir> diff --name-only --diff-filter=U)"
  [ "$(git -C <dir> write-tree)" = "$(git -C <dir> rev-parse 'HEAD^{tree}')" ]  # the resolved index must equal the child
  git -C <dir> commit --no-edit
fi
git -C <dir> merge --no-ff --no-edit origin/main         # step 3: must be clean
[ -z "$reviewed$reviewed_meta" ] && false                # step 4: an empty baseline refuses, so both sides empty never pass
[ "$(git -C <dir> diff --no-ext-diff --no-color -U0 --ignore-submodules=none --submodule=short --no-textconv --output-indicator-new='>' --output-indicator-old='<' origin/main HEAD -- <source paths> | grep -E '^[<>]')" = "$reviewed" ]   # step 4: the content lines
[ "$(meta_of <dir> origin/main HEAD -- <source paths>)" = "$reviewed_meta" ]                  # step 4: the raw listing
new=$(git -C <dir> rev-parse HEAD)                       # step 5: push by full SHA, no force
git -C <dir> push origin "${new}:refs/heads/<child>"
```

Ordering is the safety property. Taking the child's side on every conflicted file
is lossless only at step 2. The tree-identity precondition proved the squash tree
equals the pre-squash tree, and step 1 put the pre-squash tip into the child, so
the child's side already holds everything the squash brings. A clean squash merge
is checked against the pre-merge head instead: its tree must equal the pre-merge
tree, because the merge must add nothing. Step 3 must not conflict: a conflict
means `main` changed a line the child changed, which step 2 cannot vouch for.

A merge can also stop for a reason no gate names. Every merge here passes `--no-ff`, so
an operator's `merge.ff=only` cannot refuse one. An operator's
`merge.verifySignatures = true` can refuse a merge that brings in an unsigned commit,
such as a commit on `main`. The route does not override that setting, so a stop there
is the operator's own check doing its job. Resolve it in the operator's config, not by
adding a flag to the route.

## If the push is rejected

A bot can push to the child after `$tip` was read, and the push then fails as
non-fast-forward. A force would delete that commit, so every push in this route is
a plain push with no `--force`, `-f` or `+` refspec. Fetch the new head and merge
it in. Accept the merge only when it changes no tree, since a changed tree means
the bot changed content:

```bash
set -e
git fetch -q origin <child>
before=$(git -C <dir> rev-parse 'HEAD^{tree}')
git -C <dir> merge --no-ff --no-edit origin/<child>
[ "$before" = "$(git -C <dir> rev-parse 'HEAD^{tree}')" ]
new=$(git -C <dir> rev-parse HEAD)
git -C <dir> push origin "${new}:refs/heads/<child>"
```

If the tree check fails, stop and restart from
[Re-read the child](#re-read-the-child-before-any-gate). Its gates were computed
for the head they read, so a changed child needs a fresh classification.

## Guard before each merge

Retargets and `update-branch` both trigger bot commits. Before each merge, run
the guard in [serial-merge-chain.md](serial-merge-chain.md). It refuses a PR that
gained any commit after review other than GitHub's own update-branch merge, and it
pins the merge to the head it read.

## After the push

Wait for CI with the rollup gate in [stacked-chain-push.md](stacked-chain-push.md),
on the pushed SHA. Set `sha` to that SHA (`$new`) and `n` to the child's PR number
before running the block. For an `update-branch` merge, gate on the head that
Case A step 1 read. Do not gate on a check count. Once the push has succeeded,
remove the worktree with `git worktree remove <dir>`, without `--force`. It
refuses a dirty tree, and a dirty tree means work is still in progress.

## Fallback

If neither case verifies, use the rebase path in
[SKILL.md §2](../SKILL.md#2-merging-a-stacked-base-auto-closes-the-child-pr):
`git rebase --onto origin/main <old-base-tip> <child>`, then push by full SHA
with the lease that [stacked-chain-push.md](stacked-chain-push.md) prescribes.

## Auto mode

On one 2026-10 stack, the auto-mode classifier refused `git merge -s ours
origin/main`, and then refused a plain `git status` in the same worktree.
Resolving file by file (`git checkout --ours -- <file>`, `git add -- <file>`),
then checking that `git diff --cached HEAD` is empty, went through. Case B uses
the per-file resolution, and Case A falls back to it when `-X ours` is refused.
Both check the resolved index by tree (`git write-tree` against `HEAD^{tree}`)
rather than by that diff.
