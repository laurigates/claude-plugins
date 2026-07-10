"""Tests for the prompt compiler's standalone-install fallback.

When ``vault-agent`` is installed standalone (e.g. via
``uv tool install``), the sibling ``obsidian-plugin/skills/`` directory is
not present. The compiler must fall back to the pre-compiled artifacts
shipped under ``prompts/generated/`` instead of returning empty strings
or raising ``FileNotFoundError``.

These tests fake standalone mode by repointing ``_PLUGINS_ROOT`` at a
directory that contains no ``obsidian-plugin/`` sibling, then re-checking
the public compiler API.
"""

from __future__ import annotations

import pytest

from vault_agent.prompts import compiler


def _referenced_skill_relpaths() -> list[str]:
    """Union of every skill path referenced by any subagent bundle."""
    seen: set[str] = set()
    for skill_paths in compiler.SUBAGENT_SKILLS.values():
        seen.update(skill_paths)
    return sorted(seen)


@pytest.fixture
def standalone_mode(tmp_path, monkeypatch):
    """Repoint ``_PLUGINS_ROOT`` at an empty directory.

    Live compilation will fail to find any source SKILL.md, exercising
    the pre-compiled fallback path. The cache on ``get_compiled_prompt``
    / ``get_compiled_skill`` must be cleared so the fallback runs.
    """
    monkeypatch.setattr(compiler, "_PLUGINS_ROOT", tmp_path)
    compiler.get_compiled_prompt.cache_clear()
    compiler.get_compiled_skill.cache_clear()
    yield tmp_path
    compiler.get_compiled_prompt.cache_clear()
    compiler.get_compiled_skill.cache_clear()


class TestSubagentFallback:
    """``get_compiled_prompt()`` reads from generated/ when sources are absent."""

    def test_each_subagent_has_a_fallback(self, standalone_mode):
        for name in compiler.SUBAGENT_SKILLS:
            generated = compiler._GENERATED_DIR / f"{name}_skills.md"
            assert generated.exists(), (
                f"Standalone install would have no fallback for subagent "
                f"'{name}'. Run scripts/compile_prompts.py to regenerate "
                f"{generated.relative_to(compiler._REPO_ROOT)}."
            )

    def test_fallback_returns_substantive_content(self, standalone_mode):
        for name in compiler.SUBAGENT_SKILLS:
            content = compiler.get_compiled_prompt(name)
            assert len(content) > 500, (
                f"Subagent '{name}' fallback returned only {len(content)} "
                f"chars in standalone mode."
            )


class TestPerSkillFallback:
    """``get_compiled_skill()`` reads from generated/skills/ when sources are absent."""

    def test_each_referenced_skill_has_a_fallback(self, standalone_mode):
        for relpath in _referenced_skill_relpaths():
            fallback = compiler._generated_skill_path(relpath)
            assert fallback.exists(), (
                f"Standalone install would have no fallback for "
                f"'{relpath}'. Run scripts/compile_prompts.py to "
                f"regenerate {fallback.relative_to(compiler._REPO_ROOT)}."
            )

    def test_fallback_returns_skill_content(self, standalone_mode):
        for relpath in _referenced_skill_relpaths():
            content = compiler.get_compiled_skill(relpath)
            assert content, (
                f"Skill '{relpath}' returned empty content in standalone "
                "mode despite a generated fallback file existing."
            )

    def test_fallback_path_mapping(self):
        # ``<plugin>/skills/<skill>/SKILL.md`` →
        #     ``generated/skills/<plugin>/<skill>.md``
        rel = "obsidian-plugin/skills/vault-frontmatter/SKILL.md"
        expected = (
            compiler._GENERATED_SKILLS_DIR / "obsidian-plugin" / "vault-frontmatter.md"
        )
        assert compiler._generated_skill_path(rel) == expected

    def test_missing_skill_with_no_fallback_raises(self, standalone_mode):
        with pytest.raises(FileNotFoundError):
            compiler.get_compiled_skill("nonexistent/skills/no-such/SKILL.md")


class TestMonorepoTakesPrecedence:
    """Live compilation wins when sources are present (dev mode)."""

    def test_subagent_uses_live_sources(self):
        # The default fixture-less test runs in monorepo mode: sources
        # exist, so the result must match a fresh ``compile_subagent``.
        compiler.get_compiled_prompt.cache_clear()
        live = compiler.get_compiled_prompt("vault-lint")
        skill_paths = compiler.SUBAGENT_SKILLS["vault-lint"]
        if any(compiler._plugin_skill_available(p) for p in skill_paths):
            assert live == compiler.compile_subagent("vault-lint", skill_paths)
        compiler.get_compiled_prompt.cache_clear()
