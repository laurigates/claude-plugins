"""Tests for orchestrator glue: prompt assembly, compact audits."""

from __future__ import annotations

import json
import textwrap
from pathlib import Path

import pytest

from vault_agent.analyzers.audit import run_audit
from vault_agent.orchestrator import build_system_prompt, _compact_audit_for_prompt


def _make_vault(tmp_path: Path, files: dict[str, str]) -> Path:
    for rel, content in files.items():
        path = tmp_path / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(content).lstrip("\n"), encoding="utf-8")
    return tmp_path


class TestBuildSystemPrompt:
    def test_prompt_includes_orchestrator_section(self, tmp_path: Path) -> None:
        vault = _make_vault(tmp_path, {"Zettelkasten/A.md": "# a\n"})
        audit = run_audit(vault)
        prompt = build_system_prompt("vault-lint", audit)
        assert "Vault Maintenance Orchestrator" in prompt

    def test_prompt_includes_mode_prompt(self, tmp_path: Path) -> None:
        vault = _make_vault(tmp_path, {"Zettelkasten/A.md": "# a\n"})
        audit = run_audit(vault)
        prompt = build_system_prompt("vault-lint", audit)
        assert "vault-lint subagent" in prompt

    def test_prompt_embeds_audit_json(self, tmp_path: Path) -> None:
        vault = _make_vault(tmp_path, {"Zettelkasten/A.md": "# a\n"})
        audit = run_audit(vault)
        prompt = build_system_prompt("vault-lint", audit)
        assert "Pre-computed audit" in prompt
        assert "```json" in prompt
        # The JSON block should be parseable
        start = prompt.find("```json") + len("```json\n")
        end = prompt.find("```", start)
        payload = prompt[start:end]
        parsed = json.loads(payload)
        assert "health" in parsed


class TestCompactAudit:
    def test_trims_long_lists(self, tmp_path: Path) -> None:
        # Build a vault that will produce long lists
        files = {f"Zettelkasten/Note{i:03d}.md": "no links\n" for i in range(40)}
        vault = _make_vault(tmp_path, files)
        audit = run_audit(vault)
        compact = _compact_audit_for_prompt(audit, sample=5)
        fm = compact["frontmatter"]
        # 40 notes without frontmatter; expect trimmed list with marker
        assert any(
            "more" in str(item) for item in fm["notes_without_frontmatter"]
        )
