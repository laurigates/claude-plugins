"""Test runner subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

from git_repo_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "test_runner.md").read_text(encoding="utf-8")
    skills = get_compiled_prompt("test_runner")
    if skills:
        base += "\n\n" + skills
    return base


definition = AgentDefinition(
    description=(
        "Run tests and report results. Detects framework, executes with "
        "optimized flags, returns concise pass/fail summary."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Glob", "Grep", "Bash"],
    model="haiku",
)
