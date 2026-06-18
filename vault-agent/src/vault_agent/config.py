"""Vault layout conventions — overridable, with generic defaults.

A small bundle of the vault-specific conventions the analyzers and fixers
depend on. The defaults work on any Obsidian vault; a vault that uses a
work-namespace subtree, a custom daily-notes layout, or a known
broken-link rewrite table can override them.

Override mechanism: a ``.vault-agent.toml`` file in the vault root (or the
path named by ``$VAULT_AGENT_CONFIG``). Example::

    [vault]
    work_namespace = ["work", "z"]
    context_value = "work"
    daily_dirs = [["Notes"], ["work", "notes"]]

    [vault.broken_link_rewrites]
    OldTopic = "Topic"
"""

from __future__ import annotations

import os
import tomllib
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path

_CONFIG_FILENAME = ".vault-agent.toml"


@dataclass(frozen=True)
class VaultConfig:
    """Vault conventions threaded into the analyzers and fixers."""

    # Work-namespace subtree holding redirect stubs (e.g. ``work/z``).
    work_namespace: tuple[str, ...] = ("work", "z")
    # Frontmatter ``context:`` value required on work-namespace notes.
    context_value: str = "work"
    # Directories whose notes are daily notes (few backlinks expected).
    daily_dirs: tuple[tuple[str, ...], ...] = (("Notes",), ("work", "notes"))
    # Broken-wikilink rewrite table: old target → canonical target.
    broken_link_rewrites: Mapping[str, str] = field(default_factory=dict)

    @property
    def namespace_root(self) -> str:
        """First path part of the work namespace (e.g. ``work``)."""
        return self.work_namespace[0] if self.work_namespace else ""


DEFAULT_CONFIG = VaultConfig()


def _config_path(vault_root: Path | str | None) -> Path | None:
    """Resolve the config-file path from ``$VAULT_AGENT_CONFIG`` or the vault root."""
    env = os.environ.get("VAULT_AGENT_CONFIG")
    if env:
        return Path(env).expanduser()
    if vault_root is None:
        return None
    return Path(vault_root).expanduser() / _CONFIG_FILENAME


def _from_mapping(data: Mapping[str, object]) -> VaultConfig:
    """Build a :class:`VaultConfig` from a parsed TOML mapping.

    Accepts either a top-level mapping or one nested under a ``[vault]``
    table. Unknown keys are ignored; omitted keys keep their default.
    """
    vault = data.get("vault", data)
    if not isinstance(vault, Mapping):
        vault = data
    kwargs: dict[str, object] = {}
    if "work_namespace" in vault:
        kwargs["work_namespace"] = tuple(vault["work_namespace"])
    if "context_value" in vault:
        kwargs["context_value"] = str(vault["context_value"])
    if "daily_dirs" in vault:
        kwargs["daily_dirs"] = tuple(tuple(d) for d in vault["daily_dirs"])
    if "broken_link_rewrites" in vault:
        kwargs["broken_link_rewrites"] = dict(vault["broken_link_rewrites"])
    return VaultConfig(**kwargs)  # type: ignore[arg-type]


def load_config(vault_root: Path | str | None = None) -> VaultConfig:
    """Load vault conventions from a config file, or return generic defaults.

    Looks for ``$VAULT_AGENT_CONFIG`` first, then ``.vault-agent.toml`` in
    ``vault_root``. Returns :data:`DEFAULT_CONFIG` when no file is found.
    """
    path = _config_path(vault_root)
    if path is None or not path.is_file():
        return DEFAULT_CONFIG
    with path.open("rb") as fh:
        data = tomllib.load(fh)
    return _from_mapping(data)
