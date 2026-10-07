# session-distill — Cross-Repo Promotion ([PROMOTE])

## Why promote

The other categories keep knowledge in *this* repo. `[PROMOTE]` is how a
session-invented pattern reaches the **shared plugin marketplace** so every repo
benefits — the additive complement to `feedback-plugin`'s error loop (which only
fires on friction). A near-zero-friction session can still produce several
`[PROMOTE]` candidates.

## When to promote

`[PROMOTE]` is the **additive, cross-repo** category — distinct from the others,
which all write *this* repo's `.claude/`. Use it when the insight is reusable
**beyond this repo** and belongs in a marketplace plugin: either a pattern the
session invented that has **no home skill yet** (→ propose a new skill), or a
capability an **existing named skill is missing** (→ propose an edit to it). A
`[PROMOTE]` does not require anything to have gone wrong — a smooth session that
produced a strong reusable technique is exactly its trigger. Each `[PROMOTE]`
names a target `<plugin>/skills/<skill>` (new or existing) and is applied as a
**PR against the plugin repo**, never an edit to the current repo (see
[Cross-Repo Promotion](../SKILL.md#cross-repo-promotion-promote)).

## Routing: which plugin/skill should own it

Pick the target by the pattern's domain, most specific first:

| Pattern is about… | Likely owner |
|-------------------|--------------|
| A language/tool's build/test/lint (cargo, uv, biome…) | that language plugin (`rust-plugin`, `python-plugin`, …) |
| Multi-agent orchestration, waves, worktrees, dispatch | `agent-patterns-plugin` / `workflow-orchestration-plugin` |
| Git, PRs, merges, rebases, conflicts | `git-plugin` |
| CI/infra/repo configuration | `configure-plugin` / `github-actions-plugin` |
| Nothing fits, but it's clearly reusable | propose a new skill in the closest plugin and flag the routing choice for review |

Then decide **new skill vs. edit existing**: glob the owner plugin's `skills/`,
read the closest few, and prefer extending an existing skill (a new section +
cross-link) over a new skill unless the pattern is genuinely its own topic
(`Update Over Add` still applies — across repos now).

## Plugin repo conventions

The plugin source lives in its own repo. Open a PR there; the human reviews and
merges. Match the repo's conventions: skills are auto-discovered (add
`skills/<name>/SKILL.md` with dated frontmatter + `user-invocable`/`allowed-tools`),
update the plugin README's skill catalog, keep `!`-context commands free of pipes/
redirects, use a conventional commit (`feat(<plugin>):` for a new skill,
`docs(<plugin>):` for an edit — release-please versions from it), and apply the
`<plugin>` routing label (create it if missing).

## Why a throwaway clone (issue #2113)

That checkout is frequently contended by a
concurrent Claude session: a coworker's operation can autostash your in-flight
edit and move `HEAD` between two of your calls, so the next `git add`/`commit`
reports *"nothing to commit, working tree clean"* and the edit is silently gone
(issue #2113). A fresh clone shares no `.git` with that checkout, so no coworker
can move `HEAD` under it.

## PR body

The PR body should cite the session as evidence (what the pattern is, why it's
reusable, where it was used) — the additive analogue of the friction loop's
evidence summary.
