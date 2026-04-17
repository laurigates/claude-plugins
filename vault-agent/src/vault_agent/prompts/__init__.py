"""Prompt compilation and loading for vault-agent subagents."""

from vault_agent.prompts.compiler import (
    SUBAGENT_SKILLS,
    compile_skill,
    compile_subagent,
    get_compiled_prompt,
    get_compiled_skill,
)

__all__ = [
    "SUBAGENT_SKILLS",
    "compile_skill",
    "compile_subagent",
    "get_compiled_prompt",
    "get_compiled_skill",
]
