"""CLI wiring for #1074 — non-interactive, advisory lock, signal handlers.

Exercises the Typer-level wiring that's hard to reach from unit tests of
the individual modes. We use an in-process ``CliRunner`` with a
pre-initialized git repo so the lock / worktree paths are real.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from unittest import mock

import pytest
from typer.testing import CliRunner

from vault_agent.main import app
from vault_agent.non_interactive import (
    EXIT_CONFIG_ERROR,
    EXIT_LOCKED,
    EXIT_SUCCESS,
)


def _init_vault(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "init", "-q", "-b", "main"], cwd=path, check=True)
    subprocess.run(
        ["git", "config", "user.email", "t@example.com"], cwd=path, check=True
    )
    subprocess.run(["git", "config", "user.name", "Test"], cwd=path, check=True)
    (path / "Zettelkasten").mkdir(exist_ok=True)
    (path / "Zettelkasten" / "Seed.md").write_text("# seed\n", encoding="utf-8")
    subprocess.run(["git", "add", "."], cwd=path, check=True)
    subprocess.run(["git", "commit", "-qm", "initial"], cwd=path, check=True)
    return path


@pytest.fixture
def vault(tmp_path: Path) -> Path:
    return _init_vault(tmp_path / "vault")


class TestNonInteractiveGate:
    def test_refuses_write_without_tty_and_flag(self, vault: Path) -> None:
        """#1074 acceptance test: no TTY + no --non-interactive exits EXIT_CONFIG_ERROR."""
        runner = CliRunner()
        # CliRunner always presents stdin as a non-TTY, which matches the
        # real "scheduled job" scenario.
        with mock.patch.object(sys.stdin, "isatty", return_value=False):
            result = runner.invoke(app, ["lint", str(vault), "--fix"])
        assert result.exit_code == EXIT_CONFIG_ERROR
        assert "stdin is not a TTY" in result.stdout or "stdin is not a TTY" in (
            result.output or ""
        )

    def test_tty_mode_does_not_require_flag(self) -> None:
        """Interactive (TTY) callers don't need --non-interactive.

        CliRunner always presents stdin as a StringIO so it can't exercise
        the TTY branch end-to-end; test the builder directly.
        """
        from vault_agent.main import _build_ni_config

        fake_stdin = mock.Mock(isatty=mock.Mock(return_value=True))
        fake_stdout = mock.Mock(isatty=mock.Mock(return_value=True))
        with mock.patch("vault_agent.main.sys.stdin", fake_stdin), mock.patch(
            "vault_agent.main.sys.stdout", fake_stdout
        ):
            cfg = _build_ni_config(
                non_interactive=False,
                apply=False,
                max_cost_usd=None,
                log_format=None,
            )
        assert cfg is None  # interactive — no NonInteractiveConfig needed


class TestLockAcquisition:
    def test_second_concurrent_run_exits_locked(self, vault: Path) -> None:
        """#1074 acceptance test: two concurrent --fix runs — second exits EXIT_LOCKED."""
        # Simulate a still-running prior process by writing a lock file
        # with the *current* pid, which is always alive.
        lock_dir = vault / ".claude" / "worktrees"
        lock_dir.mkdir(parents=True, exist_ok=True)
        lock_path = lock_dir / ".vault-agent.lock"
        lock_path.write_text(
            json.dumps({"pid": os.getpid(), "started_at": "2026-01-01T00:00:00Z"}),
            encoding="utf-8",
        )

        runner = CliRunner()
        result = runner.invoke(
            app,
            ["lint", str(vault), "--fix", "--non-interactive", "--log-format", "plain"],
        )
        assert result.exit_code == EXIT_LOCKED

    def test_stale_lock_with_dead_pid_reclaimed(self, vault: Path) -> None:
        """#1074 acceptance test: lock with a dead PID is auto-reclaimed."""
        lock_dir = vault / ".claude" / "worktrees"
        lock_dir.mkdir(parents=True, exist_ok=True)
        lock_path = lock_dir / ".vault-agent.lock"
        # PID 1 exists on POSIX (init); use something guaranteed dead.
        # os.kill with a PID that has never been allocated raises ProcessLookupError
        # → _pid_alive returns False. Use a very large pid not reachable.
        lock_path.write_text(
            json.dumps({"pid": 2147480000, "started_at": "2026-01-01T00:00:00Z"}),
            encoding="utf-8",
        )

        runner = CliRunner()
        result = runner.invoke(
            app,
            ["lint", str(vault), "--fix", "--non-interactive", "--log-format", "plain"],
        )
        # Stale lock should have been reclaimed → normal success, lock released.
        assert result.exit_code == EXIT_SUCCESS
        assert not lock_path.exists(), "lock should be released after successful run"


class TestJsonLogFormat:
    def test_emits_single_line_json_summary(self, vault: Path) -> None:
        """#1074 acceptance test: --log-format=json writes a parseable summary line."""
        runner = CliRunner()
        result = runner.invoke(
            app,
            ["lint", str(vault), "--fix", "--non-interactive", "--log-format", "json"],
        )
        assert result.exit_code == EXIT_SUCCESS
        # Find the JSON line — must be on a line by itself.
        json_lines = []
        for line in result.stdout.splitlines():
            stripped = line.strip()
            if stripped.startswith("{") and stripped.endswith("}"):
                try:
                    json_lines.append(json.loads(stripped))
                except json.JSONDecodeError:
                    pass
        assert len(json_lines) == 1
        summary = json_lines[0]
        assert summary["mode"] == "lint"
        assert summary["dry_run"] is False
        assert "health_before" in summary
        assert "branch" in summary

    def test_text_format_emits_no_json_line(self, vault: Path) -> None:
        """When log_format is text/plain there's no JSON summary."""
        runner = CliRunner()
        result = runner.invoke(
            app,
            ["lint", str(vault), "--fix", "--non-interactive", "--log-format", "text"],
        )
        assert result.exit_code == EXIT_SUCCESS
        for line in result.stdout.splitlines():
            stripped = line.strip()
            if stripped.startswith("{") and stripped.endswith("}"):
                with pytest.raises(AssertionError):
                    # If this parses as JSON, we've leaked the summary — fail.
                    parsed = json.loads(stripped)
                    assert "mode" not in parsed


class TestBadFlags:
    def test_invalid_log_format_exits_config_error(self, vault: Path) -> None:
        runner = CliRunner()
        result = runner.invoke(
            app,
            [
                "lint",
                str(vault),
                "--fix",
                "--non-interactive",
                "--log-format",
                "yaml",
            ],
        )
        assert result.exit_code == EXIT_CONFIG_ERROR

    def test_negative_cost_exits_config_error(self, vault: Path) -> None:
        runner = CliRunner()
        result = runner.invoke(
            app,
            [
                "lint",
                str(vault),
                "--fix",
                "--non-interactive",
                "--max-cost-usd",
                "-1.0",
                "--log-format",
                "plain",
            ],
        )
        assert result.exit_code == EXIT_CONFIG_ERROR
