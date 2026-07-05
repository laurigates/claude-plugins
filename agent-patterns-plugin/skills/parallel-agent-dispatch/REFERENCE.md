# Parallel Agent Dispatch — Reference

Supporting material for [`parallel-agent-dispatch`](SKILL.md). Loaded on demand.
The operational workflow lives in `SKILL.md`; this file carries the lookup
tables, worked examples, and detailed salvage / recovery routines.

## Return Contract schema

Include this verbatim in every dispatched agent's prompt under a heading like
`### Return contract (mandatory)` — agents follow concrete schemas more reliably
than prose.

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
- Anything explicitly out of scope or punted (empty is fine — section must exist)

## Issues encountered
- Hook fires, retries, test flakes, manual workarounds, unexpected findings
  (empty is fine — section must exist)

## Orchestrator action needed
- none | <one line: what the lead must do before next phase>
```

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

**Completion manifest** (closed-list assignments — symbols to delete,
files to touch): end your final message with a machine-checkable
manifest enumerating each item you actually completed, one
`VERB: <item> (<location>)` line per item, plus `ASSIGNED: N` /
`COMPLETED: M`. The orchestrator diffs it against the assignment.

**Final step**: run `<repo regression script>`; loop until exit 0
before emitting the Return Contract.
```

> Evidence: issue [#1279](https://github.com/laurigates/claude-plugins/issues/1279)
> — six agents, 41 plugins, cleanest batch hit 28.9% reduction with zero
> >250-char outliers. PR #1314 productizes the post-pass.

**Mechanical-batch self-reports are never trusted alone.** For a
closed-list deletion/rewrite batch, the agent's own report — manifest
included — is a *claim*, not a verification. The orchestrator runs the
**authoritative checker** (`knip` / build / test) after the agent
returns and diffs the manifest against the assignment; an item on the
manifest that the checker still finds present is a silent
under-delivery. This complements Pillar 4 (the agent's own final
verification step) and Pillar 5 (a separate reviewer agent): the
manifest makes the orchestrator's post-run diff mechanical instead of a
re-derivation. Cap the per-agent batch so an early stop costs little —
see the refactor agent's batch-size guidance.

> Evidence: issue [#1601](https://github.com/laurigates/claude-plugins/issues/1601)
> — a `refactor` agent assigned ~23 symbols across ~11 files completed
> only ~5 before stopping; the shortfall was invisible from its
> (truncated) self-report and surfaced only when the orchestrator re-ran
> `knip` and saw ~18 assigned symbols still present.

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
| Burst killed agents at **startup** (worktree fan-out died before committing) | `git worktree prune` + delete the empty leftover branches before the reduced-concurrency retry — else each agent's `git switch -c <branch>` collides with the orphaned ref |

## Worktree cwd-reset guardrail (#1480)

Issue [#1480](https://github.com/laurigates/claude-plugins/issues/1480)
documents a git-**write** agent under `isolation: "worktree"` whose bare
`git` commands silently ran against the **main checkout** instead of its
worktree. Agent threads have their bash cwd reset between calls (documented
behaviour), and the reset landed on the session's primary cwd (the main repo
root) rather than the agent's worktree. Every `git fetch` / `git checkout -B`
/ `git rebase --autostash` mutated `main` — sweeping the user's uncommitted
edits into an autostash that pop-conflicted, and leaving the main repo on a
stray branch. The orchestrator believed the work was sandboxed, so the
corruption was invisible. This is **distinct** from the #1319 *transient*
leak (see `agent-coworker-detection.md`).

### Agent brief — absolute-path git

| Rule | Why |
|------|-----|
| **Never assume `cwd == worktree`.** Capture the worktree root once and reference it absolutely: prefix every git call with `git -C "$WORKTREE" …`, or `cd "$WORKTREE"` and verify with `pwd` at the top of **each** bash call. | The cwd does not persist between agent bash calls; a reset can land on the main repo root. |
| **Pin the worktree path.** Run `git rev-parse --show-toplevel` on the first call, store it as `$WORKTREE`, and use that value thereafter. | Trusting the persisted cwd is the root cause. |
| **Forbid bare branch-switching / autostash.** Confirm the agent is inside its isolated worktree before any `git checkout -B` / `git rebase --autostash`. | In the main repo these swallow the user's uncommitted work. |

### Orchestrator post-run integrity check

After a git-write agent returns, snapshot the main repo before dispatch and
re-check it afterward:

```bash
# Before dispatch
main_branch_before=$(git -C "$MAIN_REPO" branch --show-current)
main_dirty_before=$(git -C "$MAIN_REPO" status --porcelain)

# After the agent returns
[ "$(git -C "$MAIN_REPO" branch --show-current)" = "$main_branch_before" ] || echo "MAIN BRANCH MUTATED"
[ "$(git -C "$MAIN_REPO" status --porcelain)" = "$main_dirty_before" ] || echo "MAIN TREE MUTATED"
```

A changed branch or new dirty state is silent main-repo mutation — treat it
the same as a missing Return Contract (see SKILL.md "Handling a Missing
Return") and salvage before reporting the task complete. `agent-teams` Lead
Preflight Checklist adds file-scope and pin-budget checks that stack on top.

## Worktree GIT_DIR-export leak (#1692)

The empty-`mktemp -d` vector (`git -C ""` falling back to CWD) is guarded by
`scripts/check-git-sandbox-guards.sh` (#1692). A **distinct** vector is not:
**exporting `GIT_DIR` / `GIT_WORK_TREE`**. `GIT_DIR` takes precedence over
`git -C <path>` gitdir discovery, so once it is exported pointing at a real
repo's gitdir, *every* `git` command — including any test/hook subprocess that
shells to `git` — operates on that gitdir's **common config**, regardless of
`-C` or cwd. A `git config core.bare true` (common scope) then flips the
**shared** checkout to bare, breaking the main checkout and every linked
worktree simultaneously, often injecting a junk `[user]`/`[commit]` too.

Observed (2026-06-21): an agent on a corrupted worktree exported `GIT_DIR` to
force git to run; a regression test that shells `git init` / `git config` then
wrote `core.bare = true` + a junk `[user]` into the shared `.git/config`,
breaking ~35 sibling worktrees mid-run. The detection complement is
`/git:coworker-check`'s `bare_flip_suspected` verdict; the test-suite cause is
tracked separately.

### Rules

| Rule | Why |
|------|-----|
| A worktree showing `core.bare = true` / `fatal: this operation must be run in a work tree` **is shared-checkout corruption** — STOP and report it. | It is the #1692 class; "working around" it spreads the damage to every worktree. |
| Never `export GIT_DIR` / `GIT_WORK_TREE` to make git work in a broken worktree. | The export redirects every later git op (and git-shelling subprocess) at the shared gitdir's common config. |
| If a subprocess must run git in a sandbox, neutralize inherited env: `env -u GIT_DIR -u GIT_WORK_TREE git -C "$dir" …`. | Stops an inherited `GIT_DIR` from hijacking the sandbox op even when the path is correct. |
| Repair, don't paper over: `git config core.bare false`; remove junk `[user]`/`[commit]`; verify `git rev-parse --is-bare-repository` = false. | Restores the shared checkout for the main repo and all worktrees. |

## Nested-repo worktree isolation (#1838)

`isolation: "worktree"` worktrees the **session's** git repo — the one whose
`.git` encloses the cwd — not the repo the agent was told to edit. In a
nested-repo / portfolio layout the two differ: the session repo is an outer
`repos`/config repo, but the target files live in an **independent nested git
repo** (its own `.git`, untracked/gitignored by the outer one).

Observed (laurigates/comfyui-model-gallery#32): a subagent dispatched to fix a
build script in `comfyui-nodes/comfyui-model-gallery` got a worktree of the
**outer** `repos` config repo. The nested repo was absent from that worktree, so
the agent's only path to the target files was the shared checkout — which the
Edit-tool isolation guard blocked (correctly; that is the point of isolation).
The agent had to hand-roll a dedicated worktree of the nested repo off
`origin/main` and do all work there. The isolation guarantee silently did not
apply to the repo that mattered.

This is harness worktree-resolution behavior; the dispatch-side mitigation is to
detect the nesting and isolate the **nested** repo explicitly.

### Detection (before dispatch)

```sh
session_root=$(git rev-parse --show-toplevel)
target_root=$(git -C "<target-dir>" rev-parse --show-toplevel)
# If they differ, isolation: "worktree" will NOT isolate <target-dir>.
[ "$session_root" != "$target_root" ] && echo "nested repo — isolate target explicitly"
```

### Rules

| Rule | Why |
|------|-----|
| When the target's enclosing repo ≠ the session repo, do not assume `isolation: "worktree"` isolated the target. | The harness worktrees the session repo; the nested repo is absent from it. |
| (a) Create the **nested repo's** worktree explicitly off its own `origin/main` and point the agent at that path; **or** (b) brief the agent to `git -C <nested-repo> fetch && git -C <nested-repo> worktree add <path> origin/main` as its first step. | Both give the agent a real isolated checkout of the repo it edits, instead of the blocked shared checkout. |
| Have the agent operate inside that nested-repo worktree (prefix `git -C "$WORKTREE"`, per the #1480 cwd-reset rule) and open its PR from there. | Keeps the work isolated and avoids the shared-checkout collisions `shared-checkout-branch-isolation.md` guards against. |

## Target-branch preflight (#1969)

`isolation: "worktree"` names the fresh worktree's branch **automatically** (an
`agent-<hash>` name). When the project convention is a **fixed** per-issue /
per-milestone name (`feat/m4-sampling-adapter-io`), the agent is told to
**rename** onto it near the end of its run. Git refuses to check out — or rename
onto — a branch **already checked out in another worktree**, so if a concurrent
session picked the same conventional name for the same task, the refusal surfaces
only at that end-of-task rename.

Observed (laurigates/loractl M4): two sessions independently dispatched the same
milestone task, both auto-named worktrees, both told to rename onto
`feat/m4-sampling-adapter-io`. The second finished ~25 min / ~400K tokens in, hit
the rename refusal (the first had already checked the name out and committed a
complete duplicate implementation), fell back to a `-wip` suffix, and flagged the
collision in its return notes. Both reached PR-open independently — two duplicate
PRs for one issue, needing a full reconciliation pass (diff the two, keep the
better, port the other's improvements, close the loser). A preflight would have
stopped at least one session before it started.

### Detection (before dispatch, or as the agent's first step)

```sh
target="feat/m4-sampling-adapter-io"
git branch -a --list "$target"                 # local + remote-tracking refs
git worktree list | grep -F "[$target]"        # same name checked out elsewhere
git ls-remote --heads origin "$target"         # a peer already pushed it
```

Any hit ⇒ another session may already own this exact task. **Stop and reconcile**
(compare/merge with the existing branch/PR — see
`.claude/rules/concurrent-session-pr-check.md`) rather than racing to a duplicate.

### Rules

| Rule | Why |
|------|-----|
| Check the fixed target name against local refs, other worktrees, **and** the remote before substantive work. | The rename-time refusal is the most expensive place to discover the collision; the preflight is one cheap round of `git` reads. |
| A hit is a **stop/merge decision**, not a rename-with-suffix workaround. | Two sessions on the same conventional name are almost always doing the same task; a `-wip` fallback just produces the duplicate PR. |
| Prefer pushing under the target name via **explicit refspec** (`git push origin HEAD:$target`) over renaming the worktree branch. | A refspec push never touches the local branch, so it sidesteps the "already checked out in another worktree" refusal entirely; a genuine peer collision then still surfaces — cheaply — as a non-fast-forward reject at push time. |
| Acute in shared multi-session portfolios (one clone, concurrent Claude Code sessions). | A conventional per-issue/milestone name is exactly what two independent sessions pick identically. |
