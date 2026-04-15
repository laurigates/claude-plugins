"""Tests for the blueprint state-machine driver.

These tests do not call the SDK; they verify the driver's pure-Python
logic (skip policy, state hints, phase registry).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from git_repo_agent.blueprint_driver import (
    BlueprintDriver,
    DriverOptions,
    ONBOARD_PHASES,
    Phase,
)
from git_repo_agent.prompts.compiler import get_compiled_skill


class TestPhaseRegistry:
    def test_all_phases_reference_existing_skills(self):
        """Every phase's skill must actually exist and compile."""
        for phase in ONBOARD_PHASES:
            content = get_compiled_skill(phase.skill_relpath)
            assert content, f"{phase.name}: compiled skill is empty"

    def test_phase_names_are_unique(self):
        names = [p.name for p in ONBOARD_PHASES]
        assert len(names) == len(set(names))

    def test_models_are_valid(self):
        for phase in ONBOARD_PHASES:
            assert phase.model in {"haiku", "sonnet", "opus"}, phase.name

    def test_init_runs_before_derivation(self):
        names = [p.name for p in ONBOARD_PHASES]
        assert names.index("init") < names.index("derive_prd")
        assert names.index("init") < names.index("derive_adr")

    def test_sync_ids_runs_before_adr_validate(self):
        names = [p.name for p in ONBOARD_PHASES]
        assert names.index("sync_ids") < names.index("adr_validate")


class TestSkipPolicy:
    def test_skip_by_name(self, tmp_path: Path):
        driver = BlueprintDriver(
            tmp_path,
            DriverOptions(skip=frozenset({"derive_tests"})),
        )
        phase = next(p for p in ONBOARD_PHASES if p.name == "derive_tests")
        assert driver._should_skip(phase)

    def test_init_skipped_when_manifest_exists(self, tmp_path: Path):
        manifest = tmp_path / "docs" / "blueprint" / "manifest.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text("{}", encoding="utf-8")

        driver = BlueprintDriver(tmp_path, DriverOptions())
        phase = next(p for p in ONBOARD_PHASES if p.name == "init")
        assert driver._artifact_skip_reason(phase) == "manifest exists"

    def test_init_runs_when_manifest_missing(self, tmp_path: Path):
        driver = BlueprintDriver(tmp_path, DriverOptions())
        phase = next(p for p in ONBOARD_PHASES if p.name == "init")
        assert driver._artifact_skip_reason(phase) is None

    def test_workspace_scan_always_runs(self, tmp_path: Path):
        driver = BlueprintDriver(tmp_path, DriverOptions())
        phase = next(p for p in ONBOARD_PHASES if p.name == "workspace_scan")
        assert driver._artifact_skip_reason(phase) is None


class TestStateHint:
    def test_hint_when_uninitialized(self, tmp_path: Path):
        driver = BlueprintDriver(tmp_path, DriverOptions())
        hint = driver._state_hint()
        assert "not yet initialized" in hint

    def test_hint_when_initialized(self, tmp_path: Path):
        manifest = tmp_path / "docs" / "blueprint" / "manifest.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text(
            json.dumps(
                {
                    "format_version": "3.3.0",
                    "documents": [{"id": "PRD-001"}, {"id": "ADR-001"}],
                }
            ),
            encoding="utf-8",
        )

        driver = BlueprintDriver(tmp_path, DriverOptions())
        hint = driver._state_hint()
        assert "3.3.0" in hint
        assert "2 document" in hint

    def test_hint_when_manifest_is_malformed(self, tmp_path: Path):
        manifest = tmp_path / "docs" / "blueprint" / "manifest.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text("not json", encoding="utf-8")

        driver = BlueprintDriver(tmp_path, DriverOptions())
        hint = driver._state_hint()
        assert "could not be parsed" in hint


class TestPromptBuilding:
    def test_dry_run_prompt_mentions_no_writes(self, tmp_path: Path):
        driver = BlueprintDriver(tmp_path, DriverOptions(dry_run=True))
        phase = ONBOARD_PHASES[0]
        prompt = driver._build_prompt(phase)
        assert "DRY RUN" in prompt
        assert "do NOT write" in prompt.lower() or "do not write" in prompt.lower()

    def test_regular_prompt_has_invocation_and_cwd(self, tmp_path: Path):
        driver = BlueprintDriver(tmp_path, DriverOptions())
        phase = ONBOARD_PHASES[0]
        prompt = driver._build_prompt(phase)
        assert phase.invocation in prompt
        assert str(tmp_path) in prompt


class TestPhaseResultReporting:
    def test_unknown_skill_raises(self, tmp_path: Path):
        with pytest.raises(FileNotFoundError):
            get_compiled_skill("does-not-exist/SKILL.md")
