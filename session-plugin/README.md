# Session Plugin

Session bookends for Claude Code: a read-only **spinup** briefing at
session start, a **wrap** capture pass at session end, a **distill** pass
for durable learnings, and a **session-end orchestrator** that previews
which passes qualify and runs only what the user confirms.

Design background: [`docs/session-plugin-workflow.md`](../docs/session-plugin-workflow.md)
(two-speed feedback architecture, decisions D1–D5) and the flow diagram
[`docs/diagrams/two-speed-feedback.d2`](../docs/diagrams/two-speed-feedback.d2).

## Skills

| Skill | Purpose |
|---|---|
| `session-spinup` | Read-only session-start briefing: open taskwarrior tasks, git state (uncommitted / unpushed / open PRs), optional journal todos |
| `session-wrap` | End-of-session capture of loose threads to taskwarrior, an optional journal, and GitHub follow-up issues |
| `session-end` | Orchestrator: one survey, preview which of wrap / distill / feedback qualify, **single confirmation**, then sequence them |
| `session-distill` | Distill session insights into `.claude/rules/`, skill improvements, and justfile recipes (moved from `project-plugin`) |

`session-end` also references `feedback-plugin:feedback-session` by name
for the plugin-feedback pass; if that plugin isn't installed the pass is
skipped.

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
| `session-end-nudge.sh` | Stop | Offers `session-plugin:session-end` at most once per session when the user's own messages carry a wind-down phrase. Collapses the former separate wrap + distill nudges (design D4) |

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

Pre-silence either nudge for a session:

```
touch ~/.cache/claude-session-end-nudge/<session_id>
touch ~/.cache/claude-session-spinup-nudge/<session_id>
```

Regression tests: `hooks/test-session-end-nudge.sh`,
`hooks/test-session-spinup-nudge.sh` (run directly with bash).

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
