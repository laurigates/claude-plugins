"""Regression tests for health scorer formatter and type checker detection.

Tests that _score_quality correctly detects formatters and type checkers
from various config file patterns, including standalone configs and
pre-commit hooks. Also covers _score_ci per-file feature scanning.
"""

from pathlib import Path
import tempfile

from git_repo_agent.tools.health_check import _score_ci, _score_quality


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


# --- CI scoring ---


class TestCiScoring:
    """Regression tests for _score_ci per-file feature scanning.

    _score_ci awards 8 points for having workflow files, plus 3 each for
    pull_request, push-to-main/master, release, and cache features. The
    push-to-main check must match "push" and "main"/"master" within a
    single workflow file — the old aggregated-content scan let the two
    keywords match across different files (cross-file false positive).
    """

    def test_cross_file_push_main_not_credited(self):
        """Regression: 'push' in one file + 'main' in another must not score.

        The pre-fix implementation concatenated all workflow contents into
        one string, so 'push' in ci.yml and 'main' in deploy.yml satisfied
        the push-to-main check even though no single workflow had both.
        """
        repo = _make_repo(
            ".github/workflows/ci.yml",
            ".github/workflows/deploy.yml",
            file_contents={
                ".github/workflows/ci.yml": "on:\n  push:\n",
                ".github/workflows/deploy.yml": (
                    "on:\n  workflow_dispatch:\nenv:\n  BRANCH: main\n"
                ),
            },
        )
        score, findings = _score_ci(repo)
        assert score == 8  # workflows present, no feature credited
        assert findings == []

    def test_single_file_push_main_credited(self):
        repo = _make_repo(
            ".github/workflows/ci.yml",
            file_contents={
                ".github/workflows/ci.yml": "on:\n  push:\n    branches: [main]\n"
            },
        )
        score, _ = _score_ci(repo)
        assert score == 11  # 8 base + 3 push-to-main

    def test_single_file_push_master_credited(self):
        repo = _make_repo(
            ".github/workflows/ci.yml",
            file_contents={
                ".github/workflows/ci.yml": "on:\n  push:\n    branches: [master]\n"
            },
        )
        score, _ = _score_ci(repo)
        assert score == 11  # 8 base + 3 push-to-master

    def test_all_features_single_file(self):
        repo = _make_repo(
            ".github/workflows/ci.yml",
            file_contents={
                ".github/workflows/ci.yml": (
                    "on:\n"
                    "  pull_request:\n"
                    "  push:\n"
                    "    branches: [main]\n"
                    "  release:\n"
                    "jobs:\n"
                    "  test:\n"
                    "    steps:\n"
                    "      - uses: actions/cache@v4\n"
                )
            },
        )
        score, _ = _score_ci(repo)
        assert score == 20  # 8 base + 4 features x 3

    def test_features_spread_across_files(self):
        """Independent features still accumulate across separate files."""
        repo = _make_repo(
            ".github/workflows/pr.yml",
            ".github/workflows/release.yml",
            file_contents={
                ".github/workflows/pr.yml": "on:\n  pull_request:\n",
                ".github/workflows/release.yml": "on:\n  release:\n",
            },
        )
        score, _ = _score_ci(repo)
        assert score == 14  # 8 base + pull_request + release

    def test_empty_workflows_dir_reports_finding(self):
        repo = _make_repo()
        (repo / ".github" / "workflows").mkdir(parents=True)
        score, findings = _score_ci(repo)
        assert score == 0
        assert ".github/workflows/ exists but has no workflow files" in findings

    def test_no_ci_configuration(self):
        repo = _make_repo()
        score, findings = _score_ci(repo)
        assert score == 0
        assert "No CI/CD configuration found" in findings
