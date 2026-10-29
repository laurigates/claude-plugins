# Serial Merge Chains: Commits Nobody Verified

Detail for [§6 of SKILL.md](../SKILL.md#6-a-serial-merge-chain-merges-commits-nobody-verified).
Open it before scripting a loop that updates, waits for, and merges several PRs
in sequence.

## The mechanism

A serial merge loop runs, for each PR: `gh pr update-branch`, wait for green,
`gh pr merge`. The update-branch push is a `synchronize` event, so every
`pull_request` workflow runs again, including a bot that **writes to the PR
branch** (a content splitter, an auto-fixer, a formatter). Any commit that bot
pushes lands after you reviewed the PR, then passes CI and merges with the rest.
A green check on the updated head says the tree builds; it does not say
anyone read the new commits.

A second trap makes it worse. If an early PR in the chain **changes such a bot's
selection logic**, merging it switches the new behaviour on for every later PR
in the same chain, before anyone has seen it run on a real PR.

> 2026-10-07 (`laurigates/claude-plugins`): #2923 changed the skill splitter to
> select every changed SKILL.md over 10,000 characters and merged first. Its
> `pull_request` trigger then re-split skills on the next five PR branches the
> chain updated, including skills deliberately left over the threshold because
> a check pins their text in the body. Six bot commits merged unverified, and
> one moved text a test requires on the entry page, so that test went red on
> main. Reverted in #2936; the splitter became dispatch-only in #2937.

## The guard

Record when verification ended, and refuse to merge if the PR gained any
commit after it, with one exemption: a merge commit GitHub made itself through
`update-branch`. The test is the one `scripts/merge-chain.sh` applies, and both
halves are read from GitHub:

- the commit has **two or more parents**, and
- its **committer email is `noreply@github.com`**.

The subject line is not consulted. A single-parent commit titled `Merge …` is
unreviewed, and so is a real merge commit anyone else pushed: a conflict agent's
own `Merge branch main into …` carries that agent's committer, and its conflict
resolution is new code nobody reviewed. Pin the merge to the head you just
read, so a push between your read and the merge fails the merge instead of
riding along.

```bash
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # once, after the last review, before the loop
# ...per PR, after update-branch and the wait for CLEAN (owner, name, n set):
q='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { pullRequest(number: $number) {
    headRefOid
    commits(last: 100) { totalCount
      nodes { commit { oid committedDate messageHeadline parents { totalCount } committer { email } } } }
  } } }'
raw=$(gh api graphql -f query="$q" -F owner="$owner" -F name="$name" -F number="$n") || exit 1
pr=$(jq -ce '.data.repository.pullRequest | select(.headRefOid and .commits.nodes)' <<<"$raw") || exit 1
[ "$(jq '.commits.totalCount - (.commits.nodes | length)' <<<"$pr")" = 0 ] ||
  { echo "STOP #$n: commit list truncated, the guard cannot clear it"; exit 1; }
late=$(jq -r --arg t "$START" '[.commits.nodes[].commit | select(.committedDate > $t)
  | select(((.parents.totalCount // 0) >= 2 and (.committer.email // "") == "noreply@github.com") | not)
  | "\(.oid[0:8]) \(.messageHeadline)"] | join("; ")' <<<"$pr") || exit 1
[ -n "$late" ] && { echo "STOP #$n: unverified commits: $late"; exit 1; }
head=$(jq -r .headRefOid <<<"$pr")
gh pr merge "$n" -R "$owner/$name" --squash --match-head-commit "$head"
```

The read is GraphQL, as in the script, because `gh pr view --json commits`
carries no parent count. Where GraphQL is unavailable,
`gh api --paginate repos/<owner>/<repo>/pulls/<n>/commits` carries the same
facts as `.parents | length`, `.commit.committer.email` and
`.commit.committer.date`, up to 250 commits.

`--match-head-commit` takes the full 40-character SHA, which `headRefOid`
returns. An abbreviated one is rejected with `Could not coerce value "…" to
GitObjectID`, and the PR is not merged.

The chain squashes because `update-branch` adds a merge commit to each PR, and
rule 4 of the merge-method decision rule sends any branch with a merge commit
to squash (`github-pr-title` →
[merge-strategies.md](../../github-pr-title/merge-strategies.md)). A PR that
needed no update and has no merge commit takes the `METHOD=` that
`pr-merge-method.py` prints.

- **Use `jq --arg`, not `gh … --jq --arg`.** `gh`'s `--jq` takes a single
  expression and rejects extra arguments ("accepts at most 1 arg(s)"). Inside
  `late=$(…)` that error leaves `late` empty, so the guard reads "no late
  commits" and the merge goes through. That is how the first version of this
  guard silently did nothing. Control-test the guard against a PR you know has a
  late commit before trusting it.
- **Fail closed on a read error.** If `gh pr view` or `jq` fails, stop. An empty
  result from a failed read must never mean "clean".
- **Order the chain so behaviour changes go last**, or disable the bot
  (`gh workflow disable`, with a re-enable issue opened in the same step) for
  the duration of the chain.

## Known limits of the exemption

- **The committer email is a claim, not a proof.** Whoever creates a merge
  commit sets its committer, so a hand-made merge recorded as
  `noreply@github.com` passes. GraphQL's `signature { wasSignedByGitHub }` on
  the commit cannot be forged that way and would harden the exemption;
  `merge-chain.sh` does not check it yet.
- **A merge made in GitHub's web conflict editor is also committed by GitHub**,
  so it passes the exemption although it contains a conflict resolution. Treat
  a web-editor resolution after review as unreviewed and move the review
  timestamp only after reading it.

## Recovery when unverified commits already merged

1. List them with `gh pr view <n> --json commits` for each merged PR. The
   squash commit on `main` hides them, but the PR's commit list keeps them, and
   fetching the PR's head ref recovers the objects.
2. Reverse-apply each diff onto current `main`.
3. Prove the result: the diff against each commit's parent must be empty for
   every touched directory, so each one matches the tree you verified.

```bash
git fetch origin "pull/${n}/head:refs/remotes/pr/${n}"
git show --binary --format= "$sha" | git apply -R
git diff "${sha}^" -- "$dir"    # must print nothing
```
