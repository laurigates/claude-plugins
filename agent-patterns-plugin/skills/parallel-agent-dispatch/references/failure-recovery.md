# Parallel Agent Dispatch — Failure and Recovery Routines

What to do when an agent stalls, is cut off, goes idle without reporting, is
killed deliberately, or is rate-limited. Every routine here assumes the work
may still be intact on disk — salvage before re-dispatch. Entry point:
[`../SKILL.md`](../SKILL.md) § Handling a Missing Return / § Killing a
Thrashing Agent / § Concurrent Rate-Limit Risk.

## Agent stalled at commit / push — salvage routine

The dominant cause of silent stalls in real parallel dispatches is a
**pre-commit hook blocking `git commit`** — typically a slow audit,
secrets scan, or lint that runs longer than the agent's effective budget.
The agent's `git commit` call is parked on the hook, no retry fires, no
Return Contract is emitted, and the agent's actual diff is sitting intact
in the worktree. Distinct from a transport-layer rate-limit cascade (see
below), this is a hook-layer stall with the agent's work fully preserved.

**Symptoms** (any of):

- Return Contract reports `worktree: dirty: <files>` matching the agent's
  declared scope, with no `commits:` and no `pr:` line.
- No Return Contract at all, but `git -C <worktree> status --porcelain`
  shows staged or unstaged work in the agent's declared scope.
- Commits landed but the branch was never pushed
  (`git -C <worktree> log --oneline origin/main..HEAD` shows commits but
  the remote has none).

**Salvage routine** — do **not** discard the worktree. From the parent:

1. `cd <worktree>` and run `git status` — confirm the diff matches the
   agent's declared scope.
2. `git log --oneline origin/main..HEAD` — confirm whether commits
   already landed locally.
3. If commits landed but were never pushed:
   `git push -u origin <branch>` — done.
4. If the diff is uncommitted, run
   `pre-commit run --all-files 2>&1 | tail -40` to surface what blocked,
   fix the hook failure (or rerun the agent with the fix instructions),
   then commit on the agent's behalf preserving its intended commit
   message and push.

**Prevention.** Dispatch briefs should, at minimum, instruct the agent to
run `pre-commit run --files <its scope>` (or the project's equivalent)
**before** attempting `git commit`. This surfaces hook failures inside
the agent's reasoning budget, where the agent can fix them, rather than
at commit time where they manifest as a stall. Two follow-up options if
the project's hooks are still slow enough to risk budget exhaustion:

- Pre-warm pre-commit hooks during worktree setup so the agent's first
  commit isn't the first hook run on the new worktree.
- Brief agents to commit with `--no-verify` and have the orchestrator run
  `pre-commit run --all-files` once before the merge wave. Trade-off:
  individual agent diffs may fail hooks; the merge-wave fixer must be
  ready to repair.

Add to every brief an explicit fallback: *"If `git commit` fails or
hangs, emit your Return Contract with `status: failed`,
`worktree: dirty: <files>`, and `Orchestrator action needed: pre-commit
hook X failed, fix and commit on my behalf."*

## WIP salvage before re-dispatch (#1491)

A schema-bound, worktree-isolated agent cut off by a rate limit (or other
transport-layer interruption) *after* it implemented its change but *before*
it emitted the final StructuredOutput call is reported as **failed** — yet the
work is sitting fully intact as **uncommitted WIP in the agent's worktree**.
The orchestrator's result array shows nothing; only the persisted worktree
(which survives because it *did* change) hints anything happened. Without an
explicit salvage step that work is invisible and easily discarded.

> **Evidence.** A 7-agent run: 5/7 agents opened PRs; 2 were marked
> *"subagent completed without calling StructuredOutput (after 2 in-conversation
> nudges)"*. Inspecting their worktrees (`git -C <worktree> status --short`)
> showed **complete, correct implementations** as uncommitted changes (new
> files + edits). Both were salvaged manually — two trivial typecheck fixes in
> one, then lint/typecheck/tests, commit/push/PR — with no re-run needed; the
> work was already done. Salvaging cost minutes; re-dispatching would have
> redone work that was already complete.

**Empty-vs-dirty discrimination** — the first move when an agent is reported
failed is to decide whether its worktree holds salvageable work. Do this
*before* re-dispatching:

| Probe (from the parent) | Result | Decision |
|-------------------------|--------|----------|
| `git -C <worktree> status --porcelain` | non-empty | **Dirty** — agent produced changes; salvage them |
| `git -C <worktree> log --oneline origin/main..HEAD` | shows commits | **Committed** — push the branch, open the PR |
| Both empty / trivial | nothing landed | **Empty** — re-dispatch or resume; nothing to lose |

The distinction matters for the failure summary too: *"agent errored with
empty worktree"* (genuinely needs a fresh run) is a different verdict than
*"agent produced changes but didn't return structured output"* (salvage, do
not re-run). Report the two cases separately so a re-dispatch decision is not
made blind.

**Salvage routine** for a dirty worktree:

1. `git -C <worktree> status --short` — confirm the diff matches the agent's
   declared scope (it should look like a complete implementation, not a
   half-edit).
2. Run the project's quality gates inside the worktree (lint, typecheck,
   tests). Repair any trivial breakage — the implementation is done, but the
   cut-off may have left a small loose end (a stale cast, an unran formatter).
3. Commit on the agent's behalf preserving its intended commit message and
   conventional-commit scope, then `git -C <worktree> push -u origin <branch>`.
4. Open the PR. File a tracking note that the agent stalled at
   StructuredOutput so the pattern is visible.

**Defensive prevention — checkpoint WIP commits in the brief.** The salvage
above is only possible because the worktree persisted. Make the work *also*
survive on a branch by instructing every worktree-isolated agent to:

> Commit WIP at checkpoints. After each substantive slice — and **before you
> would otherwise terminate** — run `git add -A && git commit -m "wip:
> <slice>"` so your partial work is captured on the branch even if your final
> structured result is lost. The orchestrator can salvage a committed branch
> far more cleanly than an uncommitted worktree.

A checkpoint commit converts the dirty-worktree case into the
committed-branch case (row 2 above) — the cleanest salvage, a plain
`git push` with no commit-on-behalf step.

## Idle without report (#2039)

A distinct missing-return variant: the agent **completed its work fully** —
one clean commit, clean tree — then went idle, and the orchestrator received
only `{"type":"idle_notification","idleReason":"available"}`; the final
report message was never delivered. The work isn't lost; the *communication*
is. It is intermittent — sibling agents in the same wave can deliver their
reports normally.

> **Evidence (loractl post-M8 sweep, 2026-07-11).** The PR C implementer
> committed `6ad2e13` on `docs/blueprint-sweep`, then the orchestrator
> received only the idle notification. Two other agents in the same session
> delivered their reports normally.

**Discrimination** — an `idle_notification` with no preceding report is not a
failure signal. Verify the branch state directly before assuming a silent
exit (the same empty-vs-dirty probes as #1491):

```bash
git -C <worktree-or-checkout> log --oneline origin/main..HEAD   # commits present?
git -C <worktree-or-checkout> status --porcelain                # clean tree?
```

Completed work on the agent's branch + a clean tree ⇒ communication loss, not
a silent exit.

**Recovery** — `SendMessage` the **named agent** requesting the report; it
resumes from its transcript and delivers the full structured Return Contract,
after which review/push proceed normally (worked first try in the evidence
case). A report re-request is a **read-only continuation**, so the #1546
SendMessage-resume isolation caveat does not apply. Do **not** respawn — a
fresh agent lacks the context, and for worktree agents cannot take the branch
(it is still checked out in the original agent's worktree).

**Prevention** — lead briefs should tell implementers to deliver the report
via an explicit `SendMessage` to the lead ("main") as their **final act**,
not rely on the final-text return alone.

## Killed-agent worktree recovery (TaskStop)

Distinct from the silent commit-stall above: here the orchestrator
**deliberately kills** a stuck or thrashing agent with `TaskStop` rather
than waiting for it to fail on its own. The key affordance is that
`TaskStop` preserves the agent's worktree on disk — every uncommitted
change survives the kill — so the orchestrator can recover the work
instead of re-implementing from scratch.

**When to kill early.** A hook-thrashing agent emits a quantifiable
signature well before it gives up. Use these thresholds to intervene
programmatically — don't wait for the silent failure 80–200 tool calls
later:

| Signal | Thrashing threshold | Meaning |
|--------|--------------------|---------| 
| **Bash:Edit ratio** | ≥ 9:1 (≥ ~90% Bash calls relative to Edit calls) | Agent is retrying blocked commands instead of making file progress |
| **`is_error: true` rate on Bash calls** | Rising (≥ 3 consecutive `PreToolUse` blocks, or ≥ 30% of recent Bash calls) | Hook is repeatedly denying the same class of command |
| **Combined signal** | Both thresholds met simultaneously | Strong indicator — kill and salvage now |

The ratio threshold alone is not sufficient (a read-heavy research
phase is legitimately Bash-heavy). The rising `is_error` rate on Bash
calls is the key discriminator: it shows the agent is blocked, not just
exploring. When both thresholds fire together, the agent is
hook-thrashing and `TaskStop` is the right call.

Killing at that point and salvaging the worktree is cheaper than
waiting. Cross-reference the concurrency-cap and wave-splitting guidance
in `SKILL.md § Concurrent rate-limit risk` — a Bash:Edit ratio spike
during a rate-limit storm can mimic hook-thrashing; check `is_error`
content for `Rate limited` vs `hook` keywords before killing.

**Recovery checklist** — from the parent, after `TaskStop`:

1. `cd .claude/worktrees/agent-<id>/`
2. `git status` — see the uncommitted changes the agent left.
3. `git diff origin/main --stat` — measure the scope of what landed.
4. `git log --oneline -5` — check whether the agent committed anything
   before it was killed.
5. Decide **salvage vs restart**:
   - **Salvage** (substantive diff): finish the work in the parent
     session — complete any half-written files, fix tests that depend
     on the agent's changes, run the quality gates, then commit and push
     preserving the agent's intended branch, and open the PR.
   - **Restart** (empty/trivial diff, or the design was wrong):
     `git worktree remove .claude/worktrees/agent-<id>` to clear the
     abandoned worktree before re-dispatching from scratch.

This pattern pays off most for refactors with heavy design-time work:
the agent's exploration and partial implementation are recoverable even
when the agent itself fails to land them.

> **Evidence.** During Wave B of a multi-wave refactor on
> `pal-mcp-server`, a dispatched agent thrashed on `bash-antipatterns.sh`
> (180 tool calls, 120 error signals, no PR pushed). Killing it via
> `TaskStop` left its worktree intact with the bulk of the refactor
> done (−791 lines net across five provider files, plus a
> partially-written contract test). Salvaging in the parent session —
> finishing the contract test, repairing three tests that depended on the
> old API, running the gates, committing, pushing, opening the PR — took
> ~30 min versus an estimated ~90 min for a fresh agent (which would have
> re-discovered the refactor design before reimplementing).

## Concurrent rate-limit risk — recovery-dispatch routine

When a subagent returns with the rate-limit signature (`API Error: Server
is temporarily limiting requests · Rate limited` plus `status: completed`
and a partial scope), use the **recovery-dispatch pattern**: re-dispatch
the missed slice as a small follow-up agent rather than retrying the
entire wave. The successful siblings' work is already on disk; only the
rate-limited agent's remaining scope needs another pass. Issue
[#1280](https://github.com/laurigates/claude-plugins/issues/1280)
documents this recovery shape as positive evidence — a single-agent
follow-up cleanly closed the gap left by a rate-limited cascade agent.

| Symptom | Action |
|---------|--------|
| 6+ agents queued at dispatch time | Split into waves of ≤ 5 |
| Wave returns with one or two `Rate limited` agents | Recovery-dispatch the missed slice; do not retry the whole wave |
| Same agent rate-limits twice in a row | Smaller scope or staggered dispatch — the wave size is still too high |
| Burst killed agents at **startup** (worktree fan-out died before committing) | `git worktree prune` + delete the empty leftover branches before the reduced-concurrency retry — else each agent's `git switch -c <branch>` collides with the orphaned ref |

### Burst limit vs session usage limit

The table above covers the **server burst limit** — many agents dispatched at
once, refused by the API. A **session usage limit** kills a wave the same way
but for a different reason, and the two want different first moves: the burst
limit wants lower concurrency on an immediate retry, the usage limit wants a
wait. The wreckage they leave is identical, so the audit step below applies to
either.

The burst-limit signature:

Spawning many agents simultaneously — a `Workflow` `parallel()`/`pipeline()`
of N agents, or N `Agent` calls in one message — can trip a **server-side
burst rate limit** (`API Error: Server is temporarily limiting requests (not
your usage limit) · Rate limited`), distinct from your usage quota. When it
fires, the agents die after their retries and `parallel()` returns them as
`null` — **every agent's startup tokens wasted** (observed: 7 Opus auditors,
628 k tokens, all killed at 18 s).

Mitigations for this class already live above and in
[`../SKILL.md`](../SKILL.md) § Concurrent Rate-Limit Risk — safe starting
concurrency by agent profile, sequential waves over one big fan-out,
backoff-and-retry rather than task failure, and `git worktree prune` before a
reduced-concurrency retry after a startup kill. They are not restated here. The
one mitigation that is not a dispatch tactic — for deterministic, mechanical
work (parsing, counting, audits, frontmatter scans), prefer a single inline
`python3`/`rg` pass over an agent fan-out — belongs to
`.claude/rules/offload-to-deterministic-substrate.md`, not to this skill.

### Session usage limit — audit remote, then recover

The **session usage limit** ("You've hit your session limit · resets <time>")
kills in-flight subagents the same way the burst limit does: each agent dies
on a terminal API error at whatever stage it had reached — some after pushing
a branch and opening a PR, some mid-edit, some before starting. A `Workflow`
run reports them under `failures`; completed siblings' results survive in the
run's journal.

Recovery protocol (observed 2026-07: a 14-agent PR sweep lost 7 agents to the
limit and recovered fully):

1. **Wait out the reset** — the limit message names the reset time; nothing
   recovers before it.
2. **Audit remote state before resuming** — dead agents may have half-landed
   their work: `gh pr list --state open` plus `git ls-remote --heads origin`
   show which branches/PRs already exist. A re-run agent that pushes an
   already-pushed branch hits a non-fast-forward reject, and one that
   re-creates an existing PR duplicates it — brief agents to check first, or
   verify the remote is clean yourself.
3. **Resume only what actually caches.** `Workflow({scriptPath,
   resumeFromRunId})` replays completed **ordinary** agents from cache (cache
   key: unchanged prompt + opts) at zero cost, so re-dispatching those from
   scratch re-pays their tokens. It does **not** hold for `isolation:
   "worktree"` agents: one that already succeeded is **re-executed** on resume
   and re-fires its side effects — an agent that opened a PR opens a duplicate
   (PR #1858 dup of #1857; issue
   [#1868](https://github.com/laurigates/claude-plugins/issues/1868)). Recover
   those with a fresh **sequential** re-dispatch of only the dead agents, after
   the step-2 audit confirms no PR is already open. See
   [`../SKILL.md`](../SKILL.md) § "Resuming a workflow: `resumeFromRunId`
   re-runs succeeded worktree agents" and
   `.claude/rules/agent-coworker-detection.md`.
