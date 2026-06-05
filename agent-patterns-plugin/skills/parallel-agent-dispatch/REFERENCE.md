# Parallel Agent Dispatch — Reference

Supporting material for [`parallel-agent-dispatch`](SKILL.md). Loaded on demand.
The operational workflow lives in `SKILL.md`; this file carries the lookup
tables, worked examples, and detailed salvage / recovery routines.

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

## Refactor-brief template

For bulk content rewrites (description tightening, naming sweeps), use the
brief shape that worked across six concurrent refactor agents. Load-bearing:
per-step ordering, a PRECIOUS list, and a per-file cap.

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
> — six agents, 41 plugins, cleanest batch hit 28.9% reduction with zero
> >250-char outliers. PR #1314 productizes the post-pass.

## Verbatim patches — detail and rationale

Agents should emit:

- Complete CMake / build-manifest blocks with surrounding context, ready
  for `Edit(old_string=…, new_string=…)`.
- Full justfile / Makefile recipes including shebang and every parameter.
- Literal prose paragraphs for docs updates — tracker evidence strings,
  plan bullets, format-spec paragraphs — not "update the port plan with
  findings about X."
- Exact line numbers where the orchestrator must insert, when the target
  is long.

If the edit is a single-line insertion, still quote the surrounding 2–3
lines so the paste target is unambiguous. The orchestrator's role for
`Orchestrator action needed` is `Edit(old=…, new=…)` — a mechanical
operation, not prose synthesis. Brief agents accordingly.

### Agent authors the docs-update text the orchestrator pastes

The paired discipline: **the agent writes the final prose** for any docs
update its slice requires. Port-plan sub-bullets, feature-tracker evidence
strings, and format-spec paragraphs all belong in the agent's return
contract as finished sentences, ready to paste. The orchestrator's job
stays pure `Edit(old=…, new=…)` — no prose synthesis, no re-summarising
of what landed.

Evidence-strings in particular need agent authorship: the agent is the
only party that knows what actually landed in its commits, which test
cases passed, and which subtleties of the slice are worth recording.
Asking the orchestrator to compose that prose retroactively forces it to
re-read the agent's diff and produces a less faithful summary than the
agent could write inline.

> **Why this matters.** Across six sequential waves in a single session,
> every return that emitted verbatim patches paste-integrated cleanly in
> seconds. One earlier return that used prose ("add `src/foo.c` to
> `CMakeLists.txt`") forced the orchestrator to re-derive the exact
> insertion context — measurably slower and more error-prone. The
> verbatim-patch + agent-authored-prose pairing, not the parallel
> topology, is what made the multi-wave cadence sustainable.

## Bulk-edit self-verification — worked example

> **Evidence (2026-05-09 cascade).** Six refactor agents shortened
> descriptions across 41 plugins. Each agent believed it was preserving
> "Use when..." triggers, but 4 of the 6 silently introduced "Use to..."
> or "Use for..." variants that do not match the
> `audit-skill-descriptions.py` regex. The aggregate damage (68
> `NO_TRIGGER` skills) only surfaced when pre-commit ran on the
> mega-commit — a single fixer-agent pass repaired them, but only because
> pre-commit forced the issue. If each refactor agent had run
> `audit-skill-descriptions.py --strict-all` as its last step and looped
> on failures, the regression would have been caught per-agent.

**Canonical example: PR #1314** (`agents-plugin/agents/refactor.md`). That
PR bakes this exact pattern into the repository's refactor agent: it
broadens the agent's bash permissions to cover the audit script and
mandates an audit post-pass before the agent reports done. New bulk-edit
dispatch briefs should follow the same shape — agents inherit both the
permission to run the script and the requirement to clear it.

## Reviewer-agent verification — evidence

> Evidence: issue [#1239](https://github.com/laurigates/claude-plugins/issues/1239)
> — three parallel-dispatch rounds; verify-then-fix caught a "ready to
> merge" claim where helm-template did not confirm the hypothesis, and
> the self-author guard prevented HTTP 422 across every fix PR.

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
