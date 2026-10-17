---
name: workflow-scale-budget
description: Size a Workflow script's agent count before running it, or tally a finished run's agents and tokens. Use when authoring or proposing a Workflow fan-out, or asking what a run used.
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
created: 2026-09-29
modified: 2026-10-17
reviewed: 2026-09-29
---

# A Workflow's Cost Is Its Agent Count

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Writing or proposing a `Workflow` script, or estimating its cost | Writing the script's API calls — load the built-in `workflow-authoring` skill |
| The `hooks-plugin/hooks/workflow-scale-guard.sh` hook asked before a run | Recovering a run already killed mid-flight — use `workflow-orchestration-plugin:workflow-interrupted-run-recovery` |
| Choosing between per-item and grouped fan-out | Ordering dependent waves — use `workflow-orchestration-plugin:workflow-wave-dispatch` |
| A Workflow run has finished and you want its realised agent count or tokens | The tally WARNs `agents_without_result` (the run ended, whether killed, failed or completed, with agents unfinished) — use `workflow-orchestration-plugin:workflow-interrupted-run-recovery` |

The hook enforces the bound (PreToolUse on `Workflow`, `ask` when the estimated
agent count exceeds `CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS`, default 10). The two
shipped mechanisms do **not** cover this: `workflowSizeGuideline` is advisory
system-prompt text that ends "not a hard limit", and `skipWorkflowUsageWarning`
is a **one-time** acceptance — once set, auto mode never prompts before a
workflow again, at any scale.

## Execution

1. **Count agents, not tokens.** Every fresh agent builds its own prompt cache
   at 1.25x input price and a short-lived one never reads it back. 2026-09-15:
   55.2M cache *writes* cost $345 while 252.5M cache *reads* cost $126 —
   trimming prompts optimises the cheaper half.
2. **Find the per-item multiplier.** One reviewer per changed file is fine.
   `pipeline(units, edit, review, repair, re-review)` is 4x an unknown N; that
   shape across five runs produced 496 subagents against a guideline of 10, and
   $528 in an afternoon.
3. **Group by theme, not by item, when the work is per-file.** The same 43-file
   documentation sweep ran twice on 2026-09-16: one editor plus one reviewer per
   file (138 agents, 13.8M subagent tokens, 49 killed by the usage limit before
   reviewing anything), then seven editors each owning a themed group of 5–11
   files (7 agents, 1.93M tokens, zero failures). Same findings, same refs, same
   gates — an eighth of the cost. Replace the reviewer half with one
   deterministic gate (pre-commit, a scripted link check, reading the diff)
   rather than N agents.
4. **Design for re-driving, not resuming.** When the usage limit lands mid-run
   the session id changes, and `resumeFromRunId` looks for the journal under the
   *new* session directory and reports nothing to resume (observed 2026-09-16 on
   two runs whose journals sat intact under the old id). Have agents write
   output to disk as they go, keep each phase independently runnable, and record
   what completed so a replacement run can skip it. The 66 edits that survived
   that limit did so because they were already on disk.
5. **State the expected agent count when proposing the workflow, and cap the
   fan-out where the list is produced** (`.slice(0, N)` — the guard reads an
   explicit cap as the bound).
6. **A run large enough to trip the gate is the user's call.** Never raise
   `CLAUDE_HOOKS_WORKFLOW_MAX_AGENTS` to clear your own prompt.
7. **An issue sweep whose agents file follow-ups does not converge on its own.**
   Implementers and reviewers are told to split out-of-scope defects into new
   issues, so each round fills the queue it is draining. 2026-10-04,
   mcu-tinkering-lab: round 1 (41 agents, 10.2M subagent tokens) closed 21
   issues and filed 18; round 2 (32 agents, 7.3M tokens) closed 16 and filed
   15, four of them edge cases in a single checker script. Plan the number of
   rounds up front, triage the new issues between rounds, and carry the
   low-value ones as backlog. "Clear the plate" is not a stopping condition
   for a loop that refills the plate.
8. **After a run finishes:** `bash "${CLAUDE_SKILL_DIR}/scripts/workflow-run-tally.sh" <run-id>`
   tallies its realised agents and tokens from the transcripts. A session id tallies
   every run in that session, then prints one `WORKFLOW SESSION TALLY` block with the
   agents and tokens summed across the runs and the worst run status. A WARN with
   `agents_without_result` means the run ended with agents unfinished: see
   `workflow-orchestration-plugin:workflow-interrupted-run-recovery`. Summing the raw
   usage lines overstates cache tokens, because one API message is written as several
   lines, so the script keeps only the last line per message id.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Tally one finished run | `bash "${CLAUDE_SKILL_DIR}/scripts/workflow-run-tally.sh" <wf_run_id>` |
| Tally every run in a session | `bash "${CLAUDE_SKILL_DIR}/scripts/workflow-run-tally.sh" <session_id>` |
| Transcripts outside `~/.claude/projects` | `bash "${CLAUDE_SKILL_DIR}/scripts/workflow-run-tally.sh" <id> --projects-dir <dir>` |
