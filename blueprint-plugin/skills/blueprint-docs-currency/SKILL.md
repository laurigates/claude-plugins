---
name: blueprint-docs-currency
description: |
  Advisory skill enforcing same-commit landing of code and its docs —
  public APIs, file format specs, error enums, milestone status, and
  ADR-worthy decisions must travel with their documentation. Also covers
  research promotion from tmp/ into docs/ before tracker advancement.
  Use when committing code that changes API, format specs, or milestone
  status; when promoting research from scratch to docs; when landing an
  ADR-worthy decision; or when a reviewer flags missing documentation.
allowed-tools: Read, Grep, Glob, TodoWrite
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
---

# Blueprint Docs Currency

Same-commit discipline for code and documentation. This skill is the
reusable version of claude-plugins' `.claude/rules/docs-currency.md`,
refined for blueprint-driven projects.

## When to Use This Skill

| Use this skill when… | Skip when… |
|---------------------|------------|
| Committing code that changes a public API, format spec, or error enum | Refactoring internal helpers with no external surface change |
| Promoting research findings from `tmp/` to `docs/` | Scratch work that will not ship |
| Landing an architectural decision | Implementation detail with no branching trade-off |
| Advancing a tracker entry past "in progress" | Small task completion that does not cross a phase gate |
| A reviewer flags missing documentation | Typo fixes or whitespace changes |

## The Rule

> Code + its docs land in the same commit. Research promotes to `docs/`
> before the feature advances past "in progress." ADR-worthy decisions
> land with a new or updated ADR in the same commit.

## Same-commit scope

| Change kind | Doc target |
|-------------|-----------|
| Public API / exported type | Inline docstring + reference doc under `docs/api/` (or tool-appropriate) |
| File-format spec | `docs/format-spec/<name>.md` (hand-written prose, not generated) |
| Error enum / protocol code | `docs/errors/<name>.md` or the protocol reference |
| Milestone / phase status | Feature-tracker entry + `docs/PLAN.md` if the phase advanced |
| Architectural decision | New ADR under `docs/adrs/NNNN-<title>.md` |
| New CLI flag or subcommand | README + relevant `docs/cli/` page |

Forward-reference `blueprint-plugin:blueprint-curate-docs` for how to
produce the prose that goes into `docs/ai_docs/` when the code change
surfaces an AI-context gotcha worth capturing.

## Research promotion workflow

Research findings arrive in `tmp/` (gitignored). Before the dependent
feature advances past "in progress" in the blueprint feature tracker:

1. Move the findings into `docs/` at a canonical path (e.g.
   `docs/research/<topic>.md`, or directly into `docs/format-spec/<name>.md`
   if the research *is* the spec).
2. If the research produced a decision, file an ADR. ADRs without a
   decision record are a code smell — revert to research notes.
3. Update the feature-tracker entry with the `docs/` path in its
   evidence field (`blueprint-plugin:feature-tracking` handles the
   mechanical edit).
4. Only then flip the tracker status from `in_progress` to `done`.

See `blueprint-plugin:blueprint-curate-docs` for the prose-production
mechanics; see `blueprint-plugin:blueprint-sync` for the drift detection
that catches stale generated content drifting from source PRDs.

## Sidecars are not documentation

| Layer | Lives at | Authoritative? |
|-------|----------|----------------|
| `TODO.md`, feature tracker JSON | Repo root or `docs/blueprint/` | No — sidecar |
| `docs/PLAN.md`, `docs/roadmap.md` | `docs/` | Yes |
| `docs/format-spec/`, `docs/api/` | `docs/` | Yes |
| ADRs in `docs/adrs/` | `docs/adrs/` | Yes |
| `tmp/research/…` | gitignored | No — scratch |

Sidecars record priority, status, and notes for humans. If a reader
needs the information to port, debug, or onboard, it belongs in `docs/`,
not the sidecar.

## Pre-commit checklist

Before `git commit`, ask:

- [ ] Does this change the public API, file format, error enum, or milestone status?
- [ ] Same commit touches the corresponding `docs/` file?
- [ ] Decision made → new / updated ADR in the same commit?
- [ ] `tmp/research/` either empty or intentionally scratch for this change?
- [ ] Feature tracker entry's evidence field cites the new `docs/` path?

If any box is unchecked, the commit is not ready. Pattern-match on what
the code changed, then fix the doc gap in place.

## Pre-merge checklist

Before a PR's final review:

- [ ] `git log main..HEAD` — each commit that touches a scoped surface
      has a same-commit doc edit
- [ ] `find tmp -type f` — empty, or the contents are scratch that
      should not ship
- [ ] No `docs: follow-up` commits planned for after merge

Deferred doc follow-ups are the failure mode this skill exists to
prevent. "I'll write the spec after the code is in" is the signal to
stop and write the spec now.

## Quick Reference

| Signal | Action |
|--------|--------|
| Adding a new exported function | Same commit: update the reference doc |
| Changing a binary format header | Same commit: update `docs/format-spec/<name>.md` |
| Adding an error code | Same commit: update error enum docs |
| Choosing library A over library B | Same commit: file an ADR |
| Promoting `tmp/research/foo.md` → feature | Move to `docs/` first, advance tracker second |

## Related

- `.claude/rules/docs-currency.md` — claude-plugins' dogfood version of this rule
- `blueprint-plugin:blueprint-curate-docs` — mechanics of producing ai_docs prose
- `blueprint-plugin:blueprint-sync` — drift detection for generated docs
- `blueprint-plugin:feature-tracking` — tracker entry mechanics
- `.claude/rules/conventional-commits.md` — commit types that co-evolve with docs

> Evidence: research landed without a same-commit `docs/` update — the
> spec had to be reconstructed in a follow-up PR. The inverse pattern
> (same-commit code + spec) survived grep-based re-investigation months
> later without loss.
