# Parallel Agent Dispatch — Worktree Hazards

The individually-rare, collectively-expensive ways `isolation: "worktree"`
fails to isolate what you meant: a cwd reset writing to the main checkout, an
exported `GIT_DIR` hijacking every sibling worktree, a nested repo the harness
never worktreed, and a fixed target branch another session already holds.
Entry point: [`../SKILL.md`](../SKILL.md) § Worktree Preflight.

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
