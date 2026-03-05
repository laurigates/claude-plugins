"""Docs subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

from git_repo_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "docs.md").read_text(encoding="utf-8")
    skills = get_compiled_prompt("docs")
    if skills:
        base += "\n\n" + skills
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
