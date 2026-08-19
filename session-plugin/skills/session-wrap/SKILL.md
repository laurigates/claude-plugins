---
name: session-wrap
description: End-of-session capture to taskwarrior, optional journal, GitHub issues. Use when user says wrap up, session wrap, or done for now.
allowed-tools: Bash(bash *), Bash(task *), Bash(git *), Bash(gh *), Read, Write, Edit, AskUserQuestion, TodoWrite
created: 2026-05-12
modified: 2026-07-30
compatibility: claude-code
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
| **taskwarrior** | Every wrap | Mark completed tasks done; annotate in-flight tasks with PR / blocker / state; add tasks **only** for threads no open PR or issue already tracks (see "Don't duplicate an existing tracker") |
| **Journal** (e.g. Obsidian daily note) | Only when configured AND the session matches `journal_scopes` | Narrative log entry; actionable todo items |
| **GitHub issues** | Only when cwd has a `github.com` origin AND a PR merged (or is about to) with post-merge follow-ups | One issue per follow-up, linked from the PR description |
| **Upstream issue/PR candidate** | A bug/gap noticed in a *third-party* `github.com` repo, or a local fix that belongs upstream | Track for later (`+upstream` task) OR a **verified** issue / local-fix backport — never filed blind (Step 4 routes each candidate) |

Out-of-scope sessions get **only** the taskwarrior pass (plus GitHub
issues if applicable). Default to *skipping* the journal when scope is
unclear — better than spamming it. Ask once if genuinely ambiguous.

## The signal filter

This is the whole point. Log only what the user would miss tomorrow.

**LOG IT**: task started but blocked · manual follow-up outside Claude
Code · deferred decision · untracked loose thread (bug noticed in
passing, doc to write) · investigation finding worth not losing ·
upstream candidate (bug/docs-gap/feature-gap noticed in a dependency, or
a local fix that belongs upstream — route it in Step 4, never file blind).

**DO NOT LOG**: work that finished cleanly (mark the task done, don't
narrate it) · **an open PR or assigned issue as its own task** — the
PR/issue *is* the tracker (below) · anything already tracked that didn't
change state · routine ops · self-resolving items ("CI still running") ·
conversational context · speculation ("might refactor X someday") ·
anything already tracked upstream (an existing third-party issue/PR that
didn't change).

Litmus, both clauses: *"If I don't write this down, will the user notice
the gap tomorrow — **and** is there no open PR or issue already carrying
it?"* Both yes → log. Either no → skip. 3-6 items per wrap is the right
shape; 10+ means the filter is too loose. Worked examples:
[REFERENCE.md](REFERENCE.md).

### Don't duplicate an existing tracker

An open PR or assigned issue **is its own tracker**. The Step 1 digest's
`PRS` section carries every open PR (with `PR_n_STALE_DAYS`) and
`GITHUB_DRIFT` every assigned-but-untracked issue, and
`session-plugin:session-spinup` surfaces both next session — so a task
reading *"PR #N is open / needs merging"* only duplicates them, and
`taskwarrior-plugin:task-reconcile` closes it on merge anyway. A task
earns its existence when it carries something the PR or issue does **not**:

| Situation | Destination |
|---|---|
| PR open, awaiting review/merge, nothing else to say | **nothing** — the `PRS` section is the reminder |
| PR open **and** an existing task covers that work | annotate the existing task with the PR URL (this is what lets reconcile close it on merge) — never a second task |
| Assigned GitHub issue, no local task | **nothing** — `GITHUB_DRIFT` surfaces it at spinup |
| A manual step, deferred decision, or blocker the PR/issue body doesn't record | taskwarrior task — or, for a post-merge step, one GitHub issue linked from the PR |

Check a candidate's PR/issue number against `PRS` / `GITHUB_DRIFT` before
adding — a hit means annotate, not add. Same test for journal todos.

## Execution

Execute this wrap workflow:

### Step 1: Survey

Run the shared read-only collector — it does project detection, the
git/PR/taskwarrior survey, and recent commits in one parallel-safe pass,
emitting each task with its **stable UUID** so Steps 2/4 never operate on
a volatile numeric ID:

```sh
bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-dedup
```

Pass `--project <name>` when the config naming map maps the cwd to a
project other than the repo basename; when detection is ambiguous
(`DETECTION=ambiguous`) and unclear, list `task _projects` and ask once.
`--with-dedup` populates `GITHUB_DRIFT`, which the "Don't duplicate an
existing tracker" section below reads — without it the section is always
empty and the check silently passes against nothing. That section's
`GH_READY` matters too: `false` means `PRS`/`GITHUB_DRIFT` are present but
**unqueried**, not "nothing open" — never treat an empty section under
`GH_READY=false` as license to add a task that duplicates an untracked
PR/issue. The `GH_FAIL_REASON=` beside it says whether that is worth
fixing before you file: re-run once for `timeout` / `api-error` /
`unknown`; for `auth` / `no-cli` the dedup set is simply unavailable this
session, so keep the bar for adding a task high; for `no-remote` there is
no PR/issue to duplicate and the caveat does not apply. Then read the
conversation itself —
what was kicked off but not finished, discussed but not done.

### Step 2: Categorise

| Category | Action |
|---|---|
| Done this session | `task <uuid> done` |
| In-flight, well-tracked | Annotate the existing task with the new state |
| Already tracked by an open PR / assigned issue | No task — annotate an existing task with the URL if one covers the work; otherwise skip (spinup replays it) |
| In-flight, untracked | New taskwarrior task **or** journal todo (not both) |
| Loose thread, in journal scope | Journal log (narrative) or todo (action) |
| Loose thread, out of scope | Taskwarrior only, with `project:<name>` |
| Post-merge follow-up (GitHub repo) | One `gh issue create` per follow-up; link from the PR |
| Upstream candidate (third-party repo) | Per-candidate routing in Step 4 (track for later **or** verify-then-file) |
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

**Upstream candidates**: route each one with an **AskUserQuestion** —
two equal-weight options (no default lean):

- *Track for later* → `task add project:<name> +upstream '<desc — name
  the upstream repo + what/why>'`. No outward action; the `+upstream`
  tag is where "file this upstream" work surfaces later
  (`taskwarrior-plugin:task-add`).
- *File now* → hand off, in order:
  1. `workflow-orchestration-plugin:workflow-verify-before-filing` —
     verify the bug still exists at upstream HEAD **and** dedup against
     the tracker.
  2. `agent-patterns-plugin:cold-read-gate` — body legibility +
     internal-context-leak check before anything is published
     (`public-export-sanitization.md`).
  3. File the issue (`git-plugin:github-issue-writing`) or open the
     local-fix backport. When commenting on an **existing** issue, read
     the full thread first (`git-plugin:git-issue-scoping`).

  **Graceful degradation**: if `workflow-orchestration-plugin` is not
  installed (mirrors the `feedback-plugin` / `blueprint-plugin`
  cross-plugin fallback in `session-end`), fall back to
  `git-plugin:github-issue-writing` + an explicit manual upstream-HEAD
  verification, or route to *Track for later* instead — **never file
  unverified**.

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
| Survey (detection + git + PRs + tasks-with-UUIDs + commits + GitHub-drift dedup) | `bash "${CLAUDE_SKILL_DIR}/../../scripts/session-survey.sh" --with-commits --with-dedup` |
| Batch close by UUID | `task rc.confirmation:no <uuid> done` |
| Add a task | `task rc.confirmation:no add project:<name> +<tag> '<desc>'` |
| Known projects | `task _projects` |
