# /taskwarrior:task-done - Reference

Batch-close guidance for the `task-done` skill.

## Bulk-close patterns

Closing many tasks in one pass has two silent foot-guns. The obvious shape — `for id in 1 2 3; do task $id done; done` — reports success while doing the wrong thing.

### Foot-gun 1: numeric IDs renumber after every `task done`

Numeric IDs are a display index over **pending** tasks. The moment one closes, every higher ID shifts down by one. A loop over numeric IDs closes the original first task, then keeps targeting wrong tasks as IDs slide underneath the iterator. No error surfaces.

**Fix: use UUIDs** (immutable). The same applies to any iterated state-changing op — `annotate`, `modify`, `delete`.

```sh
# WRONG — IDs shift mid-loop
for id in 35 36 37 38 39; do task "$id" done; done

# Correct — capture immutable UUIDs first
UUIDS=$(task status:pending project:myrepo export | jq -r '.[].uuid')
for u in $UUIDS; do task "$u" done </dev/null; done    # stdin redirect — see below
```

### Foot-gun 2: `task done` consumes loop stdin

`task done` reads from stdin (for confirmation prompts). In a shell `for` loop, the loop's input is *also* stdin — so `task done` eats subsequent iterations and the loop exits early, usually after one or two passes, with no error.

Symptom: a loop over 15 UUIDs reports "processed 15" but only 1 task closed.

```sh
# Fix A — redirect stdin per inner command
for u in $UUIDS; do
  task "$u" rc.confirmation=no done </dev/null
done

# Fix B — xargs (preferred; each invocation runs in its own subshell with no
# stdin link to the source loop)
echo "$UUIDS" | xargs -I {} sh -c 'task rc.confirmation=no {} done'
```

### Always pass `rc.confirmation=no` for batch closes

Without it, taskwarrior may prompt "this task is blocked by N other tasks, complete anyway? (yes/no)" per task, hanging the loop. `rc.confirmation=no` makes batch closes deterministic.

### Annotate before `done`, not after

Once `completed`, a task's `id` becomes 0 and `task <id>` no longer addresses it — only the UUID does. Annotate first to keep the UUID-or-ID workflow uniform.

### Finding tasks for the bulk close

Use `export | jq` (never `list` — it exits 1 on empty filters and cancels parallel siblings; see `.claude/rules/parallel-safe-queries.md`):

```sh
task status:pending project:myrepo +pr_ready export | jq -r '.[].uuid'

# Tasks with no project (CLI filter quirk — empty value as first filter
# errors; sidestep through jq)
task status:pending export | jq -r '.[] | select(.project == null) | .uuid'

# Substring matches on description (for markers that aren't real tags)
task status:pending export \
  | jq -r '.[] | select(.description | test("\\[triage\\]")) | .uuid'
```

### Canonical pattern

```sh
UUIDS=$(task status:pending project:myrepo +pr_ready export | jq -r '.[].uuid')
echo "$UUIDS" | xargs -I {} sh -c 'task rc.confirmation=no {} done'
```
