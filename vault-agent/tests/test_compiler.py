"""Tests for the prompt compiler."""

from __future__ import annotations

from pathlib import Path

import pytest

from vault_agent.prompts.compiler import (
    SUBAGENT_SKILLS,
    compile_skill,
    filter_sections,
    get_compiled_prompt,
    parse_sections,
    strip_frontmatter,
    transform_references,
)


class TestStripFrontmatter:
    def test_removes_yaml_block(self) -> None:
        content = "---\nfoo: bar\n---\n\nbody\n"
        assert strip_frontmatter(content) == "\nbody\n"

    def test_no_frontmatter_passthrough(self) -> None:
        content = "body only\n"
        assert strip_frontmatter(content) == content


class TestParseSections:
    def test_splits_by_heading(self) -> None:
        content = "intro\n\n## First\na\n\n## Second\nb\n"
        sections = parse_sections(content)
        # [(intro, "", "intro\n\n"), ("First", "##", "a\n\n"), ("Second", "##", "b\n")]
        assert sections[0][0] == ""
        assert sections[1][0] == "First"
        assert sections[1][1] == "##"
        assert sections[2][0] == "Second"


class TestFilterSections:
    def test_drops_when_to_use(self) -> None:
        sections = [
            ("", "", "intro text"),
            ("When to Use", "##", "use it for X\n"),
            ("Core Operations", "##", "do the thing\n"),
        ]
        out = filter_sections(sections)
        assert "use it for X" not in out
        assert "do the thing" in out

    def test_drops_related_skills(self) -> None:
        sections = [
            ("Core Operations", "##", "core\n"),
            ("Related Skills", "##", "see X, Y\n"),
        ]
        out = filter_sections(sections)
        assert "core" in out
        assert "see X" not in out

    def test_keeps_safety(self) -> None:
        sections = [("Safety", "##", "never do X\n")]
        out = filter_sections(sections)
        assert "never do X" in out


class TestTransformReferences:
    def test_rewrites_askuserquestion(self) -> None:
        out = transform_references("Use AskUserQuestion to confirm.")
        assert "AskUserQuestion" not in out
        assert "report to orchestrator" in out

    def test_rewrites_ask_the_user(self) -> None:
        out = transform_references("Then ask the user for the value.")
        assert "ask the user" not in out


class TestCompileSkill:
    def test_compiles_a_real_vault_skill(self) -> None:
        plugins_root = Path(__file__).resolve().parents[2]
        skill = (
            plugins_root
            / "obsidian-plugin"
            / "skills"
            / "vault-frontmatter"
            / "SKILL.md"
        )
        assert skill.exists(), f"missing {skill}"
        out = compile_skill(skill)
        # Frontmatter is stripped
        assert "created:" not in out
        # When-to-use is dropped
        assert "## When to Use" not in out
        # Core domain content is kept
        assert "Canonical Frontmatter Shape" in out


class TestGetCompiledPrompt:
    def test_known_subagent(self) -> None:
        out = get_compiled_prompt("vault-lint")
        assert len(out) > 500  # meaningful content
        # Should contain content from the three component skills
        assert "vault-frontmatter" in out
        assert "vault-tags" in out
        assert "vault-templates" in out

    def test_unknown_subagent_returns_empty(self) -> None:
        assert get_compiled_prompt("no-such-agent") == ""

    def test_all_configured_subagents_compile(self) -> None:
        for name in SUBAGENT_SKILLS:
            out = get_compiled_prompt(name)
            assert out, f"{name} compiled to empty string"
