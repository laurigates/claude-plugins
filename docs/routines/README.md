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

1. **The marker is the only anchor.** Step 3 branches on *"has the owner
   commented after your marker comment"*. Without the marker there is no anchor,
   so the branch is undecidable.
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

## Related

- `.claude/rules/loop-integrity.md` — the sibling failure class: a self-continuing
  loop that leaves no resumable state behind. An async decision queue is the same
  shape, with the issue thread as the state packet.
- `.claude/rules/offload-to-deterministic-substrate.md` — why the marker check is
  a script assertion rather than an instruction the run is asked to remember.
- `.claude/rules/regression-testing.md` — `scripts/check-routine-prompt.sh` is
  this document's guard.
