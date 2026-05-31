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

## Killed-agent worktree recovery (TaskStop)

Distinct from the silent commit-stall above: here the orchestrator
**deliberately kills** a stuck or thrashing agent with `TaskStop` rather
than waiting for it to fail on its own. The key affordance is that
`TaskStop` preserves the agent's worktree on disk — every uncommitted
change survives the kill — so the orchestrator can recover the work
instead of re-implementing from scratch.

**When to kill early.** An agent that is hook-thrashing emits a visible
signature well before it gives up: a Bash-heavy tool mix with very few
Edits and a rising rate of `is_error: true` results (typically
`PreToolUse` hook blocks). Killing at that point and salvaging the
worktree is cheaper than letting it run another 80–200 tool calls to a
silent failure. (The leading-indicator heuristic itself is tracked
separately in issue
[#1424](https://github.com/laurigates/claude-plugins/issues/1424).)

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
