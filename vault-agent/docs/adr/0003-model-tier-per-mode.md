# ADR-0003: Model tier selected per maintenance mode

- Status: Accepted
- Date: 2026-04-17

## Context

Vault maintenance has a wide complexity spectrum:

- Stripping `id:` from frontmatter is mechanical — any model size works.
- Classifying a FVH/z stub as "redirect vs. promote" requires reading two full notes and judging overlap.
- Proposing a new MOC with curated section structure over 17 orphaned notes requires holding the whole cluster in context and recognizing natural groupings.

Using one model tier for everything means overpaying on the easy cases or underperforming on the hard ones.

## Decision

Each subagent declares its own model tier in its `AgentDefinition`:

| Subagent | Model | Rationale |
|----------|-------|-----------|
| vault-lint | haiku | Rule-driven, mechanical. Skill prompts contain explicit rewrite tables. |
| vault-links | sonnet | Rule-table plus ambiguity judgment. |
| vault-stubs | sonnet | Two-file content comparison per stub. |
| vault-mocs | opus | Graph reasoning across many notes. |

Deterministic fixers (`fixers/*`) are written in pure Python and bypass the LLM entirely — they only fire on rules with explicit transforms.

## Consequences

- The pure-Python deterministic path handles ~90% of lint/links work without any LLM cost.
- When the LLM is invoked, we pay for the complexity actually required.
- Adding a new mode is a matter of adding an `AgentDefinition` with an explicit model choice, not changing a global config.

## Related

- git-repo-agent's subagent table uses the same tier mapping strategy.
