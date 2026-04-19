"""PreToolUse safety hooks for vault-agent.

The agent runs inside an isolated git worktree, but a mistake still
costs minutes of review. These hooks block high-blast-radius operations
up front:

  * writes to Obsidian's own state (``.obsidian/``)
  * writes to Claude / git metadata (``.claude/``, ``.git/``)
  * writes to media / build output (``Files/``, ``*/_site/``, ``node_modules/``)
  * ``rm -rf`` outside whitelisted scratch directories
  * ``git push`` (vault-agent runs on a local branch; never pushes)
  * ``git reset --hard``, ``git checkout -- .`` (destructive)

Pure-Python so it can be unit-tested without the SDK. The function's
shape matches ``claude_agent_sdk.HookMatcher`` expectations.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any

SAFETY_HOOK_NAME = "vault-agent-safety"

# Path segments that are never writable by the agent.
PROTECTED_DIR_SEGMENTS: frozenset[str] = frozenset(
    {
        ".obsidian",
        ".claude",
        ".git",
        "node_modules",
        "_site",
        "__pycache__",
    }
)

# Top-level directories that are non-note assets; the agent may read them but
# never write. ``Files/`` holds Obsidian attachments.
PROTECTED_TOP_DIRS: frozenset[str] = frozenset({"Files"})

# Scratch dirs where rm -rf is allowed (mainly for processed/ folders).
RM_RF_ALLOWLIST_SEGMENTS: frozenset[str] = frozenset(
    {"tmp", "__pycache__", "processed"}
)

# Bash patterns that are always blocked.
_BLOCKED_BASH_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"\bgit\s+push\b"),
    re.compile(r"\bgit\s+reset\s+--hard\b"),
    re.compile(r"\bgit\s+checkout\s+--?\s*\.\b"),
    re.compile(r"\bgit\s+restore\s+--source\b"),
    re.compile(r"\bgit\s+clean\s+-[a-zA-Z]*f"),
)

# rm -rf detection (non-anchored).
_RM_RF_RE = re.compile(r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f\b|\brm\s+-[a-zA-Z]*f[a-zA-Z]*r\b")


@dataclass(frozen=True)
class SafetyDecision:
    """Result of a hook evaluation."""

    allow: bool
    reason: str  # human-readable; empty when allow=True

    @classmethod
    def ok(cls) -> "SafetyDecision":
        return cls(allow=True, reason="")

    @classmethod
    def block(cls, reason: str) -> "SafetyDecision":
        return cls(allow=False, reason=reason)


# ---------------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------------


def _path_touches_protected(path: str) -> str | None:
    """Return the offending segment if ``path`` is under a protected dir."""
    parts = [p for p in path.replace("\\", "/").split("/") if p and p != "."]
    for segment in parts:
        if segment in PROTECTED_DIR_SEGMENTS or segment in PROTECTED_TOP_DIRS:
            return segment
    return None


def _rm_rf_allowed(command: str) -> bool:
    """True if every rm target is inside the allowlist."""
    # Very cheap: require that at least one allowlisted segment appears
    # after the rm invocation. Not a full shell parser, but conservative.
    for seg in RM_RF_ALLOWLIST_SEGMENTS:
        if f"/{seg}/" in command or command.endswith(f"/{seg}") or f" {seg}/" in command:
            return True
    return False


# ---------------------------------------------------------------------------
# Per-tool validators
# ---------------------------------------------------------------------------


def _check_file_write(tool_input: dict[str, Any]) -> SafetyDecision:
    """Block writes to protected paths. Handles Write / Edit / NotebookEdit."""
    candidates = [
        tool_input.get("file_path"),
        tool_input.get("notebook_path"),
    ]
    for raw in candidates:
        if not raw:
            continue
        offending = _path_touches_protected(str(raw))
        if offending:
            return SafetyDecision.block(
                f"refusing to write under protected path segment '{offending}' ({raw})"
            )
    return SafetyDecision.ok()


def _check_bash(tool_input: dict[str, Any]) -> SafetyDecision:
    """Block destructive bash invocations."""
    command = str(tool_input.get("command", "") or "")
    if not command.strip():
        return SafetyDecision.ok()

    for pat in _BLOCKED_BASH_PATTERNS:
        if pat.search(command):
            return SafetyDecision.block(
                f"blocked destructive git invocation: {pat.pattern}"
            )

    if _RM_RF_RE.search(command):
        if not _rm_rf_allowed(command):
            return SafetyDecision.block(
                "blocked 'rm -rf' outside allowlisted scratch directories "
                f"({sorted(RM_RF_ALLOWLIST_SEGMENTS)})"
            )
    return SafetyDecision.ok()


# Mapping tool name → validator.
_TOOL_VALIDATORS = {
    "Write": _check_file_write,
    "Edit": _check_file_write,
    "NotebookEdit": _check_file_write,
    "Bash": _check_bash,
}


def validate_tool_use(
    tool_name: str, tool_input: dict[str, Any]
) -> SafetyDecision:
    """Return SafetyDecision for a PreToolUse event.

    Unknown tools are allowed by default — we only guard the ones that
    can mutate the vault or the repository.
    """
    validator = _TOOL_VALIDATORS.get(tool_name)
    if validator is None:
        return SafetyDecision.ok()
    return validator(tool_input or {})
