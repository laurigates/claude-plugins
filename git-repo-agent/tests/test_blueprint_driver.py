"""Tests for the blueprint state-machine driver.

These tests do not call the SDK; they verify the driver's pure-Python
logic (skip policy, state hints, phase registry).
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from git_repo_agent.blueprint_driver import (
    ADR_LIST_PHASES,
    BlueprintDriver,
    DERIVE_PLANS_PHASES,
    DriverOptions,
    GENERATE_RULES_PHASES,
    ONBOARD_PHASES,
    PHASE_REGISTRIES,
    SCAN_PHASES,
    STATUS_PHASES,
    SYNC_PHASES,
    UPGRADE_PHASES,
    Phase,
    make_promote_phase,
    make_prp_create_phase,
    make_prp_execute_phase,
    make_work_order_phase,
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


class TestLifecycleRegistries:
    """Every non-onboard registry must reference compilable skills."""

    @pytest.mark.parametrize(
        "registry",
        [STATUS_PHASES, UPGRADE_PHASES, SYNC_PHASES, SCAN_PHASES],
    )
    def test_registry_skills_compile(self, registry):
        for phase in registry:
            body = get_compiled_skill(phase.skill_relpath)
            assert body, f"{phase.name}: empty compiled skill"

    def test_upgrade_runs_sync_ids_before_validate(self):
        names = [p.name for p in UPGRADE_PHASES]
        assert names.index("sync_ids") < names.index("adr_validate")

    def test_scan_starts_with_workspace_scan(self):
        assert SCAN_PHASES[0].name == "workspace_scan"

    def test_status_phases_are_readonly_by_model(self):
        # Status and scan should be cheap — haiku-only.
        for phase in STATUS_PHASES:
            assert phase.model == "haiku", phase.name
        for phase in SCAN_PHASES:
            assert phase.model == "haiku", phase.name

    def test_registries_are_registered_under_expected_keys(self):
        assert set(PHASE_REGISTRIES) == {
            "onboard",
            "new",
            "status",
            "upgrade",
            "sync",
            "scan",
            "adr-list",
            "derive-plans",
            "generate-rules",
        }
        assert PHASE_REGISTRIES["onboard"] is ONBOARD_PHASES
        assert PHASE_REGISTRIES["status"] is STATUS_PHASES
        assert PHASE_REGISTRIES["adr-list"] is ADR_LIST_PHASES

    def test_no_registry_has_duplicate_phase_names(self):
        for name, registry in PHASE_REGISTRIES.items():
            names = [p.name for p in registry]
            assert len(names) == len(set(names)), f"{name} has dupes: {names}"


class TestPhaseFactories:
    """Dynamic phase factories interpolate args into the invocation."""

    def test_prp_create_embeds_feature_slug(self):
        phase = make_prp_create_phase("auth-oauth2")
        assert "`auth-oauth2`" in phase.invocation
        assert phase.model == "sonnet"
        assert "blueprint-prp-create" in phase.skill_relpath

    def test_prp_execute_embeds_prp_name(self):
        phase = make_prp_execute_phase("feature-auth-oauth2")
        assert "`feature-auth-oauth2`" in phase.invocation
        assert "blueprint-prp-execute" in phase.skill_relpath

    def test_work_order_from_issue(self):
        phase = make_work_order_phase(from_issue=42, publish=True)
        assert "#42" in phase.invocation
        assert "local only" not in phase.invocation

    def test_work_order_no_publish(self):
        phase = make_work_order_phase(from_issue=None, publish=False)
        assert "local only" in phase.invocation

    def test_work_order_defaults_are_minimal(self):
        phase = make_work_order_phase()
        # no issue hint, no no-publish hint
        assert "#" not in phase.invocation
        assert "local only" not in phase.invocation

    def test_promote_embeds_target(self):
        phase = make_promote_phase("blueprint-derive-prd")
        assert "`blueprint-derive-prd`" in phase.invocation
        assert phase.model == "haiku"

    def test_factory_phases_reference_existing_skills(self):
        phases = [
            make_prp_create_phase("x"),
            make_prp_execute_phase("x"),
            make_work_order_phase(),
            make_promote_phase("x"),
        ]
        for phase in phases:
            body = get_compiled_skill(phase.skill_relpath)
            assert body, f"{phase.name}: empty compiled skill"


class TestBlueprintCliWiring:
    """Verify the Typer subcommands dispatch to the right registries."""

    def test_blueprint_subcommands_are_registered(self):
        from typer.testing import CliRunner

        from git_repo_agent.main import app

        runner = CliRunner()
        result = runner.invoke(app, ["blueprint", "--help"])
        assert result.exit_code == 0
        for sub in (
            "status",
            "upgrade",
            "sync",
            "scan",
            "adr-list",
            "derive-plans",
            "generate-rules",
            "promote",
            "prp-create",
            "prp-execute",
            "work-order",
        ):
            assert sub in result.stdout, sub

    def test_unknown_mode_exits_with_config_error(self, tmp_path: Path):
        from git_repo_agent.main import _run_blueprint_mode
        from git_repo_agent.non_interactive import EXIT_CONFIG_ERROR
        import typer

        with pytest.raises(typer.Exit) as excinfo:
            _run_blueprint_mode(str(tmp_path), mode="bogus", dry_run=False)
        assert excinfo.value.exit_code == EXIT_CONFIG_ERROR

    def test_nonexistent_repo_path_fails_fast(self, tmp_path: Path):
        from git_repo_agent.main import _run_blueprint_mode
        from git_repo_agent.non_interactive import EXIT_CONFIG_ERROR
        import typer

        bogus = tmp_path / "does-not-exist"
        with pytest.raises(typer.Exit) as excinfo:
            _run_blueprint_mode(str(bogus), mode="status", dry_run=False)
        assert excinfo.value.exit_code == EXIT_CONFIG_ERROR
