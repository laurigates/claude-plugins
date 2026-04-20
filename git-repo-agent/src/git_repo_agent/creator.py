"""Local genesis for ``git-repo-agent new`` (Phase 2 of the plan).

Pure Python — no SDK. Given a ``NewProjectSpec`` this module:

1. Creates the target directory
2. Runs ``git init -b main``
3. Renders seed templates (README, .gitignore, initial PRD)
4. Writes ``.claude/settings.json`` via ``plugin_enroller``
5. Stages everything and creates a single initial commit on ``main``

Phase 4 (``gh repo create`` + push) is handled separately by the ``new``
command so dry-run and ``--no-remote`` can short-circuit before touching
GitHub.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from .plugin_enroller import (
    select_permissions,
    select_plugins,
    write_settings_json,
)

_TEMPLATES_DIR = Path(__file__).parent / "templates"

# Languages that have a dedicated gitignore fragment. Any other value falls
# back to the default fragment only.
_KNOWN_LANGUAGES: frozenset[str] = frozenset(
    {"python", "typescript", "javascript", "rust", "go"}
)


@dataclass(frozen=True)
class NewProjectSpec:
    """Parsed intent for a new project.

    In PR 1 this is populated from explicit CLI flags. PR 2 adds an
    ``intent.py`` parser that derives it from a natural-language idea.
    """

    name: str                        # human-readable display name
    slug: str                        # directory / repo name (kebab-case)
    description: str                 # 1-line summary for README + gh repo create
    idea: str                        # original idea string
    language: str                    # "python" | "typescript" | ... | "default"
    stack_indicators: tuple[str, ...]  # e.g. ("python", "github-actions")
    extra_plugins: tuple[str, ...] = ()


@dataclass
class GenesisResult:
    path: Path
    plugins: list[str]
    permissions: list[str]
    commit_sha: str | None
    dry_run: bool
    files_written: list[Path] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Name / slug utilities
# ---------------------------------------------------------------------------

_SLUG_STRIP = re.compile(r"[^a-z0-9-]+")
_SLUG_SQUEEZE = re.compile(r"-+")


def slugify(text: str) -> str:
    """Return a kebab-case slug safe for use as a directory and gh repo name.

    Lowercases, replaces whitespace / underscores with dashes, and strips
    any remaining non-``[a-z0-9-]`` characters. Collapses repeated dashes
    and trims leading / trailing dashes.

    >>> slugify("Telegram Chat Bot")
    'telegram-chat-bot'
    >>> slugify("My_App v2!")
    'my-app-v2'
    """
    if not text:
        raise ValueError("slugify() requires a non-empty string")
    lowered = text.strip().lower()
    # Replace whitespace and underscores with dashes before stripping.
    lowered = re.sub(r"[\s_]+", "-", lowered)
    slug = _SLUG_STRIP.sub("", lowered)
    slug = _SLUG_SQUEEZE.sub("-", slug).strip("-")
    if not slug:
        raise ValueError(f"could not derive a slug from {text!r}")
    return slug


# ---------------------------------------------------------------------------
# Template rendering
# ---------------------------------------------------------------------------


def _load_template(name: str) -> str:
    return (_TEMPLATES_DIR / name).read_text(encoding="utf-8")


def _render_template(name: str, /, **vars: str) -> str:
    """Render a ``templates/<name>`` file with ``str.format`` substitutions."""
    return _load_template(name).format(**vars)


def _render_gitignore(language: str) -> str:
    """Compose a .gitignore from the language fragment + default block."""
    parts: list[str] = []
    if language in _KNOWN_LANGUAGES:
        parts.append(_load_template(f"gitignore-{language}.tmpl").rstrip() + "\n")
    parts.append(_load_template("gitignore-default.tmpl").rstrip() + "\n")
    return "\n".join(parts)


def _render_readme(spec: NewProjectSpec) -> str:
    return _render_template(
        "README.md.tmpl",
        name=spec.name,
        description=spec.description,
    )


def _render_prd(spec: NewProjectSpec, *, today: date | None = None) -> str:
    today = today or date.today()
    indicators = ", ".join(spec.stack_indicators) or "(none)"
    return _render_template(
        "prd-0001.md.tmpl",
        name=spec.name,
        idea=spec.idea,
        description=spec.description,
        language=spec.language,
        stack_indicators=indicators,
        initial_date=today.isoformat(),
    )


# ---------------------------------------------------------------------------
# Genesis
# ---------------------------------------------------------------------------


def _run_git(args: list[str], *, cwd: Path) -> subprocess.CompletedProcess:
    """Run a git subcommand, capturing output, raising on non-zero exit.

    Helper so subprocess calls in tests can be mocked in one place.
    """
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )


def create_repo(
    *,
    spec: NewProjectSpec,
    parent_dir: Path,
    dry_run: bool = False,
    commit_message: str | None = None,
) -> GenesisResult:
    """Run the local-genesis pipeline.

    Side effects (unless ``dry_run=True``):

    - Creates ``<parent_dir>/<spec.slug>/``
    - ``git init -b main`` inside it
    - Writes README, .gitignore, docs/prds/0001-project-goal.md,
      .claude/settings.json
    - Stages all tracked files and creates a single initial commit on main
    """
    if not parent_dir.is_dir():
        raise FileNotFoundError(f"parent directory does not exist: {parent_dir}")

    target = parent_dir / spec.slug
    plugins = select_plugins(spec.stack_indicators, extra_plugins=spec.extra_plugins)
    permissions = select_permissions(spec.stack_indicators)

    if dry_run:
        return GenesisResult(
            path=target,
            plugins=plugins,
            permissions=permissions,
            commit_sha=None,
            dry_run=True,
        )

    if target.exists():
        raise FileExistsError(f"target directory already exists: {target}")

    target.mkdir(parents=True)
    _run_git(["init", "-b", "main"], cwd=target)

    files_written: list[Path] = []
    files_written.append(_write(target / "README.md", _render_readme(spec)))
    files_written.append(_write(target / ".gitignore", _render_gitignore(spec.language)))
    prd_path = target / "docs" / "prds" / "0001-project-goal.md"
    files_written.append(_write(prd_path, _render_prd(spec)))
    files_written.append(
        write_settings_json(target, plugins, permissions)
    )

    _run_git(["add", "-A"], cwd=target)
    message = commit_message or f"chore: initialize {spec.slug}"
    _run_git(["commit", "-m", message], cwd=target)
    sha = _run_git(["rev-parse", "HEAD"], cwd=target).stdout.strip()

    return GenesisResult(
        path=target,
        plugins=plugins,
        permissions=permissions,
        commit_sha=sha,
        dry_run=False,
        files_written=files_written,
    )


def _write(path: Path, content: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


# ---------------------------------------------------------------------------
# Remote push (Phase 4)
# ---------------------------------------------------------------------------


def gh_repo_create(
    *,
    repo_path: Path,
    owner: str | None,
    slug: str,
    description: str,
    visibility: str = "private",
) -> str:
    """Run ``gh repo create ... --source=. --push``.

    Returns the created repo's URL on stdout. Raises ``CalledProcessError``
    if ``gh`` is not authenticated or the repo name is already taken.
    """
    target = f"{owner}/{slug}" if owner else slug
    result = subprocess.run(
        [
            "gh", "repo", "create", target,
            "--source", str(repo_path),
            "--push",
            f"--{visibility}",
            "--description", description,
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    # gh prints the HTTPS URL on stdout; may contain trailing whitespace.
    return result.stdout.strip()


def gh_current_user(default: str | None = None) -> str | None:
    """Return the authenticated gh user login, or ``default`` if unauth'd."""
    try:
        result = subprocess.run(
            ["gh", "api", "user", "--jq", ".login"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError):
        return default
    return result.stdout.strip() or default


__all__ = [
    "GenesisResult",
    "NewProjectSpec",
    "create_repo",
    "gh_current_user",
    "gh_repo_create",
    "slugify",
]
