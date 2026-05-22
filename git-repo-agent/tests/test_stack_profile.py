"""Regression tests for issue #1359 — stack-aware findings.

The maintain pass previously generated findings from a generic Python-
library template, recommending tools that conflict with the project's
chosen stack (e.g. ESLint when biome is already installed, pyright when
the project has no Python beyond a 5-line stub).

These tests pin the :class:`StackProfile` behaviour that
``health_check.compute_health_score`` consults to suppress those
findings.
"""

from __future__ import annotations

from pathlib import Path

from git_repo_agent.tools.health_check import (
    _score_quality,
    _score_security,
    compute_health_score,
)
from git_repo_agent.tools.stack_profile import StackProfile, profile_stack


def _write(path: Path, content: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


class TestStackProfileJS:
    def test_empty_repo_detects_nothing(self, tmp_path: Path):
        profile = profile_stack(tmp_path)
        assert isinstance(profile, StackProfile)
        assert not profile.has_biome
        assert not profile.has_eslint
        assert not profile.has_prettier
        assert not profile.has_tsconfig

    def test_biome_json_detected(self, tmp_path: Path):
        _write(tmp_path / "biome.json", "{}")
        profile = profile_stack(tmp_path)
        assert profile.has_biome

    def test_biome_jsonc_detected(self, tmp_path: Path):
        _write(tmp_path / "biome.jsonc", "{}")
        profile = profile_stack(tmp_path)
        assert profile.has_biome

    def test_eslint_config_detected(self, tmp_path: Path):
        _write(tmp_path / "eslint.config.js", "")
        profile = profile_stack(tmp_path)
        assert profile.has_eslint

    def test_prettier_config_detected(self, tmp_path: Path):
        _write(tmp_path / ".prettierrc.json", "{}")
        profile = profile_stack(tmp_path)
        assert profile.has_prettier


class TestStackProfilePython:
    def test_ruff_in_pyproject(self, tmp_path: Path):
        _write(
            tmp_path / "pyproject.toml",
            "[tool.ruff]\nline-length = 100\n",
        )
        profile = profile_stack(tmp_path)
        assert profile.has_ruff_lint
        # Ruff's format subcommand works without [tool.ruff.format].
        assert profile.has_ruff_format

    def test_uv_lock_detected(self, tmp_path: Path):
        _write(tmp_path / "uv.lock", "version = 1\n")
        profile = profile_stack(tmp_path)
        assert profile.uses_uv

    def test_uv_build_backend_detected(self, tmp_path: Path):
        _write(
            tmp_path / "pyproject.toml",
            '[build-system]\nrequires = ["uv_build"]\n',
        )
        profile = profile_stack(tmp_path)
        assert profile.uses_uv

    def test_ty_type_checker_detected(self, tmp_path: Path):
        _write(tmp_path / "pyproject.toml", "[tool.ty]\n")
        profile = profile_stack(tmp_path)
        assert profile.has_python_type_checker
        assert profile.python_type_checker_kind == "ty"

    def test_basedpyright_detected(self, tmp_path: Path):
        _write(tmp_path / "pyproject.toml", "[tool.basedpyright]\n")
        profile = profile_stack(tmp_path)
        assert profile.python_type_checker_kind == "basedpyright"

    def test_pyright_detected(self, tmp_path: Path):
        _write(tmp_path / "pyrightconfig.json", "{}")
        profile = profile_stack(tmp_path)
        assert profile.python_type_checker_kind == "pyright"

    def test_mypy_detected(self, tmp_path: Path):
        _write(tmp_path / "pyproject.toml", "[tool.mypy]\n")
        profile = profile_stack(tmp_path)
        assert profile.python_type_checker_kind == "mypy"


class TestStackProfileCISecurity:
    def test_no_workflows_means_no_security(self, tmp_path: Path):
        profile = profile_stack(tmp_path)
        assert not profile.ci_has_security_scanning
        assert profile.ci_security_tools == ()

    def test_gitleaks_workflow_detected(self, tmp_path: Path):
        _write(
            tmp_path / ".github" / "workflows" / "ci.yml",
            "name: ci\non: push\njobs:\n  scan:\n    steps:\n      - uses: gitleaks/gitleaks-action@v2\n",
        )
        profile = profile_stack(tmp_path)
        assert profile.ci_has_security_scanning
        assert "gitleaks" in profile.ci_security_tools

    def test_trivy_workflow_detected(self, tmp_path: Path):
        _write(
            tmp_path / ".github" / "workflows" / "security.yml",
            "name: scan\non: push\njobs:\n  trivy:\n    steps:\n      - uses: aquasecurity/trivy-action@v0\n",
        )
        profile = profile_stack(tmp_path)
        assert profile.ci_has_security_scanning
        assert "trivy" in profile.ci_security_tools


class TestStackProfileProjectShape:
    def test_comfyui_pack_detected_top_level(self, tmp_path: Path):
        _write(
            tmp_path / "__init__.py",
            'WEB_DIRECTORY = "./web"\nNODE_CLASS_MAPPINGS = {}\n',
        )
        profile = profile_stack(tmp_path)
        assert profile.is_comfyui_pack

    def test_comfyui_pack_detected_in_subdirectory(self, tmp_path: Path):
        _write(
            tmp_path / "my-pack" / "__init__.py",
            'WEB_DIRECTORY = "./web"\n',
        )
        profile = profile_stack(tmp_path)
        assert profile.is_comfyui_pack

    def test_python_incidental_for_tiny_pack(self, tmp_path: Path):
        _write(
            tmp_path / "__init__.py",
            'WEB_DIRECTORY = "./web"\nNODE_CLASS_MAPPINGS = {}\n',
        )
        profile = profile_stack(tmp_path)
        assert profile.is_python_incidental
        assert profile.python_loc_outside_tests < 50

    def test_not_python_incidental_for_real_library(self, tmp_path: Path):
        body_lines = "\n".join(f"x_{i} = {i}" for i in range(80))
        _write(tmp_path / "src" / "lib.py", body_lines)
        profile = profile_stack(tmp_path)
        assert not profile.is_python_incidental
        assert profile.python_loc_outside_tests >= 50


class TestScoreQualityStackAware:
    """Issue #1359: _score_quality respects existing stack."""

    def test_biome_credits_formatter_slot(self, tmp_path: Path):
        _write(tmp_path / "biome.json", "{}")
        profile = profile_stack(tmp_path)
        _, findings = _score_quality(tmp_path, profile=profile)
        assert "No formatter configured" not in findings

    def test_comfyui_pack_no_type_checker_finding(self, tmp_path: Path):
        """A ComfyUI pack with a 5-line stub doesn't need a type checker."""
        _write(
            tmp_path / "__init__.py",
            'WEB_DIRECTORY = "./web"\nNODE_CLASS_MAPPINGS = {}\n',
        )
        profile = profile_stack(tmp_path)
        _, findings = _score_quality(tmp_path, profile=profile)
        assert "No type checking configured" not in findings
        # And the more verbose ty-variant should also be absent.
        assert not any("type checking" in f for f in findings)

    def test_python_incidental_no_type_checker_finding(self, tmp_path: Path):
        """Trivial-Python projects suppress the type-checker finding."""
        _write(tmp_path / "loader.py", "X = 1\n")
        profile = profile_stack(tmp_path)
        _, findings = _score_quality(tmp_path, profile=profile)
        assert not any("type checking" in f for f in findings)

    def test_real_python_library_still_warns(self, tmp_path: Path):
        body = "\n".join(f"x_{i} = {i}" for i in range(80))
        _write(tmp_path / "src" / "lib.py", body)
        profile = profile_stack(tmp_path)
        _, findings = _score_quality(tmp_path, profile=profile)
        assert any("type checking" in f for f in findings)

    def test_uv_ruff_project_recommends_ty(self, tmp_path: Path):
        """uv+ruff project gets the ty-variant wording, not generic."""
        _write(
            tmp_path / "pyproject.toml",
            '[tool.ruff]\nline-length = 100\n\n'
            '[build-system]\nrequires = ["uv_build"]\n',
        )
        # Add enough Python LOC so the project isn't tagged "incidental".
        body = "\n".join(f"x_{i} = {i}" for i in range(80))
        _write(tmp_path / "src" / "lib.py", body)
        profile = profile_stack(tmp_path)
        _, findings = _score_quality(tmp_path, profile=profile)
        assert any(
            "ty" in f and "Astral" in f for f in findings
        ), f"Expected ty/Astral wording in: {findings}"


class TestScoreSecurityStackAware:
    """Issue #1359: ``_score_security`` credits existing CI security tooling."""

    def test_existing_gitleaks_workflow_credits_score(self, tmp_path: Path):
        _write(
            tmp_path / ".github" / "workflows" / "ci.yml",
            "jobs:\n  scan:\n    steps:\n      - uses: gitleaks/gitleaks-action@v2\n",
        )
        profile = profile_stack(tmp_path)
        _, findings = _score_security(tmp_path, profile=profile)
        assert "No security scanning in CI" not in findings


class TestComputeHealthScoreStackProfile:
    """The top-level result must surface the stack profile."""

    def test_stack_profile_in_output(self, tmp_path: Path):
        _write(tmp_path / "biome.json", "{}")
        _write(tmp_path / "pyproject.toml", "[tool.ruff]\n")
        result = compute_health_score(tmp_path)
        assert "stack_profile" in result
        sp = result["stack_profile"]
        assert sp["has_biome"] is True
        assert sp["has_ruff_lint"] is True

    def test_comfyui_pack_no_type_finding_in_aggregated_output(self, tmp_path: Path):
        _write(
            tmp_path / "__init__.py",
            'WEB_DIRECTORY = "./web"\n',
        )
        result = compute_health_score(tmp_path)
        quality_findings = result["findings"].get("quality", [])
        assert not any("type checking" in f for f in quality_findings)
