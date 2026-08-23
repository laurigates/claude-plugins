# Bulk Sweep — Classify Every Match First - Reference

Advanced patterns for sweeps large enough to fan out across parallel agents, and for briefing the adversarial reviewers that audit them.

## Parallelizing a Sweep — Resolve the Rename Map Before Dispatch

When a sweep is large enough to fan out across parallel agents, a second failure
mode appears on top of the four categories: **the agents disagree with each
other.** Each one classifies its own borderline matches, each one is locally
defensible, and the result is a codebase that is internally inconsistent — every
file compiles on its own, the whole does not.

Fix it by resolving every cross-file naming decision **before** dispatch, into a
single explicit **rename map**: old → new, plus an explicit **do-NOT-rename**
list (the category 2–4 tokens from Step 3). Brief that map **verbatim** into
every agent's prompt — not paraphrased, not summarized per agent.

| Property you need | What guarantees it |
|---|---|
| Every agent renames the same tokens the same way | The map, resolved centrally once and copied verbatim |
| No two agents edit the same file | File grouping — **disjointness only** |

That split is the point. Agreement is hard to extract from independent agents
and trivial to get from a shared artifact, so move it out of the agents
entirely; grouping then only has to guarantee disjointness, a much weaker and
easier property than consensus.

The do-NOT-rename list is not padding — it is the contract's teeth. An agent
that "helpfully" extends the rename to a look-alike commits exactly the
category-2/3 corruption this skill exists to prevent, and a parallel agent
commits it out of your sight.

**The success signal is an agent *refusing* a rename.** In a 112-file
`Trends → Foresight` sweep (ForumViriumHelsinki/thelma PR #1263, which also
renamed a Postgres enum `TrendType → ForesightType`), agents correctly left
`LinkableEntityType` alone — it contains the target word but was not in the map.
A run where no agent declines anything usually means the map was never actually
constraining them.

Dispatch mechanics (worktree collisions, scope overflow, silent exits) belong to
`agent-patterns-plugin:parallel-agent-dispatch`; the rename map is the
sweep-specific payload you hand it.

## Brief Adversarial Auditors With the Artifact's Purpose, Not Just the Transform

When adversarial or verification agents audit a sweep, a prompt containing only
the transform contract — "rename X to Y across these files" — gives them no way
to tell a deliberate change from scope creep. So they flag the change's own
reason for existing.

Every auditor prompt needs **both**:

| Brief the auditor with | Because without it |
|---|---|
| The transform contract (rename map + do-NOT-rename list) | It cannot check the sweep did what was agreed |
| What the artifact is **for**, and what is deliberately in scope | It reports the PR's central purpose as unjustified scope creep |

In the thelma sweep above, all three auditors flagged the PR's central purpose
that way, and **10 of 25 findings were false positives** traceable to that one
omission — expensive to triage precisely because each read as a legitimate
concern.

See `agent-patterns-plugin:adversarial-review` for the review pass itself; this
is the sweep-specific brief to attach to it.
