---
created: 2026-05-25
modified: 2026-10-02
reviewed: 2026-10-02
---

# Development Terminology

Terms this repo uses with a meaning a model would not infer, and who owns each
concept. Unscoped on purpose: word choice bites in plans, commits, and PR
titles, which no `paths:` glob can see. General vocabulary (triage, dry-run,
red-team, fan-out, hoist/lift, happy path, …) and the steps for adding a term
live in [`docs/terminology.md`](../../docs/terminology.md).

| Term | Definition | Use when | Owner / not to be confused with |
|------|------------|----------|---------------------------------|
| Set the seam | Name the boundary where this change stops and the next begins | Adjacent work tempts scope creep | A scope boundary — not the *test* seam of `software-design-plugin:design-legacy-seams` |
| Define done | Make acceptance criteria explicit before starting | "Done" is ambiguous and the team needs alignment | In a loop it is the exit condition, judged by someone other than the worker (`.claude/rules/loop-integrity.md`) |
| Park | Defer with intent to return, capturing enough state to resume | Higher-priority work pre-empts current task | `taskwarrior-plugin:task-release` — stops the clock without closing the task |
| Pick up where we left off | Resume with looser continuity — reload the gist and proceed | Time has passed; some re-grounding is needed | `session-plugin:session-spinup`; exact resume of tracker work is `project-plugin:project-continue` |

If the term is plugin-specific (e.g. blueprint's `ADR`, `PRD`, `PRP`), keep it in that plugin's rules and cross-link instead.

## Related

- `.claude/rules/agent-development.md` — formal definitions of subagent, worktree isolation, team
- `agent-patterns-plugin:adversarial-review` — defines adversarial review and red-teaming
- `agent-patterns-plugin:parallel-agent-dispatch` — the fan-out / gather orchestration pattern
- `blueprint-plugin/README.md` — ADR / PRD / PRP vocabulary specific to that workflow
- `docs/PRINCIPLES.md` §7 — why every entry is a positive definition
