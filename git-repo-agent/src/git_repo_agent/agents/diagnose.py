"""Diagnose subagent definition."""

from pathlib import Path

from claude_agent_sdk import AgentDefinition

from git_repo_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"


def _load_prompt() -> str:
    base = (_PROMPTS_DIR / "diagnose.md").read_text(encoding="utf-8")
    skills = get_compiled_prompt("diagnose")
    if skills:
        base += "\n\n" + skills
    return base


definition = AgentDefinition(
    description=(
        "GitOps pipeline diagnostics. Analyze deployment failures, correlate "
        "errors across kubectl, ArgoCD, GitHub Actions, Sentry, and browser "
        "console. Produce structured diagnostic reports."
    ),
    prompt=_load_prompt(),
    tools=["Read", "Glob", "Grep", "Bash"],
    model="sonnet",
)
