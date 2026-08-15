# Parallel Agent Dispatch — Dispatch Contract

What every dispatched agent's prompt must carry: the Return Contract schema
verbatim, the failure mode each of its fields catches, and how to pick an
`agentType` that does not pay the `skill_listing` tax. Entry point:
[`../SKILL.md`](../SKILL.md) § Return Contract / § Skill-less agentType.

## Return Contract schema

Include this verbatim in every dispatched agent's prompt under a heading like
`### Return contract (mandatory)` — agents follow concrete schemas more reliably
than prose.

```markdown
## Result
- status: success | partial | failed
- branch: <branch-name>
- pr: <url> | not opened: <reason>
- commits: <N> (<short-sha-range>)
- worktree: <path> (clean | dirty: <file list>)

## Scope delivered
- 2–4 bullets on what actually landed

## Deferred / skipped
- Anything explicitly out of scope or punted (empty is fine — section must exist)

## Issues encountered
- Hook fires, retries, test flakes, manual workarounds, unexpected findings
  (empty is fine — section must exist)

## Orchestrator action needed
- none | <one line: what the lead must do before next phase>
```

## Failure modes → schema field

Why each Return Contract field exists — the observed failure mode it catches.

| Failure mode (observed) | Schema field that catches it |
|-------------------------|------------------------------|
| Silent mid-task exit | No return message → orchestrator treats as stall and resumes |
| Work on wrong branch | `branch` + `worktree` fields force self-report |
| Uncommitted loose ends | `worktree: dirty` is explicit, impossible to gloss over |
| Second root cause missed | `Issues encountered` has a home for "bonus" findings |
| Follow-up work invisible | `Deferred / skipped` and `Orchestrator action needed` |
| Budget overrun | `status: partial` + explicit deferred list beats a truncated claim of success |
| Pre-commit hook stall at commit time | `worktree: dirty: <files>` + `status: failed` with `Orchestrator action needed` naming the hook that blocked |
| Concurrent rate-limit cascade | `status: partial` + recovery-dispatch follow-up agent on the unfinished slice |
## The Return Contract as workflow primitives

A harness does not replace this contract; it turns what prose can only *request*
into what a runtime *enforces*:

| Here (prose) | Workflow primitive |
|---|---|
| The `## Result` schema pasted into each brief | a **JSON Schema** on the `agent()` call — validated, so a one-word surrender cannot parse |
| "every returned summary parsed" (Orchestrator Checklist) | `parallel()` — the barrier that line already assumes |

What to weigh before turning that mapping into a harness:

- **A schema-bound agent has no partial result.** An `agent()` bound to a
  `StructuredOutput` schema that is cut off *before* it emits — a rate-limit
  storm, a context exhaustion — is reported to the caller as a hard parse
  failure, not as partial output, even when substantial work was done inside its
  context window (issue
  [#1463](https://github.com/laurigates/claude-plugins/issues/1463)). The prose
  contract degrades more gracefully: a worktree still holds the work, and the
  empty-vs-dirty discrimination in
  [failure-recovery.md](failure-recovery.md) recovers it. Cap schema-bound waves
  and stagger their launches —
  `workflow-orchestration-plugin:workflow-wave-dispatch` § Schema-Constrained
  Agents Under Rate-Limit Storms owns those numbers.
- **`parallel()` is a barrier, not a speedup.** Its value here is that no stage
  may begin before every branch of the previous one returned. If the "barrier"
  is really a summary the last agent could have written inline, the harness
  bought nothing.
- **The cost gate.** A harness costs **one opus agent per fan-out unit, per
  invocation** — `.claude/rules/workflow-vs-skill.md` is the gate, and it
  rejects a harness for *this* skill: it is reference doctrine with no execution
  body of its own, so there is no N to enumerate and no stage to barrier.

## Skill-less agentType — evidence

`SKILL.md` § "Skill-less agentType for Read-Only Fan-Out" carries the routing
table; this is the measurement behind it.

Every `Skill`-bearing subagent pays a large **fixed** context tax before it runs
a single tool call:

| Injected up front | Size |
|---|---|
| `skill_listing` attachment | ~88k chars / ~22k tokens |
| `deferred_tools_delta` | ~12k chars / ~3k tokens |

That ~25k overhead is paid whether or not the agent ever calls `Skill`. Add ~10
file reads and a forced `StructuredOutput` schema and a read-only classifier
subagent exceeds its context window — observed as `Prompt is too long` with
**40–100% batch-failure rates** in a real fan-out (issue
[#1549](https://github.com/laurigates/claude-plugins/issues/1549)). Agents whose
tool set omits `Skill` receive **no `skill_listing` injection at all**, so the
identical workload fits comfortably.

`agents-plugin:review` doubles as a **token-lean structured-output classifier**:
given a procedure-vs-judgment rubric and a forced `StructuredOutput` schema it
cleanly classified a 10-file batch where identical `general-purpose` agents
failed with `Prompt is too long` (issue
[#1550](https://github.com/laurigates/claude-plugins/issues/1550)). Its review
system prompt does not interfere when the brief supplies an explicit rubric and
schema. Preserve its lean, no-`Skill` tool set when reaching for it as a fan-out
building block — adding `Skill` to it reinstates the full tax.
