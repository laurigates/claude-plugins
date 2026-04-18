"""Tests for the SDK session loop in orchestrator.run_mode_with_sdk.

Real SDK calls need an auth token and the CLI subprocess, which we don't
want in unit tests. Instead we stub ``ClaudeSDKClient`` with an async
context manager that yields a canned message stream. This exercises the
orchestrator's plumbing (message handling, report extraction, hook
wiring) without touching the network.
"""

from __future__ import annotations

import asyncio
import subprocess
import textwrap
from pathlib import Path
from unittest import mock

import pytest

from vault_agent.analyzers.audit import run_audit
from vault_agent.orchestrator import (
    _extract_report_section,
    _has_sdk_work,
    _build_safety_hook_callback,
    build_system_prompt,
)


def _init_repo(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=path, check=True)
    subprocess.run(
        ["git", "config", "user.email", "t@e"], cwd=path, check=True
    )
    subprocess.run(["git", "config", "user.name", "T"], cwd=path, check=True)
    (path / "seed.md").write_text("# seed\n")
    subprocess.run(["git", "add", "."], cwd=path, check=True)
    subprocess.run(["git", "commit", "-qm", "init"], cwd=path, check=True)
    return path


def _make_vault(tmp_path: Path, files: dict[str, str]) -> Path:
    for rel, content in files.items():
        (tmp_path / rel).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / rel).write_text(
            textwrap.dedent(content).lstrip("\n"), encoding="utf-8"
        )
    return tmp_path


class TestExtractReportSection:
    def test_extracts_run_summary_block(self) -> None:
        collected = [
            "Plan: lint 3 categories.",
            "Completed.\n## Run summary\n- Mode: lint\n- Branch: foo\n- Commits: 2",
        ]
        out = _extract_report_section(collected)
        assert out.startswith("## Run summary")
        assert "Commits: 2" in out

    def test_stops_at_next_top_level_heading(self) -> None:
        collected = [
            "## Run summary\n- Mode: lint\n\n## Next steps\n- Review the diff."
        ]
        out = _extract_report_section(collected)
        assert "Mode: lint" in out
        assert "Next steps" not in out

    def test_returns_empty_when_no_summary(self) -> None:
        assert _extract_report_section(["no summary here"]) == ""


class TestHasSdkWork:
    def test_lint_never_has_sdk_work(self, tmp_path: Path) -> None:
        vault = _make_vault(tmp_path, {"Zettelkasten/A.md": "# a\n"})
        audit = run_audit(vault)
        assert _has_sdk_work("lint", audit) is False

    def test_mocs_has_work_when_categories_have_orphans(
        self, tmp_path: Path
    ) -> None:
        # Build a vault that has orphan notes with emoji tags but no MOC.
        files = {}
        for i in range(15):
            files[f"Zettelkasten/Note{i:02d}.md"] = (
                "---\ntags:\n  - 🔌/iot\n---\n# Note\n"
            )
        vault = _make_vault(tmp_path, files)
        audit = run_audit(vault)
        # If any coverage row has orphans → SDK work
        if any(
            cov.unlinked_note_count > 0 for cov in audit.mocs.coverage_by_category
        ):
            assert _has_sdk_work("mocs", audit) is True

    def test_unknown_mode_returns_false(self, tmp_path: Path) -> None:
        vault = _make_vault(tmp_path, {"Zettelkasten/A.md": "# a\n"})
        audit = run_audit(vault)
        assert _has_sdk_work("unknown", audit) is False


class TestSafetyHookCallback:
    def test_allows_safe_write(self) -> None:
        cb = _build_safety_hook_callback()
        result = asyncio.run(
            cb(
                {
                    "tool_name": "Write",
                    "tool_input": {"file_path": "Zettelkasten/Note.md"},
                },
                None,
                {"signal": None},
            )
        )
        assert result == {}

    def test_blocks_protected_path(self) -> None:
        from vault_agent.non_interactive import HookBlockedError

        cb = _build_safety_hook_callback()
        with pytest.raises(HookBlockedError) as exc_info:
            asyncio.run(
                cb(
                    {
                        "tool_name": "Write",
                        "tool_input": {"file_path": ".obsidian/config.json"},
                    },
                    None,
                    {"signal": None},
                )
            )
        assert ".obsidian" in str(exc_info.value)

    def test_blocks_git_push(self) -> None:
        from vault_agent.non_interactive import HookBlockedError

        cb = _build_safety_hook_callback()
        with pytest.raises(HookBlockedError):
            asyncio.run(
                cb(
                    {"tool_name": "Bash", "tool_input": {"command": "git push origin main"}},
                    None,
                    {"signal": None},
                )
            )


class TestRunModeWithSdkSmoke:
    """End-to-end smoke test stubbing ``ClaudeSDKClient``.

    Verifies: (a) options are built with the right agents+hooks, (b) the
    message stream is consumed, (c) ``## Run summary`` is extracted.
    """

    def test_stubbed_session_extracts_report(self, tmp_path: Path) -> None:
        vault = _init_repo(tmp_path / "vault")
        (vault / "Zettelkasten").mkdir(exist_ok=True)
        (vault / "Zettelkasten" / "A.md").write_text("# a\n", encoding="utf-8")
        subprocess.run(["git", "add", "."], cwd=vault, check=True)
        subprocess.run(["git", "commit", "-qm", "seed"], cwd=vault, check=True)

        # Build a fake SDK message stream.
        from types import SimpleNamespace

        class FakeTextBlock:
            def __init__(self, text: str) -> None:
                self.text = text

        class FakeAssistantMessage:
            def __init__(self, text: str) -> None:
                self.content = [FakeTextBlock(text)]

        class FakeResultMessage:
            def __init__(self) -> None:
                self.is_error = False
                self.result = None
                self.total_cost_usd = 0.0
                self.subtype = "success"

        class FakeClient:
            def __init__(self, options) -> None:
                self.options = options
                # Record for assertions later via closure.
                captured["options"] = options

            async def __aenter__(self):
                return self

            async def __aexit__(self, *exc):
                return None

            async def query(self, prompt):
                captured["prompt"] = prompt

            async def receive_response(self):
                yield FakeAssistantMessage("Plan: lint 2 categories.\n")
                yield FakeAssistantMessage(
                    "Complete.\n## Run summary\n- Mode: stubs\n- Commits: 0\n"
                )
                yield FakeResultMessage()

        captured: dict = {}

        # Make the fake client importable as
        # `claude_agent_sdk.ClaudeSDKClient` for the duration of the test.
        # Also stub AssistantMessage / TextBlock / ResultMessage so
        # isinstance() in _display_message succeeds.
        import claude_agent_sdk

        with mock.patch.object(
            claude_agent_sdk, "ClaudeSDKClient", FakeClient
        ), mock.patch.object(
            claude_agent_sdk, "AssistantMessage", FakeAssistantMessage
        ), mock.patch.object(
            claude_agent_sdk, "TextBlock", FakeTextBlock
        ), mock.patch.object(
            claude_agent_sdk, "ResultMessage", FakeResultMessage
        ):
            from vault_agent.orchestrator import run_mode_with_sdk

            result = asyncio.run(
                run_mode_with_sdk(vault, "stubs", apply=False, console=mock.Mock())
            )

        assert result.mode == "stubs"
        assert result.dry_run is True
        assert "## Run summary" in result.report_section
        assert "Mode: stubs" in result.report_section

        # Verify the options were built with the expected agents + hooks.
        opts = captured["options"]
        assert set(opts.agents.keys()) == {
            "vault-lint",
            "vault-links",
            "vault-stubs",
            "vault-mocs",
        }
        assert "PreToolUse" in opts.hooks
        # The matcher should cover writes + bash.
        hook_matchers = opts.hooks["PreToolUse"]
        assert any("Write" in m.matcher for m in hook_matchers)
