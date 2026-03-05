"""Security subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

from git_repo_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "security.md").read_text(encoding="utf-8")
    skills = get_compiled_prompt("security")
    if skills:
        base += "\n\n" + skills
    return base


definition = AgentDefinition(
    description=(
        "Security audit. Scan for exposed secrets, dependency vulnerabilities, "
        "injection risks, and insecure configurations."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Glob", "Grep", "Bash"],
    model="opus",
)
