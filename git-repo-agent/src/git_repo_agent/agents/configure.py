"""Configure subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "configure.md").read_text(encoding="utf-8")
    generated = _PROMPTS_DIR / "generated" / "configure_skills.md"
    if generated.exists():
        base += "\n\n" + generated.read_text(encoding="utf-8")
    return base


definition = AgentDefinition(
    description=(
        "Project standards configuration. Set up linting, formatting, testing, "
        "pre-commit hooks, CI/CD workflows, and code coverage."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    model="haiku",
)
