"""Subagent definitions for vault-agent.

Each subagent is an :class:`claude_agent_sdk.AgentDefinition` whose system
prompt is the concatenation of a mode-specific instruction file (under
``prompts/``) and the compiled bundle of SKILL.md files from
obsidian-plugin (see ``prompts/compiler.py``).
"""

from vault_agent.agents.vault_lint import definition as lint_definition
from vault_agent.agents.vault_links import definition as links_definition
from vault_agent.agents.vault_mocs import definition as mocs_definition
from vault_agent.agents.vault_stubs import definition as stubs_definition

ALL_DEFINITIONS = {
    "vault-lint": lint_definition,
    "vault-links": links_definition,
    "vault-stubs": stubs_definition,
    "vault-mocs": mocs_definition,
}

__all__ = [
    "ALL_DEFINITIONS",
    "lint_definition",
    "links_definition",
    "mocs_definition",
    "stubs_definition",
]
