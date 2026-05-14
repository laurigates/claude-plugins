---
name: parallel-agent-dispatch
description: Dispatch contract for spawning parallel agents covering worktree collisions, scope overflow, and silent exits. Use when fanning out concurrent agents or authoring a lead prompt.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-04-21
modified: 2026-05-14
reviewed: 2026-05-14
---

# Parallel Agent Dispatch

Conventions that apply every time more than one agent runs in parallel. Prevents
the top failure modes observed across real multi-agent sessions: dirty-worktree
cross-contamination, context overflow mid-task, and silent exits that require
manual salvage from orphan branches.

## When to Use This Skill

| Use this skill when... | Use `agent-teams` instead when... |
|---|---|
| Spawning >1 agent via plain `Agent` tool fan-out (N concurrent invocations) | Single-agent delegation or one-off subagent spawn |
| Using `TeamCreate` + teammate spawn for coordinated parallel work | A simple background task with no parallel siblings |
| Running worktree-isolated parallel implementation across repos/features | A read-only inline subagent that does not write to disk |
| Coordinating parallel investigation or audit swarms | The work fits in the current session without forking |

## Dispatch from the Main Thread When Possible

`Agent`, `TeamCreate`, and other parallel-spawn tools may not be present in a sub-agent's sandbox even when they are available in the main conversation. Designing a fan-out from inside a coordinating sub-agent risks silent degradation to sequential single-thread execution — the wall-clock cost of a 5-way design landing in a 5× slower sequential mode.

When planning a parallel dispatch:

- **Default**: dispatch from the main conversation. The full tool surface is guaranteed.
- **Sub-agent orchestrator**: only when the team's outputs do not need to feed back into the main thread. Brief the sub-agent to verify tool availability up front and report sequential fallback as a first-class outcome (see `agent-teams` → "Sub-Agent Caveat: Spawn Teams from the Main Thread" for the detection contract).

## The Three Pillars

### 1. Worktree Preflight

Before spawning, the orchestrator must verify:

| Check | Rationale |
|-------|-----------|
| Main working tree is clean (`git status --porcelain` empty) | Agents inherit cwd; uncommitted changes cross-contaminate worktrees |
| No existing worktree at each planned path (`git worktree list`) | Nested or duplicate worktrees are the #1 source of salvage work |
| Each agent gets a **unique** branch name | Prevents commits landing on the wrong branch when cwd resolution drifts |
| Shared counters snapshot (next ADR/PRP number, feature-tracker IDs) | Prevents numbering collisions in parallel doc writes |

If any check fails, **refuse to dispatch** and report the blocker. Do not
"clean up" uncommitted user work — surface it and ask.

See also: `agent-teams` Lead Preflight Checklist for file-scope and pin-budget
checks that stack on top of these.

### 2. Scope Budget (per-agent prompt rules)

Every agent prompt must declare:

- **File scope**: exclusive write paths (glob or explicit list). No agent may
  write outside its declared scope. Out-of-scope discovery → stop and report
  (see `agent-teams`).
- **Read budget**: soft cap on files examined before producing output. A
  reasonable default is "≤10 files per exploration hop, ≤3 hops before
  returning a result."
- **Output budget**: expected length of the return summary. Discourages
  agents from echoing full file contents when a diff or line reference will do.

These budgets are what prevents the "security audit agent hit context limits"
and "prompt is too long" failure modes — without them, a well-intentioned
agent exhausts its window on exploration and truncates its actual deliverable.

#### Shared-File Exclusion List

Even when each agent's declared file scope is disjoint, a second list of
**orchestrator-only files** must be excluded from every agent's write-path.
These are the files that many agents are tempted to touch because their work
"relates to" them, and where last-writer-wins silently destroys earlier work.

Adapt this template to the repository's stack:

- Blueprint manifest (`docs/blueprint/manifest.json`) — ID registry, agents
  risk clobbering each other's pre-allocated IDs
- Per-project feature tracker (stats, phases, notes) — touched by every slab
- Top-level plan / roadmap docs — agents cite these, they do not edit them
- Build manifests (`CMakeLists.txt`, `pyproject.toml`, `package.json`,
  `Cargo.toml`, `go.mod`) — added-dependency edits are cross-cutting
- `justfile` / `Makefile` — new recipes land through the orchestrator so
  conflicting recipe names surface at review time
- Local task-queue stores (e.g. `~/.task/` for taskwarrior) — serialised
  writes, never concurrent

Every dispatched agent brief must call these out explicitly as **not in
scope**, regardless of what the agent's declared write-paths say. The
exclusion list belongs under a `### Orchestrator-only files` heading in
the brief, not buried in prose.

> Evidence: five-agent parallel dispatch, zero merge conflicts (2026-04-23).
> Before this discipline, informal dispatches suffered silent manifest
> clobbers (last-writer-wins) because each agent independently "also"
> updated the manifest.

#### Pre-Allocated Blueprint IDs

The Worktree Preflight table mandates a **shared counter snapshot**. That
snapshot must expand into **explicit per-agent ID assignment** in each
brief — "Use WO-012 for this slice. Other agents claim WO-013 and WO-014."

"Pick the next free ID" is a race condition under parallelism: two agents
read the same counter, both allocate the same number, the second commit
silently overwrites the first's manifest entry. Pre-allocation eliminates
the race; the orchestrator, running alone, is the only writer.

The same discipline applies to any shared monotonic identifier — ADR
numbers, migration sequences, feature-request codes, PRP slugs. If agents
need to reference them, the orchestrator assigns them up front.

> Evidence: pre-allocation was added after observing a silent WO-number
> collision in an early three-agent dispatch.

#### Wave Splits for Exclusive Locks

At dispatch time, check every candidate agent for resources with an
**exclusive lock**:

- Ghidra project lock (analyses fail on second concurrent invocation)
- Git index on a shared checkout (two agents in the same cwd contend)
- Database migration lock (single-writer)
- Task-queue bulk modifications (taskwarrior `task modify`, `task done`
  across many IDs)
- Single-writer caches (build outputs, compiled decompilation)

An agent that needs an exclusive lock **cannot share a wave** with another
lock-contender. Either dispatch the lock-holder alone and parallelise the
siblings afterwards, or pre-compute the locked tool's artefacts to
gitignored scratch so all downstream agents read-only siblings.

See `exclusive-lock-dispatch` for the full pattern.

#### Refactor-brief template

For bulk content rewrites (description tightening, naming sweeps),
use the brief shape that worked across six concurrent refactor
agents. Load-bearing: per-step ordering, a PRECIOUS list, a per-file cap.

```markdown
**Scope**: <glob>, capped at N files. Do NOT chain edits across files
you have not Read in this run.

**Procedure (per file)**: Read first, then propose, then Edit.
No batch-rewrites across unread files.

**PRECIOUS — preserve verbatim**: literal "Use when..." triggers,
sibling-skill cross-references, tool names, negative-scope clauses.

**Cut**: marketing prose, redundant restatement, adjective stacking.

**Final step**: run `<repo regression script>`; loop until exit 0
before emitting the Return Contract.
```

> Evidence: issue [#1279](https://github.com/laurigates/claude-plugins/issues/1279)
> — six agents, 41 plugins, cleanest batch hit 28.9% reduction with
> zero >250-char outliers. PR #1314 productizes the post-pass.

### 3. Return Contract (mandatory structured summary)

Every parallel agent must end its run with this schema as its final message,
regardless of success or failure:

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
- Anything explicitly out of scope or punted
- Empty is fine — the section must exist

## Issues encountered
- Hook fires, retries, test flakes, manual workarounds
- Unexpected findings worth surfacing (e.g. second root cause)
- Empty is fine — the section must exist

## Orchestrator action needed
- none | <one line: what the lead must do before next phase>
```

Include the schema verbatim in every dispatched agent's prompt under a heading
like `### Return contract (mandatory)`. Do not paraphrase — agents follow
concrete schemas more reliably than prose instructions.

#### Verbatim patches, not prose

**Orchestrator edits needed must be verbatim patches, not prose.** List
each shared file and provide the literal text the orchestrator will
paste: complete CMake blocks with surrounding context, full justfile
recipes including shebang, literal prose paragraphs for docs updates.
Prose-style "add X to Y" descriptions force the orchestrator to
re-derive the exact insertion point, which is measurably slower and
more error-prone. If the edit is a single-line insertion, still quote
the surrounding 2–3 lines so the paste target is unambiguous.

Agents should emit:

- Complete CMake / build-manifest blocks with surrounding context, ready
  for `Edit(old_string=…, new_string=…)`.
- Full justfile / Makefile recipes including shebang and every parameter.
- Literal prose paragraphs for docs updates — tracker evidence strings,
  plan bullets, format-spec paragraphs — not "update the port plan with
  findings about X."
- Exact line numbers where the orchestrator must insert, when the target
  is long.

The orchestrator's role for `Orchestrator action needed` is `Edit(old=…,
new=…)` — a mechanical operation, not prose synthesis. Brief agents
accordingly.

#### Agent authors the docs-update text the orchestrator pastes

The paired discipline: **the agent writes the final prose** for any
docs update its slice requires. Port-plan sub-bullets, feature-tracker
evidence strings, and format-spec paragraphs all belong in the agent's
return contract as finished sentences, ready to paste. The
orchestrator's job stays pure `Edit(old=…, new=…)` — no prose
synthesis, no re-summarising of what landed.

Evidence-strings in particular need agent authorship: the agent is the
only party that knows what actually landed in its commits, which test
cases passed, and which subtleties of the slice are worth recording.
Asking the orchestrator to compose that prose retroactively forces it
to re-read the agent's diff and produces a less faithful summary than
the agent could write inline.

> **Why this matters.** Across six sequential waves in a single
> session, every return that emitted verbatim patches paste-integrated
> cleanly in seconds. One earlier return that used prose ("add
> `src/foo.c` to `CMakeLists.txt`") forced the orchestrator to re-derive
> the exact insertion context — measurably slower and more error-prone.
> The verbatim-patch + agent-authored-prose pairing, not the parallel
> topology, is what made the multi-wave cadence sustainable.

### 4. Agent self-verification in bulk-edit briefs

When fanning out agents to bulk-edit content covered by a regression
script, the brief **must** include the script as the agent's own
final verification step before it reports completion. Exit 0 means
ship; non-zero means fix-and-re-run inside the same agent's budget.

This shifts validation from commit-time (orchestrator pre-commit) to
edit-time (per-agent). A regression that only one of six agents
introduces is cheap for that one agent to repair; the same regression
multiplied across all six and surfaced at the merge-wave pre-commit is
an aggregate fixer-pass.

Repository regression scripts to wire into briefs:

| Bulk edit | Agent's final verification step |
|-----------|--------------------------------|
| SKILL.md description rewrites | `python3 scripts/audit-skill-descriptions.py --strict-all` |
| Context-command edits in skill bodies | `bash scripts/lint-context-commands.sh` |
| `allowed-tools` / bash-permission edits | `bash scripts/plugin-compliance-check.sh` |

The brief must instruct: **run the script, read the output, and if
non-zero, re-edit and re-run before emitting the Return Contract.**
Treating the script as advisory ("flag any issues for the orchestrator")
defeats the purpose — the regression lands in the agent's diff and the
agent already has the context to fix it.

> **Evidence (2026-05-09 cascade).** Six refactor agents shortened
> descriptions across 41 plugins. Each agent believed it was preserving
> "Use when..." triggers, but 4 of the 6 silently introduced "Use to..."
> or "Use for..." variants that do not match the `audit-skill-descriptions.py`
> regex. The aggregate damage (68 `NO_TRIGGER` skills) only surfaced
> when pre-commit ran on the mega-commit — a single fixer-agent pass
> repaired them, but only because pre-commit forced the issue. If each
> refactor agent had run `audit-skill-descriptions.py --strict-all` as
> its last step and looped on failures, the regression would have been
> caught per-agent.

**Canonical example: PR #1314** (`agents-plugin/agents/refactor.md`).
That PR bakes this exact pattern into the repository's refactor agent:
it broadens the agent's bash permissions to cover the audit script and
mandates an audit post-pass before the agent reports done. New
bulk-edit dispatch briefs should follow the same shape — agents inherit
both the permission to run the script and the requirement to clear it.

Cross-reference `.claude/rules/regression-testing.md` for the catalogue
of regression scripts and the rule that every fixed bug ships with a
matching script check.

### 5. Reviewer-agent verification (verify-then-fix)

Self-attestation is unreliable: an agent can return `status: success`
with a half-written file or claim "tests pass" without running them.
For high-stakes dispatches (PR "ready to merge", security audits,
shared-state mutations), spawn a **separate reviewer agent** *after*
the worker reports done and *before* the orchestrator trusts it.

The reviewer:

- Runs in its **own worktree** (different cwd than the worker).
- Ideally uses a **different model** so the same blind spot does not pass.
- Receives the worker's claim and branch — not the reasoning trace —
  and re-derives a verdict from the diff.
- Returns the Return Contract: `success` = claim holds; `failed` =
  claim does not hold.

**Verify-then-fix loop**: on a reviewer flag, the orchestrator fixes
inline or dispatches a follow-up worker scoped to the regression.
Do **not** close on the worker's self-claim alone.

**Self-author guard for `gh pr` flows**: `gh pr review --reviewer
<user>` returns HTTP 422 when the target is the PR author. Brief
reviewers: *"Do not pass `--reviewer <author>`; if the dispatch lead
is the PR author, post inline comments instead."*

> Evidence: issue [#1239](https://github.com/laurigates/claude-plugins/issues/1239)
> — three parallel-dispatch rounds; verify-then-fix caught a "ready
> to merge" claim where helm-template did not confirm the hypothesis,
> and the self-author guard prevented HTTP 422 across every fix PR.

## Why the Schema Matters

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

## Who Pushes?

Agents push their own commits in the normal case — worktree isolation plus
per-agent branches makes this safe and keeps the main orchestrator context
lean. Centralizing pushes through the lead collapses the isolation benefit
and bloats the lead's transcript with N agents' worth of diffs.

Exceptions where the lead should push instead:

- **Web sandbox sessions** (`CLAUDE_CODE_REMOTE=true`) — teammates may hit
  TLS errors on push. See `agent-teams` Sandbox Considerations.
- **Cross-agent dependencies** where Phase 1 agents' commits must land
  together as a single merge base for Phase 2.
- **Explicit user instruction** ("I'll push manually, just commit").

Default remains: agent commits, agent pushes, agent opens its own PR, agent
reports the URL back in the Return Contract.

## Handling a Missing Return

If an agent exits without emitting the Return Contract:

1. Treat as a **silent stall**, not a success.
2. Check the agent's worktree for uncommitted work (`git status`) and
   committed-but-unpushed branches (`git log --branches --not --remotes`).
3. Either resume the agent with a message asking for the missing summary,
   or salvage the work yourself and file a tracking issue noting the stall.
4. Do **not** report the parent task as complete until every spawned agent
   has produced a Return Contract (or been explicitly accounted for).

### When the agent stalled at commit / push

The dominant cause of silent stalls in real parallel dispatches is a
**pre-commit hook blocking `git commit`** — typically a slow audit,
secrets scan, or lint that runs longer than the agent's effective
budget. The agent's `git commit` call is parked on the hook, no retry
fires, no Return Contract is emitted, and the agent's actual diff is
sitting intact in the worktree. Distinct from a transport-layer
rate-limit cascade (see below), this is a hook-layer stall with the
agent's work fully preserved.

**Symptoms** (any of):

- Return Contract reports `worktree: dirty: <files>` matching the
  agent's declared scope, with no `commits:` and no `pr:` line.
- No Return Contract at all, but `git -C <worktree> status --porcelain`
  shows staged or unstaged work in the agent's declared scope.
- Commits landed but the branch was never pushed
  (`git -C <worktree> log --oneline origin/main..HEAD` shows commits
  but the remote has none).

**Salvage routine** — do **not** discard the worktree. From the parent:

1. `cd <worktree>` and run `git status` — confirm the diff matches the
   agent's declared scope.
2. `git log --oneline origin/main..HEAD` — confirm whether commits
   already landed locally.
3. If commits landed but were never pushed:
   `git push -u origin <branch>` — done.
4. If the diff is uncommitted, run
   `pre-commit run --all-files 2>&1 | tail -40` to surface what
   blocked, fix the hook failure (or rerun the agent with the fix
   instructions), then commit on the agent's behalf preserving its
   intended commit message and push.

**Prevention.** Dispatch briefs should, at minimum, instruct the agent
to run `pre-commit run --files <its scope>` (or the project's
equivalent) **before** attempting `git commit`. This surfaces hook
failures inside the agent's reasoning budget, where the agent can fix
them, rather than at commit time where they manifest as a stall. Two
follow-up options if the project's hooks are still slow enough to risk
budget exhaustion:

- Pre-warm pre-commit hooks during worktree setup so the agent's first
  commit isn't the first hook run on the new worktree.
- Brief agents to commit with `--no-verify` and have the orchestrator
  run `pre-commit run --all-files` once before the merge wave. Trade-off:
  individual agent diffs may fail hooks; the merge-wave fixer must be
  ready to repair.

Add to every brief an explicit fallback: *"If `git commit` fails or
hangs, emit your Return Contract with `status: failed`,
`worktree: dirty: <files>`, and `Orchestrator action needed: pre-commit
hook X failed, fix and commit on my behalf."*

## Concurrent rate-limit risk

Opus 4.7 (1M) parents running **six or more** concurrent subagents can
hit `Server is temporarily limiting requests` partway through a wave.
Each `[1m]` request counts independently against the rate-limit
window, and the cascade tends to strike agents that have already
completed substantial work — surviving siblings finish cleanly, but
rate-limited agents return partial state with no Return Contract.
Matches the documented upstream issue
[anthropics/claude-code#33154](https://github.com/anthropics/claude-code/issues/33154).

**Mitigation**: cap concurrent agent dispatch at **≤ 5** for Opus 4.7
(1M) parents. Five was reliable across multiple sessions; six landed
at the edge of safe and produced the cascade in the evidence below.
When the fan-out genuinely needs more than five agents, dispatch in
waves (e.g. five now, the next batch when the first wave reports) or
stagger by ~30 seconds so the requests are not simultaneous.

**Recovery**. When a subagent returns with the rate-limit signature
(`API Error: Server is temporarily limiting requests · Rate limited`
plus `status: completed` and a partial scope), use the
**recovery-dispatch pattern**: re-dispatch the missed slice as a small
follow-up agent rather than retrying the entire wave. The successful
siblings' work is already on disk; only the rate-limited agent's
remaining scope needs another pass. Issue
[#1280](https://github.com/laurigates/claude-plugins/issues/1280)
documents this recovery shape as positive evidence — a single-agent
follow-up cleanly closed the gap left by a rate-limited cascade agent.

| Symptom | Action |
|---------|--------|
| 6+ agents queued at dispatch time | Split into waves of ≤ 5 |
| Wave returns with one or two `Rate limited` agents | Recovery-dispatch the missed slice; do not retry the whole wave |
| Same agent rate-limits twice in a row | Smaller scope or staggered dispatch — the wave size is still too high |

Cross-reference `.claude/rules/skill-fork-context.md`, which documents
the underlying `[1m]` rate-limit issue and lists the upstream tickets
(#16803, #27053, #33154, #6594) to track for upstream fixes.

## Composition with agent-teams

`agent-teams` covers the TeamCreate / SendMessage / TaskUpdate mechanics.
This skill adds the dispatch-time contract that applies to both team and
non-team parallel fan-out. When both apply, follow both — the out-of-scope
protocol from `agent-teams` slots naturally into the `Issues encountered`
and `Deferred / skipped` sections of the Return Contract here.

## Quick Reference

### Orchestrator Checklist

- [ ] Working tree clean; no conflicting worktrees
- [ ] Each agent has unique branch name and exclusive file scope
- [ ] Each prompt includes file/read/output budgets
- [ ] Each prompt includes the Return Contract schema verbatim
- [ ] Agents authorized to push their own commits (unless sandbox/dependency exception)
- [ ] Every returned summary parsed; missing returns treated as stalls

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Spawning agents from a dirty main tree | Commit or stash first; refuse to dispatch on dirty state |
| Scope described in prose, not glob | Explicit write-path list per agent |
| "Report back when done" with no schema | Include Return Contract verbatim in every prompt |
| Treating agent silence as success | No Return Contract = stall; investigate before reporting done |
| Centralizing pushes as a default | Agent pushes its own work; lead pushes only on sandbox/dependency exceptions |

## Related

- `agent-teams` — TeamCreate/SendMessage mechanics, out-of-scope discovery protocol
- `custom-agent-definitions` — agent file structure, tool restrictions, context forking
- `.claude/rules/agent-development.md` — agent authoring conventions
- `.claude/rules/sandbox-guidance.md` — when sandbox constraints override push defaults
