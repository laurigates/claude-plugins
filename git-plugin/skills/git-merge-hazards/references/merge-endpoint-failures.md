# Merge-Endpoint Failures: Is It GitHub or the PR?

Skill-only material for `SKILL.md` §4; not part of `pr-merge-hazards.md`. Read
when `gh pr merge` fails with GraphQL errors, or the REST merge call returns a
`500` or `502` (often with an empty body) or a `405`, and you need to know
whether the PR is at fault before you touch it.

## First: read the PR's state

After any merge-call failure (a `502`, a GraphQL error, a `405`), read the PR's
state before retrying or probing:

```bash
gh pr view <n> --json state,mergedAt
```

A failed merge call can still merge the PR, or leave a merge running that
completes minutes later. `MERGED` with a `mergedAt` timestamp ends the
investigation: do not retry, and check that the push-triggered workflows ran
([Lost push event](#lost-push-event)). `OPEN` means continue with
[the stale-SHA control](#the-stale-sha-control).

Observed on 2026-11-04 ([Incident](#incident)): two PRs whose `gh pr merge`
returned `502 Bad Gateway` were already `MERGED` when read straight afterwards,
and two more, whose retries got `Merge already in progress`, merged a few
minutes later with no change to either PR.

## The stale-SHA control

`PUT /repos/{owner}/{repo}/pulls/<n>/merge` takes an optional `sha`: the head
commit the caller expects. When it does not match the PR's head, GitHub refuses
with `409` and merges nothing. That refusal is the endpoint's own validation, so
a deliberately wrong SHA is a safe probe of whether the endpoint is working at
all:

```bash
gh api -X PUT "repos/{owner}/{repo}/pulls/<n>/merge" \
  -f sha=0000000000000000000000000000000000000000 --include
```

`gh api` fills `{owner}` and `{repo}` from the current repository. The probe can
target the PR that failed or any other open PR: a SHA that matches no head
cannot merge anything. Prefer probing the failing PR itself, so a `405`
describes that PR rather than another one.

| Control returns | Reading | Action |
|---|---|---|
| `409` | The endpoint is up and validating | The failure is specific to the PR. Read `mergeStateStatus`, required checks and conflicts (§4) |
| `405`, body `Merge already in progress` | A merge of the probed PR is already running, typically left by an earlier call that failed | **Do not resubmit.** Wait a few minutes and re-read `state,mergedAt` |
| `405`, any other body | The endpoint is up and validating (the *probed* PR is not mergeable) | Same as `409`: the failure is specific to the PR that failed, not GitHub |
| `500` / `502`, empty body | The endpoint fails before it validates anything | GitHub-side. Wait, re-read the PR's state, then retry; **do not change the PR** |

## Why not change the PR

A `500` on the control says the failure is upstream of anything the PR
contains. Rebasing, force-pushing, retitling or re-requesting checks in response
restarts CI, can introduce the very conflict you were trying to rule out, and
leaves you unable to tell whether a later success came from your change or from
GitHub recovering. Other write endpoints failing at the same time (issue
creation, comments) corroborate an outage; reads succeeding do not rule one out.

## Lost push event

A merge made during a GitHub incident can move `main` without delivering the
push event, so a workflow whose only trigger is `on: push` never runs for it.
After such a merge, list the workflow's recent runs; if none ran for the merge
commit, re-run the previous one:

```bash
gh run list --workflow <workflow-file> --branch main --limit 3 \
  --json databaseId,headSha,event,createdAt
gh run rerun <previous run id>
```

The re-run executes on the previous run's SHA. That is enough for
release-please, which reads `main` and the `autorelease: pending` PRs through
the API rather than the triggering SHA, so it releases what the current `main`
holds. A workflow that checks out and builds the triggering commit would
rebuild the old SHA, so this re-run fits only actions that read repository
state through the API.

## Incident

2026-10-07/08, `laurigates/pal-mcp-server`: merging #168 failed with GraphQL
errors, then the REST `PUT /pulls/168/merge` returned `500` with an empty body.
The control, `PUT /pulls/170/merge` with `sha=0000…0`, which GitHub normally
refuses with `409`, also returned `500`, so the endpoint was failing before
validation, the problem was not specific to #168, and nothing could have merged.
Issue creation failed the same way. A retry the next day succeeded with no
changes to the PR.

2026-11-04, a GitHub incident with many `502`s on merges. Observed in
`ForumViriumHelsinki/fvh-data-pipe#111`: `gh pr merge` returned `502`, retries
got `GraphQL: Something went wrong` and `Merge already in progress`, and the
control, `PUT /pulls/111/merge` with `sha=0000…0`, returned `405` with body
`{"message":"Merge already in progress"}` while the PR read `CLEAN`/`MERGEABLE`.
The PR merged at 10:17:19Z with no change. `infrastructure#2710` behaved the
same way: a `502`, then `Merge already in progress` twice, merged at 10:43:47Z.
`R4C-VTT-API-UI#17` and `infrastructure#2699` got a `502` and were already
`MERGED` when read straight afterwards. The `R4C-VTT-API-UI#17` merge moved
`main` but started no run of its push-only release-please workflow;
`gh run rerun` of the previous run (41813114630) published
`vtt-flood-sim-ui-v0.7.0`.
