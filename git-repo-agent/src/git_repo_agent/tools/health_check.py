"""health_score MCP tool — compute repository health from findings."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from claude_agent_sdk import tool

from .stack_profile import StackProfile, profile_stack


def _score_docs(repo: Path) -> tuple[int, list[str]]:
    """Score documentation health (0-20)."""
    score = 0
    findings: list[str] = []

    if (repo / "README.md").exists():
        readme = (repo / "README.md").read_text(encoding="utf-8", errors="replace")
        score += 5
        if len(readme) > 200:
            score += 3
        else:
            findings.append("README.md is very short (< 200 chars)")
    else:
        findings.append("Missing README.md")

    if (repo / "CLAUDE.md").exists():
        score += 4
    else:
        findings.append("Missing CLAUDE.md")

    if (repo / "docs").is_dir():
        score += 3
    else:
        findings.append("No docs/ directory")

    if (repo / "docs" / "blueprint").is_dir():
        score += 3

    if (repo / "LICENSE").exists() or (repo / "LICENSE.md").exists():
        score += 2
    else:
        findings.append("Missing LICENSE file")

    return min(score, 20), findings


def _score_tests(repo: Path) -> tuple[int, list[str]]:
    """Score testing health (0-20)."""
    score = 0
    findings: list[str] = []

    test_dirs = [repo / "tests", repo / "test", repo / "src" / "tests"]
    has_tests = any(d.is_dir() for d in test_dirs)

    if has_tests:
        score += 8
    else:
        # Check for inline test files
        test_files = list(repo.rglob("*test*"))
        test_files = [f for f in test_files if f.is_file() and ".venv" not in str(f)]
        if test_files:
            score += 5
        else:
            findings.append("No test directory or test files found")

    # Check for test config
    test_configs = [
        "vitest.config.ts", "vitest.config.js",
        "jest.config.js", "jest.config.ts",
        "pytest.ini", "conftest.py",
        "playwright.config.ts",
    ]
    if any((repo / cfg).exists() for cfg in test_configs):
        score += 4
    elif has_tests:
        findings.append("Tests exist but no test configuration file found")

    # Check for CI test step (look in workflows)
    workflows_dir = repo / ".github" / "workflows"
    if workflows_dir.is_dir():
        for wf in workflows_dir.glob("*.yml"):
            try:
                content = wf.read_text(encoding="utf-8", errors="replace")
                if "test" in content.lower():
                    score += 5
                    break
            except OSError:
                pass
        else:
            findings.append("No CI workflow runs tests")

    # Coverage config
    coverage_indicators = [
        ".coveragerc", "coverage.config.js",
        "codecov.yml", ".codecov.yml",
    ]
    if any((repo / f).exists() for f in coverage_indicators):
        score += 3

    return min(score, 20), findings


def _score_security(
    repo: Path, profile: StackProfile | None = None,
) -> tuple[int, list[str]]:
    """Score security health (0-20).

    Stack-aware (issue #1359): when CI already runs known security
    tooling (gitleaks, trivy, codeql, etc.), credit the score and
    omit the "no security scanning" finding even if the substring
    heuristic below would have missed it.
    """
    score = 0
    findings: list[str] = []

    # .gitignore
    if (repo / ".gitignore").exists():
        gitignore = (repo / ".gitignore").read_text(encoding="utf-8", errors="replace")
        score += 4
        # Check for common sensitive patterns
        sensitive_patterns = [".env", "*.pem", "*.key", "credentials"]
        for pattern in sensitive_patterns:
            if pattern in gitignore:
                score += 1
                break
    else:
        findings.append("Missing .gitignore")

    # No .env committed
    if (repo / ".env").exists():
        findings.append(".env file exists in repository (should be gitignored)")
    else:
        score += 4

    # Pre-commit hooks
    if (repo / ".pre-commit-config.yaml").exists():
        score += 4
    else:
        findings.append("No pre-commit hooks configured")

    # Security-related CI checks
    workflows_dir = repo / ".github" / "workflows"
    security_found = False
    if profile is not None and profile.ci_has_security_scanning:
        security_found = True
        score += 4
    elif workflows_dir.is_dir():
        for wf in workflows_dir.glob("*.yml"):
            try:
                content = wf.read_text(encoding="utf-8", errors="replace").lower()
                if any(kw in content for kw in ["security", "audit", "dependabot", "codeql", "snyk"]):
                    score += 4
                    security_found = True
                    break
            except OSError:
                pass
    if not security_found and workflows_dir.is_dir():
        findings.append("No security scanning in CI")

    # Dependabot
    if (repo / ".github" / "dependabot.yml").exists():
        score += 3
    else:
        findings.append("No Dependabot configuration")

    return min(score, 20), findings


def _score_quality(
    repo: Path, profile: StackProfile | None = None,
) -> tuple[int, list[str]]:
    """Score code quality health (0-20).

    Stack-aware (issue #1359):

      - When ``biome.json`` is present, both the linter and formatter
        slots are credited (biome replaces both ESLint and Prettier).
      - When ruff is configured, both linter and formatter are credited
        (ruff's ``format`` subcommand works whenever ``[tool.ruff]`` is
        present, even without ``[tool.ruff.format]``).
      - The "No type checking" finding is suppressed for
        Python-incidental projects (e.g. ComfyUI custom-node packs
        with a 5-line ``__init__.py``) because there is nothing to
        type-check.
      - For Astral-aligned projects (uv + ruff) without a type
        checker, the finding wording prefers Astral's ``ty`` over
        mypy/pyright to match the project's tool family.
    """
    score = 0
    findings: list[str] = []

    # Linter config
    linter_configs = [
        "biome.json", "biome.jsonc",
        ".eslintrc.json", ".eslintrc.js", "eslint.config.js", "eslint.config.mjs",
        ".ruff.toml", "ruff.toml",
    ]
    if any((repo / f).exists() for f in linter_configs):
        score += 6
    else:
        # Check pyproject.toml for ruff config
        pyproject = repo / "pyproject.toml"
        if pyproject.exists():
            try:
                content = pyproject.read_text(encoding="utf-8")
                if "tool.ruff" in content or "tool.pylint" in content:
                    score += 6
            except OSError:
                pass
        if score == 0:
            findings.append("No linter configured")

    # Formatter config — biome and ruff each cover the formatter slot.
    formatter_configs = [
        "biome.json", "biome.jsonc",
        ".prettierrc", ".prettierrc.json", ".prettierrc.yaml", ".prettierrc.yml",
        "prettier.config.js", "prettier.config.mjs", "prettier.config.cjs",
        ".clang-format",
        "ruff.toml", ".ruff.toml",
        ".rustfmt.toml", "rustfmt.toml",
        ".scalafmt.conf",
    ]
    if any((repo / f).exists() for f in formatter_configs):
        score += 5
    else:
        formatter_found = False
        if profile is not None and profile.has_ruff_format:
            score += 5
            formatter_found = True
        elif (repo / "pyproject.toml").exists():
            try:
                content = (repo / "pyproject.toml").read_text(encoding="utf-8")
                if "tool.ruff" in content or "tool.black" in content:
                    score += 5
                    formatter_found = True
            except OSError:
                pass
        if not formatter_found:
            findings.append("No formatter configured")

    # Type checking — suppress finding for Python-incidental projects.
    type_configs = [
        "tsconfig.json",
        "pyrightconfig.json", "basedpyright",
        "mypy.ini", ".mypy.ini",
    ]
    if any((repo / f).exists() for f in type_configs):
        score += 5
    else:
        typechecker_found = False
        if profile is not None and profile.has_python_type_checker:
            score += 5
            typechecker_found = True
        # Check pyproject.toml
        if not typechecker_found and (repo / "pyproject.toml").exists():
            try:
                content = (repo / "pyproject.toml").read_text(encoding="utf-8")
                if any(t in content for t in ["tool.pyright", "tool.basedpyright", "tool.mypy", "tool.ty"]):
                    score += 5
                    typechecker_found = True
            except OSError:
                pass
        # Check setup.cfg for [mypy]
        if not typechecker_found and (repo / "setup.cfg").exists():
            try:
                content = (repo / "setup.cfg").read_text(encoding="utf-8")
                if "[mypy" in content:
                    score += 5
                    typechecker_found = True
            except OSError:
                pass
        # Check pre-commit for type checker hooks
        if not typechecker_found:
            pre_commit = repo / ".pre-commit-config.yaml"
            if pre_commit.exists():
                try:
                    content = pre_commit.read_text(encoding="utf-8")
                    if "mypy" in content or "pyright" in content:
                        score += 5
                        typechecker_found = True
                except OSError:
                    pass
        if not typechecker_found:
            # Stack-aware suppression: don't recommend type checking for
            # projects that have essentially no Python to check.
            if profile is not None and (
                profile.is_comfyui_pack or profile.is_python_incidental
            ):
                # No finding emitted — but also no score credit.
                pass
            else:
                # Stack-aware wording: for uv+ruff (Astral) projects,
                # default the recommendation to ``ty``. Otherwise leave
                # the generic message so a JS/TS project doesn't see a
                # Python-specific suggestion.
                if profile is not None and profile.uses_uv and profile.has_ruff_lint:
                    findings.append(
                        "No type checking configured (recommend `ty` — "
                        "Astral's type checker, matches the uv+ruff stack)"
                    )
                else:
                    findings.append("No type checking configured")

    # Editor config
    if (repo / ".editorconfig").exists():
        score += 2

    # Justfile or Makefile for task running
    if (repo / "justfile").exists() or (repo / "Makefile").exists():
        score += 2

    return min(score, 20), findings


def _score_ci(repo: Path) -> tuple[int, list[str]]:
    """Score CI/CD health (0-20)."""
    score = 0
    findings: list[str] = []

    workflows_dir = repo / ".github" / "workflows"
    if not workflows_dir.is_dir():
        # Check for other CI systems
        if (repo / ".gitlab-ci.yml").exists():
            score += 10
        elif (repo / "Jenkinsfile").exists():
            score += 8
        else:
            findings.append("No CI/CD configuration found")
            return 0, findings

    if workflows_dir.is_dir():
        workflow_files = list(workflows_dir.glob("*.yml"))
        if workflow_files:
            score += 8

            # Check for specific CI features
            all_content = ""
            for wf in workflow_files:
                try:
                    all_content += wf.read_text(encoding="utf-8", errors="replace").lower()
                except OSError:
                    pass

            if "pull_request" in all_content:
                score += 3
            if "push" in all_content and ("main" in all_content or "master" in all_content):
                score += 3
            if "release" in all_content:
                score += 3
            if "cache" in all_content:
                score += 3
        else:
            findings.append(".github/workflows/ exists but has no workflow files")

    return min(score, 20), findings


def _grade(overall_score: int) -> str:
    """Convert numeric score to letter grade."""
    if overall_score >= 90:
        return "A"
    if overall_score >= 80:
        return "B"
    if overall_score >= 70:
        return "C"
    if overall_score >= 60:
        return "D"
    return "F"


def compute_health_score(repo_path: Path) -> dict[str, Any]:
    """Compute repository health score with category breakdown.

    Computes a :class:`StackProfile` once and passes it to scorers that
    use it to skip findings that don't apply to the project's actual
    stack (issue #1359). The profile is also surfaced under the
    ``stack_profile`` key in the result so downstream consumers (and
    the agent prompt) can see what was detected.
    """
    profile = profile_stack(repo_path)

    # The profile-aware scorers accept an optional second argument; the
    # plain ones ignore it. Pass the profile uniformly so future scorers
    # can opt in without changing the dispatch.
    profile_aware_scorers: dict[str, Any] = {
        "docs": _score_docs,
        "tests": _score_tests,
        "security": _score_security,
        "quality": _score_quality,
        "ci": _score_ci,
    }

    category_scores: dict[str, int] = {}
    all_findings: dict[str, list[str]] = {}

    for cat_name, scorer in profile_aware_scorers.items():
        # Use a parameter probe so we only forward the profile to
        # scorers that accept it. Cheaper than introspection: every
        # scorer here is called with profile as keyword arg when its
        # signature supports it.
        try:
            cat_score, cat_findings = scorer(repo_path, profile=profile)  # type: ignore[call-arg]
        except TypeError:
            cat_score, cat_findings = scorer(repo_path)
        category_scores[cat_name] = cat_score
        if cat_findings:
            all_findings[cat_name] = cat_findings

    overall_score = sum(category_scores.values())

    return {
        "overall_score": overall_score,
        "grade": _grade(overall_score),
        "category_scores": category_scores,
        "findings": all_findings,
        "max_score": 100,
        "stack_profile": {
            "has_biome": profile.has_biome,
            "has_eslint": profile.has_eslint,
            "has_prettier": profile.has_prettier,
            "has_tsconfig": profile.has_tsconfig,
            "has_ruff_lint": profile.has_ruff_lint,
            "has_ruff_format": profile.has_ruff_format,
            "has_python_type_checker": profile.has_python_type_checker,
            "python_type_checker_kind": profile.python_type_checker_kind,
            "uses_uv": profile.uses_uv,
            "ci_has_security_scanning": profile.ci_has_security_scanning,
            "ci_security_tools": list(profile.ci_security_tools),
            "is_comfyui_pack": profile.is_comfyui_pack,
            "is_python_incidental": profile.is_python_incidental,
            "python_loc_outside_tests": profile.python_loc_outside_tests,
        },
    }


@tool(
    "health_score",
    "Compute repository health score from static analysis of project structure. "
    "Scores 5 categories (docs, tests, security, quality, ci) each 0-20, "
    "summed to 0-100 with letter grade.",
    {"path": str},
)
async def health_score(args: dict[str, Any]) -> dict[str, Any]:
    """MCP tool handler for health scoring."""
    repo_path = Path(args["path"]).resolve()
    if not repo_path.is_dir():
        return {
            "content": [
                {
                    "type": "text",
                    "text": f"Error: {repo_path} is not a valid directory",
                }
            ]
        }
    result = compute_health_score(repo_path)
    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(result, indent=2),
            }
        ]
    }
