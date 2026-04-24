---
name: exclusive-lock-dispatch
description: |
  Pre-dump-then-dispatch pattern for tools that hold an exclusive lock —
  Ghidra projects, database migration locks, single-writer caches, git
  indexes on shared checkouts, taskwarrior bulk modifications. Use when
  planning a parallel fan-out and one or more candidate agents would need
  a resource that cannot tolerate concurrent access, when a locked tool's
  "retry" errors are showing up in agent returns, or when deciding whether
  to serialise an agent or pre-compute its outputs. Complements
  parallel-agent-dispatch §Wave Splits and workflow-wave-dispatch.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# Exclusive-Lock Dispatch

The dispatch-time pattern for tools that hold an exclusive lock during
execution. Running such a tool from multiple parallel agents is a guaranteed
failure; running the same tool's *outputs* through many parallel agents is
the right shape.

## When to Use This Skill

| Use this skill when… | Use `parallel-agent-dispatch` alone when… |
|----------------------|-------------------------------------------|
| Two or more candidate agents would invoke the same lock-holding tool | No candidate agent touches a locked resource |
| A prior wave emitted lock-contention errors | Agents only read pre-computed artefacts |
| You are debating "serialise the agent or pre-dump the artefacts?" | File scopes are disjoint and lock-free |
| The tool in question is slow (decompilation, migration, compile) so re-running per agent would burn minutes | The lock holder is cheap enough to serialise without pre-dump |

## Canonical Locked Resources

| Tool / Resource | Lock Behaviour | Typical Symptom |
|-----------------|---------------|-----------------|
| Ghidra project (`.gpr`) | Single writer; second invocation fails | `Project is locked by another instance` |
| Database migration lock | Single writer per database | Migration tool blocks or errors |
| Git index on shared checkout (`.git/index.lock`) | Single writer per working tree | `index.lock` exists / cannot `git add` |
| Taskwarrior bulk modify (`task modify`, `task done` ranges) | Effectively single-writer for the task store | Sporadic "task database is locked" or lost edits |
| Single-writer build caches (ccache, cargo target/, Bazel action cache) | First writer serialises others | Spurious build failures or cache corruption |
| Decompiler output caches | Re-analysis on every access | Minutes-per-agent rerun when artefacts could be shared |

## The Anti-Pattern

```
Wave plan:
  Agent A: ghidra -process BIN --script ExtractStrings.java
  Agent B: ghidra -process BIN --script ExtractXrefs.java
  Agent C: ghidra -process BIN --script ExtractStructs.java
  Dispatched in parallel.
```

Second invocation refuses to open the project. The orchestrator receives
two "failed" returns and, without this skill's discipline, dispatches
*more* agents to "retry" — multiplying the lock contention.

## The Pattern

### Step 1 — One serialised run emits every artefact

Run the locked tool exactly once (or once per distinct artefact kind),
writing everything downstream agents will need into **gitignored scratch**.
Keep the outputs under a stable path that the brief can reference:

```
tmp/decomp/strings.txt
tmp/decomp/xrefs.json
tmp/decomp/structs.json
tmp/ghidra/analysis.log
```

The pre-dump agent runs alone in its wave. Its return contract includes
the artefact paths as "produced" so downstream waves can cite them.

### Step 2 — Downstream agents read, do not re-analyse

Parallel agents in the next wave take the pre-computed artefacts as input
and produce their implementation slabs from those. No lock-holder
invocations, no re-analysis, no contention.

Briefs must reference artefacts by path:

> "Input artefacts: `tmp/decomp/strings.txt`, `tmp/decomp/xrefs.json`.
> Treat as read-only. Do not re-run Ghidra."

### Step 3 — Wave boundaries enforce exclusivity

The orchestrator never places two lock-contenders in the same wave.
`workflow-wave-dispatch` handles the scheduling; this skill is the
pre-work that makes wide parallelism possible afterwards.

## When to Pre-Dump vs Dispatch Directly

| Situation | Decision |
|-----------|----------|
| N ≥ 2 candidate agents would each need a fresh analysis of the same source | **Pre-dump**: one serialised run, then fan out |
| Exactly one agent needs the lock and no siblings do | **Dispatch directly**: the lone agent serialises itself |
| Lock holder is fast (< 10s) and agents need fresh state | **Dispatch serially**: skip pre-dump, run agents one at a time |
| Lock holder is slow and agents need only a stable snapshot | **Pre-dump**: amortises the cost across the fan-out |

The pre-dump cost is paid once. Serialising N agents pays the lock cost
N times and removes any parallelism benefit.

## Ghidra Specifics

Ghidra is the most common pre-dump target. The 12.x release changed
scripting:

| Concern | Current-as-of-2026 Answer |
|---------|---------------------------|
| Scripting language | `.java` post-scripts (Jython removed in 12.x) |
| First-time vs re-run | `-import` on first run; `-process` once the binary is in the project |
| Skip analyzers on re-run | `-noanalysis` |
| Headless wrapper | `analyzeHeadless <project_dir> <project_name>` |
| Output destination | Post-script writes to stdout or to a file under `tmp/` |

A typical pre-dump recipe:

```bash
# First run: import and analyse once
analyzeHeadless tmp/ghidra/ myproj -import path/to/bin \
  -postScript ExtractEverything.java tmp/decomp/

# Later runs: re-use analysis
analyzeHeadless tmp/ghidra/ myproj -process bin -noanalysis \
  -postScript RefreshStrings.java tmp/decomp/
```

For more-than-a-few-scripts workflows, extract the detailed recipe and
script inventory to `REFERENCE.md` and cite it from here.

## Taskwarrior Specifics

The `~/.task/` store is single-writer in practice. Dispatching five
agents to each `task modify` different filters produces sporadic
"database is locked" errors and, worse, silently lost edits when one
agent's write races another's.

The rule is the same: one orchestrator-owned agent (or the orchestrator
itself) performs the bulk mutation, derived tasks the parallel siblings
need are emitted to gitignored scratch (`tmp/tasks.json`), and the
parallel wave reads from scratch.

## Quick Reference

### Pre-Dispatch Checklist

- [ ] Identified every locked resource across candidate agents
- [ ] Confirmed which agents need lock access vs which just need artefacts
- [ ] Decided pre-dump vs serial dispatch using the table above
- [ ] Pre-dump artefacts targeted at a gitignored path under `tmp/`
- [ ] Downstream briefs reference artefact paths, not the lock holder
- [ ] Lock-holder agent runs alone in its wave

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Dispatching N agents that each run the locked tool | Pre-dump once, fan out on artefacts |
| Retrying the locked agent on failure | Diagnose the lock, then either serialise or pre-dump |
| Committing `tmp/decomp/` or `tmp/ghidra/` | `.gitignore` the scratch directory |
| Briefing "and run Ghidra again to double-check" | Once the artefacts exist, treat them as authoritative |

## Related

- `parallel-agent-dispatch` — overall dispatch contract; §Wave Splits cites this skill
- `workflow-wave-dispatch` — wave scheduling between lock-holder and parallel waves
- `.claude/rules/parallel-safe-queries.md` — commands that exit 1 on empty, a different form of parallel foot-gun

> Evidence: six-wave renderer landing shipped with zero lock-contention
> retries after adopting pre-dump for the decompiler and the task queue.
> Before this discipline, ad-hoc parallel dispatches frequently consumed
> an entire wave recovering from lock errors.
