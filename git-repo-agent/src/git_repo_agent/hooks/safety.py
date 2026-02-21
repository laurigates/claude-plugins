"""Safety hooks — block dangerous operations in subagent execution.

These hooks are registered as PreToolUse validators in the orchestrator
to prevent subagents from performing destructive operations.
"""

from __future__ import annotations

import re
from dataclasses import dataclass


@dataclass
class HookResult:
    """Result of a safety hook check."""

    allowed: bool
    reason: str = ""


# Directories that rm -rf is allowed on (build artifacts)
SAFE_RM_DIRS = frozenset({
    "node_modules",
    "dist",
    "build",
    ".venv",
    "venv",
    "__pycache__",
    ".cache",
    ".next",
    ".nuxt",
    "target",  # Rust
    "coverage",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
})

# File patterns that should never be written/edited
SENSITIVE_FILE_PATTERNS = [
    re.compile(r"\.env($|\.)"),
    re.compile(r"credentials", re.IGNORECASE),
    re.compile(r".*\.pem$"),
    re.compile(r".*\.key$"),
    re.compile(r".*\.p12$"),
    re.compile(r".*\.pfx$"),
    re.compile(r".*_rsa$"),
    re.compile(r".*_ecdsa$"),
    re.compile(r".*_ed25519$"),
]

# Protected branches
PROTECTED_BRANCHES = frozenset({"main", "master", "production", "release"})


def check_bash_command(command: str) -> HookResult:
    """Check a Bash command for dangerous operations."""
    # Block force-push to protected branches
    if re.search(r"git\s+push\s+.*(-f|--force)", command):
        # Check if targeting a protected branch
        for branch in PROTECTED_BRANCHES:
            if branch in command:
                return HookResult(
                    allowed=False,
                    reason=f"Force-push to {branch} is blocked. "
                    "Use a regular push or create a PR instead.",
                )
        # Force-push to non-protected branches gets a warning but is allowed
        return HookResult(allowed=True)

    # Block rm -rf on non-build directories
    rm_match = re.search(r"rm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\s+(.+)", command)
    if not rm_match:
        rm_match = re.search(r"rm\s+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*\s+(.+)", command)
    if rm_match:
        target = rm_match.group(1).strip().rstrip("/")
        target_base = target.split("/")[-1] if "/" in target else target
        if target_base not in SAFE_RM_DIRS:
            return HookResult(
                allowed=False,
                reason=f"rm -rf on '{target}' is blocked. "
                f"Only allowed on build artifact directories: {', '.join(sorted(SAFE_RM_DIRS))}",
            )

    return HookResult(allowed=True)


def check_file_write(file_path: str) -> HookResult:
    """Check if a file path is safe to write/edit."""
    from pathlib import PurePosixPath

    filename = PurePosixPath(file_path).name

    for pattern in SENSITIVE_FILE_PATTERNS:
        if pattern.search(filename):
            return HookResult(
                allowed=False,
                reason=f"Writing to '{filename}' is blocked. "
                "Sensitive files (.env, credentials, private keys) "
                "must not be modified by automated agents.",
            )

    return HookResult(allowed=True)


def validate_tool_use(tool_name: str, tool_input: dict) -> HookResult:
    """Validate a tool use request against safety rules.

    This is the main entry point called by the orchestrator's hook system.
    """
    if tool_name == "Bash":
        command = tool_input.get("command", "")
        return check_bash_command(command)

    if tool_name in ("Write", "Edit"):
        file_path = tool_input.get("file_path", "")
        return check_file_write(file_path)

    return HookResult(allowed=True)
