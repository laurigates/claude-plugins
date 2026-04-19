"""Tests for the plugin-enrollment logic used by ``git-repo-agent new``.

Includes a drift test that parses the ``configure-claude-plugins`` SKILL.md
table and asserts the Python-side mapping (``STACK_PLUGINS``) matches it
row-for-row. Update either the Python mapping or SKILL.md whenever one
changes — they must stay in lockstep.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from git_repo_agent.plugin_enroller import (
    ALWAYS_ON_PLUGINS,
    MARKETPLACE_KEY,
    STACK_PLUGINS,
    build_settings_json,
    select_permissions,
    select_plugins,
    write_settings_json,
)


# ---------------------------------------------------------------------------
# select_plugins / select_permissions
# ---------------------------------------------------------------------------


class TestSelectPlugins:
    def test_no_indicators_returns_always_on(self):
        result = select_plugins([])
        assert set(result) == set(ALWAYS_ON_PLUGINS)

    def test_python_adds_stack_plugins(self):
        result = set(select_plugins(["python"]))
        assert set(ALWAYS_ON_PLUGINS).issubset(result)
        assert {"python-plugin", "testing-plugin", "code-quality-plugin", "git-plugin"}.issubset(result)

    def test_multiple_indicators_merge(self):
        result = set(select_plugins(["python", "docker", "github-actions"]))
        assert {"python-plugin", "container-plugin", "github-actions-plugin"}.issubset(result)

    def test_extra_plugins_merged_and_deduped(self):
        result = select_plugins(
            ["python"],
            extra_plugins=["python-plugin", "my-custom-plugin"],
        )
        # No duplicates even though python-plugin is already selected via the stack.
        assert result.count("python-plugin") == 1
        assert "my-custom-plugin" in result

    def test_unknown_indicator_ignored(self):
        # Unknown indicators don't raise — callers own validation.
        result = select_plugins(["not-a-real-stack"])
        assert set(result) == set(ALWAYS_ON_PLUGINS)

    def test_result_is_sorted(self):
        result = select_plugins(["python", "docker"])
        assert result == sorted(result)


class TestSelectPermissions:
    def test_common_entries_always_present(self):
        result = select_permissions([])
        assert "Bash(git:*)" in result
        assert "Bash(gh:*)" in result
        assert "Bash(pre-commit:*)" in result

    def test_python_stack_permissions(self):
        result = select_permissions(["python"])
        assert "Bash(uv:*)" in result
        assert "Bash(ruff:*)" in result
        assert "Bash(pytest:*)" in result

    def test_typescript_stack_permissions(self):
        result = select_permissions(["typescript"])
        assert "Bash(npm:*)" in result
        assert "Bash(vitest:*)" in result

    def test_permissions_deduplicated(self):
        # esphome includes uv / uvx; python does too — combined, each should appear once.
        result = select_permissions(["python", "esphome"])
        assert result.count("Bash(uv:*)") == 1


# ---------------------------------------------------------------------------
# build_settings_json / write_settings_json
# ---------------------------------------------------------------------------


class TestBuildSettingsJson:
    def test_fresh_settings(self):
        plugins = ["python-plugin", "git-plugin"]
        perms = ["Bash(git:*)", "Bash(uv:*)"]
        data = build_settings_json(plugins, perms)

        assert data["permissions"]["allow"] == perms
        assert MARKETPLACE_KEY in data["extraKnownMarketplaces"]
        assert data["extraKnownMarketplaces"][MARKETPLACE_KEY]["source"] == {
            "source": "github",
            "repo": "laurigates/claude-plugins",
        }
        assert data["enabledPlugins"] == {
            "git-plugin@claude-plugins": True,
            "python-plugin@claude-plugins": True,
        }

    def test_merges_with_existing(self):
        existing = {
            "permissions": {"allow": ["Bash(git:*)", "Bash(custom:*)"]},
            "enabledPlugins": {"existing-plugin@claude-plugins": True},
            "hooks": {"SessionStart": []},  # preserved untouched
            "env": {"MY_VAR": "1"},
        }
        data = build_settings_json(
            plugins=["python-plugin"],
            permissions=["Bash(git:*)", "Bash(uv:*)"],
            existing=existing,
        )
        # Custom permissions are preserved.
        assert "Bash(custom:*)" in data["permissions"]["allow"]
        # New permission is added.
        assert "Bash(uv:*)" in data["permissions"]["allow"]
        # No duplicates.
        assert data["permissions"]["allow"].count("Bash(git:*)") == 1
        # Previously enabled plugins are preserved.
        assert data["enabledPlugins"]["existing-plugin@claude-plugins"] is True
        assert data["enabledPlugins"]["python-plugin@claude-plugins"] is True
        # Non-managed keys pass through.
        assert data["hooks"] == {"SessionStart": []}
        assert data["env"] == {"MY_VAR": "1"}

    def test_preserves_existing_marketplace_entry(self):
        existing = {
            "extraKnownMarketplaces": {
                MARKETPLACE_KEY: {
                    "source": {"source": "github", "repo": "laurigates/claude-plugins"},
                    "autoUpdate": False,  # user turned it off
                }
            },
        }
        data = build_settings_json([], [], existing=existing)
        # We do not overwrite autoUpdate when the marketplace entry is already present.
        assert data["extraKnownMarketplaces"][MARKETPLACE_KEY]["autoUpdate"] is False


class TestWriteSettingsJson:
    def test_creates_claude_dir_and_file(self, tmp_path: Path):
        path = write_settings_json(
            tmp_path,
            plugins=["python-plugin"],
            permissions=["Bash(git:*)"],
        )
        assert path == tmp_path / ".claude" / "settings.json"
        assert path.is_file()

        import json as _json
        data = _json.loads(path.read_text(encoding="utf-8"))
        assert data["enabledPlugins"]["python-plugin@claude-plugins"] is True

    def test_merges_when_called_twice(self, tmp_path: Path):
        # First run: python stack.
        write_settings_json(tmp_path, ["python-plugin"], ["Bash(git:*)"])
        # Second run: add a docker indicator's plugin + permission.
        path = write_settings_json(
            tmp_path, ["container-plugin"], ["Bash(docker:*)"],
        )
        import json as _json
        data = _json.loads(path.read_text(encoding="utf-8"))
        # Both plugins should survive.
        assert "python-plugin@claude-plugins" in data["enabledPlugins"]
        assert "container-plugin@claude-plugins" in data["enabledPlugins"]
        # Both permissions should survive.
        assert "Bash(git:*)" in data["permissions"]["allow"]
        assert "Bash(docker:*)" in data["permissions"]["allow"]


# ---------------------------------------------------------------------------
# Drift test against configure-claude-plugins/SKILL.md
# ---------------------------------------------------------------------------

_SKILL_MD_PATH = (
    Path(__file__).resolve().parent.parent.parent
    / "configure-plugin"
    / "skills"
    / "configure-claude-plugins"
    / "SKILL.md"
)

# Maps SKILL.md "Project Indicator" column (lowercased) to the Python-side
# stack-indicator name in STACK_PLUGINS. ``Default (any)`` is intentionally
# omitted — the Python code treats the always-on baseline separately.
_SKILL_INDICATOR_TO_STACK = {
    "package.json": "typescript",
    "pyproject.toml / setup.py": "python",
    "cargo.toml": "rust",
    "dockerfile": "docker",
    ".github/workflows/": "github-actions",
    "idf_component.yml / sdkconfig": "esp-idf",
    "esphome yaml": "esphome",
}


def _parse_plugins_cell(cell: str) -> set[str]:
    """Extract ``*-plugin`` names from a markdown table cell.

    Strips ``Above +`` prefix so rows expressed as deltas (Dockerfile,
    .github/workflows/) compare correctly against the Python table, which
    stores those same deltas.
    """
    cell = cell.replace("Above +", "").strip()
    return set(re.findall(r"`([a-z0-9-]+-plugin)`", cell))


def _parse_skill_table(skill_md: str) -> dict[str, set[str]]:
    """Return ``{indicator_label_lowercase: {plugin, ...}}`` from SKILL.md.

    Parses the "Project Indicator | Recommended Plugins" table under
    Step 2. Stops at the first non-table line.
    """
    rows: dict[str, set[str]] = {}
    in_table = False
    for line in skill_md.splitlines():
        if "Project Indicator" in line and "Recommended Plugins" in line:
            in_table = True
            continue
        if not in_table:
            continue
        if line.startswith("|---") or line.startswith("| ---"):
            continue
        if not line.startswith("|"):
            break
        parts = [p.strip() for p in line.split("|")[1:-1]]
        if len(parts) != 2:
            continue
        # SKILL.md renders each indicator in its own backticks, e.g.
        # "`pyproject.toml` / `setup.py`". Strip all backticks and normalise
        # internal whitespace before lowercasing.
        indicator = re.sub(r"\s+", " ", parts[0].replace("`", "")).strip().lower()
        rows[indicator] = _parse_plugins_cell(parts[1])
    return rows


class TestSkillMdDrift:
    """Fails if the Python stack→plugins mapping drifts from SKILL.md.

    SKILL.md is the user-facing source of truth for plugin selection; this
    test catches cases where one side is updated and the other is not.
    """

    @pytest.fixture(scope="class")
    def skill_rows(self) -> dict[str, set[str]]:
        assert _SKILL_MD_PATH.is_file(), (
            f"Expected SKILL.md at {_SKILL_MD_PATH}; monorepo layout changed?"
        )
        return _parse_skill_table(_SKILL_MD_PATH.read_text(encoding="utf-8"))

    def test_every_mapped_indicator_parses(self, skill_rows):
        for indicator in _SKILL_INDICATOR_TO_STACK:
            assert indicator in skill_rows, (
                f"SKILL.md table no longer contains row {indicator!r}. "
                f"Update _SKILL_INDICATOR_TO_STACK in tests."
            )

    def test_stack_plugins_match_skill_md(self, skill_rows):
        mismatches: list[str] = []
        for skill_indicator, stack_name in _SKILL_INDICATOR_TO_STACK.items():
            skill_plugins = skill_rows[skill_indicator]
            python_plugins = set(STACK_PLUGINS[stack_name])
            if skill_plugins != python_plugins:
                mismatches.append(
                    f"  {skill_indicator!r} ({stack_name}): "
                    f"SKILL.md={sorted(skill_plugins)}, "
                    f"Python={sorted(python_plugins)}"
                )
        assert not mismatches, (
            "Drift between configure-claude-plugins SKILL.md and "
            "plugin_enroller.STACK_PLUGINS:\n" + "\n".join(mismatches)
        )
