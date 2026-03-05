"""Configure subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

from git_repo_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "configure.md").read_text(encoding="utf-8")
    skills = get_compiled_prompt("configure")
    if skills:
        base += "\n\n" + skills
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
