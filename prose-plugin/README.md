# Prose Plugin

Prose transformation and style control for Claude Code. Synthesize, distill, tune, and enforce prose standards.

## Overview

This plugin provides skills for transforming and controlling written output — synthesizing unstructured thinking into plans, tightening verbose text, enforcing consistent tone, and maintaining stylistic discipline across documents.

## Skills

| Skill | Description |
|-------|-------------|
| `prose-distill` | Compress verbose text to its essence. Lossless condensation — precis, verbal economy, Strunk & White's "omit needless words" as executable practice. |
| `prose-synthesize` | Synthesize unstructured thinking into a structured, actionable plan. Takes stream-of-consciousness thoughts and imposes order — goals, actions, priorities, open questions. |

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
├── skills/
│   ├── prose-distill/
│   │   └── SKILL.md
│   └── prose-synthesize/
│       └── SKILL.md
└── README.md
```
