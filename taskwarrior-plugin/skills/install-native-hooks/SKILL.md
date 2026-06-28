---
name: install-native-hooks
description: "Install opt-in taskwarrior native on-add/on-modify/on-exit hooks: auto-stamp project, enforce claims, batch GitHub sync, maintain coworker markers. Use when hardening a local taskwarrior store."
args: "[--check] [--uninstall]"
allowed-tools: Bash(task *), Bash(bash *), Read, TodoWrite
argument-hint: optional --check (preview) or --uninstall
created: 2026-06-20
modified: 2026-06-28
reviewed: 2026-06-28
---

# /taskwarrior:install-native-hooks

Install the plugin's **opt-in** taskwarrior native hooks into the user's
taskwarrior hooks directory (`<data.location>/hooks/`). These are taskwarrior's
own `on-add` / `on-modify` / `on-exit` hooks — distinct from Claude Code hooks —
and run on every local `task add` / `task modify` / `task` exit, regardless of
whether the change came from a plugin skill.

This skill writes to the user's global taskwarrior config and is **strictly
opt-in**: it runs only when the user explicitly invokes it. Nothing else in the
plugin (no SessionStart hook, no `chezmoi apply`) installs these.

## When to Use This Skill

| Use this skill when...                                                      | Use a sibling skill instead when...                              |
| --------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| Hardening a local store so every `task add` gets auto-stamped + tag-checked | Closing stale issue/PR trackers — use `task-reconcile`           |
| You want the hyphenated-tag warning enforced outside the plugin skills      | Filing or claiming a single task — use `task-add` / `task-claim` |

## What gets installed

| Hook | Fires on | Behaviour |
| ---- | -------- | --------- |

| `on-add-taskwarrior-plugin` | `task add` | Auto-stamps `project` from the git toplevel / cwd basename when unset; auto-links the `ghid` UDA from a trailing `#N` in the description when unset (pure text, no network); warns (never rejects) on a hyphenated `+tag` in the description (the form taskwarrior mis-parses) |
| `on-modify-taskwarrior-plugin` | `modify` / `annotate` / `done` / `start` / `stop` | Stamps claim identity (`agent`/`host`/`branch`/`worktree`) when a task goes `+ACTIVE` without it (so a bare `task start` still carries the UDAs `/git:coworker-check` reads); warns on a claim takeover (`agent` change); expires a stale claim (drops `+ACTIVE` + drains identity when `start` exceeds the TTL); warns on a hyphenated tag in the modified description |
| `on-exit-taskwarrior-plugin` | every `task` exit (sees the whole changeset) | **Batches GitHub sync** — queues the UUID of each touched task carrying a `ghid`/`ghpr` linkage UDA to `<data>/claude-plugin-ghsync.queue`; a SessionStart drain (`scripts/drain-ghsync-queue.sh`, run by the drift probe) resolves them in one batched `task export`, busts the drift-probe TTL cache for the affected projects so the next stale-check re-polls in one batched `gh` pass, and clears the queue. **Maintains the coworker marker** — for a touched task carrying `pid`+`worktree`, writes `<git-dir>/.claude-session-<pid>` when it goes `+ACTIVE` without one (skip-if-exists, so the skill marker is never clobbered) and removes a now-stale marker after a raw stop/done |

All three **fail open** — on any error (missing `jq`, bad JSON) they pass the
task through unchanged and exit 0, so a broken hook never blocks `task add`. The
on-exit hook's stdout is advisory feedback only; its exit code is ignored.

The on-modify stale-claim expiry is tunable from the environment (native hooks
inherit the caller's shell):

| Variable                             | Default   | Effect                                                                          |
| ------------------------------------ | --------- | ------------------------------------------------------------------------------- |
| `CLAUDE_TASKWARRIOR_CLAIM_TTL_HOURS` | `4`       | Age (hours) past which a still-`+ACTIVE` task is expired on next touch          |
| `CLAUDE_TASKWARRIOR_NO_CLAIM_EXPIRY` | _(unset)_ | Set to `1` to disable stale-claim expiry entirely (stamping + warnings stay on) |

Expiry is **opportunistic** — it fires when a stale claim is touched by any
modify, not as a guaranteed background sweep. The deterministic dead-PID release
(laurigates/claude-plugins#1792) and scheduled reconcile (#1793) cover the
not-touched case.

The on-exit hook is likewise tunable from the environment:

| Variable                              | Default                                   | Effect                                                            |
| ------------------------------------- | ----------------------------------------- | ---------------------------------------------------------------- |
| `CLAUDE_TASKWARRIOR_GHSYNC_QUEUE`     | `<data.location>/claude-plugin-ghsync.queue` | Path of the batch gh-sync queue file                          |
| `CLAUDE_TASKWARRIOR_NO_GHSYNC_QUEUE`  | _(unset)_                                 | Set to `1` to disable the gh-sync queue (and its drain) entirely |
| `CLAUDE_TASKWARRIOR_NO_MARKER_UPKEEP` | _(unset)_                                 | Set to `1` to disable coworker-marker upkeep entirely            |

> **on-exit has no before-image.** Unlike on-modify (which sees the original and
> modified task), on-exit receives only the final state of each changed task. So
> "linkage changed" is approximated as "a touched task carries a `ghid`/`ghpr`",
> and marker upkeep keys on the task's `pid` UDA (a taskwarrior subprocess has no
> live agent PID of its own). A pure raw `task start` on a never-claimed task
> carries no `pid`, so its marker is left to `/taskwarrior:task-claim`.

> **`task import` bypasses native hooks.** Taskwarrior does **not** run
> `on-add`/`on-modify` hooks during `task import`. So `/taskwarrior:task-reconcile`'s
> bulk close path (which uses `task import`) is unaffected by these hooks — they
> complement reconciliation, they do not gate it.

## Context

- Task CLI available: !`task --version`

## Parameters

Parse `$ARGUMENTS`:

- `--check` — report which hooks are present without installing.
- `--uninstall` — remove the plugin's hooks.

## Execution

Execute this install workflow:

### Step 1: Preview

Run the installer in check mode to show the resolved hooks directory and current
state:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/install-hooks.sh" --check --templates-dir "${CLAUDE_SKILL_DIR}/templates"
```

Read `HOOKS_DIR=` and the per-hook `present`/`absent` lines.

### Step 2: Confirm

Because this writes to the user's global taskwarrior config, confirm with
**AskUserQuestion** (not a freeform prompt — see
`.claude/rules/skill-execution-structure.md`): show the hooks dir and the three
hooks, and offer install / cancel. Skip the confirm only if `--check` or
`--uninstall` was passed.

### Step 3: Install (or uninstall)

On confirmation:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/install-hooks.sh" --templates-dir "${CLAUDE_SKILL_DIR}/templates"
```

For `--uninstall`:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/install-hooks.sh" --uninstall --templates-dir "${CLAUDE_SKILL_DIR}/templates"
```

### Step 4: Verify and report

Confirm the hooks are executable and exercise them safely in a scratch store —
add a throwaway task with no project and a hyphenated tag, confirm the project is
stamped and the warning prints, then delete it.

> Smoke test (blockquoted so the tag-lint skips the intentionally-broken tag):
> `TASKDATA="$(mktemp -d)" task add "smoke +bad-tag test"` — the on-add hook
> stamps `project` and prints the hyphenated-tag warning. Remove the scratch dir
> afterwards.

Report `INSTALLED=` / `REMOVED=`, the hooks dir, and a reminder that the hooks
fail open and are bypassed by `task import`.

## Agentic Optimizations

| Context           | Command                                                               |
| ----------------- | --------------------------------------------------------------------- |
| Preview           | `bash scripts/install-hooks.sh --check --templates-dir templates`     |
| Install           | `bash scripts/install-hooks.sh --templates-dir templates`             |
| Uninstall         | `bash scripts/install-hooks.sh --uninstall --templates-dir templates` |
| Resolve hooks dir | `task _get rc.data.location` → `<that>/hooks`                         |

## Quick Reference

| Flag          | Purpose                                     |
| ------------- | ------------------------------------------- |
| _(none)_      | Confirm, then install all three hooks       |
| `--check`     | Report hooks dir + present/absent, no write |
| `--uninstall` | Remove the plugin's hooks                   |

## Related

- `/taskwarrior:task-reconcile` — bulk close uses `task import`, which bypasses these native hooks (by design)
- `/taskwarrior:task-add` — the skill that already stamps project + warns on hyphenated tags; these hooks extend that to ad-hoc `task add`
- `scripts/lint-taskwarrior-tags.sh` — the docs-side guard for the same hyphenated-tag class
- `.claude/rules/skill-execution-structure.md` — AskUserQuestion confirmation gate
