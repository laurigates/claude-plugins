# ADR-0021: Do Not Adopt the Open Knowledge Format (OKF) for Skills; Record Substrate Convergence

---
date: 2026-07-12
created: 2026-07-12
modified: 2026-07-12
status: Proposed
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0001  # plugin-based architecture (independent install units; "format not platform" tension)
  - ADR-0004  # marketplace registry model (the OKF catalog/Knowledge-Catalog analogue)
  - ADR-0016  # deterministic script extraction (skills are executable, not declarative knowledge)
  - ADR-0019  # reject shared-library/@-imports/templating for skill DRY (sibling "keep current model" decision)
---

## Context

Google Cloud published the **Open Knowledge Format (OKF) v0.1** on 2026-06-12
([blog post](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing)),
a vendor-neutral specification for the curated knowledge that AI agents consume.
Its representation is deflationary and familiar: **a directory of markdown files
with YAML frontmatter**, cross-linked with ordinary markdown links so the link
graph *is* the knowledge graph. A "bundle" holds "concept" files (tables,
datasets, metrics, runbooks); the only *required* frontmatter field is `type`,
with `title`/`description`/`resource`/`tags`/`timestamp` as conventions. Optional
`index.md` (progressive disclosure) and `log.md` (chronological history) per
directory.

This repository already runs that pattern in production: `SKILL.md` is markdown +
YAML frontmatter, cross-linked, versioned in git, with `PLUGIN-MAP.md` as a
navigation index and a `marketplace.json` registry. The convergence prompted the
question this ADR settles: **should skills adopt OKF (its frontmatter keys, its
bundle/`index.md`/`log.md` structure) as their format, to gain the interoperability
OKF promises?**

### Grounding facts (measured 2026-07-12, canonical tree only — worktrees/node_modules excluded)

| Fact | Value | Source |
|------|-------|--------|
| Plugins / skills / agents | 44 / 401 / 21 | `glob '*/skills/*/SKILL.md'` etc. |
| Skills using lazy `REFERENCE.md` | 127 | `glob '*/skills/*/REFERENCE.md'` |
| Skills carrying OKF's required `type:` field | **0 / 401** | frontmatter scan |
| Cross-plugin `plugin:skill` name-references (graph edges) | 198 | regex over skill bodies |
| Skill frontmatter fields (by prevalence) | `name`/`description`/`allowed-tools`/`created`/`modified`/`reviewed` (≈401), `user-invocable` (187), `args` (178), `argument-hint` (177), `model` (58), `disable-model-invocation` (25), `agent` (12), `context` (8) | frontmatter scan |
| Marketplace registry entries | 44 (fields: `name`, `source`, `description`, `version`, `keywords`, `category`) | `marketplace.json` |

### The mapping (OKF element → claude-plugins analogue)

| OKF element | Required? | claude-plugins analogue | Conformance |
|------|:---:|------|------|
| Bundle = directory of concept files | — | `<plugin>/skills/`; repo as super-bundle | ● substrate identical |
| Concept file = markdown + YAML frontmatter | — | `SKILL.md` | ● identical substrate |
| `type` | ✓ | none (0/401); nearest is plugin `category` (marketplace) | ○ absent |
| `title` | conv. | `name` (401) | ◐ renamed |
| `description` | conv. | `description` (401) | ● |
| `resource` (pointer to the live asset) | conv. | none — a skill *is* the asset, not a pointer | ✗ category error |
| `tags` | conv. | `keywords` (marketplace layer, not per-skill) | ◐ different layer |
| `timestamp` | conv. | `created`/`modified`/`reviewed` (401) | ● richer |
| Links form a knowledge graph | — | `plugin:skill` name-refs (198) + `.claude/rules/*` links | ◐ semantic, not path-based |
| `index.md` progressive disclosure | opt. | `PLUGIN-MAP.md` (repo), plugin `README.md` | ◐ repo/plugin-level, not per-dir |
| `log.md` chronological history | opt. | `CHANGELOG.md` (release-please) + git log | ◐ different file |
| Catalog ingestion (Knowledge Catalog) | — | `marketplace.json` (44 entries) | ◐ registry analogue |
| Producer/consumer independence | principle | skill authored once; Claude consumes at runtime | ● |
| "Format, not platform" | principle | `SKILL.md` **is** a Claude Code runtime format | ✗ direct tension |

### The deciding distinction — declarative knowledge vs executable capability

The substrate is the same idea (markdown + frontmatter + links in git), and its
independent re-invention by OKF, Obsidian, and this repo is a genuine signal that
the substrate is *right*. But the **semantics diverge**, and that governs the
decision:

> **OKF concepts are declarative knowledge that *many* consumers read. Skills are
> invocable procedures with permission scoping that *one* runtime executes.**

The frontmatter that dominates skills is executional, not descriptive:
`allowed-tools` (401), `args` (178), `model` (58), `disable-model-invocation`
(25), `context: fork`/`agent:` (8/12) route *how a capability runs*. None of it
has an OKF meaning. Conversely OKF's required `type` has no skill reader (0/401),
and OKF's `resource` field — a pointer *to* the described asset — is a category
error for a skill, which *is* the asset rather than a description of one. Skills
are closer to ADR-0016's "executable procedure" than to a passive concept doc.

The genuinely OKF-*shaped* surface in the portfolio is elsewhere: `.claude/rules/`
(conventions, gotchas, facts) and the sibling Obsidian vault are *declarative*
knowledge — real "concepts." If an OKF representation ever earns its place, it is
as an **export of rules + catalog for a second, non-Claude-Code consumer**, not as
a re-format of skills.

The contrast is concrete, not hypothetical. The **LakuVault** already runs an
OKF-*equivalent* pipeline (its NotebookLM "distillation": subject-grouped markdown
concept files with citations, a "ground truth vs projection" invariant, and a
producer/consumer split) precisely because it has the precondition skills lack — a
**second consumer** (Obsidian, the agent, *and* NotebookLM all read the same
corpus). Skills have one consumer, the Claude Code runtime, whose format is already
`SKILL.md`. So OKF maps to the vault and not to skills *for the same underlying
reason*: declarative multi-consumer knowledge vs single-runtime executable
capability. The portfolio-level treatment of this convergence lives in the vault
note **`Open Knowledge Format (OKF)`** (linked from the *Local LLM & Agents —
Portfolio MOC*); this ADR is the narrow skill-scoped decision that note points at.

## Decision

1. **Do not adopt OKF as the format for skills**, and do not add OKF frontmatter
   keys (`type`, `resource`, OKF-style `tags`/`timestamp`) to `SKILL.md`. The
   current model stands unchanged: self-contained `SKILL.md` artifacts, runtime
   slimming via `REFERENCE.md`, cross-plugin reuse via `plugin:skill`
   name-references, a `marketplace.json` registry, and `PLUGIN-MAP.md` navigation.
2. **Record the substrate convergence** as validation of the existing design:
   markdown + frontmatter + links in git is the pattern OKF, Obsidian, and this
   repo independently arrived at.
3. **Scope any future OKF work to declarative knowledge** (`.claude/rules/`, the
   catalog, the vault) *and* to the existence of a real second consumer — never to
   skills.

### Rationale

| Candidate | Verdict | Why |
|------|------|------|
| Add OKF frontmatter keys to skills | Reject | Additive frontmatter with **zero reader** (Claude Code reads `name`/`description`/`allowed-tools`, not `type`/`resource`). Pure drift against `offload-to-deterministic-substrate` and DRY. |
| Restructure skills into OKF bundles (`index.md`/`log.md` per dir) | Reject | Duplicates functions that already exist at the right altitude (`PLUGIN-MAP.md`, plugin `README.md`, release-please `CHANGELOG.md`). Net churn, no consumer benefit. |
| Adopt OKF to gain interoperability | Reject (now) | Interop needs a **second consumer**; the sole consumer today is the Claude Code runtime, whose format is `SKILL.md`. YAGNI: no interop payoff exists to capture. OKF is also v0.1 with one required field — no enforced interop contract yet. |
| Export `.claude/rules/` + catalog *as* an OKF bundle | Defer | The one mapping that is semantically sound (declarative knowledge → OKF concepts), but blocked on the same missing second consumer. A revisit trigger, not present work. |

## Consequences

### Positive

- No frontmatter drift, no reader-less keys, no bundle restructuring churn.
- Skills stay self-contained platform artifacts with correct executional
  semantics (`allowed-tools`, `model`, `context`) intact.
- The convergence is captured as design validation without a migration.
- A clean, pre-scoped path exists if a second consumer ever appears (export
  rules/catalog, don't touch skills).

### Negative

- The portfolio gains no cross-vendor knowledge interoperability. Accepted: there
  is no second consumer to interoperate with, so there is nothing to lose.
- If OKF becomes a de-facto standard that external agents expect, this repo would
  need an export step later rather than being natively OKF. Accepted as a
  deferable, additive cost — captured as a revisit trigger below.

### Revisit triggers

- **A second, non-Claude-Code consumer** of this repo's knowledge emerges (another
  agent runtime, an external catalog, a cross-org share) — the interop payoff
  becomes real; re-evaluate exporting `.claude/rules/` + `marketplace.json` as an
  OKF bundle.
- **OKF exits v0.1** with an enforced interop contract (more than one required
  field, a published validator) *and* demonstrable multi-vendor adoption.
- **We decide to publish** the rules corpus or plugin catalog as an
  externally-consumable knowledge bundle — then OKF is the *wire format* to target
  for that export, still not the internal format for skills.
- **Claude Code adds** first-class semantic frontmatter (a `type`/`resource`-style
  field a runtime reads) — re-measure alignment then.

## References

- [OKF v0.1 announcement](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing) — Google Cloud Data Analytics, 2026-06-12
- [Karpathy "LLM Wiki" gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) — the living-docs pattern OKF cites
- ADR-0001: Plugin-Based Architecture (independent install units; the "format not platform" tension)
- ADR-0004: Marketplace Registry Model (the catalog/Knowledge-Catalog analogue)
- ADR-0016: Deterministic Script Extraction (skills as executable procedure, not declarative knowledge)
- ADR-0019: Reject Shared-Library / @-Imports / Templating for Skill DRY (sibling "keep the current model" decision)
- `.claude/rules/offload-to-deterministic-substrate.md` — why reader-less frontmatter is drift
- `.claude/rules/documentation-authoring.md` — one canonical home; the vault MOC crosswalk
- LakuVault note `Open Knowledge Format (OKF)` — the portfolio-level concept (OKF ≈ the vault's NotebookLM distillation pipeline); this ADR is its narrow skill-scoped application
