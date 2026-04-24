# health-skill-audit — Reference

Detailed rubric, threshold rationale, and JSON schema for `/health:skill-audit`.

## Scope

This audit owns **skill-to-skill relationships** — overlap, split-pressure,
and consolidation. Adjacent audits own their own concerns and must be run
first:

| Audit | Owns |
|-------|------|
| `scripts/plugin-compliance-check.sh` | Frontmatter fields, 500-line hard limit, body corruption |
| `scripts/audit-skill-descriptions.py` | Description presence and "Use when…" trigger phrases |
| `/health:check --scope=agentic` | CLI-flag compactness inside individual skills |
| **`/health:skill-audit`** | **Overlap clusters, split-pressure evidence, consolidation** |

## Heuristics

### Overlap clusters

Emit a cluster whenever ≥3 skills share a meaningful name component. Three
cluster bases are computed — deliberately redundant so a single skill may
appear in multiple clusters (this is a triage signal, not a disjoint
partition):

| Basis | Key format | Rule |
|-------|------------|------|
| `plugin-prefix` | `<plugin>:<component>-*` | Within one plugin, ≥3 skills sharing their distinctive first name component (first component that is not the plugin's own stem, e.g. `api` for `configure-api-tests` inside `configure-plugin`). |
| `suffix` | `*-<component>*` | Globally, ≥3 skills sharing their last name component (after light stemming: `-s`, `-es`, `-ing` folded), spanning ≥2 plugins. |
| `shared-token` | `*<token>*` | Globally, ≥4 skills sharing any other name component (stemmed), spanning ≥2 plugins, where the token is not any member's plugin stem. |

**Pair scoring within a cluster** uses Jaccard similarity on description
trigger tokens (stop-words removed). Pairs flagged when:

- Similarity ≥ **0.60**, or
- Descriptions have an **identical first sentence**.

Pair flagging is a secondary signal — the **cluster itself** is the finding.
A cluster with zero flagged pairs still means ≥3 skills share a name token
and merits a disposition (merge / rename / rewrite / leave).

**Ambiguity markers.** Inside a cluster, a skill whose description tokens
are fully covered by a sibling's (set subset) is flagged as dominated —
there is no distinguishing token against its sibling. This mirrors the
global trigger-phrase check from `audit-skill-descriptions.py`, rescoped
to the cluster.

### Split candidates

Each finding is `warn` or `error` tier. `error`-tier exits non-zero; `warn`
exits non-zero only under `--strict`.

| Rule | Severity | Suppressed when |
|------|----------|-----------------|
| SKILL.md > **400** lines | `warn` | sibling `REFERENCE.md` exists |
| SKILL.md > **500** lines | `error` | sibling `REFERENCE.md` exists |
| Contiguous table block > **80** rows | `warn` | sibling `REFERENCE.md` exists |
| Aggregate fenced-code lines > **100** | `warn` | sibling `scripts/` exists and is non-empty |
| ≥ **5** `example` headings totalling > **120** lines | `warn` | sibling `examples/` exists and is non-empty |

The thresholds are conservative. An oversized skill with a sibling file
already split out is surfaced only if there is a *different* kind of
pressure (e.g. 450 lines + 300 fenced-code lines despite an existing
`REFERENCE.md` → still flagged for `scripts/` extraction).

### Consolidation candidates

A pair is flagged when all four hold:

1. Both skills belong to the same plugin
2. Both SKILL.md files are under **100** lines
3. They share the same first name component (after dropping the plugin stem)
4. Jaccard similarity on trigger tokens ≥ **0.70**

Merges are always editorial — the pair is a candidate, not a prescription.

### Stop-word and token model

Tokens are extracted from `description` using the lowercase regex
``[a-z][a-z0-9-]+``. A conservative stop-word list (copied below) drops
filler verbs, auxiliaries, and pronouns that would otherwise inflate
Jaccard scores. Tokens shorter than three characters are dropped.

```
a an and or the of to for with in on at by from as is are be use used using
when user users asks want wants ask asking need needs requires requirement
this that these those it its skill use-when such skills command commands
mentions mention provides provide provided can will would should may might
also etc via into over up all any each every some other another same more
less less-than greater-than between before after during while if then else
new existing your their my our they them he she his her its we i you
support supports supporting across against including include included
make makes made do does doing done have has had get gets got set sets
configure configured configuring run running runs based uses using
check checks checking
```

## What the analyzer deliberately does not do

- Does **not** re-check frontmatter / size / review-date / body corruption — that is the domain of `scripts/plugin-compliance-check.sh`.
- Does **not** re-check the global "Use when…" trigger phrase — that is the domain of `scripts/audit-skill-descriptions.py`.
- Does **not** re-check CLI-flag compactness — that is the domain of `/health:check --scope=agentic`.
- Does **not** auto-fix anything. Every finding is surfaced for human editorial judgement.

## `report.json` schema

```jsonc
{
  "skills": [
    {
      "plugin": "configure-plugin",
      "skill": "configure-tests",
      "path": "configure-plugin/skills/configure-tests/SKILL.md",
      "lines": 184,
      "fenced_lines": 42,
      "table_lines": 28,
      "largest_table": 12,
      "example_blocks": 0,
      "example_lines": 0,
      "has_reference": false,
      "has_scripts": false,
      "has_examples_dir": false,
      "description": "Check and configure testing frameworks..."
    }
  ],
  "overlap_clusters": [
    {
      "cluster": "*-test*",
      "basis": "suffix",
      "members": ["configure-plugin/skills/configure-tests/SKILL.md", "..."],
      "pairs": [
        {
          "a": "configure-plugin/skills/configure-tests/SKILL.md",
          "b": "configure-plugin/skills/configure-api-tests/SKILL.md",
          "similarity": 0.42,
          "identical_first_sentence": false
        }
      ],
      "ambiguous": [
        {
          "skill": "configure-plugin/skills/configure-tests/SKILL.md",
          "dominated_by": "configure-plugin/skills/configure-api-tests/SKILL.md"
        }
      ]
    }
  ],
  "split_candidates": [
    {
      "skill": "blueprint-plugin/skills/blueprint-upgrade/SKILL.md",
      "lines": 523,
      "reason": "523 lines and no sibling REFERENCE.md",
      "severity": "error"
    }
  ],
  "consolidation_candidates": [
    {
      "plugin": "example-plugin",
      "prefix": "foo",
      "skills": ["example-plugin/skills/foo-a/SKILL.md", "example-plugin/skills/foo-b/SKILL.md"],
      "similarity": 0.78,
      "combined_lines": 132,
      "rationale": "Both under 100 lines, same prefix 'foo', Jaccard 0.78"
    }
  ],
  "thresholds": {
    "warn_lines": 400,
    "error_lines": 500,
    "table_block_warn": 80,
    "fenced_code_warn": 100,
    "example_block_count": 5,
    "example_block_lines": 120,
    "overlap_similarity": 0.6,
    "consolidation_similarity": 0.7,
    "consolidation_max_lines": 100
  }
}
```

## Exit codes

| Condition | Exit code |
|-----------|-----------|
| Default (any finding, report-only) | `0` |
| `--strict` with any `warn` or `error` split candidate | `1` |

The default is report-only so the audit can land alongside a baseline that
still contains real findings. Wire `--strict` into CI once the baseline is
clean. Overlap clusters and consolidation candidates never change the exit
code — they are editorial surfacing only.

## Output paths

All artefacts are written to `tmp/skill-audit/` relative to the repo root.
The directory is created if missing. The script overwrites existing
artefacts on each run (the JSON is the source of truth).

## Related

- `.claude/rules/skill-quality.md` — size limits and required sections
- `.claude/rules/skill-naming.md` — namespace conventions that drive cluster names
- `.claude/rules/skill-development.md` — granularity decision that drives consolidation
- `.claude/rules/regression-testing.md` — add a fixture when acting on a finding
