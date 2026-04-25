# Blueprint (constrained dogfooding)

This directory contains [Blueprint Development](https://github.com/laurigates/claude-plugins/tree/main/blueprint-plugin) state for `claude-plugins` — the **source repo** for `blueprint-plugin` itself. Blueprint is initialised here in a deliberately constrained mode so the maintainer can dogfood the read-leaning workflows without the destructive automations colliding with this repo's hand-written governance content.

## Why constrained?

`claude-plugins` is the upstream of `blueprint-plugin`. That makes naïve use of the derive/generate tasks dangerous:

- **`derive-prd` / `derive-plans`** mine git history and `README.md` to invent PRDs/PRPs. Here, git history is dominated by plugin-feature commits (`feat(blueprint-plugin): ...`) and 39 `*-plugin/SKILL.md` files look like requirements documents to a naïve scanner. Synthesised PRDs would treat plugin work as project requirements.
- **`derive-rules` / `generate-rules`** write into `.claude/rules/`, which already holds 18 hand-curated rules (the source of truth for plugin conventions, shared with every marketplace user). Generated content currently lands flat alongside hand-written files, so a hash-collision overwrite would clobber governance content.
- **`claude-md`** offers a "regenerate completely" option that would discard 230+ lines of hand-curated convention guidance in `CLAUDE.md` if accepted by mistake.

The constrained posture disables all of the above. It keeps the workflows that genuinely add value across 16 ADRs / 2 PRDs / 5 PRPs.

## Enabled vs disabled tasks

See `manifest.json#task_registry` (each disabled task carries a `context.disabled_reason`).

| Task | Enabled | Why |
|------|---------|-----|
| `adr-validate` | ✓ | Detects orphans, broken `supersedes` chains, and missing domain tags across 16 ADRs |
| `sync-ids` | ✓ | Reconciles document ID frontmatter; **always run with `--dry-run` first** |
| `feature-tracker-sync` | ✓ | Read-leaning sync against `TODO.md` (no tracker enabled yet) |
| `story-audit` | ✓ | Read-only audit: capability map ↔ PRD stories ↔ tests, tier-ranked. Writes one dated artifact under `docs/blueprint/audits/` |
| `story-reconcile` | ✓ | Phase 2 of story-audit. Mutates PRDs only (idempotent inline markers + wholesale `## Known Drift` section); confirms each PRD before writing |
| `derive-prd` | ✗ | Would invent PRDs from plugin-feature commits |
| `derive-plans` | ✗ | Conflicts with hand-authored `docs/plans/` |
| `derive-rules` | ✗ | Could overwrite the 18 hand-written rules |
| `generate-rules` | ✗ | No subdirectory output path yet — re-enable once configurable ([#1043](https://github.com/laurigates/claude-plugins/issues/1043)) |
| `claude-md` | ✗ | "Regenerate completely" prompt is too easy to mis-click |
| `curate-docs` | ✗ | Default off in blueprint init |

## Directory structure

```
docs/blueprint/
├── README.md            # This file
├── manifest.json        # Constrained task_registry — see top-level CLAUDE.md
├── work-orders/         # Gitignored; per-task scratch
│   ├── completed/
│   └── archived/
├── audits/              # Dated story-audit artifacts (one file per run)
└── ai_docs/             # On-demand curated docs (curate-docs is disabled)
    ├── libraries/
    └── project/
```

## Related locations

| Location | Content |
|----------|---------|
| `docs/prds/` | Product Requirements Documents (hand-authored) |
| `docs/adrs/` | Architecture Decision Records (hand-authored, 0001–0015) |
| `docs/prps/` | Product Requirement Prompts (hand-authored) |
| `docs/plans/` | Hand-authored plans (do not confuse with blueprint PRPs) |
| `.claude/rules/` | 18 hand-written rules — **never** auto-generated into this directory |

## Commit-scope convention

| Scope | Effect | Use for |
|-------|--------|---------|
| `chore(blueprint): …` | No version bump | Manifest bookkeeping, sync runs, ID assignments |
| `feat(blueprint-plugin): …` | Minor version bump on `blueprint-plugin` | Skill changes inside `blueprint-plugin/` |
| `fix(blueprint-plugin): …` | Patch version bump | Bug fixes inside `blueprint-plugin/` |

The unscoped `blueprint` scope deliberately exists separately from `blueprint-plugin` so dogfooding maintenance never accidentally publishes the plugin.

## Re-enabling tasks

Before flipping any disabled task to `enabled: true`:

1. Read the `context.disabled_reason` in `manifest.json`.
2. Confirm the underlying concern has been addressed (e.g. `generate-rules` only after a configurable output path lands in `blueprint-plugin`).
3. Open a PR with the manifest change separately from any other work, so the rationale lives in one commit.

## Learn more

- [Blueprint Plugin Documentation](https://github.com/laurigates/claude-plugins/tree/main/blueprint-plugin)
- [ADR-0005: Blueprint Development Methodology](../adrs/0005-blueprint-development-methodology.md)
- [ADR-0011: Blueprint State in docs/ Directory](../adrs/0011-blueprint-state-in-docs-directory.md)
