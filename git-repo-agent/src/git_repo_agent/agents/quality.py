"""Quality subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "quality.md").read_text(encoding="utf-8")
    generated = _PROMPTS_DIR / "generated" / "quality_skills.md"
    if generated.exists():
        base += "\n\n" + generated.read_text(encoding="utf-8")
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
