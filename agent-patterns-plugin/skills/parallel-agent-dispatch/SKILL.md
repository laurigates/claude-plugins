---
name: parallel-agent-dispatch
description: Dispatch contract for spawning parallel agents covering worktree collisions, scope overflow, and silent exits. Use when fanning out concurrent agents or authoring a lead prompt.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-04-21
modified: 2026-08-22
compatibility: claude-code
reviewed: 2026-07-05
---

# Parallel Agent Dispatch

Conventions that apply every time more than one agent runs in parallel. Prevents
the top failure modes observed across real multi-agent sessions: dirty-worktree
cross-contamination, context overflow mid-task, and silent exits that require
manual salvage from orphan branches.

Supporting material is split across `references/` by the path that needs it;
[REFERENCE.md](REFERENCE.md) is the index. Sections below link the specific file.

## When to Use This Skill

| Use this skill when... | Use `agent-teams` instead when... |
|---|---|
| Spawning >1 agent via plain `Agent` tool fan-out (N concurrent invocations) | Single-agent delegation or one-off subagent spawn |
| Using the implicit team + teammate spawn for coordinated parallel work | A simple background task with no parallel siblings |
| Running worktree-isolated parallel implementation across repos/features | A read-only inline subagent that does not write to disk |
| Coordinating parallel investigation or audit swarms | The work fits in the current session without forking |

## Dispatch from the Main Thread When Possible

`Agent` and other parallel-spawn tools may be absent from a sub-agent's sandbox
even when available in the main conversation, so designing a fan-out from inside
a coordinating sub-agent risks silent degradation to sequential execution.

- **Default**: dispatch from the main conversation — the full tool surface is
  guaranteed.
- **Sub-agent orchestrator**: only when the team's outputs need not feed back
  into the main thread. Brief it to verify tool availability up front and report
  sequential fallback as a first-class outcome (`agent-teams` → "Sub-Agent
  Caveat").

## The Three Pillars

### 1. Worktree Preflight

Before spawning, the orchestrator must verify:

| Check | Rationale |
|-------|-----------|
| Main working tree is clean (`git status --porcelain` empty) | Agents inherit cwd; uncommitted changes cross-contaminate worktrees |
| No existing worktree at each planned path (`git worktree list`) | Nested or duplicate worktrees are the #1 source of salvage work |
| Each agent gets a **unique** branch name | Prevents commits landing on the wrong branch when cwd resolution drifts |
| **Fixed target branch name not already taken** (see Target-branch preflight below) | A conventional per-issue/milestone name is one two sessions pick identically; the collision otherwise surfaces only at end-of-task rename |
| Shared counters snapshot (next ADR/PRP number, feature-tracker IDs) | Prevents numbering collisions in parallel doc writes |

If any check fails, **refuse to dispatch** and report the blocker. Do not
"clean up" uncommitted user work — surface it and ask.

**Target-branch preflight (#1969).** `isolation: "worktree"` auto-names the
branch; renaming onto a **fixed** conventional name another session's worktree
already holds is refused only at the end-of-task rename, deep into the run (real
case: two sessions both reached PR-open → duplicate-PR reconcile). Check the name
is free first (`git branch -a --list "$target"`, `git worktree list`,
`git ls-remote --heads origin "$target"`); any hit ⇒ **stop and reconcile**, not
race to a duplicate PR (`.claude/rules/concurrent-session-pr-check.md`).
**Mitigation:** push via explicit refspec (`git push origin HEAD:$target`)
instead of renaming. See
[references/worktree-hazards.md → Target-branch preflight](references/worktree-hazards.md#target-branch-preflight-1969).

**Transient worktree leaks (#1319).** While a wave runs, a file a child wrote
inside its worktree can briefly appear in the **parent** as an untracked entry
at the same relative path, then vanish when the child commits. Do not stash,
restore, or commit untracked parent files during a wave; wait for the child's
completion, then let its branch reclaim the file. `/git:coworker-check` raises
`worktree_leak_suspected` for this — run it before every parent-side commit.

**cwd-reset leaking git writes (#1480).** Distinct from the transient leak: an
agent thread's bash cwd resets between calls and can land on the main repo root,
so a git-**write** agent's bare commands mutate `main` instead of its worktree.
Brief every git-write agent: pin the root once
(`git rev-parse --show-toplevel` → `$WORKTREE`) and prefix every call with
`git -C "$WORKTREE" …`; forbid bare `git checkout -B` / `git rebase --autostash`
until inside the worktree. After the agent returns, run the post-run main-repo
integrity check (see [references/worktree-hazards.md → cwd-reset
guardrail](references/worktree-hazards.md#worktree-cwd-reset-guardrail-1480)) —
a changed branch or new dirty state is silent main-repo mutation.

**`GIT_DIR`/`GIT_WORK_TREE` export leak (#1692 sibling).** A worktree reporting
`core.bare = true` is shared-checkout corruption — **STOP and report it**; never
"work around" it by exporting `GIT_DIR`/`GIT_WORK_TREE`, which **override
`git -C`** so every later git call targets the shared common config, breaking
**all** sibling worktrees at once. A subprocess that must run git in a sandbox
neutralizes inherited env first:
`env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" …`. See
[references/worktree-hazards.md → GIT_DIR-export leak](references/worktree-hazards.md#worktree-git_dir-export-leak-1692).

**Nested-repo workspaces — `isolation: "worktree"` isolates the *outer* repo (#1838).**
The harness worktrees the **session's** repo, not the repo the agent was told to
edit, so in a portfolio layout the target files are **absent** from the worktree
and the agent's only path to them is the shared checkout — which the Edit-tool
isolation guard correctly blocks. Detect it before dispatch:
`git -C <target-dir> rev-parse --show-toplevel` ≠ `git rev-parse --show-toplevel`;
when they differ, isolate the **nested** repo explicitly. See
[references/worktree-hazards.md → Nested-repo isolation](references/worktree-hazards.md#nested-repo-worktree-isolation-1838)
for the detection script and rules.

**Concurrent agents default to the *same* scratchpad path (#2370).** Sibling
subagents share the session scratchpad, so two agents each told to "make your own
clone" pick the identical path and silently operate **one working tree**. Give
each an explicit, distinct path (`<scratchpad>/<agent-name>`) whenever they work
outside worktree isolation — which the nested-repo case above forces. See
[references/worktree-hazards.md → Shared scratchpad collisions](references/worktree-hazards.md#shared-scratchpad-collisions-2370).

**A deleted worktree kills the agent's shell, not its reasoning (#2372).** Every
Bash call then fails, and a spawned subagent inherits the same dead cwd. See
[references/worktree-hazards.md → Deleted worktree](references/worktree-hazards.md#deleted-worktree-kills-the-shell-not-the-agent-2372).

**`isolation: "remote"` may resolve to a LOCAL worktree (#2447).** The tool
result never says which mode ran; `git worktree list` and the notification's
`worktreePath` are the tells. An empty remote is evidence about the **push**,
not the **work** — audit local worktrees alongside `gh pr list` / `git
ls-remote` before calling work lost, and brief agents to open a **draft PR
early**, pushing after each commit. See
[references/worktree-hazards.md → isolation: "remote"](references/worktree-hazards.md#isolation-remote-may-resolve-to-a-local-worktree-2447).

### 2. Scope Budget (per-agent prompt rules)

Every agent prompt must declare:

- **File scope**: exclusive write paths (glob or explicit list). Out-of-scope
  discovery → stop and report (see `agent-teams`).
- **Read budget**: soft cap on files examined (default "≤10 files per hop, ≤3
  hops before returning").
- **Output budget**: expected length of the return summary — discourages echoing
  full file contents when a diff or line reference will do.

These budgets prevent the "agent hit context limits" and "prompt too long"
failure modes — without them an agent exhausts its window on exploration and
truncates its deliverable.

**Orchestrator-only files.** Even with disjoint write scopes, shared files must
be excluded from every agent's write-path under an `### Orchestrator-only files`
heading in the brief: the blueprint manifest (ID registry), the feature tracker,
top-level plan/roadmap docs, build manifests, `justfile`/`Makefile`, and local
task-queue stores. Last-writer-wins silently destroys earlier work on these. See
[references/brief-templates.md](references/brief-templates.md) for the full
template and evidence.

**Pre-allocated IDs.** The shared-counter snapshot must expand into **explicit
per-agent ID assignment** in each brief ("Use WO-012; others claim WO-013/014").
"Pick the next free ID" is a race under parallelism. Applies to any shared
monotonic identifier (ADR, migration, PRP).

**Wave splits for exclusive locks.** An agent needing an exclusive lock (Ghidra
project lock, shared git index, migration lock, taskwarrior bulk ops,
single-writer caches) cannot share a wave with another lock-contender. Dispatch
it alone, or pre-compute its artefacts so downstream agents are read-only. See
`exclusive-lock-dispatch`.

**Refactor briefs.** For bulk content rewrites, use the per-step / PRECIOUS /
per-file-cap shape — see [references/brief-templates.md → Refactor-brief template](references/brief-templates.md#refactor-brief-template).

### 3. Return Contract (mandatory structured summary)

Every parallel agent must end its run with a structured `## Result` summary as
its final message, regardless of success or failure (status / branch / pr /
commits / worktree, plus Scope delivered, Deferred, Issues encountered, and
Orchestrator action needed). Include the schema **verbatim** in every dispatched
agent's prompt under a heading like `### Return contract (mandatory)` — agents
follow concrete schemas more reliably than prose. Copy the full schema from
[references/dispatch-contract.md → Return Contract schema](references/dispatch-contract.md#return-contract-schema);
for the failure-mode → schema-field rationale, see
[references/dispatch-contract.md → Failure modes](references/dispatch-contract.md#failure-modes--schema-field).

Orchestrator edits needed must be **verbatim patches, not prose** (literal CMake
blocks, full justfile recipes, literal doc paragraphs), and the agent writes the
final prose for any docs update its slice requires. See
[references/brief-templates.md → Verbatim patches](references/brief-templates.md#verbatim-patches--detail-and-rationale).

#### Loud-failure contract (never surrender silently)

A dispatched agent that hits a wall must say so **loudly**. The dominant failure
shape (issue [#1422](https://github.com/laurigates/claude-plugins/issues/1422))
is an agent that runs 50–200 tool calls, thrashes against hooks, then emits a
one-word final message — `Terminal.`, `Done.`, `Stopped.` — with no PR URL and
no blocked list. That is **indistinguishable from success** to the orchestrator,
so the harness reads "no changes", cleans up the worktree, and the work is lost.

Tie the escalation to the Return Contract's `status` field:

| Outcome | The agent must return |
|---------|-----------------------|
| **Success** | PR URL **plus one summary metric** (test/line delta) — `status: success` |
| **Partial blocker** | Push the WIP, open a **draft PR**, return its URL **plus an explicit "what's blocked" list** — `status: partial` |
| **Total blocker** | Explain *exactly* what blocked it, which tools were denied, what it tried — `status: failed`. Never a bare `Terminal.` / `Done.` / `Stopped.` |

The one-sentence contract to paste into every brief: **"Your final message is
the only thing I can act on — a one-word summary loses all your work. On any
blocker, push what you have, open a draft PR, and tell me exactly what stopped
you."** Optional enforcement: a `SubagentStop` hook that flags sub-~20-char or
bare-surrender final messages (see `hooks-plugin`).

A workflow harness does not replace this contract; it turns what prose can only
*request* into what a runtime *enforces*. The prose→primitive mapping, its two
cautions, and the cost gate before reaching for one:
[references/dispatch-contract.md → Workflow primitives](references/dispatch-contract.md#the-return-contract-as-workflow-primitives).

### 4. Agent self-verification in bulk-edit briefs

When fanning out agents to bulk-edit content covered by a regression script, the
brief **must** include the script as the agent's own final verification step.
Exit 0 means ship; non-zero means fix-and-re-run inside the same agent's budget —
shifting validation from commit-time to edit-time.

| Bulk edit | Agent's final verification step |
|-----------|--------------------------------|
| SKILL.md description rewrites | `python3 scripts/audit-skill-descriptions.py --strict-all` |
| Context-command edits in skill bodies | `bash scripts/lint-context-commands.sh` |
| `allowed-tools` / bash-permission edits | `bash scripts/plugin-compliance-check.sh` |

Treating the script as advisory defeats the purpose — the regression lands in
the agent's diff and the agent already has the context to fix it. See
[references/brief-templates.md → Bulk-edit self-verification](references/brief-templates.md#bulk-edit-self-verification--worked-example)
and `.claude/rules/regression-testing.md`.

**Closed-list mechanical batches need a completion manifest, not just a
self-report.** A `refactor` agent assigned a fixed list (symbols to delete, files
to touch) must emit a machine-checkable manifest of what it completed — and
**never** trust that manifest alone: re-run the authoritative checker (`knip` /
build / test) afterward and diff against the assignment. A truncated or
optimistic summary reads as success even when the batch fell short (issue
[#1601](https://github.com/laurigates/claude-plugins/issues/1601): a ~23-symbol
batch completed only ~5, invisible until `knip` was re-run). Cap the per-agent
batch so an early stop costs little. See
[references/brief-templates.md → Refactor-brief template](references/brief-templates.md#refactor-brief-template).

### 5. Reviewer-agent verification (verify-then-fix)

Self-attestation is unreliable. For high-stakes dispatches (PR "ready to merge",
security audits, shared-state mutations), spawn a **separate reviewer agent**
*after* the worker reports done and *before* trusting it. The reviewer runs in
its own worktree, ideally a different model, receives the claim and branch (not
the reasoning trace), and re-derives a verdict from the diff. On a flag, fix
inline or dispatch a follow-up worker — do not close on the worker's self-claim.

**Self-author guard for `gh pr` flows**: `gh pr review --reviewer <user>` returns
HTTP 422 when the target is the PR author; brief reviewers to post inline
comments instead. See [references/brief-templates.md → Reviewer-agent verification](references/brief-templates.md#reviewer-agent-verification--evidence).

## Who Pushes?

Agents push their own commits in the normal case — worktree isolation plus
per-agent branches makes this safe and keeps the lead context lean. The lead
pushes instead only for: **web sandbox sessions** (`CLAUDE_CODE_REMOTE=true`,
where teammates may hit TLS errors on push — see `agent-teams`), **cross-agent
dependencies** where Phase 1 commits must land as a single merge base for Phase
2, and **explicit user instruction** ("I'll push manually").

## Handling a Missing Return

If an agent exits without emitting the Return Contract, treat it as a **silent
stall, not a success**. Before deciding, **discriminate empty vs dirty
worktree**:

```bash
git -C <worktree> status --porcelain
git -C <worktree> log --oneline origin/main..HEAD
```

- **Dirty / commits present** → the agent did the work; **salvage** it
  (commit/push the WIP, open the PR) rather than re-dispatching.
- **Empty / trivial diff** → nothing to salvage; resume or re-dispatch.

Do **not** report the parent task complete until every spawned agent has produced
a Return Contract (or been explicitly accounted for). Two causes leave the work
intact: a pre-commit hook blocking `git commit`, or a rate-limit cut-off after
the implementation but before the StructuredOutput call (issue
[#1491](https://github.com/laurigates/claude-plugins/issues/1491)).

Defensive mitigation: instruct worktree-isolated agents to commit
**WIP at checkpoints** — after each substantive slice and before they would
terminate — so partial work survives a lost structured result. See
[references/failure-recovery.md → Agent stalled at commit / push](references/failure-recovery.md#agent-stalled-at-commit--push--salvage-routine)
and [references/failure-recovery.md → WIP salvage before re-dispatch](references/failure-recovery.md#wip-salvage-before-re-dispatch-1491).

### Idle without report (#2039)

An implementer can **finish its work** (clean commit + tree) then go idle
emitting only an `idle_notification` — the work isn't lost, the *communication*
is (intermittent; siblings can deliver fine). Not a failure signal: run the
empty-vs-dirty check above, then `SendMessage` the named agent to resend the
Return Contract (read-only, so the #1546 caveat below does not apply). Never
respawn — a fresh agent lacks context and can't take the branch. Prevention:
implementers `SendMessage` the report to the lead as their final act. See
[references/failure-recovery.md → Idle without report](references/failure-recovery.md#idle-without-report-2039).

## Killing a Thrashing Agent Preserves Its Worktree

`TaskStop` does **not** discard the agent's work — its worktree stays on disk
with every uncommitted change intact, making `TaskStop` a **recovery
affordance**. When an agent is thrashing (high Bash:Edit ratio with a rising
error rate on hook-blocked Bash calls), killing it early and salvaging beats
waiting for a silent give-up. Then decide from the worktree state:

| Worktree state | Decision |
|----------------|----------|
| Substantive diff vs `origin/main` | **Salvage** — finish in the parent session, commit, push, open the PR |
| Empty / trivial diff, or wrong design | **Restart** — `git worktree remove <path>` first, then re-dispatch |

For the quantitative kill thresholds and the rate-limit vs hook-block
discriminator, see [references/failure-recovery.md → Killed-agent worktree recovery](references/failure-recovery.md#killed-agent-worktree-recovery-taskstop).

## Concurrent Rate-Limit Risk

`[1m]` parents running **six or more** concurrent subagents can hit `Server is
temporarily limiting requests` partway through a wave (distinct from your account
usage limit; varies by time of day). "It worked with N agents yesterday" is not
a guarantee. **Start conservative, then scale up:**

| Agent profile | Safe starting concurrency |
|---|---|
| Heavy (installs / builds / long tool chains) | **2–3** |
| Light (read-only analysis, single-file edits) | up to 5 |

Prefer **sequential waves of small batches** over one big fan-out beyond ~4
heavy agents, and treat the rate-limit signal as **backoff-and-retry, not task
failure** — re-dispatch rejected agents with backoff *and reduced concurrency*.
When the burst killed agents **at startup**, the dead worktrees leave empty
branch refs behind: `git worktree prune` and delete them before the retry, or
each agent's `git switch -c <branch>` collides with the leftover ref.
See [references/failure-recovery.md → Concurrent rate-limit recovery](references/failure-recovery.md#concurrent-rate-limit-risk--recovery-dispatch-routine)
and `.claude/rules/skill-fork-context.md`.

## Skill-less agentType for Read-Only Fan-Out

For read-only / structured-output fan-out — classification, verification, audit
sweeps where each agent **reads files and emits a result, nothing more** —
dispatch a **Skill-less agentType** rather than `general-purpose`. A
`general-purpose` subagent carries the `Skill` tool, which injects a
**`skill_listing` attachment (~88k chars / ~22k tokens)** plus a
`deferred_tools_delta` (~3k tokens) *before its first tool call*; add file reads
and a forced `StructuredOutput` schema and that ~25k fixed tax pushes the
subagent over its window (`Prompt is too long`, 40–100% batch failures — issue
[#1549](https://github.com/laurigates/claude-plugins/issues/1549)). Agents
without the `Skill` tool receive **no `skill_listing` injection at all**.

| Fan-out need | agentType | Why |
|---|---|---|
| Read-only classify / verify / audit | `agents-plugin:review` | Read/Glob/Grep, no `Skill` tool → no `skill_listing` tax; its review system prompt does not interfere given an explicit rubric + schema |
| Read **plus** `Write` (e.g. emit a report file) | `agents-plugin:docs` | Same Skill-less lean tool set, with write capability |
| Genuinely needs the skill catalog or broad `Bash` (`gh`/`task` filing) | `general-purpose` | The ~25k tax is only worth paying when the catalog is actually used |

Preserve `agents-plugin:review`'s lean, no-`Skill` tool set when reaching for it
as a fan-out building block. See
[references/dispatch-contract.md → Skill-less agentType](references/dispatch-contract.md#skill-less-agenttype--evidence);
sibling authoring guidance is in `custom-agent-definitions`.

## Composition with agent-teams

`agent-teams` covers the implicit-team / SendMessage / TaskUpdate mechanics; this
skill adds the dispatch-time contract that applies to both team and non-team
fan-out. When both apply, follow both — the out-of-scope protocol from
`agent-teams` slots into the `Issues encountered` / `Deferred` sections here.

### Resuming agents: SendMessage loses worktree isolation

`SendMessage`-resume of a **completed** worktree-isolated agent does **not**
re-enter that agent's worktree — the resumed run executes in the
**orchestrator's main checkout**, so the resume **loses worktree isolation**;
resuming several file-mutating agents this way runs them concurrently in the
main checkout and tangles branch state (issue
[#1546](https://github.com/laurigates/claude-plugins/issues/1546)).

| Continuation | Safe to `SendMessage`-resume? | Do instead |
|---|---|---|
| Read-only / single-checkout follow-up | Yes — no worktree to re-enter | Resume freely |
| Parallel **file-mutating** agent that must stay in its worktree | No — resume runs in the main checkout | **Re-dispatch a fresh `Agent` with `isolation: "worktree"`** |

### Resuming a workflow: `resumeFromRunId` re-runs succeeded worktree agents

`Workflow({resumeFromRunId})`'s "completed `agent()` calls return cached
results" holds for ordinary agents but **not** for `isolation: "worktree"`
ones: a worktree agent that **already succeeded** is **re-executed** on resume,
re-firing its outward side effects — an agent that opened a PR opens a
**duplicate** (PR #1858 dup of #1857; issue
[#1868](https://github.com/laurigates/claude-plugins/issues/1868)). Opposite
failure to the `SendMessage` case above (there the resume loses its worktree;
here it re-runs the whole agent).

So to retry a few failed worktree agents, do **not** resume the whole run —
**re-dispatch only the failed agents** in a fresh **sequential** pass (which
also dodges the burst rate limit), checking for an already-open PR first
(`gh pr list --state all --search …`, reading `state`/`mergedAt` per
`.claude/rules/gh-json-fields.md`). Non-worktree stages cache correctly. See
`.claude/rules/agent-coworker-detection.md`.

## Quick Reference

### Orchestrator Checklist

- [ ] Working tree clean; no conflicting worktrees
- [ ] Each agent has unique branch name and exclusive file scope
- [ ] Each prompt includes file/read/output budgets
- [ ] Each prompt includes the Return Contract schema verbatim
- [ ] Each prompt mandates the loud-failure contract (no one-word surrenders)
- [ ] Agents authorized to push their own commits (unless sandbox/dependency exception)
- [ ] Every returned summary parsed; missing returns treated as stalls

### Common Mistakes

| Mistake | Correct Approach |
|---------|-----------------|
| Spawning agents from a dirty main tree | Commit or stash first; refuse to dispatch on dirty state |
| Scope described in prose, not glob | Explicit write-path list per agent |
| "Report back when done" with no schema | Include Return Contract verbatim in every prompt |
| Treating agent silence as success | No Return Contract = stall; investigate before reporting done |
| Respawning after an `idle_notification` with no report | Check the branch, then `SendMessage` the agent to resend the report (#2039) |
| Accepting a one-word final message (`Terminal.`/`Done.`) | Mandate the loud-failure contract: push work, open a draft PR, explain |
| Centralizing pushes as a default | Agent pushes its own work; lead pushes only on sandbox/dependency exceptions |

## Related

- [REFERENCE.md](REFERENCE.md) — index over `references/`: dispatch contract, brief templates, failure recovery, worktree hazards
- `agent-teams` — implicit-team / SendMessage mechanics, out-of-scope discovery protocol
- `custom-agent-definitions` — agent file structure, tool restrictions, context forking
- `.claude/rules/agent-development.md` — agent authoring conventions
- `.claude/rules/sandbox-guidance.md` — when sandbox constraints override push defaults
