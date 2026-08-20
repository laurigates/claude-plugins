---
created: 2026-08-15
modified: 2026-08-20
reviewed: 2026-08-20
paths:
  - "health-plugin/**"
  - "evaluate-plugin/**"
  - "feedback-plugin/**"
---
# `pluginUsage.usageCount` Counts Hook Fires, Not Plugin Value

`~/.claude.json` carries a `pluginUsage` map — `usageCount`, `lastUsedAt`,
`lastUsedNumStartups` per installed plugin. It reads like a "how much is this
plugin earning its catalog cost?" counter. It is not one: **hook fires are
counted in the same number as skill, agent, and command deliveries**, and the
hook term runs three to four orders of magnitude ahead. A plugin that has
delivered nothing but registers one `SessionStart` hook outranks a hookless
plugin that really was invoked, by roughly 20×.

## The measurement

Measured 2026-08-15 against `~/.claude.json`, correlated with each plugin's
declared hooks. Hook declarations resolve **two ways** — an inline `hooks`
object in `.claude-plugin/plugin.json`, or a `"hooks": "./hooks.json"` **string
reference** to a sibling file — and reading only the inline form scores six
plugins here (`git-plugin`, `terraform-plugin`, `blueprint-plugin`,
`code-quality-plugin`, `codebase-attributes-plugin`, `agent-patterns-plugin`)
as declaring none, which inverts the correlation.

| Plugin | `usageCount` | Hook entries | Matcher |
|---|---:|---:|---|
| `hooks-plugin` | 207,210 | 12 across 8 events | per-tool-call |
| `git-plugin` | 64,107 | 3 (via `hooks.json`) | `PreToolUse: Bash` |
| `blueprint-plugin` | 13,204 | 22 (via `hooks.json`) | path-scoped `docs/**` |
| `session-plugin` | 5,474 | 2 | `SessionStart` + `Stop` |
| `health-plugin` | 1,536 | 1 | `SessionStart` |
| `agent-patterns-plugin` | 24 | 2 (via `hooks.json`) | `PreCompact` |
| `project-plugin` | 67 | **none** | — |
| `tools-plugin` | 6 | **none** | — |

The separation is clean: every plugin above 126 declares hooks; every one of the
30 hookless plugins sits at or below 67. Two rows refine the mechanism past
"has hooks":

- **Entry count does not drive it.** `blueprint-plugin`'s 22 path-scoped entries
  earn a fifth of `git-plugin`'s 3 broad ones. What multiplies is *matcher
  breadth × event frequency*.
- **A rare event ranks below no hooks at all.** `agent-patterns-plugin` declares
  2 `PreCompact` hooks and sits at 24 — under three hookless plugins. So a low
  count is not evidence of no hooks either; the counter tracks **trigger
  cadence** and nothing else.

Corroborating: the `SessionStart`-only cohort (`configure`, `health`,
`taskwarrior`, `evaluate`, `session`) all share the identical `lastUsedAt`
millisecond `1786786648800` — one session-start event dispatching five plugin
hooks in lockstep. And the counter moves while you read it: `hooks-plugin` went
206,856 → 207,137 → 207,210 over one working session, tracking tool calls rather
than any use of the plugin.

## Nothing in this repo reads it — keep it that way

A repo-wide search for `pluginUsage` / `usageCount` across `*.md`, `*.sh`,
`*.py`, and `*.json` returns **zero** hits. In particular
`health-plugin:health-check` does **not** consume it:

| Scope | Reads |
|---|---|
| `--scope=runtime` | `~/.claude.json`, but only for **bloat** — dead `projects[]`, dead `githubRepoPaths[*]`, orphaned `disabledMcpServers[]`, duplicate MCP names |
| `--scope=usage` | `~/.claude/projects/*/*.jsonl` **session transcripts**, mining skill/agent invocation recency (never-fired, dormant) |

So no normalization work is owed anywhere. This rule exists so the counter is
not *newly* wired into a ranking by someone who reads it as a value signal — the
tempting consumers being `health-plugin`'s audit scopes and `evaluate-plugin`'s
effectiveness measurement.

## The delivery signal, and its exact spelling

Per-call attribution in the session transcripts measures delivery directly.
**The keys are lowercase-first**, and the capitalized spelling matches nothing:

| Field | Non-empty calls | Distinct values |
|---|---:|---:|
| `attributionAgent` | 5,562 | 5 |
| `attributionSkill` | 3,607 | 25 |
| `attributionPlugin` | 2,880 | 9 |
| `attributionMcpServer` / `attributionMcpTool` | 320 | — |

Measured over the 200 most-recent transcripts (56,598 lines, 21,298 carrying a
`tool_use`). Scanning for `AttributionPlugin` instead returns **0** — a clean
zero that reads exactly like "the field is never populated", which is why the
control matters (`~/.claude/rules/never-fabricate-test-identifiers.md`).

`attributionAgent` is populated — in fact it is the **most** common of the three
(`workflow-subagent` 2,955, `general-purpose` 2,077, `Explore` 400,
`feedback-plugin:friction-learner` 91, `Plan` 39). A `--scope=usage` run already
reads agent dispatch from `Agent`/`Task` `subagent_type` events; this field is
the per-call complement, not a gap.

## Transcripts expire — the durable signal is `~/.claude/skill-usage.jsonl`

Transcript mining is correct but **bounded by retention**. Measured 2026-08-20:
1,134 files under `~/.claude/projects` reached back only to 2026-07-22, and a
full sweep of them found 57 distinct skills used out of 420 in the marketplace.
That 363-skill remainder is a *floor*, not a verdict — anything used before the
window is indistinguishable from never used.

`feedback-plugin/hooks/skill-usage-log.sh` (`PreToolUse(Skill|SlashCommand)` +
`UserPromptSubmit`, **opt-in** via `CLAUDE_HOOKS_ENABLE_SKILL_USAGE_LOG=1`)
appends one JSONL record per invocation to `~/.claude/skill-usage.jsonl`, which
no retention policy trims. `feedback-plugin/scripts/skill_usage_report.py` reads
it — merging the expiring transcripts on `--include-transcripts` — and
`friction-learner` Step 1b consumes that to target which skills the weekly slow
loop analyses. It lives in `feedback-plugin` rather than `hooks-plugin` because
the log has one consumer and that consumer is the feedback loop; a telemetry
file nothing reads is the failure this rule already documents.

Two traps it exists to avoid re-deriving:

- **Filesystem `atime` is not a usage signal on macOS.** Reading a file does not
  update `atime` on this APFS volume (verified: write, sleep 2s, `cat`, `atime`
  unchanged), and all 2,038 `SKILL.md` files under `~/.claude/plugins` have
  `atime == mtime` — install time, not use time. Zero files anywhere have
  `atime > mtime`.
- **A `PreToolUse` hook alone under-counts.** A user-typed `/plugin:skill` never
  reaches a tool; the client expands it into the prompt, so only
  `UserPromptSubmit` sees it. In the sweep above, 11 of the 57 used skills
  appeared *only* by that path — `session-end`, `git-issue`, `project-refocus`
  and `health-check` among them.

## Related

- `feedback-plugin/hooks/skill-usage-log.sh` — the durable per-invocation log described above
- `feedback-plugin/scripts/skill_usage_report.py` — its consumer; `friction-learner` Step 1b
- `health-plugin:health-check` — `--scope=usage` (transcript mining) and `--scope=runtime` (`~/.claude.json` bloat); neither touches the counter
- `.claude/rules/skill-evaluation.md` — how skill *effectiveness* is actually measured (with-skill vs baseline delta), the question the counter looks like it answers
- `.claude/rules/context-engineering.md` — the catalog-cost question a delivery signal would inform
- `~/.claude/rules/never-fabricate-test-identifiers.md` — the capitalized-spelling zero above is this trap in miniature
