"""Tests for deterministic fixers."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from vault_agent.fixers import (
    clean_templater_leakage,
    normalize_tags,
    strip_legacy_id,
)
from vault_agent.fixers._frontmatter_io import load, save


def _write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")


# ---------------------------------------------------------------------------
# Frontmatter IO
# ---------------------------------------------------------------------------


class TestFrontmatterIO:
    def test_roundtrip_preserves_body(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        content = "---\ntags: [a]\n---\n\nbody text\nmore\n"
        p.write_text(content)
        ff = load(p)
        save(ff)
        assert p.read_text() == content

    def test_no_frontmatter_passthrough(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        content = "just body\n"
        p.write_text(content)
        ff = load(p)
        save(ff)
        assert p.read_text() == content


# ---------------------------------------------------------------------------
# ID stripper
# ---------------------------------------------------------------------------


class TestIdStripper:
    def test_strips_id_line(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(
            p,
            """
            ---
            id: 20240118
            tags: [🛠️/neovim]
            ---

            body
            """,
        )
        changed = strip_legacy_id([p])
        assert changed == [p]
        out = p.read_text()
        assert "id:" not in out
        assert "tags: [🛠️/neovim]" in out

    def test_idempotent(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(p, "---\ntags: [a]\n---\nbody\n")
        assert strip_legacy_id([p]) == []


# ---------------------------------------------------------------------------
# Tag normalizer
# ---------------------------------------------------------------------------


class TestTagNormalizerInline:
    def test_removes_bare_placeholder_inline(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(p, "---\ntags: [📝, 🛠️/neovim]\n---\nbody\n")
        results = normalize_tags([p])
        assert results[0].changed
        assert results[0].removed_placeholders == 1
        assert "📝" not in p.read_text().split("---\n\nbody")[0]
        assert "🛠️/neovim" in p.read_text()

    def test_rewrites_legacy_moc_inline(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(p, "---\ntags: [🗺️]\n---\nbody\n")
        results = normalize_tags([p])
        assert results[0].rewrites == 1
        assert "📝/moc" in p.read_text()

    def test_drops_null_inline(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(p, "---\ntags: [null, 🛠️/neovim]\n---\nbody\n")
        results = normalize_tags([p])
        assert results[0].removed_nulls == 1
        assert "null" not in p.read_text().split("body")[0]


class TestTagNormalizerBlock:
    def test_removes_bare_placeholder_block(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(
            p,
            """
            ---
            tags:
              - 📝
              - 🛠️/neovim
            ---
            body
            """,
        )
        results = normalize_tags([p])
        assert results[0].changed
        assert results[0].removed_placeholders == 1
        content = p.read_text()
        assert "  - 📝\n" not in content
        assert "  - 🛠️/neovim" in content

    def test_rewrites_legacy_moc_block(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(
            p,
            """
            ---
            tags:
              - 🗺️
            ---
            body
            """,
        )
        results = normalize_tags([p])
        assert results[0].rewrites == 1
        assert "- 📝/moc" in p.read_text()


class TestTagNormalizerScalar:
    def test_removes_scalar_placeholder(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(p, "---\ntags: 📝\n---\nbody\n")
        results = normalize_tags([p])
        assert results[0].removed_placeholders == 1
        # Line should be gone — the bare tags: line is removed
        assert "tags:" not in p.read_text().split("---\n\nbody")[0].split("\n---")[0]


# ---------------------------------------------------------------------------
# Templater cleaner
# ---------------------------------------------------------------------------


class TestTemplaterCleaner:
    def test_strips_cursor_marker(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(
            p,
            """
            ---
            tags: [📝/notes]
            ---

            <% tp.file.cursor(1) %>
            """,
        )
        results = clean_templater_leakage([p])
        assert results[0].changed
        assert results[0].cursor_markers_removed == 1
        assert "<% tp." not in p.read_text()

    def test_replaces_title_with_filename(self, tmp_path: Path) -> None:
        p = tmp_path / "2024-09-06.md"
        _write(
            p,
            """
            ---
            tags: [📅/daily]
            ---

            # {{title}}

            content
            """,
        )
        results = clean_templater_leakage([p])
        assert results[0].title_substitutions == 1
        assert "# 2024-09-06" in p.read_text()
        assert "{{title}}" not in p.read_text()

    def test_unchanged_when_clean(self, tmp_path: Path) -> None:
        p = tmp_path / "n.md"
        _write(p, "---\ntags: []\n---\n\nclean body\n")
        results = clean_templater_leakage([p])
        assert not results[0].changed
