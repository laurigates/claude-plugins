# Prose Plugin

Writing style control and consistency for Claude Code. Distill, tune, and enforce prose standards.

## Overview

This plugin provides skills for controlling written output — tightening verbose text, enforcing consistent tone, and maintaining stylistic discipline across documents.

## Skills

| Skill | Description |
|-------|-------------|
| `prose-distill` | Compress verbose text to its essence. Lossless condensation — precis, verbal economy, Strunk & White's "omit needless words" as executable practice. |

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
│   └── prose-distill/
│       └── SKILL.md
└── README.md
```
