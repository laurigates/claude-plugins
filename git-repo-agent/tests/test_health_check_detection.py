"""Regression tests for health scorer formatter and type checker detection.

Tests that _score_quality correctly detects formatters and type checkers
from various config file patterns, including standalone configs and
pre-commit hooks.
"""

from pathlib import Path
import tempfile

from git_repo_agent.tools.health_check import _score_quality


def _make_repo(*files: str, file_contents: dict[str, str] | None = None) -> Path:
    """Create a temporary repo directory with the given files."""
    tmp = Path(tempfile.mkdtemp())
    for f in files:
        path = tmp / f
        path.parent.mkdir(parents=True, exist_ok=True)
        content = (file_contents or {}).get(f, "")
        path.write_text(content, encoding="utf-8")
    return tmp


# --- Formatter detection ---


class TestFormatterDetection:
    def test_clang_format(self):
        repo = _make_repo(".clang-format")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_ruff_toml_standalone(self):
        repo = _make_repo("ruff.toml")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_dot_ruff_toml_standalone(self):
        repo = _make_repo(".ruff.toml")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_rustfmt_toml(self):
        repo = _make_repo(".rustfmt.toml")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_scalafmt_conf(self):
        repo = _make_repo(".scalafmt.conf")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_prettierrc_yaml(self):
        repo = _make_repo(".prettierrc.yaml")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_prettier_config_mjs(self):
        repo = _make_repo("prettier.config.mjs")
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_pyproject_with_ruff(self):
        repo = _make_repo(
            "pyproject.toml",
            file_contents={"pyproject.toml": "[tool.ruff]\nline-length = 88\n"},
        )
        score, findings = _score_quality(repo)
        assert "No formatter configured" not in findings

    def test_pyproject_without_formatter_reports_finding(self):
        """Regression: pyproject.toml without tool.ruff/tool.black should still report."""
        repo = _make_repo(
            "pyproject.toml",
            file_contents={"pyproject.toml": "[project]\nname = 'foo'\n"},
        )
        score, findings = _score_quality(repo)
        assert "No formatter configured" in findings

    def test_no_formatter_at_all(self):
        repo = _make_repo()
        _, findings = _score_quality(repo)
        assert "No formatter configured" in findings


# --- Type checker detection ---


class TestTypeCheckerDetection:
    def test_mypy_ini(self):
        repo = _make_repo("mypy.ini")
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_dot_mypy_ini(self):
        repo = _make_repo(".mypy.ini")
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_tsconfig(self):
        repo = _make_repo("tsconfig.json")
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_pyproject_with_mypy(self):
        repo = _make_repo(
            "pyproject.toml",
            file_contents={"pyproject.toml": "[tool.mypy]\nstrict = true\n"},
        )
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_setup_cfg_with_mypy(self):
        repo = _make_repo(
            "setup.cfg",
            file_contents={"setup.cfg": "[mypy]\nstrict = true\n"},
        )
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_pre_commit_with_mypy(self):
        repo = _make_repo(
            ".pre-commit-config.yaml",
            file_contents={
                ".pre-commit-config.yaml": (
                    "repos:\n"
                    "  - repo: https://github.com/pre-commit/mirrors-mypy\n"
                    "    hooks:\n"
                    "      - id: mypy\n"
                )
            },
        )
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_pre_commit_with_pyright(self):
        repo = _make_repo(
            ".pre-commit-config.yaml",
            file_contents={
                ".pre-commit-config.yaml": (
                    "repos:\n"
                    "  - repo: https://github.com/RobertCraiworthy/pyright-python\n"
                    "    hooks:\n"
                    "      - id: pyright\n"
                )
            },
        )
        score, findings = _score_quality(repo)
        assert "No type checking configured" not in findings

    def test_pyproject_without_typechecker_reports_finding(self):
        """Regression: pyproject.toml without type checker should still report."""
        repo = _make_repo(
            "pyproject.toml",
            file_contents={"pyproject.toml": "[project]\nname = 'foo'\n"},
        )
        _, findings = _score_quality(repo)
        assert "No type checking configured" in findings

    def test_no_typechecker_at_all(self):
        repo = _make_repo()
        _, findings = _score_quality(repo)
        assert "No type checking configured" in findings
