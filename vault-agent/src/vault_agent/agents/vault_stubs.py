"""vault-stubs subagent — FVH/z redirect stub consolidation."""

from __future__ import annotations

from vault_agent.agents._build import _BASE_TOOLS, load_mode_prompt

try:
    from claude_agent_sdk import AgentDefinition  # type: ignore[import-untyped]
except ImportError:  # pragma: no cover
    AgentDefinition = None  # type: ignore[assignment]


_DESCRIPTION = (
    "Classify FVH/z/ files (clean_redirect / broken_redirect / "
    "stale_duplicate / fvh_original) and consolidate stale duplicates "
    "into redirect stubs pointing to Zettelkasten canonical notes, "
    "merging unique content first."
)


def _build() -> "AgentDefinition":
    assert AgentDefinition is not None
    return AgentDefinition(
        description=_DESCRIPTION,
        prompt=load_mode_prompt("vault_stubs.md", "vault-stubs"),
        tools=list(_BASE_TOOLS),
        model="sonnet",
    )


definition = _build() if AgentDefinition is not None else None
