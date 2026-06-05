---
name: parallel-agent-dispatch
description: Dispatch contract for spawning parallel agents covering worktree collisions, scope overflow, and silent exits. Use when fanning out concurrent agents or authoring a lead prompt.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-04-21
modified: 2026-06-05
reviewed: 2026-06-05
---

# Parallel Agent Dispatch

Conventions that apply every time more than one agent runs in parallel.
Prevents the top failure modes observed across real multi-agent sessions:
dirty-worktree cross-contamination, context overflow mid-task, and silent
exits that require manual salvage from orphan branches.

For lookup tables, worked examples, evidence trails, and the detailed
salvage / recovery routines, see [REFERENCE.md](REFERENCE.md).

## When to Use This Skill

| Use this skill when... | Use `agent-teams` instead when... |
|---|---|
| Spawning >1 agent via plain `Agent` tool fan-out (N concurrent invocations) | Single-agent delegation or one-off subagent spawn |
| Using `TeamCreate` + teammate spawn for coordinated parallel work | A simple background task with no parallel siblings |
| Running worktree-isolated parallel implementation across repos/features | A read-only inline subagent that does not write to disk |
| Coordinating parallel investigation or audit swarms | The work fits in the current session without forking |

## Dispatch from the Main Thread When Possible

`Agent`, `TeamCreate`, and other parallel-spawn tools may not be present in a
sub-agent's sandbox even when they are available in the main conversation.
Designing a fan-out from inside a coordinating sub-agent risks silent
degradation to sequential single-thread execution — the wall-clock cost of a
5-way design landing in a 5× slower sequential mode.

When planning a parallel dispatch:

- **Default**: dispatch from the main conversation. The full tool surface is
  guaranteed.
- **Sub-agent orchestrator**: only when the team's outputs do not need to feed
  back into the main thread. Brief the sub-agent to verify tool availability up
  front and report sequential fallback as a first-class outcome (see
  `agent-teams` → "Sub-Agent Caveat: Spawn Teams from the Main Thread" for the
  detection contract).

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

#### Transient worktree leaks while a wave runs

`Agent(isolation: "worktree")` is supposed to be a sealed filesystem view,
but issue [#1319](https://github.com/laurigates/claude-plugins/issues/1319)
documents a transient leak: a file the child wrote inside its worktree
briefly appears in the **parent** as an untracked entry at the same
relative path, then vanishes when the child commits. While a wave is
running, the orchestrator must:

- Treat untracked files in the parent checkout as **potentially leaked
  from a child agent**. Do not stash, restore, or commit them.
- Wait for the child's completion notification, then diff the parent's
  orphan against the child's commit. Identical contents = leak; safe to
  let the child's branch reclaim it.
- Avoid `git commit` on the parent branch while child worktree agents
  are still running — a leaked file caught by `git add -A` lands on the
  wrong branch.

`/git:coworker-check` raises the verdict `worktree_leak_suspected` when
an untracked file in the parent matches a path in any linked worktree.
Run it before every parent-side commit during a wave.

#### cwd-reset leaking git writes into the main repo

Distinct from the transient-leak shape above: issue
[#1480](https://github.com/laurigates/claude-plugins/issues/1480)
documents a git-write agent under `isolation: "worktree"` whose bare
`git` commands ran against the **main checkout**, not its worktree. Agent
threads have their bash cwd reset between calls (documented behaviour),
and the reset landed on the session's primary cwd (the main repo root)
instead of the agent's worktree. Every `git fetch` / `git checkout -B` /
`git rebase --autostash` mutated `main` — sweeping the user's uncommitted
edits into an autostash that pop-conflicted, and leaving the main repo on
a stray branch. The orchestrator believed the work was sandboxed.

Brief every git-**write** agent dispatched under worktree isolation to be
resilient to the cwd reset:

- **Never assume `cwd == worktree`.** Capture the worktree root once and
  reference it absolutely. Either prefix every git call with
  `git -C "$WORKTREE" …`, or `cd "$WORKTREE"` and verify with `pwd` at the
  top of **each** bash call — the cwd does not persist between calls.
- **Pin the worktree path.** Run `git rev-parse --show-toplevel` on the
  first call, store it as `$WORKTREE`, and use that value thereafter
  rather than trusting the persisted cwd.
- **Forbid bare branch-switching / autostash.** A git-write agent must
  confirm it is inside its isolated worktree before any
  `git checkout -B` / `git rebase --autostash`; in the main repo these
  swallow the user's uncommitted work.

After a git-write agent returns, the orchestrator runs a **post-run
integrity check** on the main repo: `git -C <main-repo> branch
--show-current` and `git -C <main-repo> status --porcelain` must be
unchanged from before the dispatch. A changed branch or new dirty state
is silent main-repo mutation — treat it the same as a missing Return
Contract (see "Handling a Missing Return") and salvage before reporting
the task complete.

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
- **Output budget**: expected length of the return summary. Discourages agents
  from echoing full file contents when a diff or line reference will do.

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
exclusion list belongs under a `### Orchestrator-only files` heading in the
brief, not buried in prose.

> Evidence: five-agent parallel dispatch, zero merge conflicts (2026-04-23).
> Before this discipline, informal dispatches suffered silent manifest clobbers
> because each agent independently "also" updated the manifest.

#### Pre-Allocated Blueprint IDs

The Worktree Preflight table's **shared counter snapshot** must expand into
**explicit per-agent ID assignment** in each brief — "Use WO-012 for this
slice. Other agents claim WO-013 and WO-014."

"Pick the next free ID" is a race condition under parallelism: two agents read
the same counter, both allocate the same number, the second commit silently
overwrites the first's manifest entry. Pre-allocation eliminates the race —
the orchestrator, running alone, is the only writer. The same discipline
applies to any shared monotonic identifier: ADR numbers, migration sequences,
feature-request codes, PRP slugs.

#### Wave Splits for Exclusive Locks

At dispatch time, check every candidate agent for resources with an
**exclusive lock** — Ghidra project locks, the git index on a shared checkout,
database migration locks, taskwarrior bulk `task modify` / `task done` across
many IDs, single-writer build/decompilation caches.

An agent that needs an exclusive lock **cannot share a wave** with another
lock-contender. Either dispatch the lock-holder alone and parallelise the
siblings afterwards, or pre-compute the locked tool's artefacts to gitignored
scratch so all downstream agents are read-only siblings. See
`exclusive-lock-dispatch` for the full pattern.

#### Refactor-brief template

For bulk content rewrites (description tightening, naming sweeps), use the
per-step / PRECIOUS / per-file-cap brief shape. The full template and the
six-agent evidence (issue
[#1279](https://github.com/laurigates/claude-plugins/issues/1279)) live in
[REFERENCE.md → Refactor-brief template](REFERENCE.md#refactor-brief-template).

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

For the failure-mode → schema-field rationale (what each field catches and
why), see [REFERENCE.md → Failure modes](REFERENCE.md#failure-modes--schema-field).

#### Verbatim patches, not prose

**Orchestrator edits needed must be verbatim patches, not prose.** Provide the
literal text the orchestrator will paste — complete CMake blocks with
surrounding context, full justfile recipes including shebang, literal prose
paragraphs for docs updates. Prose-style "add X to Y" descriptions force the
orchestrator to re-derive the exact insertion point.

The paired discipline: **the agent writes the final prose** for any docs
update its slice requires. See
[REFERENCE.md → Verbatim patches](REFERENCE.md#verbatim-patches--detail-and-rationale)
for the worked-example detail and the multi-wave cadence evidence.

#### Loud-failure contract (never surrender silently)

A dispatched agent that hits a wall must say so **loudly**. The dominant
failure shape (issue
[#1422](https://github.com/laurigates/claude-plugins/issues/1422)) is an
agent that runs 50–200 tool calls, thrashes against hooks, then emits a
one-word final message — `Terminal.`, `Done.`, `Stopped.` — with no PR
URL, no error explanation, and no list of what is blocked. The harness
reads "no changes", cleans up the worktree, and the work is lost. A
one-word summary is **indistinguishable from success** to the
orchestrator, so it is treated as success and the failure is invisible.

Every dispatched agent's prompt must mandate this escalation, tied to the
Return Contract's `status` field:

| Outcome | The agent must return |
|---------|-----------------------|
| **Success** | PR URL **plus one summary metric** (test-count delta, line delta) — `status: success`. |
| **Partial blocker** | Commit and push the in-progress work to its branch, open a **draft PR**, and return its URL **plus an explicit "what's blocked" list** — `status: partial`. |
| **Total blocker** | Explain *exactly* what blocked it, which tools were denied, and what it tried — `status: failed`. Never a bare `Terminal.` / `Done.` / `Stopped.` |

The contract is one sentence the orchestrator pastes into every brief:
**"Your final message is the only thing I can act on — a one-word summary
loses all your work. On any blocker, push what you have, open a draft PR,
and tell me exactly what stopped you."**

Optional enforcement: a `SubagentStop` hook (see `hooks-plugin`) that
inspects the final message and, when it is under ~20 characters or matches
a bare-surrender pattern, injects a reminder asking the agent to elaborate
before terminating. This catches the silent-surrender case the prompt
contract alone can miss.

This is the *negative*-case complement to the positive clean-stop report
celebrated in issue #1393 — that issue covers an agent that stops cleanly
with a useful report; this contract covers the agent that stops *badly*.

### 4. Agent self-verification in bulk-edit briefs

When fanning out agents to bulk-edit content covered by a regression script,
the brief **must** include the script as the agent's own final verification
step before it reports completion. Exit 0 means ship; non-zero means
fix-and-re-run inside the same agent's budget.

This shifts validation from commit-time (orchestrator pre-commit) to edit-time
(per-agent). A regression that only one of six agents introduces is cheap for
that one agent to repair; the same regression multiplied across all six and
surfaced at the merge-wave pre-commit is an aggregate fixer-pass.

Repository regression scripts to wire into briefs:

| Bulk edit | Agent's final verification step |
|-----------|--------------------------------|
| SKILL.md description rewrites | `python3 scripts/audit-skill-descriptions.py --strict-all` |
| Context-command edits in skill bodies | `bash scripts/lint-context-commands.sh` |
| `allowed-tools` / bash-permission edits | `bash scripts/plugin-compliance-check.sh` |

The brief must instruct: **run the script, read the output, and if non-zero,
re-edit and re-run before emitting the Return Contract.** Treating the script
as advisory ("flag any issues for the orchestrator") defeats the purpose — the
regression lands in the agent's diff and the agent already has the context to
fix it.

See [REFERENCE.md → Bulk-edit self-verification](REFERENCE.md#bulk-edit-self-verification--worked-example)
for the 2026-05-09 cascade evidence and the PR #1314 canonical example.
Cross-reference `.claude/rules/regression-testing.md` for the catalogue of
regression scripts and the rule that every fixed bug ships with a matching
script check.

### 5. Reviewer-agent verification (verify-then-fix)

Self-attestation is unreliable: an agent can return `status: success` with a
half-written file or claim "tests pass" without running them. For high-stakes
dispatches (PR "ready to merge", security audits, shared-state mutations),
spawn a **separate reviewer agent** *after* the worker reports done and
*before* the orchestrator trusts it.

The reviewer:

- Runs in its **own worktree** (different cwd than the worker).
- Ideally uses a **different model** so the same blind spot does not pass.
- Receives the worker's claim and branch — not the reasoning trace — and
  re-derives a verdict from the diff.
- Returns the Return Contract: `success` = claim holds; `failed` = claim does
  not hold.

**Verify-then-fix loop**: on a reviewer flag, the orchestrator fixes inline or
dispatches a follow-up worker scoped to the regression. Do **not** close on
the worker's self-claim alone.

**Self-author guard for `gh pr` flows**: `gh pr review --reviewer <user>`
returns HTTP 422 when the target is the PR author. Brief reviewers: *"Do not
pass `--reviewer <author>`; if the dispatch lead is the PR author, post inline
comments instead."*

See [REFERENCE.md → Reviewer-agent verification](REFERENCE.md#reviewer-agent-verification--evidence)
for the three-round verify-then-fix evidence (issue #1239).

## Who Pushes?

Agents push their own commits in the normal case — worktree isolation plus
per-agent branches makes this safe and keeps the main orchestrator context
lean. Centralizing pushes through the lead collapses the isolation benefit and
bloats the lead's transcript with N agents' worth of diffs.

Exceptions where the lead should push instead:

- **Web sandbox sessions** (`CLAUDE_CODE_REMOTE=true`) — teammates may hit TLS
  errors on push. See `agent-teams` Sandbox Considerations.
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
3. Either resume the agent with a message asking for the missing summary, or
   salvage the work yourself and file a tracking issue noting the stall.
4. Do **not** report the parent task as complete until every spawned agent has
   produced a Return Contract (or been explicitly accounted for).

The dominant cause of silent stalls is a **pre-commit hook blocking
`git commit`** — the agent's diff sits intact in the worktree, the hook is
parked, no Return Contract fires. See
[REFERENCE.md → Agent stalled at commit / push](REFERENCE.md#agent-stalled-at-commit--push--salvage-routine)
for symptoms, the four-step salvage routine, and prevention briefs.

## Killing a Thrashing Agent Preserves Its Worktree

`TaskStop` does **not** discard the agent's work — its worktree stays on
disk with every uncommitted change intact. This makes `TaskStop` a
**recovery affordance**, not a last resort: when an agent is stuck or
thrashing — Bash:Edit ratio ≥ 9:1 **and** a rising `is_error` rate on
those Bash calls, typically `PreToolUse` hook blocks — killing it early
and salvaging the worktree beats waiting for it to give up silently
80–200 tool calls later. See
[REFERENCE.md → When to kill early](REFERENCE.md#killed-agent-worktree-recovery-taskstop)
for the full quantitative thresholds and the rate-limit vs hook-block
discriminator.

After `TaskStop`, decide **salvage vs restart** from the worktree state:

| Worktree state | Decision |
|----------------|----------|
| Substantive diff vs `origin/main` (the agent did the hard part) | **Salvage** — finish in the parent session, commit, push, open the PR |
| Empty / trivial diff, or the design itself was wrong | **Restart** — `git worktree remove <path>` first, then re-dispatch |

Quick triage inside the worktree: `git status`, `git diff origin/main
--stat`, `git log --oneline -5`. The agent's exploration and partial
implementation are not wasted even when the agent itself failed — which
matters most for refactors with heavy design-time work. See
[REFERENCE.md → Killed-agent worktree recovery](REFERENCE.md#killed-agent-worktree-recovery-taskstop)
for the full recovery checklist and evidence.

## Concurrent rate-limit risk

Opus 4.7 (1M) parents running **six or more** concurrent subagents can hit
`Server is temporarily limiting requests` partway through a wave. Each `[1m]`
request counts independently against the rate-limit window; the cascade tends
to strike agents that have already completed substantial work, so surviving
siblings finish cleanly while rate-limited agents return partial state with no
Return Contract. Matches upstream
[anthropics/claude-code#33154](https://github.com/anthropics/claude-code/issues/33154).

**Mitigation**: cap concurrent agent dispatch at **≤ 5** for Opus 4.7 (1M)
parents. When the fan-out genuinely needs more, dispatch in waves (five now,
the next batch when the first reports) or stagger by ~30 seconds. For the
**recovery-dispatch pattern** when a wave returns with one or two
`Rate limited` agents, see
[REFERENCE.md → Concurrent rate-limit recovery](REFERENCE.md#concurrent-rate-limit-risk--recovery-dispatch-routine).

Cross-reference `.claude/rules/skill-fork-context.md` for the underlying
`[1m]` rate-limit issue and the upstream tickets (#16803, #27053, #33154,
#6594) to track for fixes.

## Composition with agent-teams

`agent-teams` covers the TeamCreate / SendMessage / TaskUpdate mechanics.
This skill adds the dispatch-time contract that applies to both team and
non-team parallel fan-out. When both apply, follow both — the out-of-scope
protocol from `agent-teams` slots naturally into the `Issues encountered` and
`Deferred / skipped` sections of the Return Contract here.

## Quick Reference

### Orchestrator Checklist

- [ ] Working tree clean; no conflicting worktrees
- [ ] Each agent has unique branch name and exclusive file scope
- [ ] Each prompt includes file/read/output budgets
- [ ] Each prompt includes the Return Contract schema verbatim
- [ ] Each prompt mandates the loud-failure contract (no one-word surrenders on a blocker)
- [ ] Agents authorized to push their own commits (unless sandbox/dependency exception)
- [ ] Every returned summary parsed; missing returns treated as stalls

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Spawning agents from a dirty main tree | Commit or stash first; refuse to dispatch on dirty state |
| Scope described in prose, not glob | Explicit write-path list per agent |
| "Report back when done" with no schema | Include Return Contract verbatim in every prompt |
| Treating agent silence as success | No Return Contract = stall; investigate before reporting done |
| Accepting a one-word final message (`Terminal.`/`Done.`) as success | Mandate the loud-failure contract: on any blocker, push work, open a draft PR, explain what stopped |
| Centralizing pushes as a default | Agent pushes its own work; lead pushes only on sandbox/dependency exceptions |

## Related

- [REFERENCE.md](REFERENCE.md) — failure-mode table, refactor-brief template, salvage routines, evidence trails
- `agent-teams` — TeamCreate/SendMessage mechanics, out-of-scope discovery protocol
- `custom-agent-definitions` — agent file structure, tool restrictions, context forking
- `.claude/rules/agent-development.md` — agent authoring conventions
- `.claude/rules/sandbox-guidance.md` — when sandbox constraints override push defaults
