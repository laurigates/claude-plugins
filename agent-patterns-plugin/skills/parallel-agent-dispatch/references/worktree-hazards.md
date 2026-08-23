# Parallel Agent Dispatch — Worktree Hazards

The individually-rare, collectively-expensive ways `isolation: "worktree"`
fails to isolate what you meant: a cwd reset writing to the main checkout, an
exported `GIT_DIR` hijacking every sibling worktree, a nested repo the harness
never worktreed, two agents colliding in one shared scratchpad clone, a worktree
deleted out from under a live agent, a fixed target branch another session
already holds, and an `isolation: "remote"` dispatch that quietly ran in a local
worktree. Entry point: [`../SKILL.md`](../SKILL.md) § Worktree Preflight.

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

## Shared scratchpad collisions (#2370)

The session scratchpad directory is shared across sibling subagents, so two
agents told to "make your own clone" independently pick the identical path and
end up operating **one working tree**. Nothing errors: one agent's `git switch`
moves `HEAD` under the other, so its edits land on the peer's branch and both
PRs can carry each other's hunks. A per-file `git diff` cannot separate
interleaved hunks in a co-modified file, so the extracted patch looks correct
while carrying someone else's work.

Give every concurrent agent an **explicit, distinct** working path in its
prompt — `<scratchpad>/<agent-name>` — rather than letting each choose. This
applies whenever agents work outside worktree isolation, which the nested-repo
case above forces them into.

Recovery, if it already happened: rebuild in a fresh clone and **re-apply your
changes by hand**. Do not copy files out of the shared tree — co-modified files
carry the peer's hunks with them. Leave the shared tree dirty rather than
reverting it; a revert destroys the peer's uncommitted work. Verify with
`git log --oneline origin/main..HEAD` plus `--stat` that the branch holds only
your commits and only your paths.

> Observed 2026-08: two agents fixing different defects in the same MCP server
> collided this way. Each caught a real error in the other's cleanup — one
> nearly shipped a merge warning that would have broken the build if acted on,
> the other a verification `grep` that would have cried wolf. Neither shipped
> contaminated, but only because they were talking to each other.

## Deleted worktree kills the shell, not the agent (#2372)

An isolation worktree removed **while its agent is still running** takes the
agent's shell with it. The trigger for the reported occurrence is unknown — this
section records the observed behaviour and its consequences only, not a cause.

### The failure signature is a total Bash refusal, not a permission denial

Once the worktree directory is gone, **every** Bash call fails, including a bare
`echo` — the agent's cwd no longer exists, so nothing can be executed from it.
The refusal reads like an ordinary permission-style denial, which is what makes
it easy to misread: the natural response to one denied command is to reword it
and try again, and every reword is denied identically. A bare `echo` is the
cheapest probe that separates the two readings — if that fails too, the failure
is environmental (the shell has no working directory) rather than specific to
the command that was refused.

The agent's other faculties are unaffected. It can still reason, read its own
context, and send messages — so it can keep producing confident, specific
conclusions it has no remaining way to verify. In the reported occurrence one
agent in that state emitted a precise merge-order warning ("PR B needs three
lines hand-edited or it won't compile") that was wrong, and the orchestrator had
to disprove it empirically by performing the merge in a throwaway clone; acting
on the warning would have caused the breakage it claimed to prevent.

### A spawned subagent inherits the same dead cwd

Delegation is **not** a workaround. An agent that tries to route around the dead
working directory by spawning a child gets a child with the same dead cwd, and
the child can execute nothing either. In the reported occurrence that attempt
burned ~137k tokens and performed zero work. Nothing warns about this in
advance, so an agent in this state can spend a large share of its remaining
budget rediscovering it.

The corollary for dispatch: **uncommitted work in a worktree is only as safe as
the worktree.** Both agents in the reported occurrence had already pushed before
the deletion, so nothing was lost — the same failure minutes earlier would have
stranded uncommitted work in a directory that no longer exists. This is the same
asymmetry the WIP-checkpoint instruction in
[`../SKILL.md`](../SKILL.md) § Handling a Missing Return already trades on:
committed work survives, uncommitted work does not.

Related but distinct: `../SKILL.md` § "Resuming agents: SendMessage loses
worktree isolation" (#1546) and the `resumeFromRunId` re-run hazard (#1868) both
concern *resume* semantics. This is the worktree disappearing under a live agent.

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

## `isolation: "remote"` may resolve to a LOCAL worktree (#2447)

`isolation: "remote"` is a *request*, not a guarantee. The dispatch may resolve
to an ordinary **local** git worktree in the shared checkout
(`.claude/worktrees/agent-*`), and **nothing in the dispatch tool result says
which mode was in effect** — so an orchestrator that assumes "remote" reasons
about the wrong place for the rest of the run.

Observed 2026-08: three agents dispatched with `isolation: "remote"` all ran in
local worktrees. Two were killed by a 600 s stall watchdog. The recovery audit
followed the remote protocol — `gh pr list` and `git ls-remote --heads origin`,
both empty for one agent — and its work was reported to the user as
unrecoverable, twice. `git worktree list` showed the branch holding a
**complete** commit (both intended edits plus a 28-line documentation table)
that had simply never been pushed. The remote audit was accurate; the conclusion
drawn from it was wrong.

### The two tells

| Tell | How to read it |
|------|----------------|
| `git worktree list` | A `.claude/worktrees/agent-*` entry for the dispatched agent means the dispatch resolved **locally**, whatever mode was requested. |
| The completion notification's `worktreePath` field | Present and pointing at a local path ⇒ local worktree. It is carried in the notification, but only if you think to look. |

Read one of them **right after dispatch**, while the answer is still cheap —
not during recovery, when the wrong assumption has already been acted on.

### Rules

| Rule | Why |
|------|-----|
| Establish the mode from `git worktree list` / the notification's `worktreePath`; never infer it from the `isolation` argument you passed. | The requested mode and the resolved mode can differ silently, and the tool result does not distinguish them. |
| Audit **local worktrees alongside the remote** before concluding an agent's work is lost — see [`failure-recovery.md` → Audit local worktrees alongside the remote](failure-recovery.md#audit-local-worktrees-alongside-the-remote-2447). | An empty remote is evidence about the push, not about the work. |
| Brief every dispatched agent to commit, push, and open a **draft PR before the bulk of the work**, then push after each commit. | It makes the remote a live mirror of the work instead of a single end-of-run event, so a mid-run death costs one push rather than everything. The retry agent survived having its own branch merged and deleted mid-task on this basis; recovery was one cherry-pick. |

Related but distinct — all three concern `worktree`, none concerns `remote`:
[nested-repo isolation (#1838)](#nested-repo-worktree-isolation-1838) (the
harness worktreed the *outer* repo), `../SKILL.md` § "Resuming agents:
SendMessage loses worktree isolation" (#1546), and
[deleted worktree (#2372)](#deleted-worktree-kills-the-shell-not-the-agent-2372).
