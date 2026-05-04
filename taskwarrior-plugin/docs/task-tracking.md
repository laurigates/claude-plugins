# Task Tracking Pattern

Conventions for using taskwarrior as a coordination layer for multi-agent and multi-WO blueprint work. These patterns apply across all `taskwarrior-plugin` skills.

## UDAs (User-Defined Attributes)

Declared in `~/.taskrc`. `task-add` installs them on first use (with confirmation).

| UDA | Type | Purpose |
|-----|------|---------|
| `bpid` | string | Blueprint ID link (WO-NNN, PRP-NNN, FR-NNN) |
| `bpdoc` | string | Repo-relative markdown path for the linked doc |
| `bpms` | string | Milestone tag |
| `ghid` | numeric | Linked GitHub issue number |
| `ghpr` | numeric | Linked GitHub PR number |

## Tags

| Tag | Meaning |
|-----|---------|
| `+wo` | Work order (from blueprint-plugin) |
| `+prp` | PRP implementation plan |
| `+fr` | Feature request |
| `+re` | Research task |
| `+gh` | Linked to a GitHub issue or PR |
| `+pr-ready` | Implementation done, open PR, waiting on merge |
| `+needs-review` | Ready for review |
| `+blocked-on-merge` | Waiting on another PR to merge |
| `+blocked` | Blocked on external factor |

## Lifecycle

### 1. Pre-allocate blueprint IDs

Before filing tasks, pre-allocate WO/PRP IDs in the manifest (e.g., WO-058/059/060). Task IDs assigned by taskwarrior at file-time may differ from blueprint IDs — the `bpid` UDA bridges them. Pre-allocating prevents ID drift and keeps the manifest and task queue in 1:1 correspondence.

### 2. File tasks with `depends:` for sequential ordering

For work orders that must land in sequence, set `depends:` on each downstream task pointing to its predecessor's taskwarrior ID (not its bpid — taskwarrior uses internal numeric IDs for dependency):

```bash
# File WO-058 first — no depends (it's first in the chain)
task add "WO-058: implement sprite_blit_frame" bpid:WO-058 +wo project:myrepo
# → taskwarrior assigns ID 51

# WO-059 waits for WO-058
task add "WO-059: add CLI subcommand" bpid:WO-059 +wo project:myrepo depends:51
# → taskwarrior assigns ID 52

# WO-060 waits for both
task add "WO-060: document format spec" bpid:WO-060 +wo project:myrepo depends:51,52
# → taskwarrior assigns ID 53
```

The `-BLOCKED` virtual attribute in `task-coordinate` and `task-status` automatically hides depends-blocked tasks from dispatch candidates — no manual filtering needed.

### 3. ★ KEY: `depends:` + `task done` auto-unblocks the chain

> **This is the single biggest productivity multiplier in multi-WO work.**

When you close a task with `task done`, taskwarrior immediately unblocks every task that listed it in `depends:` and prints a confirmation:

```
$ task 51 done
Completed task 51 'WO-058: implement sprite_blit_frame'.
Unblocked 52 'WO-059: add CLI subcommand'.
```

No manual intervention. After `task done` on WO-058:

- `task next` surfaces WO-059 as the top dispatch candidate
- `task-coordinate` (`task ... -BLOCKED export | jq`) shows WO-059 as ready
- A three-WO chain (058 → 059 → 060) manages itself: each `task done` fires the correct unblock automatically

The agent only needs to call `task done` on the completed task; the queue re-sorts instantly.

### 4. Annotate with the landing commit before closing

Always annotate before calling `done` — if close fails (e.g., remaining unresolved depends), the annotation is still captured:

```bash
task "$TASKID" annotate "landed: $COMMIT_SHORT $COMMIT_SUBJECT"
task "$TASKID" done
```

### 5. Report unblocked siblings after close

After `task done`, query which tasks were unblocked (parallel-safe):

```bash
task depends:"$TASKID" export | jq '.[] | {id, description, urgency}'
```

Include these in the close-out report so the orchestrator knows the next ready task immediately.

## Parallel-Safe Queries

All taskwarrior queries use `export | jq` — never bare `list`, `next`, or similar commands — because these exit 1 on an empty result and cancel sibling Bash calls in parallel batches.

| Use | Never use |
|-----|-----------|
| `task project:X status:pending export \| jq` | `task project:X status:pending list` |
| `task status:pending -BLOCKED export \| jq` | `task next` |
| `task depends:"$ID" export \| jq` | `task depends:"$ID" list` |
| `task bpid:WO-012 export \| jq` | `task bpid:WO-012 list` |

See `.claude/rules/parallel-safe-queries.md` for the full rule and rationale.

## Urgency and `task next`

The default urgency formula ranks tasks by project membership, tags, age, and dependencies. In most sessions no per-session priority tuning is needed — the parallel-safe equivalent (`task ... export | jq 'sort_by(-.urgency)'`) surfaces the right candidate.

When urgency rankings feel wrong, the common culprits are missing `project:` tags (task falls outside the scoped filter) or stale `+blocked` tags that should have been removed after the external blocker resolved.

## Related

- `/taskwarrior:task-add` — file tasks with UDA linkage and `depends:` ordering
- `/taskwarrior:task-done` — close + annotate + check unblocked siblings
- `/taskwarrior:task-coordinate` — surface next unblocked candidates for a wave
- `/taskwarrior:task-status` — full queue audit with drift detection
- `.claude/rules/parallel-safe-queries.md` — the `export | jq` idiom (zero parallel-batch errors)
- `blueprint-plugin:feature-tracking` — blueprint IDs that `bpid` links to
