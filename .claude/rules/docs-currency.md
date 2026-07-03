---
created: 2026-04-24
modified: 2026-05-23
reviewed: 2026-05-23
---

# Docs Currency

> **Moved to plugin skill.** The canonical content lives in
> [`blueprint-plugin/skills/blueprint-docs-currency/SKILL.md`](../../blueprint-plugin/skills/blueprint-docs-currency/SKILL.md).
> This stub is kept for backward compatibility with existing
> `.claude/rules/docs-currency.md` references (currently:
> `configure-plugin/skills/multi-repo-discipline`,
> `tools-plugin/skills/cli-smoke-recipes`, and the skill's own back-link).

The rule: code and the docs that describe it land in the **same commit**.
No deferred doc follow-ups, no "docs: update for X" three commits later.

For the same-commit scope, research-promotion workflow, pre-commit and
pre-merge checklists, and sidecars-vs-authoritative-docs distinction,
invoke the skill directly:

```
/blueprint:blueprint-docs-currency
```

## Why this dogfooding stub remains

This file dogfoods the rule against claude-plugins itself — when a skill
gains new behaviour, its README / skill-description / plugin README land
in the same commit as the code. The narrative ("the rule earned its own
reusable skill once it had survived a few weeks of practice here") is
preserved so references from sibling skills resolve to a meaningful
pointer rather than a 404.

## Related

- `blueprint-plugin:blueprint-docs-currency` — the reusable skill (canonical content)
- `blueprint-plugin:blueprint-curate-docs` — mechanics of promoting research to curated `.claude/rules/` entries
- `blueprint-plugin:blueprint-sync` — detects stale generated content
- `.claude/rules/conventional-commits.md` — commit-type scopes that co-evolve with doc edits
