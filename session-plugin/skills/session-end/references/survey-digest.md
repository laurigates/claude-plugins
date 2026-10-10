# session-end — Survey Digest Keys

## `TASKWARRIOR` scoping keys

Note two scoping
keys in its `TASKWARRIOR` section: `TASK_SCOPE` (`project` /
`remote-name` / `ancestor-name` / `all-projects-fallback` / `unknown` /
`none`) names where `OPEN_TASKS` was actually counted, and
`PROJECT_CONFIDENCE` (`high` / `low`) says whether that slug can be
trusted — the detected project is a directory-basename guess and can be
wrong (chezmoi source dirs, worktrees, portfolio checkouts, renamed
clones). A third pair, `PROJECT_AMBIGUOUS` / `PROJECT_AMBIGUOUS_TASKS`,
appears only when the detected slug owns zero tasks while a named
ancestor slug owns some. A fourth, `PROJECT_PREFIX_SIBLINGS` /
`PROJECT_PREFIX_SIBLING_TASKS`, appears only when other slugs share the
detected slug's **prefix** — the split taskwarrior's own CLI filter
(`task project:<slug>`) hides, which is how a wrong slug gets "verified"
and follow-ups land in a near-empty sibling. `PROJECT_EXACT_TASKS` is
always present: the slug alone, without its `.` subprojects.

## `TASK_STORE_REACHABLE` — was the store read at all?

`TASK_AVAILABLE=true` means only that the `task` binary exists.
`TASK_STORE_REACHABLE` says whether `task export` actually read the store.
When it is `false`, every count in the section is **unqueried**, the same
signal `GH_READY=false` gives for GitHub: `TASK_SCOPE=unknown` and
`PROJECT_CONFIDENCE=low` even under `--project`. `TASK_FAIL_REASON` says why:

| `TASK_FAIL_REASON` | Cause | Remedy to name in the preview |
|---|---|---|
| `read-only` | The configured `data.location` sits on a read-only mount (a `.taskrc` synced from another host) | Re-run with `rc.data.location=<writable store>` or fix `.taskrc` |
| `store-unreachable` | The store path is missing or cannot be opened | Check `task _get rc.data.location` |
| `no-cli` | No `task` binary | Nothing to sync |
| `unknown` | Any other export failure | Quote `TASK_FAIL_DETAIL` |

`TASK_FAIL_DETAIL` is the first non-blank line of `task`'s stderr, bounded to
200 characters.
