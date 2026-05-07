"""Runtime compiler for SKILL.md files into subagent prompt fragments.

Reads selected plugin skills, strips Claude Code metadata, keeps domain
knowledge sections, and produces combined prompt text for each subagent.
"""

from __future__ import annotations

import re
import sys
from functools import lru_cache
from pathlib import Path

_MODULE_DIR = Path(__file__).resolve().parent  # prompts/
_REPO_ROOT = _MODULE_DIR.parent.parent.parent  # git-repo-agent/
_PLUGINS_ROOT = _REPO_ROOT.parent  # claude-plugins/
_GENERATED_DIR = _MODULE_DIR / "generated"  # Pre-compiled subagent prompts
_GENERATED_SKILLS_DIR = _GENERATED_DIR / "skills"  # Pre-compiled per-skill files


def _plugin_skill_available(skill_relpath: str) -> bool:
    """Return True when ``skill_relpath`` resolves under the monorepo plugins root.

    Live compilation requires sibling plugin checkouts. When ``git-repo-agent``
    is installed standalone (e.g. via ``uv tool install``), ``_PLUGINS_ROOT``
    points at the package's parent directory which does not contain
    ``*-plugin/skills/*/SKILL.md``. In that case the runtime falls back to
    pre-compiled artifacts shipped under ``prompts/generated/``.
    """
    return (_PLUGINS_ROOT / skill_relpath).exists()


def _generated_skill_path(skill_relpath: str) -> Path:
    """Map ``<plugin>/skills/<skill>/SKILL.md`` → ``generated/skills/<plugin>/<skill>.md``."""
    parts = Path(skill_relpath).parts
    if len(parts) >= 4 and parts[1] == "skills" and parts[-1] == "SKILL.md":
        return _GENERATED_SKILLS_DIR / parts[0] / f"{parts[-2]}.md"
    # Fallback: flatten the relpath under the generated tree.
    return _GENERATED_SKILLS_DIR / Path(skill_relpath).with_suffix(".md")

# Subagent → list of skill files (relative to PLUGINS_ROOT).
#
# The `blueprint` subagent is intentionally absent — the blueprint lifecycle is
# now driven by the Python state machine in ``blueprint_driver.py`` (see
# ADR-006), which uses ``get_compiled_skill()`` to load one skill per phase
# instead of bundling them into a single subagent prompt.
SUBAGENT_SKILLS: dict[str, list[str]] = {
    "configure": [
        "configure-plugin/skills/configure-linting/SKILL.md",
        "configure-plugin/skills/configure-formatting/SKILL.md",
        "configure-plugin/skills/configure-tests/SKILL.md",
        "configure-plugin/skills/configure-pre-commit/SKILL.md",
        "configure-plugin/skills/configure-workflows/SKILL.md",
        "configure-plugin/skills/configure-coverage/SKILL.md",
        "configure-plugin/skills/configure-release-please/SKILL.md",
        "configure-plugin/skills/configure-dockerfile/SKILL.md",
        "configure-plugin/skills/configure-sentry/SKILL.md",
    ],
    "diagnose": [
        "kubernetes-plugin/skills/kubectl-debugging/SKILL.md",
        "github-actions-plugin/skills/github-actions-inspection/SKILL.md",
        "code-quality-plugin/skills/debugging-methodology/SKILL.md",
    ],
    "docs": [
        "configure-plugin/skills/configure-readme/SKILL.md",
        "blueprint-plugin/skills/blueprint-claude-md/SKILL.md",
        "blueprint-plugin/skills/blueprint-docs-list/SKILL.md",
        "blueprint-plugin/skills/blueprint-curate-docs/SKILL.md",
        "code-quality-plugin/skills/code-docs-quality/SKILL.md",
    ],
    "quality": [
        "code-quality-plugin/skills/code-review-checklist/SKILL.md",
        "code-quality-plugin/skills/code-antipatterns-analysis/SKILL.md",
        "code-quality-plugin/skills/code-lint/SKILL.md",
        "code-quality-plugin/skills/dry-consolidation/SKILL.md",
        "code-quality-plugin/skills/code-silent-degradation/SKILL.md",
        "code-quality-plugin/skills/code-lint-fix/SKILL.md",
    ],
    "security": [
        "git-plugin/skills/git-security-checks/SKILL.md",
        "configure-plugin/skills/configure-security/SKILL.md",
        "github-actions-plugin/skills/github-actions-auth-security/SKILL.md",
    ],
    "test_runner": [
        "testing-plugin/skills/test-run/SKILL.md",
        "testing-plugin/skills/test-report/SKILL.md",
        "testing-plugin/skills/test-tier-selection/SKILL.md",
        "testing-plugin/skills/test-analyze/SKILL.md",
        "testing-plugin/skills/test-quality-analysis/SKILL.md",
    ],
}

# Sections to KEEP (domain knowledge)
KEEP_HEADINGS = {
    "core expertise",
    "execution",
    "key capabilities",
    "essential syntax",
    "common patterns",
    "error handling",
    "best practices",
    "standard recipes",
    "critical guidelines",
    "steps",
}

# Sections to DROP (Claude Code metadata)
DROP_HEADINGS = {
    "when to use",
    "when to use this skill",
    "context",
    "parameters",
    "agentic optimizations",
    "flags",
    "see also",
    "quick reference",
}

FRONTMATTER_RE = re.compile(r"\A---\n.*?^---\n", re.MULTILINE | re.DOTALL)


def strip_frontmatter(content: str) -> str:
    """Remove YAML frontmatter between --- markers."""
    return FRONTMATTER_RE.sub("", content, count=1)


def parse_sections(content: str) -> list[tuple[str, str, str]]:
    """Parse markdown into (heading_text, heading_level_marker, body) tuples.

    Returns a list where each element is a section. The first element may have
    an empty heading (content before the first heading).
    """
    sections: list[tuple[str, str, str]] = []
    current_heading = ""
    current_marker = ""
    current_lines: list[str] = []

    for line in content.splitlines(keepends=True):
        heading_match = re.match(r"^(#{1,3})\s+(.+?)(\s*#*)?\s*$", line)
        if heading_match:
            # Save previous section
            sections.append((current_heading, current_marker, "".join(current_lines)))
            current_marker = heading_match.group(1)
            current_heading = heading_match.group(2).strip()
            current_lines = []
        else:
            current_lines.append(line)

    sections.append((current_heading, current_marker, "".join(current_lines)))
    return sections


def filter_sections(sections: list[tuple[str, str, str]]) -> str:
    """Keep domain-knowledge sections, drop Claude Code metadata."""
    output_parts: list[str] = []

    for heading, marker, body in sections:
        heading_lower = heading.lower().rstrip(".")

        # Always keep content before first heading (intro text)
        if not heading:
            intro = body.strip()
            if intro:
                output_parts.append(intro)
            continue

        # Drop explicitly excluded sections
        if heading_lower in DROP_HEADINGS:
            continue

        # Keep explicitly included sections or anything not in drop list
        if heading_lower in KEEP_HEADINGS or heading_lower not in DROP_HEADINGS:
            output_parts.append(f"{marker} {heading}\n{body}")

    return "\n".join(output_parts)


def transform_references(content: str) -> str:
    """Replace AskUserQuestion references with orchestrator reporting."""
    content = re.sub(
        r"(?i)\bAskUserQuestion\b",
        "report to orchestrator",
        content,
    )
    content = re.sub(
        r"(?i)\bask\s+the\s+user\b",
        "report to the orchestrator",
        content,
    )
    return content


def resolve_reference_md(content: str, skill_dir: Path) -> str:
    """Inline REFERENCE.md content where linked."""
    ref_path = skill_dir / "REFERENCE.md"
    if not ref_path.exists():
        return content

    ref_content = ref_path.read_text(encoding="utf-8")
    ref_content = strip_frontmatter(ref_content)

    # Replace markdown links to REFERENCE.md with inline content
    pattern = r"\[.*?\]\(REFERENCE\.md\)"
    if re.search(pattern, content):
        content = re.sub(pattern, "", content)
        content = content.rstrip() + "\n\n" + ref_content.strip() + "\n"

    return content


def compile_skill(skill_path: Path) -> str:
    """Compile a single skill file into a prompt fragment."""
    content = skill_path.read_text(encoding="utf-8")
    content = strip_frontmatter(content)
    content = resolve_reference_md(content, skill_path.parent)
    sections = parse_sections(content)
    content = filter_sections(sections)
    content = transform_references(content)
    return content.strip()


def compile_subagent(name: str, skill_paths: list[str]) -> str:
    """Compile all skills for a subagent into a combined prompt."""
    fragments: list[str] = []

    for rel_path in skill_paths:
        skill_path = _PLUGINS_ROOT / rel_path
        if not skill_path.exists():
            print(f"  WARNING: {rel_path} not found, skipping", file=sys.stderr)
            continue

        fragment = compile_skill(skill_path)
        if fragment:
            skill_name = skill_path.parent.name
            fragments.append(f"## {skill_name}\n\n{fragment}")

    return "\n\n---\n\n".join(fragments) + "\n"


@lru_cache(maxsize=None)
def get_compiled_prompt(subagent_name: str) -> str:
    """Get compiled prompt for a subagent, with caching.

    Live compiles from sibling plugin checkouts when present (monorepo dev
    mode); otherwise falls back to the pre-compiled artifact under
    ``prompts/generated/<subagent>_skills.md`` shipped with the package
    (standalone install mode). Returns an empty string if the subagent has
    no configured skills, no sources, and no pre-compiled fallback.
    """
    skill_paths = SUBAGENT_SKILLS.get(subagent_name)
    if not skill_paths:
        return ""
    if any(_plugin_skill_available(p) for p in skill_paths):
        return compile_subagent(subagent_name, skill_paths)
    fallback = _GENERATED_DIR / f"{subagent_name}_skills.md"
    if fallback.exists():
        return fallback.read_text(encoding="utf-8")
    return ""


@lru_cache(maxsize=None)
def get_compiled_skill(skill_relpath: str) -> str:
    """Compile a single skill file into a prompt fragment.

    ``skill_relpath`` is relative to the plugins root, e.g.
    ``"blueprint-plugin/skills/blueprint-init/SKILL.md"``. Returns the
    stripped, filtered skill body (frontmatter removed, Claude Code
    metadata sections dropped, ``AskUserQuestion`` references rewritten
    to orchestrator-reporting). Used by the blueprint state machine
    driver to load exactly one skill per LLM call rather than bundling
    many skills into one subagent prompt.

    Raises FileNotFoundError if the skill does not exist in either the
    monorepo plugin tree or the package's pre-compiled ``generated/skills/``
    directory (standalone install mode).
    """
    skill_path = _PLUGINS_ROOT / skill_relpath
    if skill_path.exists():
        return compile_skill(skill_path)
    fallback = _generated_skill_path(skill_relpath)
    if fallback.exists():
        return fallback.read_text(encoding="utf-8")
    raise FileNotFoundError(f"Skill not found: {skill_relpath}")
