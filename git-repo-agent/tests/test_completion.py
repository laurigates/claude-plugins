"""Tests for the ``git-repo-agent completion`` subcommand.

Regression coverage for the shellingham-bypass: Typer's
``--install-completion`` / ``--show-completion`` fail with "Shell None is not
supported" when invoked from non-shell parents (Claude Code's node runtime,
CI, Docker). The ``completion`` subcommand takes an explicit shell argument
and uses Click's completion machinery directly.
"""

from __future__ import annotations

from typer.testing import CliRunner

from git_repo_agent.main import app


runner = CliRunner()


def test_completion_zsh_emits_script() -> None:
    result = runner.invoke(app, ["completion", "zsh"])
    assert result.exit_code == 0, result.output
    assert "compdef" in result.output or "_git_repo_agent" in result.output


def test_completion_bash_emits_script() -> None:
    result = runner.invoke(app, ["completion", "bash"])
    assert result.exit_code == 0, result.output
    assert "complete" in result.output


def test_completion_fish_emits_script() -> None:
    result = runner.invoke(app, ["completion", "fish"])
    assert result.exit_code == 0, result.output
    assert "complete" in result.output


def test_completion_unsupported_shell_exits_nonzero() -> None:
    result = runner.invoke(app, ["completion", "tcsh"])
    assert result.exit_code != 0
    assert "not supported" in result.output.lower()
