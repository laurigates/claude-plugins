"""vault-lint subagent — mechanical frontmatter & tag fixes."""

from __future__ import annotations

from vault_agent.agents._build import _BASE_TOOLS, load_mode_prompt

try:
    from claude_agent_sdk import AgentDefinition  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover - SDK optional for tests
    AgentDefinition = None  # type: ignore[assignment]


_DESCRIPTION = (
    "Mechanical frontmatter repair: strip legacy `id:` fields, remove bare "
    "placeholder tags (`📝`, `🌱`), rewrite legacy `🗺️` to `📝/moc`, remove "
    "`null` tag entries, strip unrendered Templater markers. Zero content "
    "judgment."
)


def _build() -> "AgentDefinition":
    assert AgentDefinition is not None, "claude-agent-sdk is required"
    return AgentDefinition(
        description=_DESCRIPTION,
        prompt=load_mode_prompt("vault_lint.md", "vault-lint"),
        tools=list(_BASE_TOOLS),
        model="haiku",
    )


definition = _build() if AgentDefinition is not None else None
