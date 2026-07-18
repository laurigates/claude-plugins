---
name: session-spinup
description: Read-only session-start briefing of open tasks, git state, journal todos. Use when user says spin up, what was I doing, or pick up where I left off.
allowed-tools: Bash(bash *), Read, TodoWrite
created: 2026-05-13
modified: 2026-07-18
compatibility: claude-code
reviewed: 2026-06-24
---

# session-spinup

Read-only orientation at session start — the inverse of
`session-plugin:session-wrap`: where wrap writes loose threads, spinup
reads them back. The failure mode this prevents: the user sits down,
doesn't remember what was open, and starts fresh on something else while
yesterday's PR sits stale.

The deterministic work — project detection, the survey, GitHub-issue
dedup against taskwarrior, staleness, journal extraction — is done by
`scripts/session-survey.sh` (shared with session-wrap, session-end, and
the spinup nudge hook). This skill runs that collector once, then applies
**judgment**: filter the digest to what matters and suggest next moves.

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
pass the journal flags to the collector so the briefing includes
unchecked todos from the most recent dated note. Schema:
[session-wrap/REFERENCE.md](../session-wrap/REFERENCE.md).

## The signal filter

The collector gathers everything; **you** surface only what the user
would otherwise miss — 3-6 item target, 10+ means trim.

**SURFACE**: open PR from a recent branch (especially review/CI-stale) ·
`+ACTIVE` task (work was mid-flight) · unchecked journal todo ·
real uncommitted edits · unpushed commits · task whose annotation reads
"blocked on X" where X may now be unblocked · GitHub drift issue (the
`GITHUB_DRIFT` section — assigned, open, untracked locally) · blueprint
tracker state when a tracker exists (ready/blocked counts, in-flight WOs)
· undrained closed WOs (`UNDRAINED_COUNT` ≥ 1 — the tracker lags reality;
a wind-down `/session-end` reconciles).

**DO NOT SURFACE**: completed tasks · merged PRs · closed issues ·
issues already represented by a surfaced task (the collector already
dedups these out of `GITHUB_DRIFT`) · recurring-reminder / dataview
machinery · weeks-stale tasks with no recent annotation (that's
`task-status`'s job) · `+ACTIVE` tasks from a *different* project
(the `STALE_ACTIVE_ELSEWHERE` section — at most one footnote line, never
a scope hijack) · the `BLUEPRINT` section when `MANIFEST=false` or
`TRACKER=false`.

## Context

- Project config: !`find . -maxdepth 2 -path '*/.claude/session-plugin.local.md'`

## Execution

Execute this read-only briefing:

### Step 1: Read config, then run the collector once

Read `.claude/session-plugin.local.md` (project, then `~/.claude/`
fallback) for the taskwarrior project-naming map and journal settings.
Then run the shared collector — it does detection, survey, dedup, and
staleness in one pass and emits a structured digest:

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-dedup --with-blueprint
```

Add `--project <name>` when the config naming map maps the cwd to a
project other than the repo basename. When the session is in journal
scope, add `--with-journal --journal-path <dir>` (plus
`--journal-todo-heading` / `--journal-todo-stop` if the config overrides
the defaults). The digest sections: `PROJECT`, `GIT`, `PRS`,
`TASKWARRIOR` (each task with its stable UUID + `STALE_DAYS`),
`GITHUB_DRIFT`, `JOURNAL`, `BLUEPRINT`, `STALE_ACTIVE_ELSEWHERE`.

### Step 1b: If `GH_READY=false`, fetch GitHub state via MCP instead

The `PRS` and `GITHUB_DRIFT` sections carry `GH_READY=`. When it is
`false` (no `gh` CLI or unauthenticated — the normal state in Claude
Code on the web), their zeros mean **not queried**, not "nothing open".
Do not present them as a clean state. Instead:

1. If GitHub MCP tools are available (`mcp__github__list_issues`,
   `mcp__github__list_pull_requests` — load via ToolSearch if needed),
   fetch the repo's open issues assigned to the user and open PRs
   authored by them, then apply the same dedup the collector would
   have: drop issues whose number appears as a task `ghid` UDA or as a
   `#N` / `issues/N` token in the `TASKWARRIOR` section's descriptions
   or annotations. Treat what survives as the `GITHUB_DRIFT` set.
2. If no GitHub path exists at all, the briefing's github line must say
   `github: not queried (gh unavailable)` — never omit it silently.

### Step 2: Apply the signal filter

Cut the digest to the 3-6 things that matter, using the filter above.
The collector has already done the mechanical drops (dedup, cross-project
separation, staleness numbers); your job is the judgment calls — e.g. is
a "blocked on X" annotation now unblocked, is an 11-day-stale PR worth a
nudge.

### Step 3: Present

Compact briefing, one section per source, reflecting **only** the cwd
project. Say "git state: clean" / "nothing pending under `project:<name>`"
explicitly rather than omitting sections. A `STALE_ACTIVE_ELSEWHERE`
entry gets a single footnote line at the very end, never its own scope.
When the repo has a feature tracker, add one blueprint line —
`blueprint: 14 ready · 2 blocked · in flight: WO-031 · undrained: WO-045`
— omitting empty fragments; omit the line entirely when the tracker is
absent. Example briefing: [REFERENCE.md](REFERENCE.md).

### Step 4: Offer next moves

Suggest 2-4 concrete "next moves" and let the user pick — never
auto-resume a task or start a workflow. Spinup makes the open threads
visible; the user decides.

## Auto-surfacing

A SessionStart hook (`hooks/session-spinup-nudge.sh`) runs the same
collector in `--summary` mode and injects a one-time context note when a
fresh session opens with open threads. It offers; it never runs the
skill. Pre-silence:
`touch ~/.cache/claude-session-spinup-nudge/<session_id>`.

## Agentic Optimizations

| Context | Command |
|---|---|
| Full digest (detection + survey + dedup + staleness + blueprint tracker state) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-dedup --with-blueprint` |
| With journal todos | add `--with-journal --journal-path <dir>` |
| Override detected project | add `--project <name>` |
| Coarse counts only (hook shape) | add `--summary` |
