"""Tests for the MOC curation helpers (#1071, #1072).

These exercise the deterministic building blocks the vault-mocs
subagent calls — no LLM interaction.
"""

from __future__ import annotations

import textwrap

import pytest

from vault_agent.fixers.moc_curation import (
    MocProposal,
    insert_link_alphabetically,
    is_dataview_moc,
    parse_moc_sections,
    render_new_moc,
)


BASIC_MOC = textwrap.dedent(
    """
    ---
    tags:
      - 📝/moc
    ---

    # Development MOC

    One-line framing paragraph.

    ## Languages

    - [[Python]]
    - [[Rust]]
    - [[TypeScript]]

    ## Tools

    - [[Git]]
    - [[Neovim]]
    """
).lstrip()


DATAVIEW_MOC = textwrap.dedent(
    """
    ---
    tags:
      - 📝/moc
    ---

    # Project index MOC

    ```dataview
    TABLE status FROM #project
    ```
    """
).lstrip()


class TestParseMocSections:
    def test_extracts_structure(self) -> None:
        s = parse_moc_sections(BASIC_MOC)
        assert [sec.heading for sec in s.sections] == ["Languages", "Tools"]
        assert s.sections[0].wikilink_targets == ["Python", "Rust", "TypeScript"]
        assert s.sections[1].wikilink_targets == ["Git", "Neovim"]

    def test_preserves_frontmatter(self) -> None:
        s = parse_moc_sections(BASIC_MOC)
        assert "tags:" in s.frontmatter
        assert "📝/moc" in s.frontmatter

    def test_no_sections_produces_empty_list(self) -> None:
        s = parse_moc_sections("# Title\n\njust a preamble")
        assert s.sections == []


class TestIsDataviewMoc:
    def test_detects_dataview_fence(self) -> None:
        assert is_dataview_moc(DATAVIEW_MOC) is True

    def test_rejects_plain_moc(self) -> None:
        assert is_dataview_moc(BASIC_MOC) is False

    def test_rejects_code_block_other_language(self) -> None:
        body = "```python\nprint('hi')\n```"
        assert is_dataview_moc(body) is False


class TestInsertLinkAlphabetically:
    def test_preserves_alphabetical_order(self) -> None:
        out = insert_link_alphabetically(BASIC_MOC, "Languages", "Go")
        langs_idx = out.index("## Languages")
        tools_idx = out.index("## Tools")
        langs_section = out[langs_idx:tools_idx]
        # Order should be: Go, Python, Rust, TypeScript
        assert langs_section.index("[[Go]]") < langs_section.index("[[Python]]")
        assert langs_section.index("[[Python]]") < langs_section.index("[[Rust]]")
        assert langs_section.index("[[Rust]]") < langs_section.index("[[TypeScript]]")

    def test_appends_when_section_not_alphabetical(self) -> None:
        body = textwrap.dedent(
            """
            ## Languages
            - [[Rust]]
            - [[Python]]
            - [[Go]]
            """
        ).lstrip()
        out = insert_link_alphabetically(body, "Languages", "TypeScript")
        # Should append since existing section is not alphabetical.
        assert out.rstrip().endswith("[[TypeScript]]")

    def test_idempotent_when_link_already_present(self) -> None:
        out = insert_link_alphabetically(BASIC_MOC, "Languages", "Python")
        assert out.count("[[Python]]") == 1

    def test_rejects_missing_section(self) -> None:
        with pytest.raises(ValueError, match="section"):
            insert_link_alphabetically(BASIC_MOC, "Nonexistent", "Go")

    def test_rejects_dataview_moc(self) -> None:
        with pytest.raises(ValueError, match="dataview"):
            insert_link_alphabetically(DATAVIEW_MOC, "anything", "Foo")


class TestRenderNewMoc:
    def test_shape_matches_convention(self) -> None:
        proposal = MocProposal(
            subject="Embedded Systems and IoT",
            intro="Resources on microcontrollers, sensors, and home automation.",
            sections=[
                ("Microcontrollers", ["ESP32", "Arduino", "Raspberry Pi"]),
                ("Sensors", ["SHT4x", "BME280"]),
            ],
        )
        body = render_new_moc(proposal)
        assert "tags:\n  - 📝/moc" in body
        assert "# Embedded Systems and IoT" in body
        assert "Resources on microcontrollers" in body
        # Sections alphabetized inside each heading.
        micro_idx = body.index("## Microcontrollers")
        sensors_idx = body.index("## Sensors")
        micro_section = body[micro_idx:sensors_idx]
        assert micro_section.index("[[Arduino]]") < micro_section.index("[[ESP32]]")
        assert micro_section.index("[[ESP32]]") < micro_section.index(
            "[[Raspberry Pi]]"
        )

    def test_filename_convention(self) -> None:
        proposal = MocProposal(
            subject="Foo Bar", intro="desc", sections=[("Anything", [])]
        )
        assert proposal.filename() == "Zettelkasten/Foo Bar MOC.md"
