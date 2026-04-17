"""Unit tests for the vault analyzers.

Each test builds a minimal vault in a temp dir and asserts against the
specific analyzer's report. Uses a ``_make_vault`` helper mirroring the
``_make_repo`` pattern in git-repo-agent.
"""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from vault_agent.analyzers import scan
from vault_agent.analyzers.audit import run_audit
from vault_agent.analyzers.duplicates import analyze_duplicates
from vault_agent.analyzers.frontmatter import analyze_frontmatter
from vault_agent.analyzers.graph import analyze_graph
from vault_agent.analyzers.links import analyze_links
from vault_agent.analyzers.mocs import analyze_mocs
from vault_agent.analyzers.stubs import StubClass, analyze_stubs


def _make_vault(tmp_path: Path, files: dict[str, str]) -> Path:
    """Build a vault at ``tmp_path`` with the given ``rel_path → content`` dict."""
    for rel, content in files.items():
        path = tmp_path / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")
    return tmp_path


# ---------------------------------------------------------------------------
# VaultIndex
# ---------------------------------------------------------------------------


class TestVaultIndex:
    def test_scans_markdown_files(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Note1.md": "# Note1\n",
                "Zettelkasten/Note2.md": "# Note2\n",
            },
        )
        index = scan(vault)
        assert len(index.notes) == 2
        assert "Note1" in index.by_basename
        assert "Note2" in index.by_basename

    def test_excludes_dotfiles(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Keep.md": "# Keep\n",
                ".obsidian/workspace.md": "# skip\n",
                ".claude/agents/foo.md": "# skip\n",
                ".git/info/exclude.md": "# skip\n",
            },
        )
        index = scan(vault)
        basenames = {n.basename for n in index.notes}
        assert basenames == {"Keep"}

    def test_excludes_files_dir(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Keep.md": "# Keep\n",
                "Files/attachment-note.md": "# attachment\n",
            },
        )
        index = scan(vault)
        assert {n.basename for n in index.notes} == {"Keep"}

    def test_parses_frontmatter_and_tags(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": """
                    ---
                    tags:
                      - 🛠️/neovim
                      - 📝/notes
                    ---
                    body
                """,
            },
        )
        index = scan(vault)
        note = index.notes[0]
        assert note.has_frontmatter is True
        assert note.tags == ["🛠️/neovim", "📝/notes"]

    def test_extracts_wikilinks(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": "See [[B]] and ![[Files/img.png]] and [[C#section|C-alias]]\n",
                "Zettelkasten/B.md": "# B\n",
                "Zettelkasten/C.md": "# C\n",
            },
        )
        index = scan(vault)
        a = index.by_basename["A"][0]
        targets = [lnk.target for lnk in a.wikilinks]
        assert "B" in targets
        assert "C" in targets
        embed_count = sum(1 for lnk in a.wikilinks if lnk.is_embed)
        assert embed_count == 1

    def test_resolve_basename_and_path(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Docker.md": "main\n",
                "FVH/z/Docker.md": "stub\n",
                "Kanban/Main.md": "# kanban\n",
            },
        )
        index = scan(vault)
        # Ambiguous by basename
        assert len(index.resolve("Docker")) == 2
        assert index.is_ambiguous("Docker")
        # Path-qualified resolves uniquely
        assert len(index.resolve("Kanban/Main")) == 1
        # Missing target
        assert index.is_broken("NoSuchNote")


# ---------------------------------------------------------------------------
# Frontmatter analyzer
# ---------------------------------------------------------------------------


class TestFrontmatter:
    def test_detects_bare_placeholder(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": """
                    ---
                    tags:
                      - 📝
                    ---
                    body
                """,
            },
        )
        report = analyze_frontmatter(scan(vault))
        assert len(report.notes_with_bare_placeholder) == 1

    def test_detects_legacy_id(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": """
                    ---
                    id: abc123
                    tags: [📝/notes]
                    ---
                    body
                """,
            },
        )
        report = analyze_frontmatter(scan(vault))
        assert len(report.notes_with_legacy_id) == 1

    def test_detects_templater_leak(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": """
                    ---
                    tags: [📝/notes]
                    ---
                    <% tp.file.cursor(1) %>
                """,
                "Zettelkasten/B.md": """
                    ---
                    tags: [📝/notes]
                    ---
                    # {{title}}
                """,
            },
        )
        report = analyze_frontmatter(scan(vault))
        assert len(report.notes_with_templater_leak) == 2

    def test_detects_missing_fvh_context(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "FVH/z/Ansible.md": """
                    ---
                    tags: [🛠️/ansible]
                    ---
                    body
                """,
                "FVH/z/Proper.md": """
                    ---
                    context: fvh
                    tags: [🛠️/proper]
                    ---
                    body
                """,
            },
        )
        report = analyze_frontmatter(scan(vault))
        assert len(report.fvh_notes_missing_context) == 1

    def test_tag_duplicate_candidates(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": """
                    ---
                    tags: [🔍/security]
                    ---
                """,
                "Zettelkasten/B.md": """
                    ---
                    tags: [🔒/security]
                    ---
                """,
            },
        )
        report = analyze_frontmatter(scan(vault))
        # "security" normalizes both, giving a duplicate group
        assert "security" in report.tag_duplicate_candidates
        assert len(report.tag_duplicate_candidates["security"]) == 2


# ---------------------------------------------------------------------------
# Links analyzer
# ---------------------------------------------------------------------------


class TestLinks:
    def test_detects_broken(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": "See [[NoSuchNote]].\n",
            },
        )
        report = analyze_links(scan(vault))
        assert report.broken_count == 1
        assert report.broken_target_frequency == {"NoSuchNote": 1}

    def test_detects_ambiguous(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Docker.md": "# main\n",
                "FVH/z/Docker.md": "# stub\n",
                "Zettelkasten/Note.md": "See [[Docker]].\n",
            },
        )
        report = analyze_links(scan(vault))
        assert report.ambiguous_count == 1

    def test_top_broken_ordering(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": "[[Gone]]\n",
                "Zettelkasten/B.md": "[[Gone]]\n",
                "Zettelkasten/C.md": "[[Gone]] [[Other]]\n",
            },
        )
        report = analyze_links(scan(vault))
        top = report.top_broken()
        assert top[0] == ("Gone", 3)


# ---------------------------------------------------------------------------
# Graph analyzer
# ---------------------------------------------------------------------------


class TestGraph:
    def test_meaningful_orphan(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Lonely.md": "just text, no links\n",
                "Zettelkasten/Connected.md": "See [[Lonely]]\n",
            },
        )
        report = analyze_graph(scan(vault))
        # Lonely has 1 incoming, Connected has 1 outgoing, both are non-orphan
        assert report.meaningful_orphans == []

    def test_inbox_orphan_is_expected(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Inbox/Untitled.md": "no links\n",
            },
        )
        report = analyze_graph(scan(vault))
        assert report.meaningful_orphans == []
        assert len(report.expected_orphans) == 1

    def test_top_hubs(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Hub.md": "# Hub\n",
                "Zettelkasten/A.md": "[[Hub]]\n",
                "Zettelkasten/B.md": "[[Hub]]\n",
                "Zettelkasten/C.md": "[[Hub]]\n",
            },
        )
        report = analyze_graph(scan(vault))
        assert report.top_hubs[0][1] == 3


# ---------------------------------------------------------------------------
# Stubs analyzer
# ---------------------------------------------------------------------------


class TestStubs:
    def test_clean_redirect(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Docker.md": "# Main\n",
                "FVH/z/Docker.md": """
                    ---
                    tags: [redirect]
                    context: fvh
                    ---
                    See [[Zettelkasten/Docker|Docker]] in the main knowledge base.
                """,
            },
        )
        report = analyze_stubs(scan(vault))
        assert report.total_stubs == 1
        assert report.classifications[0].cls == StubClass.CLEAN_REDIRECT

    def test_stale_duplicate(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Docker.md": "# Main\n",
                "FVH/z/Docker.md": """
                    ---
                    tags: [🌱]
                    context: fvh
                    ---
                    Lots and lots of duplicated docker content here. """ + ("x" * 300),
            },
        )
        report = analyze_stubs(scan(vault))
        assert report.classifications[0].cls == StubClass.STALE_DUPLICATE

    def test_fvh_original(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "FVH/z/FvhOnly.md": """
                    ---
                    tags: [🛠️/internal]
                    context: fvh
                    ---
                    FVH-only content, no zettelkasten counterpart.
                """,
            },
        )
        report = analyze_stubs(scan(vault))
        assert report.classifications[0].cls == StubClass.FVH_ORIGINAL


# ---------------------------------------------------------------------------
# MOCs analyzer
# ---------------------------------------------------------------------------


class TestMocs:
    def test_inventory(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Neovim MOC.md": """
                    ---
                    tags: [📝/moc]
                    ---
                    [[Neovim]] [[Lazy]]
                """,
                "Zettelkasten/Neovim.md": "# nv\n",
                "Zettelkasten/Lazy.md": "# lazy\n",
            },
        )
        report = analyze_mocs(scan(vault))
        assert len(report.mocs) == 1
        assert report.mocs[0].basename == "Neovim MOC"

    def test_flags_legacy_moc_tag(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "FVH/z/Data MOC.md": """
                    ---
                    tags: [🗺️]
                    context: fvh
                    ---
                    [[Thing]]
                """,
                "FVH/z/Thing.md": """
                    ---
                    tags: [☁️/data]
                    context: fvh
                    ---
                """,
            },
        )
        report = analyze_mocs(scan(vault))
        assert len(report.legacy_tagged_mocs) == 1


# ---------------------------------------------------------------------------
# Duplicates analyzer
# ---------------------------------------------------------------------------


class TestDuplicates:
    def test_detects_basename_collisions_and_untitled(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Docker.md": "# A\n",
                "FVH/z/Docker.md": "# B\n",
                "Inbox/Untitled.md": "\n",
                "Inbox/Untitled 1.md": "\n",
            },
        )
        report = analyze_duplicates(scan(vault))
        assert report.basename_collisions[0].basename in {"Docker", "Untitled"}
        # 2 "Docker" in one group + both untitled placeholders
        assert len(report.untitled_placeholders) == 2


# ---------------------------------------------------------------------------
# End-to-end audit
# ---------------------------------------------------------------------------


class TestAudit:
    def test_run_audit_returns_all_reports(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/A.md": """
                    ---
                    tags: [📝/notes]
                    ---
                    [[B]]
                """,
                "Zettelkasten/B.md": """
                    ---
                    tags: [📝/notes]
                    ---
                """,
            },
        )
        audit = run_audit(vault)
        assert audit.frontmatter.total_notes == 2
        assert audit.links.broken_count == 0
        # 4 of 5 sub-scores perfect; mocs penalized because notes are tagged
        # with a category but no MOC covers them.
        assert audit.health.total == 80.0

    def test_perfect_score_on_empty_vault(self, tmp_path: Path) -> None:
        vault = tmp_path / "empty"
        vault.mkdir()
        audit = run_audit(vault)
        assert audit.health.total == 100.0
