# Routine prompts

Scheduled Routines that operate on this repository, checked in so their prompts
are reviewable and diffable.

| File | Routine | Schedule |
|------|---------|----------|
| [`resolve-claude-plugins-issues.md`](resolve-claude-plugins-issues.md) | `trig_01Q4ScmAWZfGkCaTd43eLwg3` — "Resolve claude-plugins repo issues" | daily `0 6 * * *` (UTC) |

## Why these live in the repo

A Routine's prompt is stored server-side. It has no version history, no diff, no
review, and no CI. Between 2026-08-11 and 2026-09-03 the issue-resolving Routine
stopped emitting the `<!-- routine:needs-decision v1 -->` marker its own prompt
declares mandatory, and nothing surfaced it — because the failure mode is
*silence* (see below). Checking the prompt in gives the guard a place to stand:
`scripts/check-routine-prompt.sh` asserts the invariants that broke.

These files are **source of truth for review, not for execution.** The Routines
above were created via the HTTP API, so agents cannot update them
(`update_trigger` returns *"Agents can only update routines they created"*).
Changing a prompt is a two-step edit: land it here, then paste it into the
Routine.

## The failure this documents

The Routine posts as the repo owner, so every comment in an issue thread — its
own questions and the owner's replies — carries the same `user.login` and
`author_association: OWNER`. Authorship cannot distinguish them. Three
consequences, all observed:

1. **The marker is the only anchor, and it does not survive the trip.** Step 3
   branches on *"has the owner commented after your marker comment"*. Without the
   marker there is no anchor, so the branch is undecidable — and the marker is
   an HTML comment, which has been observed reaching GitHub three different ways
   depending on the posting path: preserved (#2119, 2026-08-14), entity-escaped
   so it renders as visible text and fails a literal match, and **silently
   stripped**, leaving an orphan blank first line (#2141 2026-08-11, #2569
   2026-09-03, and a comment posted from this session with a marker that was
   verifiably sent). No error is raised on any of these paths. A signal that
   survives only some of the paths that post it cannot anchor a state machine,
   so v2 makes the marker visible markdown and the footer authoritative.
2. **The undecidable case defaults to silence.** The fall-through branch is
   *"do nothing at all. Silence here is the feature."* A dropped reply is
   therefore indistinguishable from correct operation. #2141 sat answered and
   unread for a month on exactly this path.
3. **A false state record compounds it.** The phrase `Proceeding on:` marks a
   reply as consumed. #2119 carries a `Proceeding on:` comment that explicitly
   did *not* proceed and did *not* clear the label, so a later run re-deriving
   state from the thread reads an unconsumed reply as handled.

The corrected prompt adds an author-independent identity signal (a footer on
every comment, not just questions), verifies both signals after posting rather
than checking comment length, adds an explicit no-anchor recovery branch instead
of falling through to silence, requires the run summary to account for every
labelled issue, and reserves `Proceeding on:` for actual unblocking.

## Group-level work (2026-11)

On 2026-11-01 backlog triage grouped related issues under `epic` tracking
issues (as native sub-issues). The prompt originally dispatched one subagent and
one PR per issue, so siblings whose implementations interact were built
independently and reconciled afterwards. The prompt now treats an epic's (or
milestone's) group as the unit of work, per `.claude/rules/issue-grouping.md`:

| Rule | Prompt step |
|------|-------------|
| A group's actionable members go to one subagent and land as one PR, one commit per issue | 4, 5, 6 |
| Blocked siblings (decision label, `needs-human`, open `blocked_by`) stay out and are named; the whole group is deferred when the actionable half would be redone after the decision | 4.1 |
| Cap: 3 work units and 6 issues per run; a group counts as one unit, each member toward the 6 | 4 |
| Ungrouped issues (no epic, no milestone, not exempt) come from `scripts/check-issue-grouping.sh` and are reported under `UNGROUPED`, not worked, unless the fix touches a single file | 1.5, 4.2, 7 |
| The exempt list (recurring machine-filed and feedback issues) lives only in `scripts/issue-grouping-exempt.txt` | 1.5 |

The live Routine runs whatever was last pasted into it, so these steps take
effect only after the owner pastes the updated prompt.

## Working alongside the Routine

Two constraints for any session that touches issues the Routine tracks
(observed in the 2026-11-01 triage):

- **Do not create a higher-precedence decision label.** Step 3 reuses the first
  existing label from `needs-decision`, `needs-input`, `question`, `blocked`.
  This repo has only `question`, so creating `needs-decision` would move the
  Routine onto an empty label and orphan every open `question` thread.
- **Record a relayed answer as a decision, not as a reply.** An answer Lauri
  gives in another session and an agent posts carries the
  `_Generated by [Claude Code]…_` footer, so the Routine reads it as its own
  comment and becomes the anchor, not an owner reply (branch (b): silence).
  Post a `## Decision recorded (Lauri, <date>)` comment, remove the decision
  label, and add `agent-ready` in the same pass. The issue then leaves the
  needs-decision state machine, and Step 2 classifies it from the recorded
  decision.

## Related

- `.claude/rules/issue-grouping.md` — why related issues are grouped, and how
  new issues join a group.

- `.claude/rules/loop-integrity.md` — the sibling failure class: a self-continuing
  loop that leaves no resumable state behind. An async decision queue is the same
  shape, with the issue thread as the state packet.
- `.claude/rules/offload-to-deterministic-substrate.md` — why the marker check is
  a script assertion rather than an instruction the run is asked to remember.
- `.claude/rules/regression-testing.md` — `scripts/check-routine-prompt.sh` is
  this document's guard.
