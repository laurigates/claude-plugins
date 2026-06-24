---
name: session-wrap
description: End-of-session capture to taskwarrior, optional journal, GitHub issues. Use when user says wrap up, session wrap, or done for now.
allowed-tools: Bash(bash *), Bash(task *), Bash(git *), Bash(gh *), Read, Write, Edit, AskUserQuestion, TodoWrite
created: 2026-05-12
modified: 2026-06-24
reviewed: 2026-06-24
---

# session-wrap

End-of-session capture for the things that **won't surface on their own**
next time the user sits down. The failure mode this prevents: follow-up
work gets agreed in conversation, the session ends, and a week later the
user can't remember what was left hanging.

## When to Use This Skill

| Use this skill when... | Use alternative when... |
|------------------------|------------------------|
| User says "wrap up", "session wrap", "done for now" | Full end-of-session pass incl. distill/feedback → `session-plugin:session-end` |
| Loose threads need capturing before the session ends | Capturing reusable *learnings* (rules/recipes) → `session-plugin:session-distill` |
| One task needs closing with audit trail mid-session | → `taskwarrior-plugin:task-done` |

## Configuration

Read per-user/per-project config before doing anything:

1. `.claude/session-plugin.local.md` in the project (wins)
2. `~/.claude/session-plugin.local.md` (user-global fallback)
3. Neither exists → taskwarrior + GitHub-issue destinations only; no journal

YAML frontmatter carries the journal settings (`journal`, `journal_path`,
`journal_template`, heading targets, `journal_scopes`); the markdown body
carries freeform scope-detection heuristics and the user's taskwarrior
project-naming map — read it and apply it as context. Full schema and a
worked example: [REFERENCE.md](REFERENCE.md).

## Destinations

| Destination | When | What goes there |
|---|---|---|
| **taskwarrior** | Every wrap | Mark completed tasks done; annotate in-flight tasks with PR / blocker / state; add tasks for surfaced threads |
| **Journal** (e.g. Obsidian daily note) | Only when configured AND the session matches `journal_scopes` | Narrative log entry; actionable todo items |
| **GitHub issues** | Only when cwd has a `github.com` origin AND a PR merged (or is about to) with post-merge follow-ups | One issue per follow-up, linked from the PR description |

Out-of-scope sessions get **only** the taskwarrior pass (plus GitHub
issues if applicable). Default to *skipping* the journal when scope is
unclear — better than spamming it. Ask once if genuinely ambiguous.

## The signal filter

This is the whole point. Log only what the user would miss tomorrow.

**LOG IT**: PR open and waiting (capture URL + gate) · task started but
blocked · manual follow-up outside Claude Code · deferred decision ·
untracked loose thread (bug noticed in passing, doc to write) ·
investigation finding worth not losing.

**DO NOT LOG**: work that finished cleanly (mark the task done, don't
narrate it) · anything already tracked that didn't change state · routine
ops · self-resolving items ("CI still running") · conversational context
· speculation ("might refactor X someday").

Litmus: *"If I don't write this down, will the user notice the gap
tomorrow?"* Yes → log. No → skip. 3-6 items per wrap is the right shape;
10+ means the filter is too loose. Worked examples: [REFERENCE.md](REFERENCE.md).

## Execution

Execute this wrap workflow:

### Step 1: Survey

Run the shared read-only collector — it does project detection, the
git/PR/taskwarrior survey, and recent commits in one parallel-safe pass,
emitting each task with its **stable UUID** so Steps 2/4 never operate on
a volatile numeric ID:

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits
```

Pass `--project <name>` when the config naming map maps the cwd to a
project other than the repo basename; when detection is ambiguous
(`DETECTION=ambiguous`) and unclear, list `task _projects` and ask once.
Then read the conversation itself — what was kicked off but not finished,
discussed but not done.

### Step 2: Categorise

| Category | Action |
|---|---|
| Done this session | `task <uuid> done` |
| In-flight, well-tracked | Annotate the existing task with the new state |
| In-flight, untracked | New taskwarrior task **or** journal todo (not both) |
| Loose thread, in journal scope | Journal log (narrative) or todo (action) |
| Loose thread, out of scope | Taskwarrior only, with `project:<name>` |
| Post-merge follow-up (GitHub repo) | One `gh issue create` per follow-up; link from the PR |
| Noise (per filter) | Skip silently |

Resolve numeric task IDs to UUIDs at read time (`task _get <id>.uuid`)
and operate on UUIDs — IDs shift when any task completes.

### Step 3: Preview and confirm

Show a compact preview of everything about to be written (per-destination
blocks; one block per project if several were touched).

Then confirm with **AskUserQuestion** — options like "Apply", "Apply
without journal", "Adjust first". Never end the turn on a freeform
"Apply? (y/n)" text question: ending the turn fires Stop hooks, which can
inject content and split the confirmation (this raced the old nudge hook
in production). AskUserQuestion keeps the turn open — no Stop event, no
race.

### Step 4: Apply

Taskwarrior: `task <uuid> done` / `task <uuid> annotate "..."` /
`task add project:<name> priority:M +<tag> '<description>'`. Annotate
**before** closing. Journal: append per the configured headings —
mechanics in [REFERENCE.md](REFERENCE.md). GitHub: one issue per
follow-up, then edit the PR description to link them.

### Step 5: Report

One paragraph: what was written where, plus the count of items skipped
as noise so the user can sanity-check the filter.

## Auto-surfacing

A Stop hook (`hooks/session-end-nudge.sh`) offers
`session-plugin:session-end` (which can route here) once per session on
genuine user wind-down phrasing. It stays silent while this skill is
running. Pre-silence for a session:
`touch ~/.cache/claude-session-end-nudge/<session_id>`.

## Agentic Optimizations

| Context | Command |
|---|---|
| Survey (detection + git + PRs + tasks-with-UUIDs + commits) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits` |
| Batch close by UUID | `task rc.confirmation:no <uuid> done` |
| Add a task | `task rc.confirmation:no add project:<name> +<tag> '<desc>'` |
| Known projects | `task _projects` |
