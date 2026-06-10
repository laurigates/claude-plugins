# session-spinup — Reference

Supporting detail for [SKILL.md](SKILL.md). The shared configuration
schema lives in [session-wrap/REFERENCE.md](../session-wrap/REFERENCE.md).

## Project detection precedence

| Situation | Scope winner |
|---|---|
| cwd → unambiguous project, `+ACTIVE` is same project | cwd project |
| cwd → unambiguous project, `+ACTIVE` is a **different** project | cwd project; cross-project `+ACTIVE` shown only as a footnote |
| cwd → ambiguous (home dir, /tmp, no remote), `+ACTIVE` present | `+ACTIVE` task's project |
| cwd → ambiguous, no `+ACTIVE` | git remote repo name |

The cross-project `+ACTIVE` footnote shape:

```
note: +ACTIVE lock on project:claude-plugins from a previous session —
run session-wrap to close it if done.
```

If multiple projects are detectable (monorepo, multi-package), survey
each in its own section. If the cwd maps to no known project, list
options with `task _projects` and ask once.

## Journal todo extraction

Walk back from today (first existing note wins), extract unchecked
todos, stop at the configured stop-subheading or the next `## ` heading:

```sh
for offset in 0 1 2 3 4 5 6 7; do
    day=$(date -v-"${offset}"d +%Y-%m-%d)  # macOS; GNU: date -d "-${offset} day"
    note="<journal_path>/$day.md"
    [ -f "$note" ] || continue
    awk -v todo="<journal_todo_heading>" -v stop="<journal_todo_stop>" '
        $0 == todo { in_todo = 1; next }
        in_todo && stop != "" && index($0, stop) == 1 { in_todo = 0 }
        in_todo && /^## / { in_todo = 0 }
        in_todo && /^- \[ \]/ { print }
    ' "$note"
    break
done
```

Skip structural blocks (recurring reminders, dataview sections) — the
journal app's own machinery surfaces those; spinup fills in what the
terminal-only view can't see.

## Example briefing

```
Spin-up — project: fvh.cost-attribution (cwd: repos/ForumViriumHelsinki/infrastructure)

  taskwarrior (3 pending)
    +ACTIVE  #237 "Cluster fallback rules"
             annot: PR #1774 awaiting review, opened 2026-05-04
             [11 days stale — reviewer may have responded; check]
    pending  #240 "Confirm Hetzner db01-03 shutdown date with Aapo (#838)"
    pending  #243 "OpenCost re-evaluation date (ADR-0029 deferred)"

  journal 2026-05-12.md (yesterday)
    - [ ] Nudge production GKE Standard PR #1607 reviewers (stale 7d)

  git state (branch: feat/cluster-fallback-rules)
    PR #1774 OPEN — 11d since open, 3 unpushed commits ahead of origin

Next moves:
  • Resume #237 — check PR #1774 review state
  • Tackle yesterday's todo: nudge PR #1607 reviewers
  • Confirm Hetzner shutdown date (#240)
```

## Edge cases

- **No journal note in the last 7 days** — silently skip that source;
  still show taskwarrior + git state.
- **No tasks for the project** — say `nothing pending under
  project:<name>` explicitly rather than an empty-looking section.
- **Clean tree, no PRs** — one line: `git state: clean`.
- **All sources empty** — say so briefly, then step out of the way.
- **Plan mode / interactive UI** — present the briefing only; spinup
  never mutates anything.

## Rationale

Wrap writes; spinup reads. Without the read side, the queue and journal
become write-only: follow-ups get logged diligently and never seen
again. Spinup closes the loop — open threads visible in 30 seconds
before the user picks the next move.
