"""Blueprint subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

_PROMPT_PATH = Path(__file__).parent.parent / "prompts" / "blueprint.md"


def _load_prompt() -> str:
    return _PROMPT_PATH.read_text(encoding="utf-8")


definition = AgentDefinition(
    description=(
        "Blueprint lifecycle management. Initialize, derive, sync, and maintain "
        "blueprint artifacts (PRDs, ADRs, PRPs, work orders, manifest). "
        "Use this agent to set up or update the docs/blueprint/ directory structure."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Write", "Edit", "Bash", "Glob", "Grep"],
    model="sonnet",
)
