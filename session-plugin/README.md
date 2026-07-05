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
| `session-wrap` | End-of-session capture of loose threads to taskwarrior, an optional journal, and GitHub follow-up issues |
| `session-end` | Orchestrator: one survey, preview which of wrap / distill / feedback / taskwarrior-sync / blueprint tracker-sync qualify, **single confirmation**, then sequence them |
| `session-distill` | Distill session insights into `.claude/rules/`, skill improvements, and justfile recipes (moved from `project-plugin`) |

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
| `session-spinup-nudge.sh` | SessionStart (startup/resume) | Injects a one-time context note when open threads exist (dirty tree, unpushed commits, open tasks for the cwd project). Informational only — never blocks |
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
| (none) | PROJECT, GIT, PRS, TASKWARRIOR, STALE_ACTIVE_ELSEWHERE |
| `--with-dedup` | GITHUB_DRIFT (assigned-open issues minus those tracked in taskwarrior) |
| `--with-journal --journal-path <dir>` | JOURNAL (unchecked todos from the most recent dated note) |
| `--with-commits` | COMMITS (recent commit subjects) |
| `--with-blueprint` | BLUEPRINT (manifest/tracker presence, ready/blocked/in-flight feature counts, closed-but-undrained WO-linked tasks). Degrades to `MANIFEST=false` + zeroed counts when the repo isn't blueprint-enabled |
| `--summary` | coarse counts only (used by the nudge hook) |
| `--project <name>` | override the detected project |

Regression test: `scripts/tests/test-session-survey.sh` (run directly
with bash).

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
