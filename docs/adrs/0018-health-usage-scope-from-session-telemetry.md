# ADR-0018: Usage-Telemetry Scope for `health-plugin`

---
date: 2026-06-16
created: 2026-06-16
modified: 2026-06-16
status: Proposed
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0016
github-issues: []
---

## Context

A comparison of [`ncoevoet/claude-markdown-health-check`](https://github.com/ncoevoet/claude-markdown-health-check)
against our `health-plugin` surfaced one capability class that the external
plugin has and we have **none** of: **usage telemetry**. Despite its name, that
plugin is a `.claude/` ecosystem auditor (a 26-phase analogue of our
`/health:check`). Most of its phases overlap what we already do — plugin /
settings / hooks / MCP integrity, skill description quality, the skill-listing
budget — and several things it *lacks* we already cover uniquely (`--scope=stack`
tech-fit, `--scope=runtime` `~/.claude.json` bloat, SessionStart smoke test,
marketplace enrollment, the `skill-argument-handling.md` 9-axis sweep, and the
`evaluate-plugin` cross-model delta).

The genuine gap is its history-mining phases: **dormant skills** (unused in
30+ days), **never-fired skills**, hook failure rates, per-session token trends,
and recurring permission denials. Every check `health-plugin` performs today is
**static** — it reads config and source on disk. None reads what actually
happened across sessions.

Two adjacent ideas from the same comparison are explicitly **out of scope** for
this ADR and recorded here so they are not silently dropped or re-litigated:

- **Auto-memory hygiene** — deliberately **not** adopted. This repo keeps
  auto-memory disabled in favour of a more deliberate session workflow
  (`session-plugin`); an auto-memory audit would imply an integration we have
  chosen not to run.
- **Command↔skill name collisions** — **not applicable**. This repo ships only
  skills (no slash-command files), so the collision class cannot occur.

A third borrow — **live thresholds** (re-fetching skill/memory limits from
Anthropic docs and caching) — is tracked separately; it is a freshness mechanism
for the *existing* static checks, not a telemetry source, and does not belong in
this ADR.

### What the telemetry actually is, and where it lives

Investigation of the local Claude Code data directory (this repo, 2026-06-16)
established the concrete, parseable source:

| Path | Contents | Useful for |
|---|---|---|
| `~/.claude/projects/<slug>/<session-id>.jsonl` | Per-session transcripts, JSONL | Skill / tool invocation counts, recency, denials |
| `~/.claude/sessions/` | Session metadata | Session enumeration, timestamps |
| `~/.claude.json` | Harness runtime state | Already audited by `--scope=runtime` |

Each transcript line is a typed event. A skill invocation appears as an
`assistant` event whose `message.content[]` holds a `tool_use` with
`.name == "Skill"` and `.input.skill` / `.input.command` naming the skill;
every other tool call appears the same way with its own `.name`. A `date`/recency
signal is available from the per-event timestamps and the file mtime. This is
enough to compute, with `jq` over the JSONL set:

- **Never-fired**: enabled skills (from the plugin manifests) that appear in
  **zero** `tool_use name=="Skill"` events in the window.
- **Dormant**: skills whose most-recent invocation is older than N days.
- **Hot/cold ranking**: invocation counts per skill, per tool.

### The constraint the data imposes

The investigation also surfaced the load-bearing design constraint: this data is
**local and long-lived**, not portable. The remote/web sandbox clones a fresh
project directory per session, so `~/.claude/projects/<slug>/` held exactly **one**
transcript and **no history** here. A usage scope is therefore only meaningful in
a long-running **local** install; in a remote session it must degrade cleanly to
`STATUS=SKIP` / "insufficient history" rather than reporting every skill as
"never fired". This is the same local-leaning, read-only shape the existing
`--scope=runtime` audit already adopts for `~/.claude.json`.

## Decision

**Add a read-only `--scope=usage` to `/health:check`, backed by a single
deterministic script (`check-usage.sh`) that mines `~/.claude/projects/*/*.jsonl`
for skill/tool invocation recency and emits the repo's standard structured
output. It is local-leaning and degrades to `SKIP` when history is
insufficient. It is read-only — there is no `--fix` path (consistent with
`--scope=runtime`).**

The skill-listing-budget *sum* check and reference-graph cycle/orphan detection
(the other two borrows worth doing) are **deferred to follow-up work**, not
folded into this scope — the budget sum belongs with the static
agentic/description checks, and graph analysis is a distinct concern.

### Why a new scope, not a new plugin or a phase monolith

The external plugin packs all 26 phases into one ~440-line command — exactly the
phase-based-narration shape `.claude/rules/skill-execution-structure.md` warns
against, and one that `skill-quality.md` would flag as oversized. Our router +
scoped-skill architecture already has the right seam: `--scope=usage` slots
beside `registry`/`stack`/`agentic`/`runtime`, reuses the existing report
aggregation, and keeps the heavy `jq` in a script per ADR-0016
(deterministic-script-extraction).

### Script contract (`check-usage.sh`)

Follows `.claude/rules/structured-script-output.md` and `shell-scripting.md`:

```
=== USAGE TELEMETRY ===
JQ_AVAILABLE=true
HISTORY_AVAILABLE=true
WINDOW_DAYS=30
TRANSCRIPTS_SCANNED=412
SKILLS_ENABLED=210
SKILLS_FIRED=63
SKILLS_NEVER_FIRED=147
SKILLS_DORMANT=12
STATUS=WARN
ISSUE_COUNT=2
ISSUES:
  - SEVERITY=WARN TYPE=never_fired COUNT=147 MSG=enabled skills with zero invocations in window (use --verbose to list)
  - SEVERITY=WARN TYPE=dormant COUNT=12 MSG=skills not invoked in 30+ days (use --verbose to list)
=== END USAGE TELEMETRY ===
```

| Behaviour | Rule |
|---|---|
| Flags | `--home-dir`, `--project-dir`, `--window-days N` (default 30), `--verbose` |
| Empty / no history | `HISTORY_AVAILABLE=false`, `STATUS=SKIP`, `ISSUE_COUNT=0`, exit 0 — never report all-never-fired on a fresh clone |
| Remote sandbox | Same `SKIP` path triggers naturally (fresh clone → 1 transcript) — no `CLAUDE_CODE_REMOTE` branch needed, but documented |
| Parallel-safe | `jq` over the JSONL set returns `[]`/0 and exits 0 on empty (`.claude/rules/parallel-safe-queries.md`) |
| Read-only | No `--fix`; "never-fired" is **advisory** (a skill can be correct and rarely needed) |
| Worktree prune | `find` excludes `*/.claude/worktrees/*` (the #1492 / #1548 prune class) |

### Interpreting "never-fired" honestly

A never-fired skill is **not** automatically dead weight — many skills are
correct-but-rarely-needed (recovery, migration, incident). The report frames the
list as *candidates for review* (description quality, discoverability, or
consolidation per `skill-consolidation.md`), never as an automated delete list.
This mirrors how `--scope=runtime` only *suggests* `jq` cleanups.

## Consequences

### Positive

- **Closes the one real capability gap** versus the external plugin, using our
  existing router seam and structured-output convention rather than a monolith.
- **Feeds existing workflows** — the never-fired / dormant lists are direct input
  to `skill-consolidation.md` reviews and to description-quality audits
  (`audit-skill-descriptions.py`).
- **Read-only and local-leaning** — no new write surface, no portability claim it
  cannot keep.

### Negative

- **Local-only value** — near-useless in remote/web sessions (degrades to `SKIP`);
  the headline feature only earns its keep on a long-running local install.
- **Transcript-format coupling** — keys off the JSONL `tool_use name=="Skill"`
  shape, which is an undocumented harness internal that can change between Claude
  Code versions. Needs a format-sentinel and a `reviewed:` cadence.

### Risks

| Risk | Mitigation |
|------|------------|
| Transcript schema drifts; parser silently returns zero | Format sentinel: if `TRANSCRIPTS_SCANNED>0` but **all** tool counts are 0, emit `STATUS=WARN TYPE=schema_drift` instead of "all never-fired" |
| "Never-fired" misread as "delete me" | Report frames it as review candidates; no `--fix` path |
| Auto-invoked (non-`/`) skills not captured if they register differently | Pilot validates capture against a known-invoked skill before trusting counts; documented as a known limitation if partial |
| `jq` over hundreds of transcripts is slow | Window-bound by mtime before parsing; prune `.claude/worktrees/` |

### Follow-up (explicitly not in this ADR)

1. **Skill-listing-budget sum check** — tally `(name+description)/4 + ~35` tokens
   across enabled skills against `skillListingBudgetFraction × context`; belongs
   with the static agentic/description checks, not usage telemetry.
2. **Reference-graph cycle/orphan detection** across `REFERENCE.md` / cross-links.
3. **Live thresholds** freshness mechanism for the static limits.

## References

- `ncoevoet/claude-markdown-health-check` — the external plugin that prompted the comparison
- `.claude/rules/structured-script-output.md` — `=== SECTION ===` / `STATUS=` / `ISSUE_COUNT=` contract
- `.claude/rules/parallel-safe-queries.md` — empty-result exit-0 requirement
- `.claude/rules/shell-scripting.md` — safe shell patterns, `--home-dir`/`--project-dir` flags
- `.claude/rules/skill-consolidation.md` — the review workflow the never-fired list feeds
- `.claude/rules/regression-testing.md` — the pilot's required guard (schema-drift sentinel)
- `health-plugin/skills/health-check/SKILL.md` — the router this scope slots into
- `health-plugin/skills/health-check/scripts/check-runtime.sh` — the read-only, local-leaning sibling this mirrors
- [ADR-0016: Extract Deterministic Skill Procedure into Structured-Output Scripts](0016-deterministic-script-extraction-for-token-efficiency.md)
