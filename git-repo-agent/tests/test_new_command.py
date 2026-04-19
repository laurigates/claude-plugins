"""End-to-end tests for the ``git-repo-agent new`` CLI command.

These exercise the command through Typer's ``CliRunner`` so flag parsing,
validation, and the spec-building pipeline are covered together. Tests
either use ``--dry-run`` (no filesystem or network side effects) or
point at ``tmp_path`` with ``--skip-blueprint --no-remote`` so the only
side effect is a local repo that the tmpdir fixture cleans up.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest
from typer.testing import CliRunner

from git_repo_agent.main import app


runner = CliRunner()


class TestNewDryRun:
    def test_prints_plan_without_side_effects(self, tmp_path: Path):
        result = runner.invoke(
            app,
            [
                "new", "Just an idea",
                "--name", "My Cool Project",
                "--language", "python",
                "--stack-indicators", "github-actions",
                "--parent-dir", str(tmp_path),
                "--no-remote",
                "--dry-run",
            ],
        )
        assert result.exit_code == 0, result.output
        assert "DRY RUN" in result.output
        assert "python-plugin" in result.output
        assert "github-actions-plugin" in result.output
        # No directory was actually created.
        assert not (tmp_path / "my-cool-project").exists()

    def test_unknown_language_rejected(self, tmp_path: Path):
        result = runner.invoke(
            app,
            [
                "new", "idea",
                "--name", "x",
                "--language", "cobol",
                "--parent-dir", str(tmp_path),
                "--no-remote", "--dry-run",
            ],
        )
        assert result.exit_code == 2
        assert "--language" in result.output

    def test_unknown_visibility_rejected(self, tmp_path: Path):
        result = runner.invoke(
            app,
            [
                "new", "idea",
                "--name", "x",
                "--visibility", "secret",
                "--parent-dir", str(tmp_path),
                "--no-remote", "--dry-run",
            ],
        )
        assert result.exit_code == 2
        assert "--visibility" in result.output

    def test_missing_parent_dir_rejected(self):
        result = runner.invoke(
            app,
            [
                "new", "idea",
                "--name", "x", "--language", "python",
                "--parent-dir", "/nonexistent/does/not/exist",
                "--no-remote", "--dry-run",
            ],
        )
        assert result.exit_code == 2
        assert "parent-dir" in result.output.lower()


class TestNewFullGenesis:
    """Runs the real genesis pipeline, skipping blueprint-init + remote push.

    Covers the PR 1 happy path end-to-end: CLI → creator → commit on main.
    Blueprint-init would require spawning a real ClaudeSDKClient, so we
    skip it here and cover that code path via unit tests separately.
    """

    def test_creates_local_repo_with_initial_commit(self, tmp_path: Path):
        result = runner.invoke(
            app,
            [
                "new", "A small CLI that does a thing",
                "--name", "Small CLI",
                "--language", "python",
                "--stack-indicators", "github-actions",
                "--parent-dir", str(tmp_path),
                "--no-remote",
                "--skip-blueprint",
            ],
        )
        assert result.exit_code == 0, result.output

        repo = tmp_path / "small-cli"
        assert (repo / ".git").is_dir()
        assert (repo / "README.md").is_file()
        assert (repo / "docs" / "prds" / "0001-project-goal.md").is_file()

        settings = json.loads(
            (repo / ".claude" / "settings.json").read_text(encoding="utf-8")
        )
        assert "claude-plugins" in settings["extraKnownMarketplaces"]
        assert "python-plugin@claude-plugins" in settings["enabledPlugins"]
        assert "github-actions-plugin@claude-plugins" in settings["enabledPlugins"]

        # Single initial commit on main (blueprint-init was skipped).
        log = subprocess.run(
            ["git", "log", "--format=%s"],
            cwd=repo, capture_output=True, text=True, check=True,
        ).stdout.strip().splitlines()
        assert len(log) == 1
        assert log[0].startswith("chore: initialize")
