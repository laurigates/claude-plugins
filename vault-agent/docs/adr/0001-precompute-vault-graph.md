# ADR-0001: Pre-compute the vault graph in pure Python before any LLM call

- Status: Accepted
- Date: 2026-04-17

## Context

vault-agent operates on an Obsidian vault of 1,400+ markdown notes. Every mode (lint, links, stubs, mocs, maintain) needs the same structural information: basename index, wikilink graph, tag distribution, orphan lists, MOC inventory.

If each subagent re-scanned the vault via `Read` + `Grep` tool calls, we'd burn tokens on trivial filesystem walks and invite inconsistency between modes.

## Decision

Every invocation starts with a single synchronous call to `analyzers.audit.run_audit(vault)`, which produces a `VaultAudit` containing:

- `VaultIndex`: basename → paths, rel-path → note, wikilinks per note
- `FrontmatterReport`, `LinkReport`, `GraphReport`, `StubReport`, `MocReport`, `DuplicateReport`, `HealthScore`

The audit runs in pure Python (no LLM, no Obsidian CLI). Its results are then:

1. Used directly by deterministic fixers (`fixers/*`) to apply mechanical edits.
2. Serialized to JSON and embedded in the orchestrator's system prompt as a fenced block, so subagents can reason about the vault without additional tool calls (trimmed to samples for prompt-size economy — see `orchestrator._compact_audit_for_prompt`).

## Consequences

- Analyzers are fast (<1 s on a 1,400-note vault), so we can run the audit on every command invocation.
- The LLM never needs to scan the vault itself; it reasons over pre-computed JSON.
- Adding a new check means writing a new analyzer module, not a new subagent prompt.
- The health score (0–100) becomes a natural regression metric: the user can run `vault-agent health` any time to see progress.

## Related

- git-repo-agent ADR-001: same pattern for code repositories.
