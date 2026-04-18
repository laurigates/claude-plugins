"""Tests for the LLM-tier triage helpers in link_patcher (#1073)."""

from __future__ import annotations

import subprocess
import textwrap
from pathlib import Path

import pytest

from vault_agent.analyzers.audit import run_audit
from vault_agent.analyzers.vault_index import scan
from vault_agent.fixers.link_patcher import (
    BasenameMatch,
    BROKEN_LINK_REWRITES,
    ConfidenceTier,
    classify_match,
    fuzzy_basename_candidates,
    is_inline_tag_syntax,
    propose_rewrites,
)


def _make_vault(tmp_path: Path, files: dict[str, str]) -> Path:
    for rel, content in files.items():
        p = tmp_path / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")
    return tmp_path


class TestIsInlineTagSyntax:
    @pytest.mark.parametrize(
        "target", ["code", "Project", "SOFTWARE", "tool", "framework"]
    )
    def test_detects_generic_nouns(self, target: str) -> None:
        assert is_inline_tag_syntax(target) is True

    @pytest.mark.parametrize(
        "target", ["ArgoCD", "Kafka", "CI/CD", "Raspberry Pi"]
    )
    def test_allows_real_note_basenames(self, target: str) -> None:
        assert is_inline_tag_syntax(target) is False


class TestFuzzyBasenameCandidates:
    def test_finds_close_match(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/CI-CD.md": "# ci cd\n",
                "Zettelkasten/ArgoCD.md": "# argocd\n",
                "Zettelkasten/Kafka.md": "# kafka\n",
            },
        )
        idx = scan(vault)
        out = fuzzy_basename_candidates("CICD", idx)
        bn = [m.basename for m in out]
        assert "CI-CD" in bn

    def test_respects_cutoff(self, tmp_path: Path) -> None:
        vault = _make_vault(tmp_path, {"Zettelkasten/Python.md": "# p"})
        idx = scan(vault)
        out = fuzzy_basename_candidates("ESP32 MOC", idx, cutoff=0.6)
        # "ESP32 MOC" shares almost nothing with "Python" — no candidates.
        assert out == []


class TestClassifyMatch:
    def test_auto_when_ratio_above_0_9(self) -> None:
        candidates = [BasenameMatch("Ansible", 0.95)]
        assert classify_match("AnsibleFVH", candidates) == ConfidenceTier.AUTO

    def test_confirm_when_between(self) -> None:
        candidates = [BasenameMatch("Kafka", 0.78)]
        assert classify_match("Kafkax", candidates) == ConfidenceTier.CONFIRM

    def test_no_canonical_when_below_0_7(self) -> None:
        candidates = [BasenameMatch("Some", 0.5)]
        assert classify_match("Xyz", candidates) == ConfidenceTier.NO_CANONICAL

    def test_no_canonical_when_empty(self) -> None:
        assert classify_match("Anything", []) == ConfidenceTier.NO_CANONICAL

    def test_inline_tag_syntax_always_skip(self) -> None:
        # Even with a perfect match, we skip inline-tag syntax.
        assert (
            classify_match("code", [BasenameMatch("code", 1.0)])
            == ConfidenceTier.SKIP
        )


class TestProposeRewrites:
    def test_filters_by_reference_count(self, tmp_path: Path) -> None:
        vault = _make_vault(
            tmp_path,
            {
                "Zettelkasten/Python.md": "no links\n",
                "Zettelkasten/Rust.md": "[[Pythn]]\n",
            },
        )
        audit = run_audit(vault)
        # Only one broken reference — below min_references=3 default.
        proposals = propose_rewrites(audit.links.top_broken(20), audit.index)
        assert all(p.reference_count >= 3 for p in proposals)

    def test_skips_rule_table_entries(self, tmp_path: Path) -> None:
        # Build a vault where a rule-table target appears as broken.
        # Rule table entry "AnsibleFVH" → "Ansible" — create several broken refs.
        files = {"Zettelkasten/Ansible.md": "# ansible\n"}
        for i in range(5):
            files[f"Zettelkasten/Other{i}.md"] = "[[AnsibleFVH]]\n"
        vault = _make_vault(tmp_path, files)
        audit = run_audit(vault)
        proposals = propose_rewrites(audit.links.top_broken(20), audit.index)
        targets = {p.target for p in proposals}
        assert "AnsibleFVH" not in targets
        # Assumption: at least one rule-table entry exists to skip.
        assert "AnsibleFVH" in BROKEN_LINK_REWRITES

    def test_produces_tier_for_each(self, tmp_path: Path) -> None:
        # Build a vault with at least 3 refs to "Pythn" (close to "Python").
        files = {"Zettelkasten/Python.md": "# python\n"}
        for i in range(5):
            files[f"Zettelkasten/Ref{i}.md"] = "[[Pythn]]\n"
        vault = _make_vault(tmp_path, files)
        audit = run_audit(vault)
        proposals = propose_rewrites(audit.links.top_broken(20), audit.index)
        assert proposals
        pythn = next((p for p in proposals if p.target == "Pythn"), None)
        assert pythn is not None
        # "Pythn" → "Python": SequenceMatcher("pythn","python").ratio() ≈ 0.91 → AUTO
        assert pythn.tier in (ConfidenceTier.AUTO, ConfidenceTier.CONFIRM)
        assert pythn.top_canonical == "Python"

    def test_to_dict_is_json_safe(self, tmp_path: Path) -> None:
        import json

        files = {"Zettelkasten/Python.md": "# python\n"}
        for i in range(5):
            files[f"Zettelkasten/Ref{i}.md"] = "[[Pythn]]\n"
        vault = _make_vault(tmp_path, files)
        audit = run_audit(vault)
        proposals = propose_rewrites(audit.links.top_broken(20), audit.index)
        for p in proposals:
            s = json.dumps(p.to_dict())
            assert "Pythn" in s or "target" in s
