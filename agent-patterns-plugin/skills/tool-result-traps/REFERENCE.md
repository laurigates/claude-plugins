# Tool Result Traps - Reference

Environment- and orchestration-level traps: a wedged worktree shell, a persistent
cwd that makes verification vacuous, `Workflow` args arriving as a JSON string,
and parallel-batch / agent fan-out hazards. The search- and stderr-level traps
stay in [SKILL.md](SKILL.md).

## A worktree-isolated shell can wedge — and `cd` cannot unwedge it

The Bash tool's working directory is **persistent across calls**. In a
worktree-isolated session, one `cd` into the parent (shared) checkout moves it
there permanently, and the isolation guard then refuses **every** subsequent
command — *including the `cd` back*, because it evaluates the shell's current
cwd before running anything. The state is self-reinforcing:

```
cd /repo && rg …                 # succeeds; cwd now the shared checkout
cd /repo/.claude/worktrees/wt    # REFUSED — "resolved to the shared checkout"
pwd                              # REFUSED — same reason
```

**`! <cmd>` does not escape it.** The user's own `!`-prefixed command runs in
the *same session shell*, so handing them the `cd` (the reflex from the
denial-handoff above) fails identically. This is the one case where that
handoff is wrong.

**Recovery: `EnterWorktree` with an explicit `path`** pointing at the worktree
already in use. It re-pins the session's working directory as session state
rather than going through the shell, so the guard never sees the bad cwd:

```
EnterWorktree(path="/repo/.claude/worktrees/<name>")   # then `pwd` works again
```

- **Prevention**: never `cd` outside the worktree. Use absolute paths, or
  `git -C <path>` / `grep <abs-path>` — a *parallel* batch is the usual culprit,
  since one sibling's `cd` moves the cwd for everything after it.
- If the Grep tool is unavailable in the session (it is not always registered),
  Bash is the only search path — so this wedge can take out searching too. Read
  and Edit keep working; they take absolute paths and ignore cwd.

## The same persistent cwd makes a path-scoped *verification* pass over nothing

The wedge above is loud — every command is refused. The quieter consequence of
the same persistent cwd is a **verification that reports success having checked
zero items**, because its path filter is relative and the cwd moved out from
under it. Nothing errors; the check just has an empty input set, and an empty
set satisfies every "nothing was lost" assertion you can write.

```
cd repo/subdir && …                                  # cwd now subdir, persistently
git diff --name-only HEAD -- docs/                   # → empty: no repo/subdir/docs/
# verification loops over the empty list and prints "no content lost"
```

Observed 2026-08 verifying a 26-file migration: an earlier call had left the
cwd in a plugin subdirectory, so the file list came back empty and the
body-preservation check passed instantly. Re-run from the repo root it found 26
files — and still passed, but only the second run was evidence of anything.

- **Assert the input is non-empty before verifying it.** One line, and it turns
  a silent vacuous pass into a loud failure:

  ```python
  assert files, "FIXTURE INVALID: nothing to check — this verification is vacuous"
  ```

  This is `never-fabricate-test-identifiers.md`'s known-good control and the
  guard-integrity half of `validate-adversarial-constructions.md`, applied to
  an *ad-hoc* check rather than a committed test. Ad-hoc is exactly where it
  gets skipped, and exactly where nobody reviews it afterwards.
- **Anchor the paths instead of trusting the cwd** — `git -C <abs-repo>`, or
  resolve the repo root (`git rev-parse --show-toplevel`) in the same command
  that uses it. A relative path in a long-running session is a bet on state
  several calls back.
- **Report the count, not just the verdict.** "26 files checked, none lost"
  cannot hide this; "no content lost" can. Any check whose output would read
  identically at N=0 and N=26 is not yet a check.

## Workflow `args` can arrive as a JSON **string**, silently

Passing an object to the `Workflow` tool's `args` can reach the script
JSON-**encoded**, so `args.foo` is `undefined` and every agent runs without the
input. Nothing errors — the prompts interpolate the literal text `undefined`
and the run completes normally. Observed 2026-08: a 15-agent comparison ran
end-to-end against material it never received; only the synthesis agent noticed
and said so in its report.

- **Make the script defensive**, since you cannot rely on the delivery shape:

  ```js
  const SOURCE = typeof args === 'string'
    ? (JSON.parse(args).source ?? args)
    : (args?.source ?? '')
  ```

- **Re-run without re-paying for the good agents.** The cache key is the
  agent's `(prompt, opts)`, so *freeze the phases that were already correct
  byte-identical* — keep the broken interpolation literal (`undefined`) in
  their prompt template, add a corrected template for the affected phases only
  — then `Workflow({scriptPath, resumeFromRunId})`. The untouched phases replay
  from cache at zero cost. Changing a shared template string changes every
  prompt and forfeits the whole cache.
- **The tell is absence, not error**: agents reporting thin, generic, or
  hedged findings on material you know is rich. Have at least one agent state
  what it actually received.

## Parallel tool calls

### Do not parallel-batch a tool whose siblings can exit non-zero

When one call in a parallel batch exits non-zero, **every sibling is
marked cancelled** and wasted. Specific offenders to avoid in a batch:

- `task <filter> list` — exits 1 on empty result; use
  `task <filter> export | jq '.[]'` (always exit-0) instead.
- `tar -xzf <archive>` — fails on missing archive; verify path first.
- `ls <glob>` — fails on no-match; verify or use Glob.
- `jq` on possibly-empty pipelines.
- `Read` on a possibly-missing path (see above).

Pattern: when a batch's siblings depend on existence, do a single
existence-check call first (`Glob`, `ls -1`), then issue the parallel
batch over confirmed-present paths.

### Agent fan-out rate limits and mid-run kills

Promoted to a skill: see `agent-patterns-plugin:parallel-agent-dispatch`
(§ Concurrent Rate-Limit Risk → `references/failure-recovery.md`) before
fanning out more than ~3 heavy agents, and after any wave dies mid-run — it
carries the server burst limit vs session usage limit discrimination, safe
starting concurrency per agent profile, serialize-or-wave mitigation, the
audit-remote-before-resume protocol (`gh pr list`, `git ls-remote --heads`),
and why `resumeFromRunId` re-runs already-succeeded worktree agents.

For mechanical work (parsing, counting, audits) prefer one inline `python3`/`rg`
pass over an agent fan-out — see `offload-to-deterministic-substrate.md`.

### The remote is not the whole audit — a dead agent's work may be in a worktree

Step 2 above says audit the **remote**. That is only sufficient when the agent
actually ran remotely, and you cannot assume it did: `isolation: "remote"` can
resolve to a **local git worktree** in the shared checkout. Nothing in the
dispatch result distinguishes the two — the completion notification's
`worktreePath` field does, and so does `git worktree list`.

> Observed 2026-08-19 (claude-plugins). Three agents dispatched with
> `isolation: "remote"` all ran in `.claude/worktrees/agent-<id>/`. Two were
> killed by a 600s stall watchdog. For one, `gh pr list` and
> `git ls-remote --heads origin` were both empty, and its work was reported to
> the user as unrecoverable — twice. `git worktree list` showed its branch
> carrying a **complete** commit (both intended edits plus a 28-line doc table)
> that had simply never been pushed. The remote audit was correct and the
> conclusion drawn from it was wrong.

- **Audit local worktrees alongside the remote**, before concluding anything was
  lost:

  ```
  git worktree list
  git log --oneline origin/main..<branch>    # per stale worktree branch
  ```

- **An empty remote is evidence about the push, not about the work.** The two
  come apart precisely when an agent dies between committing and pushing — the
  most likely single point to die, since the push is the last step.
- **Mitigate at dispatch**: brief agents to commit, push, and open a *draft* PR
  before the bulk of the work, then push after each subsequent commit. The same
  session's retry survived having its branch merged and deleted mid-task because
  it had pushed early; the recovery cost was one cherry-pick onto a fresh branch.
- Cleanup of the leftover worktrees is governed by `agent-coworker-detection.md`
  (claude-plugins): gate removal on the agent's completion notification, never on
  PR state, and never `--force` — a non-forced `git worktree remove` refuses on a
  dirty tree, which is the property that makes it safe.
