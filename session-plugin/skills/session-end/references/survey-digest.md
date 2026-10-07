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

## Taskwarrior-sync preview scoping (Step 2/3)

When `PROJECT_CONFIDENCE=low`, name the scope actually used (`TASK_SCOPE`, plus `PROJECT_RESOLVED` when set) in the Step 3 preview and offer `--project <slug>` — a low-confidence zero is an unqueried project, never a clean queue. When `PROJECT_AMBIGUOUS` is set, render the preview as `0 here, N under <slug>` and offer `--project <slug>`; this fires **even at `PROJECT_CONFIDENCE=high`**, because a user-asserted `--project` and a repo declaration both deliberately keep `high` — so the `low`-confidence escape below does not cover it. When `PROJECT_PREFIX_SIBLINGS` is present, name it in the preview as `N under <slugs>` and confirm the slug **before filing anything**: those slugs are what a `task project:<slug>` CLI check would have swept in, so a slug verified that way can be the wrong one and the follow-ups land in a sibling nobody reads.

## Remediating `GH_READY=false`

It always ships with `GH_FAIL_REASON=`,
which says *why* GitHub went unqueried — the six causes want different
responses, so act on the reason rather than treating every `false` alike.
Never re-run for `auth`, `no-cli`, or `no-remote`. In every case the
GitHub-derived counts stay **unqueried**, not zero — so the taskwarrior-sync
redundancy test in Step 4 must not use them as evidence a follow-up is
untracked. See [../REFERENCE.md](../REFERENCE.md) for the per-reason table.
