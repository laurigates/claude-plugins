"""Tests for the local-genesis logic used by ``git-repo-agent new``."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path

import pytest

from git_repo_agent.creator import (
    NewProjectSpec,
    create_repo,
    slugify,
)


def _git_available() -> bool:
    return shutil.which("git") is not None


needs_git = pytest.mark.skipif(not _git_available(), reason="git not installed")


# ---------------------------------------------------------------------------
# slugify
# ---------------------------------------------------------------------------


class TestSlugify:
    def test_basic_conversion(self):
        assert slugify("Telegram Chat Bot") == "telegram-chat-bot"

    def test_snake_case_becomes_kebab(self):
        assert slugify("my_cool_project") == "my-cool-project"

    def test_strips_special_chars(self):
        assert slugify("Hello, World! v2") == "hello-world-v2"

    def test_collapses_dashes(self):
        assert slugify("a---b  c") == "a-b-c"

    def test_rejects_empty(self):
        with pytest.raises(ValueError):
            slugify("")

    def test_rejects_only_specials(self):
        with pytest.raises(ValueError):
            slugify("!!!")


# ---------------------------------------------------------------------------
# create_repo — dry run
# ---------------------------------------------------------------------------


def _spec(**over) -> NewProjectSpec:
    defaults = dict(
        name="Telegram Chat Bot",
        slug="telegram-chat-bot",
        description="Bot that replies to users",
        idea="Telegram chat bot that replies to user messages",
        language="python",
        stack_indicators=("python",),
        extra_plugins=(),
    )
    defaults.update(over)
    return NewProjectSpec(**defaults)


class TestCreateRepoDryRun:
    def test_dry_run_makes_no_changes(self, tmp_path: Path):
        result = create_repo(spec=_spec(), parent_dir=tmp_path, dry_run=True)
        assert result.dry_run is True
        assert result.commit_sha is None
        assert result.path == tmp_path / "telegram-chat-bot"
        assert not result.path.exists()
        assert "python-plugin" in result.plugins
        assert "Bash(uv:*)" in result.permissions

    def test_dry_run_with_missing_parent_dir(self, tmp_path: Path):
        bogus = tmp_path / "does" / "not" / "exist"
        with pytest.raises(FileNotFoundError):
            create_repo(spec=_spec(), parent_dir=bogus, dry_run=True)


# ---------------------------------------------------------------------------
# create_repo — full genesis (requires git on PATH)
# ---------------------------------------------------------------------------


@needs_git
class TestCreateRepoFullGenesis:
    def test_creates_directory_and_initial_commit(self, tmp_path: Path):
        result = create_repo(spec=_spec(), parent_dir=tmp_path)

        assert result.path.is_dir()
        assert (result.path / ".git").is_dir()
        assert (result.path / "README.md").is_file()
        assert (result.path / ".gitignore").is_file()
        assert (result.path / "docs" / "prds" / "0001-project-goal.md").is_file()
        assert (result.path / ".claude" / "settings.json").is_file()

        assert result.commit_sha is not None
        assert len(result.commit_sha) == 40

        # Initial commit is on main with expected scope.
        branch = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=result.path, capture_output=True, text=True, check=True,
        ).stdout.strip()
        assert branch == "main"

        log = subprocess.run(
            ["git", "log", "--format=%s", "-n", "1"],
            cwd=result.path, capture_output=True, text=True, check=True,
        ).stdout.strip()
        assert log.startswith("chore: initialize")

    def test_settings_json_has_marketplace_and_plugins(self, tmp_path: Path):
        result = create_repo(spec=_spec(), parent_dir=tmp_path)
        settings = json.loads(
            (result.path / ".claude" / "settings.json").read_text(encoding="utf-8")
        )
        assert "claude-plugins" in settings["extraKnownMarketplaces"]
        assert (
            settings["extraKnownMarketplaces"]["claude-plugins"]["source"]["repo"]
            == "laurigates/claude-plugins"
        )
        assert "python-plugin@claude-plugins" in settings["enabledPlugins"]
        # Always-on baseline survives.
        assert "configure-plugin@claude-plugins" in settings["enabledPlugins"]

    def test_prd_contains_idea_text(self, tmp_path: Path):
        result = create_repo(spec=_spec(), parent_dir=tmp_path)
        prd = (result.path / "docs" / "prds" / "0001-project-goal.md").read_text(
            encoding="utf-8"
        )
        assert "Telegram chat bot that replies to user messages" in prd
        assert "Primary language: python" in prd

    def test_refuses_to_overwrite_existing_target(self, tmp_path: Path):
        # Pre-create the target so the second create_repo call must refuse.
        (tmp_path / "telegram-chat-bot").mkdir()
        with pytest.raises(FileExistsError):
            create_repo(spec=_spec(), parent_dir=tmp_path)

    def test_default_language_uses_only_default_gitignore(self, tmp_path: Path):
        spec = _spec(language="default", stack_indicators=())
        result = create_repo(spec=spec, parent_dir=tmp_path)
        gi = (result.path / ".gitignore").read_text(encoding="utf-8")
        # Default fragment is always present.
        assert ".DS_Store" in gi
        # Python fragment is not.
        assert "__pycache__" not in gi
