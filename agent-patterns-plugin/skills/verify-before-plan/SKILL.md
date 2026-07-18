---
name: verify-before-plan
description: Verify orchestrator premises (file counts, build state, artefact presence) before dispatching parallel subagents. Use when a wave's briefs cite a number, path, or behaviour not yet checked.
allowed-tools: Read, Glob, Grep, Bash(git status *), Bash(git diff *), Bash(gh pr view *), TodoWrite
model: opus
created: 2026-05-14
modified: 2026-07-18
compatibility: claude-code
reviewed: 2026-05-14
---

# Verify Before Plan

A premise is anything the orchestrator's plan asserts about the world without
having looked: "there are 41 SKILL.md files that need editing," "the
deprecated endpoint still has callers," "build is green on main," "the agent
must rewrite the manifest." Before a wave of parallel subagents fans out
against that premise, **verify it with a small read-only probe**. A wrong
premise propagates to every brief in the wave and wastes an entire wave's
worth of work — restarting is the only honest salvage.

## When to Use This Skill

| Use this skill when... | Skip when... |
|---|---|
| About to dispatch ≥2 parallel agents whose briefs cite a number, state, or path | Single-agent delegation — verify inline |
| The premise was carried in from an earlier message and not re-checked this session | The premise was produced by a tool call earlier in this same session |
| The user's report describes a symptom; the plan cites a cause | Waves entirely independent of repo state (e.g. brainstorming) |
| The plan assumes a tool/library/agent does X based on its name or docs | The behaviour is covered by a passing test the wave will re-run |
| The plan inherits a premise from another agent's return contract | The return contract already cites file:line evidence for the premise |

This skill sits **before** `parallel-agent-dispatch` in the dispatch
sequence. `parallel-agent-dispatch` covers the contract; this skill covers
the assumption the contract is built on.

## The Verification Protocol

### Step 1: Name the premise

State the load-bearing facts in one or two sentences, in the form the wave's
briefs will reference. Numbers, paths, and "does X" claims must be explicit
— "all the affected plugins" is not yet a premise.

### Step 2: Pick the cheapest verifier

| Premise shape | Verifier |
|---|---|
| File count / "N occurrences of …" | `Glob` or `Grep -c` directly from the main thread |
| "Does this tool/agent do X?" | Dispatch one read-only `general-purpose` agent: "Report what `<thing>` actually does, with file:line citations" |
| "Build is green / artefact exists" | One `Bash` call (`gh pr checks`, `ls path`, `git log --branches`) |
| "User's bug is X" | Read the failing log; do not patch the symptom |
| Manifest / counter snapshot | `Read` the file and quote the relevant lines |

Inline the verifier if it is one to three tool calls. Use a one-shot
investigation agent only when the answer requires multi-file synthesis.

### Step 3: Verifier return contract

The verifier — whether inline calls or a dispatched agent — must report:

```markdown
## Premise
<one-line restatement of what is being checked>

## Evidence
- file:line — <quoted finding>
- file:line — <quoted finding>

## Verdict
- confirmed | refuted | partial: <what changed>
- exact count / value: <N>
- sample paths: <up to 5>

## Implicit assumptions surfaced
- <assumptions the verifier had to make to answer>
- empty is fine — section must exist
```

Refuse to dispatch the wave until this report exists. "I'll check while
dispatching" loses the salvage argument before it starts.

### Step 4: Diff verdict against premise

If `confirmed`, dispatch as planned. If `refuted` or `partial`, revise the
plan: shrink the file scope, re-allocate per-agent IDs, drop agents that no
longer have work, re-write the brief that cites the refuted fact. Only then
dispatch.

## Anti-patterns

| Premise | How it fails | Verifier |
|---|---|---|
| "There are 41 SKILL.md files needing edits" | Actual was 28 — some plugins have no skills; 13 agents had empty briefs | `Glob("**/SKILL.md")` then count |
| "git-repo-agent supports X" (from the name) | Name ≠ behaviour; agent did not implement X | Read `agents/git-repo-agent/SKILL.md` |
| "The user says the bug is X" | Bug was a config typo two layers up; the X patch did nothing | Read the failing log / repro |
| "The plan says clear stuck Jobs" | Real root cause was an IdP password mismatch in ConfigMap; jobs were a symptom | Re-spelunk with one read-only agent |
| "Manifest counter is at WO-012" | Counter was bumped by a coworker mid-session | `Read` the manifest as the last act before allocation |
| "Build is green" (from morning standup) | Broke an hour ago; one wave-member tripped over the failing step | `gh pr checks` or `gh run list` |
| "All callers of the deprecated API are gone" | Two remained in a vendored copy outside the search root | `Grep` with a wide-enough path |

The unifying pattern: **the premise was true at some past moment, but the
current session has not confirmed it.** Time is the silent invalidator.

## Composition

| With … | Slot it in by … |
|---|---|
| `parallel-agent-dispatch` | Verify before the worktree-preflight; preflight assumes the file scope is right |
| `wave-based-dispatch` | Verify per wave — a Phase-1 wave's return contract is a premise for Phase 2 |
| `exclusive-lock-dispatch` | Verify the lock-holder list is current; locks come and go |
| `agent-teams` | The Lead Preflight Checklist's "file-scope and pin-budget" entries are premises |

## Quick Reference

### Orchestrator checklist (before any parallel dispatch)

- [ ] Premise named in one or two sentences with numbers and paths
- [ ] Verifier picked (inline call ≤ 3, otherwise one read-only agent)
- [ ] Verifier return contract followed (Premise / Evidence / Verdict / Assumptions)
- [ ] Verdict `confirmed` — or plan revised before dispatch
- [ ] Implicit assumptions logged for the wave's briefs

### Common mistakes

| Mistake | Correct approach |
|---|---|
| "Based on the name, X probably does Y" | Dispatch a read-only probe; cite file:line |
| "The user says the bug is X, so we patch X" | Read the failing repro before any patch |
| "The plan's remediation is X" | Verify the plan's premise; remediations inherit its truth-value |
| Verifying after dispatch ("I'll check while they work") | Verify first — re-running a wave costs more than the probe |
| Skipping the Verdict line — just summarising | The wave's briefs need a copy-pasteable fact, not a narrative |

## Related

- [`parallel-agent-dispatch`](../parallel-agent-dispatch/SKILL.md) — the
  dispatch contract whose preflight this skill protects
- [`wave-based-dispatch`](../wave-based-dispatch/SKILL.md) — per-wave
  premise verification fits cleanly between phases
- [`exclusive-lock-dispatch`](../exclusive-lock-dispatch/SKILL.md) — lock
  inventory is itself a premise
- `.claude/rules/regression-testing.md` — landing a verifier as a script
  check when a premise-failure recurs
- Motivating evidence: [issue #1283](https://github.com/laurigates/claude-plugins/issues/1283)
  — aggregate `wrong_approach` and `initial_misdiagnosis` signals across
  284 sessions
