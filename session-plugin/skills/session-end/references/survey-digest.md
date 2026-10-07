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
