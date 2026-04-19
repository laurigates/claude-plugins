"""Deterministic, LLM-free fixers for the vault.

These modules perform mechanical transformations that don't require
judgment: strip a field, normalize a tag, remove an unrendered template
marker. They're fast, idempotent, and safe to run inside a worktree.

The LLM-backed modes (vault-stubs, vault-mocs) handle the judgment cases.
"""

from vault_agent.fixers.id_stripper import strip_legacy_id
from vault_agent.fixers.tag_normalizer import normalize_tags
from vault_agent.fixers.templater_cleaner import clean_templater_leakage

__all__ = [
    "strip_legacy_id",
    "normalize_tags",
    "clean_templater_leakage",
]
