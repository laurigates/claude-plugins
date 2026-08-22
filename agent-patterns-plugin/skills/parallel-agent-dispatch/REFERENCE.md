# Parallel Agent Dispatch — Reference Index

Supporting material for [`parallel-agent-dispatch`](SKILL.md), split across
`references/` so a run loads only the material its path needs. The operational
workflow lives in `SKILL.md`; nothing below is loaded unless you follow one of
these links.

| Path you are on | File | Carries |
|---|---|---|
| Composing the dispatch call and the brief's scaffolding | [`references/dispatch-contract.md`](references/dispatch-contract.md) | Return Contract schema (verbatim), failure mode → schema field, the contract as workflow primitives (the prose→primitive mapping table, JSON Schema + `parallel()` barrier, and their cost gate), Skill-less `agentType` evidence (`skill_listing` tax) |
| Writing a refactor / bulk-edit brief | [`references/brief-templates.md`](references/brief-templates.md) | Refactor-brief template, completion manifest (#1601), verbatim-patch discipline, agent self-verification and reviewer-agent evidence |
| An agent stalled, was cut off, went idle, was killed, or was rate-limited | [`references/failure-recovery.md`](references/failure-recovery.md) | Commit/push stall salvage, WIP salvage before re-dispatch (#1491), audit local worktrees alongside the remote (#2447), idle-without-report (#2039), `TaskStop` recovery + kill thresholds, rate-limit recovery-dispatch |
| Setting up worktree isolation, or a git write went somewhere unexpected | [`references/worktree-hazards.md`](references/worktree-hazards.md) | cwd-reset guardrail (#1480), `GIT_DIR`-export leak (#1692), nested-repo isolation (#1838), shared scratchpad collisions (#2370), deleted worktree kills the shell (#2372), target-branch preflight (#1969), `isolation: "remote"` resolving to a local worktree (#2447) |

This file is an index only. Add new reference material to the file whose path
needs it — or a new `references/*.md` plus a row here — rather than growing this
page (`.claude/rules/context-engineering.md` § "Split long skills across files").
