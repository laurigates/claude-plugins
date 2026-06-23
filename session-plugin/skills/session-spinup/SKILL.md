---
name: session-spinup
description: Read-only session-start briefing of open tasks, git state, journal todos. Use when user says spin up, what was I doing, or pick up where I left off.
allowed-tools: Bash(task *), Bash(git *), Bash(gh *), Read, TodoWrite
created: 2026-05-13
modified: 2026-06-22
reviewed: 2026-06-22
---

# session-spinup

Read-only orientation at session start — the inverse of
`session-plugin:session-wrap`: where wrap writes loose threads, spinup
reads them back. The failure mode this prevents: the user sits down,
doesn't remember what was open, and starts fresh on something else while
yesterday's PR sits stale.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| User says "spin up", "what was I doing", "pick up where I left off" | Resuming a TDD cycle on known state → `project-plugin:project-continue` |
| Fresh session opens with open threads (hook-nudged) | Cross-project queue health → `taskwarrior-plugin:task-status` |
| Orienting before picking the next move | Unfamiliar codebase orientation → `project-plugin:project-discovery` |

## Configuration

Same file as the other session skills: `.claude/session-plugin.local.md`
(project) → `~/.claude/session-plugin.local.md` (user-global) → none.
When `journal` is configured and the session matches `journal_scopes`,
the briefing includes unchecked todos from the most recent dated note.
Schema: [session-wrap/REFERENCE.md](../session-wrap/REFERENCE.md).

## Sources

| Source | When | What comes from there |
|---|---|---|
| **taskwarrior** | Every spin-up | Pending tasks for the inferred project; `+ACTIVE` tasks; recently-annotated tasks |
| **GitHub issues** | Every spin-up with a GitHub remote | Open issues assigned to you in the **cwd repo** that no surveyed task already references — the issues opened on GitHub but never mirrored into taskwarrior |
| **Journal** | Only when configured + in scope | Unchecked `- [ ]` items under the todo heading, most recent note ≤7 days back |
| **git state** | Every spin-up | Current branch, uncommitted changes, unpushed commits, open PRs from this branch |

GitHub issues close a drift gap: opening an issue does **not** create a
taskwarrior task, so without this source a freshly-filed assigned issue is
invisible to spinup and the "pending work" picture is silently wrong.

## The signal filter

Surface only what the user would otherwise miss — same 3-6 item target
as wrap; 10+ means trim.

**SURFACE**: open PR from a recent branch (especially review/CI-stale) ·
`+ACTIVE` task (work was mid-flight) · unchecked journal todo ·
real uncommitted edits · unpushed commits · task annotated "blocked on X"
where X may now be unblocked · **open assigned GitHub issue with no
matching taskwarrior task** (the drift case — filed on GitHub, never
mirrored locally).

**DO NOT SURFACE**: completed tasks · merged PRs · closed issues ·
issues assigned to someone else · **a GitHub issue already represented
by a surfaced taskwarrior task** (dedup by issue number — show the task,
not the issue) · recurring-reminder / dataview machinery in the journal ·
weeks-stale tasks with no recent annotation (that's `task-status`'s job) ·
`+ACTIVE` tasks from a *different* project than the cwd — those are stale
locks; at most one footnote line ("Stale +ACTIVE elsewhere" at the end of
the briefing), never a scope hijack.

## Execution

Execute this read-only briefing:

### Step 1: Detect the project

Tiered precedence — full table in [REFERENCE.md](REFERENCE.md):

1. cwd → unambiguous project (repo-root basename or config naming map)
2. `+ACTIVE` task's project, only when cwd is ambiguous
3. git remote name as last resort

A cross-project `+ACTIVE` task never overrides an unambiguous cwd. When cwd unambiguously maps to a project, all subsequent queries must be scoped *only* to that project.

### Step 2: Survey (parallel-safe)

```sh
task project:<name> '(status:pending or +ACTIVE)' export | jq '.[]'
git status --porcelain
git log '@{u}..HEAD' --oneline
gh pr list --head "$(git branch --show-current)" --json number,title,url,state,createdAt --jq '.[]'
gh issue list --assignee @me --state open --json number,title,url,updatedAt --jq '.[]'
```

`gh issue list` with no `-R` targets the cwd repo and `--json` returns
`[]` (exit 0) on no matches, keeping the batch parallel-safe. Skip it when
the cwd maps to no GitHub remote.

**Dedup before surfacing issues.** Collect every issue number the surveyed
tasks already reference (a `ghid` UDA, or a `#N` / `issues/N` token in any
description or annotation) and drop those from the `gh issue list` result.
What remains is the drift set — assigned, open, and untracked locally.
Dedup snippet in [REFERENCE.md](REFERENCE.md).

Journal source (only when configured + in scope): walk back from today
up to 7 days, first existing note wins, extract unchecked todos —
extraction snippet in [REFERENCE.md](REFERENCE.md).

### Step 3: Present

Compact briefing, one section per source, then 2-4 concrete "next moves".
The spin-up sections (taskwarrior / daily note / git) must reflect *only* the cwd project.
Say "git state: clean" / "nothing pending under `project:<name>`"
explicitly rather than omitting sections. Example briefing in
[REFERENCE.md](REFERENCE.md).

If a `+ACTIVE` task exists in a different project than the cwd-mapped one, do NOT include it in the cwd project's sections. Append a single line under a clearly separate "Stale +ACTIVE elsewhere" notice at the very end of the briefing.

### Step 4: Offer next moves

Let the user pick — never auto-resume a task or start a workflow. Spinup
makes the open threads visible; the user decides.

## Auto-surfacing

A SessionStart hook (`hooks/session-spinup-nudge.sh`) injects a one-time
context note when a fresh session opens with open threads (dirty tree,
unpushed commits, or open tasks for the cwd project). It offers; it never
runs the skill. Pre-silence:
`touch ~/.cache/claude-session-spinup-nudge/<session_id>`.

## Agentic Optimizations

| Context | Command |
|---|---|
| Open + in-flight tasks (exit-0 on empty) | `task project:<name> '(status:pending or +ACTIVE)' export \| jq '.[]'` |
| Unpushed commits | `git log '@{u}..HEAD' --oneline` |
| Branch PRs | `gh pr list --head <branch> --json number,title,url,state --jq '.[]'` |
| Assigned open issues (cwd repo, exit-0 on empty) | `gh issue list --assignee @me --state open --json number,title,url,updatedAt --jq '.[]'` |
| Known projects | `task _projects` |
