# Merge-Endpoint Failures: Is It GitHub or the PR?

Skill-only material for `SKILL.md` §4; not part of `pr-merge-hazards.md`. Read
when `gh pr merge` fails with GraphQL errors, or the REST merge call returns a
`500` (often with an empty body), and you need to know whether the PR is at
fault before you touch it.

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
cannot merge anything.

| Control returns | Reading | Action |
|---|---|---|
| `409` | The endpoint is up and validating | The failure is specific to the PR. Read `mergeStateStatus`, required checks and conflicts (§4) |
| `405` | The endpoint is up; the PR is not mergeable | Same: the PR is the problem, not GitHub |
| `500` / `502`, empty body | The endpoint fails before it validates anything | GitHub-side. Wait and retry later; **do not change the PR** |

## Why not change the PR

A `500` on the control says the failure is upstream of anything the PR
contains. Rebasing, force-pushing, retitling or re-requesting checks in response
restarts CI, can introduce the very conflict you were trying to rule out, and
leaves you unable to tell whether a later success came from your change or from
GitHub recovering. Other write endpoints failing at the same time (issue
creation, comments) corroborate an outage; reads succeeding do not rule one out.

## Incident

2026-10-07/08, `laurigates/pal-mcp-server`: merging #168 failed with GraphQL
errors, then the REST `PUT /pulls/168/merge` returned `500` with an empty body.
The control, `PUT /pulls/170/merge` with `sha=0000…0`, which GitHub normally
refuses with `409`, also returned `500`, so the endpoint was failing before
validation, the problem was not specific to #168, and nothing could have merged.
Issue creation failed the same way. A retry the next day succeeded with no
changes to the PR.
