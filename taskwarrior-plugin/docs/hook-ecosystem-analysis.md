# Hook Ecosystem Analysis

Brainstorming how taskwarrior native hooks (`on-add` / `on-modify` / `on-exit` / `on-launch`) and
Claude Code hooks (`Stop` / `PreToolUse` / `SessionStart` / `SubagentStop` / `UserPromptSubmit`)
can work together to improve multi-agent work coordination.

## The Two Hook Systems

| Dimension | Taskwarrior Native Hooks | Claude Code Hooks |
|-----------|--------------------------|-------------------|
| Fires on | Every `task` invocation (terminal, scripts, CC) | Claude Code session events only |
| Location | `<data.location>/hooks/` | `plugin.json` or `.claude/settings.json` |
| Events | `on-launch`, `on-add`, `on-modify`, `on-exit` | `SessionStart`, `Stop`, `PreToolUse`, `PostToolUse`, `SubagentStop`, `UserPromptSubmit`, etc. |
| Enforced by | `rc.hooks=on` (default) | Claude Code runtime |
| Language | Any (bash, python, etc.) | Shell script (`type: "command"`), LLM prompt (`type: "prompt"`), subagent (`type: "agent"`) |
| Timeout | No timeout (blocks `task` until done) | Default 600s (command), 30s (prompt), 60s (agent) |
| Exit 0 means | Allow/modify the task | Allow the operation / continue |
| Exit non-zero | Reject the operation (on-add/on-modify); ignored (on-exit) | Block the turn; stderr shown to agent |
| Stdout | First line = modified JSON; subsequent = feedback | JSON response in `hookSpecificOutput` envelope |

## Current State

### What the three installed hooks already do

| Hook script | Event | Behaviour |
|-------------|-------|-----------|
| `on-add-taskwarrior-plugin` | `on-add` | Stamp `project` from git toplevel; link `ghid` from trailing `#N` in description; warn on hyphenated tags. Fail-open. |
| `on-modify-taskwarrior-plugin` | `on-modify` | Stamp claim identity (`agent`/`host`/`branch`/`worktree`) on bare `task start`; detect claim takeovers; expire stale claims past TTL (4h); warn on hyphenated tags. Fail-open. |
| `on-exit-taskwarrior-plugin` | `on-exit` | Batch GitHub-sync queue (append touched `ghid`/`ghpr` UUIDs); coworker-marker upkeep (write/remove `.claude-session-<pid>`). Fail-open. |

### What is NOT used

| Event | Currently used? | Potential |
|-------|----------------|-----------|
| `on-launch` | ❌ Not used | Pre-flight checks, environment hardening, context education |
| `on-add` | ✅ Project stamp / ghid link | BPID auto-detect, dependency linking from description |
| `on-modify` | ✅ Claim identity / TTL expiry | PID-liveness in expiry, annotation-based state transitions |
| `on-exit` | ✅ GH queue / markers | Queue stats footer, lightweight reconcile hint, split into separate scripts |

### What Claude Code hooks exist (from `plugin.json`)

Only a `SessionStart` hook that runs the drift probe (`taskwarrior-drift-probe.sh`). All other
CC hook events are unused.

---

## 1. `on-launch` — Pre-flight Environment Hardening

`on-launch` fires **after init but before any processing**. It receives 0 lines of input, emits
0 lines of JSON, and can abort the entire `task` command with a non-zero exit. Feedback is
shown as footnotes.

### 1a. UDA guarantee at every `task` invocation

**System**: TW native

Currently `ensure-udas.sh` runs only inside plugin skills and the SessionStart drift probe.
A raw `task add bpid:WO-012` outside a session will silently discard the `bpid` UDA if it's
undeclared in `~/.taskrc`.

```
on-launch → check 10 required UDAs (bpid, bpdoc, bpms, ghid, ghpr, agent, pid, host, branch, worktree)
          → if missing, abort with "Install UDAs first: /taskwarrior:task-add or run ensure-udas.sh"
```

**Effort**: Low | **Risk**: None | **Value**: High — catches the silent-drop bug class

### 1b. Stale lock guard

**System**: TW native

If a `~/.task/.lock.*` file exists from a crashed agent session (or an unclean exit), taskwarrior
polls it for 30 seconds before giving up. This is invisible to the user.

```
on-launch → check for lock files where owning PID is dead
          → clean them up and proceed
          → footnote: "Cleaned stale lock from dead PID 98765"
```

**Effort**: Low | **Risk**: None | **Value**: Medium — debuggability

### 1c. Version compatibility check

**System**: TW native

Some features the hooks rely on (`+READY` virtual tag, DOM references) were added in specific
versions. Warn (don't block) if the running version is too old.

```
on-launch → task --version → parse major.minor
          → if < 2.6.0: footnote warning about +READY
```

**Effort**: Low | **Risk**: None | **Value**: Low — rare edge case

### 1d. Multi-agent claim detection on shared `data.location`

**System**: TW native

Two agents sharing the same `data.location` (e.g., over syncthing) can corrupt each other's
claims. If a task is `+ACTIVE` with a `pid` on a different `host`, the current agent might
inadvertently conflict.

```
on-launch → check for +ACTIVE tasks with host != $(hostname)
          → warn: "N tasks claimed on other hosts — verify before starting work"
```

**Effort**: Medium | **Risk**: None | **Value**: Medium

### 1e. GitHub auth health check

**System**: TW native

If the cwd is a git repo with a remote and `ghid`-bearing tasks exist, verify `gh auth status`
is still valid.

```
on-launch → git remote? gh auth status?
          → if token expired: "GitHub auth expired — /taskwarrior:task-reconcile will fail"
```

Does not abort — the user may not need GH features this session.

**Effort**: Low | **Risk**: None | **Value**: Medium

### 1f. Cross-project task leakage education (context nudge)

**System**: TW native

The most insidious UX problem: `task list` shows tasks from ALL projects. The on-add hook
auto-stamps `project:<repo>`, but a raw `task list` still shows everything.

```
on-launch → detect cwd → git toplevel → project name
          → if no context active: footnote suggesting one
          → if context doesn't match cwd: footnote to switch
          → if context matches: silence (self-extinguishing)
```

Full treatment in §7 below.

---

## 2. `on-add` — Enhancement Opportunities

### 2a. Blueprint ID auto-detection from description

**System**: TW native

If the description carries `WO-\d+` / `PRP-\d+` / `FR-\d+`, auto-stamp `bpid`. Currently
requires explicit `bpid:` pass, so ad-hoc `task add` outside skills misses the linkage.

```
on-add → jq '.description' → grep for BPID pattern
       → if found and bpid is unset: stamp .bpid = "WO-042"
       → footnote: "Auto-linked bpid: WO-042"
```

**Effort**: Low | **Risk**: None | **Value**: Medium

### 2b. Dependency linking from description

**System**: TW native

If the description mentions `depends:#N` or `blocked-by:#N`, auto-set the `depends:` field
to the matching task (by description search or existing `ghid`).

```
on-add → if desc matches depends:#N:
       → task export | jq to find the referenced task's UUID
       → stamp .depends = ["<uuid>"]
       → footnote: "Linked dependency on task <uuid>"
```

**Risk**: Medium — wrong task matched. Gate behind a minimum description match threshold.

**Effort**: Medium | **Value**: Medium

### 2c. Tag auto-correction (beyond hyphenated warning)

**System**: TW native

Currently warns on hyphenated tags but doesn't fix them. Could auto-correct known patterns:

Broken forms below are written **without** the leading `+` sigil on purpose —
`scripts/lint-taskwarrior-tags.sh` flags any hyphenated tag written with its
sigil anywhere in this plugin's docs, and that guard should stay strict. Read
each "bad input" cell as if it carried a `+`.

| Bad input | Auto-corrected to |
|-----------|-------------------|
| `blocked-on-merge` | `+blocked_on_merge` |
| `needs-review` | `+needs_review` |
| `work-order` | `+wo` (canonical short form) |

```
on-add → detect a hyphenated tag → rewrite to canonical form
       → footnote: "Auto-corrected blocked-on-merge → +blocked_on_merge"
```

**Effort**: Low | **Risk**: None | **Value**: Low

### 2d. Milestone validation

**System**: TW native

If `bpms` is set or a milestone is detected in the description, validate against known
projects / milestones.

```
on-add → if bpms set but not in task _projects: warn
```

**Effort**: Low | **Risk**: None | **Value**: Low

### 2e. Guard against empty descriptions

**System**: TW native

A fat-fingered `task add` with no description creates a silent placeholder.

```
on-add → if (.description // "") == "": footnote warning
```

Must not abort — some workflows use blank descriptions intentionally.

**Effort**: Low | **Risk**: None | **Value**: Low

---

## 3. `on-modify` — Enhancement Opportunities

### 3a. PID liveness check in stale-claim expiry

**System**: TW native

**The most valuable improvement to the existing hooks.** The current TTL expiry (4h timer)
fires on any task touch regardless of whether the claiming agent is still alive. If the
agent is genuinely working slowly (e.g., a long-running compile), this falsely expires the
claim and removes `+ACTIVE` — confusing the user and losing the claim's duration tracking.

```
on-modify → before TTL expiry fires:
          → if .host equals $(hostname) AND .pid is a number AND kill -0 .pid succeeds:
          →   skip expiry (agent is still alive)
          → else if .host equals $(hostname) AND .pid is dead:
          →   expire, annotate: "Claim released: pid .pid is no longer running"
          → else:
          →   fall back to TTL timer (cross-host claim, can't check PID)
```

The dead-PID release is already handled deterministically by `scripts/release-stale-claims.sh`
at session start. This enhancement preserves the existing fallback and only adds a cheap
`kill -0` check before expiring — reducing false positives on the same host.

**Effort**: Low | **Risk**: Reduces false-positive TTL expiry | **Value**: High

### 3b. Annotation-based state transitions

**System**: TW native

Detect special annotation patterns and auto-apply/remove tags and UDAs:

| Annotation pattern | Auto-action |
|-------------------|-------------|
| `BLOCKED: waiting on PR #45` | Tag `+blocked`, set `wait:` if date-like followup detected |
| `UNBLOCKED` | Remove `+blocked`, clear `wait:` |
| `PART OF: WO-045` | Set `bpid: WO-045` if not already set |
| `ESTIMATE: 3h` | Set `effort: 3h` (new numeric UDA) |

```
on-modify → compare original.annotation vs modified.annotation
          → match against known patterns via jq (not grep — grep is fragile on multi-line)
          → update JSON accordingly
```

**Risk**: Medium — regex fragility and false positives. Gate behind opt-in env var?

**Effort**: Medium | **Value**: Medium

### 3c. `due:` / `scheduled:` / `wait:` cross-check

**System**: TW native

Common data-entry mistakes:

```
on-modify → if .due < .scheduled: warn "due is before scheduled"
          → if .wait > .due: warn "wait is after due — task will appear after it's already due"
          → if .scheduled is set and .due is not: "scheduled without due?"
```

**Effort**: Low | **Risk**: None | **Value**: Low

### 3d. Parent/child project cascade

**System**: TW native

When a task's `project:` changes, check if dependents still match the old project and warn.

```
on-modify → if .project changed:
          → query tasks depending on this UUID
          → if any have different project value: warn
```

**Effort**: Medium | **Risk**: None | **Value**: Medium

### 3e. Duration annotation on TTL expiry

**System**: TW native

When the TTL expiry fires (or the PID-liveness check confirms a dead agent), annotate the
task with the elapsed active duration for audit trail.

```
on-modify → on TTL expiry:
          → start_epoch = parse(.start), end_epoch = now
          → duration = end_epoch - start_epoch
          → annotate: "Claim auto-expired after ${duration}m (TTL ${ttl_hours}h)"
```

**Effort**: Low | **Risk**: None | **Value**: Low — audit trail

### 3f. Guard against accidental `project:` removal

**System**: TW native

If a `modify` removes `project:` (sets it to empty), warn that the task will be orphaned
from its project queue.

```
on-modify → if .project was set and is now empty: warn
```

**Effort**: Low | **Risk**: None | **Value**: Low

---

## 4. `on-exit` — Enhancement Opportunities

`on-exit` fires ONCE after the command exits, receiving all added/modified tasks (0+ lines).
Stdout is advisory — the first line is NOT treated as JSON (unlike on-add/on-modify).
Exit code is ignored.

### 4a. Queue statistics footer

**System**: TW native

After every mutation, emit a one-line queue summary. Keeps health visible without a separate
`/taskwarrior:task-status` call.

```
on-exit → task status:pending export | jq → count by state
        → echo "Queue: 12 pending, 3 active, 1 overdue, 8 ready"
```

**Optimisation**: The on-exit hook already received the changeset in stdin. It can count
locally without a second `task export` for tasks touched this invocation. For the full
queue it still needs a query, but that's a single `export` call — cheap.

**Effort**: Low | **Risk**: None | **Value**: Medium — ambient awareness

### 4b. Lightweight reconcile hint

**System**: TW native

For each touched task carrying a `ghid`, check if the linked issue/PR is closed. If so,
flag it. No TTL cache (unlike the SessionStart probe) — just a quick check on touched tasks.

```
on-exit → for each task in changeset:
         → if .ghid or .ghpr is set and upstream is closed:
         →   flag: "Task #N (ghid:#M) — issue has closed. Run /taskwarrior:task-reconcile"
```

Not a replacement for the batched reconcile pass (which checks ALL linked tasks). This is
a just-in-time hint for the tasks the user just touched.

**Effort**: Low | **Risk**: None | **Value**: Medium

### 4c. Split into separate scripts (collating sequence)

**System**: TW native

The current monolithic `on-exit-taskwarrior-plugin` handles two concerns: ghsync queue +
coworker markers. Taskwarrior runs all scripts for the same event in **collating sequence**,
and on-exit is already advisory-only (exit code ignored). This is ideal for splitting:

| Script name | Responsibility | Fails independently? |
|-------------|----------------|---------------------|
| `on-exit-01-ghsync-queue` | Append touched `ghid`/`ghpr` UUIDs to queue | ✅ (fail-open) |
| `on-exit-02-coworker-markers` | Write/remove `.claude-session-<pid>` markers | ✅ (fail-open) |
| `on-exit-03-queue-stats` | Print queue statistics footnote | ✅ (fail-open) |
| `on-exit-04-orphan-cleanup` | Clean orphaned `.claude-session-*` across all worktrees | ✅ (fail-open) |

Each script is smaller, independently testable, and independently disableable (remove
execute permission on one without affecting the others). The collating-sequence prefix
(`01-`, `02-`, `03-`, `04-`) is descriptive — scripts run in that order, and a single
non-zero exit from an on-exit script is ignored.

**Effort**: Medium | **Risk**: Low with good tests | **Value**: High — maintainability

### 4d. Batch annotation journal

**System**: TW native

When a `task import` round-trip runs (used by `/taskwarrior:task-reconcile`'s bulk close
path), the on-exit hook sees the whole batch. Log a summary annotation somewhere.

```
on-exit → if changeset size > threshold (say, 5):
        → count closed tasks
        → echo: "Bulk close: 5 tasks retired (3 PR merged, 2 issue closed)"
```

**Effort**: Low | **Risk**: None | **Value**: Low

### 4e. Live per-task reconcile (skip the queue file)

**System**: TW native

Currently the hook queues UUIDs to a file, and the SessionStart drain resolves them later.
For tasks whose `ghid` was newly SET (not just touched), we could immediately check the
upstream state. The queue file stays for the "touched a task whose linkage existed before"
case (which we can't distinguish from no change since on-exit has no before-image).

**Effort**: Medium | **Risk**: Low | **Value**: Medium

---

## 5. Claude Code Hook Opportunities

### 5a. `Stop` → task claim hygiene

**System**: CC hook (command type)

When Claude Code finishes a response (`Stop` event), check if the session holds any
`+ACTIVE` task claims that should be released. Uses the drift-protocol pattern from the
existing probes (self-extinguishing, fires only on real findings).

```
Stop → task +ACTIVE agent:claude-${CLAUDE_SESSION_ID:0:8} count
     → if > 0 and stop_hook_active is false:
     →   emit additionalContext: "You have N unreleased task claims — consider task-release"
     → if stop_hook_active is true: silent (loop guard)
```

**Effort**: Low | **Risk**: None | **Value**: Medium

### 5b. `SubagentStop` → release subagent claims

**System**: CC hook (command type)

When a subagent finishes (`SubagentStop`), check if it had any `+ACTIVE` task claims and
auto-release them. This prevents orphaned claims from agent teams where subagents forget
to release before returning.

```
SubagentStop → task +ACTIVE agent:claude-${CLAUDE_SESSION_ID:0:8} export
             → for each: task $uuid stop && task $uuid modify agent: pid: host: branch: worktree:
```

More aggressive than 5a (auto-releases instead of nudging) because a subagent is ephemeral
and has no future turns to act on a nudge.

**Effort**: Low | **Risk**: Low — subagents should not hold claims across sessions | **Value**: Medium

### 5c. `Stop` `additionalContext` soft nudge (post-close feedback)

**System**: CC hook (command type, using 2.1.163+ `additionalContext`)

After a `/taskwarrior:task-done`, if the closed task had dependents that are now unblocked,
nudge the agent without blocking the turn.

```
Stop → check if the last tool call was "task done"
     → query task depends:<closed-uuid> — any now-unblocked?
     → emit additionalContext: "2 dependent tasks are now unblocked"
```

Not a block — just a soft nudge that the agent can act on or ignore.

**Effort**: Low | **Risk**: None | **Value**: Low

### 5d. `PreToolUse` → guard against broken UUID discipline

**System**: CC hook (command type)

The most common footgun across the project's own rules (`.claude/rules/task-id-stability.md`):
running `task <numeric> <mutate>` where the numeric ID was resolved minutes ago and may
have renumbered. Nudge the agent to use UUIDs.

```
PreToolUse (matcher: Bash) → if COMMAND matches '^task [0-9]+ (modify|done|start|stop|annotate)'
                           → if COMMAND does NOT contain a UUID-looking token:
                           →   ask: "Using numeric ID — tasks may have renumbered since resolve. Use UUID instead?"
```

Two variants:

| Variant | Mechanism | Experience |
|---------|-----------|------------|
| **Nudge + allow** | `permissionDecision: "ask"` with warning reason | Agent sees the warning, bypasses if intentional |
| **Auto-block** | `permissionDecision: "deny"` | Safer but may frustrate intentional numeric-ID use |

Recommend: **nudge + allow** initially. The guard is advisory — the agent already has UUID
discipline in skill code, but raw Bash calls may forget.

**Effort**: Low | **Risk**: Nudge only | **Value**: High — prevents a real bug class

### 5e. `UserPromptSubmit` → raw `task` detection

**System**: CC hook (prompt type)

When a user types a raw `task` command rather than a `/taskwarrior:*` skill, offer to route
through the plugin skills instead. This is a one-time education hook.

```
UserPromptSubmit → if prompt starts with "task "
                 →   return ok: false, reason: "I see you used raw 'task'. The plugin has 
                     /taskwarrior:task-add, /taskwarrior:task-status, etc. — try those?"
```

Risk: annoying. Gate behind a per-session dedup so it fires at most once.

**Effort**: Low | **Risk**: None | **Value**: Low — onboarding aid

### 5f. `ConfigChange` → UDA drift monitor

**System**: CC hook (command type)

If `.claude/settings.json` changes in a way that disables the taskwarrior-plugin, warn that
UDA-reliant hooks will break.

```
ConfigChange → if config_key matches "enabledPlugins.*taskwarrior-plugin"
             → log audit entry
```

**Effort**: Low | **Risk**: None | **Value**: Low

---

## 6. Cross-System Integration Patterns

### 6a. Reverse-direction webhook (GitHub → Taskwarrior)

**System**: External server (not a hook script)

Instead of polling GitHub via reconcile, set up a lightweight webhook receiver that updates
taskwarrior tasks in real time when linked issues/PRs change state.

```
GitHub webhook → issue.closed → find task by ghid → annotate "Linked issue closed upstream"
               → issue.reopened → find task by ghid → reopen task
               → pr.merged → find task by ghpr → auto-close task with reconcile annotation
```

**Complexity**: Needs a server process (Cloudflare Worker, Railway, or local daemon) that
has both `gh` CLI access and a taskwarrior data directory. Taskwarrior doesn't support
remote API access — it reads local `.data` files — so the webhook handler must either
shell out to `task` or write task data files directly (fragile).

**Effort**: High | **Value**: High — true real-time reconciliation | **Replaces**: polling

### 6b. `on-add` → GitHub issue subscription

**System**: TW native (calls gh CLI)

When a task with `ghid` is filed, auto-watch the GitHub issue and post a "tracking this"
comment.

```
on-add → if .ghid set and commit-access check passes:
       → gh api -X PUT repos/:owner/:repo/subscription  (watch the issue)
       → gh issue comment "$GHID" --body "Tracking this issue in taskwarrior via claude-plugins"
```

**Risk**: Requires commit-level scope on the GH token. May be too aggressive for all tasks.
Opt-in via env var?

**Effort**: Medium | **Value**: Medium

### 6c. Hook → CC signal file (cross-world messaging)

**System**: TW native writes, CC hook reads

The two hook systems operate independently with no shared runtime. Bridge them via a
well-known file path:

```
TW on-exit → writes structured signal to ~/.task/claude-signals/<session_id>/
CC SessionStart → reads and drains signals for this session
```

Signal types:

| Signal file | Written by | Read by | Purpose |
|-------------|------------|---------|---------|
| `tasks_done` | on-exit (when task.status → completed) | UserPromptSubmit | "3 tasks closed while you were away — issues still open?" |
| `claims_released` | on-modify (TTL expiry) | SessionStart | "Claim on task #N auto-expired" |
| `gh_sync_pending` | on-exit | SessionStart drift probe | Already handled via the queue file |

**Risk**: File-based signaling is fragile (races, stale files). The existing ghsync queue
already follows this pattern successfully.

**Effort**: Medium | **Value**: Medium

### 6d. Session-aware hooks

**System**: TW native (checks env vars)

The on-launch and on-add hooks can detect whether they're running inside a Claude Code
session (via `CLAUDE_SESSION_ID`) and adjust their behaviour:

| Behaviour | Inside CC session | Outside CC session |
|-----------|------------------|-------------------|
| on-add feedback | Machine-friendly (`KEY=VALUE`) | Human-friendly prose |
| on-launch context nudge | Skip (CC already handles via PreToolUse) | Print suggestion |
| on-launch UDA check | Skip (CC drift probe handles it) | Run the check |

```
on-launch → if CLAUDE_SESSION_ID is set: minimal output
          → else: verbose human-oriented hints
```

**Effort**: Low | **Value**: Medium

---

## 7. Cross-Project Task Leakage — Full Treatment

### The problem

The plugin auto-stamps `project:<repo>` on every new task (on-add hook), and all skills
scope queries by project. But raw `task list` / `task next` / bare `task` shows tasks from
**all** projects. Within Claude Code this wastes agent context; at the terminal it's confusing
noise.

### Mitigations by system

| # | Mitigation | System | Auto-scopes? | Works outside CC? | Self-extinguishing? | Risk |
|---|-----------|--------|-------------|-------------------|---------------------|------|
| 7a | `PreToolUse` auto-scope raw `task list` | **CC** hook | ✅ Rewrites cmd | ❌ | N/A (always rewrites if no filter) | Low |
| 7b | `on-launch` context education footnote | **TW** native | ❌ Educates | ✅ | Once context matches cwd | None |
| 7c | `on-launch` auto-activate matching context | **TW** native | ✅ Side-effect | ✅ | Always active | **Medium** — dir-crossing |
| 7d | `direnv` + `TASKRC` cascade | **Shell** setup | ✅ | ✅ | N/A (explicit choice) | None |
| 7e | `Stop` post-response hygiene check | **CC** hook | ❌ Reports | ❌ | Self-extinguishing | None |

### 7a. `PreToolUse` auto-scope (recommended as primary)

**System**: CC hook

When an agent types `task list`, `task next`, or bare `task` without a project filter,
silently rewrite the command to include the project filter.

```bash
# scope-task-list.sh — PreToolUse hook, matcher: Bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Match bare `task`, `task list`, `task next`, `task all` — without an explicit project filter
if echo "$CMD" | grep -qE '^task\s*(list|next|all|$)' \
   && ! echo "$CMD" | grep -qE '(^|\s)project:'; then
  PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || true)")
  [ -n "$PROJECT" ] || exit 0  # no repo → no scoping

  SCOPED=$(echo "$CMD" | sed "s/^task/task project:$PROJECT/")
  cat <<JSON
{"hookSpecificOutput": {
  "hookEventName": "PreToolUse",
  "updatedInput": {"command": "$SCOPED"}
}}
JSON
  exit 0
fi
exit 0
```

If git resolution fails, the hook exits 0 and the raw command passes through — fail-open.

**Variation**: Instead of silent rewrite, use `permissionDecision: "ask"` to let the agent
explicitly choose.

### 7b. `on-launch` context education footnote (recommended as secondary)

**System**: TW native

For terminal users who run `task list` directly. Prints a one-liner suggesting context setup
the first time in a new repo. Self-extinguishing.

```bash
# on-launch context educator (snippet to add to the on-launch hook)
project=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || true)")
[ -z "$project" ] && exit 0

current_ctx=$(task _get rc.context 2>/dev/null || true)
ctx_exists=$(task _get "rc.context.$project" 2>/dev/null || true)

if [ -z "$current_ctx" ] && [ -n "$ctx_exists" ]; then
  echo "taskwarrior-plugin: context '$project' exists but is not active. Use 'task context $project' to scope lists."
elif [ -z "$current_ctx" ] && [ -z "$ctx_exists" ]; then
  echo "taskwarrior-plugin: define 'task context define $project project:$project', then 'task context $project' to scope lists to this repo."
elif [ -n "$current_ctx" ] && [ "$current_ctx" != "$project" ]; then
  echo "taskwarrior-plugin: context '$current_ctx' active but cwd is in '$project'. Use 'task context $project' to switch."
fi
# matching context → silent
```

### 7c. `on-launch` auto-activate matching context (not recommended)

**System**: TW native

```bash
if task _get "rc.context.$project" >/dev/null 2>&1; then
  current=$(task _get rc.context 2>/dev/null || true)
  if [ "$current" != "$project" ]; then
    task context "$project"  # mutates ~/.taskrc
  fi
fi
```

**Why not recommended**: Auto-mutates `.taskrc` as a side effect of every `task` command.
If the user `cd`s to a different repo, the context silently follows — now `task list` in
the new repo shows the OLD repo's tasks until the next invocation catches up. Also, `task
context` is itself a `task` command, causing recursive hook invocation (the on-exit hook
fires for the context-switch command).

### 7d. `direnv` + `TASKRC` cascade (power-user upgrade)

**System**: Shell setup (no hooks)

```bash
# .envrc (per repo)
export TASKRC="$HOME/.taskrc:$PWD/.taskrc-project"
```

```ini
# .taskrc-project
context=myrepo
```

Then `task list` in that directory automatically loads the project context. Requires:
1. `direnv` installed and hooked into the shell
2. Per-repo `.envrc` + `.taskrc-project` (could be scaffolded by a plugin skill)

Scaffold command (idempotent):
```bash
cat > .taskrc-project <<'INI'
context=<project>
INI
cat > .envrc <<'ENVRC'
export TASKRC="$HOME/.taskrc:$PWD/.taskrc-project"
ENVRC
direnv allow
```

### 7e. `Stop` post-response hygiene check

**System**: CC hook

After the agent finishes a response, if it ran any `task` command without scoping, emit a
soft nudge:

```bash
# Check if the last turn included unscoped task commands
if grep -qE 'task (list|next|all|^[^ ]*$)' <<<"$recent_commands" \
   && ! grep -qE 'project:' <<<"$recent_commands"; then
  # emit additionalContext
fi
```

### Recommended layered approach

| Layer | What | Who it protects | When it fires |
|-------|------|----------------|---------------|
| **Primary** (7a) | `PreToolUse` auto-scopes raw `task list` in CC | Agent (avoids context waste) | Every CC session |
| **Secondary** (7b) | `on-launch` context nudge at terminal | Human terminal user | First few `task` invocations per repo |
| **Upgrade** (7d) | `direnv` + `TASKRC` cascade | Both (CC and terminal) | Always (once set up) |

Layers 7a + 7b together cover both environments with zero config mutation and no surprises.
Layer 7d is the "power user" upgrade — set up once, scoped everywhere.

---

## 8. Decision Matrix (All Ideas)

| # | Idea | Event | System | Effort | Risk | Value | Replaces / complements |
|---|------|-------|--------|--------|------|-------|------------------------|
| 1a | UDA guarantee | `on-launch` | TW | Low | None | **High** | Complements `ensure-udas.sh` |
| 1b | Stale lock guard | `on-launch` | TW | Low | None | Medium | Complements drift probe |
| 1c | Version check | `on-launch` | TW | Low | None | Low | Advisory |
| 1d | Multi-agent detection | `on-launch` | TW | Medium | None | Medium | New capability |
| 1e | GH auth check | `on-launch` | TW | Low | None | Medium | Complements `detect-gh-mode.sh` |
| 1f | Context education | `on-launch` | TW | Low | None | Medium | New capability |
| 2a | BPID auto-detect | `on-add` | TW | Low | None | Medium | Complements `task-add` skill |
| 2b | Depends from desc | `on-add` | TW | Medium | Medium | Medium | New UX |
| 2c | Tag auto-correct | `on-add` | TW | Low | None | Low | Extends hyphenated warning |
| 2d | Milestone validation | `on-add` | TW | Low | None | Low | New UX |
| 2e | Empty desc guard | `on-add` | TW | Low | None | Low | New UX |
| 3a | **PID liveness in expiry** | `on-modify` | TW | Low | Reduces false +ves | **High** | Improves stale-claim logic |
| 3b | Annotation state transitions | `on-modify` | TW | Medium | Medium | Medium | New automation |
| 3c | Date cross-check | `on-modify` | TW | Low | None | Low | New UX |
| 3d | Parent/child cascade | `on-modify` | TW | Medium | None | Medium | New UX |
| 3e | Duration annotation | `on-modify` | TW | Low | None | Low | Audit trail |
| 3f | Guard project removal | `on-modify` | TW | Low | None | Low | New UX |
| 4a | Queue stats footer | `on-exit` | TW | Low | None | Medium | Complements `task-status` |
| 4b | Lightweight reconcile hint | `on-exit` | TW | Low | None | Medium | Complements `task-reconcile` |
| 4c | **Split on-exit into scripts** | `on-exit` | TW | Medium | Low with tests | **High** | Refactoring |
| 4d | Batch annotation journal | `on-exit` | TW | Low | None | Low | New UX |
| 4e | Live per-task reconcile | `on-exit` | TW | Medium | Low | Medium | Complements queue file |
| 5a | Stop → claim hygiene | `Stop` | CC | Low | None | Medium | Complements `task-release` |
| 5b | SubagentStop → release | `SubagentStop` | CC | Low | None | Medium | Complements `task-release` |
| 5c | Stop additionalContext | `Stop` | CC | Low | None | Low | New UX |
| 5d | **UUID discipline guard** | `PreToolUse` | CC | Low | Nudge only | **High** | Enforces `task-id-stability.md` |
| 5e | Raw task detection | `UserPromptSubmit` | CC | Low | None | Low | Onboarding |
| 5f | ConfigChange monitor | `ConfigChange` | CC | Low | None | Low | Audit |
| 6a | Reverse webhook | External | Server | High | Medium | **High** | Replaces polling |
| 6b | GH subscription on-add | `on-add` | TW | Medium | Medium | Medium | New integration |
| 6c | Hook → CC signal file | Both | TW+CC | Medium | None | Medium | New comms channel |
| 6d | Session-aware hooks | `on-launch` | TW | Low | None | Medium | Optimisation |
| 7a | **PreToolUse auto-scope** | `PreToolUse` | CC | Low | Low | **High** | Prevents cross-project leakage |
| 7b | on-launch context nudge | `on-launch` | TW | Low | None | Medium | Educates terminal users |
| 7c | Auto-activate context | `on-launch` | TW | Low | **Medium** | Medium | ⚠️ Not recommended |
| 7d | direnv + TASKRC cascade | Shell | Shell | Medium | None | **High** | Power-user upgrade |

---

## 9. Recommended Next Steps (ranked)

### Tier 1 — High value, low effort, implement now

| Order | Idea | Why now |
|-------|------|---------|
| 1 | **3a — PID liveness in stale-claim expiry** | Fixes a known false-positive bug in the current on-modify hook. One `kill -0` check. |
| 2 | **7a — PreToolUse auto-scope raw `task list`** | Fixes cross-project leakage in Claude Code. ~30 lines of bash, registers in plugin.json. |
| 3 | **5d — UUID discipline guard** | Prevents the most common footgun from `.claude/rules/task-id-stability.md`. Nudge-only, no risk. |
| 4 | **1a — UDA guarantee on-launch** | Catches the silent-field-drop bug on every `task` invocation outside CC. |

### Tier 2 — Medium value, low effort, implement next

| Order | Idea | Why next |
|-------|------|----------|
| 5 | **4a — Queue stats footer** | Cheap ambient awareness. One `export | jq` on on-exit. |
| 6 | **4c — Split on-exit into separate scripts** | Improves maintainability. Collating-sequence makes it safe. |
| 7 | **1f — Context education on-launch** | Fills the "I ran `task list` at the terminal and saw other repos" gap. Self-extinguishing. |
| 8 | **6d — Session-aware hooks** | Makes feedback appropriate to environment (CC vs terminal). |

### Tier 3 — Interesting but needs more design

| Order | Idea | Why deferred |
|-------|------|--------------|
| 9 | **5a — Stop → claim hygiene** | Needs the `additionalContext` mechanism tested with the existing drift protocol. |
| 10 | **5b — SubagentStop → release** | Needs a team-use scenario to validate correctness. |
| 11 | **2a — BPID auto-detect** | Useful but low urgency — skills already handle it explicitly. |
| 12 | **4b — Lightweight reconcile hint** | Overlaps with the SessionStart probe. Worth designing as a complement, not a duplicate. |

### Tier 4 — Speculative / future

| Idea | Why far out |
|------|-------------|
| 6a — Reverse webhook | Requires a server process, webhook registration, and taskwarrior data-directory write access. Big infrastructure investment. |
| 7c — Auto-activate context | Persistent side-effect on every `task` invocation. Dir-crossing bug is too risky without an "undo" mechanism. |
| 3b — Annotation state transitions | Regex fragility at scale. Needs a rule engine (or an LLM prompt hook) to avoid false positives. |
| 6c — Hook → CC signal file | File-based IPC is inherently race-prone. The ghsync queue works because the drain clears it deterministically. |
