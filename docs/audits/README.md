# Documentation audits

This directory holds dated, read-only audit artifacts — findings documents, not
fixes. An audit records what was wrong at a point in time and links the issues
that track remediation; the edits themselves land in separate PRs.

Naming follows the one artifact already here,
`project-plugin-phase1-audit-2026-06-04.md`: `<scope>-<what>-YYYY-MM-DD.md`.

## Two layers

The top-level documentation audit (issue #1460) splits into a mechanical half
and a judgment half. Both matter: a complete index pointing at stale prose is
still broken.

| | Layer 1 — mechanical drift | Layer 2 — content health |
|---|---|---|
| Question | Do the maps agree with the territory? | Is the prose accurate, current, and coherent? |
| Mechanism | `scripts/check-docs-index.sh` | Human/agent read-through over four doc clusters |
| Output | Structured `STATUS=`/`ISSUE_COUNT=` findings | Per-cluster follow-up issues, plus a dated artifact here |
| Fixer | The `/docs-refresh` project skill | Whoever picks up the filed issues |

### Layer 1 — automated, no cadence decision needed

`scripts/check-docs-index.sh` runs seven zero-false-positive checks (rules index,
plugin-map agreement, per-plugin counts, d2 diagram nodes, `reviewed:`
frontmatter, rendered diagram SVG, README skill rows). It is wired in twice:

- **`docs-index` job in `.github/workflows/scheduled-audits.yml`** — scheduled
  monthly (`cron: '19 9 1 * *'`), auto-opening a `docs-index`-labelled issue when
  drift is found and filing nothing when clean.
- **`.github/workflows/plugin-pr-checks.yml`** — `--strict`, ungated, on every
  PR, so drift cannot merge.

Nothing here needs scheduling by hand. (The 2026-06-28 cadence decision described
this job as weekly; the workflow's schedule has since been consolidated to
monthly.)

### Layer 2 — quarterly, plus milestone-triggered

Layer 2 cannot be scripted, so it needs a recorded cadence. Run it:

- **Quarterly**, and additionally
- **On a milestone**, whichever comes first:
  - a Claude Code **major version**, or
  - crossing a **plugin-count threshold** — each +10 plugins.

A pass is a fan-out with one reviewer per cluster, read-only, each returning
contradictions / stale sections / coverage gaps / redundancy with `file:line`
evidence:

| Cluster | Scope |
|---|---|
| A — front door & maps | `README.md`, `CLAUDE.md`, `docs/PLUGIN-MAP.md`, `docs/PRINCIPLES.md` |
| B — rules coherence | `.claude/rules/*.md` |
| C — legacy docs | the non-blueprint `docs/*.md` |
| D — blueprint & decisions | `docs/blueprint/` — ADRs, PRDs, PRPs |

The deliverable is **follow-up issues, one per cluster** — not a fix-everything
PR — reconciled into a dated findings document in this directory. Mechanical
drift stays with Layer 1 so reviewers spend judgment only
(`.claude/rules/offload-to-deterministic-substrate.md`).

## Related

- Issue [#1460](https://github.com/laurigates/claude-plugins/issues/1460) — where both layers and this cadence were decided
- `.claude/skills/docs-refresh/SKILL.md` — the fixer that consumes Layer 1 findings
- `.claude/rules/docs-currency.md` — code and its docs land in the same commit
