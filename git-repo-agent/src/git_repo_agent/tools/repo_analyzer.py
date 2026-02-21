"""repo_analyze MCP tool — detects repository technology stack and structure."""

import json
import subprocess
from pathlib import Path
from typing import Any

from claude_agent_sdk import tool


def _read_json(path: Path) -> dict[str, Any] | None:
    """Read and parse a JSON file, returning None on failure."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def _read_toml(path: Path) -> dict[str, Any] | None:
    """Read and parse a TOML file, returning None on failure."""
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib  # type: ignore[no-redef]
        except ImportError:
            return None
    try:
        return tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, Exception):
        return None


def _detect_language(repo: Path) -> str:
    """Detect primary language from manifest files."""
    if (repo / "package.json").exists():
        return "typescript" if (repo / "tsconfig.json").exists() else "javascript"
    if (repo / "pyproject.toml").exists() or (repo / "setup.py").exists():
        return "python"
    if (repo / "Cargo.toml").exists():
        return "rust"
    if (repo / "go.mod").exists():
        return "go"
    if (repo / "build.gradle").exists() or (repo / "pom.xml").exists():
        return "java"
    return "unknown"


def _detect_framework(repo: Path, language: str) -> str:
    """Detect framework from dependencies."""
    if language in ("javascript", "typescript"):
        pkg = _read_json(repo / "package.json")
        if pkg:
            all_deps = {
                **pkg.get("dependencies", {}),
                **pkg.get("devDependencies", {}),
            }
            for fw, name in [
                ("next", "Next.js"),
                ("nuxt", "Nuxt"),
                ("@angular/core", "Angular"),
                ("react", "React"),
                ("vue", "Vue"),
                ("svelte", "Svelte"),
                ("express", "Express"),
                ("fastify", "Fastify"),
                ("hono", "Hono"),
            ]:
                if fw in all_deps:
                    return name
    elif language == "python":
        pyproject = _read_toml(repo / "pyproject.toml")
        if pyproject:
            deps = pyproject.get("project", {}).get("dependencies", [])
            deps_str = " ".join(deps) if isinstance(deps, list) else str(deps)
            for fw, name in [
                ("django", "Django"),
                ("flask", "Flask"),
                ("fastapi", "FastAPI"),
                ("starlette", "Starlette"),
            ]:
                if fw in deps_str.lower():
                    return name
    elif language == "rust":
        cargo = _read_toml(repo / "Cargo.toml")
        if cargo:
            deps = cargo.get("dependencies", {})
            for fw, name in [
                ("actix-web", "Actix Web"),
                ("axum", "Axum"),
                ("rocket", "Rocket"),
                ("bevy", "Bevy"),
            ]:
                if fw in deps:
                    return name
    return "none"


def _detect_package_manager(repo: Path, language: str) -> str:
    """Detect package manager."""
    if language in ("javascript", "typescript"):
        if (repo / "bun.lockb").exists() or (repo / "bun.lock").exists():
            return "bun"
        if (repo / "pnpm-lock.yaml").exists():
            return "pnpm"
        if (repo / "yarn.lock").exists():
            return "yarn"
        if (repo / "package-lock.json").exists():
            return "npm"
        return "npm"
    if language == "python":
        if (repo / "uv.lock").exists():
            return "uv"
        if (repo / "Pipfile").exists():
            return "pipenv"
        if (repo / "poetry.lock").exists():
            return "poetry"
        return "pip"
    if language == "rust":
        return "cargo"
    if language == "go":
        return "go"
    return "unknown"


def _detect_test_framework(repo: Path, language: str) -> str:
    """Detect test framework."""
    if language in ("javascript", "typescript"):
        pkg = _read_json(repo / "package.json")
        if pkg:
            dev_deps = pkg.get("devDependencies", {})
            if "vitest" in dev_deps:
                return "vitest"
            if "jest" in dev_deps:
                return "jest"
            if "@playwright/test" in dev_deps:
                return "playwright"
        if (repo / "vitest.config.ts").exists() or (repo / "vitest.config.js").exists():
            return "vitest"
    elif language == "python":
        pyproject = _read_toml(repo / "pyproject.toml")
        if pyproject:
            deps = pyproject.get("project", {}).get("dependencies", [])
            optional = pyproject.get("project", {}).get("optional-dependencies", {})
            dev_deps = optional.get("dev", []) + optional.get("test", [])
            all_deps_str = " ".join(deps + dev_deps).lower()
            if "pytest" in all_deps_str:
                return "pytest"
        if (repo / "tests").is_dir() or (repo / "test").is_dir():
            return "pytest"
    elif language == "rust":
        return "cargo-test"
    elif language == "go":
        return "go-test"
    return "none"


def _detect_linter(repo: Path, language: str) -> str:
    """Detect linter configuration."""
    if language in ("javascript", "typescript"):
        if (repo / "biome.json").exists() or (repo / "biome.jsonc").exists():
            return "biome"
        for eslint in [".eslintrc.json", ".eslintrc.js", ".eslintrc.cjs", "eslint.config.js", "eslint.config.mjs"]:
            if (repo / eslint).exists():
                return "eslint"
    elif language == "python":
        pyproject = _read_toml(repo / "pyproject.toml")
        if pyproject and "tool" in pyproject:
            if "ruff" in pyproject["tool"]:
                return "ruff"
            if "pylint" in pyproject["tool"]:
                return "pylint"
            if "flake8" in pyproject["tool"]:
                return "flake8"
        if (repo / ".ruff.toml").exists() or (repo / "ruff.toml").exists():
            return "ruff"
    elif language == "rust":
        return "clippy"
    return "none"


def _detect_formatter(repo: Path, language: str) -> str:
    """Detect formatter configuration."""
    if language in ("javascript", "typescript"):
        if (repo / "biome.json").exists() or (repo / "biome.jsonc").exists():
            return "biome"
        if (repo / ".prettierrc").exists() or (repo / ".prettierrc.json").exists():
            return "prettier"
    elif language == "python":
        pyproject = _read_toml(repo / "pyproject.toml")
        if pyproject and "tool" in pyproject:
            ruff_cfg = pyproject["tool"].get("ruff", {})
            if "format" in ruff_cfg:
                return "ruff"
            if "black" in pyproject["tool"]:
                return "black"
        if (repo / ".ruff.toml").exists() or (repo / "ruff.toml").exists():
            return "ruff"
    elif language == "rust":
        return "rustfmt"
    return "none"


def _detect_ci(repo: Path) -> str:
    """Detect CI system."""
    if (repo / ".github" / "workflows").is_dir():
        return "github-actions"
    if (repo / ".gitlab-ci.yml").exists():
        return "gitlab-ci"
    if (repo / ".circleci").is_dir():
        return "circleci"
    if (repo / "Jenkinsfile").exists():
        return "jenkins"
    return "none"


def _get_git_info(repo: Path) -> dict[str, Any]:
    """Get basic git information."""
    info: dict[str, Any] = {
        "is_repo": (repo / ".git").exists(),
        "branch": "unknown",
        "remote": "none",
        "commit_count": 0,
    }
    if not info["is_repo"]:
        return info

    try:
        result = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            info["branch"] = result.stdout.strip() or "HEAD"
    except (subprocess.SubprocessError, OSError):
        pass

    try:
        result = subprocess.run(
            ["git", "remote", "get-url", "origin"],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=5,
        )
        if result.returncode == 0:
            info["remote"] = result.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        pass

    try:
        result = subprocess.run(
            ["git", "rev-list", "--count", "HEAD"],
            cwd=repo,
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode == 0:
            info["commit_count"] = int(result.stdout.strip())
    except (subprocess.SubprocessError, OSError, ValueError):
        pass

    return info


def analyze_repo(repo_path: Path) -> dict[str, Any]:
    """Analyze a repository and return structured metadata."""
    language = _detect_language(repo_path)
    return {
        "language": language,
        "framework": _detect_framework(repo_path, language),
        "package_manager": _detect_package_manager(repo_path, language),
        "test_framework": _detect_test_framework(repo_path, language),
        "linter": _detect_linter(repo_path, language),
        "formatter": _detect_formatter(repo_path, language),
        "ci_system": _detect_ci(repo_path),
        "has_claude_md": (repo_path / "CLAUDE.md").exists(),
        "has_blueprint": (repo_path / "docs" / "blueprint").is_dir(),
        "has_readme": (repo_path / "README.md").exists(),
        "has_pre_commit": (repo_path / ".pre-commit-config.yaml").exists(),
        "git_info": _get_git_info(repo_path),
    }


@tool(
    "repo_analyze",
    "Analyze repository structure, technology stack, and existing tooling. "
    "Returns language, framework, package manager, test/lint/format tools, CI system, "
    "and blueprint status.",
    {"path": str},
)
async def repo_analyze(args: dict[str, Any]) -> dict[str, Any]:
    """MCP tool handler for repo analysis."""
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
    result = analyze_repo(repo_path)
    return {
        "content": [
            {
                "type": "text",
                "text": json.dumps(result, indent=2),
            }
        ]
    }
