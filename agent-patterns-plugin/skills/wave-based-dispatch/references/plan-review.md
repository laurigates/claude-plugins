# Wave-Based Dispatch — Layer Map and Common Mistakes

Moved verbatim from [SKILL.md](../SKILL.md). Open when reviewing a wave plan, or
when deciding which sibling skill owns a concern.

## Composition

| Layer | Skill | Concern |
|-------|-------|---------|
| Per-agent brief inside a wave | `agent-patterns-plugin:parallel-agent-dispatch` | Worktree preflight, scope budget, Return Contract, shared-file exclusion |
| Lock-holding waves | `agent-patterns-plugin:exclusive-lock-dispatch` | Pre-dump mechanics so downstream waves read artefacts, not the lock |
| Wave scheduling and gate failures | `workflow-orchestration-plugin:workflow-wave-dispatch` | Workflow-side view: which waves exist, what to do when a gate fails |
| Where wave candidates come from | `taskwarrior-plugin:task-coordinate` | Surfaces unblocked tasks while skipping lock-contenders |

This skill is the dispatch-time discipline that ties them together —
the agent-pattern view of why the chain is sequential and what the
between-wave gates buy you.

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Writing the implementation brief before the research probe lands | Research wave first; implementation brief cites the artefact paths |
| Skipping a gate "because nothing changed" | All six gates run at every boundary; cheap gates are cheap on purpose |
| Re-deriving the exclusion list per wave | Cite once in wave 1; reference by name in waves 2..N |
| Filing every small issue as a follow-up WO | Inline-fix when ≤ ~10 lines and the orchestrator has the context |
| Treating a gate failure as "dispatch the next wave to fix it" | Fix in place and retry the gate; revert and re-brief if unrecoverable |
