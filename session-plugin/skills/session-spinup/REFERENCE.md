# session-spinup — Reference

Supporting detail for [SKILL.md](SKILL.md). The shared configuration
schema lives in [session-wrap/REFERENCE.md](../session-wrap/REFERENCE.md).
The detection, dedup, staleness, and journal-extraction logic itself
lives in `scripts/session-survey.sh` (covered by
`scripts/tests/test-session-survey.sh`) — this file documents how to
*interpret* its output, not how to reproduce it.

## Project detection precedence

The collector does the mechanical layer (`--project` override → git
repo-root basename → ambiguous, reported as `DETECTION=`). The skill
applies the rest of the precedence on top of the digest:

| Situation | Scope winner |
|---|---|
| cwd → unambiguous project, `+ACTIVE` is same project | cwd project |
| cwd → unambiguous project, `+ACTIVE` is a **different** project | cwd project; cross-project `+ACTIVE` shown only as a footnote (`STALE_ACTIVE_ELSEWHERE`) |
| cwd → ambiguous (`DETECTION=ambiguous`), `+ACTIVE` present | re-run with `--project <that task's project>` |
| cwd → ambiguous, no `+ACTIVE` | ask once, listing `task _projects` |

When the config naming map maps the cwd to a project name other than the
repo basename, pass it as `--project <name>`. If multiple projects are
detectable (monorepo, multi-package), run the collector per project.

## Task scoping is a guess, and says so

The basename is a *guess*, so the `TASKWARRIOR` section reports how the
count was scoped alongside the count itself — the same "not queried vs
genuine zero" distinction `GH_READY` draws for GitHub. Read
`TASK_SCOPE=` / `PROJECT_CONFIDENCE=` before asserting anything about the
queue:

| `TASK_SCOPE` | Meaning | `PROJECT_CONFIDENCE` | Briefing line |
|---|---|---|---|
| `project` | The detected (or `--project`) slug owns the count. Subprojects count too — `project:bluepad32` covers `bluepad32.own`, exactly as taskwarrior's own hierarchy match does | `high` | `nothing pending under project:<name>` is licensed |
| `remote-name` | The basename matched nothing; the git remote's repo name did (`PROJECT_RESOLVED=`) | `low` | Name the **resolved** slug, not the directory |
| `ancestor-name` | The basename matched nothing, but an **ancestor directory's** repo slug did — that slug is adopted and reported as `PROJECT_RESOLVED=` (`DETECTION=cwd-repo-basename-ancestor`) | `low` | Name the **adopted ancestor** slug, not the directory |
| `all-projects-fallback` | No slug matched while tasks exist elsewhere; `RECENT_TASK_*` rows list tasks touched within `--recent-days`, `TASKS_ALL_PROJECTS` is the denominator | `low` | `taskwarrior: project scope unresolved (N tasks across all projects)` — never a clean queue |
| `unknown` / `none` | `jq` or `task` unavailable, so no scoping was possible | `low` | `taskwarrior: not queried` |

`DETECTION=` names *how* the slug was chosen, independently of `TASK_SCOPE`:

| `DETECTION` | Source of the slug |
|---|---|
| `override` | The caller passed `--project` — user-asserted, so it keeps `high` confidence even at zero |
| `declared` | A `.claude/session.json` `.project` string found at the cwd or the repo root. Repo content, so it is validated as a plain single-line string; any other shape is rejected rather than flattened |
| `cwd-repo-basename` | The repo directory basename (the guess) |
| `cwd-repo-basename-ancestor` | An ancestor repo's slug, adopted because the basename matched nothing (`TASK_SCOPE=ancestor-name`) |
| `ambiguous` | No repo context at all |

### `PROJECT_AMBIGUOUS` — a zero that is not clean

When the detected slug owns **no** tasks but an ancestor slug does, and the
detected slug may not be adopted away (it was *asserted* via `--project` or a
`.claude/session.json` declaration), the collector emits:

| Key | Meaning |
|---|---|
| `PROJECT_AMBIGUOUS` | The ancestor slug that actually holds the work |
| `PROJECT_AMBIGUOUS_TASKS` | How many open tasks sit under it |

Both are **omitted entirely** when there is no ambiguity. Present this as
`0 here, N under <slug>` — never as a clean queue. This is the one case where a
`high`-confidence zero is still not licensed as "nothing pending".

### `PROJECT_PREFIX_SIBLINGS` — a count that is not the whole picture

taskwarrior's **CLI** `project:<p>` filter is a *prefix* match: `task
project:comfyui list` also returns every `comfyui-nodes` task. The collector's
own scoping is narrower (exact slug + `.`-separated children), so its counts are
right — but a slug "confirmed" at the CLI that way can still be the wrong one,
and its count then reads as a verified backlog while the real one sits under a
sibling:

| Key | Meaning |
|---|---|
| `OPEN_TASKS` | This scope: the slug **plus** its `.` subprojects |
| `PROJECT_EXACT_TASKS` | The slug **alone** — always emitted, always an integer |
| `PROJECT_PREFIX_SIBLINGS` | Slugs a CLI prefix filter would **also** have swept in (up to 8) |
| `PROJECT_PREFIX_SIBLING_TASKS` | How many open tasks they hold |

The last two are **omitted entirely** when the store has no such siblings. When
present, say `N under <slugs>` alongside the count and offer `--project <slug>`.
`PROJECT_CONFIDENCE` drops to `low` when the siblings hold strictly *more* tasks
than the scope — strict dominance, so a one-task `dotfiles-archive` beside
`dotfiles` is named without costing confidence. That downgrade applies to an
asserted slug too (`--project` / a declaration): assertion fixes the slug's
identity, not what the store holds. Nothing is adopted or rewritten.

A `RECENT_TASK_*` row is a **pointer**, not a task: it carries the UUID,
project, description, and age, but no `ghid`, no annotations, and no
`+ACTIVE` flag. Resolve the slug (re-run with `--project <name>`) before
acting on one.

The cross-project `+ACTIVE` footnote shape:

```
Stale +ACTIVE elsewhere: task cccc-3333 in project:claude-plugins is still +ACTIVE — release with /task-release if you've moved on.
```

## GitHub issue dedup (how the collector decides)

With `--with-dedup`, the collector emits a `GITHUB_DRIFT` section: open
issues assigned to you in the cwd repo, **minus** any already tracked in
taskwarrior. "Tracked" = the issue number appears as a task's `ghid` UDA,
or as a `#N` / `issues/N` token in any task description or annotation for
the project. What survives is the genuine drift set — filed on GitHub,
never mirrored locally. Show the task, not a duplicate issue line.

The section (and `PRS`) carries `GH_READY=`. `GH_READY=false` means the
collector never reached GitHub — `gh` is absent (always the case in
Claude Code on the web) or unauthenticated — so the zero counts are
*unqueried*, not empty. In that case the skill fetches via the GitHub
MCP tools and dedups in-skill (SKILL.md Step 1b), or states
`github: not queried (gh unavailable)` in the briefing. Only with
`GH_READY=true` does an empty drift set mean "everything assigned is
already tracked" — then the source earns no line.

## Journal todos (how the collector decides)

With `--with-journal --journal-path <dir>`, the collector walks back from
today up to 7 days (first existing `YYYY-MM-DD.md` note wins), extracts
unchecked `- [ ]` items under `journal_todo_heading`, and stops at
`journal_todo_stop` or the next `## ` heading. It skips structural blocks
(recurring reminders, dataview) by construction — the journal app surfaces
those; spinup fills in what the terminal-only view can't see.

## Example briefing

```
Spin-up — project: work.cost-attribution (cwd: repos/<org>/infrastructure)

  taskwarrior (3 pending)
    +ACTIVE  aaaa-1111 "Cluster fallback rules"
             annot: PR #1774 awaiting review, opened 2026-05-04
             [11 days stale — reviewer may have responded; check]
    pending  bbbb-2222 "Confirm Hetzner db01-03 shutdown date with Aapo (#838)"
    pending  cccc-3333 "OpenCost re-evaluation date (ADR-0029 deferred)"

  github issues (1 assigned, untracked)
    #851 "OpenCost pods OOMKilled on >2k namespaces" — filed 2d ago, no task

  journal 2026-05-12.md (yesterday)
    - [ ] Nudge production GKE Standard PR #1607 reviewers (stale 7d)

  git state (branch: feat/cluster-fallback-rules)
    PR #1774 OPEN — 11d since open, 3 unpushed commits ahead of origin

Next moves:
  • Resume aaaa-1111 — check PR #1774 review state
  • Triage assigned issue #851 (filed since last session, not yet tracked)
  • Tackle yesterday's todo: nudge PR #1607 reviewers
  • Confirm Hetzner shutdown date (bbbb-2222)

Stale +ACTIVE elsewhere: task dddd-5555 in bluepad32.own is still +ACTIVE — release with /task-release if you've moved on.
```

## Edge cases

These are handled by the collector (empty digest sections) — present them
gracefully rather than omitting:

- **No journal note in the last 7 days** — `JOURNAL` section empty; skip
  it, still show taskwarrior + git state.
- **No GitHub remote, or every assigned issue is already tracked** —
  `GITHUB_DRIFT` empty with `GH_READY=true`; the source earns a line
  only on a genuinely untracked assigned issue.
- **`GH_READY=false`** — GitHub was never queried; fall back to the
  GitHub MCP tools (SKILL.md Step 1b) or say `github: not queried (gh
  unavailable)` — never present the zeros as a clean state.
- **No tasks for the project** — `OPEN_TASKS=0` **with
  `PROJECT_CONFIDENCE=high`**; say `nothing pending under
  project:<name>` explicitly rather than an empty-looking section.
- **`PROJECT_CONFIDENCE=low`** — the slug was never confirmed, so
  `OPEN_TASKS=0` means *unscoped*, not *empty*. Never present the zero as
  a clean queue: follow the `TASK_SCOPE` table above (name the resolved
  slug, or surface the `RECENT_TASK_*` rows with `TASKS_ALL_PROJECTS` as
  the denominator and offer `--project <name>`). Same shape as
  `GH_READY=false`.
- **Clean tree, no PRs** — `DIRTY=false`, `PR_COUNT=0`; one line: `git
  state: clean`.
- **All sources empty** — say so briefly, then step out of the way.
- **Plan mode / interactive UI** — present the briefing only; spinup
  never mutates anything.

## Rationale

Wrap writes; spinup reads. Without the read side, the queue and journal
become write-only: follow-ups get logged diligently and never seen
again. Spinup closes the loop — open threads visible in 30 seconds
before the user picks the next move. Sharing one read-only collector with
wrap/end/hook keeps that survey deterministic, testable, and
single-sourced.

Surfacing open PRs and assigned issues here is load-bearing for the write
side: `session-plugin:session-wrap` declines to create a task whose only
content is "PR #N is open" **because** spinup replays the `PRS` and
`GITHUB_DRIFT` sections. Dropping either from this briefing would make
that redundancy rule wrong, so the two move together.
