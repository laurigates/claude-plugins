"""vault-links subagent — broken wikilink repair."""

from __future__ import annotations

from vault_agent.agents._build import _BASE_TOOLS, load_mode_prompt

try:
    from claude_agent_sdk import AgentDefinition  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover
    AgentDefinition = None  # type: ignore[assignment]


_DESCRIPTION = (
    "Repair broken wikilinks. Applies rule-table rewrites (e.g. "
    "[[AnsibleFVH]] → [[Ansible]]), unqualifies [[Kanban/X]] → [[X]], "
    "and reports cross-namespace ambiguous targets for user decision."
)


def _build() -> "AgentDefinition":
    assert AgentDefinition is not None
    return AgentDefinition(
        description=_DESCRIPTION,
        prompt=load_mode_prompt("vault_links.md", "vault-links"),
        tools=list(_BASE_TOOLS),
        model="sonnet",
    )


definition = _build() if AgentDefinition is not None else None
