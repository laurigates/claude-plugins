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

When the cwd has no GitHub remote or `gh` is unauthenticated, the section
is empty (the collector gates on `gh auth status`); skip it silently.

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
  `GITHUB_DRIFT` empty; the source earns a line only on a genuinely
  untracked assigned issue.
- **No tasks for the project** — `OPEN_TASKS=0`; say `nothing pending
  under project:<name>` explicitly rather than an empty-looking section.
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
