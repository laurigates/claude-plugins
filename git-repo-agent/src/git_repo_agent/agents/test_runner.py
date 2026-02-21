"""Test runner subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "test_runner.md").read_text(encoding="utf-8")
    generated = _PROMPTS_DIR / "generated" / "test_runner_skills.md"
    if generated.exists():
        base += "\n\n" + generated.read_text(encoding="utf-8")
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
