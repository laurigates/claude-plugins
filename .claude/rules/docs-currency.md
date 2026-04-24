---
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# Docs Currency

Code and the docs that describe it land in the **same commit**. No deferred
doc follow-ups, no "docs: update for X" three commits later, no notes to
self in the PR description.

## The Rule

> When a change modifies a public API, format spec, error enum, or
> milestone status, the same commit touches the corresponding `docs/`
> file. When a decision was made, the same commit lands a new or updated
> ADR.

## Why

Separate doc commits rot. The code change lands first, the work gets
noisy, the doc commit slips. Grep-based re-investigation months later
turns up the code without the context that explains *why* it exists.
Conversely, a same-commit code + docs pair survives indefinitely — the
prose is findable from the code and the code is findable from the prose.

## Scope

The rule applies when the change touches any of:

- **Public API / schema** — function signatures, exported types,
  generated schemas, protobuf, JSON-schema, OpenAPI
- **File format specs** — binary/text format definitions, on-disk schemas
- **Error enums / protocol codes** — user-visible error identifiers
- **Milestone status / roadmap** — feature-tracker entries, `PLAN.md`,
  `TODO.md`, release notes
- **Decisions** — architectural choices that affect more than one module

Ordinary implementation refactors, typo fixes, and internal helper churn
do not require docs updates.

## Research Promotion

Findings produced by research — decompilation dumps, spec experiments,
API probes, benchmark results — live in gitignored scratch
(`tmp/research/…`). **Before** the feature that depends on those findings
advances past "in progress" in the tracker, the findings move into
`docs/` (and, if a decision was made, an ADR).

Tracker-advancement gate:

- [ ] Findings promoted to `docs/` at a canonical path
- [ ] ADR filed if the research produced a decision
- [ ] Tracker entry cites the new docs path in its evidence field

If any box is unchecked, the tracker stays in "in progress."

## Sidecars vs. authoritative docs

| Layer | Audience | Content |
|-------|----------|---------|
| Sidecar (feature tracker, `TODO.md`) | Humans working in the repo | Priority, status, notes, evidence pointers |
| Authoritative (`docs/`) | Anyone onboarding, debugging, or porting | Prose that survives without the author |

Sidecars are fine; they are *not* documentation. If a reader needs the
information to port, debug, or onboard, it belongs in `docs/`.

## Pre-merge checklist

Before merging a code change, ask:

- [ ] Does this change the public API, file format, error enum, or
      milestone status?
- [ ] If yes, does the same commit touch the corresponding `docs/` file?
- [ ] Was a decision made? If yes, is there a new or updated ADR?
- [ ] Is `tmp/research/` empty (or intentionally scratch) for the change
      being merged?

Any unchecked box is a blocker. Fix in the same PR.

## Why this lives here (claude-plugins)

This file dogfoods the rule against claude-plugins itself. When a skill
gains new behaviour, its README / skill-description / plugin README land
in the same commit. The rule earned its own reusable skill
(`blueprint-plugin:blueprint-docs-currency`) once it had survived a few
weeks of practice here.

## Related

- `blueprint-plugin:blueprint-docs-currency` — reusable skill version of this rule
- `blueprint-plugin:blueprint-curate-docs` — mechanics of promoting research to ai_docs
- `blueprint-plugin:blueprint-sync` — detects stale generated content
- `.claude/rules/conventional-commits.md` — commit-type scopes that co-evolve with doc edits

> Evidence: research landed without a same-commit `docs/` update — the
> spec had to be reconstructed in a follow-up PR. The inverse pattern
> (same-commit code + spec) survived grep-based re-investigation months
> later without loss.
