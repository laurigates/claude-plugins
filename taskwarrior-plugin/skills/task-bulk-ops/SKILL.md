---
name: task-bulk-ops
description: Batch taskwarrior operations without the ID-renumbering and stdin foot-guns. Use when closing/triaging/modifying many tasks in one pass, bulk `task done` loops, or scripting task queries.
args: "[filter]"
allowed-tools: Bash(task *), Bash(jq *), Bash(xargs *), Read, TodoWrite
argument-hint: optional filter, e.g. project:foo +bulk or a status/tag filter
created: 2026-07-05
modified: 2026-07-05
reviewed: 2026-07-05
---

# /taskwarrior:task-bulk-ops

Operate on **many** taskwarrior tasks in one pass — queue cleanup, a PR-merge
sweep, a project wrap-up — without hitting the four foot-guns that make the
obvious `for id in 1 2 3; do task $id done; done` silently do the wrong thing.
Every foot-gun fails **invisibly**: the loop reports success, the count looks
right, and the wrong tasks (or no tasks) were touched.

## When to Use This Skill

| Use this skill when... | Use a sibling skill instead when... |
|---|---|
| Closing / annotating / modifying **many** tasks in one pass | Closing **one** task with a landing commit — use `task-done` |
| Running a bulk `task done` loop over a queue | Retiring tasks whose GitHub issue/PR closed — use `task-reconcile` |
| Scripting a query over the queue (`export \| jq`, tag/project filters) | Reading a consolidated queue report — use `task-status` |
| Any state-changing op iterated over a **set** of tasks | Filing / claiming / releasing a single task — use `task-add` / `task-claim` / `task-release` |

## Context

- Task CLI available: !`task --version`
- Pending task count: !`task status:pending count`

## Parameters

Parse `$ARGUMENTS` as an **optional taskwarrior filter** that narrows the set to
operate on (e.g. `project:foo`, `+bulk status:pending`, `+gh`). When empty, ask
the user which set to target before mutating anything — never bulk-mutate an
unfiltered queue by default.

## Execution

Execute bulk operations under these four rules. They are not optional style
preferences — skipping any one silently corrupts the batch.

### Rule 1 — Address tasks by UUID, never numeric ID

Taskwarrior numeric IDs are a **display index over pending tasks**: the moment
any task completes, every higher ID shifts down by one. A numeric ID is stale
across *any* gap between reading and acting — a loop iteration, a later turn, a
new session, or an unrelated `task done` in another session.

Resolve the immutable UUID **at read time**, then use only UUIDs for every later
op:

```sh
# Loop over a set — capture UUIDs up front (they never shift)
UUIDS=$(task status:pending project:foo export | jq -r '.[] | .uuid')
for u in $UUIDS; do
  task "$u" done </dev/null            # (Rule 2: </dev/null)
done
```

```sh
# Acting later? Resolve the UUID the moment you know you'll act, not the number.
PROMOTE=$(task _get 169.uuid)          # 169 is valid RIGHT NOW, at read time
# ...any number of turns / unrelated closes later...
task "$PROMOTE" done </dev/null        # still the right task
```

If you only have a numeric ID and a gap has passed, **re-derive it** (re-run the
`export`/`list`, re-match on description) before acting — do not trust the
cached number. The same applies to `annotate` / `modify` / `delete`: any
state-changing op iterated over a set references UUIDs.

**The `+LATEST _get` trap.** `_get` is a **DOM accessor** taking an
`<id>.<attribute>` reference — given a *filter* (a tag like `+LATEST`) it
silently returns empty (exit 0) and captures nothing. To grab the UUID of the
task you just added, use the `+LATEST`-aware accessor or `export | jq`:

```sh
task +LATEST uuids                          # → UUID of the just-added task
task +LATEST export | jq -r '.[0].uuid'     # always exit-0, parallel-safe
```

> **Do not** reach for the `_get` DOM accessor with a tag filter to grab that
> UUID — `task +LATEST _get uuid` silently returns empty (exit 0). `_get` needs
> an `<id>.<attribute>` reference: `task _get <id>.uuid` works for a known
> numeric id, but the just-added task's UUID comes from `task +LATEST uuids`.

### Rule 2 — Redirect stdin and disable confirmation on every mutation

`task done` (and other mutating subcommands) **read from stdin**. Inside a shell
`for` loop the loop's input *is* stdin, so `task done` eats the remaining
iterations and the loop exits early after one or two — reporting "processed 15"
while closing 1. Two safe forms:

```sh
# Form A — redirect stdin per inner command
for u in $UUIDS; do
  task "$u" annotate "swept in cleanup" </dev/null
  task "$u" rc.confirmation=no done </dev/null
done
```

```sh
# Form B — xargs runs each command in its own subshell, no stdin link (preferred one-liner)
echo "$UUIDS" | xargs -I {} sh -c 'task rc.confirmation=no {} done'
```

Always pass **`rc.confirmation=no`** to batch `task done` — without it
taskwarrior may prompt "blocked by N other tasks, complete anyway?" and hang.

**`task config` has the same confirmation hazard — and it's worse.**
`task config <name> <value>` prompts to confirm by default; non-interactively
(a script, this Bash tool, a hook, chezmoi) the un-answered prompt makes it
**exit 0 without writing the value**. The failure is invisible. The sharpest
bite is **declaring UDAs**:

```sh
# WRONG — exits 0 but the UDA is NOT written; next `task add foo ghid:1417`
# appends the literal "ghid:1417" to the description instead of setting the UDA
task config uda.ghid.type numeric

# RIGHT — rc.confirmation=no makes the write happen; </dev/null guards stdin
task rc.confirmation=no config uda.ghid.type numeric </dev/null
task rc.confirmation=no config uda.ghid.label "GH Issue" </dev/null
```

Verify the write landed rather than trusting the exit code:

```sh
task _udas | grep -qx ghid && echo "declared" || echo "MISSING — config did not persist"
```

### Rule 3 — Find tasks with `export | jq`, and mind the filter caveats

Prefer `task <filter> export | jq` over `task <filter> list`: `export` emits
`[]` and exits 0 on an empty result (parallel-safe), while `list` exits 1 —
which silently cancels sibling calls in a parallel Bash batch.

- **Empty `project:` as the first filter errors.** `task project: status:pending list`
  fails with `Unable to find report`. Put the value-less filter later, or sidestep
  the CLI with jq:

  ```sh
  task status:pending export | jq -r '.[] | select(.project == null) | .uuid'
  ```

- **Escape `+` in `test()`** when matching a tag-style marker that lives in the
  **description text** (not a real tag):

  ```sh
  task status:pending export | jq -r '.[] | select(.description | test("\\+upstream_issue")) | .uuid'
  ```

- **Real taskwarrior tags** (set via `+tag` at creation, listed in `.tags`) filter
  through the CLI: `task +upstream_issue status:pending export`. Use underscores or
  camelCase in tag names, never hyphens — taskwarrior parses a hyphen mid-tag as an
  exclude filter, so the tag silently never lands.

### Rule 4 — Annotate before `done`, not after

Once a task is `completed` its `id` becomes 0 and `task <id>` no longer addresses
it (only the UUID does). Add annotations **before** closing so the annotate/done
workflow stays uniform and the annotation lands on the still-pending task that
`task <id> info` shows.

```sh
for u in $UUIDS; do
  task "$u" annotate "closed in PR-merge sweep" </dev/null   # annotate FIRST
  task "$u" rc.confirmation=no done </dev/null                # then close
done
```

### Report

After the pass, re-query and report what actually changed — never trust the loop
count. For a close sweep, confirm the pending count dropped by the expected
amount and no stray tasks were touched:

```sh
task status:pending count
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Snapshot a set as UUIDs | `task <filter> export \| jq -r '.[] \| .uuid'` |
| Bulk close (xargs, no stdin trap) | `echo "$UUIDS" \| xargs -I {} sh -c 'task rc.confirmation=no {} done'` |
| Bulk close (loop) | `for u in $UUIDS; do task "$u" rc.confirmation=no done </dev/null; done` |
| UUID of just-added task | `task +LATEST uuids` |
| UUID of a known numeric id | `task _get <id>.uuid` |
| Null-project tasks | `task status:pending export \| jq -r '.[] \| select(.project == null) \| .uuid'` |
| Description-text marker (escape `+`) | `task status:pending export \| jq -r '.[] \| select(.description \| test("\\+marker")) \| .uuid'` |
| Declare a UDA non-interactively | `task rc.confirmation=no config uda.<name>.type <type> </dev/null` |
| Verify a UDA landed | `task _udas \| grep -qx <name>` |

## Quick Reference

| Foot-gun | Symptom | Fix |
|----------|---------|-----|
| Numeric IDs renumber after each `done` | Closes the wrong tasks after the first | Address by **UUID**; resolve at read time |
| `+LATEST _get uuid` returns empty | Captures nothing (exit 0); next op no-ops/misfires | `task +LATEST uuids` |
| `task done` consumes loop stdin | "Processed 15", only 1 closed | `</dev/null` per command, or `xargs -I {}` |
| Missing `rc.confirmation=no` | Loop hangs on blocked-task prompts | Pass `rc.confirmation=no` to batch `done` |
| `task config` prompts, exits 0 without writing | UDA silently not declared; value lands in description text | `rc.confirmation=no ... </dev/null`; verify with `task _udas` |
| Empty `project:` first filter | `Unable to find report` | Reorder, or `export \| jq 'select(.project==null)'` |
| Annotating after `done` | `id` is 0; `task <id>` can't address it | Annotate **before** `done` |

## Related

- `/taskwarrior:task-done` — close one task with a landing commit (single-task path)
- `/taskwarrior:task-reconcile` — close tasks whose linked GitHub issue/PR closed (bulk, but GitHub-driven)
- `/taskwarrior:task-status` — read-only consolidated queue report
- `/taskwarrior:task-add` — file a single linked task (the `+LATEST uuids` capture pattern originates here)
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` (exit-0-on-empty) idiom
- `.claude/rules/task-id-stability.md` — central citation for numeric-ID-vs-UUID; this skill owns the full bulk/loop treatment
