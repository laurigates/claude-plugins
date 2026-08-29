# Prose Plugin

Prose transformation and style control for Claude Code. Synthesize, distill, tune, and enforce prose standards.

## Overview

This plugin provides skills for transforming and controlling written output — synthesizing unstructured thinking into plans, tightening verbose text, enforcing consistent tone, and maintaining stylistic discipline across documents.

## Skills

| Skill | Description |
|-------|-------------|
| `prose-distill` | Compress verbose text to its essence. Lossless condensation — precis, verbal economy, Strunk & White's "omit needless words" as executable practice. |
| `prose-synthesize` | Synthesize unstructured thinking into a structured, actionable plan. Takes stream-of-consciousness thoughts and imposes order — goals, actions, priorities, open questions. |
| `prose-check` | Self-evaluate a draft against the house rubric before it ships — the three tics from `communication.md`, end-on-the-fact, the TL;DR footer. Runs vale, harper, and a positional-tic script; every finding is a candidate for judgment, not a defect. |

## Planned Skills

| Skill | Purpose |
|-------|---------|
| `prose-tone` | Control register and tone (technical, conversational, formal, neutral) |
| `prose-voice` | Active/passive voice enforcement and conversion |
| `prose-clarity` | Sentence-level clarity — eliminate ambiguity, simplify without dumbing down |
| `prose-consistency` | Terminology and style consistency across a document |
| `prose-rhythm` | Sentence length variation and paragraph cadence |
| `prose-structure` | Document-level organization, flow, and information hierarchy |
| `prose-audience` | Adapt text for a target audience (developer, executive, end-user) |

## Usage

### Synthesize

Turn stream-of-consciousness thinking into a structured plan:

```
/prose:synthesize I need to fix the auth system, tests are broken, maybe move to JWT, deployment keeps failing, Sarah mentioned rate limiting, should do a security audit, docs are out of date
```

Result: structured plan with objective, key decisions, ordered actions, dependencies, and open questions.

### Check

Run a draft through the house rubric before it ships:

```
prose-plugin/skills/prose-check/scripts/prose-check.sh --kind ticket /tmp/pr-body.md
```

Result: a `STATUS=` / `ISSUE_COUNT=` rollup over three layers — vale token
rules, harper grammar, and paragraph-final tic detection — with each flagged
sentence quoted. Read the rollup first; open a layer only when the count is
non-zero.

### Distill

Condense verbose text while preserving all meaning:

```
/prose:distill "The end result of this process is that each and every individual component is tested and verified to ensure and confirm that it meets the required specifications."
```

Result: "This process verifies each component meets the required specifications."

## Plugin Structure

```
prose-plugin/
├── .claude-plugin/
│   └── plugin.json
├── styles/                      # vale style package (House = derived rubric)
│   ├── .vale.ini                # curated third-party allowlist; E-Prime OFF
│   ├── house-only.vale.ini      # offline fallback, no downloaded packages
│   └── House/
│       ├── Filler.yml
│       ├── Hedge.yml
│       ├── MeanSentenceLength.yml
│       ├── SignificanceAssertion.yml
│       ├── ThroatClearing.yml
│       ├── TicketHype.yml
│       └── TicketPlaceholder.yml
├── skills/
│   ├── prose-check/
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── positional-tics.py   # PEP 723; pysbd
│   │       └── prose-check.sh       # orchestrator
│   ├── prose-distill/
│   │   └── SKILL.md
│   └── prose-synthesize/
│       └── SKILL.md
└── README.md
```

## The House Style Package

`styles/House/` encodes `~/.claude/rules/communication.md`. It is a **derived
copy**: each rule carries a `link:` back to the rule that owns its criterion
rather than restating the rationale, and
`scripts/check-prose-house-style.sh` in the repo root asserts the derived tokens
have not drifted from the source.

Three tools, three limits:

| Layer | Covers | Why not the layer above it |
|---|---|---|
| vale | token shapes, doc metrics, markdown scoping | free code/table/heading skipping; **no ordinal scope**, so it cannot express "paragraph-final" |
| harper | grammar, readability, sentence length | an independent segmenter and a second opinion on length |
| script | paragraph-final position + tic shape, TL;DR footer | the position half of "position plus shape" |
| model | *is* this a chiasmus? | irreducibly judgment |

`vale`, `harper-cli`, and `uv` are each optional; a missing one is reported as
`AVAILABLE=false` and the other layers still run.

## Automatic Nudge

`hooks-plugin/hooks/prose-house-style-nudge.sh` runs the same check after a
`Write`/`Edit` of a `.md` file and before `gh pr create` / `gh issue create`. It
never blocks, and is opt-in behind `CLAUDE_HOOKS_ENABLE_PROSE_CHECK=1`.
