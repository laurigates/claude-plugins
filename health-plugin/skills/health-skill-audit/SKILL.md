---
created: 2026-04-24
modified: 2026-04-24
reviewed: 2026-04-24
description: |
  Audit the plugin skill tree for skill-to-skill overlap, split-pressure inside
  a single SKILL.md, and small sibling skills that could consolidate. Use when
  the user asks to find overlapping skills, surface skills that should extract
  a REFERENCE.md or scripts/ directory, locate clusters of confusingly similar
  skills (e.g. configure-*-test* siblings, test-* fragmentation, *-development
  variants), or run `/health:skill-audit`.
allowed-tools: Bash(python3 *), Read, TodoWrite
args: "[--plugin <name>] [--strict]"
argument-hint: "[--plugin <name>] [--strict]"
name: health-skill-audit
---

# /health:skill-audit

Produce triageable evidence for **skill-to-skill** quality: overlap clusters, split-pressure inside a skill body, and consolidation candidates. The analyzer reports only — every recommendation is editorial.

Complements the other skill audits — this skill assumes frontmatter hygiene is already green.

## When to Use This Skill

| Use this skill when... | Use another approach when... |
|------------------------|------------------------------|
| Finding overlapping skills ambiguous to an invoking agent | Frontmatter / size / body corruption (use `scripts/plugin-compliance-check.sh`) |
| Scoring split-pressure in an oversized skill body | Missing "Use when…" triggers (use `scripts/audit-skill-descriptions.py`) |
| Locating name-prefix or name-suffix clusters | CLI-flag compactness (use `/health:check --scope=agentic`) |
| Surfacing small sibling skills that could merge | Plugin ↔ stack relevance (use `/health:check --scope=stack`) |

## Context

- Analyzer: !`find scripts -maxdepth 1 -name audit-skill-structure.py -type f`
- Prior output: !`find tmp/skill-audit -maxdepth 1 -type f`
- Compliance pre-check: !`find scripts -maxdepth 1 -name plugin-compliance-check.sh -type f`
- Description pre-check: !`find scripts -maxdepth 1 -name audit-skill-descriptions.py -type f`

## Parameters

Parse these from `$ARGUMENTS`:

| Parameter | Description |
|-----------|-------------|
| `--plugin <name>` | Restrict scan to a single plugin directory (e.g. `configure-plugin`) |
| `--strict` | Exit non-zero on `warn`-tier findings in addition to `error`-tier |

## Execution

Execute this skill-structure audit:

### Step 1: Confirm prerequisites are green

These audits own orthogonal concerns. Run them first and resolve their findings before triaging this skill's output:

1. `scripts/plugin-compliance-check.sh` — frontmatter, size budget, body corruption
2. `python3 scripts/audit-skill-descriptions.py --strict` — `description` fields have trigger phrases

If either reports errors, pause and ask the user whether to continue — a messy frontmatter baseline makes the overlap heuristics noisier.

### Step 2: Run the analyzer

```bash
python3 scripts/audit-skill-structure.py $ARGUMENTS
```

This writes five artefacts into `tmp/skill-audit/`:

| File | Contents |
|------|----------|
| `report.json` | Canonical machine-readable output (source of truth) |
| `summary.md` | Top-N by severity, intended for triage |
| `overlap-clusters.md` | Side-by-side description comparison per cluster |
| `split-candidates.md` | Per-skill evidence (lines, tables, fenced code, examples) |
| `consolidation-candidates.md` | Conservative merge suggestions |

The schema for `report.json` and the rationale for every threshold live in [REFERENCE.md](REFERENCE.md).

### Step 3: Triage `summary.md` first

Open `tmp/skill-audit/summary.md`. It lists:

1. Top error-tier split candidates (SKILL.md bodies that exceed the hard line limit without a `REFERENCE.md`)
2. Largest overlap clusters (by number of flagged pairs)
3. Pointers to the three detail reports

### Step 4: For each overlap cluster, decide the disposition

For each cluster in `tmp/skill-audit/overlap-clusters.md`, pick one:

| Disposition | When it fits |
|-------------|--------------|
| Merge | Two small skills describing the same intent → fold into one |
| Rename | Clear distinct intent but colliding names → disambiguate the slug |
| Rewrite descriptions | Intent is distinct but descriptions collide → sharpen trigger phrases |
| Leave | Cluster is a family by design (e.g. `python-plugin` ecosystem skills) — no change |

Do **not** auto-act. Each disposition lands in its own PR per the `CLAUDE.md` guidance.

### Step 5: For each split candidate, decide the disposition

For each row in `tmp/skill-audit/split-candidates.md`, pick one:

| Disposition | When it fits |
|-------------|--------------|
| Extract to `REFERENCE.md` | Warn/error-tier size or contiguous table block |
| Extract to `scripts/` | Fenced-code aggregate exceeds threshold |
| Extract to `examples/` | Multiple lengthy example blocks |
| Leave | Content is genuinely part of the skill's core instruction |

The report's `reason` column carries the quantitative evidence — cite it when opening the split PR.

### Step 6: For each consolidation candidate, decide the disposition

Consolidation suggestions are conservative — both skills must be small, share a plugin, share a name prefix, and have high description similarity. Still, *merge* is editorial:

1. Read both SKILL.md files
2. Confirm the intents really are duplicative (not complementary)
3. Choose the merge target name and fold the smaller skill into it

File a GitHub issue per consolidation decision rather than bundling them.

## Post-actions

- `report.json` is the source of truth for any follow-up PRs — cite the relevant JSON entries in PR descriptions
- Each cluster or split candidate acted upon lands as its own PR
- Add a regression fixture under `tmp/fixtures/` if a fix should be prevented from recurring (see `.claude/rules/regression-testing.md`)

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Full scan | `python3 scripts/audit-skill-structure.py` |
| Single-plugin scan | `python3 scripts/audit-skill-structure.py --plugin configure-plugin` |
| CI-gating run | `python3 scripts/audit-skill-structure.py --strict` |
| Top splits only | `jq '.split_candidates \| sort_by(-.lines) \| .[:10]' tmp/skill-audit/report.json` |
| Top clusters only | `jq '.overlap_clusters \| sort_by(-(.pairs \| length)) \| .[:10]' tmp/skill-audit/report.json` |

## See Also

- `.claude/rules/skill-quality.md` — size limits and required sections
- `scripts/plugin-compliance-check.sh` — frontmatter and body corruption owner
- `scripts/audit-skill-descriptions.py` — trigger-phrase coverage owner
- `/health:check --scope=agentic` — CLI-flag compactness audit
- [REFERENCE.md](REFERENCE.md) — heuristic rubric, thresholds, and JSON schema
