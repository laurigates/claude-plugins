# task-reconcile reference

Detailed behaviour of the GitHub issue/PR ↔ task reconciliation, the two close
paths, and the `task import` constraints that shape the design.

## Why reconciliation is a skill, not a hook

`task import` does **not** fire taskwarrior native (`~/.task/hooks/`) hooks, and
reconciliation needs `gh` calls to learn upstream state — neither fits an
`on-modify` hook. So the close logic lives in a skill-invoked script that the
agent runs on demand (or that `task-status`/session skills suggest when drift is
detected). The optional native hooks installed by
`/taskwarrior:install-native-hooks` are for *enforcement on add/modify*, a
separate concern.

## Ref extraction — what counts as "linked"

A task is reconciled if it references a GitHub issue/PR by **either** a UDA or
its text. The `refs` jq function in `reconcile.sh` extracts a deduped list of
`{repo, kind, num}` per task, in this precedence:

| Source | Form | Repo | Kind |
|--------|------|------|------|
| UDA | `ghpr` | CWD default | `pr` |
| UDA | `ghid` | CWD default | `issue` |
| Text | `github.com/<owner>/<repo>/(issues\|pull)/<N>` | `<owner>/<repo>` | known (`pr`/`issue`) |
| Text | `<owner>/<repo>#<N>` | `<owner>/<repo>` | unknown → resolved |
| Text | `#<N>` (not preceded by a word char or `/`) | CWD default | unknown → resolved |

`description` + every annotation `description` are scanned. Matched spans are
removed before the next (looser) pattern runs, so `owner/repo#N` is not also
counted as a bare `#N`. **Shorthand without an `owner/` slash — `prompt-editor#42`
— deliberately does NOT match** (the negative-lookbehind on bare `#N` rejects a
`#` preceded by a word char), so such a task stays `live`/kept rather than
resolving `#42` against the wrong repo. This is a safe false-negative: the skill
errs toward *keeping* an ambiguous task, never toward a wrong-repo close.

**Cross-repo:** a ref that names `<owner>/<repo>` is resolved with `gh … -R
owner/repo`; a bare `#N` and the UDAs use the CWD-resolved repo. So a task in
project A whose description says `owner/B#N` is checked against repo B.

**Ambiguous repo under `--all` (issue #3387):** the CWD repo is only the right
default for tasks of the CWD's own project. Under `--all`, a ref with no repo
(bare `#N`, `ghid`, `ghpr`) resolves only when the task's project equals the CWD
project (`scripts/resolve-project.sh`: basename of the git toplevel) or is a
dotted child of it (`<cwd-project>.*`; `alphabet` is not a child of `alpha`).
For every other task the ref is `AMBIGUOUS`: no `gh` call is made, the task is
`live` with `upstream=AMBIGUOUS`, and it is counted in `AMBIGUOUS_REPO`, so it
can never be closed. Refs that name their repo resolve in any project under the
**Cross-repo** rule, and single-project runs are unchanged. Run from `~/repos`, an `OLMap` task citing
`#65` had resolved against `laurigates/repos-claude-config` PR 65 (`MERGED`)
while `ForumViriumHelsinki/OLMap` PR 65 was `OPEN`; the scheduled bounded apply
(`--all --apply --only-verdicts=pr-merged,issue-closed`) would have closed it.

**Kind resolution:** a text ref of unknown kind (`#N`, `owner/repo#N`) is tried
as a PR first (a merged PR is the common "done" signal); if `gh pr view` returns
nothing (the number is an issue) it falls back to `gh issue view`.

## Classification authority

Each ref resolves to a per-ref state; the PR signal wins over issue for the same
number. Single-ref verdicts:

| Ref | Upstream state | Verdict |
|----------|----------------|---------|
| PR | `MERGED` | `pr-merged` (stale — work landed) |
| PR | `CLOSED` | `pr-closed` (stale — abandoned PR) |
| PR | `OPEN` | `live` (keep — work lives in the PR, even if a linked issue closed) |
| issue | `CLOSED` | `issue-closed` (stale) |
| issue | `OPEN` | `live` |
| any | `UNKNOWN` (fetch failed) | `live` — never close on uncertainty |

Upstream state is read with `gh issue view N --json state` / `gh pr view N
--json state` (with `-R owner/repo` for a cross-repo ref), cached per
`repo|kind|num` so a queue with many tasks pointing at the same issue/PR makes
one call each. PR state uses the `state` enum (`MERGED`/`OPEN`/`CLOSED`) per
`.claude/rules/gh-json-fields.md` — never a `merged` field.

### Multi-ref aggregation

A task referencing several items (e.g. `Monitor #142, #143, #144`) is stale
**only when every ref resolves done** — this prevents closing a monitor task
when only some of the items have closed:

| Any ref is… | Task verdict |
|-------------|--------------|
| open (PR/issue `OPEN`) | `live` (keep) |
| `AMBIGUOUS` (`--all`, no repo, task outside the CWD project) | `live` (keep, counts toward `AMBIGUOUS_REPO`) |
| `UNKNOWN` (unreadable) | `live` (keep, counts toward `UNKNOWN_UPSTREAM`) |
| all stale, some `pr-closed` | `pr-closed` (ambiguous — kept out of the bounded `--only-verdicts` auto-apply set) |
| all stale, some `pr-merged` (rest `issue-closed`) | `pr-merged` |
| all stale, all `issue-closed` | `issue-closed` |

The `pr-closed`-dominates rule keeps an ambiguous abandoned-vs-superseded PR from
being auto-closed in the bounded scheduled apply even when it sits alongside
merged/closed siblings.

### Link strength: text refs report, UDAs close

The verdicts in § Classification authority apply as written only to a task with a `ghid`/`ghpr` UDA. A
task linked **only** by text refs whose items are all done gets verdict
`review` instead (issue #3126):

| Link source | All refs done | Close method |
|-------------|---------------|--------------|
| `ghid`/`ghpr` UDA | `pr-merged` / `pr-closed` / `issue-closed` | bulk / done (subject to `--only-verdicts`) |
| text refs only | `review` | keep — never closed |

Tasks routinely cite a merged PR as background ("promoted in PR #2479 — add the
section to REFERENCE.md"). In the dry run behind #3126, 7 of 8 text-ref
`pr-merged` verdicts were open work, and the one correct verdict came from a
`ghpr` UDA. `review` is counted in `REVIEW_COUNT`, not `STALE_COUNT`, so the
SessionStart drift line and the scheduled notifier count UDA-backed verdicts
only. `verdict_allowed` rejects `review` even when `--only-verdicts` lists it.
Text refs still resolve (the `upstream=` field shows their state), so the
`review` list is the input for deciding later whether a narrower text rule is
worth adding.

## The two close paths — and why

| Path | Used for | Mechanism | Trade-off |
|------|----------|-----------|-----------|
| **bulk** | leaf stale tasks (no dependents) | one `task export \| jq \| task import` round-trip: set `status=completed`, `end`, append `reconcile:` annotation | fast; **skips** dependency auto-unblock and native hooks |
| **done** | stale tasks that `+BLOCKING` others | per-task `task <uuid> annotate` then `task rc.confirmation=no <uuid> done </dev/null` | fires taskwarrior's auto-unblock so dependents become ready |

The split exists because `task import` writes the completed state directly and
**does not run the dependency-unblock pass** that `task done` performs. A stale
task that blocks others must therefore close via `task done`, or its dependents
would stay `+BLOCKED` forever. Leaf trackers (the common case — an `issue #N`
mirror with no dependents) take the fast bulk path.

## `task import` round-trip gotchas

The bulk path round-trips JSON through `task import`. To keep it safe:

- **Preserve `uuid` and `entry`.** Import matches on `uuid` to *update* the
  existing task rather than create a duplicate; `entry` is the creation
  timestamp. The jq transform only sets `status`/`end`/`annotations` and leaves
  everything else (including `uuid`/`entry`) untouched.
- **Do not write derived fields back.** `id` and `urgency` in the export are
  display-derived; importing them is harmless but pointless — the transform
  leaves them as-is and taskwarrior recomputes.
- **Dates use taskwarrior basic ISO** (`YYYYMMDDTHHMMSSZ`), computed once via
  `date -u +%Y%m%dT%H%M%SZ` and applied to both `end` and the annotation
  `entry`.
- **Annotation before/with close.** The bulk transform appends the `reconcile:`
  annotation in the same import that sets `completed`, so the reason is captured
  atomically. The per-task path annotates first, then closes — if `done` fails
  (unresolved deps), the annotation still landed.

## Stale numeric IDs

The script addresses every mutation by **UUID**, never numeric ID. Numeric IDs
are a display index over pending tasks and shift whenever any task completes —
exactly what happens mid-reconciliation as the stale set closes. See
`.claude/rules/task-id-stability.md`.

## Parallel-safety

Every read uses `task ... export | jq`, which returns `[]` and exits 0 on an
empty result — so the script is safe to invoke inside a parallel Bash batch
(`.claude/rules/parallel-safe-queries.md`). The script's own exit code is 0 on
any clean run (dry-run or apply); failures surface in `STATUS=`/`ISSUE_COUNT=`,
not the exit code. The exceptions are startup failures that must be loud:
exit 1 when the `task` binary is missing, and exit 2 on an **unknown
argument**. The argument parser rejects anything it does not recognise rather
than silently ignoring it — a swallowed `--only-verdicts` (caller/script
version skew, or a typo) would otherwise turn a bounded apply into an
unbounded one that closes the `pr-closed` tasks the flag exists to protect
(issue #2057).

## What it never does

- Never closes a task whose upstream state is `UNKNOWN` (fetch failed).
- Never closes a `live` task.
- Never deletes tasks — only transitions stale ones to `completed`.
- Never mutates GitHub — it reads issue/PR state only. Closing the GitHub side
  is `task-done`'s job (`gh issue close` / `gh pr comment`).
