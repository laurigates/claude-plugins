---
name: parallel-agent-dispatch
description: Dispatch contract for spawning parallel agents covering worktree collisions, scope overflow, and silent exits. Use when fanning out concurrent agents or authoring a lead prompt.
user-invocable: false
allowed-tools: Read, Glob, Grep, TodoWrite
model: opus
created: 2026-04-21
modified: 2026-07-05
reviewed: 2026-07-05
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
| Using the implicit team + teammate spawn for coordinated parallel work | A simple background task with no parallel siblings |
| Running worktree-isolated parallel implementation across repos/features | A read-only inline subagent that does not write to disk |
| Coordinating parallel investigation or audit swarms | The work fits in the current session without forking |

## Dispatch from the Main Thread When Possible

`Agent` and other parallel-spawn tools may not be present in a
sub-agent's sandbox even when they are available in the main conversation.
Designing a fan-out from inside a coordinating sub-agent risks silent
degradation to sequential single-thread execution.

- **Default**: dispatch from the main conversation — the full tool surface is
  guaranteed.
- **Sub-agent orchestrator**: only when the team's outputs do not need to feed
  back into the main thread. Brief it to verify tool availability up front and
  report sequential fallback as a first-class outcome (see `agent-teams` →
  "Sub-Agent Caveat").

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

**Target-branch preflight (#1969).** `isolation: "worktree"` auto-names the fresh
worktree's branch; when the agent is told to **rename** onto a **fixed**
conventional target name (`feat/m4-…`), git refuses a name already checked out in
another worktree — so a collision with a concurrent session that picked the same
name surfaces only at that end-of-task rename, deep into the run (real case: two
sessions both reached PR-open ~25 min / ~400K tokens in → duplicate-PR reconcile).
Make it a **cheap up-front stop/merge decision** — before dispatching, or as the
agent's *first* step:

```bash
target="feat/m4-sampling-adapter-io"
git branch -a --list "$target"            # local + remote-tracking refs
git worktree list | grep -F "[$target]"  # checked out elsewhere
git ls-remote --heads origin "$target"   # a peer already pushed it
```

Any hit ⇒ another session may already own this task — **stop and reconcile**, not
race to a duplicate PR (acute in shared multi-session portfolios —
`.claude/rules/concurrent-session-pr-check.md`). **Mitigation:** push under the
target name via explicit refspec (`git push origin HEAD:$target`) instead of
renaming — sidesteps the "already checked out" refusal. See
[REFERENCE.md](REFERENCE.md) "Target-branch preflight (#1969)".

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
integrity check (see [REFERENCE.md](REFERENCE.md) "Worktree cwd-reset guardrail
(#1480)") — a changed branch or new dirty state is silent main-repo mutation.

**`GIT_DIR`/`GIT_WORK_TREE` export leak (#1692 sibling).** A sharper worktree-git
leak. If an agent meets a corrupted worktree (`core.bare = true`, or `fatal: this
operation must be run in a work tree`) and "works around" it by **exporting**
`GIT_DIR`/`GIT_WORK_TREE`, those vars **override `git -C`** — so every later `git`
call, *and any test/hook subprocess that shells to `git`*, targets that gitdir's
**common config**, flipping the **shared** checkout to bare and breaking **all**
sibling worktrees at once. This is the env-var sibling of the empty-`mktemp -d`
vector guarded by `check-git-sandbox-guards.sh` (#1692) — the mktemp guard does
not catch it, because the sandbox path is correct; the exported env is the hijack.
So: a bare / `must-be-run-in-a-work-tree` worktree **is** shared-checkout
corruption — STOP and report it, repair `core.bare`, and never paper over it with
exported git env. When a subprocess genuinely must run git in a sandbox,
neutralize inherited env first: `env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" …`.
See [REFERENCE.md](REFERENCE.md) "Worktree GIT_DIR-export leak (#1692)".

**Nested-repo workspaces — `isolation: "worktree"` isolates the *outer* repo (#1838).**
`isolation: "worktree"` resolves against the **session's** git repo, not the
repo the agent is told to edit. In a nested-repo / portfolio layout (the
`repos/<org>/<repo>` shape — see `shared-checkout-branch-isolation.md`,
`concurrent-session-pr-check.md`), where the target files live in an
**independent nested git repo** untracked by the outer session repo, the harness
worktrees the **outer** repo. The nested repo isn't present in that worktree, so
the agent's only path to the target files is the **shared checkout** — which the
Edit-tool isolation guard correctly blocks. The isolation guarantee silently
didn't apply to the repo that mattered, and the agent must hand-roll its own
worktree to make progress.

Detect it before dispatch: the target path's enclosing repo
(`git -C <target-dir> rev-parse --show-toplevel`) differs from the session repo
(`git rev-parse --show-toplevel`). When they differ, do **not** assume
`isolation: "worktree"` isolated the target. Instead, the lead should either:

- **(a)** create the **nested repo's** worktree explicitly off its own
  `origin/main` and point the agent at that path, or
- **(b)** brief the agent that its *first* step is
  `git -C <nested-repo> fetch && git -C <nested-repo> worktree add <path> origin/main`
  for the **specific nested repo** — never assuming it is already isolated — and
  to do all work in that dedicated worktree.

See [REFERENCE.md](REFERENCE.md) "Nested-repo worktree isolation (#1838)".

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

**Orchestrator-only files.** Even with disjoint write scopes, a second list of
shared files must be excluded from every agent's write-path under a
`### Orchestrator-only files` heading in the brief: the blueprint manifest
(ID registry), the feature tracker, top-level plan/roadmap docs, build manifests
(`pyproject.toml`/`package.json`/`Cargo.toml`/`go.mod`), `justfile`/`Makefile`,
and local task-queue stores. Last-writer-wins silently destroys earlier work on
these. See [REFERENCE.md](REFERENCE.md) for the full template and evidence.

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
per-file-cap shape — see [REFERENCE.md → Refactor-brief template](REFERENCE.md#refactor-brief-template).

### 3. Return Contract (mandatory structured summary)

Every parallel agent must end its run with a structured `## Result` summary as
its final message, regardless of success or failure (status / branch / pr /
commits / worktree, plus Scope delivered, Deferred, Issues encountered, and
Orchestrator action needed). Include the schema **verbatim** in every dispatched
agent's prompt under a heading like `### Return contract (mandatory)` — agents
follow concrete schemas more reliably than prose. Copy the full schema from
[REFERENCE.md → Return Contract schema](REFERENCE.md#return-contract-schema); for
the failure-mode → schema-field rationale, see
[REFERENCE.md → Failure modes](REFERENCE.md#failure-modes--schema-field).

Orchestrator edits needed must be **verbatim patches, not prose** (literal CMake
blocks, full justfile recipes, literal doc paragraphs) — and the agent writes
the final prose for any docs update its slice requires. See
[REFERENCE.md → Verbatim patches](REFERENCE.md#verbatim-patches--detail-and-rationale).

#### Loud-failure contract (never surrender silently)

A dispatched agent that hits a wall must say so **loudly**. The dominant failure
shape (issue [#1422](https://github.com/laurigates/claude-plugins/issues/1422))
is an agent that runs 50–200 tool calls, thrashes against hooks, then emits a
one-word final message — `Terminal.`, `Done.`, `Stopped.` — with no PR URL, no
error, no blocked list. A one-word summary is **indistinguishable from success**
to the orchestrator, so the harness reads "no changes", cleans up the worktree,
and the work is lost.

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
[REFERENCE.md → Bulk-edit self-verification](REFERENCE.md#bulk-edit-self-verification--worked-example)
and `.claude/rules/regression-testing.md`.

**Closed-list mechanical batches need a completion manifest, not just a
self-report.** When a `refactor` agent is assigned a fixed list (symbols to
delete, files to touch), brief it to emit a machine-checkable manifest of what
it actually completed, and **never** trust that manifest alone — re-run the
authoritative checker (`knip` / build / test) after it returns and diff the
result against the assignment. A truncated or optimistic summary reads as
success even when the batch fell short (issue
[#1601](https://github.com/laurigates/claude-plugins/issues/1601): a ~23-symbol
batch completed only ~5, invisible until the orchestrator re-ran `knip`). Cap
the per-agent batch so an early stop costs little. See
[REFERENCE.md → Refactor-brief template](REFERENCE.md#refactor-brief-template)
and the refactor agent's batch-size guidance.

### 5. Reviewer-agent verification (verify-then-fix)

Self-attestation is unreliable. For high-stakes dispatches (PR "ready to merge",
security audits, shared-state mutations), spawn a **separate reviewer agent**
*after* the worker reports done and *before* trusting it. The reviewer runs in
its own worktree, ideally a different model, receives the claim and branch (not
the reasoning trace), and re-derives a verdict from the diff. On a flag, fix
inline or dispatch a follow-up worker — do not close on the worker's self-claim.

**Self-author guard for `gh pr` flows**: `gh pr review --reviewer <user>` returns
HTTP 422 when the target is the PR author; brief reviewers to post inline
comments instead. See [REFERENCE.md → Reviewer-agent verification](REFERENCE.md#reviewer-agent-verification--evidence).

## Who Pushes?

Agents push their own commits in the normal case — worktree isolation plus
per-agent branches makes this safe and keeps the lead context lean. Exceptions
where the lead pushes instead:

- **Web sandbox sessions** (`CLAUDE_CODE_REMOTE=true`) — teammates may hit TLS
  errors on push (see `agent-teams`).
- **Cross-agent dependencies** where Phase 1 commits must land as a single merge
  base for Phase 2.
- **Explicit user instruction** ("I'll push manually").

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

Defensive mitigation: instruct worktree-isolated agents to `git add -A &&
git commit` **WIP at checkpoints** — after each substantive slice and before
they would terminate — so partial work is always captured even if the structured
result is lost. See
[REFERENCE.md → Agent stalled at commit / push](REFERENCE.md#agent-stalled-at-commit--push--salvage-routine)
and [REFERENCE.md → WIP salvage before re-dispatch](REFERENCE.md#wip-salvage-before-re-dispatch-1491).

## Killing a Thrashing Agent Preserves Its Worktree

`TaskStop` does **not** discard the agent's work — its worktree stays on disk
with every uncommitted change intact, making `TaskStop` a **recovery
affordance**. When an agent is thrashing (high Bash:Edit ratio with a rising
error rate on hook-blocked Bash calls), killing it early and salvaging beats
waiting for a silent give-up. After `TaskStop`, decide salvage vs restart from
the worktree state:

| Worktree state | Decision |
|----------------|----------|
| Substantive diff vs `origin/main` | **Salvage** — finish in the parent session, commit, push, open the PR |
| Empty / trivial diff, or wrong design | **Restart** — `git worktree remove <path>` first, then re-dispatch |

For the quantitative kill thresholds and the rate-limit vs hook-block
discriminator, see [REFERENCE.md → Killed-agent worktree recovery](REFERENCE.md#killed-agent-worktree-recovery-taskstop).

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
heavy agents. **Treat the rate-limit signal as backoff-and-retry, not task
failure** — re-dispatch rejected agents with backoff *and reduced concurrency*.
When the burst **killed agents at startup** (an `isolation: "worktree"` fan-out
that all died before committing), the dead worktrees leave **empty branch refs**
behind: `git worktree prune` and delete those branches before the retry, or each
agent's `git switch -c <branch>` collides with the leftover ref.
See [REFERENCE.md → Concurrent rate-limit recovery](REFERENCE.md#concurrent-rate-limit-risk--recovery-dispatch-routine)
and `.claude/rules/skill-fork-context.md` for the upstream tickets.

## Skill-less agentType for Read-Only Fan-Out

For read-only / structured-output fan-out — classification, verification, audit
sweeps where each agent **reads files and emits a result, nothing more** —
dispatch a **Skill-less agentType** rather than `general-purpose`. A
`general-purpose` subagent carries the `Skill` tool, and every `Skill`-bearing
agent pays a large fixed context tax *before it runs a single tool call*: the
**`skill_listing` attachment (~88k chars / ~22k tokens)** plus a
**`deferred_tools_delta` (~12k chars / ~3k tokens)** are injected up front. Add
~10 file reads and a forced `StructuredOutput` schema on top and that ~25k fixed
overhead pushes the subagent over its context window — observed as
`Prompt is too long` and **40–100% batch-failure rates** in a real fan-out
(issue [#1549](https://github.com/laurigates/claude-plugins/issues/1549)).

Agents without the `Skill` tool receive **no `skill_listing` injection at all**,
so the same workload fits comfortably.

| Fan-out need | agentType | Why |
|---|---|---|
| Read-only classify / verify / audit | `agents-plugin:review` | Read/Glob/Grep, no `Skill` tool → no `skill_listing` tax; its review system prompt does not interfere given an explicit rubric + schema |
| Read **plus** `Write` (e.g. emit a report file) | `agents-plugin:docs` | Same Skill-less lean tool set, with write capability |
| Genuinely needs the skill catalog or broad `Bash` (`gh`/`task` filing) | `general-purpose` | Reserve `general-purpose` for agents that actually use `Skill` / broad Bash — the ~25k tax is only worth paying when the catalog is used |

`agents-plugin:review` doubles as a **token-lean structured-output classifier**:
given a procedure-vs-judgment rubric and a forced `StructuredOutput` schema it
cleanly classified a 10-file batch where identical `general-purpose` agents
failed with `Prompt is too long` (issue
[#1550](https://github.com/laurigates/claude-plugins/issues/1550)). Preserve its
lean, no-`Skill` tool set when reaching for it as a fan-out building block.

Sibling guidance for writing such agents lives in `custom-agent-definitions`.

## Composition with agent-teams

`agent-teams` covers the implicit-team / SendMessage / TaskUpdate mechanics; this
skill adds the dispatch-time contract that applies to both team and non-team
fan-out. When both apply, follow both — the out-of-scope protocol from
`agent-teams` slots into the `Issues encountered` / `Deferred` sections here.

### Resuming agents: SendMessage loses worktree isolation

`SendMessage`-resume of a **completed** worktree-isolated agent (one spawned via
`Agent` with `isolation: "worktree"`) does **not** re-enter that agent's
worktree — the resumed run executes in the **orchestrator's main checkout**. A
resume therefore **loses worktree isolation**: resuming several file-mutating
agents this way runs them concurrently in the main checkout, tangling branch
state (issue [#1546](https://github.com/laurigates/claude-plugins/issues/1546)).

| Continuation | Safe to `SendMessage`-resume? | Do instead |
|---|---|---|
| Read-only / single-checkout follow-up | Yes — no worktree to re-enter | Resume freely |
| Parallel **file-mutating** agent that must stay in its worktree | No — resume runs in the main checkout | **Re-dispatch a fresh `Agent` with `isolation: "worktree"`** for the remaining work |

The rule: for parallel file-mutating work, never resume a finished
worktree-isolated agent via `SendMessage` — re-dispatch a new
`isolation: "worktree"` agent instead. Reserve `SendMessage`-resume for
read-only or single-checkout continuations.

### Resuming a workflow: `resumeFromRunId` re-runs succeeded worktree agents

`Workflow({resumeFromRunId})`'s resume contract — "completed `agent()` calls
return cached results" — holds for ordinary `agent()` calls but **not** for
`isolation: "worktree"` agents: on resume a worktree agent that **already
succeeded** is **re-executed**, not served from cache. Opposite failure to the
`SendMessage` case above (there the resume loses its worktree; here it re-runs
the whole agent, side effects and all). The damage is outward and
non-idempotent — an agent that opened a PR opens a **duplicate** one on resume
(PR #1858 dup of #1857), needing manual cleanup (issue
[#1868](https://github.com/laurigates/claude-plugins/issues/1868)).

So to retry a few rate-limited/failed worktree agents from a finished workflow,
do **not** resume the whole run — the succeeded ones re-run and duplicate their
PRs. **Re-dispatch only the failed agents** with a fresh **sequential** pass
(which also dodges the burst rate limit). Check for an already-open PR first
(`gh pr list --state all --search …`, reading `state`/`mergedAt` per
`.claude/rules/gh-json-fields.md`). Non-worktree stages cache correctly — the
hazard is worktree-specific. See `.claude/rules/agent-coworker-detection.md`.

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
| Accepting a one-word final message (`Terminal.`/`Done.`) | Mandate the loud-failure contract: push work, open a draft PR, explain |
| Centralizing pushes as a default | Agent pushes its own work; lead pushes only on sandbox/dependency exceptions |

## Related

- [REFERENCE.md](REFERENCE.md) — failure-mode table, refactor-brief template, salvage routines, evidence trails
- `agent-teams` — implicit-team / SendMessage mechanics, out-of-scope discovery protocol
- `custom-agent-definitions` — agent file structure, tool restrictions, context forking
- `.claude/rules/agent-development.md` — agent authoring conventions
- `.claude/rules/sandbox-guidance.md` — when sandbox constraints override push defaults
