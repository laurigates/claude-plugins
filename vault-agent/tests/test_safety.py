"""Unit tests for safety hooks."""

from __future__ import annotations

import pytest

from vault_agent.hooks.safety import SafetyDecision, validate_tool_use


class TestFileWriteHook:
    def test_allows_plain_note_write(self) -> None:
        decision = validate_tool_use(
            "Write", {"file_path": "/vault/Zettelkasten/Note.md"}
        )
        assert decision.allow

    def test_blocks_obsidian_config(self) -> None:
        decision = validate_tool_use(
            "Write", {"file_path": "/vault/.obsidian/workspace.json"}
        )
        assert not decision.allow
        assert ".obsidian" in decision.reason

    def test_blocks_claude_dir(self) -> None:
        decision = validate_tool_use(
            "Edit", {"file_path": "/vault/.claude/rules/override.md"}
        )
        assert not decision.allow

    def test_blocks_git_internals(self) -> None:
        decision = validate_tool_use(
            "Write", {"file_path": "/vault/.git/HEAD"}
        )
        assert not decision.allow

    def test_blocks_files_dir(self) -> None:
        decision = validate_tool_use(
            "Write", {"file_path": "/vault/Files/Pasted image.png"}
        )
        assert not decision.allow
        assert "Files" in decision.reason

    def test_blocks_site_build_output(self) -> None:
        decision = validate_tool_use(
            "Write", {"file_path": "/vault/radio-hacking/_site/index.html"}
        )
        assert not decision.allow


class TestBashHook:
    def test_allows_git_status(self) -> None:
        decision = validate_tool_use("Bash", {"command": "git status"})
        assert decision.allow

    def test_blocks_git_push(self) -> None:
        decision = validate_tool_use(
            "Bash", {"command": "git push origin main"}
        )
        assert not decision.allow
        assert "push" in decision.reason

    def test_blocks_reset_hard(self) -> None:
        decision = validate_tool_use(
            "Bash", {"command": "git reset --hard HEAD~5"}
        )
        assert not decision.allow

    def test_blocks_rm_rf_on_vault(self) -> None:
        decision = validate_tool_use(
            "Bash", {"command": "rm -rf /vault/Zettelkasten"}
        )
        assert not decision.allow
        assert "rm" in decision.reason.lower()

    def test_allows_rm_rf_in_tmp(self) -> None:
        decision = validate_tool_use(
            "Bash", {"command": "rm -rf /vault/tmp/scratch"}
        )
        assert decision.allow

    def test_allows_rm_rf_in_pycache(self) -> None:
        decision = validate_tool_use(
            "Bash", {"command": "rm -rf src/__pycache__"}
        )
        assert decision.allow

    def test_allows_rm_rf_processed(self) -> None:
        decision = validate_tool_use(
            "Bash",
            {"command": "rm -rf Inbox/ChatExport_2025-11-13/processed"},
        )
        assert decision.allow

    def test_blocks_git_clean_f(self) -> None:
        decision = validate_tool_use("Bash", {"command": "git clean -fd"})
        assert not decision.allow


class TestUnknownToolPassthrough:
    def test_unknown_tool_allowed(self) -> None:
        decision = validate_tool_use("RandomTool", {"anything": True})
        assert decision.allow
