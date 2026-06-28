# ADR-0019: Reject a Shared-Library Plugin / @-Imports / Build-Time Templating for Skill DRY

---
date: 2026-06-28
created: 2026-06-28
modified: 2026-06-28
status: Accepted
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0001  # plugin-based architecture (independent install units)
  - ADR-0016  # deterministic script extraction (the real token lever)
---

## Context

The repository ships **383 `SKILL.md` files (~2.85M chars ≈ 712K tokens of
source)** across 44 plugins. There is visible repetition — 242 skills carry an
`## Agentic Optimizations` table, all 383 carry a `## When to Use This Skill`
section, frontmatter scaffolding repeats, a handful of safety preambles recur.
This raised three candidate ideas for making skills "more DRY" / slimmer:

- **A. A runtime "library" plugin** of shared concepts other plugins reference.
- **B. `@`-symbol references** inside skills that pull in shared content.
- **C. Build-time templating** — a `src/` of partials compiled into the
  committed `SKILL.md` artifacts (kept where they are now).

The pivotal distinction that governs all three:

> **Author-time DRY** (less duplication in maintained source) and **runtime
> context DRY** (fewer tokens injected when a skill runs) are different problems
> with opposite mechanics. A shared include the runtime expands costs *more*
> context, not less. Only lazy-loading (`REFERENCE.md`) reduces runtime context.

### Grounding facts (measured 2026-06-28, not estimated)

| Fact | Value | Source |
|------|-------|--------|
| Skills / total source | 383 / ~2.85M chars (~712K tokens) | `find … cat \| wc` |
| Skills already using lazy `REFERENCE.md` | 122 | `find -name REFERENCE.md` |
| Literal cross-plugin safety prose | **6** (`CLAUDE_CODE_REMOTE`), **11** (sandbox allowlist) | grep |
| `## Agentic Optimizations` tables | 242 — **structural** dup (same shape, skill-specific rows) | grep |
| Skills referencing `.claude/rules/` | 75 files / 236 lines; **~43 legitimate** (operate on project rules, `$HOME`, `find`/`Glob`); rest are attribution next to **self-contained** content | grep + inspection |
| SKILL.md injection model | **full body at invocation**; `REFERENCE.md` on demand | `skill-quality.md` |
| Cross-plugin file refs | **break** unless both plugins installed; canonical fix is `plugin:skill` name-reference | `skill-consolidation.md` |
| `@`-import in SKILL.md | **not a supported mechanism** (CLAUDE.md supports `@path`; SKILL.md does not) | repo search |

### The DRY surface is shallow (the deciding measurement)

Because build-time templating ships **unchanged** artifacts, corpus size and
runtime context do not shrink — its only payoff is edit-once maintainability.
The right metric is therefore *how much identical source exists across files,
and in what unit.* Counting literally-identical lines across all `SKILL.md`:

| Most-duplicated source line | Files | Nature |
|------|------|--------|
| `## When to Use This Skill` | 383 | section heading (1 line) |
| `## Agentic Optimizations` | 242 | section heading (1 line) |
| `\| Context \| Command \|` | 219 | table column header (1 line) |
| frontmatter / batch date-stamps | 40–186 | per-skill data, not scaffolding |
| `\| Use this skill when... \| Use X when... \|` | ≥6 **hand-varied** variants | not templatable content |
| `…see [REFERENCE.md](REFERENCE.md).` | 18 | the largest repeated **content** line |

The duplication is **single-line structural skeleton** — headings, column
headers, frontmatter. There is **no large repeated block**: the biggest
repeated content line appears in only 18 of 383 files; everything else ≤10.
Even the "identical" `When to Use` header has ≥6 deliberately-varied right-hand
columns. So the maintainability leverage of a single-source partial is ≈ a
heading or two per skill — and those headings essentially never change.

### The `.claude/rules/` references are not a bug

An initial framing treated 75 skills' `.claude/rules/` references as "dead
links to fix." Verifying against the files (per `skill-consolidation.md`
"verify the premise first") disproved it: ~43 are legitimate, and the remainder
are attribution / further-reading pointers sitting next to **self-contained**
content (e.g. `plugin-settings/SKILL.md:69` cites
`.claude/rules/shell-scripting.md` immediately above the actual code block). The
skills work without the referenced file; the references are an intentional
repo-wide dogfooding convention. A 236-edit rewrite would fight that convention
for negligible consumer benefit.

## Decision

**Reject all three DRY mechanisms (A runtime library plugin, B `@`-imports, C
build-time templating). Keep the existing model: self-contained shipped
artifacts, runtime slimming via `REFERENCE.md` lazy-loading, cross-plugin reuse
via `plugin:skill` name-references, and token reduction via the deterministic
script extraction already adopted in ADR-0016. Leave the `.claude/rules/`
reference convention as-is.**

### Rationale per idea

| Idea | Verdict | Why |
|------|---------|-----|
| **A — runtime library plugin** | Reject | Plugins install independently (ADR-0001); a cross-plugin file/library reference is a dead link whenever the consumer lacks the library — exactly the failure `skill-consolidation.md` documents. And it does not slim runtime context: injected → more tokens; name-referenced → the other skill's whole body loads anyway. |
| **B — `@`-imports** | Reject | Not a supported SKILL.md mechanism. Even if it were, it would inject content (no runtime saving) and break cross-plugin (same path problem as A). |
| **C — build-time templating** | Reject | Ships unchanged artifacts → 0 runtime saving by design; the DRY surface is shallow (single-line skeleton, no repeated blocks), so single-source leverage ≈ 2 lines/skill, while the system adds an artifacts-match-`src` CI freshness guard + contributor learning cost. Net negative. |

### What we do instead (already in place)

- **Runtime slimming** → continue moving skill-specific detail into lazy
  `REFERENCE.md` (the 122-skill existing pattern); this is the only lever that
  cuts invocation tokens.
- **Genuine token reduction** → ADR-0016 deterministic script extraction
  (procedure → structured-output scripts), the measured win.
- **Cross-plugin reuse** → reference the canonical owner by `plugin:skill` name.
- **Author-convenience for new skills** → if pursued, a *scaffold/generator* for
  new skills (e.g. `claude plugin init`-style) captures the heading/frontmatter
  boilerplate win with **no** rebuild of existing artifacts and **no** drift
  guard — distinct from templating committed artifacts.
- **Structural consistency** → already enforced by
  `scripts/plugin-compliance-check.sh` (required `When to Use` / `Agentic
  Optimizations` sections), not by a template engine.

## Consequences

### Positive

- No build step, no `src/`→artifact drift guard, no contributor onboarding cost.
- Shipped skills stay self-contained — no broken cross-plugin references.
- Effort stays on the measured token lever (ADR-0016) instead of a cosmetic one.

### Negative

- The shallow structural duplication (section headings, column headers) remains
  hand-maintained. Accepted: the units are 1-line and effectively immutable, and
  the compliance checker already pins their presence.
- The `.claude/rules/` references remain pointers a single-plugin consumer can't
  open. Accepted as harmless attribution; revisit only if it causes real
  confusion (then prefer full-URL rewrite over a library).

### Revisit triggers

- A future change introduces genuinely **large, identical, frequently-edited**
  multi-line blocks across many skills (a repeated block, not a heading) — then
  re-measure the templating payoff against the freshness-guard cost.
- Claude Code ships a first-class, cross-plugin-safe skill-include mechanism.

## References

- ADR-0001: Plugin-Based Architecture (independent install units)
- ADR-0016: Deterministic Script Extraction for Token Efficiency (the real lever)
- `.claude/rules/skill-consolidation.md` — cross-plugin = `plugin:skill` name, not shared file; verify-the-premise discipline
- `.claude/rules/skill-quality.md` — full-body injection model, size gates, `REFERENCE.md` split
- `.claude/rules/skill-evaluation.md` — the cross-model delta harness a future templating spike would use as its behavior gate
