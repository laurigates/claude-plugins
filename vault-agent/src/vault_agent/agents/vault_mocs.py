"""vault-mocs subagent — Map-of-Content curation."""

from __future__ import annotations

from vault_agent.agents._build import _BASE_TOOLS, load_mode_prompt

try:
    from claude_agent_sdk import AgentDefinition  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover
    AgentDefinition = None  # type: ignore[assignment]


_DESCRIPTION = (
    "Curate Maps of Content: propose new MOCs for categories with "
    "many orphaned notes, extend existing MOCs with tag-matched "
    "orphans, and fix MOC convention drift (🗺️ → 📝/moc, "
    "[[Kanban/X]] → [[X]])."
)


def _build() -> "AgentDefinition":
    assert AgentDefinition is not None
    return AgentDefinition(
        description=_DESCRIPTION,
        prompt=load_mode_prompt("vault_mocs.md", "vault-mocs"),
        tools=list(_BASE_TOOLS),
        model="opus",
    )


definition = _build() if AgentDefinition is not None else None
