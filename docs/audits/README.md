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
frontmatter, rendered diagram SVG, README skill rows). It is wired in three
places:

- **`docs-index` job in `.github/workflows/scheduled-audits.yml`** — scheduled
  monthly (`cron: '19 9 1 * *'`), auto-opening a `docs-index`-labelled issue when
  drift is found and filing nothing when clean.
- **`.github/workflows/plugin-pr-checks.yml`** — `--strict`, ungated, on every
  PR, so **ERROR-severity** drift cannot merge. `--strict` exits non-zero only
  on ERROR (`exit_severity` is set in the `SEVERITY=ERROR` branch alone), so
  this step passes on the WARN tier — `doc_count_drift`, `rule_not_indexed`,
  `diagram_count_drift`, `rule_reviewed_*`.
- **`.pre-commit-config.yaml`** (`check-docs-index`) — `--strict` plus
  `verbose: true`, triggered by the paths that can move a stated count, so
  `doc_count_drift` reaches the committer before a push instead of after
  (#2522). `verbose: true` is what surfaces it, for the reason above: a silent
  exit-0 hook prints nothing. Its trigger is narrower than the guard's verdict
  surface, so it narrows the count-drift feedback loop rather than replacing
  the CI step.

What catches the WARN tier is `scripts/tests/test-check-docs-index.sh` TEST A,
which asserts `STATUS=OK` on the real repo. That suite runs only in
`Test: Skill scripts`, whose `paths:` do not include `*-plugin/skills/**`, and
it is absent from the always-on `compliance` job's `--only` list — so a PR that
adds or removes a skill and touches nothing under `scripts/` can still merge
with a stated count out of date. That gap is what the pre-commit entry above
mitigates locally; closing it in CI is a separate decision.

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
