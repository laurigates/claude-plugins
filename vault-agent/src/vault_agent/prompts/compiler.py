"""Runtime compiler for SKILL.md files into subagent prompt fragments.

Reads selected obsidian-plugin skills, strips Claude Code metadata, keeps
domain knowledge sections, and produces combined prompt text for each
vault-agent subagent. Same pattern as git-repo-agent's compiler.
"""

from __future__ import annotations

import re
import sys
from functools import lru_cache
from pathlib import Path

_MODULE_DIR = Path(__file__).resolve().parent  # prompts/
_REPO_ROOT = _MODULE_DIR.parent.parent.parent  # vault-agent/
_PLUGINS_ROOT = _REPO_ROOT.parent  # claude-plugins/
_GENERATED_DIR = _MODULE_DIR / "generated"  # Pre-compiled subagent prompts
_GENERATED_SKILLS_DIR = _GENERATED_DIR / "skills"  # Pre-compiled per-skill files


def _plugin_skill_available(skill_relpath: str) -> bool:
    """Return True when ``skill_relpath`` resolves under the monorepo plugins root.

    Live compilation requires sibling plugin checkouts. When ``vault-agent``
    is installed standalone (e.g. via ``uv tool install``), ``_PLUGINS_ROOT``
    points at the package's parent directory which does not contain
    ``obsidian-plugin/skills/*/SKILL.md``. In that case the runtime falls back
    to pre-compiled artifacts shipped under ``prompts/generated/``.
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
# All vault maintenance skills live under the existing obsidian-plugin
# (alongside the CLI-operation skills: vault-files, properties, etc.).
SUBAGENT_SKILLS: dict[str, list[str]] = {
    "vault-lint": [
        "obsidian-plugin/skills/vault-frontmatter/SKILL.md",
        "obsidian-plugin/skills/vault-tags/SKILL.md",
        "obsidian-plugin/skills/vault-templates/SKILL.md",
    ],
    "vault-links": [
        "obsidian-plugin/skills/vault-wikilinks/SKILL.md",
        "obsidian-plugin/skills/vault-orphans/SKILL.md",
    ],
    "vault-stubs": [
        "obsidian-plugin/skills/vault-stubs/SKILL.md",
        "obsidian-plugin/skills/vault-frontmatter/SKILL.md",
    ],
    "vault-mocs": [
        "obsidian-plugin/skills/vault-mocs/SKILL.md",
        "obsidian-plugin/skills/vault-tags/SKILL.md",
        "obsidian-plugin/skills/vault-orphans/SKILL.md",
    ],
}

# Sections to KEEP (domain knowledge). Everything NOT in DROP is kept by
# default — this is the explicit allow-list for any section name we
# especially want to preserve.
KEEP_HEADINGS = {
    "canonical frontmatter shape",
    "canonical redirect stub format",
    "canonical moc shape",
    "canonical categories",
    "consolidation table",
    "classifications (from vault-agent's stubs analyzer)",
    "common breakage patterns",
    "core operations",
    "detection",
    "detection patterns",
    "edit pattern",
    "edit recipes",
    "legacy moc fixups",
    "resolution rules",
    "rewriting strategy",
    "safety",
    "triage workflow",
    "unrendered markers",
}

# Sections to DROP (Claude Code metadata / how-to-use-this-skill stuff).
DROP_HEADINGS = {
    "when to use",
    "when to use this skill",
    "prerequisites",
    "context",
    "parameters",
    "agentic optimizations",
    "flags",
    "see also",
    "quick reference",
    "related skills",
}

FRONTMATTER_RE = re.compile(r"\A---\n.*?^---\n", re.MULTILINE | re.DOTALL)


def strip_frontmatter(content: str) -> str:
    """Remove YAML frontmatter between --- markers."""
    return FRONTMATTER_RE.sub("", content, count=1)


def parse_sections(content: str) -> list[tuple[str, str, str]]:
    """Parse markdown into (heading, level_marker, body) triples.

    The first triple may have an empty heading — that's the intro text
    before any heading. Level marker is the literal ``#`` / ``##`` / ``###``.
    """
    sections: list[tuple[str, str, str]] = []
    current_heading = ""
    current_marker = ""
    current_lines: list[str] = []

    for line in content.splitlines(keepends=True):
        heading_match = re.match(r"^(#{1,3})\s+(.+?)(\s*#*)?\s*$", line)
        if heading_match:
            sections.append((current_heading, current_marker, "".join(current_lines)))
            current_marker = heading_match.group(1)
            current_heading = heading_match.group(2).strip()
            current_lines = []
        else:
            current_lines.append(line)

    sections.append((current_heading, current_marker, "".join(current_lines)))
    return sections


def filter_sections(sections: list[tuple[str, str, str]]) -> str:
    """Keep domain-knowledge sections, drop metadata sections."""
    parts: list[str] = []

    for heading, marker, body in sections:
        heading_lower = heading.lower().rstrip(".")

        # Intro (before first heading)
        if not heading:
            intro = body.strip()
            if intro:
                parts.append(intro)
            continue

        if heading_lower in DROP_HEADINGS:
            continue
        # Default: keep everything not explicitly dropped
        parts.append(f"{marker} {heading}\n{body}")

    return "\n".join(parts)


def transform_references(content: str) -> str:
    """Rewrite ``AskUserQuestion`` / "ask the user" to orchestrator-reporting.

    Inside a subagent these phrases are meaningless — the subagent talks to
    the orchestrator, not to the user directly.
    """
    content = re.sub(r"(?i)\bAskUserQuestion\b", "report to orchestrator", content)
    content = re.sub(r"(?i)\bask\s+the\s+user\b", "report to the orchestrator", content)
    return content


def compile_skill(skill_path: Path) -> str:
    """Compile one SKILL.md into a prompt fragment."""
    content = skill_path.read_text(encoding="utf-8")
    content = strip_frontmatter(content)
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
    """Return the compiled skill bundle for a subagent (cached).

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
    """Compile a single skill file (cached).

    ``skill_relpath`` is relative to the plugins root, e.g.
    ``"obsidian-plugin/skills/vault-frontmatter/SKILL.md"``. Live-compiles
    from the monorepo plugin tree when present (dev mode); otherwise reads
    the pre-compiled artifact under ``prompts/generated/skills/<plugin>/<skill>.md``
    (standalone install mode). Useful for phased drivers that run one skill
    per LLM call.

    Raises FileNotFoundError if the skill does not exist in either the
    monorepo plugin tree or the package's pre-compiled ``generated/skills/``
    directory.
    """
    skill_path = _PLUGINS_ROOT / skill_relpath
    if skill_path.exists():
        return compile_skill(skill_path)
    fallback = _generated_skill_path(skill_relpath)
    if fallback.exists():
        return fallback.read_text(encoding="utf-8")
    raise FileNotFoundError(f"Skill not found: {skill_relpath}")
