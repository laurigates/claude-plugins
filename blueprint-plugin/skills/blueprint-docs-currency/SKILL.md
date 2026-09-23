---
name: blueprint-docs-currency
description: Enforce same-commit landing of code and docs (APIs, formats, ADRs). Use when committing API/format changes, promoting research to docs/, or landing an ADR decision.
allowed-tools: Bash(bash *), Read, Grep, Glob, TodoWrite
created: 2026-04-24
modified: 2026-09-23
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
produce the curated `.claude/rules/` entry when the code change
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

## Dependency sweep

Before committing, run the bounded sweep over the staged diff:

```bash
bash "${CLAUDE_SKILL_DIR}/../../scripts/docs-dependency-sweep.sh" --project-dir "$(pwd)"
```

It names the hand-written docs that may describe what the commit
changes, one hop from each staged path. It reports; it never edits.

| Staged path | Candidate docs (`KIND=`) |
|-------------|--------------------------|
| `<plugin>/skills/<skill>/…`, `<plugin>/agents/<agent>.md`, `<plugin>/.claude-plugin/…` | plugin `README.md` (`plugin_readme`), plugin `plugin.json` (`plugin_manifest`), `README.md` / `docs/PLUGIN-MAP.md` / `.claude-plugin/marketplace.json` (`catalog`) |
| `<plugin>/<any other path>` | plugin `README.md`, plugin `plugin.json` |
| `.claude/rules/<rule>.md` | `CLAUDE.md` / `AGENTS.md` (`rule_index`), then every other tracked `*.md` citing `<rule>.md` (`rule_backref`) |
| Anything else | Not swept (`UNMAPPED_PATHS=`); use the Same-commit scope table |

**Bound.** At most `CANDIDATE_CAP` files are examined (default 10; set
it with `--cap N` or `DOCS_SWEEP_CAP`). Candidates already staged count
as covered and are not examined. Past the cap the sweep stops and emits
one `cap_reached` finding with the number dropped: a change that broad
needs a full review, not a longer sweep.

**Reading the output.** Each `review_candidate` row carries `DOC=`,
`KIND=`, the staged `SOURCE=`, and `ENTRY_LINES=`, the lines in that doc
that name the change (`none`: the doc does not name it; `-`: there was
no specific name to look for). Open each doc at those lines, then update
it in this commit or confirm it is unaffected. `STATUS=OK` means nothing
is left to review.

## Pre-commit checklist

Before `git commit`, ask:

- [ ] Does this change the public API, file format, error enum, or milestone status?
- [ ] Same commit touches the corresponding `docs/` file?
- [ ] Dependency sweep run, and every `review_candidate` updated in this commit or confirmed unaffected?
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
- `blueprint-plugin:blueprint-curate-docs` — mechanics of producing curated rule entries
- `blueprint-plugin:blueprint-sync` — drift detection for generated docs
- `blueprint-plugin:feature-tracking` — tracker entry mechanics
- `scripts/check-docs-index.sh` (claude-plugins, Layer 1 of #1460) — the whole-repo audit that owns skill/agent counts; the sweep names rows and never compares counts
- `.claude/rules/conventional-commits.md` — commit types that co-evolve with docs

> Evidence: research landed without a same-commit `docs/` update — the
> spec had to be reconstructed in a follow-up PR. The inverse pattern
> (same-commit code + spec) survived grep-based re-investigation months
> later without loss.
