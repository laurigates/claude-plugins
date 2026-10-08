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
non-merge commit after it. Merge commits from update-branch are expected;
anything else is unreviewed. Pin the merge to the head you just read, so a push
between your read and the merge fails the merge instead of riding along.

```bash
START=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # once, after the last review, before the loop
# ...per PR, after update-branch and the wait for CLEAN:
commits_json=$(gh pr view "$n" --json commits) || exit 1
late=$(jq -r --arg t "$START" '[.commits[] | select(.committedDate > $t)
  | select((.messageHeadline | startswith("Merge")) | not)
  | "\(.oid[0:8]) \(.messageHeadline)"] | join("; ")' <<<"$commits_json") || exit 1
[ -n "$late" ] && { echo "STOP #$n: unverified commits: $late"; exit 1; }
head=$(gh pr view "$n" --json headRefOid --jq .headRefOid)
gh pr merge "$n" --squash --match-head-commit "$head"
```

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

## Recovery when unverified commits already merged

1. List them with `gh pr view <n> --json commits` for each merged PR. The
   squash commit on `main` hides them, but the PR's commit list keeps them, and
   fetching the PR's head ref recovers the objects.
2. Reverse-apply each diff onto current `main`.
3. Prove the result: the diff against each commit's parent must be empty for
   every touched directory, so each one matches the tree you verified.

```bash
git fetch origin "pull/${n}/head" && git branch "pr-${n}" FETCH_HEAD
git show --binary --format= "$sha" | git apply -R
git diff "${sha}^" -- "$dir"    # must print nothing
```
