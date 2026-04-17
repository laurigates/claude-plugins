"""Pure-Python analyzers for Obsidian vaults.

Each analyzer operates on the filesystem (no LLM, no running Obsidian
instance required) and emits JSON-serializable dataclasses. Results are
aggregated into a single VaultAudit by ``audit.run_audit``.

Analyzers share a ``VaultIndex`` built once by ``vault_index.scan``.
"""

from vault_agent.analyzers.vault_index import VaultIndex, scan

__all__ = ["VaultIndex", "scan"]
