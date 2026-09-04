# Session Plugin

Session bookends for Claude Code: a read-only **spinup** briefing at
session start, a **wrap** capture pass at session end, a **distill** pass
for durable learnings, and a **session-end orchestrator** that previews
which passes qualify and runs only what the user confirms.

Design background: [`docs/archive/session-plugin-workflow.md`](../docs/archive/session-plugin-workflow.md)
(two-speed feedback architecture, decisions D1–D5) and the flow diagram
[`docs/diagrams/two-speed-feedback.d2`](../docs/diagrams/two-speed-feedback.d2).

## Skills

| Skill | Purpose |
|---|---|
| `session-spinup` | Read-only session-start briefing: open taskwarrior tasks, git state (uncommitted / unpushed / open PRs), optional journal todos |
| `session-wrap` | End-of-session capture of loose threads to taskwarrior, an optional journal, GitHub follow-up issues, and upstream issue/PR candidates (track-for-later or verify-then-file, never blind). Skips anything an open PR/issue already tracks — those resurface via `session-spinup` |
| `session-end` | Orchestrator: one survey, preview which of wrap / distill / feedback / taskwarrior-sync / blueprint tracker-sync qualify, **single confirmation**, then sequence them |
| `session-distill` | Distill session insights into `.claude/rules/`, skill improvements, justfile recipes, and process/methodology captures (project-local `.claude/skills/` or `scripts/`+recipe); driven by the read-only `distill-survey.sh` collector |

`session-end` also references `feedback-plugin:feedback-session` (the
plugin-feedback pass) and `blueprint-plugin:blueprint-feature-tracker-sync`
(the blueprint tracker-sync pass, offered when the session left closed
WO-linked tasks undrained from the feature tracker) by name only; if the
referenced plugin isn't installed the pass is skipped.

## Configuration (`session-plugin.local.md`)

The skills are journal-agnostic by default (taskwarrior + GitHub only).
To add a journal destination/source (e.g. Obsidian daily notes), create:

- `.claude/session-plugin.local.md` in a project (wins), or
- `~/.claude/session-plugin.local.md` user-globally

YAML frontmatter carries the journal settings (`journal`,
`journal_path`, heading targets, `journal_scopes`); the markdown body
carries scope-detection heuristics and your taskwarrior project-naming
map. Full schema and a worked example:
[`skills/session-wrap/REFERENCE.md`](skills/session-wrap/REFERENCE.md).

Add `.claude/*.local.md` to the project's `.gitignore` — the file is
user-local by convention (`agent-patterns-plugin:plugin-settings`).

## Hooks

| Hook | Event | Behavior |
|---|---|---|
| `session-spinup-nudge.sh` | SessionStart (startup/resume) | Injects a one-time context note when open threads exist (dirty tree, unpushed commits, open tasks for the cwd project, assigned GitHub issues). Names the scope the task count actually came from, so a remote-resolved or all-projects-fallback count is not passed off as `project:<basename>`. Informational only — never blocks |
| `session-end-nudge.sh` | Stop | Offers `session-plugin:session-end` at most once per session when the user's own messages carry a wind-down phrase. Collapses the former separate wrap + distill nudges (design D4). When taskwarrior is on PATH and the project has open/active tasks, the offer also mentions a taskwarrior state-sync pass |

The Stop nudge is deliberately conservative:

- counts only **genuine** user turns — tool results and slash-command
  expansions are excluded from both the turn floor and the wind-down
  phrase scan (a previous nudge matched a skill's own injected markdown
  and fired mid-skill)
- stays **silent when session-wrap / session-end / session-distill is
  already in the transcript** — the skill owns the flow; the hook never
  races a pending confirmation
- requires something to capture into (taskwarrior on PATH, or a
  `.claude/rules/` / justfile surface)
- the taskwarrior open-task query uses `export` (not `list`) so it exits 0
  on empty and is safe in parallel batches (see `.claude/rules/parallel-safe-queries.md`)

Pre-silence either nudge for a session:

```
touch ~/.cache/claude-session-end-nudge/<session_id>
touch ~/.cache/claude-session-spinup-nudge/<session_id>
```

Regression tests: `hooks/test-session-end-nudge.sh`,
`hooks/test-session-spinup-nudge.sh` (run directly with bash).

## Shared collector (`scripts/session-survey.sh`)

The read-only survey that `session-spinup`, `session-wrap`, `session-end`,
and the spinup nudge hook all need — project detection, git state, branch
PRs, taskwarrior tasks (each with its **stable UUID**), GitHub-issue dedup
against taskwarrior, staleness, journal-todo extraction, and recent
commits — lives in one place instead of being re-implemented inline four
times. It emits `structured-script-output.md`-style `=== SECTION ===` /
`KEY=VALUE` blocks so the skills consume a compact digest rather than
re-parsing raw JSON, and every section is exit-0 on empty (parallel-safe).

The script is **read-only by contract**: detection and collection only.
All writes and judgment stay in the invoking skill.

| Flag | Adds |
|---|---|
| (none) | PROJECT, GIT, TASKWARRIOR, STALE_ACTIVE_ELSEWHERE, PRS |
| `--with-dedup` | GITHUB_DRIFT (assigned-open issues minus those tracked in taskwarrior) |
| `--with-journal --journal-path <dir>` | JOURNAL (unchecked todos from the most recent dated note) |
| `--with-commits` | COMMITS (recent commit subjects) |
| `--with-blueprint` | BLUEPRINT (manifest/tracker presence, ready/blocked/in-flight feature counts, closed-but-undrained WO-linked tasks). Degrades to `MANIFEST=false` + zeroed counts when the repo isn't blueprint-enabled |
| `--summary` | coarse counts only (used by the nudge hook) |
| `--project <name>` | override the detected project (also makes its zero *confident* — see below) |
| `--recent-days <n>` | recency window for the all-projects task fallback (default 2) |

| Env seam | Purpose |
|---|---|
| `SESSION_SURVEY_GH_TIMEOUT` | per-`gh`-call budget in seconds (default 8) |
| `SESSION_SURVEY_RECENT_DAYS` | default for `--recent-days` |
| `SESSION_SURVEY_TASK_BIN` / `_GIT_BIN` / `_GH_BIN` | binary overrides (tests) |

Both numeric knobs are validated, and their effective values are echoed
into the digest (`RECENT_DAYS=` in `TASKWARRIOR`, `GH_BUDGET=` in
`PRS`). A non-numeric value falls back to the documented default and is
reported (`RECENT_DAYS_INVALID=`, `GH_BUDGET_INVALID=`) rather than
silently degrading — unvalidated, they
produced exactly the silent zeros the rest of this collector exists to
avoid (`RECENT_TASK_COUNT=0` for every task; `GH_READY=false` for every
call, because the watchdog's `sleep` failed instantly and killed them).

### Degrade, don't die

Every no-network section (PROJECT, GIT, TASKWARRIOR, JOURNAL, COMMITS,
BLUEPRINT, STALE_ACTIVE_ELSEWHERE) is emitted **before** the
GitHub-backed ones, and the `gh` calls run **in parallel**, each under its
own watchdog bounded by `SESSION_SURVEY_GH_TIMEOUT`. A hard kill at the
SessionStart hook's timeout therefore truncates the digest rather than
producing nothing at all. `--summary` — the hook's own mode — obeys the
same ordering: its local keys are written before the GitHub wait, so a
kill mid-`gh` truncates that block too. There is deliberately no
`gh auth status` probe — that was a network round-trip spent deciding
whether to make network round-trips. `GH_READY` is derived from whether a
real query returned 0, so an unauthenticated, absent, or timed-out `gh`
still reads as "not queried" (`GH_READY=false`, plus `GH_TIMEOUT=true` as
a diagnostic) and never as a clean zero.

A bare `GH_READY=false` is undiagnosable, though, so it always ships with
`GH_FAIL_REASON=` — `timeout` (raise the budget), `auth` (`gh auth
login`; re-running is futile), `no-cli` (no `gh` on PATH — fall back to
the GitHub MCP tools), `no-remote` (nothing to query), `api-error` (a 5xx
or network failure — re-run), or `unknown`. The last two also carry
`GH_FAIL_DETAIL=`, the first line of `gh`'s stderr, sanitised to one
`KEY=VALUE` row. The budget is 8s rather than 4s because a
`pr list --author @me` resolves the `@me` handle *before* it can run the
query — 4s covered two round-trips only on a fast link, and every overrun
silently disabled the dedup guard. The calls are backgrounded, so the
higher ceiling costs wall-clock time only when something is actually
slow. Each mode makes exactly the
calls whose output it prints: the summary prints `GH_READY` and
`ASSIGNED_ISSUES`, so it issues the assigned-issue query even without
`--with-dedup`.

### Git state reports both directions

The `GIT` section carries `IN_GIT`, `BRANCH`, `DIRTY`, `UNPUSHED`, and
`BEHIND` — the last two are the two directions a checkout can diverge:

| Key | Meaning | On no upstream / detached HEAD |
|---|---|---|
| `UNPUSHED` | Commits HEAD holds that upstream does not (`@{u}..HEAD`) | `0` |
| `BEHIND` | Commits upstream holds that HEAD does not (`HEAD..@{upstream}`) | `0` |

`BEHIND` reads `@{upstream}` rather than a hardcoded `origin/main`, so it
resolves per branch and degrades to `0` — silently, exit 0 — wherever there
is no upstream to compare against. That means `BEHIND=0` is *never* evidence
the tree is current, only that nothing said otherwise.

`BEHIND` ≥ 1 is a **caveat, not an error**: `STATUS` stays `OK`, exactly as
it does for `PROJECT_CONFIDENCE=low`. It says everything read from this tree
was read against a stale basis — the failure it exists to prevent is a
confident, specific finding about a bug that was already fixed upstream, with
nothing in the digest hinting the checkout had fallen behind.

#### Whose repository is this?

`GIT` and `PRS` read the repo at `--project-dir` — `GIT` directly, `PRS`
because every `gh` call is launched with that cwd, so `gh` resolves the repo
from the same checkout's remote. When the cwd lands inside a **nested**
checkout (an untracked upstream fork living inside the workspace repo), both
sections describe a different repository's branch, dirt and PRs. The same
vocabulary as the taskwarrior ladder says so:

| `GIT_SCOPE` | Meaning | `GIT_CONFIDENCE` |
|---|---|---|
| `repo` | The checkout is the outermost repo here | `high` |
| `nested-repo` | A **different** repo contains this one; `GIT_NESTED_IN=` names its directory | `low` |
| `project-ancestor` | No outer repo, but the project slug resolved to an ancestor workspace (`PROJECT_RESOLVED=` / `PROJECT_AMBIGUOUS=`), so the slug and this checkout name different things | `low` |
| `none` | Not in a git repo at all | `low` |

A containment the outer repo **ignores via a `.gitignore`** (a portfolio
root's `/*/*`) or **tracks** (a submodule, a committed subtree) is a declared
layout, not a misdetection, and is never flagged — otherwise every repo in a
portfolio checkout would read `low` and the caveat would be noise. The ignore
*source* decides: `.gitignore` is repo content, while `.git/info/exclude` and
a global `core.excludesFile` are private to one checkout, and the usual reason
a line lands there is to stop an accidental nested clone showing up in `git
status` — the very state this signal reports. A linked worktree is not nested
either: it shares its main checkout's git common dir.

`PRS_SCOPE` / `PRS_CONFIDENCE` mirror the git verdict, plus one rung of their
own: `PRS_SCOPE=none` when `GH_READY=false`, because an unqueried zero is not
a zero. Both are **caveats** — `STATUS` stays `OK` on every rung, and nothing
is re-resolved: `GIT` keeps reporting the repo it is standing in.

### Task scoping is honest about its guess

The taskwarrior project slug is detected from the repo **directory
basename**, which is wrong for chezmoi source dirs, worktrees, monorepo
subdirs, portfolio checkouts, and repos cloned under another name. The
collector takes **one** all-projects `(status:pending or +ACTIVE)`
snapshot and scopes it in `jq`, so it can see that the detected slug
matched nothing while tasks exist elsewhere — and says so instead of
reporting a confident `OPEN_TASKS=0`:

| `TASK_SCOPE` | Meaning | `PROJECT_CONFIDENCE` |
|---|---|---|
| `project` | The detected (or `--project`) slug owns the count. Scoping is a **hierarchy** match, exactly like `task project:<p>`: `bluepad32` covers `bluepad32.own` but not `bluepad32-extra` | `high` |
| `remote-name` | The slug matched nothing; the **git remote's** repo name did (`PROJECT_RESOLVED=`) | `low` |
| `ancestor-name` | The slug matched nothing; an **ancestor directory's** repo slug did, and was adopted (`PROJECT_RESOLVED=`, `DETECTION=cwd-repo-basename-ancestor`) | `low` |
| `all-projects-fallback` | No slug matched; `RECENT_TASK_*` rows list tasks touched within `--recent-days` across all projects | `low` |
| `unknown` | `jq` unavailable, so no scoping was possible | `low` |
| `none` | `task` unavailable | `low` |

`DETECTION=` reports how the slug was chosen, independently of `TASK_SCOPE`:

| `DETECTION` | Source |
|---|---|
| `override` | `--project` (caller-supplied, user-asserted) |
| `declared` | A `.claude/session.json` `.project` string at the cwd or repo root. That file is repo content, so the value must be a plain single-line string — any other shape is rejected, never flattened into a slug that would match nothing and earn a confident zero |
| `cwd-repo-basename` | The directory basename (the guess) |
| `cwd-repo-basename-ancestor` | An adopted ancestor repo slug |
| `ambiguous` | No repo context |

When the detected slug owns zero tasks but an ancestor slug owns some — and the
detected slug is *asserted*, so it may not be adopted away — the collector emits
`PROJECT_AMBIGUOUS=<slug>` and `PROJECT_AMBIGUOUS_TASKS=N` (both omitted when
there is no ambiguity). Consumers render this as `0 here, N under <slug>`; it is
the one case where even a `high`-confidence zero is not a clean queue.

`OPEN_TASKS` stays an integer in every branch (consumers do arithmetic on
it); the uncertainty lives in `TASK_SCOPE` / `PROJECT_CONFIDENCE`.
`TASKS_ALL_PROJECTS` gives the denominator. An explicit `--project` is
user-asserted, so it keeps a confident zero.

#### The prefix-sibling split

taskwarrior's **CLI** `project:<p>` filter is a *prefix* match, so
`task project:comfyui list` also returns every `comfyui-nodes` task. The
collector's own scoping is narrower (exact slug + `.`-separated children),
so it never miscounts — but a slug "confirmed" at the CLI that way can
still be the wrong one, and its `high`-confidence count then reads as a
verified backlog while the real one sits in a sibling. Three keys make
the split legible:

| Key | Meaning |
|---|---|
| `OPEN_TASKS` | This scope: the slug **plus** its `.`-separated subprojects |
| `PROJECT_EXACT_TASKS` | The slug **alone** (`.project == <slug>`) — always emitted, always an integer |
| `PROJECT_PREFIX_SIBLING_TASKS` / `PROJECT_PREFIX_SIBLINGS` | What a CLI *prefix* filter would **also** have swept in, and the (up to 8) slugs it would have come from. Both omitted when the store has no such siblings |

All three are computed against the slug `OPEN_TASKS` was actually counted
under — `PROJECT_RESOLVED` when a rung above resolved one, else `PROJECT`.

`PROJECT_CONFIDENCE` drops to `low` when
`PROJECT_PREFIX_SIBLING_TASKS > OPEN_TASKS` — strict dominance, not "a
sibling exists", so a `dotfiles` beside a one-task `dotfiles-archive`
stays `high` while still naming the sibling. This downgrade applies to an
*asserted* slug too (`--project`, or a repo declaration): assertion fixes
the slug's identity, it cannot assert what the store holds. Nothing is
adopted or rewritten — the scope and the count stay the caller's.

Regression test: `scripts/tests/test-session-survey.sh` (run directly
with bash).

## Distill collector (`scripts/distill-survey.sh`)

The distill-side analogue of `session-survey.sh`. Where the capture side
surveys *repo/task state*, the distill side mines the local **session
transcript** (`~/.claude/projects/<slug>/<session-id>.jsonl`) so
`session-distill` judges instead of re-reading the whole conversation for
commands/edits and re-running `just --dump` from memory. Same contract:
**read-only** (extraction only — all writes and all *judgment*, including
naming a sequence or a rule, stay in the skill), `=== SECTION ===` /
`KEY=VALUE` output, exit-0 on empty.

Signals are chosen to reward durable workflows over TDD/debug thrash:
cross-session recurrence (a novel command recurring across **separate**
sessions), commit-bracketing (commands in the interval a `git commit`
terminates), and novelty vs `just --dump`. It emits a command *digest* and
commit-interval groupings — it never infers a sequence (that is judgment).

| Flag | Adds |
|---|---|
| `--session-id <id>` | which transcript is "this session" (required — without it the collector SKIPs) |
| `--window-sessions N` | cross-session recurrence window, newest N transcripts (default 10) |
| `--window-days N` | window by age instead of count |
| `--min-sessions N` | SKIP below this many transcripts (default 1) |
| `--project-dir <path>` / `--home-dir <path>` | project root / home (transcripts live under `<home>/.claude/projects`) |
| `--summary` | coarse counts only (`RECIPE_CANDIDATE_COUNT`, `HOT_FILE_COUNT`, `PROCESS_SIGNAL`, `TRANSCRIPT_AVAILABLE`) — used by session-end's Distill qualify gate |

Sections: `SESSION_META`, `RECIPE_CANDIDATES` (novel + recurring/bracketed
commands with `_FIRST`/`_SESSIONS`/`_NOVEL_TOKENS`), `HOT_FILES` (files
edited ≥3× this session, exact paths), `COMMIT_INTERVALS`, `COMMAND_DIGEST`,
and `RULE_HINTS_FROM_TOOLING` (repeated permission/auth denials — the only
mechanical rule signal). Degrades to `TRANSCRIPT_AVAILABLE=false` +
`STATUS=SKIP` when no transcript is reachable, and `session-distill` falls
back to its LLM-re-read behaviour.

Test seams: `DISTILL_SURVEY_PROJECTS_DIR`, `DISTILL_SURVEY_JUST_BIN`.
Regression test: `scripts/tests/test-distill-survey.sh` (run directly with
bash).

## Confirmation-gate convention

All write paths in this plugin confirm via **AskUserQuestion**, never a
freeform "Apply? (y/n)" text question. Ending the turn to wait for a
typed y/n fires Stop hooks, which can inject content between the
question and the answer — the exact race that motivated this plugin's
consolidation.

## Dependencies

- `task` (Taskwarrior 3.x) — primary capture destination; skills degrade
  gracefully when absent
- `git`, `gh` — git state and GitHub passes
- `jq` — hook input parsing

## License

MIT
