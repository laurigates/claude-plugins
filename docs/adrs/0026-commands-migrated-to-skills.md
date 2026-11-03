---
id: ADR-0026
date: 2026-02-06
created: 2026-11-02
modified: 2026-11-02
status: Accepted
deciders: claude-plugins team
domain: organization
supersedes: ADR-0007
relates-to:
  - ADR-0003
github-issues:
  - 423
  - 2841
---

# ADR-0026: Commands Migrated to Skills

Recorded retroactively on 2026-11-02. The migration landed on 2026-02-06 in
[#423](https://github.com/laurigates/claude-plugins/pull/423); no ADR recorded
it until the Layer-2 documentation audit (#2841, finding D-9).

## Context

Plugins in this repo shipped two component types for user-facing operations:
markdown files under `commands/` (ADR-0003's auto-discovery convention, with
ADR-0007's subdirectory namespaces such as `commands/configure/tests.md` →
`/configure:tests`) and skills under `skills/<name>/skill.md`. Claude Code
2.1.7 merged skills and slash commands into one system: both are invoked as
`/name`, both are auto-discovered, and a skill can carry `args` and
`argument-hint` like a command. Keeping both trees meant two file layouts, two
sets of authoring rules, and duplicated content for the same operation.

## Decision

Every user-invocable operation is a skill. The `commands/` directories were
removed from every plugin, along with the `commands` field in `plugin.json`.
Skill files are named `SKILL.md` and carry a `name:` field. The `/<ns>:<name>`
invocation form ADR-0007 introduced survives, now carried by the skill
directory name `skills/<ns>-<name>/SKILL.md` (`.claude/rules/skill-naming.md`).

This supersedes ADR-0007 in full, and the `commands/` parts of ADR-0003 (the
`commands/` rows of its directory conventions, discovery rules and component
metadata). ADR-0003's convention-based discovery of skills and agents stands.

## Consequences

- One component type to author, lint and document. The authoring rules live in
  `.claude/rules/skill-development.md`, `skill-naming.md` and
  `skill-execution-structure.md`; the former `command-naming.md` became
  `skill-naming.md`.
- Namespacing is a naming convention on skill directories, not a directory
  nesting, so a plugin cannot group skills into subdirectories under
  `skills/`.
- Consumer projects that still keep `.claude/commands/` files need to move them
  to `.claude/skills/<name>/SKILL.md` to follow this repo's conventions;
  Claude Code itself still loads `.claude/commands/`.
- Text in older ADRs (0003, 0005, 0007, 0008, 0010) that describes `commands/`
  files is historical; the banners on those ADRs point here or to ADR-0011.
