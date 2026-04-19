"""Claude Agent SDK safety hooks for vault-agent."""

from vault_agent.hooks.safety import (
    SAFETY_HOOK_NAME,
    SafetyDecision,
    validate_tool_use,
)

__all__ = ["SAFETY_HOOK_NAME", "SafetyDecision", "validate_tool_use"]
