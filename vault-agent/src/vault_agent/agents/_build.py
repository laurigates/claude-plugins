"""Shared factory for building subagent definitions."""

from __future__ import annotations

from pathlib import Path

from vault_agent.prompts.compiler import get_compiled_prompt

_PROMPTS_DIR = Path(__file__).parent.parent / "prompts"

# Tools every subagent needs. Writes go to files via Edit/Write; reads via
# Read/Grep/Glob; commits via Bash. Todo tools are unavailable on
# Opus 4.8+/Sonnet 5/Fable (Claude Code 2.1.233) without
# CLAUDE_CODE_ENABLE_TODO_TOOLS=1; the mode prompts batch fixes by rule
# group in prose instead.
_BASE_TOOLS: tuple[str, ...] = (
    "Read",
    "Edit",
    "Write",
    "Bash",
    "Grep",
    "Glob",
)


def load_mode_prompt(prompt_filename: str, subagent_name: str) -> str:
    """Combine the mode-specific prompt with its compiled skill bundle."""
    base = (_PROMPTS_DIR / prompt_filename).read_text(encoding="utf-8")
    compiled = get_compiled_prompt(subagent_name)
    if compiled:
        base += "\n\n---\n\n" + compiled
    return base
