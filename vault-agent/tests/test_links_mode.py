"""Tests for the links-mode dry-run renderer."""

from __future__ import annotations

from vault_agent.links_mode import LinksPlan, render_dry_run


class TestRenderDryRun:
    def test_excludes_rule_table_targets_from_low_leverage_section(self) -> None:
        # Regression for #1075: a target that will be auto-rewritten by the
        # rule-table must not also appear under "not auto-fixed".
        plan = LinksPlan(
            rewrites_available={"AnsibleFVH": "Ansible"},
            kanban_candidates=0,
            ambiguous_basenames=[],
            low_leverage_broken=[("AnsibleFVH", 44), ("Nuuka REST API 2.0", 10)],
        )
        output = render_dry_run(plan)
        # The rule-table entry stays in the top section.
        assert "[[AnsibleFVH]] → [[Ansible]]" in output
        # But is filtered out of the bottom section.
        low_leverage_section = output.split(
            "Low-leverage broken targets (for reference — not auto-fixed):"
        )[1]
        assert "AnsibleFVH" not in low_leverage_section
        assert "Nuuka REST API 2.0" in low_leverage_section

    def test_no_rule_table_matches_still_renders(self) -> None:
        plan = LinksPlan(
            rewrites_available={},
            kanban_candidates=0,
            ambiguous_basenames=[],
            low_leverage_broken=[("ESP32 MOC", 9)],
        )
        output = render_dry_run(plan)
        assert "[[ESP32 MOC]] × 9" in output
        assert "(none apply in this vault)" in output
