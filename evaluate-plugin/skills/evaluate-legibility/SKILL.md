---
name: evaluate-legibility
description: Cold-read a SKILL.md with a zero-context agent reader to check its intent is legible. Use when validating whether a skill says clearly when to invoke it and how to start.
args: <plugin/skill-name>
allowed-tools: Task, Read, Glob, Bash(bash *), TodoWrite
argument-hint: "git-plugin/git-commit"
model: opus
agent: general-purpose
created: 2026-06-13
modified: 2026-06-18
reviewed: 2026-06-13
---

# /evaluate:legibility

Dispatch an isolated, zero-context **agent reader** at a single `SKILL.md` and
ask it the only two questions that matter for reuse: *from this file alone, can
you tell WHEN to invoke the skill, and can you carry out its FIRST concrete
action?* What confuses a cold agent reader is what will silently degrade
auto-invocation and first-step execution for every future agent that loads the
skill.

This is the **comprehension** gate — read and critique, never execute. It
reuses the dispatch contract of `agent-patterns-plugin:cold-read-gate` (isolated
haiku reader, `QUESTIONS` / `HESITATIONS` / `verdict` schema, triage before
acting). The difference: the reader here is an *agent* loading a skill, not a
human triaging an outward artifact — so the persona and the triage table are
skill-doc-specific. See that skill for the dispatch rationale; this skill does
not restate it.

The verdict is **advisory, not a CI gate**: haiku is non-deterministic, so a
`needs-revision` is a prompt to look, never a merge block.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| Checking a SKILL.md reads clearly to a fresh agent | Testing whether the skill *executes* correctly -> `/evaluate:matrix` |
| Triaging why a skill never auto-invokes | Need structural/lint validation -> `scripts/plugin-compliance-check.sh` |
| Reviewing a newly-authored or just-edited skill | Gating outward issues/docs for a human reader -> `agent-patterns-plugin:cold-read-gate` |
| Want a cheap, no-execution legibility read | Benchmarking effectiveness vs a baseline -> `/evaluate:skill` |

## Context

- Available skills: !`find . -path '*/skills/*' -name 'SKILL.md' -not -path '*/.claude/worktrees/*'`

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `<plugin/skill-name>` | required | Target skill as `plugin-name/skill-name` |

## Execution

Execute this legibility gate:

### Step 1: Resolve the prompt

The Context block above ran `emit-legibility-prompt.sh`, which resolved the
target `SKILL.md` absolute path and emitted the cold-reader dispatch prompt
between `=== PROMPT ===` and `=== END PROMPT ===`.

If `STATUS=ERROR`, report the `ERROR=` line and stop (bad argument or missing
SKILL.md). Otherwise read `SKILL_PATH=` and the `=== PROMPT ===` block.

### Step 2: Dispatch the cold reader

Spawn one `Task` subagent to read the skill cold:

```
Task subagent_type: general-purpose
model: haiku
prompt: <the text between === PROMPT === and === END PROMPT ===>
```

The reader is deliberately **haiku, isolated, and shown only the file path** —
it is the measurement instrument, not a delegate (the sanctioned exception in
`.claude/rules/agent-and-tool-selection.md`). Do not add context, do not let it
explore the repo. Capture its final message: `QUESTIONS`, `HESITATIONS`, and a
`verdict` of `clear` or `needs-revision`.

### Step 3: Triage — genuine gaps vs test artifacts

The cold reader cannot know the invocation context, so some complaints are
artifacts of reading a skill in isolation. Triage before recommending changes:

| Genuine gap — fix it | Test artifact — ignore it |
|---|---|
| No "When to Use" table; reader can't tell when to invoke | "What is plugin X?" when X is named in the frontmatter |
| `description` has no "Use when…" trigger phrase | REFERENCE.md content absent (loaded on demand by design) |
| First execution step names a script/term the file never defines | Harness vars (`$ARGUMENTS`, `${CLAUDE_SKILL_DIR}`) unrecognized |
| Skill narrates ("this skill handles X") instead of an imperative step | Full tool list absent from the body (it's in `allowed-tools`) |
| Acronym/jargon used before it is introduced | Demands for context a real invocation supplies |

### Step 4: Report

Print the verdict, the genuine-gap `QUESTIONS` (each with the quoted phrase that
blocked the reader), and a one-line recommendation per gap. State explicitly
that the verdict is advisory. Do **not** edit the skill — surfacing the gaps is
the deliverable; fixing them is a separate, human-confirmed step.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Resolve path + emit prompt | `bash evaluate-plugin/skills/evaluate-legibility/scripts/emit-legibility-prompt.sh --plugin-skill <plugin/skill>` |
| Run the script test | `bash evaluate-plugin/scripts/tests/test-emit-legibility-prompt.sh` |

## Quick Reference

| Field | Meaning |
|-------|---------|
| `verdict: clear` | Reader could answer both (a) when and (b) first action |
| `verdict: needs-revision` | A genuine gap blocked (a) or (b) — advisory, not a block |
| `QUESTIONS` | Blocking confusions, each with a quoted phrase |
| `HESITATIONS` | Non-blocking uncertainties |

## Related

- `agent-patterns-plugin:cold-read-gate` — the dispatch contract this reuses (outward artifacts, human reader)
- `/evaluate:matrix` — the executability gate (run on haiku, grade the artifact)
- `/evaluate:skill` — effectiveness vs a baseline (with-skill − baseline delta)
- `.claude/rules/skill-evaluation.md` — the tiered measurement methodology
