---
created: 2026-04-24
modified: 2026-11-06
reviewed: 2026-11-06
---

# Docs Currency

Code and the docs that describe it land in the **same commit**: no deferred doc
follow-ups, no "docs: update for X" three commits later.

Unscoped on purpose: the rule bites at commit time, a command no `paths:` glob
can see, and a skill-only home would load only when someone already thought of
it. Kept to this stub so the every-turn cost stays small; the canonical content
(same-commit scope, research promotion, pre-commit and pre-merge checklists,
sidecars vs authoritative docs) is the
[`blueprint-plugin:blueprint-docs-currency`](../../blueprint-plugin/skills/blueprint-docs-currency/SKILL.md)
skill. The file path also stays stable for the skills, scripts and docs that
cite `.claude/rules/docs-currency.md`.

## Related

- `blueprint-plugin:blueprint-docs-currency` — the reusable skill (canonical content)
- `.claude/rules/conventional-commits.md` — commit-type scopes that co-evolve with doc edits
