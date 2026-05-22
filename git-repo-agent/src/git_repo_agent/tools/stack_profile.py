"""Project stack profile — what tools are already installed, what shape is the code.

Used by ``health_check.py`` to skip findings that don't apply to the
project's actual stack — e.g. don't recommend ESLint when ``biome.json``
exists, don't recommend a Python type checker when the project has no
Python code beyond a 5-line stub, don't recommend CodeQL when CI already
runs security tooling.

Issue #1359.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


# Patterns that indicate the file is a "trivial" Python loader/stub.
# ComfyUI custom-node packs ship a few-line ``__init__.py`` whose only
# job is to expose a ``WEB_DIRECTORY`` constant; auditing it as if it
# were a Python library is noise.
_COMFYUI_PACK_MARKERS = re.compile(
    r"^\s*WEB_DIRECTORY\s*=", re.MULTILINE,
)

# Heuristic threshold: when total non-test Python LOC is below this,
# treat the project as "Python-incidental" and suppress Python quality
# findings (type checker, coverage, py.typed, conftest.py).
_PYTHON_INCIDENTAL_LOC_THRESHOLD = 50


@dataclass(frozen=True)
class StackProfile:
    """Summary of what tooling is already installed and the project shape.

    Used by health-score functions to skip findings that would propose
    tools conflicting with what's already in place, or findings against
    aspects of the project that don't apply.

    All booleans default to ``False`` (conservative — don't suppress
    findings when we can't measure). Callers should treat each field as
    "we definitely know this is true" rather than "we know one way or
    the other".
    """

    # JS/TS quality stack
    has_biome: bool = False
    has_eslint: bool = False
    has_prettier: bool = False
    has_tsconfig: bool = False

    # Python quality stack
    has_ruff_lint: bool = False
    has_ruff_format: bool = False
    has_python_type_checker: bool = False  # mypy, pyright, basedpyright, ty
    python_type_checker_kind: str = ""  # "mypy" | "pyright" | "basedpyright" | "ty" | ""
    uses_uv: bool = False

    # CI security stack
    ci_has_security_scanning: bool = False  # gitleaks, trivy, semgrep, codeql, snyk, etc.
    ci_security_tools: tuple[str, ...] = field(default_factory=tuple)

    # Project shape
    is_comfyui_pack: bool = False
    is_python_incidental: bool = False  # < ~50 LOC of Python outside tests
    python_loc_outside_tests: int = 0


def _read_text(path: Path) -> str:
    """Read a file as text, returning '' on any failure."""
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def _detect_js_stack(repo: Path) -> dict[str, bool]:
    """Detect installed JS/TS tooling configs at the repo root."""
    has_biome = (repo / "biome.json").exists() or (repo / "biome.jsonc").exists()
    has_eslint = any(
        (repo / name).exists() for name in (
            ".eslintrc", ".eslintrc.json", ".eslintrc.js", ".eslintrc.cjs",
            "eslint.config.js", "eslint.config.mjs", "eslint.config.cjs",
        )
    )
    has_prettier = any(
        (repo / name).exists() for name in (
            ".prettierrc", ".prettierrc.json", ".prettierrc.yaml",
            ".prettierrc.yml", "prettier.config.js", "prettier.config.mjs",
            "prettier.config.cjs",
        )
    )
    has_tsconfig = (repo / "tsconfig.json").exists()
    return {
        "has_biome": has_biome,
        "has_eslint": has_eslint,
        "has_prettier": has_prettier,
        "has_tsconfig": has_tsconfig,
    }


def _detect_python_stack(repo: Path) -> dict[str, object]:
    """Detect installed Python tooling — ruff/mypy/pyright/ty/uv."""
    pyproject_text = _read_text(repo / "pyproject.toml")
    precommit_text = _read_text(repo / ".pre-commit-config.yaml")
    setupcfg_text = _read_text(repo / "setup.cfg")

    has_ruff_lint = (
        "[tool.ruff" in pyproject_text
        or (repo / "ruff.toml").exists()
        or (repo / ".ruff.toml").exists()
    )
    has_ruff_format = "[tool.ruff.format]" in pyproject_text or has_ruff_lint
    # ruff's `format` subcommand works without a [tool.ruff.format] table
    # — having ruff configured is enough to count as a formatter.

    uses_uv = (repo / "uv.lock").exists() or "uv_build" in pyproject_text

    # Type checker (the first found wins; the ordering reflects 2026
    # ecosystem reality: a uv+ruff project is most likely to add ty,
    # then basedpyright, then pyright, then mypy).
    type_checker_kind = ""
    if "[tool.ty" in pyproject_text:
        type_checker_kind = "ty"
    elif "[tool.basedpyright" in pyproject_text or (repo / "basedpyright").exists():
        type_checker_kind = "basedpyright"
    elif "[tool.pyright" in pyproject_text or (repo / "pyrightconfig.json").exists():
        type_checker_kind = "pyright"
    elif (
        "[tool.mypy" in pyproject_text
        or (repo / "mypy.ini").exists()
        or (repo / ".mypy.ini").exists()
        or "[mypy" in setupcfg_text
    ):
        type_checker_kind = "mypy"
    elif "pyright" in precommit_text or "mypy" in precommit_text or "ty" in precommit_text:
        # Fall back to pre-commit declarations; can't distinguish
        # confidently without parsing, so report a generic marker.
        type_checker_kind = "precommit"

    return {
        "has_ruff_lint": has_ruff_lint,
        "has_ruff_format": has_ruff_format,
        "uses_uv": uses_uv,
        "has_python_type_checker": bool(type_checker_kind),
        "python_type_checker_kind": type_checker_kind,
    }


def _detect_ci_security(repo: Path) -> dict[str, object]:
    """Scan ``.github/workflows/*.yml`` for known security tools."""
    workflows = repo / ".github" / "workflows"
    if not workflows.is_dir():
        return {"ci_has_security_scanning": False, "ci_security_tools": ()}

    tools: list[str] = []
    # The substring sniff is conservative — it under-counts if the
    # workflow references a tool only by uses: <action> path. That's
    # fine: a false negative produces a more verbose recommendation, a
    # false positive silently skips a useful one. Bias toward verbosity.
    detectors = {
        "gitleaks": ("gitleaks",),
        "trufflehog": ("trufflehog",),
        "codeql": ("codeql",),
        "trivy": ("trivy",),
        "grype": ("grype",),
        "semgrep": ("semgrep",),
        "snyk": ("snyk",),
        "dependency-review": ("dependency-review",),
        "osv-scanner": ("osv-scanner",),
    }
    for wf in workflows.glob("*.yml"):
        content = _read_text(wf).lower()
        if not content:
            continue
        for name, patterns in detectors.items():
            if name in tools:
                continue
            if any(p in content for p in patterns):
                tools.append(name)
    for wf in workflows.glob("*.yaml"):
        content = _read_text(wf).lower()
        if not content:
            continue
        for name, patterns in detectors.items():
            if name in tools:
                continue
            if any(p in content for p in patterns):
                tools.append(name)

    return {
        "ci_has_security_scanning": bool(tools),
        "ci_security_tools": tuple(sorted(tools)),
    }


def _count_python_loc_outside_tests(repo: Path) -> int:
    """Return total non-test Python LOC. Skips ``.venv`` and test paths."""
    skip_dir_names = {".venv", "venv", "node_modules", "tests", "test", "__pycache__"}
    total = 0
    for py in repo.rglob("*.py"):
        if not py.is_file():
            continue
        parts = py.relative_to(repo).parts
        if any(part in skip_dir_names for part in parts[:-1]):
            continue
        if py.name.startswith("test_") or py.name.endswith("_test.py"):
            continue
        try:
            total += sum(
                1 for line in py.read_text(encoding="utf-8", errors="replace").splitlines()
                if line.strip()  # non-blank
            )
        except OSError:
            continue
        if total >= _PYTHON_INCIDENTAL_LOC_THRESHOLD * 10:
            # Bail early — we only care about the < 50 boundary.
            return total
    return total


def _detect_project_shape(repo: Path) -> dict[str, object]:
    """Detect ComfyUI-pack pattern and Python-incidental projects."""
    init_py = repo / "__init__.py"
    is_comfyui_pack = bool(init_py.exists() and _COMFYUI_PACK_MARKERS.search(_read_text(init_py)))

    # Also scan the top-level package dir for the marker (some packs
    # put __init__.py inside the slug-named directory).
    if not is_comfyui_pack:
        for sub in repo.iterdir():
            if sub.is_dir() and not sub.name.startswith("."):
                child_init = sub / "__init__.py"
                if (
                    child_init.exists()
                    and _COMFYUI_PACK_MARKERS.search(_read_text(child_init))
                ):
                    is_comfyui_pack = True
                    break

    loc = _count_python_loc_outside_tests(repo)
    return {
        "is_comfyui_pack": is_comfyui_pack,
        "is_python_incidental": loc < _PYTHON_INCIDENTAL_LOC_THRESHOLD,
        "python_loc_outside_tests": loc,
    }


def profile_stack(repo_path: Path) -> StackProfile:
    """Compute a :class:`StackProfile` for ``repo_path``.

    Safe to call on any directory — returns a profile with all-False
    fields when no tooling is detected.
    """
    fields: dict[str, object] = {}
    fields.update(_detect_js_stack(repo_path))
    fields.update(_detect_python_stack(repo_path))
    fields.update(_detect_ci_security(repo_path))
    fields.update(_detect_project_shape(repo_path))
    return StackProfile(**fields)  # type: ignore[arg-type]
