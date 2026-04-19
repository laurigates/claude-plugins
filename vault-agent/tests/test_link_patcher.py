"""Tests for the broken-wikilink patcher."""

from __future__ import annotations

import textwrap
from pathlib import Path

import pytest

from vault_agent.analyzers.vault_index import scan
from vault_agent.fixers.link_patcher import (
    apply_rewrites,
    summarize_rewrites,
    unqualify_kanban_links,
)


def _make_vault(tmp_path: Path, files: dict[str, str]) -> Path:
    for rel, content in files.items():
        path = tmp_path / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")
    return tmp_path


class TestApplyRewrites:
    def test_rewrites_known_broken_target(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "FVH/z/Ansible.md": "# Ansible\n",
                "FVH/notes/2024-01-01.md": "See [[AnsibleFVH]] and [[AnsibleFVH|ansible stuff]].\n",
            },
        )
        index = scan(vault)
        results = apply_rewrites(index)
        changed = [r for r in results if r.changed]
        assert len(changed) == 1
        assert changed[0].per_rule_counts == {"AnsibleFVH": 2}
        content = (vault / "FVH/notes/2024-01-01.md").read_text()
        assert "[[Ansible]]" in content
        assert "[[Ansible|ansible stuff]]" in content
        assert "AnsibleFVH" not in content

    def test_skips_rule_when_target_not_unique(self, tmp_path: Path) -> None:
        # If Ansible resolves to two notes, the rule is skipped.
        vault = _make_vault(
            tmp_path,
            {
                "A/Ansible.md": "# a\n",
                "B/Ansible.md": "# b\n",
                "Notes.md": "See [[AnsibleFVH]]\n",
            },
        )
        index = scan(vault)
        results = apply_rewrites(index)
        assert all(not r.changed for r in results)

    def test_preserves_alias_and_section(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Target.md": "# Target\n## Install\n",
                "Note.md": "See [[OriginalName#Install|Install guide]]\n",
            },
        )
        index = scan(vault)
        results = apply_rewrites(index, {"OriginalName": "Target"})
        content = (vault / "Note.md").read_text()
        assert "[[Target#Install|Install guide]]" in content

    def test_no_change_when_target_absent(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {"Note.md": "plain note, no links\n"},
        )
        index = scan(vault)
        results = apply_rewrites(index)
        assert all(not r.changed for r in results)


class TestSummarize:
    def test_aggregates_across_files(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "FVH/z/Ansible.md": "# a\n",
                "A.md": "[[AnsibleFVH]]\n",
                "B.md": "[[AnsibleFVH]] [[AnsibleFVH]]\n",
            },
        )
        index = scan(vault)
        results = apply_rewrites(index)
        totals = summarize_rewrites(results)
        assert totals["AnsibleFVH"] == 3


class TestUnqualifyKanban:
    def test_rewrites_unique_basename(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Kanban/Main.md": "# main\n",
                "Note.md": "See [[Kanban/Main]]\n",
            },
        )
        index = scan(vault)
        results = unqualify_kanban_links(index)
        assert any(r.changed for r in results)
        assert "[[Main]]" in (vault / "Note.md").read_text()

    def test_skips_when_ambiguous(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Kanban/Main.md": "# k\n",
                "Zettelkasten/Main.md": "# z\n",
                "Note.md": "See [[Kanban/Main]]\n",
            },
        )
        index = scan(vault)
        results = unqualify_kanban_links(index)
        # Two Main.md notes mean [[Main]] is ambiguous; unqualify is skipped.
        note_content = (vault / "Note.md").read_text()
        assert "[[Kanban/Main]]" in note_content
