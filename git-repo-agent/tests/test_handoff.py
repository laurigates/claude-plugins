"""Tests for the Claude Code handoff verb in the selection prompt.

See ``orchestrator.py::_parse_user_choice`` and ``_launch_claude_handoff``.
The handoff path lets the user type ``claude [optional feedback]`` at the
fix-selection prompt, which writes a context file inside the worktree
``.git/`` and launches an interactive ``claude`` session there. Phase 2
is intentionally skipped — the worktree is left intact for the Claude
Code session to own.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass
from pathlib import Path

import pytest

from git_repo_agent import orchestrator
from git_repo_agent.orchestrator import (
    HandoffRequested,
    _launch_claude_handoff,
    _parse_user_choice,
    _stream_interactive,
)


# ---------------------------------------------------------------------------
# _parse_user_choice
# ---------------------------------------------------------------------------


class TestParseUserChoice:
    def test_handoff_bare(self):
        choice = _parse_user_choice("claude")
        assert choice.kind == "handoff"
        assert choice.feedback == ""

    def test_handoff_with_feedback(self):
        choice = _parse_user_choice("claude I want ty not pyright")
        assert choice.kind == "handoff"
        assert choice.feedback == "I want ty not pyright"

    def test_handoff_case_insensitive_upper(self):
        choice = _parse_user_choice("CLAUDE foo")
        assert choice.kind == "handoff"
        assert choice.feedback == "foo"

    def test_handoff_case_insensitive_mixed_with_padding(self):
        choice = _parse_user_choice("  Claude  foo bar  ")
        assert choice.kind == "handoff"
        assert choice.feedback == "foo bar"

    def test_only_first_token_triggers_handoff(self):
        # "1,2,claude" is a regular selection list — the leading token is
        # "1,2,claude" (no whitespace split) but lower() != "claude" so
        # it stays a select. Documents the boundary.
        choice = _parse_user_choice("1,2,claude")
        assert choice.kind == "select"

    def test_select_numbers(self):
        choice = _parse_user_choice("1,3,5")
        assert choice.kind == "select"

    def test_select_all(self):
        # "all" is not a handoff keyword; LLM parses it in Phase 2.
        choice = _parse_user_choice("all")
        assert choice.kind == "select"

    def test_select_yes(self):
        choice = _parse_user_choice("yes")
        assert choice.kind == "select"

    def test_none_keyword(self):
        assert _parse_user_choice("none").kind == "none"

    def test_none_short(self):
        assert _parse_user_choice("n").kind == "none"

    def test_none_no(self):
        assert _parse_user_choice("no").kind == "none"

    def test_none_empty(self):
        assert _parse_user_choice("").kind == "none"

    def test_none_whitespace_only(self):
        assert _parse_user_choice("   ").kind == "none"

    def test_raw_preserved(self):
        choice = _parse_user_choice("1,3,5")
        assert choice.raw == "1,3,5"

    def test_frozen(self):
        choice = _parse_user_choice("claude")
        with pytest.raises(Exception):
            choice.feedback = "mutated"  # type: ignore[misc]


# ---------------------------------------------------------------------------
# _launch_claude_handoff
# ---------------------------------------------------------------------------


@dataclass
class _SubprocessCall:
    args: list[str]
    cwd: Path | None
    check: bool


def _install_subprocess_mock(monkeypatch) -> list[_SubprocessCall]:
    """Replace ``subprocess.run`` inside the orchestrator with a capturing stub."""
    calls: list[_SubprocessCall] = []

    def fake_run(args, cwd=None, check=False, **kwargs):  # type: ignore[no-untyped-def]
        calls.append(_SubprocessCall(args=list(args), cwd=cwd, check=check))
        return None

    monkeypatch.setattr(orchestrator.subprocess, "run", fake_run)
    return calls


def _make_worktree(tmp_path: Path) -> Path:
    worktree = tmp_path / "worktree"
    (worktree / ".git").mkdir(parents=True)
    return worktree


class TestLaunchClaudeHandoff:
    def test_writes_handoff_file_with_phase1_text(self, monkeypatch, tmp_path):
        _install_subprocess_mock(monkeypatch)
        worktree = _make_worktree(tmp_path)

        _launch_claude_handoff(
            phase1_text="1. fix README\n2. add tests",
            feedback="",
            worktree_path=worktree,
            worktree_branch="maintain/2026-05-22",
            workflow="maintain",
        )

        handoff = worktree / ".git" / "git-repo-agent-handoff.md"
        assert handoff.exists()
        content = handoff.read_text()
        assert "1. fix README" in content
        assert "2. add tests" in content
        assert "maintain" in content
        assert "maintain/2026-05-22" in content
        assert "## Suggested actions" in content

    def test_writes_feedback_section_when_present(self, monkeypatch, tmp_path):
        _install_subprocess_mock(monkeypatch)
        worktree = _make_worktree(tmp_path)

        _launch_claude_handoff(
            phase1_text="1. config pyright",
            feedback="I want astral ty for type checking, not pyright",
            worktree_path=worktree,
            worktree_branch="maintain/x",
            workflow="maintain",
        )

        content = (worktree / ".git" / "git-repo-agent-handoff.md").read_text()
        assert "## User feedback" in content
        assert "astral ty" in content

    def test_omits_feedback_section_when_empty(self, monkeypatch, tmp_path):
        _install_subprocess_mock(monkeypatch)
        worktree = _make_worktree(tmp_path)

        _launch_claude_handoff(
            phase1_text="1. anything",
            feedback="",
            worktree_path=worktree,
            worktree_branch=None,
            workflow="onboard",
        )

        content = (worktree / ".git" / "git-repo-agent-handoff.md").read_text()
        assert "## User feedback" not in content
        assert "onboard" in content

    def test_invokes_claude_in_worktree(self, monkeypatch, tmp_path):
        calls = _install_subprocess_mock(monkeypatch)
        worktree = _make_worktree(tmp_path)

        _launch_claude_handoff(
            phase1_text="1. fix",
            feedback="say hi",
            worktree_path=worktree,
            worktree_branch="maintain/2026-05-22",
            workflow="maintain",
        )

        assert len(calls) == 1
        call = calls[0]
        assert call.args[0] == "claude"
        # Single positional prompt arg
        assert len(call.args) == 2
        assert "@.git/git-repo-agent-handoff.md" in call.args[1]
        assert "maintain" in call.args[1]
        assert call.cwd == worktree

    def test_handles_missing_claude_binary(self, monkeypatch, tmp_path, capsys):
        def fake_run(*args, **kwargs):  # type: ignore[no-untyped-def]
            raise FileNotFoundError("claude")

        monkeypatch.setattr(orchestrator.subprocess, "run", fake_run)
        worktree = _make_worktree(tmp_path)

        # Should not raise — graceful fallback message.
        _launch_claude_handoff(
            phase1_text="1. fix",
            feedback="",
            worktree_path=worktree,
            worktree_branch=None,
            workflow="maintain",
        )

        # Handoff file is still written so the user can use it manually.
        assert (worktree / ".git" / "git-repo-agent-handoff.md").exists()

    def test_creates_git_dir_if_missing(self, monkeypatch, tmp_path):
        # If for some reason .git/ doesn't already exist, the helper still
        # creates the parent directory rather than crashing.
        _install_subprocess_mock(monkeypatch)
        worktree = tmp_path / "fresh"
        worktree.mkdir()

        _launch_claude_handoff(
            phase1_text="x",
            feedback="",
            worktree_path=worktree,
            worktree_branch=None,
            workflow="maintain",
        )

        assert (worktree / ".git" / "git-repo-agent-handoff.md").exists()


# ---------------------------------------------------------------------------
# _stream_interactive — handoff branch
# ---------------------------------------------------------------------------


class _FakeSDKClient:
    """Replaces ``ClaudeSDKClient`` so Phase 1 / Phase 2 streaming is mocked.

    The Phase 2 client should never be opened on the handoff path.
    """

    instances: list["_FakeSDKClient"] = []

    def __init__(self, options):
        self.options = options
        self.queries: list[str] = []
        _FakeSDKClient.instances.append(self)

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return False

    async def query(self, prompt: str) -> None:
        self.queries.append(prompt)

    async def receive_response(self):
        from claude_agent_sdk import AssistantMessage, TextBlock

        yield AssistantMessage(
            content=[TextBlock(text="1. fix this\n2. fix that")],
            model="fake-model",
        )


class TestStreamInteractiveHandoff:
    def test_handoff_raises_and_skips_phase2(self, monkeypatch, tmp_path):
        _FakeSDKClient.instances = []
        monkeypatch.setattr(
            "git_repo_agent.orchestrator.ClaudeSDKClient", _FakeSDKClient,
        )
        # Mock console.input to return the handoff verb.
        monkeypatch.setattr(
            orchestrator.console, "input", lambda _label: "claude feedback here",
        )
        _install_subprocess_mock(monkeypatch)

        worktree = _make_worktree(tmp_path)

        def _build_phase2(_findings, _selection, _branch):
            raise AssertionError("Phase 2 prompt builder must not be called")

        with pytest.raises(HandoffRequested):
            asyncio.run(
                _stream_interactive(
                    "Phase 1 prompt",
                    options=_FakeOptions(),
                    completion_msg="done",
                    user_input_label="select: ",
                    build_phase2_prompt=_build_phase2,
                    workflow="maintain",
                    worktree_path=worktree,
                    worktree_branch="maintain/x",
                )
            )

        # Exactly one ClaudeSDKClient was constructed (Phase 1 only).
        assert len(_FakeSDKClient.instances) == 1

        # Handoff file was written.
        handoff = worktree / ".git" / "git-repo-agent-handoff.md"
        assert handoff.exists()
        content = handoff.read_text()
        assert "feedback here" in content


@dataclass
class _FakeOptions:
    """Minimal ClaudeAgentOptions stand-in for ``replace()`` compatibility."""

    system_prompt: str | None = None
    cwd: str | None = None


# ---------------------------------------------------------------------------
# run_maintain — handoff skips push/PR pipeline
# ---------------------------------------------------------------------------


class TestRunMaintainHandoff:
    def test_handoff_path_skips_pr_creation(self, monkeypatch, tmp_path):
        """Integration-style: simulate the handoff path through run_maintain
        and assert the PR-creation prompt is never reached.
        """
        from git_repo_agent.orchestrator import run_maintain

        # Stub out the heavyweight pre-compute step so the test doesn't run
        # real git/repo analysis.
        monkeypatch.setattr(
            orchestrator,
            "_pre_compute_context",
            lambda _path: "## Pre-computed analysis (stub)",
        )
        monkeypatch.setattr(
            orchestrator, "get_base_branch", lambda _path: "main",
        )

        # create_worktree returns a path we control; subsequent helpers
        # must not be called on the handoff path.
        worktree = _make_worktree(tmp_path)
        monkeypatch.setattr(
            orchestrator,
            "create_worktree",
            lambda _repo, _branch, base_ref=None: worktree,
        )
        monkeypatch.setattr(
            orchestrator, "_snapshot_parent_sha", lambda _path: "deadbeef",
        )

        # The freshness probe shells out to git; stub it for this unit test.
        from git_repo_agent.worktree import BaseFreshness

        monkeypatch.setattr(
            orchestrator,
            "probe_base_freshness",
            lambda _repo, _base: BaseFreshness(
                fetched=False, has_remote=False, behind=0, base_branch=_base,
            ),
        )

        # Track that the PR-creation prompt is never reached.
        pr_called = []

        async def _pr_called(*args, **kwargs):
            pr_called.append(True)

        monkeypatch.setattr(orchestrator, "_prompt_pr_creation", _pr_called)
        monkeypatch.setattr(orchestrator, "_auto_handle_pr", _pr_called)

        # Mock the SDK and console.input
        _FakeSDKClient.instances = []
        monkeypatch.setattr(
            "git_repo_agent.orchestrator.ClaudeSDKClient", _FakeSDKClient,
        )
        monkeypatch.setattr(
            orchestrator.console, "input", lambda _label: "claude",
        )
        _install_subprocess_mock(monkeypatch)

        # run_maintain should return cleanly (no exception, no PR call).
        asyncio.run(run_maintain(tmp_path, fix=False, report_only=False))

        assert pr_called == [], "PR creation must not run on the handoff path"

        # Phase 2 client must not have been opened (only Phase 1).
        assert len(_FakeSDKClient.instances) == 1
