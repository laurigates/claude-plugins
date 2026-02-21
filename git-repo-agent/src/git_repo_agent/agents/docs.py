"""Docs subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "docs.md").read_text(encoding="utf-8")
    generated = _PROMPTS_DIR / "generated" / "docs_skills.md"
    if generated.exists():
        base += "\n\n" + generated.read_text(encoding="utf-8")
    return base


definition = AgentDefinition(
    description=(
        "Documentation health. Check freshness, accuracy, completeness of "
        "README, CLAUDE.md, API docs, and blueprint documents."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Write", "Edit", "Glob", "Grep"],
    model="haiku",
)
