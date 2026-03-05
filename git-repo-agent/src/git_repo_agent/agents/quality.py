"""Quality subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

from git_repo_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "quality.md").read_text(encoding="utf-8")
    skills = get_compiled_prompt("quality")
    if skills:
        base += "\n\n" + skills
    return base


definition = AgentDefinition(
    description=(
        "Code quality analysis. Review code for quality, complexity, duplication, "
        "and adherence to project standards. Provides severity-ranked findings."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Glob", "Grep", "Bash"],
    model="opus",
)
